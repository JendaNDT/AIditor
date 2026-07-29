//
//  ShellChecks.swift
//  Projekt Krása — Measure
//
//  Fáze 18, modul 1. Kontroly nové skořápky:
//
//  `--shell-check`  geometrie okna proti tabulce návrhu, v okně I na celé
//                   obrazovce. Měří se ze SKUTEČNÝCH view v hierarchii
//                   (`TimelinePane`, `PlayerHostView`), ne z konstant —
//                   porovnávat konstantu se sebou samou nic nedokazuje.
//  `--shell-gpu`    riziko R2 plánu: pilulka transportu, čipy a měřidlo leží
//                   NA obraze, takže náhled musí být trvale skládaný. Změří
//                   tentýž klip s overlaji a bez nich.
//  `--shell-demo`   koukanec pro oko a screenshot.
//

import AppKit
import AVFoundation
import Foundation
import TimelineModel

extension AppModel {

    // MARK: - Geometrie skořápky

    /// Očekávané odsazení podle zadání návrhu. Počítá se ze stejných tokenů,
    /// jaké kreslí skořápku, ALE poskládané ručně podle tabulky z README —
    /// když se v `AppShell` splete pořadí pater, tenhle součet to chytí.
    private struct ExpectedInsets {
        let paneLeft: CGFloat
        let paneTop: CGFloat
        let paneRight: CGFloat
        let paneBottom: CGFloat
        let viewerLeft: CGFloat
        let viewerTop: CGFloat

        init(mode: ShellMode, panelVisible: Bool) {
            let hairline: CGFloat = 1
            let toolbar = mode.toolbarHeight
            let topBand = mode.topBandHeight
            paneLeft = KrasaUI.Metric.railWidth + hairline
            paneTop = toolbar + hairline + topBand + hairline
                + KrasaUI.Metric.timelineToolbarHeight + hairline
            paneRight = panelVisible ? KrasaUI.Metric.pinnedPanelWidth + hairline : 0
            paneBottom = KrasaUI.Metric.statusBarHeight + hairline
            viewerLeft = paneLeft + KrasaUI.Metric.viewerPadding
            viewerTop = toolbar + hairline + KrasaUI.Metric.viewerPadding
        }
    }

    /// Odsazení view od hran obsahu okna, přepočtené na soustavu s počátkem
    /// vlevo NAHOŘE — v ní je psané zadání i celá tahle kontrola.
    ///
    /// ⚠️ Obsah SwiftUI okna je `NSHostingView`, a ten je **flipped**: `minY`
    /// je vzdálenost od HORNÍ hrany, ne od spodní. Kdo to nezkontroluje,
    /// dostane odsazení shora a zdola prohozená — a protože obě čísla vyjdou
    /// „nějak rozumně", vypadá to jako chyba v layoutu, ne v měření.
    /// První verze téhle kontroly na to naletěla.
    private static func insets(of view: NSView, in content: NSView)
        -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        let frame = view.convert(view.bounds, to: content)
        let fromTop = content.isFlipped ? frame.minY : content.bounds.height - frame.maxY
        let fromBottom = content.isFlipped ? content.bounds.height - frame.maxY : frame.minY
        return (left: frame.minX, top: fromTop,
                right: content.bounds.width - frame.maxX, bottom: fromBottom)
    }

    func verifyShellGeometry() async {
        guard let host = await shellHostView(), let window = host.window,
              let content = window.contentView else {
            print("❌ přehrávač nemá okno — není co měřit"); return
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Skořápka musí mít po startu čas se srovnat; `TimelinePane` se do
        // hierarchie dostane až po prvním layoutu.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        var failures = 0

        failures += await measureShell(label: "OKNO", mode: .window,
                                       host: host, content: content)

        print("")
        print("=== přepínám na celou obrazovku (⌃⌘F) ===")
        guard await FullScreenSwitch.set(true, on: window) else {
            print("❌ přechod do fullscreenu se nestihl"); return
        }
        failures += await measureShell(label: "CELÁ OBRAZOVKA", mode: .fullscreenApp,
                                       host: host, content: content)

        // Kontrola, že se fullscreen doopravdy projevil na PLOŠE OBRAZU, ne
        // jen na příznaku — bit `styleMask` se přepíná už na začátku přechodu.
        let fullscreenArea = host.videoBackingPixelSize
        _ = await FullScreenSwitch.set(false, on: window)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let windowArea = host.videoBackingPixelSize
        let grew = fullscreenArea.width * fullscreenArea.height
            > windowArea.width * windowArea.height
        print("")
        print("plocha obrazu: okno \(Int(windowArea.width))×\(Int(windowArea.height))"
              + " → fullscreen \(Int(fullscreenArea.width))×\(Int(fullscreenArea.height))"
              + " \(grew ? "✅ vzrostla" : "❌ NEVZROSTLA")")
        if !grew { failures += 1 }

        print("")
        print(failures == 0
              ? "✅ SKOŘÁPKA SEDÍ NA ZADÁNÍ (okno i celá obrazovka)"
              : "❌ neshod: \(failures)")
    }

    /// Jedno kolo měření. Vrací počet neshod.
    private func measureShell(label: String, mode: ShellMode,
                              host: PlayerHostView, content: NSView) async -> Int {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard let pane = timelinePane else {
            print("❌ \(label): osa není v hierarchii"); return 1
        }

        let expected = ExpectedInsets(mode: mode, panelVisible: panelVisible)
        let paneInsets = Self.insets(of: pane, in: content)
        let viewerInsets = Self.insets(of: host, in: content)

        print("")
        print("── \(label) · obsah okna \(Int(content.bounds.width))×\(Int(content.bounds.height))"
              + " · flipped \(content.isFlipped) ──")
        print("   surově: osa \(pane.convert(pane.bounds, to: content))"
              + " · obraz \(host.convert(host.bounds, to: content))")

        var failures = 0
        func check(_ name: String, _ measured: CGFloat, _ want: CGFloat) {
            // Půl bodu tolerance: retina layout zaokrouhluje na půlpixely.
            let ok = abs(measured - want) <= 0.5
            if !ok { failures += 1 }
            print(String(format: "%@ %-28@ %7.1f   čekáno %6.1f",
                         ok ? "✅" : "❌", name as NSString, measured, want))
        }

        check("osa zleva (rail)", paneInsets.left, expected.paneLeft)
        check("osa shora (lišty)", paneInsets.top, expected.paneTop)
        check("osa zprava (panel)", paneInsets.right, expected.paneRight)
        check("osa zdola (stav. řádek)", paneInsets.bottom, expected.paneBottom)
        check("obraz zleva", viewerInsets.left, expected.viewerLeft)
        check("obraz shora", viewerInsets.top, expected.viewerTop)

        // Pravítko a hlavičky si drží svoje rozměry z fáze 2 — návrh je
        // v M1 nemění a nesmí je rozhodit ani nová skořápka.
        check("pravítko", TimelineRulerView.height, 26)
        check("hlavičky stop", TrackHeadersView.width, 96)
        return failures
    }

    // MARK: - Riziko R2: co stojí overlaye nad obrazem

    /// Změří tentýž klip DVAKRÁT: jednou s pilulkou, čipy a měřidlem nad
    /// obrazem, podruhé bez nich.
    ///
    /// ⚠️ Sama appka GPU rezidenci nezměří — ta se čte z `powermetrics`
    /// vedle. Kontrola proto tiskne zřetelné značky začátku a konce každé
    /// fáze, aby šel log rozříznout, a k tomu vydá čísla, která změřit umí
    /// (doručené snímky, dlouhé mezery mezi tiky, zahozené snímky).
    func runShellGPUComparison(only paths: [String] = []) async {
        guard let host = await shellHostView() else {
            print("❌ přehrávač nemá okno"); return
        }
        var targets = await resolveTargetsForShell(paths)
        if paths.isEmpty, let selected { targets = [selected] }
        guard let clip = targets.first else {
            print("❌ není co měřit — vyber klip nebo předej cestu"); return
        }

        host.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        print("═══ OVERLAYE NAD OBRAZEM: ZAPNUTÉ vs VYPNUTÉ ═══")
        print("klip: \(clip.name)")
        print("Vedle pusť: sudo powermetrics --samplers gpu_power -i 1000 > ~/krasa_shell_gpu.txt")
        print("")

        // Zahřívací běh — jinak by první stav měřil studený stroj.
        _ = await PlaybackBenchmark().run(url: clip.url, timing: clip,
                                          controller: controller, hostView: host)
        await coolDownForShell()

        var results: [(String, BenchmarkResult)] = []
        // ABBA: druhý stav by jinak vždycky běžel na teplejším stroji.
        for (index, overlaysOn) in [true, false, false, true].enumerated() {
            overlaysSuppressed = !overlaysOn
            // Skořápka se musí přelayoutovat, než se začne měřit.
            try? await Task.sleep(nanoseconds: 800_000_000)
            let label = overlaysOn ? "S OVERLAJI" : "BEZ OVERLAJŮ"
            print(">>> FÁZE \(index + 1)/4 — \(label) — START \(Date())")
            let result = await PlaybackBenchmark().run(url: clip.url, timing: clip,
                                                       controller: controller, hostView: host)
            print("<<< FÁZE \(index + 1)/4 — \(label) — KONEC \(Date())")
            results.append((label, result))
            await coolDownForShell()
        }
        overlaysSuppressed = false

        print("")
        print(String(format: "%-14@ %9@ %9@ %9@ %9@",
                     "stav" as NSString, "fps" as NSString, "min fps" as NSString,
                     "dl. mezery" as NSString, "zahozené" as NSString))
        for (label, result) in results {
            print(String(format: "%-14@ %9.2f %9.0f %9d %9d",
                         label as NSString, result.steadyStateFPS, result.minDeliveredFPS,
                         result.longTickGaps, result.droppedFramesFromAccessLog))
        }
        let withOverlays = results.filter { $0.0 == "S OVERLAJI" }.map { $0.1.steadyStateFPS }
        let without = results.filter { $0.0 == "BEZ OVERLAJŮ" }.map { $0.1.steadyStateFPS }
        if !withOverlays.isEmpty, !without.isEmpty {
            let a = withOverlays.reduce(0, +) / Double(withOverlays.count)
            let b = without.reduce(0, +) / Double(without.count)
            print("")
            print(String(format: "průměr s overlaji %.2f fps · bez %.2f fps · rozdíl %+.2f fps",
                         a, b, a - b))
        }
        print("")
        print("⚠️ GPU rezidenci přečti z powermetrics podle značek FÁZE výše —")
        print("   doručené snímky ji nenahrazují, měří něco jiného.")
    }

    // MARK: - Koukanec

    /// Postaví osu s klipy, presetem a rampou, aby bylo vidět chrome
    /// i čipy nad obrazem. Nic neměří — je to pro oko a screenshot.
    func runShellDemo() async {
        guard let source = timeline.project.assets
            .filter({ $0.hasVideo && !$0.isStill })
            .max(by: { $0.duration.seconds < $1.duration.seconds }) else {
            print("❌ žádný video asset"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        var firstClip: ClipID?
        do {
            for (index, start) in [0, 90, 180, 270].enumerated() {
                let clip = Clip(assetID: source.id, timelineStart: Frames(start),
                                duration: Frames(90),
                                sourceStart: project.timeline.sourceTime(Frames(index * 120)))
                try project.insert(clip, onTrack: project.timeline.tracks[0].id)
                if firstClip == nil { firstClip = clip.id }
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        var geometry = timeline.geometry
        geometry.setZoom(5)
        timeline.geometry = geometry
        timeline.project = project

        if let firstClip {
            timeline.selectClips([firstClip])
            // Preset a rampa jsou tu kvůli čipům na obraze — bez nich by
            // demo ukázalo prázdný levý horní roh.
            timeline.setColorGrade(firstClip, ColorGrade(preset: .warmFilm, intensity: 0.62))
            timeline.toggleClassicRamp(firstClip)
        }
        status = "Rampa 1× → 0,25× nastavena · ⌘Z vrátí"

        if let host = await shellHostView() {
            host.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }

    // MARK: - Pomocníci

    /// `waitForPlayerWindow` je v `AppModelu` privátní; kontroly skořápky
    /// si čekání dělají samy, aby se kvůli nim nemusela otevírat.
    private func shellHostView(timeout: TimeInterval = 10) async -> PlayerHostView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let view = hostView, view.window != nil { return view }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    private func resolveTargetsForShell(_ paths: [String]) async -> [ClipTiming] {
        guard !paths.isEmpty else { return clips }
        return clips.filter { clip in
            paths.contains { clip.url.path.hasSuffix($0) || $0.hasSuffix(clip.name) }
        }
    }

    /// Air je bezventilátorový — bez chladnutí měří druhý běh teplejší stroj.
    private func coolDownForShell() async {
        try? await Task.sleep(nanoseconds: Self.coolDownSeconds * 1_000_000_000)
    }
}
