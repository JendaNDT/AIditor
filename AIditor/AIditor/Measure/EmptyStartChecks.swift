//
//  EmptyStartChecks.swift
//  Projekt AIditor
//
//  Kontrola prázdného startu — fáze 18, modul 12 (`--empty-start-check`).
//
//  A) **Zóna přetažení přijme SOUBOR i SLOŽKU** a složka naimportuje totéž
//     co `Otevřít složku` (kritérium modulu z plánu). Jde se SKUTEČNOU cestou
//     protokolu `NSDraggingDestination` — registrace typu, pasteboard
//     s `NSURL`, `draggingEntered` → `performDragOperation` — ne zkratkou do
//     `importDropped`. Vzorec z modulu 9.
//  B) **Hit test v ploše zóny končí uvnitř registrovaného terče.** AppKit
//     hledá cíl přetažení od nejhlubšího pohledu pod kurzorem nahoru; kdyby
//     obsah zóny ležel NAD terčem místo uvnitř, drop by nad textem a tlačítky
//     přestal fungovat a nikdo by se to nedozvěděl.
//  C) **Bookmark** — pojmenované riziko modulu. Po dropu si appka cestu
//     pamatuje a asset v projektu má bookmark, jinak by import nepřežil
//     restart.
//  D) **Obnova zálohy z pruhu dá tentýž projekt jako dnešní dialog.**
//     Referencí je záloha přečtená napřímo (`ProjectFile.decode`) — tedy to,
//     co dialogová cesta uměla; porovnává se počet klipů i `validate()`.
//  E) **Prázdný start se objeví a zmizí** podle materiálu, ne podle přání UI.
//
//  ⚠️ Kontrola si odloží OBSAH SLOTU ZÁLOHY a na konci ho vrátí. Běží
//  v témže kontejneru jako appka, takže by jinak přepsala zálohu skutečné
//  neuložené práce uživatele.
//

import AppKit
import Foundation
import TimelineModel

extension AppModel {

    func verifyEmptyStart() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — není co přetáhnout"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        // Záloha uživatele stranou (viz hlavička).
        let slotURL = projectStore.autosaveFileURL
        let savedSlot = slotURL.flatMap { try? Data(contentsOf: $0) }
        defer {
            if let slotURL {
                if let savedSlot { try? savedSlot.write(to: slotURL, options: .atomic) }
                else { try? FileManager.default.removeItem(at: slotURL) }
            }
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        let scanned = clips
        let sourceFile = scanned[0].url
        let folder = sourceFile.deletingLastPathComponent()

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while hostView?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let window = hostView?.window else {
            print("❌ okno se neotevřelo"); return
        }
        window.makeKeyAndOrderFront(nil)

        print("=== E) prázdný start podle materiálu ===")
        await emptyTheProject()
        print("   assetů v projektu: \(timeline.project.assets.count)")
        check(showsEmptyStart, "bez materiálu se ukazuje prázdný start")
        check(recoveryOffer == nil, "a bez zálohy v něm není pruh obnovy")
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let shot = Self.writeWindowSnapshot(of: window, name: "prazdny-start") {
            print("   snímek: \(shot.path)")
        }

        guard let zone = dropZoneView else {
            print("❌ zóna přetažení se nedostala do okna"); return
        }
        check(zone.registeredDraggedTypes.contains(.fileURL),
              "terč je registrovaný na `.fileURL` (bez toho nikdo drop nezavolá)")

        print("")
        print("=== B) hit test v ploše zóny ===")
        // Střed zóny: kde leží nadpis a tlačítka, tedy přesně to místo, kde
        // by špatně poskládaná hierarchie drop ztratila.
        // ⚠️ `hitTest` bere bod v souřadnicích NADŘAZENÉHO pohledu; u content
        // view okna jsou to souřadnice okna, takže se převádí jen jednou.
        let center = zone.convert(NSPoint(x: zone.bounds.midX, y: zone.bounds.midY), to: nil)
        let hit = window.contentView?.hitTest(center)
        let inside = hit.map { $0 === zone || $0.isDescendant(of: zone) } ?? false
        print("   hit test vrátil \(hit.map { String(describing: type(of: $0)) } ?? "nic")")
        check(inside, "pohled pod kurzorem je terč nebo jeho potomek")

        print("")
        print("=== A1) drop JEDNOHO souboru ===")
        let filePoint = zone.convert(NSPoint(x: zone.bounds.midX, y: zone.bounds.midY), to: nil)
        let fileDrag = FakeDraggingInfo(fileURLs: [sourceFile], at: filePoint)
        let entered = zone.draggingEntered(fileDrag)
        check(entered == .copy, "`draggingEntered` povolil kopii (\(entered.rawValue))")
        let dropped = zone.performDragOperation(fileDrag)
        check(dropped, "`performDragOperation` drop přijal")
        await waitForImport(assets: 1)
        print("   po dropu: \(timeline.project.assets.count) assetů, \(clips.count) klipů")
        check(timeline.project.assets.count >= 1, "materiál je v projektu")
        check(!showsEmptyStart, "prázdný start zmizel")

        print("")
        print("=== C) bookmark (riziko modulu) ===")
        check(importer.remembers(sourceFile),
              "appka si cestu pamatuje bookmarkem, takže import přežije restart")
        check(timeline.project.assets.allSatisfy { $0.bookmark != nil },
              "a asset v projektu bookmark nese taky")

        print("")
        print("=== A2) drop CIZÍHO souboru se odmítne ===")
        let alienURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiditor-prazdny-start.txt")
        try? Data("nic k importu".utf8).write(to: alienURL)
        let before = timeline.project
        // ⚠️ Terč `.fileURL` textový soubor PŘIJME — o tom, co je použitelné,
        // rozhoduje až model podle přípony (terč nesmí zkoumat obsah, to je
        // práce importu). Kontroluje se proto to, co je vidět: projekt se
        // nezměnil a appka řekla proč.
        let alienDrag = FakeDraggingInfo(fileURLs: [alienURL], at: filePoint)
        _ = zone.performDragOperation(alienDrag)
        try? await Task.sleep(nanoseconds: 600_000_000)
        check(timeline.project == before, "cizí soubor projekt nezměnil")
        check(status.contains("neumím"), "a appka to řekla nahlas: „\(status)“")

        print("")
        print("=== A3) drop SLOŽKY == Otevřít složku ===")
        await emptyTheProject()
        let expected = importer.videoFiles(in: folder)
        print("   ve složce je \(expected.count) videosouborů")
        let folderDrag = FakeDraggingInfo(fileURLs: [folder], at: filePoint)
        let folderEntered = zone.draggingEntered(folderDrag)
        check(folderEntered == .copy, "složka se přijímá stejně jako soubor")
        let folderDropped = zone.performDragOperation(folderDrag)
        check(folderDropped, "drop složky prošel")
        await waitForImport(assets: expected.count)
        let importedURLs = Set(timeline.project.assets.map(\.originalURL.path))
        print("   naimportováno assetů: \(timeline.project.assets.count)")
        check(timeline.project.assets.count == expected.count,
              "počet sedí na `videoFiles(in:)`, tedy na `Otevřít složku`")
        check(Set(expected.map(\.path)) == importedURLs,
              "a jsou to TYTÉŽ soubory, ne jen stejný počet")
        check(timeline.project.validate().isEmpty, "projekt bez porušených invariantů")

        print("")
        print("=== D) obnova zálohy z pruhu ===")
        // Záloha: osa ze dvou klipů, přesně jak by ji nechal pád aplikace.
        var backup = Project.empty()
        backup.addAsset(timeline.project.assets[0])
        do {
            let v1 = backup.timeline.tracks[0].id
            for index in 0..<2 {
                var clip = try backup.makeClip(assetID: backup.assets[0].id,
                                               at: Frames(index * 100))
                clip.duration = Frames(60)
                try backup.insert(clip, onTrack: v1)
            }
        } catch {
            print("❌ stavba zálohy selhala: \(error)"); return
        }
        timeline.loadProject(backup)
        projectStore.markRestoredUnsaved()
        projectStore.autosaveIfDirty(timeline.project)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Reference: co by z toho souboru dostala dosavadní dialogová cesta.
        guard let slotURL,
              let data = try? Data(contentsOf: slotURL),
              let onDisk = try? ProjectFile.decode(data) else {
            print("❌ záloha se nezapsala"); return
        }
        let referenceClips = onDisk.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        let referenceViolations = onDisk.project.validate().count

        await emptyTheProject()
        let offered = presentUnsavedRecovery()
        print("   nabídka: \(recoveryOffer.map { "z \($0.modifiedAt), \($0.clipCount) klipů" } ?? "žádná")")
        check(offered && recoveryOffer != nil, "pruh obnovy se nabídl (místo dialogu)")
        check(recoveryOffer?.clipCount == referenceClips,
              "pruh říká počet klipů zálohy (\(referenceClips))")
        check(showsEmptyStart, "a nabízí se na prázdném startu, ne přes rozdělanou práci")

        // Snímek se dělá TEĎ, dokud nabídka platí. (První verze kontroly ho
        // brala až na konci — jenže uložení testovacího projektu o kus níž
        // zálohu smaže, takže na snímku žádný pruh nebyl a vypadalo to, že
        // se nekreslí.)
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let shot = Self.writeWindowSnapshot(of: window, name: "prazdny-start-obnova") {
            print("   snímek: \(shot.path)")
        }

        await restoreRecoveryOffer()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let restoredClips = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        print("   obnoveno klipů: \(restoredClips), reference ze souboru: \(referenceClips)")
        check(restoredClips == referenceClips, "obnovený projekt má tytéž klipy jako záloha")
        check(timeline.project.validate().count == referenceViolations,
              "a tentýž počet porušení invariantů (\(referenceViolations))")
        check(recoveryOffer == nil, "pruh po obnově zmizel")
        check(projectStore.isDirty,
              "obnovená práce zůstává NEULOŽENÁ (⌘S ji uloží, autosave ji chrání)")

        print("")
        print("=== poslední projekty a offline řádek ===")
        // ⚠️ Evidence se odloží a vrátí — kontrola nesmí uživateli nechat
        // v seznamu dočasný projekt ani mu přepsat „poslední projekt".
        let recentsSnapshot = projectStore.snapshotRecents()
        defer { projectStore.restoreRecents(recentsSnapshot) }

        let tempProject = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Prazdny start test.projektkrasa")
        do {
            try projectStore.save(project: timeline.project, to: tempProject)
        } catch {
            print("❌ uložení testovacího projektu selhalo: \(error)"); return
        }
        projectStore.refreshRecentProjects()
        guard let row = projectStore.recentProjects.first(where: { $0.path == tempProject.path })
        else {
            print("❌ uložený projekt se nedostal do seznamu"); return
        }
        let expectedShots = timeline.project.timeline.tracks
            .filter { $0.kind == .video }.reduce(0) { $0 + $1.clips.count }
        print("   řádek: \(row.name) · \(row.shotCount) záběrů · "
              + String(format: "%.1f s", row.durationSeconds))
        check(row.shotCount == expectedShots,
              "počet záběrů v řádku sedí na projekt (\(expectedShots))")
        check(row.durationSeconds > 0, "a délka není nula")
        check(!row.isOffline, "dostupný projekt se nehlásí jako offline")
        check(projectStore.resolveRecent(row) != nil, "a dá se z řádku otevřít")

        // Soubor pryč = disk odpojený. Toho se seznam musí všimnout SÁM.
        try? FileManager.default.removeItem(at: tempProject)
        projectStore.refreshRecentProjects()
        let gone = projectStore.recentProjects.first { $0.path == tempProject.path }
        check(gone?.isOffline == true, "nedostupný projekt se označí oranžově jako offline")
        check(gone.map { projectStore.resolveRecent($0) == nil } ?? false,
              "a otevřít se nedá — řádek to řekne, místo aby selhal potichu")
        projectStore.detachFromFile()

        print("")
        print(failures == 0 ? "✅ PRÁZDNÝ START SEDÍ" : "❌ neshod: \(failures)")
    }

    // MARK: - Pomocníci

    /// Vyprázdní osu tak, jak to dělá „Nový projekt" — jen bez dotazu na
    /// neuloženou práci (ten je pod CLI vypnutý, ale spoléhat se na to
    /// v kontrole by znamenalo měřit něco jiného než uživatel vidí).
    private func emptyTheProject() async {
        timeline.loadProject(Project.empty())
        timeline.undo = UndoStack()
        clips = []
        selected = nil
        projectStore.markCurrent(timeline.project)
        recoveryOffer = nil
        // Příznak `hasMedia` jde přes Combine, takže se musí nechat doběhnout.
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// Import běží v `Task` a měří časování každého souboru — čeká se na
    /// počet assetů, ne na pevnou dobu.
    private func waitForImport(assets: Int, timeout: TimeInterval = 60) async {
        let deadline = Date().addingTimeInterval(timeout)
        while timeline.project.assets.count < assets, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
}
