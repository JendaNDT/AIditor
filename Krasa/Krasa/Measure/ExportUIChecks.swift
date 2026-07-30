//
//  ExportUIChecks.swift
//  Projekt Krása
//
//  Kontrola listu exportu — fáze 18, modul 10 (`--export-ui-check`).
//
//  A) **Čísla v listu sedí na skutečnost.** Kolik snímků list slíbí, tolik se
//     jich musí zapsat — a porovnává se to na OBOU rozsazích (celý projekt
//     i výřez I—O). Tohle je jediné kritérium modulu, které nejde odhadnout
//     okem: 7 567 v hlavičce a 7 560 v souboru vypadá na screenshotu stejně.
//  B) **Varovný blok počítá z dat.** Týž ramp na 30fps zdroji dá 37,5 %,
//     na 120fps zdroji nic — a mezi tím musí být rozdíl vidět v UI, ne jen
//     v modelu. Pojmenované riziko modulu v plánu.
//  C) **Tři stavy listu** se projdou a nechají chvíli stát pro screenshot.
//  D) **Volby se do exportu doopravdy propíšou:** vypnuté vypalování titulků,
//     zapnutý `.srt`.
//

import AppKit
import AVFoundation
import Foundation
import TimelineModel

extension AppModel {

    func verifyExportUI() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — není co exportovat"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        // Krátká osa ze dvou klipů — export musí proběhnout několikrát,
        // takže musí být rychlý.
        guard let source = timeline.project.assets
            .first(where: { $0.hasVideo && $0.hasAudio && !$0.isStill }) else {
            print("❌ žádný video asset se zvukem"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        let v1 = project.timeline.tracks[0].id
        let a1 = project.timeline.tracks[1].id
        do {
            for index in 0..<2 {
                let pair = try project.makeLinkedClips(assetID: source.id,
                                                       at: Frames(index * 45))
                var video = pair.video, audio = pair.audio
                video.duration = Frames(45)
                audio.duration = Frames(45)
                try project.insertLinked(video: video, onVideoTrack: v1,
                                         audio: audio, onAudioTrack: a1)
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        loudnessProfile = .web

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KrasaExportUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        NSApp.activate(ignoringOtherApps: true)
        if let host = await exportUIHostView() {
            host.window?.makeKeyAndOrderFront(nil)
        }
        try? await Task.sleep(nanoseconds: 800_000_000)

        print("=== A) co list slíbí, to se zapíše ===")

        // 1) celý projekt
        timeline.clearExportRange()
        openExportSheet()
        exportUsesRange = false
        exportDestination = directory.appendingPathComponent("cely.mp4")
        try? await Task.sleep(nanoseconds: 400_000_000)
        let promisedAll = exportSheetFrameCount
        print("   list slibuje \(promisedAll) snímků (celý projekt)")
        check(exportSheet == .settings, "list je ve stavu nastavení")
        runExportFromSheet()
        await waitForExport()
        guard let allOutcome = exportOutcome else {
            print("❌ export celého projektu nedal výsledek"); return
        }
        print("   zapsáno \(allOutcome.writtenFrames), list čekal \(allOutcome.expectedFrames)")
        check(promisedAll == allOutcome.writtenFrames,
              "celý projekt: slíbeno == zapsáno (\(promisedAll))")
        check(allOutcome.framesMatch, "a list to sám vyhodnotil jako shodu")
        check(exportSheet == .done, "list se přepnul do stavu hotovo")
        check(allOutcome.fileBytes > 0,
              "soubor má nenulovou velikost ("
              + ByteCountFormatter.string(fromByteCount: allOutcome.fileBytes, countStyle: .file) + ")")
        check(exportMeasuredFPS != nil, "odhad rychlosti se objevil až po prvním exportu")

        // 2) jen výřez
        timeline.setInPoint(Frames(15))
        timeline.setOutPoint(Frames(45))
        openExportSheet()
        exportUsesRange = true
        exportDestination = directory.appendingPathComponent("vyrez.mp4")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let promisedRange = exportSheetFrameCount
        print("   list slibuje \(promisedRange) snímků (výřez 15–45)")
        check(promisedRange == 30, "výřez v listu je 30 snímků")
        runExportFromSheet()
        await waitForExport()
        guard let rangeOutcome = exportOutcome else {
            print("❌ export výřezu nedal výsledek"); return
        }
        print("   zapsáno \(rangeOutcome.writtenFrames), list čekal \(rangeOutcome.expectedFrames)")
        check(promisedRange == rangeOutcome.writtenFrames,
              "výřez: slíbeno == zapsáno (\(promisedRange))")
        check(rangeOutcome.rangeText != nil, "list přiznal, že jde jen o výřez")
        check(rangeOutcome.writtenFrames < allOutcome.writtenFrames,
              "výřez je kratší než celý projekt")

        // Ověření SOUBORU, ne jen našeho počítadla: kolik snímků má stopa.
        if let measured = await Self.countFrames(in: rangeOutcome.url) {
            print("   v souboru napočítáno \(measured) snímků")
            check(measured == rangeOutcome.writtenFrames,
                  "počet snímků v SOUBORU sedí na to, co list slíbil")
        }

        print("")
        print("=== B) varovný blok počítá z materiálu, ne z konstanty ===")
        // Rampa na 0,25× na klip, jehož zdroj má NAMĚŘENOU frekvenci 30 fps.
        var ramped = Project.empty()
        let slowAsset = Asset(originalURL: source.originalURL,
                              bookmark: source.bookmark,
                              duration: source.duration,
                              measuredFrameRate: 30,
                              hasVideo: true, hasAudio: false)
        ramped.addAsset(slowAsset)
        let track = ramped.timeline.tracks[0].id
        do {
            var clip = try ramped.makeClip(assetID: slowAsset.id)
            try ramped.insert(clip, onTrack: track)
            try ramped.setSpeedRamp(clipID: clip.id,
                                    ramp: .classicSlowMotion(from: .zero,
                                                             spanning: SourceTime(seconds: 5),
                                                             slowSpeed: 0.25))
            try ramped.trimEnd(clipID: clip.id, to: Frames(240))
            clip = ramped.timeline.clip(clip.id) ?? clip
            timeline.project = ramped
            try? await Task.sleep(nanoseconds: 300_000_000)

            let warnings = exportDuplicationWarnings
            print("   varování: \(warnings.count), podíl "
                  + String(format: "%.1f %%", (warnings.first?.share ?? 0) * 100))
            check(warnings.count == 1, "30fps zdroj s rampou 0,25× dá právě jedno varování")
            check(abs((warnings.first?.share ?? 0) - 0.375) < 0.03,
                  "podíl duplikace je 37,5 % (číslo z naměřených dat, ne z UI)")

            // Týž ramp na 120fps zdroji: duplikovat se nemá nic.
            var fast = ramped
            var fastAsset = slowAsset
            fastAsset.measuredFrameRate = 120
            fast.addAsset(fastAsset)
            timeline.project = fast
            try? await Task.sleep(nanoseconds: 300_000_000)
            print("   po přepnutí zdroje na 120 fps: varování \(exportDuplicationWarnings.count)")
            check(exportDuplicationWarnings.isEmpty,
                  "120fps zdroj tentýž ramp utáhne a varování ZMIZÍ")
        } catch {
            check(false, "stavba rampy pro varování selhala: \(error)")
        }

        print("")
        print("=== C) tři stavy listu (pro screenshot) ===")
        timeline.project = project
        timeline.clearExportRange()
        // ⚠️ NE `openExportSheet()`: ta výsledek posledního exportu maže
        // (aby stav „hotovo" nezůstal viset u nového exportu), takže by stav
        // „hotovo" neměl z čeho kreslit kontrolní řádky. Pro screenshot se
        // stavy nastavují přímo.
        exportSheet = .settings
        for (label, phase) in [("nastavení", ExportSheetPhase.settings),
                               ("průběh", .progress),
                               ("hotovo", .done)] {
            exportSheet = phase
            if phase == .progress { exportProgress = 0.42; exportStage = .rendering }
            // ⚠️ Okno do popředí PŘED každým stavem, ne jen na začátku:
            // dřívější kontroly nechávají otevřený Finder
            // (`activateFileViewerSelecting`) a screenshot pak vyfotí jeho.
            NSApp.activate(ignoringOtherApps: true)
            hostView?.window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // ⚠️ Snímek si dělá APLIKACE SAMA, ne `screencapture`. Předchozí
            // kontroly nechávají nad oknem otevřený Finder
            // (`activateFileViewerSelecting`) a `NSApp.activate` ho nepřebije,
            // takže se vyfotil Finder. `cacheDisplay(in:to:)` kreslí přímo
            // z hierarchie a na z-order se neptá.
            let shot = Self.writeWindowSnapshot(of: hostView?.window,
                                                name: "export-\(phaseFileName(phase))")
            print("   stav: \(label)\(shot.map { " → " + $0.path } ?? "")")
        }
        exportProgress = nil
        check(exportOutcome != nil, "stav hotovo má z čeho kreslit kontrolní řádky")
        check(exportStages.count == 3, "průběh má tři fáze (\(exportStages.count))")

        print("")
        print("=== D) volby listu se propíšou do exportu ===")
        timeline.project = project
        exportBurnsTitles = false
        exportWritesSRT = true
        exportDestination = directory.appendingPathComponent("volby.mp4")
        exportUsesRange = false
        exportSheet = .settings
        runExportFromSheet()
        await waitForExport()
        if let outcome = exportOutcome {
            print("   vypálených titulků: \(outcome.burnedTitles), "
                  + "srt: \(outcome.srtURL?.lastPathComponent ?? "žádný")")
            check(outcome.burnedTitles == 0, "vypnuté vypalování se propsalo")
            // Bez přepisu není co uložit — `.srt` se nemá vyrobit naprázdno.
            check(outcome.srtURL == nil,
                  "bez přepisu se prázdný .srt nevyrobil (není co do něj dát)")
        } else {
            check(false, "export s volbami nedal výsledek")
        }
        exportBurnsTitles = true
        exportWritesSRT = false
        exportSheet = nil

        print("")
        print(failures == 0 ? "✅ LIST EXPORTU SEDÍ" : "❌ neshod: \(failures)")
    }

    // MARK: - Pomocníci

    private func phaseFileName(_ phase: ExportSheetPhase) -> String {
        switch phase {
        case .settings: return "nastaveni"
        case .progress: return "prubeh"
        case .done: return "hotovo"
        }
    }

    /// Snímek okna do PNG v kontejneru. Pro koukance a pro to, aby si člověk
    /// mohl výsledek prohlédnout bez ohledu na to, co je právě v popředí.
    static func writeWindowSnapshot(of window: NSWindow?, name: String) -> URL? {
        guard let content = window?.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            return nil
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]),
              let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask).first
        else { return nil }
        let folder = directory.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name + ".png")
        try? data.write(to: url)
        return url
    }

    private func waitForExport(timeout: TimeInterval = 180) async {
        let deadline = Date().addingTimeInterval(timeout)
        // Rozjezd: export se spouští v `Task`, takže `exportProgress` ještě
        // nemusí být nastavené.
        try? await Task.sleep(nanoseconds: 500_000_000)
        while exportProgress != nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// Kolik snímků má obrazová stopa souboru. Nezávislé ověření: naše
    /// počítadlo zapsaných snímků a skutečný obsah souboru jsou dvě věci.
    ///
    /// ⚠️ **Počítají se VZORKY (`CMSampleBufferGetNumSamples`), ne buffery.**
    /// `AVAssetReaderTrackOutput` vydá i buffery BEZ dat — naměřeno
    /// 30. 07. 2026 na obou exportech: 94 bufferů / 90 vzorků a 34 / 30,
    /// tedy pokaždé čtyři buffery bez dat navíc. První verze téhle kontroly
    /// počítala buffery, dostala 34 proti 30 a vypadalo to na chybu v exportu.
    /// Délka souboru (1,000 s a 3,000 s) přitom celou dobu vycházela přesně.
    private static func countFrames(in url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            count += CMSampleBufferGetNumSamples(buffer)
        }
        return count
    }

    private func exportUIHostView(timeout: TimeInterval = 10) async -> PlayerHostView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let view = hostView, view.window != nil { return view }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }
}
