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
        timeline.onFreezeFrameRequest = { [weak self] clipID in
            self?.freezeFrame(clipID: clipID)
        }
        timeline.onTranscribeRequest = { [weak self] clipID in
            Task { await self?.performTranscription(clipID: clipID) }
        }
        // JKL z osy → rychlost přehrávače (fáze 17).
        timeline.onShuttle = { [weak self] key in
            guard let self else { return }
            let step: PlaybackController.ShuttleStep
            switch key {
            case .forward: step = .forward
            case .backward: step = .backward
            case .pause: step = .pause
            }
            self.status = "Přehrávání: " + self.controller.shuttle(step)
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
        startSharpnessAnalysis()
    }

    /// Analýzy kvality na pozadí (fáze 15): ostrost a hluchost pro video
    /// assety projektu bez vzorků. Cache otiskem — druhé otevření je
    /// zadarmo. Fotky se přeskakují (jeden snímek nemá co „rozmazat
    /// pohybem" a hluchost je věc střihu, ne fotky) a pod CLI měřeními
    /// se nespouští (soupeřila by o stroj).
    func startSharpnessAnalysis() {
        guard !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") })
        else { return }
        let pending = timeline.project.assets.filter {
            $0.hasVideo && !$0.isStill
                && (timeline.sharpnessSamples[$0.id] == nil
                    || timeline.emptinessSamples[$0.id] == nil)
        }
        guard !pending.isEmpty else { return }
        Task { [weak self] in
            for asset in pending {
                let url = asset.url(usingProxies: false)
                if let samples = await SharpnessStore.shared.samples(for: url),
                   !samples.isEmpty {
                    self?.timeline.sharpnessSamples[asset.id] = samples
                }
                if let samples = await EmptinessStore.shared.samples(for: url),
                   !samples.isEmpty {
                    self?.timeline.emptinessSamples[asset.id] = samples
                }
            }
        }
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

    /// Zmrazí snímek pod hlavou (fáze 12, modul 3): vytáhne ho z ORIGINÁLU
    /// jako PNG do kontejneru a položí jako fotku na konec V1. Fotka, ne
    /// nulová rychlost — zákaz z plánu platí (invertibilita SpeedRampEngine).
    func freezeFrame(clipID: ClipID) {
        let project = timeline.project
        guard let clip = project.timeline.clip(clipID),
              let source = project.asset(clip.assetID),
              !source.isStill, source.hasVideo,
              clip.contains(frame: timeline.playhead) else { return }
        let offset = timeline.playhead - clip.timelineStart
        let sourceTime = project.sourceOffset(in: clip, atFrame: offset)
        status = "Zmrazuju snímek…"

        Task {
            do {
                let generator = AVAssetImageGenerator(
                    asset: AVURLAsset(url: source.originalURL))
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(value: sourceTime.value, timescale: sourceTime.timescale)
                let image = try await generator.image(at: time).image

                let directory = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("FreezeFrames", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let name = source.originalURL.deletingPathExtension().lastPathComponent
                let fileURL = directory.appendingPathComponent(
                    "\(name)-\(UUID().uuidString.prefix(8)).png")
                guard let destination = CGImageDestinationCreateWithURL(
                    fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    status = "Zmrazení snímku selhalo — PNG se nepodařilo založit."
                    return
                }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else {
                    status = "Zmrazení snímku selhalo — PNG se nepodařilo zapsat."
                    return
                }

                // V kontejneru aplikace — sandbox ho pustí i bez bookmarku.
                var updated = timeline.project
                guard let v1 = updated.timeline.tracks.first(where: { $0.kind == .video })?.id
                else { return }
                let photo = Asset.still(url: fileURL)
                updated.addAsset(photo)
                guard let still = try? updated.makeClip(assetID: photo.id,
                                                        at: updated.duration),
                      (try? updated.insert(still, onTrack: v1)) != nil else {
                    status = "Zmrazený snímek se nepodařilo položit na osu."
                    return
                }
                timeline.undo.record(timeline.project)
                timeline.project = updated
                timeline.selectClips([still.id])
                status = "Snímek zmrazen — fotka na konci osy (5 s, jde natáhnout)."
            } catch {
                status = "Zmrazení snímku selhalo: \(error.localizedDescription)"
            }
        }
    }

    /// Přidá fotky na konec V1 (fáze 12). Na rozdíl od importu klipů
    /// NEPŘEPISUJE osu — fotky jsou přírůstek do rozdělané práce.
    func addPhotos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.heic, .jpeg, .png]
        panel.allowsMultipleSelection = true
        panel.message = "Vyber fotky (HEIC, JPEG, PNG) — přidají se na konec obrazové stopy."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var project = timeline.project
        guard let v1 = project.timeline.tracks.first(where: { $0.kind == .video })?.id else {
            return
        }
        var cursor = project.duration
        var added = 0
        for url in panel.urls {
            // Bookmark hned — po restartu by sandbox fotku bez něj nepustil.
            let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            let photo = Asset.still(url: url, bookmark: bookmark)
            project.addAsset(photo)
            guard let clip = try? project.makeClip(assetID: photo.id, at: cursor),
                  (try? project.insert(clip, onTrack: v1)) != nil else { continue }
            cursor = clip.timelineEnd
            added += 1
        }
        guard added > 0 else { return }
        timeline.undo.record(timeline.project)
        timeline.project = project
        status = added == 1 ? "Přidána 1 fotka (5 s, délka jde natáhnout)."
                            : "Přidáno fotek: \(added) (po 5 s, délky jdou natáhnout)."
    }

    /// Hudba na A2 (fáze 14, modul 2): vybrat soubor, položit klip a na
    /// pozadí najít doby.
    func addMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Vyber hudbu (M4A, MP3, WAV…) — položí se na A2 a najdou se doby."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importMusic(url: url) }
    }

    /// Vlastní import: klip celé skladby na A2 (za poslední klip stopy),
    /// pak analýza dob `BeatDetectorem` a mřížka k assetu. Analýza čte
    /// mono 24 kHz — krok obálky vyjde ~10,7 ms jako na 48 kHz, ale FFT
    /// jsou poloviční a detekci basy a rytmu vyšší pásmo nechybí.
    func importMusic(url: URL) async {
        status = "Načítám hudbu…"
        do {
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            guard duration > 1 else {
                status = "Soubor je moc krátký na hudební podklad."
                return
            }
            guard let a2 = timeline.project.timeline.tracks.last(where: { $0.kind == .audio })
            else {
                status = "Projekt nemá zvukovou stopu pro hudbu."
                return
            }
            let asset = Asset(originalURL: url,
                              bookmark: ProjectStore.assetBookmark(for: url),
                              duration: SourceTime(seconds: duration),
                              measuredFrameRate: Double(timeline.project.timeline.frameRate),
                              hasVideo: false,
                              hasAudio: true)
            var project = timeline.project
            project.addAsset(asset)
            let start = a2.clips.last?.timelineEnd ?? .zero
            let clip = try project.makeClip(assetID: asset.id, at: start)
            try project.insert(clip, onTrack: a2.id)
            timeline.undo.record(timeline.project)
            timeline.project = project

            status = "Hudba na A2. Hledám tempo…"
            guard let samples = try await MonoAudioReader.samples(url: url, sampleRate: 24_000)
            else {
                status = "Hudba na A2, ale soubor nemá čitelný zvuk — doby nebudou."
                return
            }
            if let grid = BeatDetector.analyze(samples: samples, sampleRate: 24_000) {
                timeline.setBeatGrid(assetID: asset.id, grid)
                // Nízká jistota se PŘIZNÁVÁ — mřížka se nepodsouvá jako fakt.
                let warning = grid.confidence < 0.3
                    ? " Jistota je nízká — doby ber s rezervou."
                    : ""
                status = String(format: "Hudba na A2: %.1f BPM (jistota %.0f %%).%@",
                                grid.bpm, grid.confidence * 100, warning)
            } else {
                status = "Hudba na A2. Zřetelné tempo se nenašlo — doby nebudou "
                    + "(u ambientní hudby je to v pořádku)."
            }
        } catch {
            status = "Přidání hudby selhalo: \(error.localizedDescription)"
        }
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
                    // Strop: TRUE PEAK po zesílení ≤ −1 dBTP (fáze 16 —
                    // špička vzorků mezivzorkové špičky neviděla a „strop
                    // −1 dB" mohl v DA převodníku a AAC kodéru přetékat).
                    // Bez limiteru je tohle jediná poctivá ochrana proti
                    // clippingu — a když zasáhne, řekne se to, nezamlčí.
                    if scan.truePeakLinear > 0 {
                        let capDB = -1.0 - 20.0 * log10(scan.truePeakLinear)
                        if gainDB > capDB {
                            gainDB = capDB
                            loudnessNote = String(
                                format: " Hlasitost %.1f LUFS, gain omezen špičkami na %+.1f dB"
                                    + " (strop −1 dBTP) — na cíl %.0f LUFS nedosáhl.",
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

    /// CLI ověření fotek (fáze 12, modul 2): syntetická bílá čtvercová
    /// fotka → osa video (0–60) + fotka (60–150) → export. Kontroly:
    /// snímek fotky má jasný střed a černé boční pruhy (aspect-fit čtverce
    /// do 16:9), snímek videa fotkou dotčený není a délka sedí.
    func verifyPhotoExport() async {
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil

        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }

        // Syntetická fotka: bílý čtverec 1000×1000 (PNG do temp).
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaPhotoCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let photoURL = directory.appendingPathComponent("ctverec.png")
        guard writeWhiteSquarePNG(to: photoURL, side: 1000) else {
            print("❌ syntetickou fotku se nepodařilo zapsat"); return
        }

        var project = Project.empty()
        project.addAsset(source)
        let photo = Asset.still(url: photoURL)
        project.addAsset(photo)
        do {
            var video = try project.makeClip(assetID: source.id)
            video.duration = Frames(60)
            try project.insert(video, onTrack: project.timeline.tracks[0].id)
            var still = try project.makeClip(assetID: photo.id, at: Frames(60))
            still.duration = Frames(90)
            try project.insert(still, onTrack: project.timeline.tracks[0].id)
            // Druhá fotka s Ken Burns (modul 3): nájezd z celku do středu.
            // Na konci nájezdu je výřez celý uvnitř bílého čtverce, takže
            // z posledního snímku zmizí černé pruhy — to je měřitelné.
            var moving = try project.makeClip(assetID: photo.id, at: Frames(150))
            moving.duration = Frames(90)
            try project.insert(moving, onTrack: project.timeline.tracks[0].id)
            try project.setKenBurns(clipID: moving.id, KenBurns(
                start: .full,
                end: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project

        let url = directory.appendingPathComponent("photo_check.mp4")
        await export(to: url)
        print(status)

        guard let videoFrame = await lumaGrid(url: url, seconds: 30.5 / 30),
              let photoFrame = await lumaGrid(url: url, seconds: 100.5 / 30),
              let lastFrame = await lumaGrid(url: url, seconds: 149.5 / 30),
              let kbStart = await lumaGrid(url: url, seconds: 150.5 / 30),
              let kbEnd = await lumaGrid(url: url, seconds: 239.5 / 30) else {
            print("❌ nepodařilo se přečíst kontrolní snímky"); return
        }

        // Čtverec v 16:9: střední sloupce 2–5 bílé, krajní 0 a 7 černé.
        func columns(_ grid: [Double], _ cols: [Int]) -> Double {
            let cells = (0..<8).flatMap { row in cols.map { grid[row * 8 + $0] } }
            return cells.reduce(0, +) / Double(cells.count)
        }
        let center = columns(photoFrame, [2, 3, 4, 5])
        let bars = columns(photoFrame, [0, 7])
        print(String(format: "fotka: střed %.0f | pruhy %.0f", center, bars))
        print(center > 180 && bars < 25
              ? "✓ fotka je v exportu — bílý střed a černé pruhy aspect-fitu"
              : "❌ fotka v exportu nevypadá podle očekávání")
        print(columns(lastFrame, [2, 3, 4, 5]) > 180
              ? "✓ fotka drží až do posledního snímku (zero-order hold)"
              : "❌ konec klipu fotky není fotka")
        let videoMean = videoFrame.reduce(0, +) / Double(videoFrame.count)
        print(videoMean > 5 && columns(videoFrame, [0, 7]) < 200
              ? String(format: "✓ snímek videa vypadá jako video (průměr %.0f)", videoMean)
              : "❌ snímek videa je podezřelý")

        // Ken Burns: na začátku nájezdu celek (pruhy), na konci výřez celý
        // uvnitř bílého čtverce — pruhy zmizí a krajní sloupce zbělají.
        let kbStartBars = columns(kbStart, [0, 7])
        let kbEndBars = columns(kbEnd, [0, 7])
        print(String(format: "Ken Burns: pruhy na začátku %.0f | na konci %.0f",
                     kbStartBars, kbEndBars))
        print(kbStartBars < 25 && kbEndBars > 180
              ? "✓ Ken Burns jede — nájezd do středu vytlačil pruhy z obrazu"
              : "❌ Ken Burns v exportu nefunguje")
        print("PHOTO_CHECK_PATH=\(directory.path)")
    }

    /// CLI ověření freeze framu (fáze 12, modul 3): klip na ose, hlava
    /// na snímek 30 → zmrazit → na konci osy je fotka, jejíž PNG se
    /// obsahově shoduje se zdrojovým snímkem v čase 1 s.
    func verifyFreezeFrame() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        let clipID: ClipID
        do {
            var clip = try project.makeClip(assetID: source.id)
            clip.duration = Frames(90)
            try project.insert(clip, onTrack: project.timeline.tracks[0].id)
            clipID = clip.id
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        timeline.setPlayheadFromUser(Frames(30))

        freezeFrame(clipID: clipID)
        for _ in 0..<40 where !timeline.project.assets.contains(where: \.isStill) {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let photo = timeline.project.assets.first(where: \.isStill) else {
            print("❌ fotka po zmrazení nevznikla"); return
        }
        print("PNG: \(photo.originalURL.lastPathComponent)")
        guard FileManager.default.fileExists(atPath: photo.originalURL.path) else {
            print("❌ soubor fotky neexistuje"); return
        }
        guard let still = timeline.project.timeline.tracks[0].clips.last,
              still.assetID == photo.id, still.timelineStart == Frames(90) else {
            print("❌ klip fotky neleží na konci osy"); return
        }
        print("✓ fotka leží na konci osy (od snímku 90, délka \(still.duration.count))")

        // Obsah: PNG proti zdrojovému snímku v čase 1,000 s (hlava 30
        // → zdroj 1 s; obě cesty čtou zero-tolerance týž snímek).
        guard let sourceGrid = await lumaGrid(url: source.originalURL, seconds: 1.0),
              let imageSource = CGImageSourceCreateWithURL(photo.originalURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let photoGrid = Self.lumaGrid(image: image) else {
            print("❌ nepodařilo se přečíst snímky k porovnání"); return
        }
        let mae = zip(sourceGrid, photoGrid).map { abs($0 - $1) }.reduce(0, +)
            / Double(sourceGrid.count)
        print(String(format: "odchylka fotky od zdrojového snímku: %.2f", mae))
        print(mae < 4
              ? "✓ zmrazený snímek odpovídá obrazu pod hlavou"
              : "❌ zmrazený snímek NEODPOVÍDÁ obrazu pod hlavou")
    }

    /// CLI ověření barevných presetů (fáze 13, modul 2): dvojí export téže
    /// osy — s presety a bez nich. Osa: video klip (pas-through), červená
    /// fotka bez presetu, s ČB naplno, s ČB na 50 %, a prolínačka mezi
    /// barevnou a ČB fotkou. Červený čtverec má ZNÁMOU saturaci (max−min
    /// ≈ 255), takže efekt jde měřit čísly: ČB ~0, poloviční intenzita
    /// ~půlka, směs na střihu ~půlka. Snímky bez presetu se mezi exporty
    /// porovnávají po pixelech — vlastní compositor NESMÍ měnit, co barvit
    /// nemá (týž vzorec jako `--title-check`).
    func verifyColorExport() async {
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil

        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaColorCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let photoURL = directory.appendingPathComponent("cerveny_ctverec.png")
        guard writeSquarePNG(to: photoURL, side: 1000,
                             color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)) else {
            print("❌ syntetickou fotku se nepodařilo zapsat"); return
        }

        // Osa: video 0–60 | fotka 60–120 | fotka 120–180 | fotka 180–240,
        // prolínačka 30 snímků na střihu 120.
        var bare = Project.empty()
        bare.addAsset(source)
        let photo = Asset.still(url: photoURL)
        bare.addAsset(photo)
        var gradedClips: [(ClipID, ColorGrade)] = []
        do {
            let v1 = bare.timeline.tracks[0].id
            var video = try bare.makeClip(assetID: source.id)
            video.duration = Frames(60)
            try bare.insert(video, onTrack: v1)
            var previous: ClipID?
            for start in [60, 120, 180] {
                var still = try bare.makeClip(assetID: photo.id, at: Frames(start))
                still.duration = Frames(60)
                try bare.insert(still, onTrack: v1)
                if start == 120 { gradedClips.append((still.id, ColorGrade(
                    preset: .blackAndWhite, intensity: 1.0))) }
                if start == 180 { gradedClips.append((still.id, ColorGrade(
                    preset: .blackAndWhite, intensity: 0.5))) }
                if start == 120, let left = previous {
                    try bare.setTransition(.crossDissolve, duration: Frames(30),
                                           betweenLeft: left, andRight: still.id)
                }
                previous = still.id
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }

        var graded = bare
        do {
            for (clipID, grade) in gradedClips {
                try graded.setColorGrade(clipID: clipID, grade)
            }
        } catch {
            print("❌ nastavení presetů selhalo: \(error)"); return
        }

        let gradedURL = directory.appendingPathComponent("color_on.mp4")
        let bareURL = directory.appendingPathComponent("color_off.mp4")
        timeline.project = graded
        await export(to: gradedURL)
        print(status)
        timeline.project = bare
        await export(to: bareURL)
        print(status)

        // Časy o půl snímku DOVNITŘ intervalu (vzorec `lumaGrid`).
        // Snímek 30 video, 90 barevná fotka, 120 střed prolínačky,
        // 150 ČB naplno, 210 ČB na 50 %.
        guard let videoOn = await lumaGrid(url: gradedURL, seconds: 30.5 / 30),
              let videoOff = await lumaGrid(url: bareURL, seconds: 30.5 / 30),
              let photoOnLuma = await lumaGrid(url: gradedURL, seconds: 90.5 / 30),
              let photoOffLuma = await lumaGrid(url: bareURL, seconds: 90.5 / 30),
              let photoOn = await chromaGrid(url: gradedURL, seconds: 90.5 / 30),
              let photoOff = await chromaGrid(url: bareURL, seconds: 90.5 / 30),
              let mixOn = await chromaGrid(url: gradedURL, seconds: 120.5 / 30),
              let mixOff = await chromaGrid(url: bareURL, seconds: 120.5 / 30),
              let bwOn = await chromaGrid(url: gradedURL, seconds: 150.5 / 30),
              let bwOff = await chromaGrid(url: bareURL, seconds: 150.5 / 30),
              let halfOn = await chromaGrid(url: gradedURL, seconds: 210.5 / 30),
              let halfOff = await chromaGrid(url: bareURL, seconds: 210.5 / 30) else {
            print("❌ nepodařilo se přečíst kontrolní snímky"); return
        }

        func mae(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
        }
        // Čtverec v 16:9 — střední sloupce 2–5 (vzorec `--photo-check`).
        func center(_ grid: [Double]) -> Double {
            let cells = (0..<8).flatMap { row in [2, 3, 4, 5].map { grid[row * 8 + $0] } }
            return cells.reduce(0, +) / Double(cells.count)
        }

        // ① Pas-through: snímky bez presetu jsou mezi exporty shodné —
        // video klip (jiná cesta dekódování) i barevná fotka.
        let videoDiff = mae(videoOn, videoOff)
        let photoDiff = mae(photoOnLuma, photoOffLuma)
        let photoChromaDiff = abs(center(photoOn) - center(photoOff))
        print(String(format: "pas-through: video %.2f | fotka jas %.2f | fotka sat %.1f",
                     videoDiff, photoDiff, photoChromaDiff))
        print(videoDiff < 3 && photoDiff < 3 && photoChromaDiff < 12
              ? "✓ snímky bez presetu jsou mezi exporty shodné"
              : "❌ vlastní compositor mění snímky, které barvit nemá")

        // ② ČB naplno: saturace k nule (proti témuž snímku bez presetu).
        let bwCenter = center(bwOn), bwBase = center(bwOff)
        print(String(format: "ČB naplno: saturace %.0f (bez presetu %.0f)", bwCenter, bwBase))
        print(bwBase > 150 && bwCenter < 20
              ? "✓ černobílý preset odbarvuje"
              : "❌ černobílý preset v exportu nefunguje")

        // ③ Intenzita 50 %: saturace zhruba na půlce originálu.
        let halfCenter = center(halfOn), halfBase = center(halfOff)
        let halfRatio = halfBase > 0 ? halfCenter / halfBase : 0
        print(String(format: "ČB na 50 %%: saturace %.0f / %.0f = %.2f",
                     halfCenter, halfBase, halfRatio))
        print(halfRatio > 0.35 && halfRatio < 0.65
              ? "✓ intenzita presetu je lineární směs (50 % ≈ půlka saturace)"
              : "❌ intenzita 50 % nedává poloviční efekt")

        // ④ Preset + prolínačka: na střihu (opacity 0,5) se míchá barevná
        // a ČB fotka — saturace směsi ~půlka.
        let mixCenter = center(mixOn), mixBase = center(mixOff)
        let mixRatio = mixBase > 0 ? mixCenter / mixBase : 0
        print(String(format: "prolínačka s presetem: saturace %.0f / %.0f = %.2f",
                     mixCenter, mixBase, mixRatio))
        print(mixRatio > 0.35 && mixRatio < 0.65
              ? "✓ preset hraje i uvnitř prolínačky (směs barevné a ČB)"
              : "❌ preset uvnitř prolínačky nefunguje")
        print("COLOR_CHECK_PATH=\(directory.path)")
    }

    /// CLI měření GPU vlastního compositoru (fáze 13, modul 2): tři klipy
    /// 4K/30 bez přechodů, s presetem na všech („on" — celá osa jde přes
    /// `ColorVideoCompositor`) nebo bez („off" — přímá cesta bez video
    /// kompozice). Vzorec `--transition-gpu` včetně markerového souboru.
    func runColorGPUPlayback(enabled: Bool) async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
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
                if enabled {
                    try project.setColorGrade(clipID: video.id,
                                              ColorGrade(preset: .warmFilm, intensity: 1.0))
                }
                if source.hasAudio {
                    let audio = Clip(assetID: source.id, timelineStart: Frames(start),
                                     duration: Frames(60),
                                     sourceStart: project.timeline.sourceTime(Frames(src)))
                    try project.insert(audio, onTrack: a1)
                }
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
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaGPUPlayback.marker")
        try? "playing".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }
        controller.seek(to: .zero)
        controller.play()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if controller.player.timeControlStatus == .paused {
                controller.seek(to: .zero)
                controller.play()
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        controller.pause()
    }

    /// CLI ukázka fáze 13 (`--color-demo`): tři klipy, prostřední s ČB
    /// presetem a VYBRANÝ — inspektor ukazuje panel presetu, hlava stojí
    /// v přebarveném klipu. Nic neměří; koukanec pro oko a screenshot.
    func runColorDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        guard project.timeline.availableFrames(from: source.duration).count >= 305 else {
            print("❌ asset je krátký"); return
        }
        let v1 = project.timeline.tracks[0].id
        var middle: ClipID?
        do {
            for (start, src) in [(0, 0), (60, 120), (120, 240)] {
                let video = Clip(assetID: source.id, timelineStart: Frames(start),
                                 duration: Frames(60),
                                 sourceStart: project.timeline.sourceTime(Frames(src)))
                try project.insert(video, onTrack: v1)
                if start == 60 {
                    middle = video.id
                    try project.setColorGrade(clipID: video.id, ColorGrade(
                        preset: .blackAndWhite, intensity: 1.0))
                }
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        if let middle { timeline.selectClips([middle]) }
        timeline.setPlayheadFromUser(Frames(90))

        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// CLI ověření hudby (fáze 14, modul 2): syntetický klikový WAV se
    /// ZNÁMÝM tempem projde toutéž cestou jako hudba uživatele — import,
    /// analýza, mřížka k assetu, promítnutí na osu, magnet. 120 BPM na
    /// 30fps ose = doba PŘESNĚ každých 15 snímků, takže rozteče značek
    /// jsou tvrdá kontrola, ne přibližná.
    func verifyMusicImport() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaMusicCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let wav = directory.appendingPathComponent("klik120.wav")
        guard writeClickWAV(to: wav, bpm: 120, seconds: 12) else {
            print("❌ klikový WAV se nepodařilo zapsat"); return
        }

        timeline.project = Project.empty()
        await importMusic(url: wav)
        print(status)

        guard let asset = timeline.project.assets.first(where: { $0.beatGrid != nil }),
              let grid = asset.beatGrid else {
            print("❌ mřížka dob k assetu nedorazila"); return
        }
        print(String(format: "mřížka: %.2f BPM, jistota %.0f %%, první doba %.3f s",
                     grid.bpm, grid.confidence * 100, grid.firstBeatTime))
        print(abs(grid.bpm - 120) < 0.5
              ? "✓ tempo sedí (120 BPM)"
              : "❌ tempo nesedí")

        // Značky proti ideální mřížce 15 snímků od první doby: detekce smí
        // mít zbytkovou chybu tempa (~0,02 BPM ze zaokrouhlení obálky),
        // takže jednotlivá rozteč smí o snímek uhnout — ale odchylka se
        // NESMÍ SČÍTAT. Kumulativní drift je přesně to, co má regrese
        // v detektoru zabíjet.
        let marks = timeline.project.beatMarks()
        let drift = marks.enumerated()
            .map { abs($0.element.frame.count - (marks[0].frame.count + 15 * $0.offset)) }
            .max() ?? 0
        print("značek na ose: \(marks.count), největší odchylka od ideální mřížky: \(drift) sn.")
        print(marks.count == 24 && drift <= 1
              ? "✓ doby drží mřížku 15 snímků bez kumulativního driftu"
              : "❌ značky driftují nebo chybí")
        let downbeats = marks.filter(\.isDownbeat).count
        print(downbeats == (marks.count + 3) / 4
              ? "✓ raz každé čtyři doby (\(downbeats)×)"
              : "❌ takty nesedí (\(downbeats) z \(marks.count))")

        // Magnet: snímek vedle doby se přitáhne na dobu, druh .beat.
        guard let first = marks.first else { return }
        let candidates = timeline.geometry.snapCandidates(
            in: timeline.project.timeline,
            beats: marks.map(\.frame))
        let snapped = timeline.geometry.snap(first.frame - Frames(1), to: candidates)
        print(snapped.frame == first.frame && snapped.candidate?.kind == .beat
              ? "✓ magnet: snímek vedle doby se přitáhl na dobu"
              : "❌ magnet na dobu nefunguje")
        print("MUSIC_CHECK_PATH=\(directory.path)")
    }

    /// CLI ukázka fáze 14 (`--music-demo`): klikový WAV na A2 s mřížkou —
    /// jantarové doby v pravítku, „raz" vyšší. Koukanec pro oko a screenshot.
    func runMusicDemo() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaMusicCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let wav = directory.appendingPathComponent("klik110.wav")
        guard writeClickWAV(to: wav, bpm: 110, seconds: 30) else {
            print("❌ klikový WAV se nepodařilo zapsat"); return
        }
        timeline.project = Project.empty()
        await importMusic(url: wav)
        print(status)
        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// Klikový WAV (PCM16 mono 44,1 kHz): 8ms úder 1 kHz s dozníváním na
    /// každé době od 0,5 s — týž syntetický vzor jako testy `AudioEngine`.
    private func writeClickWAV(to url: URL, bpm: Double, seconds: Double) -> Bool {
        let rate = 44_100.0
        var samples = [Int16](repeating: 0, count: Int(seconds * rate))
        let clickLength = Int(0.008 * rate)
        let interval = 60.0 / bpm
        var t = 0.5
        while t < seconds {
            let start = Int(t * rate)
            for i in 0..<clickLength where start + i < samples.count {
                let envelope = 1.0 - Double(i) / Double(clickLength)
                let tone = sin(2.0 * .pi * 1000.0 * Double(i) / rate)
                samples[start + i] = Int16(max(-32_768, min(32_767,
                    Double(samples[start + i]) + 0.8 * envelope * tone * 32_767)))
            }
            t += interval
        }

        // WAV hlavička (RIFF little-endian, PCM16 mono).
        var data = Data()
        func append(_ string: String) { data.append(string.data(using: .ascii)!) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        append("RIFF"); append32(36 + dataSize); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
        append("data"); append32(dataSize)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return (try? data.write(to: url)) != nil
    }

    /// CLI ověření detekce neostrosti (fáze 15, modul 1): dvě syntetické
    /// fotky se ZNÁMOU pravdou — ostrá šachovnice a táž šachovnice
    /// rozmazaná Gaussem — projdou přes still movie mezisoubory toutéž
    /// cestou jako video (škálovací kompozice → NV12 → Laplaceova
    /// metrika). Ostrá musí skórovat řádově výš. K tomu reálný klip:
    /// počet vzorků ≈ délka × 3/s a druhé čtení jde z diskové cache.
    func verifySharpness() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaSharpCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let sharpURL = directory.appendingPathComponent("ostra.png")
        let blurredURL = directory.appendingPathComponent("rozmazana.png")
        guard writeCheckerboardPNG(to: sharpURL, side: 1000, blurRadius: 0),
              writeCheckerboardPNG(to: blurredURL, side: 1000, blurRadius: 12) else {
            print("❌ syntetické fotky se nepodařilo zapsat"); return
        }

        let canvas = CGSize(width: 3840, height: 2160)
        guard let sharpMovie = try? await StillMovieStore.shared.movieURL(
                forPhoto: sharpURL, canvas: canvas),
              let blurredMovie = try? await StillMovieStore.shared.movieURL(
                forPhoto: blurredURL, canvas: canvas) else {
            print("❌ still movie mezisoubory se nepodařilo vyrobit"); return
        }
        guard let sharpSamples = await SharpnessStore.shared.samples(for: sharpMovie),
              let blurredSamples = await SharpnessStore.shared.samples(for: blurredMovie),
              let sharpScore = sharpSamples.first?.score,
              let blurredScore = blurredSamples.first?.score else {
            print("❌ vzorky ostrosti nedorazily"); return
        }
        print(String(format: "šachovnice: ostrá %.0f | rozmazaná %.0f (poměr %.1f×)",
                     sharpScore, blurredScore,
                     blurredScore > 0 ? sharpScore / blurredScore : .infinity))
        print(sharpScore > blurredScore * 5
              ? "✓ metrika rozezná ostrý obraz od rozmazaného řádově"
              : "❌ metrika ostrost nerozeznává")

        // Reálný klip: hustota vzorků a cache.
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        let started = Date()
        guard let first = await SharpnessStore.shared.samples(for: source.originalURL) else {
            print("❌ analýza reálného klipu selhala"); return
        }
        let firstTime = Date().timeIntervalSince(started)
        let expected = source.duration.seconds * SharpnessStore.samplesPerSecond
        print(String(format: "reálný klip: %d vzorků za %.1f s (čekáno ~%.0f)",
                     first.count, firstTime, expected))
        print(abs(Double(first.count) - expected) <= 3
              ? "✓ hustota vzorků sedí (3/s)"
              : "❌ hustota vzorků nesedí")

        // Druhé čtení: nová instance store (paměť pryč) → jde z DISKU.
        let freshStore = SharpnessStore()
        let cachedStart = Date()
        let second = await freshStore.samples(for: source.originalURL)
        let cachedTime = Date().timeIntervalSince(cachedStart)
        print(String(format: "druhé čtení: %.3f s", cachedTime))
        print(second == first && cachedTime < max(0.5, firstTime / 4)
              ? "✓ disková cache vrací totéž a řádově rychleji"
              : "❌ cache nefunguje")
        print("SHARP_CHECK_PATH=\(directory.path)")
    }

    /// CLI ukázka fáze 15 (`--sharp-demo`): reálný klip na V1 a syntetické
    /// vzorky s propadem — oranžový a červený proužek na klipu. Koukanec
    /// pro oko a screenshot.
    func runSharpDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        do {
            var clip = try project.makeClip(assetID: source.id)
            clip.duration = min(clip.duration, Frames(300))
            try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        // Syntetické vzorky: zdravých 100, měkký propad 2–4 s, tvrdý 6–8 s.
        timeline.sharpnessSamples[source.id] = stride(from: 0.0, to: 10, by: 1.0 / 3)
            .map { t in
                if t >= 2, t < 4 { return SharpnessSample(time: t, score: 40) }
                if t >= 6, t < 8 { return SharpnessSample(time: t, score: 10) }
                return SharpnessSample(time: t, score: 100)
            }
        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// CLI ověření hluchosti (fáze 15, modul 2): tři still movie
    /// mezisoubory se ZNÁMOU pravdou — černý čtverec (tma), šumová
    /// „dekorace" (bohatý obraz) a reálný klip (hlasitý zvuk sekery).
    /// Still movie nemá zvukovou stopu = ticho z definice, takže:
    /// černý → hluchý (ticho + tma), šumový → NE (dekorace — klíčové
    /// pravidlo plánu), reálný klip → NE (zvuk žije).
    func verifyEmptiness() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaEmptyCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let blackURL = directory.appendingPathComponent("cerna.png")
        let noiseURL = directory.appendingPathComponent("dekorace.png")
        guard writeSquarePNG(to: blackURL, side: 1000,
                             color: CGColor(gray: 0.02, alpha: 1)),
              writeNoisePNG(to: noiseURL, side: 1000) else {
            print("❌ syntetické fotky se nepodařilo zapsat"); return
        }
        let canvas = CGSize(width: 3840, height: 2160)
        guard let blackMovie = try? await StillMovieStore.shared.movieURL(
                forPhoto: blackURL, canvas: canvas),
              let noiseMovie = try? await StillMovieStore.shared.movieURL(
                forPhoto: noiseURL, canvas: canvas) else {
            print("❌ still movie mezisoubory se nepodařilo vyrobit"); return
        }
        guard let blackSample = await EmptinessStore.shared.samples(for: blackMovie)?.first,
              let noiseSample = await EmptinessStore.shared.samples(for: noiseMovie)?.first else {
            print("❌ vzorky hluchosti nedorazily"); return
        }
        print(String(format: "černá: %.0f dBFS, jas %.0f, entropie %.2f b",
                     blackSample.loudnessDB, blackSample.brightness, blackSample.entropy))
        print(String(format: "dekorace: %.0f dBFS, jas %.0f, entropie %.2f b",
                     noiseSample.loudnessDB, noiseSample.brightness, noiseSample.entropy))
        let thresholds = (quietDB: -45.0, darkLuma: 40.0, lowEntropy: 3.5)
        func isEmpty(_ s: EmptinessSample) -> Bool {
            s.loudnessDB < thresholds.quietDB
                && (s.brightness < thresholds.darkLuma || s.entropy < thresholds.lowEntropy)
        }
        print(isEmpty(blackSample)
              ? "✓ tichá tma je hluché místo"
              : "❌ tichá tma neprošla jako hluchá")
        print(!isEmpty(noiseSample)
              ? "✓ tichá dekorace s bohatým obrazem NENÍ hluché místo"
              : "❌ dekorace se hlásí jako hluchá — pravidlo plánu porušeno")

        // Reálný klip: sekera je hlasitá — ticho nesmí projít.
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        guard let real = await EmptinessStore.shared.samples(for: source.originalURL),
              !real.isEmpty else {
            print("❌ analýza reálného klipu selhala"); return
        }
        let expected = source.duration.seconds * EmptinessStore.samplesPerSecond
        let emptyCount = real.filter(isEmpty).count
        let meanDB = real.map(\.loudnessDB).reduce(0, +) / Double(real.count)
        print(String(format: "reálný klip: %d vzorků (čekáno ~%.0f), průměr %.0f dBFS, hluchých %d",
                     real.count, expected, meanDB, emptyCount))
        print(abs(Double(real.count) - expected) <= 2
              ? "✓ hustota vzorků sedí (1/s)"
              : "❌ hustota vzorků nesedí")
        print(emptyCount == 0
              ? "✓ hlasitý klip nemá žádná hluchá místa"
              : "⚠️ hlasitý klip má \(emptyCount) hluchých vzorků — zkontrolovat prahy")
        print("EMPTY_CHECK_PATH=\(directory.path)")
    }

    /// CLI ukázka F15/2 (`--empty-demo`): klip se syntetickými vzorky —
    /// šedý proužek hluchosti při spodní hraně, oranžový ostrosti nahoře.
    func runEmptyDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        do {
            var clip = try project.makeClip(assetID: source.id)
            clip.duration = min(clip.duration, Frames(300))
            try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        // Oddálit, ať jsou vidět OBĚ značky — kapsa leží až v 5.–10. sekundě.
        var geometry = timeline.geometry
        geometry.setZoom(2.5)
        timeline.geometry = geometry
        timeline.project = project
        // Ostrost: měkký propad 1–3 s. Hluchost: kapsa 5–10 s.
        timeline.sharpnessSamples[source.id] = stride(from: 0.0, to: 10, by: 1.0 / 3)
            .map { t in
                SharpnessSample(time: t, score: (t >= 1 && t < 3) ? 40 : 100)
            }
        timeline.emptinessSamples[source.id] = (0..<10).map { second in
            let t = Double(second)
            return t >= 5
                ? EmptinessSample(time: t, loudnessDB: -60, brightness: 10,
                                  entropy: 2, motion: 3)
                : EmptinessSample(time: t, loudnessDB: -20, brightness: 120,
                                  entropy: 6.5, motion: 8)
        }
        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// CLI ověření zvukových fade (fáze 16, modul 1): klip se zvukem
    /// dostane nájezd 1 s a dojezd 1 s, exportuje se a RMS profil
    /// výsledného zvuku musí na hranách klesat — a stejný export BEZ
    /// fade musí mít hrany plné (kontrola, že se neměří artefakt).
    func verifyAudioFades() async {
        let savedProfile = loudnessProfile
        defer { loudnessProfile = savedProfile }
        loudnessProfile = nil

        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && $0.hasAudio && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný asset se zvukem"); return
        }
        var bare = Project.empty()
        bare.addAsset(source)
        let audioClipID: ClipID
        do {
            let (video, audio) = try bare.makeLinkedClips(assetID: source.id)
            var v = video; v.duration = Frames(120)
            var a = audio; a.duration = Frames(120)
            try bare.insert(v, onTrack: bare.timeline.tracks[0].id)
            try bare.insert(a, onTrack: bare.timeline.tracks[1].id)
            audioClipID = a.id
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        var faded = bare
        do {
            try faded.setAudioFades(clipID: audioClipID,
                                    AudioFades(fadeIn: Frames(30), fadeOut: Frames(30)))
        } catch {
            print("❌ nastavení fade selhalo: \(error)"); return
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaFadeCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let fadedURL = directory.appendingPathComponent("fade_on.mp4")
        let bareURL = directory.appendingPathComponent("fade_off.mp4")
        timeline.project = faded
        await export(to: fadedURL)
        print(status)
        timeline.project = bare
        await export(to: bareURL)
        print(status)

        func rmsProfile(_ url: URL) async -> (head: Double, middle: Double, tail: Double)? {
            guard let audio = try? await MonoAudioReader.samples(url: url,
                                                                 sampleRate: 48_000),
                  audio.count > 48_000 * 3 else { return nil }
            func rms(_ range: Range<Int>) -> Double {
                let slice = audio[range.clamped(to: audio.indices)]
                guard !slice.isEmpty else { return 0 }
                let sum = slice.reduce(0.0) { $0 + Double($1) * Double($1) }
                return (sum / Double(slice.count)).squareRoot()
            }
            // Kraje uvnitř fade (0,1–0,5 s a poslední 0,5–0,1 s), střed mimo.
            let n = audio.count
            return (rms(4_800..<24_000),
                    rms(n / 2 - 24_000..<n / 2 + 24_000),
                    rms(n - 24_000..<n - 4_800))
        }
        guard let on = await rmsProfile(fadedURL), let off = await rmsProfile(bareURL),
              off.middle > 0 else {
            print("❌ nepodařilo se přečíst zvuk exportů"); return
        }
        let headRatio = on.head / max(off.head, 1e-9)
        let tailRatio = on.tail / max(off.tail, 1e-9)
        print(String(format: "hrany s fade proti bez: začátek %.2f, konec %.2f "
                     + "(střed %.2f)", headRatio, tailRatio, on.middle / off.middle))
        print(headRatio < 0.6 && tailRatio < 0.6
              ? "✓ nájezd i dojezd v exportu skutečně zeslabují"
              : "❌ fade v exportu neshledán")
        print(on.middle / off.middle > 0.9
              ? "✓ střed klipu zůstává nedotčený"
              : "❌ fade sahá doprostřed klipu")
        print("FADE_CHECK_PATH=\(directory.path)")
    }

    /// CLI ukázka fáze 16 (`--transition-demo`): dva přechody na ose,
    /// první VYBRANÝ klikem do těla — koukanec vidí žlutý rámeček
    /// lichoběžníku (drobnost z koukanců F10).
    func runTransitionSelectionDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        var first: TransitionID?
        do {
            var ids: [ClipID] = []
            for (start, src) in [(0, 0), (60, 120), (120, 240)] {
                let clip = Clip(assetID: source.id, timelineStart: Frames(start),
                                duration: Frames(60),
                                sourceStart: project.timeline.sourceTime(Frames(src)))
                try project.insert(clip, onTrack: project.timeline.tracks[0].id)
                ids.append(clip.id)
            }
            first = try project.setTransition(.crossDissolve, duration: Frames(30),
                                              betweenLeft: ids[0], andRight: ids[1])
            _ = try project.setTransition(.dipToBlack, duration: Frames(20),
                                          betweenLeft: ids[1], andRight: ids[2])
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        var geometry = timeline.geometry
        geometry.setZoom(6)
        timeline.geometry = geometry
        timeline.project = project
        if let first { timeline.selectTransition(first) }
        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// Kvantitativní kontrola fáze 17, modulu 1 (`--jkl-check`).
    ///
    /// Tři měření, každé odpovídá jedné otázce plánu:
    ///  A) drží žebřík JKL konvenci z NLE (L zrychluje, J tlumí, K sráží)?
    ///  B) co náš přehrávač NA NAŠÍ KOMPOZICI opravdu umí — `canPlayReverse`
    ///     a spol. se mají ZEPTAT, ne předpokládat — a jede čas při každé
    ///     rychlosti skutečně tak, jak slibuje?
    ///  C) zůstane hlava při přehrávání celé osy vidět a kolikrát se přitom
    ///     osa hne? (Stránkování se pozná podle toho, že skoků je řádově
    ///     míň než tiků hlavy.)
    func verifyShuttleAndFollow() async {
        print("=== A) žebřík JKL ===")
        var ladderOK = true
        controller.setShuttleRate(0)
        // Bez načteného itemu přehrávač nic neumí — žebřík ale musí držet,
        // to je čistá logika. Rychlost se čte z `shuttleRate`.
        let script: [(TimelineController.ShuttleKey, Double)] = [
            (.forward, 1), (.forward, 2), (.forward, 4), (.forward, 8), (.forward, 8),
            (.backward, 4), (.backward, 2), (.backward, 1), (.backward, 0),
            (.backward, -1), (.backward, -2), (.pause, 0), (.backward, -1),
        ]
        for (key, expected) in script {
            let step: PlaybackController.ShuttleStep
            switch key {
            case .forward: step = .forward
            case .backward: step = .backward
            case .pause: step = .pause
            }
            controller.shuttle(step)
            if controller.shuttleRate != expected {
                print("❌ po \(key) čekáno \(expected)×, je \(controller.shuttleRate)×")
                ladderOK = false
            }
        }
        controller.setShuttleRate(0)
        print(ladderOK ? "✅ žebřík 1→2→4→8 se stropem, J tlumí, K sráží na pauzu"
                       : "❌ žebřík nesedí")

        print("\n=== B) co přehrávač na kompozici umí ===")
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset — pusť s cestou ke klipům"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        guard project.timeline.availableFrames(from: source.duration).count >= 600 else {
            print("❌ asset je kratší než 20 s"); return
        }
        do {
            let clip = Clip(assetID: source.id, timelineStart: .zero, duration: Frames(600),
                            sourceStart: .zero)
            try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        for _ in 0..<40 where builtTimeline == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let built = builtTimeline else { print("❌ kompozice nevznikla"); return }
        controller.loadComposition(built.composition,
                                   frameRate: project.timeline.frameRate,
                                   audioMix: built.audioMix(project: project),
                                   videoComposition: built.videoComposition)
        for _ in 0..<40 where controller.player.currentItem?.status != .readyToPlay {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let item = controller.player.currentItem, item.status == .readyToPlay else {
            print("❌ item se nepřipravil"); return
        }
        print("zdroj: \(source.originalURL.lastPathComponent) (proxy: \(source.proxyURL != nil ? "ANO" : "NE"))")
        print("canPlayReverse: \(item.canPlayReverse)   canPlayFastReverse: \(item.canPlayFastReverse)")
        print("canPlayFastForward: \(item.canPlayFastForward)   canPlaySlowForward: \(item.canPlaySlowForward)")

        /// Změří, kolik SEKUND času se ujelo za jednu sekundu reálného času.
        func measure(rate: Double, from seconds: Double) async -> (moved: Double, fallback: Bool) {
            controller.setShuttleRate(0)
            controller.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            try? await Task.sleep(nanoseconds: 700_000_000)
            let before = controller.player.currentTime().seconds
            let description = controller.setShuttleRate(rate)
            let fallback = description.contains("krokováním")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let after = controller.player.currentTime().seconds
            controller.setShuttleRate(0)
            return (after - before, fallback)
        }

        for rate in [1.0, 2.0, 4.0, -1.0, -2.0] {
            let start = rate < 0 ? 15.0 : 2.0
            let (moved, fallback) = await measure(rate: rate, from: start)
            let ratio = moved / rate
            let verdict = ratio > 0.5 && ratio < 1.5 ? "✅" : "⚠️"
            print(String(format: "%@ %+.0f× → za 1 s reálného času ujeto %+.2f s (%.0f %% slíbeného)%@",
                         verdict, rate, moved, ratio * 100,
                         fallback ? "  [krokováním, bez zvuku]" : ""))
        }
        controller.setShuttleRate(0)

        // Krokovací fallback vynuceně: na téhle kompozici přehrávač reverse
        // umí, takže by se ta větev jinak nespustila ani jednou.
        controller.forcesSteppingFallback = true
        for rate in [-1.0, -2.0] {
            let (moved, fallback) = await measure(rate: rate, from: 15.0)
            let ratio = moved / rate
            print(String(format: "%@ %+.0f× vynuceně krokováním → ujeto %+.2f s (%.0f %% slíbeného)%@",
                         ratio > 0.5 && ratio < 1.5 ? "✅" : "⚠️", rate, moved, ratio * 100,
                         fallback ? "" : "  ❌ fallback se nespustil!"))
        }
        controller.forcesSteppingFallback = false
        controller.setShuttleRate(0)

        print("\n=== C) osa sleduje hlavu ===")
        // Simulace přehrávání 20 s osy v okně 900 bodů při zoomu 4 b/snímek:
        // do okna se vejde 225 snímků, osa má 600.
        var geometry = TimelineGeometry(pointsPerFrame: 4)
        let viewport = 900.0
        let maxScroll = geometry.contentWidth(of: project) - viewport
        var scrollX = 0.0
        var jumps = 0
        var invisible = 0
        for frame in 0...600 {
            let head = geometry.x(for: Frames(frame))
            if head < scrollX || head > scrollX + viewport { invisible += 1 }
            if let target = geometry.scrollToKeep(playhead: Frames(frame), scrollX: scrollX,
                                                  viewportWidth: viewport, maxScrollX: maxScroll) {
                scrollX = target
                jumps += 1
            }
        }
        print("601 tiků hlavy → \(jumps) skoků osy, hlava mimo okno \(invisible)× "
              + "(scroll skončil na \(Int(scrollX)) b z \(Int(maxScroll)) b)")
        print(jumps <= 5 && invisible == 0
              ? "✅ stránkuje se (ne plynulé centrování) a hlava je vidět pořád"
              : "❌ čekány jednotky skoků a nula neviditelných tiků")

        // A totéž s odzoomováním, kde se celá osa do okna vejde: nesmí
        // se scrollovat vůbec.
        geometry.setZoom(1)
        var stillScroll = 0.0
        var stillJumps = 0
        for frame in 0...600 {
            if let target = geometry.scrollToKeep(playhead: Frames(frame), scrollX: stillScroll,
                                                  viewportWidth: viewport,
                                                  maxScrollX: max(0, geometry.contentWidth(of: project) - viewport)) {
                stillScroll = target
                stillJumps += 1
            }
        }
        print(stillJumps == 0 ? "✅ odzoomovaná osa se pod hlavou nehne (0 skoků)"
                              : "❌ odzoomovaná osa skákala \(stillJumps)×")

        print("\n=== D) totéž v běžícím okně ===")
        // Část C ověřuje matematiku, tahle napojení: hne se v reálné ose
        // opravdu scroll, nebo se výsledek funkce ztratí cestou do AppKitu?
        var live = timeline.geometry
        live.setZoom(4)
        timeline.geometry = live
        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while timelinePane?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let pane = timelinePane, let window = pane.window else {
            print("❌ osa se nedostala do okna"); return
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let clipView = pane.scrollView.contentView
        // Nejdřív na začátek osy a nechat scroll dojet — teprve pak měřit
        // výchozí pozici, jinak by se do rozdílu započítal skok ze seeku.
        controller.seek(to: .zero)
        timeline.setPlayheadFromPlayback(.zero)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let before = Double(clipView.bounds.origin.x)
        controller.play()
        var headAlwaysVisible = true
        var samples = 0
        let playDeadline = Date().addingTimeInterval(12)
        while Date() < playDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let headX = timeline.geometry.x(for: timeline.playhead)
            let origin = Double(clipView.bounds.origin.x)
            let width = Double(clipView.bounds.width)
            if headX < origin - 1 || headX > origin + width + 1 { headAlwaysVisible = false }
            samples += 1
        }
        controller.pause()
        let after = Double(clipView.bounds.origin.x)
        print(String(format: "scroll osy: %.0f b → %.0f b za 12 s přehrávání (okno %.0f b, %d vzorků)",
                     before, after, Double(clipView.bounds.width), samples))
        print(after > before ? "✅ osa se za hlavou opravdu posunula"
                             : "❌ osa stojí — funkce počítá, ale scroll se nepohnul")
        print(headAlwaysVisible ? "✅ hlava byla po celou dobu ve výřezu"
                                : "❌ hlava z okna vypadla")

        // Klávesy: části A–B testují `shuttle` přímo na přehrávači, tohle
        // ověřuje CELÝ řetězec keyDown v ose → hook controlleru → rychlost.
        func press(_ character: String, keyCode: UInt16) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: keyCode) else { return }
            pane.documentView.keyDown(with: event)
        }
        controller.setShuttleRate(0)
        press("l", keyCode: 37); press("l", keyCode: 37)     // L, L → 2×
        let afterL = controller.shuttleRate
        press("j", keyCode: 38)                              // J → 1×
        let afterJ = controller.shuttleRate
        press("k", keyCode: 40)                              // K → pauza
        let afterK = controller.shuttleRate
        controller.setShuttleRate(0)
        print(afterL == 2 && afterJ == 1 && afterK == 0
              ? "✅ klávesy z osy dojdou k přehrávači (LL→2×, J→1×, K→pauza)"
              : "❌ klávesy nedošly: LL→\(afterL)×, J→\(afterJ)×, K→\(afterK)×")
    }

    /// CLI ukázka fáze 16 (`--fade-demo`): zvukový klip s klíny fade.
    func runFadeDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && $0.hasAudio && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný asset se zvukem"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        do {
            let (video, audio) = try project.makeLinkedClips(assetID: source.id)
            var v = video; v.duration = Frames(240)
            var a = audio; a.duration = Frames(240)
            try project.insert(v, onTrack: project.timeline.tracks[0].id)
            try project.insert(a, onTrack: project.timeline.tracks[1].id)
            try project.setAudioFades(clipID: a.id,
                                      AudioFades(fadeIn: Frames(45), fadeOut: Frames(75)))
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        if let host = await waitForPlayerWindow() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 25_000_000_000)
    }

    /// Šum jako PNG — „dekorace": bohatý, prosvětlený obraz s vysokou
    /// entropií pro `--empty-check`.
    private func writeNoisePNG(to url: URL, side: Int) -> Bool {
        var state: UInt64 = 0x9E3779B9
        func next() -> UInt8 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return UInt8(truncatingIfNeeded: state)
        }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 255                       // alfa (little-endian BGRA)
            pixels[i + 1] = next()
            pixels[i + 2] = next()
            pixels[i + 3] = next()
        }
        let ok = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
            return context.makeImage()
        }
        guard let image = ok,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Šachovnice jako PNG, volitelně rozmazaná Gaussem — syntetická
    /// fotka se známou ostrostí pro `--sharp-check`.
    private func writeCheckerboardPNG(to url: URL, side: Int, blurRadius: Double) -> Bool {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
        let cell = 25
        for row in 0..<(side / cell) {
            for column in 0..<(side / cell) where (row + column) % 2 == 0 {
                context.setFillColor(CGColor(gray: 0.95, alpha: 1))
                context.fill(CGRect(x: column * cell, y: row * cell,
                                    width: cell, height: cell))
            }
        }
        guard var image = context.makeImage() else { return false }

        if blurRadius > 0 {
            let blurred = CIImage(cgImage: image)
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
                .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
            guard let rendered = CIContext().createCGImage(blurred, from: blurred.extent)
            else { return false }
            image = rendered
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Bílý čtverec jako PNG — syntetická fotka pro `--photo-check`.
    private func writeWhiteSquarePNG(to url: URL, side: Int) -> Bool {
        writeSquarePNG(to: url, side: side, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    }

    /// Jednobarevný čtverec jako PNG — `--color-check` potřebuje sytou
    /// barvu se ZNÁMOU saturací, aby šel efekt presetu měřit čísly.
    private func writeSquarePNG(to url: URL, side: Int, color: CGColor) -> Bool {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
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
        return Self.lumaGrid(image: image)
    }

    /// Mřížka SATURACE 8×8 (max−min složek RGB, 0–255) — měří efekt
    /// barevných presetů (`--color-check`): ČB má saturaci ~0, poloviční
    /// intenzita ~polovinu originálu. Jas by to neviděl.
    private func chromaGrid(url: URL, seconds: Double) async -> [Double]? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 192, height: 108)
        let time = CMTime(seconds: seconds, preferredTimescale: SourceTime.projectTimescale)
        guard let image = try? await generator.image(at: time).image,
              let pixels = Self.pixelGrid(image: image) else { return nil }
        var chromas: [Double] = []
        chromas.reserveCapacity(64)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            chromas.append(max(r, g, b) - min(r, g, b))
        }
        return chromas
    }

    /// Surové RGBA pixely mřížky 8×8 — společný základ jasové i saturační
    /// mřížky.
    private static func pixelGrid(image: CGImage) -> [UInt8]? {
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
        return ok ? pixels : nil
    }

    /// Táž mřížka z hotového obrázku — pro PNG z freeze framu.
    private static func lumaGrid(image: CGImage) -> [Double]? {
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

    // MARK: Správa modelu přepisu (fáze 16, modul 3)

    /// Smazání se PTÁ — model se stahuje 1,5 GB po síti a uživatel to
    /// nemusí chtít zopakovat kvůli překliku.
    func deleteWhisperModel() {
        let alert = NSAlert()
        alert.messageText = "Smazat model přepisu?"
        alert.informativeText = "Uvolní se ~1,5 GB. Při dalším vytváření titulků "
            + "z řeči se model stáhne znovu — to chce síť a trpělivost."
        alert.addButton(withTitle: "Zrušit")
        alert.addButton(withTitle: "Smazat")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        transcription.deleteModel()
        status = "Model přepisu smazán."
    }

    /// Přemístění na jiný disk — soubory se přesunou, nestahují znovu.
    func relocateWhisperModel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Uložit model sem"
        panel.message = "Vyber složku pro model přepisu (~1,5 GB) — klidně na "
            + "externím disku. Stažené soubory se přesunou."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcription.relocateModel(to: url)
        status = "Model přepisu: \(transcription.modelLocationName)"
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
        startSharpnessAnalysis()
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
                } else if arguments.contains("--photo-check") {
                    await model.verifyPhotoExport()
                } else if arguments.contains("--freeze-check") {
                    await model.verifyFreezeFrame()
                } else if arguments.contains("--color-check") {
                    await model.verifyColorExport()
                } else if arguments.contains("--color-gpu") {
                    await model.runColorGPUPlayback(enabled: !explicit.contains("off"))
                } else if arguments.contains("--color-demo") {
                    await model.runColorDemo()
                } else if arguments.contains("--music-check") {
                    await model.verifyMusicImport()
                } else if arguments.contains("--music-demo") {
                    await model.runMusicDemo()
                } else if arguments.contains("--sharp-check") {
                    await model.verifySharpness()
                } else if arguments.contains("--sharp-demo") {
                    await model.runSharpDemo()
                } else if arguments.contains("--empty-check") {
                    await model.verifyEmptiness()
                } else if arguments.contains("--empty-demo") {
                    await model.runEmptyDemo()
                } else if arguments.contains("--fade-check") {
                    await model.verifyAudioFades()
                } else if arguments.contains("--fade-demo") {
                    await model.runFadeDemo()
                } else if arguments.contains("--transition-demo") {
                    await model.runTransitionSelectionDemo()
                } else if arguments.contains("--jkl-check") {
                    await model.verifyShuttleAndFollow()
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

            WhisperModelControls(transcription: model.transcription,
                                 onRelocate: { model.relocateWhisperModel() },
                                 onDelete: { model.deleteWhisperModel() })

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
        } else if let still = selectedStillClip() {
            // Fotka: editor křivky by tu neměl co dělat (rampa na fotce
            // je zakázaná) — místo něj Ken Burns (fáze 12, modul 3)
            // a barevný preset (fáze 13, modul 3).
            HStack(spacing: 0) {
                PhotoInspector(timeline: timeline, clipID: still)
                Divider()
                ColorGradePanel(timeline: timeline, clipID: still)
                    .frame(width: 260)
            }
        } else if let video = selectedVideoClip() {
            // Video klip: editor křivky + panel barevného presetu vedle.
            HStack(spacing: 0) {
                RampEditorPaneView(controller: timeline)
                Divider()
                ColorGradePanel(timeline: timeline, clipID: video)
                    .frame(width: 260)
            }
        } else {
            RampEditorPaneView(controller: timeline)
        }
    }

    private func selectedStillClip() -> ClipID? {
        guard timeline.selection.count == 1,
              let id = timeline.selection.first,
              let clip = timeline.project.timeline.clip(id),
              timeline.project.asset(clip.assetID)?.isStill == true else { return nil }
        return id
    }

    /// Jediný vybraný klip na OBRAZOVÉ stopě (a ne fotka — ta má vlastní
    /// větev). Preset patří jen obrazu; u zvukového klipu panel nemá smysl.
    private func selectedVideoClip() -> ClipID? {
        guard timeline.selection.count == 1,
              let id = timeline.selection.first,
              let at = timeline.project.timeline.locate(id),
              timeline.project.timeline.tracks[at.trackIndex].kind == .video
        else { return nil }
        return id
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

/// Inspektor fotky (fáze 12, modul 3): Ken Burns jako pohyb + zoom.
/// Výřezy drží poměr plátna (v normalizovaných jednotkách w == h) a sedí
/// ve středu — nájezd/odjezd, klasika svatebních prezentací. Volné
/// obdélníky až bude důvod; model je umí už teď.
private struct PhotoInspector: View {
    @ObservedObject var timeline: TimelineController
    let clipID: ClipID

    private enum Motion: String, CaseIterable {
        case none, zoomIn, zoomOut
    }

    var body: some View {
        let kenBurns = timeline.project.timeline.clip(clipID)?.kenBurns
        let motion = Self.motion(of: kenBurns)
        let zoom = Self.zoom(of: kenBurns)

        VStack(alignment: .leading, spacing: 8) {
            Text("Fotka — pohyb (Ken Burns)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Pohyb", selection: Binding(
                get: { motion },
                set: { timeline.setKenBurns(clipID, Self.kenBurns(motion: $0, zoom: zoom)) })) {
                Text("Bez pohybu").tag(Motion.none)
                Text("Nájezd").tag(Motion.zoomIn)
                Text("Odjezd").tag(Motion.zoomOut)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            HStack(spacing: 10) {
                Text("Zoom")
                Slider(value: Binding(
                    get: { zoom },
                    set: { timeline.kenBurnsDragChanged(
                        clipID, Self.kenBurns(motion: motion, zoom: $0)) }),
                    in: 1.1...2.0,
                    onEditingChanged: { editing in
                        if editing { timeline.kenBurnsDragBegan() }
                        else { timeline.kenBurnsDragEnded() }
                    })
                    .frame(width: 220)
                    .disabled(motion == .none)
                Text(String(format: "%.1f×", zoom))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Nájezd jede z celku do středu, odjezd obráceně. "
                 + "Pohyb je vidět v náhledu i v exportu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func motion(of kenBurns: KenBurns?) -> Motion {
        guard let kenBurns else { return .none }
        return kenBurns.start.width >= kenBurns.end.width ? .zoomIn : .zoomOut
    }

    private static func zoom(of kenBurns: KenBurns?) -> Double {
        guard let kenBurns else { return 1.3 }
        return 1.0 / min(kenBurns.start.width, kenBurns.end.width)
    }

    private static func kenBurns(motion: Motion, zoom: Double) -> KenBurns? {
        guard motion != .none else { return nil }
        let width = 1.0 / max(zoom, 1.01)
        let inner = NormalizedRect(x: (1 - width) / 2, y: (1 - width) / 2,
                                   width: width, height: width)
        return motion == .zoomIn
            ? KenBurns(start: .full, end: inner)
            : KenBurns(start: inner, end: .full)
    }
}

/// Panel barevného presetu (fáze 13, modul 3): výběr presetu + posuvník
/// síly 0–100 %. Výběr = jeden undo krok; posuvník skládá undo kolem
/// tažení (vzorec hlasitosti a zoomu). Vzhled presetů drží
/// `ColorPresetFilter` — tady je jen volba, přesně jako v modelu.
private struct ColorGradePanel: View {
    @ObservedObject var timeline: TimelineController
    let clipID: ClipID

    var body: some View {
        let grade = timeline.project.timeline.clip(clipID)?.colorGrade

        VStack(alignment: .leading, spacing: 8) {
            Text("Barevný preset")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Preset", selection: Binding(
                get: { grade?.preset },
                set: { newPreset in
                    if let newPreset {
                        // Přepnutí presetu drží nastavenou sílu.
                        timeline.setColorGrade(clipID, ColorGrade(
                            preset: newPreset, intensity: grade?.intensity ?? 1.0))
                    } else {
                        timeline.setColorGrade(clipID, nil)
                    }
                })) {
                Text("Bez úpravy").tag(ColorPreset?.none)
                Text("Jemný svatební").tag(ColorPreset?.some(.softWedding))
                Text("Teplý film").tag(ColorPreset?.some(.warmFilm))
                Text("Čistá pleť").tag(ColorPreset?.some(.cleanSkin))
                Text("Černobílá").tag(ColorPreset?.some(.blackAndWhite))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)

            HStack(spacing: 10) {
                Text("Síla")
                Slider(value: Binding(
                    get: { (grade?.intensity ?? 1.0) * 100 },
                    set: { percent in
                        guard let preset = grade?.preset else { return }
                        timeline.colorGradeDragChanged(clipID, ColorGrade(
                            preset: preset, intensity: percent / 100))
                    }),
                    in: 0...100,
                    onEditingChanged: { editing in
                        if editing { timeline.colorGradeDragBegan() }
                        else { timeline.colorGradeDragEnded() }
                    })
                    .frame(width: 140)
                    .disabled(grade == nil)
                Text(grade.map { String(format: "%.0f %%", $0.intensity * 100) } ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            Text("Preset platí pro tenhle klip, v náhledu i exportu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Správa modelu přepisu (fáze 16, modul 3). Vlastní view ze stejného
/// důvodu jako `ProxyControls` — `transcription` je vnořený
/// `ObservableObject`. Nestažený model se neukazuje vůbec: dokud
/// uživatel titulky z řeči nepoužil, není co spravovat.
private struct WhisperModelControls: View {
    @ObservedObject var transcription: TranscriptionService
    let onRelocate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if let size = transcription.modelSizeBytes {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button("Přemístit model…") { onRelocate() }
                    Button("Smazat model") { onDelete() }
                }
                .controlSize(.small)
                .disabled(transcription.statusText != nil)

                Text("Model přepisu: \(transcription.modelLocationName) · "
                     + ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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

            // JKL (fáze 17). Zkratky visí na ose, ne tady — písmeno bez
            // modifikátoru by v SwiftUI střílelo i při psaní titulku.
            // Tlačítka jsou tu pro myš a hlavně kvůli tomu, aby byla
            // rychlost VIDĚT: „−2× (krokováním)" je přiznaná mez.
            Button("J") { controller.shuttle(.backward) }
            Button("K") { controller.shuttle(.pause) }
            Button("L") { controller.shuttle(.forward) }
            if controller.shuttleRate != 0 {
                Text(controller.shuttleDescription)
                    .font(.caption)
                    .foregroundStyle(controller.isSteppingFallback ? .orange : .secondary)
            }

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
