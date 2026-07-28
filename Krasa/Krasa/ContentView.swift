//
//  ContentView.swift
//  Projekt Krása
//
//  Minimální UI fáze 1: otevřít klip, přehrát, krokovat, změřit.
//  Žádná timeline, žádné panely — to je fáze 2.
//

import AVFoundation
import AppKit
import AudioEngine
import Combine
import ProbeKit
import SwiftUI
import TimelineModel
import UniformTypeIdentifiers

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
    /// Přepis řeči (fáze 8).
    let transcription = TranscriptionService()
    /// Generátor a evidence proxy (fáze 4).
    let proxies = ProxyStore()
    /// Soubor projektu (fáze 5).
    let projectStore = ProjectStore()
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

    /// Kompozice postavená z aktuálního projektu (fáze 3, modul 1; od
    /// fáze 7 i s mapou zvukových stop pro `AVAudioMix`).
    private var builtTimeline: BuiltTimeline?
    /// Tvar osy BEZ mixu, ze kterého je kompozice postavená. Když se nový
    /// projekt liší jen mixem, kompozice se nepřestavuje — vymění se jen
    /// `audioMix` na běžícím itemu a přehrávání jede dál.
    private var builtTimelineShape: Timeline?
    private var compositionRebuild: Task<Void, Never>?
    private var subscriptions: [AnyCancellable] = []

    init() {
        loudnessProfile = Self.storedLoudnessProfile()
        // Osa → přehrávač: uživatel posunul hlavu, přehrávač skočí.
        timeline.onUserSeek = { [weak self] frame in
            self?.seekPlayer(toTimelineFrame: frame)
        }
        // Kontextové menu klipu → synchronizace externího zvuku (fáze 7).
        timeline.onSyncAudioRequest = { [weak self] clipID in
            self?.syncExternalAudio(clipID: clipID)
        }
        // Kontextové menu klipu → titulky z řeči (fáze 8).
        timeline.onTranscribeRequest = { [weak self] clipID in
            Task { await self?.performTranscription(clipID: clipID) }
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
            // Hlasitost stopy se do běžícího přehrávání promítá HNED, ne
            // přes debounce přestavby — uživatel míchá poslechem a čtvrt
            // sekundy zpoždění by z posuvníku udělalo loterii.
            timeline.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] project in self?.applyLiveAudioMix(project) },
            // Proxy se k assetům přišívají znovu po KAŽDÉ změně projektu:
            // undo vrací snapshoty z doby, kdy proxy ještě neexistovaly,
            // a bez tohohle by ⌘Z tiše přepnul přehrávání na originály.
            // Smyčka nehrozí — `setProxy` při shodě nezapisuje.
            timeline.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reapplyKnownProxies() },
            // Indikátor „neuloženo" hned…
            timeline.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] project in self?.projectStore.updateDirty(project) },
            // …a záloha 5 s po poslední změně. Zapíše se, jen když se stav
            // liší od baseline — pouhé spuštění a sken zálohu nevyrábí.
            timeline.$project
                .removeDuplicates()
                .debounce(for: .seconds(5), scheduler: DispatchQueue.main)
                .sink { [weak self] project in self?.projectStore.autosaveIfDirty(project) },
        ]

        // Ukončení aplikace nesmí zahodit posledních pár sekund práce —
        // debounce zálohy by je nestihl.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.projectStore.autosaveIfDirty(self.timeline.project)
            }
        }
    }

    private func reapplyKnownProxies() {
        for (original, proxy) in proxies.finished {
            timeline.setProxy(proxy, forAssetWithOriginal: original)
        }
    }

    // MARK: Projektový soubor (fáze 5)

    /// Dotaz před zahozením neuložené práce: ukončení aplikace, otevření
    /// jiného projektu i import (= nový projekt). Vrací `true` = pokračuj.
    ///
    /// „Neukládat" zahazuje i autosave — je to výslovné rozhodnutí a příští
    /// start by jinak „obnovoval" práci, kterou uživatel právě zahodil.
    /// Volá se až PO výběru v panelu (otevřít/import), ne před ním: kdyby
    /// uživatel řekl „Neukládat" a pak panel zrušil, projekt by zůstal,
    /// ale ochrana už by byla pryč.
    func confirmLosingUnsavedWork() -> Bool {
        guard projectStore.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Uložit změny v projektu „\(projectStore.displayName)“?"
        alert.informativeText = "Bez uložení se změny ztratí."
        alert.addButton(withTitle: "Uložit")
        alert.addButton(withTitle: "Neukládat")
        alert.addButton(withTitle: "Zrušit")
        alert.buttons[2].keyEquivalent = "\u{1b}"   // Escape = Zrušit
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveProject()
            // Neuložený projekt jde přes „Uložit jako" a ten panel se dá
            // zrušit — pak je pořád špinavo a pokračovat se nesmí.
            return !projectStore.isDirty
        case .alertSecondButtonReturn:
            projectStore.discardAutosave()
            projectStore.markCurrent(timeline.project)
            return true
        default:
            return false
        }
    }

    /// ⌘Q. CLI běhy (`--…`) se neptají — `terminate(nil)` v headless
    /// režimu by visel na modálním dialogu.
    func shouldTerminate() -> Bool {
        if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            return true
        }
        return confirmLosingUnsavedWork()
    }

    func saveProject() {
        if let url = projectStore.fileURL {
            performSave(to: url)
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [ProjectStore.fileType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = projectStore.fileURL?.lastPathComponent
            ?? "Svatba.projektkrasa"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performSave(to: url)
    }

    private func performSave(to url: URL) {
        do {
            try projectStore.save(project: timeline.project, to: url)
            status = "Projekt uložen: \(url.lastPathComponent)"
        } catch {
            status = "Uložení selhalo: \(error.localizedDescription)"
        }
    }

    func openProjectViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [ProjectStore.fileType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmLosingUnsavedWork() else { return }
        Task { await openProject(at: url) }
    }

    func openProject(at url: URL) async {
        do {
            let raw = try projectStore.load(from: url)
            var project = projectStore.resolveAssets(in: raw)
            timeline.loadProject(project)
            projectStore.markCurrent(project)

            // Záloha novější než soubor = minule to neskončilo uložením.
            // Nabídnout, ne mlčky přepsat — rozhodnutí patří uživateli.
            if let backup = projectStore.pendingAutosave(),
               backup.modifiedAt > (projectStore.lastSavedAt ?? .distantPast)
                   .addingTimeInterval(1) {
                if Self.askRestore(
                    message: "Našla se automatická záloha novější než uložený soubor",
                    detail: "Záloha je z \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)). "
                        + "Obnovená práce zůstane neuložená, dokud ji nepotvrdíš přes ⌘S.") {
                    project = projectStore.resolveAssets(in: backup.project)
                    timeline.loadProject(project)
                    // Baseline zůstává obsah SOUBORU — obnovená práce se má
                    // hlásit jako neuložená.
                } else {
                    projectStore.discardAutosave()
                }
            }

            let offline = project.assets.filter(\.isOffline).count
            status = offline == 0
                ? "Otevřen projekt \(projectStore.displayName)."
                : "Otevřen projekt \(projectStore.displayName) — \(offline) assetů offline."
            await refreshSidebar(for: project)
        } catch {
            status = "Projekt se nepodařilo otevřít: "
                + ((error as? ProjectFileError)?.description ?? error.localizedDescription)
        }
    }

    /// Obnova neuloženého projektu po pádu — volá se při startu, když není
    /// co otevírat, ale slot neuloženého projektu má zálohu.
    func offerUnsavedRecovery() async -> Bool {
        guard projectStore.fileURL == nil,
              let backup = projectStore.pendingAutosave() else { return false }
        guard Self.askRestore(
            message: "Našla se záloha neuloženého projektu",
            detail: "Aplikace minule neskončila uložením. Záloha je z "
                + "\(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)).") else {
            projectStore.discardAutosave()
            return false
        }
        let project = projectStore.resolveAssets(in: backup.project)
        timeline.loadProject(project)
        projectStore.markRestoredUnsaved()   // dál „neuloženo", autosave chrání
        status = "Obnoven neuložený projekt ze zálohy. ⌘S ho uloží."
        await refreshSidebar(for: project)
        return true
    }

    private static func askRestore(message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Obnovit zálohu")
        alert.addButton(withTitle: "Zahodit zálohu")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Start aplikace: otevřít poslední projekt. `false` = není co otevřít
    /// a jede se postaru (sken zapamatovaných složek).
    func reopenLastProject() async -> Bool {
        guard let url = projectStore.restoreLastProjectURL() else { return false }
        await openProject(at: url)
        return projectStore.fileURL != nil
    }

    /// Po otevření projektu: sidebar se přeměří z assetů projektu (badge
    /// CFR/VFR jsou měření, ne uložená data) a rozjede se generování proxy —
    /// hotové se najdou otiskem v cache.
    private func refreshSidebar(for project: Project) async {
        var found: [ClipTiming] = []
        for asset in project.assets where !asset.isOffline {
            if case .success(let timing) = await VFRDetector.inspect(url: asset.originalURL) {
                found.append(timing)
            }
        }
        clips = found.sorted { $0.name < $1.name }
        startProxyGeneration()
    }

    /// CLI ověření: uložit → načíst → porovnat. Timeline musí sedět do
    /// posledního ticku včetně rychlostních křivek.
    func verifyProjectRoundtrip() {
        if let firstClip = timeline.project.timeline.tracks.first?.clips.first {
            timeline.toggleClassicRamp(firstClip.id)   // ať se ověřuje i rampa
        }
        // Soubor se NECHÁVÁ v Application Support a pamatuje se jako
        // poslední projekt — další start bez parametrů tím ověří i obnovu
        // napříč procesy (bookmarky, security scope), kterou in-process
        // roundtrip pokrýt nemůže.
        guard let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RoundtripTest.projektkrasa") else { return }
        do {
            try projectStore.save(project: timeline.project, to: url)
            let loaded = projectStore.resolveAssets(in: try projectStore.load(from: url))
            let clipCount = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
            if loaded.timeline == timeline.project.timeline,
               loaded.usesProxies == timeline.project.usesProxies,
               loaded.assets.map(\.id) == timeline.project.assets.map(\.id) {
                print("✅ roundtrip projektu sedí: \(timeline.project.assets.count) assetů,"
                      + " \(clipCount) klipů, rampa přežila")
            } else {
                print("❌ roundtrip projektu NESEDÍ")
            }
        } catch {
            print("❌ roundtrip selhal: \(error)")
        }
    }

    /// CLI ověření autosave: baseline po skenu čistá, střih zašpiní,
    /// záloha se zapíše, sedí a jde zahodit.
    func verifyAutosave() {
        projectStore.discardAutosave()   // čistý start — slot mohl zbýt z minula
        guard !projectStore.isDirty else {
            print("❌ po skenu je projekt špinavý — baseline nesedí")
            return
        }
        guard projectStore.pendingAutosave() == nil else {
            print("❌ záloha existuje, ještě než se cokoli změnilo")
            return
        }

        if let first = timeline.project.timeline.tracks.first?.clips.first {
            timeline.toggleClassicRamp(first.id)
        }
        projectStore.updateDirty(timeline.project)   // sink jede asynchronně
        guard projectStore.isDirty else {
            print("❌ po střihu se projekt nehlásí jako neuložený")
            return
        }

        projectStore.autosaveIfDirty(timeline.project)
        guard let backup = projectStore.pendingAutosave(),
              backup.project.timeline == timeline.project.timeline else {
            print("❌ záloha chybí nebo nesedí s projektem")
            return
        }

        projectStore.discardAutosave()
        guard projectStore.pendingAutosave() == nil else {
            print("❌ zálohu se nepodařilo zahodit")
            return
        }
        print("✅ autosave: čistý po skenu, špinavý po střihu, záloha sedí a jde zahodit")
    }

    // MARK: Export (fáze 5)

    /// Zlomek hotových snímků; `nil` = žádný export neběží.
    @Published var exportProgress: Double?

    /// Profil LUFS normalizace exportu (fáze 7, modul 3). `nil` = bez
    /// normalizace. Výchozí Web −14 podle spec 7.1. Nastavení aplikace
    /// (UserDefaults), ne projektu — je to vlastnost DODÁVKY, ne střihu;
    /// per-projekt volba by chtěla změnu formátu souboru a zatím není
    /// důvod.
    @Published var loudnessProfile: LoudnessProfile? {
        didSet {
            UserDefaults.standard.set(loudnessProfile?.rawValue ?? "none",
                                      forKey: Self.loudnessProfileKey)
        }
    }
    private static let loudnessProfileKey = "cz.projektkrasa.loudnessProfile"

    static func storedLoudnessProfile() -> LoudnessProfile? {
        guard let raw = UserDefaults.standard.string(forKey: loudnessProfileKey) else {
            return .web   // první spuštění: výchozí podle spec
        }
        return LoudnessProfile(rawValue: raw)   // „none" → nil
    }

    func exportMovie() {
        guard exportProgress == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            (projectStore.fileURL?.deletingPathExtension().lastPathComponent ?? "Svatba") + ".mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await export(to: url) }
    }

    /// Export VŽDY z originálů — proxy je poloviční a je jen pro střih.
    /// HEVC 4K/30 CFR + AAC, `.timeDomain` kvůli škálovaným úsekům ramp.
    func export(to url: URL) async {
        guard exportProgress == nil else { return }
        exportProgress = 0
        defer { exportProgress = nil }
        status = "Exportuju… (HEVC z originálů)"

        do {
            let project = timeline.project
            guard let built = try await CompositionBuilder.build(project: project,
                                                                 usingProxies: false),
                  let video = built.composition.tracks(withMediaType: .video).first else {
                status = "Není co exportovat — na ose nejsou žádné klipy."
                return
            }
            let composition = built.composition
            let canvas = project.timeline.canvasSize
            let ticksPerFrame = Int64(SourceTime.projectTimescale)
                / Int64(project.timeline.frameRate)
            let mix = built.audioMix(project: project)

            // LUFS normalizace (fáze 7, modul 3): změřit budoucí mix,
            // dopočítat gain na cíl profilu, zastropovat špičkou.
            var audioGain = 1.0
            var loudnessNote = ""
            if let profile = loudnessProfile {
                status = "Měřím hlasitost… (\(profile.displayName))"
                if let scan = try await LoudnessScanner.scan(asset: composition, audioMix: mix),
                   let measured = scan.integratedLUFS {
                    var gainDB = LoudnessNormalization.gainDecibels(
                        measured: measured, target: profile.targetLUFS)
                    // Strop: špička po zesílení ≤ −1 dBFS. Bez limiteru je
                    // tohle jediná poctivá ochrana proti clippingu — a když
                    // zasáhne, řekne se to, nezamlčí.
                    if scan.samplePeak > 0 {
                        let capDB = -1.0 - 20.0 * log10(Double(scan.samplePeak))
                        if gainDB > capDB {
                            gainDB = capDB
                            loudnessNote = String(
                                format: " Hlasitost %.1f LUFS, gain omezen špičkami na %+.1f dB"
                                    + " — na cíl %.0f LUFS nedosáhl.",
                                measured, gainDB, profile.targetLUFS)
                        }
                    }
                    if loudnessNote.isEmpty {
                        loudnessNote = String(
                            format: " Hlasitost %.1f → %.0f LUFS (gain %+.1f dB).",
                            measured, profile.targetLUFS, gainDB)
                    }
                    audioGain = LoudnessNormalization.linearGain(decibels: gainDB)
                }
                status = "Exportuju… (HEVC z originálů)"
            }

            // Titulky (fáze 11): vypálení přes dekorátor snímků — snímky bez
            // titulku projdou nedotčené. Bez titulků je dekorátor nil a celá
            // cesta je ta ověřená z fáze 5.
            let titleRenderer = TitleExportRenderer(
                cues: project.titleCues(),
                canvas: CGSize(width: canvas.width, height: canvas.height))

            let result = try await CFRRenderer.render(
                asset: composition,
                videoTrack: video,
                audioTracks: composition.tracks(withMediaType: .audio),
                frameDuration: CMTime(value: ticksPerFrame,
                                      timescale: SourceTime.projectTimescale),
                audioTimePitchAlgorithm: .timeDomain,
                outputSize: CGSize(width: canvas.width, height: canvas.height),
                format: .hevcAAC(videoBitRate: 50_000_000, audioBitRate: 256_000),
                // Hlasitosti stop do exportu STEJNOU cestou jako do
                // přehrávače — co slyšíš při střihu, to dostaneš v souboru.
                audioMix: mix,
                audioGainLinear: audioGain,
                // Přechody (fáze 10): tatáž video kompozice jako v náhledu.
                videoComposition: built.videoComposition,
                frameDecorator: titleRenderer?.decorator(),
                onProgress: { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.exportProgress != nil else { return }
                        self.exportProgress = fraction
                    }
                },
                to: url)

            status = "Export hotový: \(url.lastPathComponent) — "
                + "\(result.writtenFrameCount) snímků za "
                + String(format: "%.1f s.", result.elapsedSeconds)
                + loudnessNote
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            status = "Export selhal: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// CLI ověření exportu: rampa na první klip, export do temp složky —
    /// výsledek pak přeměří MediaProbe (CFR, kodek, délka).
    func verifyExport() async {
        if let first = timeline.project.timeline.tracks.first?.clips.first {
            timeline.toggleClassicRamp(first.id)
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaExportCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("export_check.mp4")
        await export(to: url)
        let expected = Double(timeline.project.duration.count)
            / Double(timeline.project.timeline.frameRate)
        print(status)
        print(String(format: "očekávaná délka osy: %.3f s", expected))
        print("EXPORT_PATH=\(directory.path)")
    }

    /// CLI ověření mixu (fáze 7, modul 2): dvojí export téže osy — plná
    /// hlasitost a pak A1 na 0,25 (−12,04 dB). Rozdíl hlasitostí souborů
    /// přeměří externí skript; musí vyjít ~12 LU. Druhý export zároveň
    /// cvičí cestu `AVAssetReaderAudioMixOutput` s mixem.
    func verifyAudioMixExport() async {
        // CLI běh nesmí trvale přepsat uživatelské nastavení profilu.
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil   // normalizace by rozdíl hlasitostí dorovnala
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaMixCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)

        await export(to: directory.appendingPathComponent("mix_full.mp4"))
        print("plná hlasitost: \(status)")

        guard let a1 = timeline.project.timeline.tracks.first(where: { $0.kind == .audio })
        else { print("❌ osa nemá zvukovou stopu"); return }
        timeline.volumeDragBegan()
        timeline.volumeDragChanged(a1.id, volume: 0.25)
        timeline.volumeDragEnded()

        await export(to: directory.appendingPathComponent("mix_quarter.mp4"))
        print("A1 na 0,25×: \(status)")
        print("MIX_CHECK_PATH=\(directory.path)")
    }

    // MARK: Titulky z řeči (fáze 8, modul 2)

    /// Přepíše zvuk ZDROJOVÉHO souboru klipu a uloží přepis k assetu —
    /// titulky se pak promítají na osu přes všechny klipy téhož zdroje
    /// (`subtitleCues`, modul 1). Model se poprvé stahuje (~1,5 GB).
    @discardableResult
    func performTranscription(clipID: ClipID) async -> Bool {
        let project = timeline.project
        guard let clip = project.timeline.clip(clipID),
              let asset = project.asset(clip.assetID) else { return false }
        guard asset.hasAudio else {
            status = "Klip nemá zvukovou stopu — není co přepisovat."
            return false
        }
        status = "Přepisuju řeč z \(asset.originalURL.lastPathComponent)…"
        do {
            let segments = try await transcription.transcribe(url: asset.originalURL)
            guard !segments.isEmpty else {
                status = "V nahrávce se nenašla žádná řeč."
                return false
            }
            timeline.setTranscript(assetID: asset.id, segments: segments)
            status = "Přepsáno: \(segments.count) úseků řeči."
            return true
        } catch {
            status = "Přepis selhal: \(error.localizedDescription)"
            return false
        }
    }

    /// Export titulků do SubRip souboru vedle filmu (fáze 8, modul 3).
    func exportSubtitles() {
        let cues = timeline.project.subtitleCues()
        guard !cues.isEmpty else {
            status = "Na ose nejsou žádné titulky — nejdřív „Vytvořit titulky z řeči“ na klipu."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt",
                                            conformingTo: .plainText) ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            (projectStore.fileURL?.deletingPathExtension().lastPathComponent ?? "Svatba") + ".srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let srt = SRT.serialize(cues: cues, frameRate: timeline.project.timeline.frameRate)
            try srt.write(to: url, atomically: true, encoding: .utf8)
            status = "Titulky uloženy: \(url.lastPathComponent) (\(cues.count) titulků)."
        } catch {
            status = "Uložení titulků selhalo: \(error.localizedDescription)"
        }
    }

    /// CLI ověření SRT cesty: syntetický přepis na první asset → titulky
    /// promítnuté přes klipy osy → hotový SRT výstup. Formát samotný
    /// drží testy modelu; tohle cvičí skládání appky od assetu po soubor.
    func verifySRTExport() {
        guard let asset = timeline.project.assets.first else {
            print("❌ projekt nemá asset"); return
        }
        timeline.setTranscript(assetID: asset.id, segments: [
            TranscriptSegment(start: SourceTime(seconds: 1), end: SourceTime(seconds: 2.5),
                              text: "Zkušební titulek"),
            TranscriptSegment(start: SourceTime(seconds: 4), end: SourceTime(seconds: 5),
                              text: "Druhý úsek"),
        ])
        let cues = timeline.project.subtitleCues()
        print("titulků na ose: \(cues.count)")
        print(SRT.serialize(cues: cues, frameRate: timeline.project.timeline.frameRate))
    }

    /// CLI ověření přechodů (fáze 10, modul 2): tři klipy z téhož zdroje se
    /// zdrojovými přesahy, zatmívačka na prvním střihu (snímek 60), prolínačka
    /// na druhém (snímek 120), zvukový crossfade na A1. Export se přeměří po
    /// snímcích: na střihu zatmívačky musí být obraz ~černý, uprostřed
    /// prolínačky směs obou stran (opacity 0,5 → průměr jasů).
    func verifyTransitionExport() async {
        // CLI běh nesmí trvale přepsat uživatelské nastavení profilu.
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil

        guard let source = timeline.project.assets
            .filter({ $0.hasVideo })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        let available = project.timeline.availableFrames(from: source.duration)
        guard available.count >= 305 else {
            print("❌ asset je krátký (\(available.count) snímků, potřeba 305)"); return
        }

        let v1 = project.timeline.tracks[0].id
        let a1 = project.timeline.tracks[1].id
        func makeClip(start: Int, sourceFrame: Int) -> Clip {
            Clip(assetID: source.id, timelineStart: Frames(start), duration: Frames(60),
                 sourceStart: project.timeline.sourceTime(Frames(sourceFrame)))
        }
        do {
            var videoIDs: [ClipID] = []
            var audioIDs: [ClipID] = []
            for (start, src) in [(0, 0), (60, 120), (120, 240)] {
                let video = makeClip(start: start, sourceFrame: src)
                try project.insert(video, onTrack: v1)
                videoIDs.append(video.id)
                if source.hasAudio {
                    let audio = makeClip(start: start, sourceFrame: src)
                    try project.insert(audio, onTrack: a1)
                    audioIDs.append(audio.id)
                }
            }
            try project.setTransition(.dipToBlack, duration: Frames(20),
                                      betweenLeft: videoIDs[0], andRight: videoIDs[1])
            try project.setTransition(.crossDissolve, duration: Frames(30),
                                      betweenLeft: videoIDs[1], andRight: videoIDs[2])
            if audioIDs.count == 3 {
                try project.setTransition(.audioCrossfade, duration: Frames(20),
                                          betweenLeft: audioIDs[0], andRight: audioIDs[1])
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaTransitionCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("transition_check.mp4")
        await export(to: url)
        print(status)

        // Zatmívačka (oblast [50, 70), střih 60): průměrný jas na střihu
        // musí spadnout k nule.
        guard let pureA = await lumaGrid(url: url, seconds: 40.5 / 30),
              let dipCut = await lumaGrid(url: url, seconds: 60.5 / 30),
              let pureB = await lumaGrid(url: url, seconds: 80.5 / 30) else {
            print("❌ nepodařilo se přečíst kontrolní snímky exportu"); return
        }
        let dipLuma = dipCut.reduce(0, +) / Double(dipCut.count)
        let edgeLuma = min(pureA.reduce(0, +), pureB.reduce(0, +)) / Double(pureA.count)
        print(String(format: "zatmívačka: jas okolí %.0f | na střihu %.0f", edgeLuma, dipLuma))
        print(dipLuma < 0.25 * edgeLuma
              ? "✓ zatmívačka na střihu stmívá do černé"
              : "❌ zatmívačka na střihu NENÍ černá")

        // Prolínačka (oblast [105, 135), střih 120, opacity přesně 0,5):
        // snímek na střihu se PO PIXELECH porovná s průměrem obou zdrojových
        // snímků, které se v něm mají míchat — clip2 je v tu chvíli na 6,0 s
        // zdroje, clip3 na 8,0 s. Průměr jasů by prošel i tvrdému střihu,
        // tohle ne: směs musí být blíž průměru než kterékoli straně.
        guard let mid = await lumaGrid(url: url, seconds: 120.5 / 30),
              let sideA = await lumaGrid(url: source.originalURL, seconds: 6.0 + 0.5 / 30),
              let sideB = await lumaGrid(url: source.originalURL, seconds: 8.0 + 0.5 / 30) else {
            print("❌ nepodařilo se přečíst zdrojové snímky prolínačky"); return
        }
        let predicted = zip(sideA, sideB).map { ($0 + $1) / 2 }
        func mae(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
        }
        let toPredicted = mae(mid, predicted)
        let toSideA = mae(mid, sideA)
        let toSideB = mae(mid, sideB)
        print(String(format: "prolínačka: odchylka od směsi %.1f | od levé %.1f | od pravé %.1f",
                     toPredicted, toSideA, toSideB))
        let dissolveOK = toPredicted < 16 && toPredicted < toSideA && toPredicted < toSideB
        print(dissolveOK ? "✓ prolínačka na střihu je směs obou stran (opacity 0,5)"
                         : "❌ prolínačka na střihu není směs — vypadá jako tvrdý střih")
        print("TRANSITION_CHECK_PATH=\(directory.path)")
    }

    /// CLI měření GPU skoku přechodů (fáze 10, modul 2): postaví touž osu
    /// jako `--transition-check` (s přechody, nebo BEZ nich s argumentem
    /// „off") a ~20 s ji přehrává v popředí. Čísla netiskne — GPU vzorkuje
    /// vnější skript (`ioreg`/`powermetrics`) vedle běžící aplikace; okno
    /// si říká o popředí, protože měření náhledu je platné, jen když bylo
    /// na co koukat (poučení z fáze 1).
    func runTransitionGPUPlayback(enabled: Bool) async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        guard project.timeline.availableFrames(from: source.duration).count >= 305 else {
            print("❌ asset je krátký"); return
        }
        let v1 = project.timeline.tracks[0].id
        let a1 = project.timeline.tracks[1].id
        do {
            var videoIDs: [ClipID] = []
            for (start, src) in [(0, 0), (60, 120), (120, 240)] {
                let video = Clip(assetID: source.id, timelineStart: Frames(start),
                                 duration: Frames(60),
                                 sourceStart: project.timeline.sourceTime(Frames(src)))
                try project.insert(video, onTrack: v1)
                videoIDs.append(video.id)
                if source.hasAudio {
                    let audio = Clip(assetID: source.id, timelineStart: Frames(start),
                                     duration: Frames(60),
                                     sourceStart: project.timeline.sourceTime(Frames(src)))
                    try project.insert(audio, onTrack: a1)
                }
            }
            if enabled {
                try project.setTransition(.dipToBlack, duration: Frames(20),
                                          betweenLeft: videoIDs[0], andRight: videoIDs[1])
                try project.setTransition(.crossDissolve, duration: Frames(30),
                                          betweenLeft: videoIDs[1], andRight: videoIDs[2])
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project

        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        for _ in 0..<40 where builtTimeline == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let built = builtTimeline else { print("❌ kompozice nevznikla"); return }
        print("videoComposition: \(built.videoComposition != nil ? "ANO" : "NE")")
        // Synchronizace s vnějším vzorkovačem MARKEROVÝM SOUBOREM, ne přes
        // stdout — print do roury se bufferuje až do konce procesu a vnější
        // skript by se markery dozvěděl pozdě (změřeno: i pod `script` pty).
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaGPUPlayback.marker")
        try? "playing".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }
        controller.seek(to: .zero)
        controller.play()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            // Osa má 6 s — na konci se točí znovu, měří se souvislé
            // přehrávání. Konec se pozná ze STAVU přehrávače (`.pause` na
            // konci itemu), ne z času hlavy — periodický pozorovatel nemusí
            // poslední snímek vůbec tiknout a čas by konce nedosáhl.
            if controller.player.timeControlStatus == .paused {
                controller.seek(to: .zero)
                controller.play()
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        controller.pause()
    }

    /// CLI ověření vypálení titulků (fáze 11, modul 4): dvojí export téže
    /// osy — s titulkem přes snímky 30–90 a bez něj. Uvnitř titulku se
    /// exporty musí lišit (bílý text zvedá jas ve středu obrazu), mimo
    /// titulek musí být prakticky shodné (dekorátor se snímku nedotkl;
    /// drobnou odchylku smí přidat jen historie HEVC kodéru).
    func verifyTitleExport() async {
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil

        guard let source = timeline.project.assets
            .filter({ $0.hasVideo })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var bare = Project.empty()
        bare.addAsset(source)
        guard bare.timeline.availableFrames(from: source.duration).count >= 180 else {
            print("❌ asset je krátký"); return
        }
        do {
            let clip = try bare.makeClip(assetID: source.id)
            var trimmed = clip
            trimmed.duration = Frames(180)
            try bare.insert(trimmed, onTrack: bare.timeline.tracks[0].id)
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }

        var titled = bare
        do {
            let t1 = titled.ensureTitleTrack()
            let title = try titled.makeTitle(text: "Anna a Petr", template: .names,
                                             at: Frames(30), duration: Frames(60))
            try titled.addTitle(title, onTrack: t1)
        } catch {
            print("❌ přidání titulku selhalo: \(error)"); return
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaTitleCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let titledURL = directory.appendingPathComponent("title_on.mp4")
        let bareURL = directory.appendingPathComponent("title_off.mp4")

        timeline.project = titled
        await export(to: titledURL)
        print(status)
        timeline.project = bare
        await export(to: bareURL)
        print(status)

        // Snímek 60 (t = 2 s) je uprostřed titulku, snímek 135 (t = 4,5 s)
        // za ním. Časy míří o půl snímku DOVNITŘ intervalu (vzorec
        // `lumaGrid`), aby se netrefovala hrana.
        guard let onIn = await lumaGrid(url: titledURL, seconds: 60.5 / 30),
              let offIn = await lumaGrid(url: bareURL, seconds: 60.5 / 30),
              let onOut = await lumaGrid(url: titledURL, seconds: 135.5 / 30),
              let offOut = await lumaGrid(url: bareURL, seconds: 135.5 / 30) else {
            print("❌ nepodařilo se přečíst kontrolní snímky"); return
        }
        func mae(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
        }
        // Jména sedí přes střed obrazu — řádky 3–4 mřížky 8×8.
        func centerBand(_ grid: [Double]) -> Double {
            let rows = [3, 4]
            let cells = rows.flatMap { row in (1...6).map { grid[row * 8 + $0] } }
            return cells.reduce(0, +) / Double(cells.count)
        }

        let insideDiff = mae(onIn, offIn)
        let outsideDiff = mae(onOut, offOut)
        let bandLift = centerBand(onIn) - centerBand(offIn)
        print(String(format: "uvnitř titulku: odchylka %.2f | střední pás +%.1f jasu",
                     insideDiff, bandLift))
        print(String(format: "mimo titulek: odchylka %.2f", outsideDiff))
        print(insideDiff > 2 && bandLift > 5
              ? "✓ titulek je v exportu vypálený (bílý text zvedá jas středu)"
              : "❌ titulek v exportu NENÍ vidět")
        print(outsideDiff < 2
              ? "✓ snímky mimo titulek jsou nedotčené"
              : "❌ export se liší i mimo titulek — dekorátor sahá, kam nemá")
        print("TITLE_CHECK_PATH=\(directory.path)")
    }

    /// CLI ukázka fáze 11 (`--title-demo`): postaví osu s grafickými
    /// titulky na T1 a syntetickým přepisem (pásky řeči v pruhu), hlavu
    /// postaví do prvního titulku a nechá okno ~25 s v popředí. Nic
    /// neměří — je to koukanec pro oko a screenshot.
    func runTitleDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        guard project.timeline.availableFrames(from: source.duration).count >= 305 else {
            print("❌ asset je krátký"); return
        }
        let v1 = project.timeline.tracks[0].id
        let a1 = project.timeline.tracks[1].id
        do {
            for (start, src) in [(0, 0), (60, 120), (120, 240)] {
                let video = Clip(assetID: source.id, timelineStart: Frames(start),
                                 duration: Frames(60),
                                 sourceStart: project.timeline.sourceTime(Frames(src)))
                try project.insert(video, onTrack: v1)
                if source.hasAudio {
                    let audio = Clip(assetID: source.id, timelineStart: Frames(start),
                                     duration: Frames(60),
                                     sourceStart: project.timeline.sourceTime(Frames(src)))
                    try project.insert(audio, onTrack: a1)
                }
            }
            // Syntetický přepis na assetu → zelené pásky řeči v pruhu T1.
            // Časy jsou ZDROJOVÉ: 0,5–1,5 s padne do prvního klipu (osa
            // 15–45, pod titulkem jmen), 8,2–9,4 s do třetího (zdroj
            // 8–10 s → osa 126–162) — tam pruh T1 nic nezakrývá a pásek
            // je vidět samostatně.
            try project.setTranscript(assetID: source.id, segments: [
                TranscriptSegment(start: SourceTime(seconds: 0.5),
                                  end: SourceTime(seconds: 1.5),
                                  text: "Syntetická řeč jedna"),
                TranscriptSegment(start: SourceTime(seconds: 8.2),
                                  end: SourceTime(seconds: 9.4),
                                  text: "Syntetická řeč dvě"),
            ])
            let t1 = project.ensureTitleTrack()
            let names = try project.makeTitle(text: "Anna a Petr", template: .names,
                                              at: .zero, duration: Frames(75))
            try project.addTitle(names, onTrack: t1)
            let date = try project.makeTitle(text: "12. září 2026 · Kroměříž",
                                             template: .dateAndPlace,
                                             at: Frames(75), duration: Frames(45))
            try project.addTitle(date, onTrack: t1)
            // Mezera 120–150 nechává vykouknout pásek řeči (osa 75–135) —
            // jinak by ho titulky zakryly a koukanec by neměl co vidět.
            let chapter = try project.makeTitle(text: "Kapitola: obřad",
                                                template: .chapter,
                                                at: Frames(150), duration: Frames(30))
            try project.addTitle(chapter, onTrack: t1)
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        // Oddálit, ať se celá 6s osa vejde do okna — koukanec má vidět
        // i pásek řeči u konce osy. Před přiřazením projektu, aby reload
        // proběhl už s novou geometrií.
        var geometry = timeline.geometry
        geometry.setZoom(2.5)
        timeline.geometry = geometry
        timeline.project = project
        timeline.setPlayheadFromUser(Frames(30))
        // Vybrat první titulek — koukanec vidí rámeček výběru i inspektor.
        if let first = timeline.project.timeline.tracks
            .first(where: { $0.kind == .title })?.titles.first {
            timeline.selectTitle(first.id)
        }

        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        for _ in 0..<40 where builtTimeline == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard builtTimeline != nil else { print("❌ kompozice nevznikla"); return }
        print("titulky na ose: \(timeline.project.titleCues().count)")
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// Mřížka jasů 8×8 snímku v daném čase (0–255): dekóduje přes
    /// `AVAssetImageGenerator` s nulovou tolerancí. Čas se zadává o půl
    /// snímku DOVNITŘ intervalu, aby se netrefovala hrana.
    /// <https://developer.apple.com/documentation/avfoundation/avassetimagegenerator>
    private func lumaGrid(url: URL, seconds: Double) async -> [Double]? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 192, height: 108)
        let time = CMTime(seconds: seconds, preferredTimescale: SourceTime.projectTimescale)
        guard let image = try? await generator.image(at: time).image else { return nil }

        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        var lumas: [Double] = []
        lumas.reserveCapacity(side * side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            lumas.append(0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1])
                + 0.114 * Double(pixels[i + 2]))
        }
        return lumas
    }

    /// CLI ověření přepisu: soubor se známou českou větou (say/nahrávka),
    /// vytiskne úseky s časy — správnost textu se posoudí proti předloze.
    func verifyTranscription(path: String?) async {
        guard let path else { print("❌ --transcribe-check potřebuje cestu ke zvuku"); return }
        do {
            let segments = try await transcription.transcribe(url: URL(fileURLWithPath: path))
            print("úseků: \(segments.count)")
            for segment in segments {
                print(String(format: "%7.2f–%-7.2f %@", segment.start.seconds,
                             segment.end.seconds, segment.text))
            }
        } catch {
            print("❌ přepis selhal: \(error)")
        }
    }

    // MARK: Synchronizace externího zvuku (fáze 7, modul 5)

    /// Vstup z kontextového menu: vybrat soubor z rekordéru a spustit sync.
    func syncExternalAudio(clipID: ClipID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Vyber nahrávku z rekordéru (WAV, M4A…), která patří k tomuhle klipu."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await performAudioSync(clipID: clipID, url: url) }
    }

    /// Najde posun nahrávky vůči ZDROJOVÉMU souboru klipu (celému — trim
    /// na výsledek nemá vliv) a položí ji na A2 tak, aby seděla s klipem
    /// na ose. Jen pro klipy bez rampy: zvuk položený lineárně by se
    /// s křivkou rozjel.
    @discardableResult
    func performAudioSync(clipID: ClipID, url: URL) async -> Bool {
        let project = timeline.project
        guard let clip = project.timeline.clip(clipID),
              let referenceAsset = project.asset(clip.assetID) else { return false }
        guard clip.speedRamp == nil else {
            status = "Klip má rychlostní křivku — synchronizuj na klip bez rampy."
            return false
        }

        status = "Porovnávám zvukové stopy…"
        do {
            let syncRate = 48_000.0
            guard let reference = try await MonoAudioReader.samples(
                    url: referenceAsset.originalURL, sampleRate: syncRate),
                  let candidate = try await MonoAudioReader.samples(
                    url: url, sampleRate: syncRate) else {
                status = "Jeden ze souborů nemá zvukovou stopu."
                return false
            }
            guard let match = WaveformSync.offset(reference: reference,
                                                  candidate: candidate,
                                                  sampleRate: syncRate) else {
                status = "Na synchronizaci je zvuku málo, nebo je to samé ticho."
                return false
            }

            // Nízká jistota = nahrávky si nejspíš neodpovídají. Zeptat se,
            // NIKDY nepoložit mlčky — pravidlo z návrhu `WaveformSync`.
            if match.confidence < 0.25 {
                let alert = NSAlert()
                alert.messageText = "Nahrávky si nejspíš neodpovídají"
                alert.informativeText = String(
                    format: "Jistota shody je jen %.0f %%. Položit zvuk přesto na nalezené místo?",
                    match.confidence * 100)
                alert.addButton(withTitle: "Zrušit")
                alert.addButton(withTitle: "Položit přesto")
                guard alert.runModal() == .alertSecondButtonReturn else {
                    status = "Synchronizace zrušena — nahrávky si neodpovídaly."
                    return false
                }
            }

            // Pozice začátku nahrávky na ose = začátek klipu + (posun −
            // zdrojový začátek klipu). Klip smí začít jen na celém snímku;
            // zbytek posunu se schová do sourceStart — sync tak drží
            // přesnost vzorků, ne snímků.
            let frameRate = Double(project.timeline.frameRate)
            var positionSeconds = Double(clip.timelineStart.count) / frameRate
                + (match.offsetSeconds - clip.sourceStart.seconds)
            var sourceStartSeconds = 0.0
            if positionSeconds < 0 {   // nahrávka přečnívá před začátek osy
                sourceStartSeconds = -positionSeconds
                positionSeconds = 0
            }
            let startFrame = Int((positionSeconds * frameRate).rounded())
            sourceStartSeconds = max(0, sourceStartSeconds
                + Double(startFrame) / frameRate - positionSeconds)

            let fileDuration = try await AVURLAsset(url: url).load(.duration).seconds
            let durationFrames = Int((fileDuration - sourceStartSeconds) * frameRate)
            guard durationFrames > 0 else {
                status = "Nahrávka končí dřív, než začíná osa — není co položit."
                return false
            }

            let asset = Asset(originalURL: url,
                              bookmark: ProjectStore.assetBookmark(for: url),
                              duration: SourceTime(seconds: fileDuration),
                              measuredFrameRate: frameRate,   // zvuk frekvenci nemá, neutrální
                              hasVideo: false,
                              hasAudio: true)
            guard timeline.placeSyncedAudio(asset: asset,
                                            timelineStart: Frames(startFrame),
                                            duration: Frames(durationFrames),
                                            sourceStart: SourceTime(seconds: sourceStartSeconds))
            else {
                status = "Na A2 není v místě synchronizace volno — uvolni ji a zkus to znovu."
                return false
            }
            status = String(format: "Zvuk položen na A2 — posun %+.3f s, jistota %.0f %%.",
                            match.offsetSeconds, match.confidence * 100)
            return true
        } catch {
            status = "Synchronizace selhala: \(error.localizedDescription)"
            return false
        }
    }

    /// CLI ověření syncu: WAV připravený se známým posunem proti prvnímu
    /// klipu; vytiskne, kam se položil, a čísla se porovnají s očekáváním.
    func verifySyncedAudio(path: String?) async {
        guard let path else { print("❌ --sync-check potřebuje cestu k WAV"); return }
        guard let clip = timeline.project.timeline.tracks.first?.clips.first else {
            print("❌ na ose není klip"); return
        }
        let ok = await performAudioSync(clipID: clip.id, url: URL(fileURLWithPath: path))
        print(status)
        guard ok,
              let a2 = timeline.project.timeline.tracks.last(where: { $0.kind == .audio }),
              let placed = a2.clips.first else { return }
        print(String(format: "A2 klip: start %d snímků, délka %d snímků, sourceStart %.4f s",
                     placed.timelineStart.count, placed.duration.count,
                     placed.sourceStart.seconds))
    }

    /// CLI ověření normalizace (fáze 7, modul 3): export s profilem Web
    /// a s A1 ztišenou na 0,5× — normalizace musí ztišení dorovnat a
    /// výsledný soubor musí měřit −14 LUFS. Přeměří externí skript.
    func verifyNormalizedExport() async {
        // CLI běh nesmí trvale přepsat uživatelské nastavení profilu.
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        // `--broadcast` přepne cíl na −23: s testovacím materiálem je gain
        // +5,9 dB těsně POD stropem špiček, takže se ověří i cesta, kdy se
        // cíle skutečně dosáhne (web −14 na tomhle materiálu strop utne).
        loudnessProfile = CommandLine.arguments.contains("--broadcast") ? .broadcast : .web
        if let a1 = timeline.project.timeline.tracks.first(where: { $0.kind == .audio }) {
            timeline.volumeDragBegan()
            timeline.volumeDragChanged(a1.id, volume: 0.5)
            timeline.volumeDragEnded()
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaNormalizeCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        await export(to: directory.appendingPathComponent("normalized.mp4"))
        print(status)
        print("NORM_CHECK_PATH=\(directory.path)")
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
        // Import = nový projekt, stávající osa se přepíše — tedy stejný
        // dotaz jako při otevírání a ukončování.
        guard confirmLosingUnsavedWork() else { return }
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

        // Import = NOVÝ neuložený projekt z naskenovaných klipů. Bookmark
        // per asset — bez něj by uložený projekt po restartu nesměl na
        // vlastní soubory sáhnout.
        var bookmarks: [URL: Data] = [:]
        for timing in clips {
            bookmarks[timing.url] = ProjectStore.assetBookmark(for: timing.url)
        }
        timeline.loadScannedClips(clips, bookmarks: bookmarks)
        projectStore.detachFromFile()
        projectStore.markCurrent(timeline.project)   // sken je baseline, ne „neuloženo"

        status = "\(clips.count) klipů. Vyber jeden a přehraj, nebo spusť měření."
        if selected == nil, let first = clips.first { await select(first) }
        startProxyGeneration()
    }

    /// Proxy na pozadí — ale ne pod CLI měřeními, soupeřily by o stroj.
    private func startProxyGeneration() {
        guard !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) else { return }
        let scanned = clips
        guard !scanned.isEmpty else { return }
        Task { [weak self] in
            await self?.proxies.ensureProxies(for: scanned) { original, proxy in
                self?.timeline.setProxy(proxy, forAssetWithOriginal: original)
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
        let project = timeline.project
        // Změna jen v mixu: kompozice platí, stačil živý mix (viz odběr).
        if builtTimeline != nil,
           builtTimelineShape == project.timeline.withDefaultAudioSettings() {
            return
        }
        compositionRebuild?.cancel()
        compositionRebuild = Task { [weak self] in
            guard let built = try? await CompositionBuilder.build(
                    project: project, usingProxies: project.usesProxies),
                  let self, !Task.isCancelled else { return }
            let frameRate = project.timeline.frameRate
            self.builtTimeline = built
            self.builtTimelineShape = project.timeline.withDefaultAudioSettings()
            self.playerContent = .timeline
            self.controller.loadComposition(built.composition, frameRate: frameRate,
                                            audioMix: built.audioMix(project: project),
                                            videoComposition: built.videoComposition)
            self.controller.seek(to: CompositionBuilder.time(of: self.timeline.playhead,
                                                             frameRate: frameRate))
        }
    }

    /// Změna hlasitosti za běhu: vymění mix na aktuálním itemu, přehrávání
    /// nezastaví. Jen když je kompozice platná a přehrává se osa.
    private func applyLiveAudioMix(_ project: Project) {
        guard let built = builtTimeline, playerContent == .timeline,
              builtTimelineShape == project.timeline.withDefaultAudioSettings()
        else { return }
        controller.applyAudioMix(built.audioMix(project: project))
    }

    // MARK: Hlava osy ↔ přehrávač (krok 6, od fáze 3 nad kompozicí)

    /// Osa → přehrávač: snímek osy JE čas kompozice, žádné hledání klipu.
    /// Mapování klip → zdroj dělá kompozice sama — postavil ji model.
    private func seekPlayer(toTimelineFrame frame: Frames) {
        let frameRate = timeline.project.timeline.frameRate
        if playerContent != .timeline {
            guard let built = builtTimeline else { return }
            playerContent = .timeline
            controller.loadComposition(built.composition, frameRate: frameRate,
                                       audioMix: built.audioMix(project: timeline.project),
                                       videoComposition: built.videoComposition)
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
    /// Model vlastní `KrasaApp` — menu (⌘S, ⌘O) potřebuje tentýž objekt.
    @ObservedObject var model: AppModel

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
            // Bez GUI: `--benchmark [cesty…]` změří v okně,
            // `--fullscreen [cesty…]` porovná okno s celou obrazovkou,
            // `--timeline-bench` výkon osy, `--roundtrip-project` formát.
            // Sandbox drží, přístup se obnovuje z uloženého bookmarku.
            let arguments = CommandLine.arguments.dropFirst()
            let explicit = arguments.filter { !$0.hasPrefix("--") }

            if arguments.contains(where: { $0.hasPrefix("--") }) {
                await model.restoreAndScan()
                if arguments.contains("--fullscreen") {
                    await model.runFullScreenComparison(only: Array(explicit))
                } else if arguments.contains("--benchmark") {
                    await model.runBenchmark(only: Array(explicit))
                } else if arguments.contains("--timeline-bench") {
                    await model.runTimelineStressBench()
                } else if arguments.contains("--roundtrip-project") {
                    model.verifyProjectRoundtrip()
                } else if arguments.contains("--autosave-check") {
                    model.verifyAutosave()
                } else if arguments.contains("--export-check") {
                    await model.verifyExport()
                } else if arguments.contains("--mix-check") {
                    await model.verifyAudioMixExport()
                } else if arguments.contains("--normalize-check") {
                    await model.verifyNormalizedExport()
                } else if arguments.contains("--sync-check") {
                    await model.verifySyncedAudio(path: explicit.first)
                } else if arguments.contains("--transcribe-check") {
                    await model.verifyTranscription(path: explicit.first)
                } else if arguments.contains("--srt-check") {
                    model.verifySRTExport()
                } else if arguments.contains("--transition-check") {
                    await model.verifyTransitionExport()
                } else if arguments.contains("--transition-gpu") {
                    await model.runTransitionGPUPlayback(enabled: !explicit.contains("off"))
                } else if arguments.contains("--title-demo") {
                    await model.runTitleDemo()
                } else if arguments.contains("--title-check") {
                    await model.verifyTitleExport()
                }
                NSApplication.shared.terminate(nil)
            } else if await model.reopenLastProject() {
                // Projekt z minula — sken se nespouští, timeline je ze souboru.
            } else if await model.offerUnsavedRecovery() {
                // Pád s neuloženým projektem — obnoveno ze zálohy.
            } else {
                await model.restoreAndScan()
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
            ProjectStatusRow(store: model.projectStore)

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

            if let progress = model.exportProgress {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                    Text("Exportuju… \(Int(progress * 100)) %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Exportovat film…") { model.exportMovie() }
                        .disabled(model.clips.isEmpty || model.isMeasuring)
                    // Hlasitost dodávky (fáze 7): normalizace na cílový
                    // profil, nebo nechat mix, jak je.
                    Picker("Hlasitost", selection: Binding(
                        get: { model.loudnessProfile?.rawValue ?? "none" },
                        set: { model.loudnessProfile = LoudnessProfile(rawValue: $0) })) {
                        Text("Bez normalizace").tag("none")
                        Text("Web / sociální sítě (−14 LUFS)").tag(LoudnessProfile.web.rawValue)
                        Text("Vysílání EBU R128 (−23 LUFS)").tag(LoudnessProfile.broadcast.rawValue)
                    }
                    .controlSize(.small)
                    .help("Export změří hlasitost celého filmu a dorovná ji na cíl. "
                        + "Zesílení je omezené špičkami (−1 dBFS) — bez limiteru se přes ně nejde dostat poctivě.")
                }
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
            // Titulkový overlay (fáze 8): kreslí se JEN když má co říct.
            // Prázdný overlay by přepnul WindowServer do skládání a
            // zkazil GPU baseline z fáze 1; při měření je schovaný celý
            // (chromeHidden/isMeasuring), takže benchmarky měří totéž
            // co dřív.
            ZStack(alignment: .bottom) {
                PlayerView(player: model.controller.player) { view in
                    model.attach(view)
                }
                if !model.chromeHidden && !model.isMeasuring {
                    // Grafické titulky (fáze 11) POD řečovými — řeč je
                    // dole u spodní hrany, grafika výš; pořadí v ZStacku
                    // rozhoduje jen při překryvu.
                    TitleOverlay(timeline: model.timeline)
                    SubtitleOverlay(timeline: model.timeline)
                }
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
                // Pás inspektoru (fáze 11, modul 3): editor rychlostní
                // křivky vybraného klipu, NEBO inspektor vybraného
                // titulku / úseku řeči — výběry se navzájem vylučují.
                // Pevná výška ze stejného důvodu jako osa pod ním.
                InspectorStrip(timeline: model.timeline)
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

/// Pás pod přehrávačem (fáze 11, modul 3): rozhoduje, co se v něm ukáže.
/// Vlastní malé view — `selectedTitle` žije na `TimelineController`, což je
/// vnořený `ObservableObject`, a ContentView by změnu neviděl (známá past).
private struct InspectorStrip: View {
    @ObservedObject var timeline: TimelineController

    var body: some View {
        if let titleID = timeline.selectedTitle,
           let title = timeline.project.timeline.titleClip(titleID) {
            TitleInspector(timeline: timeline, titleID: titleID, title: title)
        } else if let speech = timeline.selectedSpeech,
                  let text = speechText(speech) {
            SpeechInspector(timeline: timeline, selection: speech, currentText: text)
        } else {
            RampEditorPaneView(controller: timeline)
        }
    }

    private func speechText(_ speech: TimelineController.SpeechSelection) -> String? {
        guard let transcript = timeline.project.asset(speech.assetID)?.transcript,
              transcript.indices.contains(speech.segmentIndex) else { return nil }
        return transcript[speech.segmentIndex].text
    }
}

/// Inspektor vybraného titulku: text, šablona, zarovnání, smazání.
/// Text se píše ŽIVĚ (titulek se mění v náhledu při psaní) a undo krok
/// se skládá kolem fokusu — vzorec posuvníku hlasitosti.
private struct TitleInspector: View {
    @ObservedObject var timeline: TimelineController
    let titleID: TitleClipID
    let title: TitleClip
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Titulek")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { timeline.project.timeline.titleClip(titleID)?.text ?? "" },
                    set: { timeline.titleEditingChanged(titleID, text: $0) }))
                    .font(.body)
                    .focused($textFocused)
                    .onChange(of: textFocused) { focused in
                        if focused { timeline.titleEditingBegan() }
                        else { timeline.titleEditingEnded() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Šablona", selection: Binding(
                    get: { title.template },
                    set: { timeline.setTitleTemplate(titleID, template: $0) })) {
                    Text("Jména").tag(TitleTemplate.names)
                    Text("Datum a místo").tag(TitleTemplate.dateAndPlace)
                    Text("Kapitola").tag(TitleTemplate.chapter)
                    Text("Poděkování").tag(TitleTemplate.thanks)
                    Text("Prostý text").tag(TitleTemplate.plain)
                }
                .pickerStyle(.menu)

                Picker("Zarovnání", selection: Binding(
                    get: { title.alignment },
                    set: { timeline.setTitleAlignment(titleID, alignment: $0) })) {
                    Text("Vlevo").tag(TitleAlignment.leading)
                    Text("Na střed").tag(TitleAlignment.center)
                    Text("Vpravo").tag(TitleAlignment.trailing)
                }
                .pickerStyle(.menu)

                Button("Smazat titulek", role: .destructive) {
                    timeline.deleteTitle(titleID)
                }
            }
            .frame(width: 220)
        }
        .padding(10)
    }
}

/// Inspektor úseku titulků z řeči (splátka fáze 8). Návrh (koncept)
/// se drží lokálně a zapisuje při odchodu z pole nebo Enterem — živý
/// zápis nejde: prázdný text úsek MAŽE a při psaní je prázdno legální
/// mezistav.
private struct SpeechInspector: View {
    @ObservedObject var timeline: TimelineController
    let selection: TimelineController.SpeechSelection
    let currentText: String
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Titulek z řeči (přepis)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Text titulku", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { nowFocused in
                    if !nowFocused { commit() }
                }
            Text("Prázdný text úsek z přepisu smaže. Změna platí pro všechny "
                 + "klipy z téhož zdroje — přepis patří souboru, ne klipu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .onAppear { draft = currentText }
        .onChange(of: selection) { _ in draft = currentText }
    }

    private func commit() {
        guard draft != currentText else { return }
        timeline.setSpeechText(assetID: selection.assetID,
                               segmentIndex: selection.segmentIndex,
                               text: draft)
    }
}

/// Grafické titulky v náhledu (fáze 11, modul 2). Týž vzorec jako
/// `SubtitleOverlay`: vlastní malé view, hotové seřazené pole cues
/// přepočítávané jen při změně projektu, na tik hlavy jen filtr.
/// **Kreslí se JEN když má co říct** — prázdný overlay by přepnul
/// WindowServer do skládání a zkazil GPU baseline z fáze 1.
///
/// Šablona tady dostává KONKRÉTNÍ podobu (písmo, velikost, pozice) —
/// model nese jen její jméno. Velikosti jsou zlomky výšky náhledu,
/// aby titulek vypadal stejně v malém okně i na celé obrazovce.
private struct TitleOverlay: View {
    @ObservedObject var timeline: TimelineController
    @State private var cues: [TitleCue] = []

    var body: some View {
        GeometryReader { proxy in
            let active = cues.filter {
                $0.start <= timeline.playhead && timeline.playhead < $0.end
            }
            if !active.isEmpty {
                let h = proxy.size.height
                ZStack {
                    // Středové šablony pod sebou v pořadí cues — jména
                    // navrchu, datum pod nimi, když platí zároveň.
                    let centered = active.filter { $0.template != .plain }
                    if !centered.isEmpty {
                        VStack(spacing: h * 0.02) {
                            ForEach(centered, id: \.self) { cue in
                                styledText(cue, height: h)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Prostý text sedí v dolní třetině — nad řečovými
                    // titulky, které patří až ke spodní hraně.
                    let plain = active.filter { $0.template == .plain }
                    if !plain.isEmpty {
                        VStack(spacing: h * 0.015) {
                            ForEach(plain, id: \.self) { cue in
                                styledText(cue, height: h)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottom)
                        .padding(.bottom, h * 0.18)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { cues = timeline.project.titleCues() }
        .onReceive(timeline.$project
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)) { project in
            cues = project.titleCues()
        }
    }

    /// Text se stínem místo podkladové desky — grafický titulek leží na
    /// obraze, deska by z něj udělala řečový titulek.
    private func styledText(_ cue: TitleCue, height: CGFloat) -> some View {
        Text(cue.text)
            .font(font(for: cue.template, height: height))
            .multilineTextAlignment(textAlignment(cue.alignment))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.65), radius: height * 0.008, y: 1)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: frameAlignment(cue.alignment))
    }

    private func font(for template: TitleTemplate, height: CGFloat) -> Font {
        switch template {
        case .names:        return .system(size: height * 0.105, weight: .semibold, design: .serif)
        case .chapter:      return .system(size: height * 0.065, weight: .medium, design: .serif)
        case .thanks:       return .system(size: height * 0.060, weight: .regular, design: .serif)
        case .dateAndPlace: return .system(size: height * 0.045, weight: .regular, design: .serif)
        case .plain:        return .system(size: height * 0.045, weight: .medium)
        }
    }

    private func textAlignment(_ alignment: TitleAlignment) -> TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(_ alignment: TitleAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Titulek pod hlavou osy (fáze 8, modul 3). Vlastní malé view ze
/// stejného důvodu jako `TransportBar`: hlava se při přehrávání hýbe
/// 30×/s a překreslovat se smí jen tenhle proužek, ne celé okno.
///
/// Promítnuté titulky (`subtitleCues`) se přepočítávají jen při změně
/// projektu; na tik hlavy se jen hledá v hotovém seřazeném poli.
private struct SubtitleOverlay: View {
    @ObservedObject var timeline: TimelineController
    @State private var cues: [SubtitleCue] = []

    var body: some View {
        Group {
            if let text = currentText {
                Text(text)
                    .font(.system(size: 21, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { cues = timeline.project.subtitleCues() }
        .onReceive(timeline.$project
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)) { project in
            cues = project.subtitleCues()
        }
    }

    private var currentText: String? {
        let playhead = timeline.playhead
        // Překrývající se titulky (víc stop) se skládají pod sebe.
        let active = cues.filter { $0.start <= playhead && playhead < $0.end }
        guard !active.isEmpty else { return nil }
        return active.map(\.text).joined(separator: "\n")
    }
}

/// Jméno projektu a stav uložení (fáze 5). Vlastní malé view — vnořený
/// `ObservableObject` by se v těle `ContentView` nepřekresloval.
private struct ProjectStatusRow: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        Text(store.displayName + suffix)
            .font(.headline)
            .lineLimit(1)
            .help(store.fileURL?.path ?? "Projekt zatím není uložený — ⌘S ho uloží.")
    }

    private var suffix: String {
        if store.isDirty { return " · neuloženo" }
        guard let saved = store.lastSavedAt else { return " · ⌘S uloží" }
        return " · uloženo " + saved.formatted(date: .omitted, time: .shortened)
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
