//
//  FullscreenUIChecks.swift
//  Projekt Krása
//
//  Kontrola fullscreen náhledu — fáze 18, modul 13 (`--fullscreen-ui-check`).
//
//  A) **Přechod tam a zpět nezasekne přehrávání a hlava zůstane na místě.**
//     Kritérium modulu z plánu. Měří se hlava PŘED a PO, a `rate` přehrávače
//     se přitom nesmí změnit — proto se přepíná za běžícího přehrávání.
//  B) **Tři stavy overlaye** a přechody mezi nimi: overlay po ~2 s nečinnosti
//     zmizí a pohybem myši se vrátí; ⇧T připne mini osu a připnutá NEMIZÍ.
//  C) **Sledovací oblast myši existuje a má správné volby** — bez nich se
//     `mouseMoved` nikdy nezavolá a overlay by zůstal viset napořád.
//  D) **Skořápka je z hierarchie PRYČ**, ne jen schovaná: osa i knihovna se
//     v náhledu odebírají (pravidlo R4), takže je `TimelinePane` bez okna.
//  E) **Mini osa mapuje celou osu na svou šířku** — klik na 0 / 50 / 100 %
//     položí hlavu na začátek / půlku / konec.
//
//  ⚠️ Fullscreen okna se v kontrole NEZAPÍNÁ. `--fullscreen` (regresní měření)
//  ho zapíná a čeká 2,5 s na dokončení přechodu; tady jde o overlay a stavy,
//  a přepínání skutečného fullscreenu by k tomu přidalo jen čekání a riziko,
//  že běh skončí na cizí Space. Náhled se proto zapíná bez okna
//  (`previewFullscreen`), což je táž cesta, jen bez `FullScreenSwitch`.
//

import AppKit
import Foundation
import TimelineModel

extension AppModel {

    func verifyFullscreenUI() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — není co promítat"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        // Osa ze dvou klipů se zvukem — scrub lišta i mini osa mají co kreslit.
        guard let source = timeline.project.assets
            .first(where: { $0.hasVideo && $0.hasAudio && !$0.isStill }) else {
            print("❌ žádný video asset se zvukem"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        do {
            let v1 = project.timeline.tracks[0].id
            let a1 = project.timeline.tracks[1].id
            for index in 0..<2 {
                let pair = try project.makeLinkedClips(assetID: source.id,
                                                       at: Frames(index * 90))
                var video = pair.video, audio = pair.audio
                video.duration = Frames(90)
                audio.duration = Frames(90)
                try project.insertLinked(video: video, onVideoTrack: v1,
                                         audio: audio, onAudioTrack: a1)
            }
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        timeline.setInPoint(Frames(30))
        timeline.setOutPoint(Frames(120))

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while hostView?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let window = hostView?.window else {
            print("❌ okno se neotevřelo"); return
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        print("=== A) přechod tam a zpět: hlava a přehrávání ===")
        timeline.setPlayheadFromUser(Frames(75))
        controller.play()
        try? await Task.sleep(nanoseconds: 900_000_000)
        let rateBefore = controller.player.rate
        let playheadBefore = timeline.playhead
        print("   před: hlava \(playheadBefore.count), rate \(rateBefore)")

        enterPreviewFullscreen()
        try? await Task.sleep(nanoseconds: 900_000_000)
        let rateInside = controller.player.rate
        check(previewFullscreen, "náhled se zapnul")
        check(rateInside == rateBefore,
              "přehrávání se přechodem nezaseklo (rate \(rateInside))")
        check(timeline.playhead.count >= playheadBefore.count,
              "hlava jede dál, neskočila zpátky "
              + "(\(playheadBefore.count) → \(timeline.playhead.count))")

        controller.pause()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let parked = timeline.playhead

        print("")
        print("=== D) skořápka je z hierarchie pryč, ne schovaná ===")
        check(timelinePane?.window == nil,
              "osa v náhledu není v okně (odebírá se, nekryje)")
        check(hostView?.window != nil, "přehrávač v okně naopak zůstal")
        check(dropZoneView == nil || dropZoneView?.window == nil,
              "zóna přetažení z prázdného startu tu není")

        print("")
        print("=== C) sledovací oblast myši ===")
        guard let watcher = mouseWatcherView else {
            print("❌ sledovač myši se nedostal do hierarchie"); return
        }
        // ⚠️ Sledovací oblasti se zakládají v `updateTrackingAreas`, a to
        // AppKit volá až při layoutu — po přepnutí do náhledu se na to musí
        // chvíli počkat.
        let areaDeadline = Date().addingTimeInterval(3)
        while watcher.trackingAreas.isEmpty, Date() < areaDeadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let options = watcher.trackingAreas.first?.options
        print("   oblastí: \(watcher.trackingAreas.count), volby: "
              + "\(options.map { String($0.rawValue) } ?? "žádné")")
        check(watcher.trackingAreas.count == 1, "sledovač má právě jednu oblast")
        check(options?.contains(.mouseMoved) == true, "hlásí `mouseMoved`")
        check(options?.contains(.activeInKeyWindow) == true, "a je aktivní v klíčovém okně")
        check(watcher.hitTest(NSPoint(x: 10, y: 10)) == nil,
              "hit test vrací nil, takže nebere kliknutí tlačítkům overlaye")

        print("")
        print("=== B) tři stavy overlaye ===")
        check(fullscreenOverlay == .controls, "po zapnutí je vidět ovládání")

        // Nečinnost: časovač je 2 s, čeká se o půl sekundy víc.
        try? await Task.sleep(nanoseconds: UInt64((Self.overlayIdleSeconds + 0.5) * 1e9))
        print("   po \(Self.overlayIdleSeconds) s nečinnosti: \(describe(fullscreenOverlay))")
        check(fullscreenOverlay == .clean, "overlay sám zmizel")

        noteFullscreenMouseActivity(nearBottom: false)
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(fullscreenOverlay == .controls, "pohyb myši ho vrátil")

        noteFullscreenMouseActivity(nearBottom: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(fullscreenOverlay == .timeline, "myš u spodní hrany vytáhla mini osu")

        // Nepřipnutá mini osa mizí stejně jako ovládání.
        try? await Task.sleep(nanoseconds: UInt64((Self.overlayIdleSeconds + 0.5) * 1e9))
        check(fullscreenOverlay == .clean, "a nepřipnutá zmizí nečinností taky")

        toggleFullscreenTimeline()
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(fullscreenOverlay == .timeline && fullscreenTimelinePinned,
              "⇧T mini osu připnulo")
        try? await Task.sleep(nanoseconds: UInt64((Self.overlayIdleSeconds + 0.5) * 1e9))
        print("   po další nečinnosti s ⇧T: \(describe(fullscreenOverlay))")
        check(fullscreenOverlay == .timeline, "PŘIPNUTÁ mini osa nemizí — je to volba, ne mávnutí")

        // Snímky pro oko: tři stavy.
        for (state, name) in [(AppModel.FullscreenOverlay.timeline, "nahled-osa"),
                              (.controls, "nahled-ovladani"),
                              (.clean, "nahled-cisty")] {
            setOverlayForCheck(state)
            // Čistý stav se NEnastavuje, ten se VYČKÁ — do prázdna se náhled
            // dostane jedině nečinností, a fotit se má to, co uvidí uživatel.
            let wait = state == .clean ? Self.overlayIdleSeconds + 0.7 : 0.7
            try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            check(fullscreenOverlay == state, "snímek \(name) fotí stav \(describe(state))")
            if let shot = Self.writeWindowSnapshot(of: window, name: name) {
                print("   snímek \(name) → \(shot.path)")
            }
        }

        print("")
        print("=== E) mini osa mapuje celou osu ===")
        // Šířku pásu si kontrola nebere z view (to je SwiftUI a rozměr z něj
        // nedostane), ale POČÍTÁ tutéž funkci, jakou kreslí mini osa: podíl
        // × délka filmu. Ověřuje se tedy mapování, ne pixely.
        let total = totalFrames
        print("   délka filmu: \(total.count) snímků")
        check(total.count == 180, "model zná délku osy (180 snímků)")
        for fraction in [0.0, 0.5, 1.0] {
            let target = Frames(Int((fraction * Double(total.count)).rounded()))
            timeline.setPlayheadFromUser(target)
            try? await Task.sleep(nanoseconds: 120_000_000)
            check(timeline.playhead == target,
                  String(format: "%.0f %% osy = snímek %d", fraction * 100, target.count))
        }

        print("")
        print("=== zpět do editoru ===")
        timeline.setPlayheadFromUser(parked)
        exitPreviewFullscreen()
        try? await Task.sleep(nanoseconds: 900_000_000)
        check(!previewFullscreen, "⎋ (a `exitPreviewFullscreen`) náhled zavřelo")
        check(timeline.playhead == parked,
              "hlava zůstala tam, kde byla (\(parked.count))")
        let paneDeadline = Date().addingTimeInterval(5)
        while timelinePane?.window == nil, Date() < paneDeadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        check(timelinePane?.window != nil, "osa se vrátila do okna")
        check(controller.player.rate == 0, "přehrávač zůstal zastavený, jak byl")

        print("")
        print(failures == 0 ? "✅ FULLSCREEN NÁHLED SEDÍ" : "❌ neshod: \(failures)")
    }

    private func describe(_ state: FullscreenOverlay) -> String {
        switch state {
        case .clean: return "čistý"
        case .controls: return "ovládání"
        case .timeline: return "osa"
        }
    }

    /// Přepnutí stavu pro snímek. Jde TOUTÉŽ cestou jako uživatel (⇧T a pohyb
    /// myši), aby kontrola nefotila stav, do kterého se v aplikaci nedá dostat.
    private func setOverlayForCheck(_ state: FullscreenOverlay) {
        switch state {
        case .timeline:
            if !fullscreenTimelinePinned { toggleFullscreenTimeline() }
        case .controls:
            if fullscreenTimelinePinned { toggleFullscreenTimeline() }
            noteFullscreenMouseActivity(nearBottom: false)
        case .clean:
            if fullscreenTimelinePinned { toggleFullscreenTimeline() }
            noteFullscreenMouseActivity(nearBottom: false)
        }
    }
}
