//
//  OverviewChecks.swift
//  Projekt Krása
//
//  Kontrola přehledu celé osy — fáze 18, modul 6 (`--overview-check`).
//
//  A) **Trefuje klik?** Hodinová osa, klik do 3/4 pásu položí hlavu do 3/4
//     délky. ⚠️ Plán chtěl toleranci JEDEN SNÍMEK a to je nedosažitelné
//     z konstrukce: přehled mapuje hodinu (108 000 snímků) na ~1000 bodů,
//     takže jeden bod JE stovka snímků. Kontrola proto měří toleranci
//     **jeden bod pásu** a číslo vypisuje, ať je vidět, o čem se mluví.
//  B) **Scrolluje tažení rámečku?** Assertuje se SÉMANTIKA, ne vzorec:
//     když se rámeček odtáhne na zlomek f pásu, začátek viditelného výřezu
//     osy musí být na zlomku f délky. Přepočítávat to týmž vzorcem jako kód
//     by neověřilo nic.
//  C) **Nepere se to s auto-scrollem?** (Riziko modulu.) Během tažení
//     rámečku nesmí pohyb hlavy osou hnout; po puštění platí totéž pravidlo
//     jako po ručním scrollu (osa nechá být, dokud hlava sama nevjede do
//     výřezu); a klik do přehledu je výslovná navigace, která odstavení ruší.
//  D) **Nepřestavuje se zbytečně?** `reload()` chodí i při zoomu, kdy se
//     v přehledu nemění nic. Měří se počítadlem přestaveb, ne časem —
//     ten by byl pod šumem.
//

import AppKit
import Foundation
import TimelineModel

extension AppModel {

    func verifyOverview() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — není z čeho stavět osu"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        // Hodinová osa. Dvojice klipů mají 45–150 snímků (průměr 93), takže
        // na hodinu (108 000 snímků) je potřeba ~1160 dvojic.
        timeline.loadStressProject(from: clips, pairs: 1160)
        var geometry = timeline.geometry
        geometry.setZoom(5)
        timeline.geometry = geometry

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while timelinePane?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let pane = timelinePane, let window = pane.window else {
            print("❌ osa se nedostala do okna"); return
        }
        window.makeKeyAndOrderFront(nil)
        // Miniatury pro tuhle kontrolu jen zdržují — přehled na nich nestojí.
        timeline.layers.thumbnails = false
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let overview = pane.overviewView
        let total = timeline.project.duration
        let frameRate = timeline.project.timeline.frameRate
        let strip = overview.measuredStripFrame
        let inset = overview.measuredInset
        let usable = Double(strip.width) - 2 * inset

        print("=== A) klik do přehledu položí hlavu ===")
        print(String(format: "   osa %@ (%d snímků), pás %.0f bodů → %.1f snímků na bod",
                     Timecode(total, frameRate: frameRate).text, total.count,
                     Double(strip.width), overview.framesPerPoint))
        check(total.count > 100_000, "osa je opravdu hodinová (\(total.count) snímků)")
        check(overview.measuredBlockCounts.video > 0 && overview.measuredBlockCounts.audio > 0,
              "v pásu jsou bloky obrazu i zvuku "
              + "(\(overview.measuredBlockCounts.video) / \(overview.measuredBlockCounts.audio))")
        let clipCount = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        check(overview.measuredBlockCounts.video + overview.measuredBlockCounts.audio < clipCount,
              "bloky se slily (\(overview.measuredBlockCounts.video + overview.measuredBlockCounts.audio) "
              + "proti \(clipCount) klipům)")

        let tolerance = overview.framesPerPoint
        for fraction in [0.0, 0.25, 0.75, 1.0] {
            // Bod se počítá VLASTNÍM vzorcem kontroly, ne přes view.
            let x = Double(strip.origin.x) + inset + fraction * usable
            let y = Double(strip.midY)
            synthesizeOverviewClick(on: overview, at: CGPoint(x: x, y: y))
            try? await Task.sleep(nanoseconds: 250_000_000)
            let expected = fraction * Double(total.count)
            let actual = Double(timeline.playhead.count)
            print(String(format: "   klik na %.0f %% → hlava %.0f, čekáno %.0f (odchylka %.0f snímků)",
                         fraction * 100, actual, expected, abs(actual - expected)))
            check(abs(actual - expected) <= tolerance + 1,
                  String(format: "%.0f %% sedí na bod pásu (tolerance %.0f snímků)",
                         fraction * 100, tolerance))
        }

        print("")
        print("=== B) tažení rámečku scrolluje osu ===")
        // Hlavu na začátek, ať následování nezasahuje do měření.
        timeline.setPlayheadFromUser(.zero)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let viewport = overview.measuredViewportFrame else {
            print("❌ rámeček výřezu se nekreslí, není co táhnout"); return
        }
        print(String(format: "   rámeček je široký %.1f bodu (výřez %.0f z %.0f bodů dokumentu)",
                     viewport.width, pane.scrollView.contentView.bounds.width,
                     pane.documentView.frame.width))

        for target in [0.5, 0.2] {
            // ⚠️ Rámeček se musí PŘEMĚŘIT před každým tažením. První verze
            // kontroly si ho vzala jednou před smyčkou, takže druhé tažení
            // chytalo místo, kde rámeček už nebyl — `mouseDown` to vyhodnotil
            // jako klik, hlava skočila a osa se posunula za ní. Vyšlo to
            // „skoro správně" (2,7 bodu vedle), což je nejhorší druh chyby
            // v měření: vypadá jako drobná nepřesnost kódu.
            guard let current = overview.measuredViewportFrame else {
                check(false, "rámeček zmizel před tažením"); break
            }
            let grabX = Double(strip.origin.x) + Double(current.origin.x) + Double(current.width) / 2
            let toX = Double(strip.origin.x) + inset + target * usable
                + Double(current.width) / 2
            synthesizeOverviewDrag(on: overview,
                                  from: CGPoint(x: grabX, y: Double(strip.midY)),
                                  to: CGPoint(x: toX, y: Double(strip.midY)))
            try? await Task.sleep(nanoseconds: 400_000_000)

            // Sémantika: začátek viditelného výřezu je na zlomku `target`.
            let scrollX = Double(pane.scrollView.contentView.bounds.origin.x)
            let startFrame = scrollX / timeline.geometry.pointsPerFrame
            let expectedFrame = target * Double(total.count)
            print(String(format: "   táhnu na %.0f %% → výřez začíná na snímku %.0f, čekáno %.0f "
                         + "(odchylka %.0f snímků = %.1f bodu pásu)",
                         target * 100, startFrame, expectedFrame,
                         abs(startFrame - expectedFrame),
                         abs(startFrame - expectedFrame) / overview.framesPerPoint))
            check(abs(startFrame - expectedFrame) <= 2 * overview.framesPerPoint,
                  String(format: "výřez sedí na %.0f %% délky (do dvou bodů pásu)", target * 100))
        }

        print("")
        print("=== C) souboj s auto-scrollem ===")
        // 1) Během tažení rámečku nesmí pohyb hlavy osou hnout.
        let beforeDrag = Double(pane.scrollView.contentView.bounds.origin.x)
        let grabX = Double(strip.origin.x) + inset + 0.2 * usable
            + Double(overview.measuredViewportFrame?.width ?? 6) / 2
        beginOverviewDrag(on: overview, at: CGPoint(x: grabX, y: Double(strip.midY)))
        timeline.setPlayheadFromPlayback(Frames(total.count / 2))
        try? await Task.sleep(nanoseconds: 400_000_000)
        let duringDrag = Double(pane.scrollView.contentView.bounds.origin.x)
        print(String(format: "   scroll před %.0f → během tažení %.0f (hlava skočila do poloviny osy)",
                     beforeDrag, duringDrag))
        check(abs(duringDrag - beforeDrag) < 1,
              "během tažení rámečku osa za hlavou NEJEDE")

        // 2) Po puštění platí pravidlo ručního scrollu: osa nechá být.
        endOverviewDrag(on: overview, at: CGPoint(x: grabX, y: Double(strip.midY)))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let afterDrag = Double(pane.scrollView.contentView.bounds.origin.x)
        timeline.setPlayheadFromPlayback(Frames(total.count / 2 + 60))
        try? await Task.sleep(nanoseconds: 400_000_000)
        let afterMove = Double(pane.scrollView.contentView.bounds.origin.x)
        print(String(format: "   po puštění %.0f → po posunu hlavy %.0f", afterDrag, afterMove))
        check(abs(afterMove - afterDrag) < 1,
              "po puštění osa zůstane stát (hlava je mimo výřez — vzorec ručního scrollu)")

        // 3) Klik do přehledu je výslovná navigace: odstavení ruší a osa jede.
        let clickX = Double(strip.origin.x) + inset + 0.6 * usable
        synthesizeOverviewClick(on: overview, at: CGPoint(x: clickX, y: Double(strip.midY)))
        try? await Task.sleep(nanoseconds: 500_000_000)
        let afterClick = Double(pane.scrollView.contentView.bounds.origin.x)
        let playheadX = timeline.geometry.x(for: timeline.playhead)
        let viewportWidth = Double(pane.scrollView.contentView.bounds.width)
        print(String(format: "   klik na 60 %% → scroll %.0f, hlava na %.0f bodech dokumentu",
                     afterClick, playheadX))
        check(playheadX >= afterClick && playheadX <= afterClick + viewportWidth,
              "po kliku do přehledu je hlava ve výřezu (osa se za ní posunula)")

        print("")
        print("=== D) reload při zoomu přehled nepřestavuje ===")
        let rebuildsBefore = overview.rebuildCount
        for zoom in [3.0, 8.0, 5.0] {
            var next = timeline.geometry
            next.setZoom(zoom)
            timeline.geometry = next
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        let rebuildsAfterZoom = overview.rebuildCount
        print("   přestaveb: před zoomem \(rebuildsBefore), po třech zoomech \(rebuildsAfterZoom)")
        check(rebuildsAfterZoom == rebuildsBefore,
              "tři změny zoomu nepřestavěly bloky ani jednou")

        // Změna projektu naopak přestavět MUSÍ.
        var shorter = timeline.project
        if let track = shorter.timeline.tracks.first(where: { $0.kind == .video }),
           let last = track.clips.last {
            try? shorter.remove(clipID: last.id)
            timeline.project = shorter
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        print("   po smazání klipu: \(overview.rebuildCount)")
        check(overview.rebuildCount > rebuildsAfterZoom,
              "změna projektu bloky přestavěla")

        print("")
        print("=== E) celá osa ve výřezu = žádný rámeček ===")
        pane.zoomToFit()
        try? await Task.sleep(nanoseconds: 800_000_000)
        let viewportWidthAfterFit = Double(pane.scrollView.contentView.bounds.width)
        let documentAfterFit = Double(pane.documentView.frame.width)
        print(String(format: "   ⇧Z na hodinové ose: zoom %.4f b/snímek (podlaha %.2f), "
                     + "dokument %.0f proti výřezu %.0f bodů",
                     timeline.geometry.pointsPerFrame, TimelineGeometry.minPointsPerFrame,
                     documentAfterFit, viewportWidthAfterFit))
        // ⚠️ NÁLEZ, ne chyba kontroly: ⇧Z hodinovou osu do okna nedostane.
        // `TimelineGeometry.minPointsPerFrame` je 0,02, takže do výřezu 562
        // bodů se vejde nejvýš ~27 700 snímků, tedy ~15 minut. Na delší ose
        // fit dojede na podlahu a rámeček výřezu SPRÁVNĚ zůstává — a je to
        // přesně ten případ, pro který přehled vznikl.
        check(documentAfterFit > viewportWidthAfterFit + 1,
              "fit hodinovou osu do okna nedostane (naráží na podlahu zoomu) — "
              + "rámeček proto zůstává")
        check(overview.measuredViewportFrame != nil,
              "a rámeček se opravdu dál kreslí, protože výřez je opravdu výřez")

        // Krátká osa: tam fit doopravdy fitne a rámeček musí zmizet.
        var short = Project.empty()
        if let source = timeline.project.assets.first(where: { $0.hasVideo && !$0.isStill }),
           let v1 = short.timeline.tracks.first(where: { $0.kind == .video })?.id {
            short.addAsset(source)
            for index in 0..<3 {
                let clip = Clip(assetID: source.id, timelineStart: Frames(index * 90),
                                duration: Frames(90),
                                sourceStart: short.timeline.sourceTime(.zero))
                try? short.insert(clip, onTrack: v1)
            }
            timeline.project = short
            try? await Task.sleep(nanoseconds: 500_000_000)
            pane.zoomToFit()
            try? await Task.sleep(nanoseconds: 800_000_000)
            // Ve snímcích, ne v bodech dokumentu: `contentWidth` přidává za
            // poslední klip rezervu, takže dokument je širší než výřez i když
            // je celá osa vidět — a v bodech to vypadá jako protimluv.
            let visibleFrames = Double(pane.scrollView.contentView.bounds.width)
                / timeline.geometry.pointsPerFrame
            print(String(format: "   ⇧Z na 9s ose: zoom %.2f b/snímek → výřez pokrývá %.0f "
                         + "z %d snímků osy",
                         timeline.geometry.pointsPerFrame, visibleFrames,
                         timeline.project.duration.count))
            check(overview.measuredViewportFrame == nil,
                  "na krátké ose fit rámeček skryje (jinak by „vidím vše\" a „vidím výřez\" "
                  + "vypadalo stejně)")
        }

        print("")
        print("=== F) co stojí aktualizace výřezu za tik ===")
        // ⚠️ Tohle je BRÁNA, ne informace. První verze modulu 6 čtla
        // `Project.duration` při každém zápisu výřezu — a ta prochází všechny
        // klipy a alokuje dvě pole, takže medián práce na tik vyskočil
        // z 0,95 na 2,45 ms (změřeno A/B proti HEAD). Kritérium je proto
        // vlastnost TÉHLE cesty, ne celkové číslo benchmarku: to by se
        // schovalo do šumu stroje.
        timeline.loadStressProject(from: clips, pairs: 1000)
        var benchGeometry = timeline.geometry
        benchGeometry.setZoom(5)
        timeline.geometry = benchGeometry
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let clips2000 = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }

        let iterations = 400
        overview.visibleDocumentRange = (origin: 0, width: 500)   // rozjezd
        let started = CACurrentMediaTime()
        for index in 0..<iterations {
            overview.visibleDocumentRange = (origin: Double(index) * 10, width: 500)
        }
        let msPerWrite = (CACurrentMediaTime() - started) * 1000 / Double(iterations)
        print(String(format: "   %d klipů na ose, %.4f ms na jeden zápis výřezu",
                     clips2000, msPerWrite))
        check(msPerWrite < 0.1,
              String(format: "aktualizace výřezu je pod 0,1 ms (%.4f) — délka osy se NEPOČÍTÁ znovu",
                     msPerWrite))

        print("")
        print(failures == 0 ? "✅ PŘEHLED OSY SEDÍ" : "❌ neshod: \(failures)")
    }

    // MARK: - Syntetické události

    private func overviewEvent(_ type: NSEvent.EventType, on view: NSView,
                               at point: CGPoint) -> NSEvent? {
        guard let window = view.window else { return nil }
        return NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                                  modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1)
    }

    private func synthesizeOverviewClick(on view: NSView, at point: CGPoint) {
        if let down = overviewEvent(.leftMouseDown, on: view, at: point) {
            view.mouseDown(with: down)
        }
        if let up = overviewEvent(.leftMouseUp, on: view, at: point) {
            view.mouseUp(with: up)
        }
    }

    private func synthesizeOverviewDrag(on view: NSView, from: CGPoint, to: CGPoint) {
        beginOverviewDrag(on: view, at: from)
        if let moved = overviewEvent(.leftMouseDragged, on: view, at: to) {
            view.mouseDragged(with: moved)
        }
        endOverviewDrag(on: view, at: to)
    }

    private func beginOverviewDrag(on view: NSView, at point: CGPoint) {
        if let down = overviewEvent(.leftMouseDown, on: view, at: point) {
            view.mouseDown(with: down)
        }
    }

    private func endOverviewDrag(on view: NSView, at point: CGPoint) {
        if let up = overviewEvent(.leftMouseUp, on: view, at: point) {
            view.mouseUp(with: up)
        }
    }
}
