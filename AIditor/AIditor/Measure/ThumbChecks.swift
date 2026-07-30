//
//  ThumbChecks.swift
//  Projekt AIditor
//
//  Kontrola miniatur na klipech — fáze 18, modul 5 (`--thumb-check`).
//
//  Pět otázek, každá na jednu věc, která by se dala pokazit tak, že by to
//  na první pohled fungovalo:
//
//  A) **Generuje se to a vede si to mezipaměť?** Studená disková cache proti
//     teplé: čas na dlaždici a hlavně SHODA obrázků. Cache, která vrací jiný
//     obrázek než generátor, je horší než žádná.
//  B) **Leží na dlaždici snímek z jejího zdrojového času?** Porovnání jasu
//     proti `AVAssetImageGenerator` volanému NAPŘÍMO, plus kontrola, že se
//     dlaždice liší od snímku ze vzdáleného času. Výřez i podvzorek si
//     kontrola dělá VLASTNÍ — kdyby použila kód z `ThumbnailStore`, ověřila
//     by jen to, že se tentýž kód chová dvakrát stejně.
//  C) **Trefuje se trimnutý klip?** Klip, který začíná v desáté sekundě
//     zdroje, nesmí v pásu ukazovat začátek souboru. Tohle je ta chyba,
//     která by v UI vypadala nejnevinněji.
//  D) **BRÁNA R1: sráží pás miniatur scroll?** ABBA na 2000 klipech při
//     zoomu, ve kterém se doopravdy stříhá (vzorec `--layers-check`: při
//     zoomu zátěžového testu je klip 20 bodů široký a miniatura se nekreslí,
//     takže by test měřil nulu proti nule). Měří se studená i teplá cache —
//     studená je horší případ, protože se generuje PŘI scrollu.
//  E) **Dluh z modulu 3:** anomálie příznaku `beats` (0,70 ms s vypnutými
//     dobami proti 0,29 se všemi zapnutými). Rozděluje se cena scrollovacího
//     tiku na `refreshClips` a kreslení pravítka — plán chtěl vysvětlení
//     právě v tomhle modulu.
//

import AVFoundation
import AppKit
import CoreMedia
import Foundation
import TimelineModel
import UniformTypeIdentifiers

extension AppModel {

    func verifyThumbnails() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — není z čeho brát miniatury"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        // Osa z reálných klipů: každý asset jeden klip na V1, zoom 5 bodů
        // na snímek (tři sekundy klipu = 450 bodů, tedy plný pás miniatur).
        let sources = timeline.project.assets.filter { $0.hasVideo && !$0.isStill }
        guard let first = sources.first else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        var trimmedClipID: ClipID?
        do {
            for (index, source) in sources.enumerated() {
                project.addAsset(source)
                // Druhý klip je TRIMNUTÝ o 10 sekund — část C.
                let sourceStart = index == 1
                    ? SourceTime(seconds: 10)
                    : project.timeline.sourceTime(.zero)
                let clip = Clip(assetID: source.id, timelineStart: Frames(index * 90),
                                duration: Frames(90), sourceStart: sourceStart)
                try project.insert(clip, onTrack: project.timeline.tracks[0].id)
                if index == 1 { trimmedClipID = clip.id }
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        var geometry = timeline.geometry
        geometry.setZoom(5)
        timeline.geometry = geometry
        timeline.project = project

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

        let store = timeline.thumbnails
        let side = ThumbnailStore.tileSidePoints
        let scale = window.backingScaleFactor
        let rung = ThumbnailStore.rung(for: timeline.geometry.pointsPerFrame)
        let secondsPerTile = ThumbnailStore.secondsPerTile(rung: rung, side: side)
        let url = first.url(usingProxies: timeline.project.usesProxies)
        let indices = Array(0..<6)

        print("=== A) generování a mezipaměť ===")
        print(String(format: "   zoom %.1f b/snímek → úroveň %.2f, %.3f s na dlaždici, hrana %.0f b @%.0fx",
                     timeline.geometry.pointsPerFrame, rung, secondsPerTile, side, scale))
        print("   zdroj: \(url.lastPathComponent)"
              + (timeline.project.usesProxies ? " (proxy)" : " (originál — proxy projekt nemá)"))

        // ⚠️ Vrstva se pro část A VYPÍNÁ, a je to podstatné: statistiky store
        // jsou globální, takže dokud pás na ose kreslí, míchají se do nich
        // požadavky view. První verze kontroly proto hlásila „vygenerováno
        // 12 dlaždic" na šest vyžádaných a část A padala, přestože kód byl
        // v pořádku. Store se dá oslovit přímo, takže izolace nic neztratí.
        timeline.layers.thumbnails = false
        // ⚠️ A od modulu 9 nestačí vypnout OSU: dlaždice si žádá i knihovna
        // médií (hrana 104) a ta je v okně pořád. Kontrola proto přepne rail
        // na `Řeč`, čímž se knihovna z horního pásu vymění za Zdroje řeči.
        // Bez toho hlásila „vygenerováno 7 dlaždic" v druhém průchodu a
        // vypadalo to na chybu v mezipaměti — chyba byla v izolaci měření.
        // (Našlo se v modulu 13; `--thumb-check` se od M6 nepouštěl.)
        let railBefore = railSection
        railSection = .speech
        try? await Task.sleep(nanoseconds: 700_000_000)
        defer { railSection = railBefore }

        // Studená cache: naše dlaždice se z disku vyhodí, aby se opravdu
        // generovaly. Je to mezipaměť, ne dokument — smazat ji jde.
        Self.clearThumbnailDiskCache()
        store.dropMemory()
        store.resetStats()

        let cold = await awaitTiles(store: store, url: url, rung: rung,
                                    indices: indices, side: side, scale: scale)
        let coldStats = store.stats
        check(cold.count == indices.count,
              "studená cache dodala všech \(indices.count) dlaždic (\(cold.count))")
        print(String(format: "   generováno %d dlaždic, %.1f ms na dlaždici",
                     coldStats.generated, coldStats.msPerGenerated))

        store.dropMemory()
        store.resetStats()
        let warm = await awaitTiles(store: store, url: url, rung: rung,
                                    indices: indices, side: side, scale: scale)
        let warmStats = store.stats
        print(String(format: "   z disku %d dlaždic, %.1f ms na dlaždici",
                     warmStats.fromDisk, warmStats.msPerDisk))
        check(warmStats.fromDisk == indices.count && warmStats.generated == 0,
              "druhý průchod vzal VŠECHNO z disku a negeneroval nic")
        check(warmStats.msPerDisk < coldStats.msPerGenerated,
              String(format: "z disku je to rychlejší (%.1f proti %.1f ms)",
                     warmStats.msPerDisk, coldStats.msPerGenerated))

        var mismatches = 0
        for index in indices {
            guard let a = cold[index], let b = warm[index],
                  let lumaA = Self.meanLuma(of: a), let lumaB = Self.meanLuma(of: b)
            else { mismatches += 1; continue }
            if abs(lumaA - lumaB) > 0.5 { mismatches += 1 }
        }
        check(mismatches == 0, "obrázek z cache je týž jako vygenerovaný (neshod: \(mismatches))")

        timeline.layers.thumbnails = true

        print("")
        print("=== B) dlaždice odpovídá svému zdrojovému času ===")
        // Přímo generátorem, s vlastním výřezem — nezávisle na `ThumbnailStore`.
        let probeIndex = 3
        let probeSeconds = Double(probeIndex) * secondsPerTile
        let farSeconds = probeSeconds + 20
        let direct = await Self.directFrame(url: url, seconds: probeSeconds,
                                           pixelSide: Int(side * scale))
        let far = await Self.directFrame(url: url, seconds: farSeconds,
                                         pixelSide: Int(side * scale))
        if let ours = cold[probeIndex], let ourLuma = Self.meanLuma(of: ours),
           let direct, let directLuma = Self.meanLuma(of: direct) {
            let farLuma = far.flatMap { Self.meanLuma(of: $0) }
            print(String(format: "   dlaždice %d (%.2f s): náš jas %.1f, napřímo %.1f, rozdíl %.2f",
                         probeIndex, probeSeconds, ourLuma, directLuma,
                         abs(ourLuma - directLuma)))
            if let farLuma {
                print(String(format: "   vzdálený snímek (%.2f s): jas %.1f, rozdíl proti naší %.2f",
                             farSeconds, farLuma, abs(ourLuma - farLuma)))
            }
            check(abs(ourLuma - directLuma) < 2.0,
                  String(format: "dlaždice je TÝŽ snímek jako z generátoru (rozdíl %.2f < 2)",
                         abs(ourLuma - directLuma)))
            if let farLuma {
                let distinguishes = abs(ourLuma - farLuma) > 2.0
                if distinguishes {
                    check(abs(ourLuma - directLuma) < abs(ourLuma - farLuma),
                          "a je BLÍŽ svému času než vzdálenému")
                } else {
                    print("   ⚠️ materiál se v tomhle úseku jasem nerozlišuje "
                          + "(rozdíl vzdáleného snímku je taky pod 2) — část B tím říká "
                          + "jen tolik, že dlaždice není prázdná ani z jiného souboru.")
                }
            }
        } else {
            check(false, "nepodařilo se získat dlaždici i přímý snímek k porovnání")
        }

        print("")
        print("=== C) trimnutý klip ukazuje trimnuté místo ===")
        timeline.selectClips([])
        pane.documentView.refreshClips()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let probe = pane.documentView.thumbnailProbe
        print("   nasazených dlaždic na ose: \(probe.count), "
              + "s obrázkem: \(probe.filter { $0.image != nil }.count)")
        if let trimmedClipID,
           let firstTile = probe.filter({ $0.clipID == trimmedClipID })
                                .min(by: { $0.index < $1.index }) {
            let tileSeconds = Double(firstTile.index) * secondsPerTile
            print(String(format: "   první dlaždice trimnutého klipu: index %d = %.2f s zdroje "
                         + "(klip začíná v 10,00 s)", firstTile.index, tileSeconds))
            check(tileSeconds >= 10 - secondsPerTile && tileSeconds < 10 + 2 * secondsPerTile,
                  "index dlaždice odpovídá trimu, ne začátku souboru")
            if let image = firstTile.image, let ourLuma = Self.meanLuma(of: image) {
                let atTrim = await Self.directFrame(url: sources[1].url(usingProxies: timeline.project.usesProxies),
                                                    seconds: tileSeconds,
                                                    pixelSide: Int(side * scale))
                let atZero = await Self.directFrame(url: sources[1].url(usingProxies: timeline.project.usesProxies),
                                                    seconds: 0, pixelSide: Int(side * scale))
                let trimLuma = atTrim.flatMap { Self.meanLuma(of: $0) }
                let zeroLuma = atZero.flatMap { Self.meanLuma(of: $0) }
                if let trimLuma, let zeroLuma {
                    print(String(format: "   jas: naše %.1f · v %.2f s %.1f · v 0 s %.1f",
                                 ourLuma, tileSeconds, trimLuma, zeroLuma))
                    check(abs(ourLuma - trimLuma) < 2.0,
                          "obsah dlaždice sedí na trimnutý čas")
                    if abs(trimLuma - zeroLuma) > 2.0 {
                        check(abs(ourLuma - trimLuma) < abs(ourLuma - zeroLuma),
                              "a NENÍ to snímek ze začátku souboru")
                    } else {
                        print("   ⚠️ začátek souboru a trimnuté místo mají shodný jas — "
                              + "rozlišit je tímhle materiálem nejde, platí jen kontrola indexu.")
                    }
                }
            } else {
                check(false, "na první dlaždici trimnutého klipu není obrázek")
            }
        } else {
            check(false, "trimnutý klip nemá v pásu ani jednu dlaždici")
        }

        // Vypnutá vrstva: ani jedna dlaždice, ani jeden požadavek (M3 vzorec).
        print("")
        print("=== C2) vypnutá vrstva se nepočítá ===")
        let onCounts = pane.documentView.drawnThumbCounts
        timeline.layers.thumbnails = false
        try? await Task.sleep(nanoseconds: 800_000_000)
        store.resetStats()
        pane.documentView.refreshClips()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let offCounts = pane.documentView.drawnThumbCounts
        print("   zapnuté: \(onCounts.tiles) dlaždic (\(onCounts.withImage) s obrázkem), "
              + "vypnuté: \(offCounts.tiles)")
        check(onCounts.withImage > 0, "se zapnutou vrstvou jsou v pásech obrázky")
        check(offCounts.tiles == 0, "s vypnutou vrstvou nezůstala ANI JEDNA dlaždice")
        check(store.stats.generated == 0 && store.pendingCount == 0,
              "s vypnutou vrstvou se nezadal ani jeden požadavek na generování")
        timeline.layers.thumbnails = true

        // Fotka: jedna dlaždice na celý pás, přes ImageIO. Vlastní část,
        // protože je to JINÁ CESTA než video (žádný `AVAsset`) — a v
        // `TestClips/` fotka není, takže by se nikdy nespustila.
        print("")
        print("=== C3) fotka má jednu dlaždici na celý pás ===")
        timeline.layers.thumbnails = true
        if let photoURL = Self.writeTestPhoto() {
            var withPhoto = timeline.project
            let photo = Asset.still(url: photoURL)
            withPhoto.addAsset(photo)
            if let v1 = withPhoto.timeline.tracks.first(where: { $0.kind == .video })?.id,
               let clip = try? withPhoto.makeClip(assetID: photo.id, at: withPhoto.duration),
               (try? withPhoto.insert(clip, onTrack: v1)) != nil {
                timeline.project = withPhoto
                timeline.selectClips([clip.id])
                // ⚠️ Fotka leží na KONCI osy, tedy mimo výřez — a co není
                // vidět, není nasazené a nemá dlaždice. (První verze téhle
                // části proto hlásila nulu a vypadalo to na chybu v kódu
                // fotek.) Osa se k ní musí odscrollovat.
                let clipView = pane.scrollView.contentView
                clipView.scroll(to: NSPoint(
                    x: max(0, timeline.geometry.x(for: clip.timelineStart) - 120),
                    y: clipView.bounds.origin.y))
                pane.scrollView.reflectScrolledClipView(clipView)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let photoTiles = pane.documentView.thumbnailProbe.filter { $0.clipID == clip.id }
                print("   dlaždic na klipu fotky: \(photoTiles.count), "
                      + "s obrázkem: \(photoTiles.filter { $0.image != nil }.count)")
                check(photoTiles.count == 1, "fotka má PRÁVĚ JEDNU dlaždici (\(photoTiles.count))")
                check(photoTiles.first?.image != nil, "a je na ní obrázek")
                if let image = photoTiles.first?.image, let luma = Self.meanLuma(of: image) {
                    // Testovací fotka je vodorovný přechod z černé do bílé,
                    // takže střední jas musí být kolem poloviny rozsahu.
                    print(String(format: "   jas dlaždice %.1f (čekáno ~128 u přechodu 0→255)", luma))
                    check(luma > 80 && luma < 176, "obsah dlaždice je ta fotka, ne prázdno")
                }
            } else {
                check(false, "fotku se nepodařilo položit na osu")
            }
        } else {
            check(false, "testovací fotku se nepodařilo zapsat")
        }

        await verifyThumbnailScroll(pane: pane, check: check)
        await explainBeatsAnomaly(pane: pane)

        print("")
        print(failures == 0 ? "✅ MINIATURY SEDÍ" : "❌ neshod: \(failures)")
    }

    // MARK: - D) brána R1

    private func verifyThumbnailScroll(pane: TimelinePane,
                                       check: (Bool, String) -> Void) async {
        print("")
        print("=== D) BRÁNA R1: scroll s miniaturami (2000 klipů, zoom 5) ===")

        timeline.loadStressProject(from: clips, pairs: 1000)
        var geometry = timeline.geometry
        geometry.setZoom(5)
        timeline.geometry = geometry
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        let clipCount = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        isMeasuring = true
        defer { isMeasuring = false }

        // Studená cache je horší případ: generuje se PŘI scrollu. Měří se
        // dvakrát — s VYNUCENÝM generováním za jízdy (cesta, která se
        // v aplikaci nikdy nespustí, a proto by tiše shnila) a s odkladem,
        // jak to appka dělá.
        timeline.layers.thumbnails = true
        for deferral in [false, true] {
            Self.clearThumbnailDiskCache()
            timeline.thumbnails.dropMemory()
            timeline.thumbnails.resetStats()
            timeline.thumbnails.deferralEnabled = deferral
            try? await Task.sleep(nanoseconds: 800_000_000)
            let run = await TimelineScrollBenchmark(pane: pane, clipCount: clipCount).run()
            print(String(format: "   studená cache, odklad %@: medián %.2f ms · maximum %.2f ms "
                         + "· vypadlé tiky %d (vygenerováno %d dlaždic za jízdy)",
                         (deferral ? "ZAPNUTÝ " : "vypnutý") as NSString,
                         run.medianWorkMs, run.maxWorkMs, run.droppedTicks,
                         timeline.thumbnails.stats.generated))
            if deferral {
                check(run.droppedTicks == 0,
                      "studená cache s odkladem: 0 vypadlých tiků (\(run.droppedTicks))")
                check(timeline.thumbnails.stats.generated == 0,
                      "za jízdy se nevygenerovala ani jedna dlaždice "
                      + "(\(timeline.thumbnails.stats.generated))")
            }
        }
        timeline.thumbnails.deferralEnabled = true

        // A co to stojí PO zastavení: pás se musí doplnit, a to za dobu,
        // po kterou se uživatel nedívá na prázdno moc dlouho.
        let settleStart = Date()
        while timeline.thumbnails.isBusy, Date().timeIntervalSince(settleStart) < 20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let counts = pane.documentView.drawnThumbCounts
        print(String(format: "   po zastavení: pás doplněn za %.1f s "
                     + "(%d dlaždic, %d s obrázkem, %d vygenerováno)",
                     Date().timeIntervalSince(settleStart),
                     counts.tiles, counts.withImage, timeline.thumbnails.stats.generated))
        check(counts.withImage > 0, "po zastavení jsou v pásech obrázky")

        // Teplá cache, ABBA proti vypnuté vrstvě.
        var runs: [(on: Bool, result: TimelineScrollResult)] = []
        for on in [true, false, false, true] {
            timeline.layers.thumbnails = on
            try? await Task.sleep(nanoseconds: 700_000_000)
            runs.append((on, await TimelineScrollBenchmark(pane: pane,
                                                          clipCount: clipCount).run()))
        }
        for (on, result) in runs {
            print(String(format: "   %-8@ medián %5.2f ms · maximum %5.2f ms · vypadlé tiky %d",
                         (on ? "s pásem" : "bez") as NSString,
                         result.medianWorkMs, result.maxWorkMs, result.droppedTicks))
        }
        func mean(_ selector: Bool) -> Double {
            let values = runs.filter { $0.on == selector }.map(\.result.medianWorkMs)
            return values.reduce(0, +) / Double(max(1, values.count))
        }
        print(String(format: "   s pásem %.2f ms · bez pásu %.2f ms · rozdíl %.2f ms "
                     + "(rozpočet na tik 16,67)",
                     mean(true), mean(false), mean(true) - mean(false)))
        check(runs.allSatisfy { $0.result.droppedTicks == 0 },
              "teplá cache: 0 vypadlých tiků ve všech čtyřech bězích")
        check(runs.allSatisfy { $0.result.windowWasVisible },
              "okno bylo po celou dobu vidět (jinak je běh neplatný)")

        // A totéž při zoomu FORMÁLNÍ brány (`--timeline-bench`, celá osa do
        // 40 000 bodů). Klipy tam mají 20–65 bodů, takže pás dostanou jen ty
        // delší — ale dostanou. Bez tohohle by se nedalo říct, čím se změnil
        // medián formální brány proti modulu 4.
        var stressGeometry = timeline.geometry
        stressGeometry.setZoom(40_000 / Double(max(1, timeline.project.duration.count)))
        timeline.geometry = stressGeometry
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        print(String(format: "   — a při zoomu formální brány (%.3f b/snímek) —",
                     timeline.geometry.pointsPerFrame))
        var stressRuns: [(on: Bool, result: TimelineScrollResult, tiles: Int)] = []
        for on in [true, false, false, true] {
            timeline.layers.thumbnails = on
            try? await Task.sleep(nanoseconds: 700_000_000)
            let result = await TimelineScrollBenchmark(
                pane: pane, clipCount: clipCount, secondsPerPass: 5).run()
            // Počet dlaždic se musí přečíst HNED po běhu, ne až při výpisu:
            // do té doby se vrstva přepne a čísla by patřila jiné konfiguraci
            // (první verze kontroly hlásila 14 dlaždic i u vypnutého pásu).
            stressRuns.append((on, result, pane.documentView.drawnThumbCounts.tiles))
        }
        for run in stressRuns {
            print(String(format: "   %-8@ medián %5.2f ms · maximum %5.2f ms · vypadlé tiky %d "
                         + "· dlaždic na ose %d",
                         (run.on ? "s pásem" : "bez") as NSString,
                         run.result.medianWorkMs, run.result.maxWorkMs,
                         run.result.droppedTicks, run.tiles))
        }
        func stressMean(_ selector: Bool) -> Double {
            let values = stressRuns.filter { $0.on == selector }.map { $0.result.medianWorkMs }
            return values.reduce(0, +) / Double(max(1, values.count))
        }
        print(String(format: "   s pásem %.2f ms · bez pásu %.2f ms · rozdíl %.2f ms",
                     stressMean(true), stressMean(false),
                     stressMean(true) - stressMean(false)))
        check(stressRuns.allSatisfy { $0.result.droppedTicks == 0 },
              "zoom formální brány: 0 vypadlých tiků ve všech čtyřech bězích")

        timeline.layers.thumbnails = true
    }

    // MARK: - E) dluh z modulu 3: anomálie příznaku `beats`

    /// Modul 3 naměřil s vypnutými dobami DRAŽŠÍ scroll (0,70 proti 0,29 ms),
    /// přestože `drawBeatMarks` tehdy dělá striktně méně práce. Scrollovací
    /// tik měří `scroll(to:)` + `reflectScrolledClipView`, a v tom je
    /// `syncChrome`: `refreshClips` **a** `needsDisplay` pravítka. Rozdělíme
    /// to na kusy a změříme každý zvlášť.
    private func explainBeatsAnomaly(pane: TimelinePane) async {
        print("")
        print("=== E) anomálie příznaku `beats` z modulu 3 ===")

        isMeasuring = true
        defer { isMeasuring = false }

        func measure(_ label: String, iterations: Int = 200,
                     body: () -> Void) -> Double {
            body()   // rozjezd, ať se neměří první líné vytvoření vrstev
            let started = CACurrentMediaTime()
            for _ in 0..<iterations { body() }
            return (CACurrentMediaTime() - started) * 1000 / Double(iterations)
        }

        let clipCount = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        print("   (\(clipCount) klipů, zoom \(String(format: "%.1f", timeline.geometry.pointsPerFrame)) b/snímek)")
        for beats in [true, false, true, false] {
            timeline.layers.beats = beats
            try? await Task.sleep(nanoseconds: 400_000_000)
            let refresh = measure("refresh") { pane.documentView.refreshClips() }
            let ruler = measure("pravítko") { pane.rulerView.display() }
            // Týž údaj, jaký měřil modul 3: `scroll(to:)` + `reflectScrolledClipView`.
            let tick = await TimelineScrollBenchmark(pane: pane, clipCount: clipCount,
                                                    secondsPerPass: 4).run()
            print(String(format: "   doby %@: refreshClips %.3f · pravítko %.3f · SOUČET %.3f ms"
                         + "  |  scrollovací tik (metrika M3) %.3f ms, vypadlé tiky %d",
                         (beats ? "zapnuté" : "vypnuté") as NSString,
                         refresh, ruler, refresh + ruler, tick.medianWorkMs, tick.droppedTicks))
        }
        timeline.layers.beats = true
        print("")
        print("   VYSVĚTLENÍ: práce dob žije v KRESLENÍ PRAVÍTKA (`beatMarks()` prochází")
        print("   všechny zvukové klipy, tady tisíc), a scrollovací tik měří `scroll(to:)`")
        print("   + `reflectScrolledClipView`, tedy `refreshClips` a nastavení `needsDisplay` —")
        print("   pravítko se kreslí až v dalším průchodu smyčkou, VNĚ měřeného okna.")
        print("   `refreshClips` je na příznaku nezávislý, takže modul 3 měřil tu část tiku,")
        print("   ve které o dobách nic není. Přepínač ubírá práci tam, kde ji dělá.")
    }

    // MARK: - Pomocníci

    /// Smaže naši diskovou mezipaměť miniatur. Je to mezipaměť: co se smaže,
    /// se dopočítá. Sáhne se JEN do vlastní složky v kontejneru aplikace.
    private static func clearThumbnailDiskCache() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Testovací fotka do kontejneru aplikace: vodorovný přechod černá →
    /// bílá, 1600×900. Do kontejneru schválně — sandbox ho pustí bez
    /// bookmarku (vzorec `freezeFrame`), a v `TestClips/` žádná fotka není.
    private static func writeTestPhoto() -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask).first else { return nil }
        let folder = directory.appendingPathComponent("ThumbCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("prechod.png")

        let width = 1600, height = 900
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(gray: 0, alpha: 1),
                                                 CGColor(gray: 1, alpha: 1)] as CFArray,
                                        locations: [0, 1])
        else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: Double(width), y: 0), options: [])
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    private func awaitTiles(store: ThumbnailStore, url: URL, rung: Double,
                            indices: [Int], side: Double, scale: CGFloat,
                            timeout: TimeInterval = 60) async -> [Int: CGImage] {
        var result: [Int: CGImage] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for index in indices where result[index] == nil {
                if let image = store.tile(url: url, rung: rung, index: index,
                                          side: side, scale: scale) {
                    result[index] = image
                }
            }
            if result.count == indices.count { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return result
    }

    /// Snímek napřímo, s VLASTNÍM čtvercovým výřezem. Schválně samostatná
    /// implementace: kontrola, která by si výřez vzala z `ThumbnailStore`,
    /// by ověřila jen to, že tentýž kód dvakrát udělá totéž.
    private static func directFrame(url: URL, seconds: Double,
                                    pixelSide: Int) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(value: CMTimeValue((seconds * 30_000).rounded()), timescale: 30_000)
        guard let full = try? await generator.image(at: time).image else { return nil }

        let side = Double(pixelSide)
        let scale = max(side / Double(full.width), side / Double(full.height))
        guard let context = CGContext(data: nil, width: pixelSide, height: pixelSide,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let width = Double(full.width) * scale
        let height = Double(full.height) * scale
        context.draw(full, in: CGRect(x: (side - width) / 2, y: (side - height) / 2,
                                      width: width, height: height))
        return context.makeImage()
    }

    /// Průměrný jas 0–255 z podvzorku 16×16. Jas, ne rozdíl pixel po pixelu:
    /// naše dlaždice je zmenšená interpolací a přímý snímek jinou cestou,
    /// takže bit po bitu se rovnat nebudou ani u téhož snímku — kdežto jas
    /// dvou různých snímků se u pohyblivého záběru liší spolehlivě.
    private static func meanLuma(of image: CGImage, side: Int = 16) -> Double? {
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(data: &pixels, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let sum = pixels.reduce(0) { $0 + Int($1) }
        return Double(sum) / Double(pixels.count)
    }
}
