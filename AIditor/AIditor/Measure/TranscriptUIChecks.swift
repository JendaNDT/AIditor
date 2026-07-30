//
//  TranscriptUIChecks.swift
//  Projekt AIditor
//
//  Kontrola panelu přepisu řeči — fáze 18, modul 11 (`--transcript-ui-check`).
//
//  A) **Oprava textu se projeví v `.srt`** — a je to JEDEN undo krok.
//     Kritérium modulu z plánu. Přepis patří assetu, takže se změna musí
//     objevit u VŠECH klipů z toho zdroje; to se měří dvěma klipy.
//  B) **„Rozdělit v kurzoru" dá dva úseky se správnými časy** — a součet
//     jejich délek se rovná původní.
//  C) **Prázdný text úsek maže** (pravidlo modelu z fáze 11) a `.srt` o něm
//     přestane vědět.
//  D) **Zvýraznění na ose** ukazuje rozsah vybraného úseku, a když je zdroj
//     na ose dvakrát, ukazuje ho dvakrát.
//
//  ⚠️ Přepis se v kontrole NESPOUŠTÍ. WhisperKit by stahoval 1,5 GB a jel
//  minuty; testovat jde všechno ostatní se SYNTETICKÝM přepisem, a to je
//  právě ta část, kterou modul 11 přidal. Skutečný přepis hlídá
//  `--transcribe-check`.
//

import AppKit
import Foundation
import TimelineModel

extension AppModel {

    func verifyTranscriptUI() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        // Osa: TÝŽ zdroj dvakrát na A1 (v nule a v 600. snímku) se třemi úseky
        // přepisu. Dvakrát schválně — přepis patří assetu, takže se každá
        // změna musí projevit na obou.
        guard let source = timeline.project.assets
            .first(where: { $0.hasAudio && !$0.isStill }) else {
            print("❌ žádný asset se zvukem"); return
        }
        var project = Project.empty()
        project.addAsset(source)
        guard let a1 = project.timeline.tracks.first(where: { $0.kind == .audio })?.id else {
            print("❌ projekt nemá zvukovou stopu"); return
        }
        do {
            for start in [Frames(0), Frames(600)] {
                var clip = try project.makeClip(assetID: source.id, at: start)
                clip.duration = Frames(300)
                try project.insert(clip, onTrack: a1)
            }
            try project.setTranscript(assetID: source.id, segments: [
                TranscriptSegment(start: SourceTime(seconds: 1), end: SourceTime(seconds: 3),
                                  text: "ANO CHCI a slibuji"),
                TranscriptSegment(start: SourceTime(seconds: 4), end: SourceTime(seconds: 6),
                                  text: "před tímto shromážděním"),
                TranscriptSegment(start: SourceTime(seconds: 7), end: SourceTime(seconds: 9),
                                  text: "artefakt přepisu"),
            ])
        } catch {
            print("❌ stavba osy selhala: \(error)"); return
        }
        timeline.project = project
        timeline.undo = UndoStack()
        railSection = .speech

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while timelinePane?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let pane = timelinePane, let window = pane.window else {
            print("❌ osa se nedostala do okna"); return
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        print("=== A) oprava textu → náhled i .srt, jeden undo krok ===")
        let cuesBefore = timeline.project.subtitleCues()
        print("   titulků na ose: \(cuesBefore.count) (dva klipy × tři úseky)")
        check(cuesBefore.count == 6, "úseky se promítly na OBA klipy zdroje")

        setSpeechText(assetID: source.id, segmentIndex: 0, text: "ANO, CHCI")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let afterEdit = timeline.project.subtitleCues()
        let edited = afterEdit.filter { $0.text == "ANO, CHCI" }
        print("   po opravě: \(edited.count) titulků s novým textem")
        check(edited.count == 2, "nový text je na obou klipech ze zdroje")
        let srt = SRT.serialize(cues: afterEdit,
                                frameRate: timeline.project.timeline.frameRate)
        check(srt.contains("ANO, CHCI"), "`.srt` nese nový text")
        check(!srt.contains("ANO CHCI a slibuji"), "a starý už v něm není")

        timeline.undoStep()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let afterUndo = timeline.project.subtitleCues().filter { $0.text == "ANO CHCI a slibuji" }
        print("   po ⌘Z: \(afterUndo.count) titulků s původním textem")
        check(afterUndo.count == 2, "JEDEN undo krok vrátil oba")
        setSpeechText(assetID: source.id, segmentIndex: 0, text: "ANO, CHCI")
        try? await Task.sleep(nanoseconds: 200_000_000)

        print("")
        print("=== B) rozdělit v kurzoru ===")
        let before = timeline.project.asset(source.id)?.transcript?[1]
        let originalSpan = (before?.end.seconds ?? 0) - (before?.start.seconds ?? 0)
        // Kurzor za slovem „před" (5 znaků z 24).
        splitSpeechSegment(assetID: source.id, segmentIndex: 1, atCharacter: 5)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let segments = timeline.project.asset(source.id)?.transcript else {
            print("❌ přepis zmizel"); return
        }
        print("   úseků po rozdělení: \(segments.count) (bylo 3)")
        check(segments.count == 4, "z jednoho úseku jsou dva")
        if segments.count >= 3 {
            let first = segments[1], second = segments[2]
            print(String(format: "   „%@\" %.2f–%.2f s · „%@\" %.2f–%.2f s",
                         first.text, first.start.seconds, first.end.seconds,
                         second.text, second.start.seconds, second.end.seconds))
            check(first.text == "před" && second.text == "tímto shromážděním",
                  "text se rozdělil v kurzoru")
            check(abs(first.end.seconds - second.start.seconds) < 0.0001,
                  "časy na sebe navazují bez děr")
            let newSpan = second.end.seconds - first.start.seconds
            check(abs(newSpan - originalSpan) < 0.0001,
                  String(format: "součet délek se rovná původní (%.2f s)", originalSpan))
            check(first.end.seconds > first.start.seconds
                  && second.end.seconds > second.start.seconds,
                  "ani jedna půlka nemá nulovou délku")
        }
        timeline.undoStep()
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(timeline.project.asset(source.id)?.transcript?.count == 3,
              "⌘Z vrátil rozdělení jedním krokem")

        print("")
        print("=== C) prázdný text úsek maže ===")
        let countBefore = timeline.project.asset(source.id)?.transcript?.count ?? 0
        timeline.selectedSpeech = TimelineController.SpeechSelection(assetID: source.id,
                                                                    segmentIndex: 2)
        setSpeechText(assetID: source.id, segmentIndex: 2, text: "")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let countAfter = timeline.project.asset(source.id)?.transcript?.count ?? 0
        print("   úseků: \(countBefore) → \(countAfter)")
        check(countAfter == countBefore - 1, "prázdný text úsek smazal")
        check(timeline.selectedSpeech == nil, "a výběr zanikl s ním")
        let srtAfter = SRT.serialize(cues: timeline.project.subtitleCues(),
                                     frameRate: timeline.project.timeline.frameRate)
        check(!srtAfter.contains("artefakt přepisu"), "`.srt` o smazaném úseku neví")

        print("")
        print("=== D) zvýraznění rozsahu na ose ===")
        let ranges = timeline.project.speechCueRanges(assetID: source.id, segmentIndex: 0)
        print("   rozsahů úseku 0: \(ranges.count) "
              + ranges.map { "\($0.lowerBound.count)–\($0.upperBound.count)" }.joined(separator: ", "))
        check(ranges.count == 2, "úsek je vidět na OBOU klipech zdroje")
        // Zdroj začíná v 1 s = 30. snímek; druhý klip je posunutý o 600.
        check(ranges.first?.lowerBound.count == 30,
              "první rozsah začíná na 30. snímku (1 s zdroje)")
        check(ranges.last?.lowerBound.count == 630,
              "druhý o 600 snímků dál (posun klipu)")

        timeline.selectedSpeech = TimelineController.SpeechSelection(assetID: source.id,
                                                                    segmentIndex: 0)
        try? await Task.sleep(nanoseconds: 600_000_000)
        let drawn = pane.documentView.speechRangeCount
        print("   nakreslených zvýraznění: \(drawn)")
        check(drawn == 2, "osa kreslí obě zvýraznění")
        timeline.selectedSpeech = nil
        try? await Task.sleep(nanoseconds: 400_000_000)
        check(pane.documentView.speechRangeCount == 0,
              "po zrušení výběru zvýraznění zmizí")

        // Snímek panelu pro oko (vzorec z modulu 10).
        timeline.selectedSpeech = TimelineController.SpeechSelection(assetID: source.id,
                                                                    segmentIndex: 0)
        try? await Task.sleep(nanoseconds: 800_000_000)
        if let shot = Self.writeWindowSnapshot(of: hostView?.window, name: "prepis-editace") {
            print("   snímek: \(shot.path)")
        }

        print("")
        print(failures == 0 ? "✅ PANEL PŘEPISU SEDÍ" : "❌ neshod: \(failures)")
    }
}
