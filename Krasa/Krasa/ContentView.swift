//
//  ContentView.swift
//  Projekt Krása
//
//  Minimální UI fáze 1: otevřít klip, přehrát, krokovat, změřit.
//  Žádná timeline, žádné panely — to je fáze 2.
//

import AVFoundation
import AppKit
import SwiftUI

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
    /// Stav časové osy. Žije v modelu, ne ve view — `TimelinePaneView` se
    /// smí kdykoli přetvořit, `TimelineController` to nesmí pocítit.
    let timeline = TimelineController()
    private(set) var hostView: PlayerHostView?

    /// Pauza mezi běhy. Air je bezventilátorový — bez chladnutí měří druhý
    /// běh teplejší stroj, ne jiný stav.
    static let coolDownSeconds: UInt64 = 20

    func attach(_ view: PlayerHostView) { hostView = view }

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
        status = "\(clips.count) klipů. Vyber jeden a přehraj, nebo spusť měření."
        if selected == nil, let first = clips.first { await select(first) }
    }

    func select(_ clip: ClipTiming) async {
        selected = clip
        try? await controller.load(url: clip.url, measuredFrameRate: clip.measuredFrameRate)
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
            }
        }
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

            List(model.clips, id: \.url) { clip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.name).font(.system(.body, design: .monospaced))
                    Text("\(clip.verdict.shortLabel) · \(String(format: "%.2f", clip.measuredFrameRate)) fps"
                         + (clip.droppedFrames > 0 ? " · \(clip.droppedFrames) zahozených" : ""))
                        .font(.caption)
                        .foregroundStyle(clip.isVariable ? .orange : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.select(clip) } }
            }

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
                // Pevná výška, ne `idealHeight`. Přehrávač i osa jsou oba
                // pružné `NSViewRepresentable`, takže se o volné místo
                // podělily napůl a pod třemi pruhy (156 bodů) zbylo přes
                // dvě stě bodů prázdna. Tady si osa říká přesně o svoje;
                // roztahovací dělič je věc kroku 3, až přibude pravítko.
                TimelinePaneView(controller: model.timeline)
                    .frame(height: 220)
            }

            HStack(spacing: 16) {
                Button(model.controller.isPlaying ? "Pauza" : "Přehrát") {
                    model.controller.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("◀︎ snímek") { model.controller.step(frames: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("snímek ▶︎") { model.controller.step(frames: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                Spacer()
                Text(timecode(model.controller.currentTime))
                    .font(.system(.body, design: .monospaced))
            }
            .padding(10)
            .frame(height: model.chromeHidden ? 0 : nil)
            .opacity(model.chromeHidden ? 0 : 1)
            .clipped()
        }
    }

    private func timecode(_ time: CMTime) -> String {
        guard time.isValid, time.seconds.isFinite else { return "—" }
        let total = time.seconds
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, seconds)
    }
}
