//
//  ContentView.swift
//  Projekt Krása
//
//  Minimální UI fáze 1: otevřít klip, přehrát, krokovat, změřit.
//  Žádná timeline, žádné panely — to je fáze 2.
//

import AVFoundation
import AppKit
import Combine
import SwiftUI
import TimelineModel

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Vyber klip nebo složku s klipy."
    @Published var clips: [ClipTiming] = []
    @Published var selected: ClipTiming?
    @Published var isMeasuring = false
    @Published var reportLines: [String] = []
    /// Skrývá sidebar a transport, aby přehrávač dostal celou plochu.
    /// Bez toho by „fullscreen" znamenal dvě třetiny obrazovky vedle sidebaru.
    @Published var chromeHidden = false

    let importer = MediaImporter()
    let controller = PlaybackController()
    /// Generátor a evidence proxy (fáze 4).
    let proxies = ProxyStore()
    /// Stav časové osy. Žije v modelu, ne ve view — `TimelinePaneView` se
    /// smí kdykoli přetvořit, `TimelineController` to nesmí pocítit.
    let timeline = TimelineController()
    private(set) var hostView: PlayerHostView?
    /// Pane osy — jen pro výkonový test, který potřebuje scroll view.
    private(set) weak var timelinePane: TimelinePane?
    /// Výkonový test osy staví projekt s 2000 klipy — kompozice z něj by se
    /// stavěla desítky sekund a s měřením scrollu nesouvisí.
    private var skipsCompositionRebuild = false

    /// Pauza mezi běhy. Air je bezventilátorový — bez chladnutí měří druhý
    /// běh teplejší stroj, ne jiný stav.
    static let coolDownSeconds: UInt64 = 20

    /// Co má přehrávač v ruce: celou osu (kompozici), nebo sólo klip
    /// vybraný v sidebaru (kvůli poslechu zdroje a benchmarkům).
    enum PlayerContent { case timeline, solo }
    private(set) var playerContent: PlayerContent = .solo

    /// Kompozice postavená z aktuálního projektu (fáze 3, modul 1).
    private var timelineComposition: AVMutableComposition?
    private var compositionRebuild: Task<Void, Never>?
    private var subscriptions: [AnyCancellable] = []

    init() {
        // Osa → přehrávač: uživatel posunul hlavu, přehrávač skočí.
        timeline.onUserSeek = { [weak self] frame in
            self?.seekPlayer(toTimelineFrame: frame)
        }
        subscriptions = [
            // Přehrávač → osa: při přehrávání jede hlava za časem přehrávače.
            // Smyčce brání dvojí pojistka: `isUserScrubbing` během tažení
            // a `isPlaying` — hlava se veze jen za běžícím přehráváním.
            controller.$currentTime
                .receive(on: DispatchQueue.main)
                .sink { [weak self] time in self?.syncPlayhead(from: time) },
            // Každá změna projektu (import, střih, undo) přestaví kompozici.
            // Debounce: tažení sype změny po commitech, přestavba za 250 ms
            // po poslední z nich stačí a nebuduje se nadarmo.
            timeline.$project
                .removeDuplicates()
                .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.rebuildTimelineComposition() },
            // Proxy se k assetům přišívají znovu po KAŽDÉ změně projektu:
            // undo vrací snapshoty z doby, kdy proxy ještě neexistovaly,
            // a bez tohohle by ⌘Z tiše přepnul přehrávání na originály.
            // Smyčka nehrozí — `setProxy` při shodě nezapisuje.
            timeline.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reapplyKnownProxies() },
        ]
    }

    private func reapplyKnownProxies() {
        for (original, proxy) in proxies.finished {
            timeline.setProxy(proxy, forAssetWithOriginal: original)
        }
    }

    // MARK: Správa proxy úložiště (fáze 4)

    /// Kritérium plánu: „proxy jde vygenerovat na externí disk."
    func changeProxyDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ukládat proxy sem"
        panel.message = "Vyber složku pro proxy — klidně na externím disku. "
            + "Stávající proxy se vygenerují znovu do nového umístění."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        timeline.clearAssetProxies()      // nejdřív odšít, pak měnit úložiště
        proxies.chooseDirectory(url)
        regenerateProxies()
    }

    func deleteProxies() {
        timeline.clearAssetProxies()      // kompozice nesmí ukazovat na mazané soubory
        proxies.deleteAll()
    }

    private func regenerateProxies() {
        let scanned = clips
        guard !scanned.isEmpty else { return }
        Task { [weak self] in
            await self?.proxies.ensureProxies(for: scanned) { original, proxy in
                self?.timeline.setProxy(proxy, forAssetWithOriginal: original)
            }
        }
    }

    func attach(_ view: PlayerHostView) { hostView = view }
    func attachTimeline(_ pane: TimelinePane) { timelinePane = pane }

    // MARK: Import

    func openFiles(directories: Bool) async {
        let urls = importer.promptForAccess(directories: directories)
        guard !urls.isEmpty else { return }
        await ingest(urls: urls)
    }

    func restoreAndScan() async {
        let urls = importer.restoreRememberedAccess()
        guard !urls.isEmpty else { return }
        await ingest(urls: urls)
    }

    private func ingest(urls: [URL]) async {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                files.append(contentsOf: importer.videoFiles(in: url))
            } else {
                files.append(url)
            }
        }

        status = "Měřím časování \(files.count) klipů…"
        var found: [ClipTiming] = []
        for file in files {
            switch await VFRDetector.inspect(url: file) {
            case .success(let timing): found.append(timing)
            case .failure(let error):
                status = "\(file.lastPathComponent): \(error.localizedDescription)"
            }
        }
        clips = found.sorted { $0.name < $1.name }
        timeline.loadScannedClips(clips)
        status = "\(clips.count) klipů. Vyber jeden a přehraj, nebo spusť měření."
        if selected == nil, let first = clips.first { await select(first) }

        // Proxy na pozadí — ale ne pod CLI měřeními, soupeřily by o stroj.
        if !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            let scanned = clips
            Task { [weak self] in
                await self?.proxies.ensureProxies(for: scanned) { original, proxy in
                    self?.timeline.setProxy(proxy, forAssetWithOriginal: original)
                }
            }
        }
    }

    /// Sólo poslech zdroje z sidebaru — kvůli kontrole klipu a benchmarkům.
    /// Zpátky na osu se přehrávač přepne klikem do pravítka.
    func select(_ clip: ClipTiming) async {
        selected = clip
        playerContent = .solo
        try? await controller.load(url: clip.url, measuredFrameRate: clip.measuredFrameRate)
    }

    // MARK: Přehrávání osy (fáze 3, modul 1)

    /// Přestaví kompozici z aktuálního projektu a dá ji přehrávači.
    /// Od fáze 3 je tohle výchozí obsah přehrávače — hlava, klik do
    /// pravítka i mezerník jedou nad CELOU osou, ne nad jedním souborem.
    private func rebuildTimelineComposition() {
        guard !skipsCompositionRebuild else { return }
        compositionRebuild?.cancel()
        let project = timeline.project
        compositionRebuild = Task { [weak self] in
            guard let composition = try? await CompositionBuilder.build(
                    project: project, usingProxies: project.usesProxies),
                  let self, !Task.isCancelled else { return }
            let frameRate = project.timeline.frameRate
            self.timelineComposition = composition
            self.playerContent = .timeline
            self.controller.loadComposition(composition, frameRate: frameRate)
            self.controller.seek(to: CompositionBuilder.time(of: self.timeline.playhead,
                                                             frameRate: frameRate))
        }
    }

    // MARK: Hlava osy ↔ přehrávač (krok 6, od fáze 3 nad kompozicí)

    /// Osa → přehrávač: snímek osy JE čas kompozice, žádné hledání klipu.
    /// Mapování klip → zdroj dělá kompozice sama — postavil ji model.
    private func seekPlayer(toTimelineFrame frame: Frames) {
        let frameRate = timeline.project.timeline.frameRate
        if playerContent != .timeline {
            guard let composition = timelineComposition else { return }
            playerContent = .timeline
            controller.loadComposition(composition, frameRate: frameRate)
        }
        controller.seek(to: CompositionBuilder.time(of: frame, frameRate: frameRate))
    }

    /// Přehrávač → osa. Jen při přehrávání kompozice — sólo klip má vlastní
    /// časovou osu souboru a s osou projektu nesouvisí.
    private func syncPlayhead(from time: CMTime) {
        guard playerContent == .timeline,
              controller.isPlaying,
              !timeline.isUserScrubbing,
              time.isValid else { return }
        timeline.setPlayheadFromPlayback(
            CompositionBuilder.frame(of: time, frameRate: timeline.project.timeline.frameRate))
    }

    // MARK: Měření — společné

    /// Čeká, až bude přehrávač v okně. Display link se rozjede až tam,
    /// takže dřív by se měřilo do prázdna.
    private func waitForPlayerWindow(timeout: TimeInterval = 10) async -> PlayerHostView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let view = hostView, view.window != nil { return view }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    /// Čerstvá dvojice view + okno. Po přechodu na fullscreen může SwiftUI
    /// `NSViewRepresentable` přetvořit; držet si starý odkaz by znamenalo
    /// měřit view bez okna, tedy nula tiků vydaných za „fullscreen bolí".
    private func currentHost() async -> (view: PlayerHostView, window: NSWindow)? {
        guard let view = await waitForPlayerWindow(timeout: 5), let window = view.window else {
            return nil
        }
        return (view, window)
    }

    /// Prázdný seznam cest = všechny načtené klipy.
    /// Cesty musí ležet uvnitř složky, na kterou máme bookmark.
    private func resolveTargets(_ paths: [String]) async -> [ClipTiming] {
        guard !paths.isEmpty else { return clips }
        var targets: [ClipTiming] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            switch await VFRDetector.inspect(url: url) {
            case .success(let timing): targets.append(timing)
            case .failure(let error):
                status = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        return targets
    }

    private func coolDown() async {
        status = "Chladnu mezi běhy…"
        try? await Task.sleep(nanoseconds: Self.coolDownSeconds * 1_000_000_000)
    }

    // MARK: Měření v okně

    /// Změří konkrétní soubory v okně. Prázdný seznam = všechny načtené klipy.
    func runBenchmark(only paths: [String] = []) async {
        guard let hostView = await waitForPlayerWindow() else {
            status = "Přehrávač se nedostal do okna, měření by měřilo prázdno."
            return
        }

        let targets = await resolveTargets(paths)
        guard !targets.isEmpty else {
            status = "Není co měřit."
            return
        }

        isMeasuring = true
        reportLines = []
        defer { isMeasuring = false }

        var lines: [String] = ["═══ MĚŘENÍ NÁHLEDU ═══", ""]
        for clip in targets {
            status = "Měřím \(clip.name)…"
            let benchmark = PlaybackBenchmark()
            var result = await benchmark.run(url: clip.url, timing: clip,
                                             controller: controller, hostView: hostView)
            result.codec = describeCodec(clip)
            lines.append(contentsOf: result.report)
            lines.append("")

            // Mezi běhy pauza, ať se stroj vrátí blíž k výchozí teplotě.
            // Bez toho druhý běh měří teplejší Air, ne pomalejší kodek.
            if clip.url != targets.last?.url { await coolDown() }
        }
        reportLines = lines
        status = "Hotovo."
        writeReport(lines, to: "KrasaBenchmark.txt")
        for line in lines { print(line) }
    }

    // MARK: Měření okno vs celá obrazovka

    /// Změří tentýž klip v okně a na celé obrazovce.
    ///
    /// Kola jsou dvě a v zrcadlovém pořadí (ABBA). Jedno pořadí by nestačilo:
    /// druhý stav by vždycky běžel na teplejším stroji a rozdíl by se dal
    /// vyložit jako vliv plochy, i kdyby to byla jen teplota. Před prvním
    /// kolem se pouští zahazovaný zahřívací běh — jinak by pozice 1 měřila
    /// studený stroj se studenou souborovou cache.
    ///
    /// Na jeden klip to je asi 4 minuty, proto se to pouští na vybraný klip.
    func runFullScreenComparison(only paths: [String] = []) async {
        guard var host = await currentHost() else {
            status = "Přehrávač nemá okno, není co přepnout na celou obrazovku."
            return
        }

        var targets = await resolveTargets(paths)
        if paths.isEmpty, let selected { targets = [selected] }
        guard !targets.isEmpty else {
            status = "Není co měřit."
            return
        }

        isMeasuring = true
        reportLines = []
        chromeHidden = true
        defer {
            isMeasuring = false
            chromeHidden = false
        }

        // Po skrytí sidebaru musí SwiftUI přelayoutovat a vrstva se natáhnout.
        try? await Task.sleep(nanoseconds: 800_000_000)

        var lines: [String] = ["═══ NÁHLED: OKNO vs CELÁ OBRAZOVKA ═══", ""]

        for clip in targets {
            // Zahřívací běh. Výsledek se zahazuje — jde jen o to, aby první
            // měřený stav neběžel na studeném stroji a studené cache.
            status = "Zahřívám na \(clip.name)… (výsledek se zahodí)"
            _ = await PlaybackBenchmark().run(url: clip.url, timing: clip,
                                              controller: controller, hostView: host.view)
            await coolDown()

            var rounds: [ComparisonRound] = []

            for roundIndex in 0..<2 {
                let windowedFirst = roundIndex == 0
                var windowed: BenchmarkResult?
                var fullScreen: BenchmarkResult?

                for step in 0..<2 {
                    let wantFullScreen = windowedFirst ? step == 1 : step == 0
                    let place = wantFullScreen ? "celá obrazovka" : "okno"

                    let areaBefore = host.view.videoBackingPixelSize
                    // Dvě ze čtyř přepnutí jsou no-op (kolo končí ve stavu,
                    // kterým další začíná). Bez tohohle příznaku by se u nich
                    // hlásilo, že se plocha nezměnila — a varování určené pro
                    // skutečný problém by se utopilo ve vlastním šumu.
                    let didSwitch = FullScreenSwitch.isFullScreen(host.window) != wantFullScreen

                    guard await FullScreenSwitch.set(wantFullScreen, on: host.window) else {
                        status = "Přechod na \(place) se nestihl — měření zastaveno."
                        await FullScreenSwitch.set(false, on: host.window)
                        reportLines = lines
                        return
                    }

                    // Po přechodu si vyzvednout view i okno znovu.
                    guard let refreshed = await currentHost() else {
                        status = "Po přechodu na \(place) se ztratil přehrávač — měření zastaveno."
                        // Okno by jinak zůstalo na celé obrazovce bez sidebaru
                        // a bez tlačítek. Starý odkaz je pořád platný.
                        await FullScreenSwitch.set(false, on: host.window)
                        reportLines = lines
                        return
                    }
                    host = refreshed

                    let areaAfter = host.view.videoBackingPixelSize
                    if didSwitch, areaBefore == areaAfter {
                        lines.append("⚠️ Přechod na \(place) plochu obrazu nezměnil"
                                   + " (\(Int(areaAfter.width))×\(Int(areaAfter.height)) px)."
                                   + " Srovnání bude nejspíš neprůkazné.")
                    }

                    status = "Měřím \(clip.name) — \(place), kolo \(roundIndex + 1) ze 2…"
                    let benchmark = PlaybackBenchmark()
                    var result = await benchmark.run(url: clip.url, timing: clip,
                                                     controller: controller, hostView: host.view)
                    result.codec = describeCodec(clip)
                    if wantFullScreen { fullScreen = result } else { windowed = result }

                    await coolDown()
                }

                if let windowed, let fullScreen {
                    rounds.append(ComparisonRound(windowed: windowed,
                                                  fullScreen: fullScreen,
                                                  windowedFirst: windowedFirst))
                }
            }

            await FullScreenSwitch.set(false, on: host.window)
            if let refreshed = await currentHost() { host = refreshed }

            let comparison = FullScreenComparison(clipName: clip.name, rounds: rounds)
            lines.append(contentsOf: comparison.report)
            lines.append("")
        }

        reportLines = lines
        status = "Hotovo."
        writeReport(lines, to: "KrasaFullScreen.txt")
        for line in lines { print(line) }
    }

    // MARK: Výkonový test osy (kritérium fáze 2)

    /// 1000 dvojic obraz+zvuk (2000 klipů), scroll přes celou osu tam
    /// a zpět, počítání vypadlých tiků. Detaily v `TimelineScrollBenchmark`.
    func runTimelineStressBench(pairs: Int = 1000) async {
        guard !clips.isEmpty else {
            status = "Nejsou naskenované klipy — není z čeho stavět zátěžový projekt."
            return
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        status = "Stavím zátěžový projekt (\(pairs) dvojic klipů)…"
        timeline.loadStressProject(from: clips, pairs: pairs)

        // Zoom tak, aby se celá osa dala projet za dobu testu se slušnou
        // hustotou klipů na obrazovce (~40 000 bodů dokumentu).
        let totalFrames = max(1, timeline.project.duration.count)
        var geometry = timeline.geometry
        geometry.setZoom(40_000 / Double(totalFrames))
        timeline.geometry = geometry

        NSApp.activate(ignoringOtherApps: true)

        let deadline = Date().addingTimeInterval(10)
        while timelinePane?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let pane = timelinePane, let window = pane.window else {
            status = "Osa se nedostala do okna, není co scrollovat."
            return
        }
        // Okno musí být VIDĚT: zakryté okno pozastaví display link a měření
        // by viselo na prvním tiku. Stejná třída pasti jako u měření náhledu.
        window.makeKeyAndOrderFront(nil)

        // Usadit layout a nechat doběhnout první vlnu výpočtu špiček.
        status = "Čekám na usazení osy…"
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        isMeasuring = true
        defer { isMeasuring = false }
        status = "Scrolluju přes celou osu…"

        let clipCount = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        let bench = TimelineScrollBenchmark(pane: pane, clipCount: clipCount)
        let result = await bench.run()

        reportLines = result.report
        status = "Hotovo."
        writeReport(result.report, to: "KrasaTimelineBench.txt")
        for line in result.report { print(line) }
    }

    private func describeCodec(_ clip: ClipTiming) -> String {
        clip.isVariable ? "VFR zdroj" : "CFR zdroj"
    }

    private func writeReport(_ lines: [String], to fileName: String) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first
        guard let url = directory?.appendingPathComponent(fileName) else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("Report zapsán do \(url.path)")
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        fullLayout
    }

    private var fullLayout: some View {
        HSplitView {
            sidebar
                .frame(minWidth: model.chromeHidden ? 0 : 260,
                       idealWidth: model.chromeHidden ? 0 : 300,
                       maxWidth: model.chromeHidden ? 0 : 420)
                .opacity(model.chromeHidden ? 0 : 1)
            playerPane
                .frame(minWidth: model.chromeHidden ? 0 : 640)
        }
        .frame(minWidth: model.chromeHidden ? 0 : 1000, minHeight: 640)
        .task {
            await model.restoreAndScan()
            // Bez GUI: `--benchmark [cesty…]` změří v okně,
            // `--fullscreen [cesty…]` porovná okno s celou obrazovkou.
            // Sandbox drží, přístup se obnovuje z uloženého bookmarku.
            let arguments = CommandLine.arguments.dropFirst()
            let explicit = arguments.filter { !$0.hasPrefix("--") }
            if arguments.contains("--fullscreen") {
                await model.runFullScreenComparison(only: Array(explicit))
                NSApplication.shared.terminate(nil)
            } else if arguments.contains("--benchmark") {
                await model.runBenchmark(only: Array(explicit))
                NSApplication.shared.terminate(nil)
            } else if arguments.contains("--timeline-bench") {
                await model.runTimelineStressBench()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Vybraný klip drží `AppModel`, ne `@State` ve view.
    ///
    /// Jedno úložiště, žádná synchronizace — stejný důvod, proč geometrii
    /// osy vlastní `TimelineController`. Se dvěma kopiemi by se po přetvoření
    /// view rozešel zvýrazněný řádek od klipu načteného v přehrávači.
    private var clipSelection: Binding<URL?> {
        Binding(
            get: { model.selected?.url },
            set: { url in
                guard let url,
                      let clip = model.clips.first(where: { $0.url == url }),
                      clip.url != model.selected?.url else { return }
                Task { await model.select(clip) }
            })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Otevřít soubor") { Task { await model.openFiles(directories: false) } }
                Button("Otevřít složku") { Task { await model.openFiles(directories: true) } }
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⚠️ Výběr přes `selection:`, NE přes `.onTapGesture` na řádku.
            //
            // Na macOS stojí `List` nad `NSTableView` a ten si myš bere na
            // vlastní výběr — gesto uvnitř řádku se pak nespustí a klik na
            // klip nedělá nic. Na iOSu tentýž kód funguje, takže se ta chyba
            // snadno napíše a těžko všimne. Odhaleno 27. 07. 2026, ale je
            // v projektu od fáze 1: dokud se první klip vybíral sám, nebylo
            // poznat, že ručně vybrat nejde.
            //
            // Vedlejší zisk: `selection:` zvýrazní vybraný řádek. Předtím
            // nešlo poznat, který klip je v přehrávači načtený.
            List(model.clips, id: \.url, selection: clipSelection) { clip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.name).font(.system(.body, design: .monospaced))
                    Text("\(clip.verdict.shortLabel) · \(String(format: "%.2f", clip.measuredFrameRate)) fps"
                         + (clip.droppedFrames > 0 ? " · \(clip.droppedFrames) zahozených" : ""))
                        .font(.caption)
                        .foregroundStyle(clip.isVariable ? .orange : .secondary)
                }
            }

            ProxyControls(timeline: model.timeline, proxies: model.proxies,
                          onChangeLocation: { model.changeProxyDirectory() },
                          onDelete: { model.deleteProxies() })

            Button(model.isMeasuring ? "Měřím…" : "Změřit náhled v okně") {
                Task { await model.runBenchmark() }
            }
            .disabled(model.isMeasuring || model.clips.isEmpty)

            Button(model.isMeasuring ? "Měřím…" : "Okno vs celá obrazovka") {
                Task { await model.runFullScreenComparison() }
            }
            .disabled(model.isMeasuring || model.selected == nil)

            Text(verbatim: """
                Srovnání běží na vybraném klipu: zahřívací běh a pak dvě kola v opačném \
                pořadí. Počítej asi 4 minuty.

                ⚠️ Po spuštění se aplikace nesmí dostat na pozadí ani na jiný Space. \
                Když okno není vidět, systém ho přestane skládat, měření vyjde jako \
                dokonalé a přitom neměřilo nic. Klikni na tlačítko a nech myš i \
                klávesnici být.

                Před spuštěním zmenši okno, ať je co porovnávat. A pusť vedle v Terminálu:
                sudo powermetrics --samplers gpu_power,cpu_power -i 1000 > ~/krasa_gpu.txt
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
                // Pevná šířka: při skrytém sidebaru se rámec smrskne na nulu
                // a text bez tohohle by se zalomil na jedno slovo na řádek,
                // čímž by natáhl výšku celého HSplitView na tisíce bodů.
                .frame(width: 276, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !model.reportLines.isEmpty {
                ScrollView {
                    Text(model.reportLines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160)
            }
        }
        .padding(12)
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            PlayerView(player: model.controller.player) { view in
                model.attach(view)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 🚩 Při měření náhledu se osa z hierarchie ODSTRANÍ, ne jen skryje.
            //
            // Dva důvody, každý sám o sobě dostatečný. Za prvé: timeline je
            // první věc v projektu, nad kterou musí WindowServer něco skládat,
            // a čísla z fáze 1 jsou naměřená bez ní — nechat ji na obrazovce
            // znamená měřit něco jiného a tvrdit, že je to totéž. Za druhé:
            // skrývání přes nulový rámec už jednou natáhlo layout na 4398
            // bodů a měření to nepoznalo (27. 07. 2026). `if` tuhle past
            // obchází celou; stav osy přežije v `AppModelu`.
            if !model.chromeHidden {
                Divider()
                // Editor rychlostní křivky vybraného klipu (fáze 3, modul 3).
                // Pevná výška ze stejného důvodu jako osa pod ním.
                RampEditorPaneView(controller: model.timeline)
                    .frame(height: 132)
                Divider()
                // Pevná výška, ne `idealHeight`. Přehrávač i osa jsou oba
                // pružné `NSViewRepresentable`, takže se o volné místo
                // podělily napůl a pod třemi pruhy (156 bodů) zbylo přes
                // dvě stě bodů prázdna. Tady si osa říká přesně o svoje;
                // roztahovací dělič je věc kroku 3, až přibude pravítko.
                TimelinePaneView(controller: model.timeline,
                                 onMake: { model.attachTimeline($0) })
                    .frame(height: 220)
            }

            TransportBar(controller: model.controller, hidden: model.chromeHidden)
        }
    }
}

/// Přepínač proxy a průběh generování (fáze 4). Vlastní malé view ze
/// stejného důvodu jako `TransportBar`: SwiftUI nesleduje vnořené
/// `ObservableObject`y, takže `model.proxies.progressText` by se v těle
/// `ContentView` nikdy nepřekreslil.
private struct ProxyControls: View {
    @ObservedObject var timeline: TimelineController
    @ObservedObject var proxies: ProxyStore
    let onChangeLocation: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Stříhat z proxy (rychlejší scrubování)", isOn: Binding(
                get: { timeline.project.usesProxies },
                set: { timeline.setUsesProxies($0) }))
                .disabled(timeline.project.assets.allSatisfy { $0.proxyURL == nil })
                .help("ProRes 422 Proxy v polovičním rozlišení, VFR zploštěné na CFR. "
                    + "Seek 6 ms místo 41–95 ms. Export půjde vždy z originálů.")

            if let text = proxies.progressText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Změnit umístění…") { onChangeLocation() }
                Button("Smazat proxy") { onDelete() }
                    .disabled(proxies.cacheSizeBytes == 0)
            }
            .controlSize(.small)
            .disabled(proxies.progressText != nil)

            Text("Úložiště: \(proxies.directoryDisplayName) · "
                 + ByteCountFormatter.string(fromByteCount: proxies.cacheSizeBytes,
                                             countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// Ovládání přehrávání. Vlastní view schválně.
///
/// ⚠️ **SwiftUI nesleduje vnořené `ObservableObject`y.** `ContentView` drží
/// `AppModel`, ale `currentTime` a `isPlaying` jsou publikované na
/// `AppModel.controller`, což je jiný objekt — změna v něm tedy `ContentView`
/// nepřekreslí. Projevovalo se to tak, že **časový údaj trvale ukazoval
/// `0:00.000` a tlačítko se nikdy nepřepnulo na „Pauza"**, přestože
/// přehrávání běželo a zvuk byl slyšet. V projektu to bylo od fáze 1
/// a odhaleno až 27. 07. 2026 ruční zkouškou.
///
/// Řešením je `@ObservedObject` na controlleru — ale v malém view, ne
/// v `ContentView`. Kdyby se překresloval celý obsah okna, dělo by se to
/// třicetkrát za sekundu (tolikrát chodí pozorovatel času) a s ním by se
/// třicetkrát za sekundu volalo `updateNSView` na časové ose. Takhle se
/// překresluje jen tenhle proužek.
private struct TransportBar: View {
    @ObservedObject var controller: PlaybackController
    let hidden: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button(controller.isPlaying ? "Pauza" : "Přehrát") {
                controller.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("◀︎ snímek") { controller.step(frames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("snímek ▶︎") { controller.step(frames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])

            Spacer()
            Text(Self.timecode(controller.currentTime))
                .font(.system(.body, design: .monospaced))
        }
        .padding(10)
        .frame(height: hidden ? 0 : nil)
        .opacity(hidden ? 0 : 1)
        .clipped()
    }

    private static func timecode(_ time: CMTime) -> String {
        guard time.isValid, time.seconds.isFinite else { return "—" }
        let total = time.seconds
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, seconds)
    }
}
