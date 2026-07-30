//
//  TranscriptTests.swift
//  Projekt AIditor — TimelineModel
//
//  Fáze 8, modul 1: přepis kotvený ve zdroji, promítnutí na osu, SRT.
//

import XCTest
@testable import TimelineModel

private func segment(_ from: Double, _ to: Double, _ text: String) -> TranscriptSegment {
    TranscriptSegment(start: SourceTime(seconds: from),
                      end: SourceTime(seconds: to),
                      text: text)
}

final class TranscriptModelTests: XCTestCase {

    func testUlozeniSeradiASmazeprazdne() throws {
        var fixture = Fixture()
        try fixture.project.setTranscript(assetID: fixture.assetID, segments: [
            segment(5, 6, "druhý"),
            segment(1, 2, "první"),
            segment(3, 4, "   \n  "),   // artefakt — zahodit
        ])
        let stored = fixture.project.asset(fixture.assetID)?.transcript
        XCTAssertEqual(stored?.map(\.text), ["první", "druhý"])
        XCTAssertValid(fixture.project)
    }

    func testKonecPredZacatkemOdmitne() {
        var fixture = Fixture()
        let assetID = fixture.assetID
        XCTAssertThrowsUnchanged(&fixture.project, .invalidTranscriptSegment) {
            try $0.setTranscript(assetID: assetID, segments: [segment(2, 2, "nula")])
        }
    }

    func testNeznamyAssetOdmitne() {
        var fixture = Fixture()
        let ghost = AssetID()
        XCTAssertThrowsUnchanged(&fixture.project, .assetNotFound(ghost)) {
            try $0.setTranscript(assetID: ghost, segments: [segment(0, 1, "x")])
        }
    }

    /// Přepis se veze v projektovém souboru a starý soubor bez něj se
    /// pořád načte (pole je volitelné, verze formátu se nezvedá).
    func testPrepisPrezijeProjektovySoubor() throws {
        var fixture = Fixture()
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(1, 2.5, "ano")])
        let file = ProjectFile(project: fixture.project, name: "t",
                               createdAt: Date(), modifiedAt: Date())
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project.asset(fixture.assetID)?.transcript?.first?.text, "ano")
    }
}

final class SubtitleCueTests: XCTestCase {

    /// Klip 1×: titulek 2–4 s zdroje, klip od zdroje 1 s na snímku 100.
    /// 2 s zdroje = 1 s do klipu = snímek 130; 4 s = snímek 190.
    func testPromitnutiPrestrih() throws {
        var fixture = Fixture(seconds: 10)
        _ = try fixture.addClip(start: 100, duration: 200, sourceStartFrames: 30,
                                on: fixture.a1)
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(2, 4, "ahoj")])
        let cues = fixture.project.subtitleCues()
        XCTAssertEqual(cues, [SubtitleCue(start: Frames(130), end: Frames(190),
                                          text: "ahoj")])
    }

    /// Úsek přesahující okno klipu se zařízne na hranice klipu.
    func testZaperezaniNaOknoKlipu() throws {
        var fixture = Fixture(seconds: 10)
        _ = try fixture.addClip(start: 0, duration: 60, sourceStartFrames: 30,
                                on: fixture.a1)   // zdroj 1–3 s
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(0, 10, "celou dobu")])
        let cues = fixture.project.subtitleCues()
        XCTAssertEqual(cues, [SubtitleCue(start: .zero, end: Frames(60),
                                          text: "celou dobu")])
    }

    func testUsekMimoKlipSeVynecha() throws {
        var fixture = Fixture(seconds: 10)
        _ = try fixture.addClip(start: 0, duration: 60, sourceStartFrames: 0,
                                on: fixture.a1)   // zdroj 0–2 s
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(5, 6, "pozdě")])
        XCTAssertTrue(fixture.project.subtitleCues().isEmpty)
    }

    /// Svázaný pár obraz+zvuk sdílí asset — titulek smí vzniknout JEDNOU
    /// (ze zvukové stopy), ne dvakrát.
    func testSvazanyParDaJedenTitulek() throws {
        var fixture = Fixture(seconds: 10)
        _ = try fixture.addClip(start: 0, duration: 120, on: fixture.v1)
        _ = try fixture.addClip(start: 0, duration: 120, on: fixture.a1)
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(1, 2, "jednou")])
        XCTAssertEqual(fixture.project.subtitleCues().count, 1)
    }

    /// Střih klipu titulky nerozbije: po splitu pokrývají obě poloviny
    /// dohromady totéž, co celek — kotvení ve zdroji, ne na ose.
    func testSplitTitulekZachova() throws {
        var fixture = Fixture(seconds: 10)
        let clipID = try fixture.addClip(start: 0, duration: 120, on: fixture.a1)
        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(1, 3, "přes střih")])
        let before = fixture.project.subtitleCues()
        _ = try fixture.project.split(clipID: clipID, at: Frames(60))   // uvnitř titulku
        let after = fixture.project.subtitleCues()
        XCTAssertEqual(before, [SubtitleCue(start: Frames(30), end: Frames(90),
                                            text: "přes střih")])
        // Po řezu dva titulky navazující beze spáry, se stejným textem.
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[0].start, Frames(30))
        XCTAssertEqual(after[0].end, after[1].start)
        XCTAssertEqual(after[1].end, Frames(90))
    }

    /// Pod rychlostní křivkou se titulek natahuje s řečí. Hranice musí
    /// sedět s inverzí `sourceOffset` — mapování jde přes tutéž funkci,
    /// kterou používá střih.
    func testRampaNatahneTitulek() throws {
        var fixture = Fixture(seconds: 10)
        let clipID = try fixture.addClip(start: 0, duration: 240, on: fixture.a1)
        let clipBefore = try XCTUnwrap(fixture.clip(clipID))
        let consumption = fixture.project.sourceConsumption(of: clipBefore)
        let ramp = SpeedRamp.classicSlowMotion(
            from: clipBefore.sourceStart,
            spanning: SourceTime(seconds: consumption.seconds * 0.625),
            slowSpeed: 0.25)
        try fixture.project.setSpeedRamp(clipID: clipID, ramp: ramp)

        try fixture.project.setTranscript(assetID: fixture.assetID,
                                          segments: [segment(2, 3, "zpomaleně")])
        let cues = fixture.project.subtitleCues()
        XCTAssertEqual(cues.count, 1)
        let cue = try XCTUnwrap(cues.first)
        let clip = try XCTUnwrap(fixture.clip(clipID))

        // Uprostřed rampy jede zdroj 0,25× — sekunda řeči zabere na ose
        // ~4 s. Přesné hranice: inverze sourceOffset, tedy konzistence
        // s vlastním mapováním, a délka výrazně přes normální 30 snímků.
        XCTAssertGreaterThan(cue.end - cue.start, Frames(90))
        let mappedStart = fixture.project.sourceOffset(in: clip, atFrame: cue.start)
        XCTAssertGreaterThanOrEqual(mappedStart, SourceTime(seconds: 2))
        let beforeStart = fixture.project.sourceOffset(
            in: clip, atFrame: cue.start - Frames(1))
        XCTAssertLessThan(beforeStart, SourceTime(seconds: 2))
    }
}

final class SRTTests: XCTestCase {

    func testFormatCasu() {
        XCTAssertEqual(SRT.timestamp(frame: .zero, frameRate: 30), "00:00:00,000")
        XCTAssertEqual(SRT.timestamp(frame: Frames(45), frameRate: 30), "00:00:01,500")
        // 1 hodina, 2 minuty, 3,4 s = 3723,4 s = 111702 snímků
        XCTAssertEqual(SRT.timestamp(frame: Frames(111_702), frameRate: 30),
                       "01:02:03,400")
    }

    func testCelySoubor() {
        let cues = [
            SubtitleCue(start: Frames(30), end: Frames(75), text: "Ahoj."),
            SubtitleCue(start: Frames(90), end: Frames(150), text: "Jak se máš?"),
        ]
        XCTAssertEqual(SRT.serialize(cues: cues, frameRate: 30), """
            1
            00:00:01,000 --> 00:00:02,500
            Ahoj.

            2
            00:00:03,000 --> 00:00:05,000
            Jak se máš?

            """)
    }

    func testPrazdneTitulkySePreskoci() {
        let cues = [
            SubtitleCue(start: Frames(0), end: Frames(30), text: "  "),
            SubtitleCue(start: Frames(30), end: Frames(60), text: "text"),
        ]
        let srt = SRT.serialize(cues: cues, frameRate: 30)
        XCTAssertTrue(srt.hasPrefix("1\n"))
        XCTAssertFalse(srt.contains("2\n"))
    }

    func testPrazdnySeznamDaPrazdnyRetezec() {
        XCTAssertEqual(SRT.serialize(cues: [], frameRate: 30), "")
    }
}

// MARK: - Rozdělení úseku a rozsah na ose (fáze 18, modul 11)

final class TranscriptSplitTests: XCTestCase {

    /// Osa: jeden zvukový klip celého assetu s jedním úsekem přepisu.
    private func projectWithSpeech() throws -> (Project, AssetID) {
        var project = Project.empty()
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/rec.wav"),
                          duration: SourceTime(seconds: 20),
                          measuredFrameRate: 30,
                          hasVideo: false, hasAudio: true)
        project.addAsset(asset)
        let audioTrack = try XCTUnwrap(project.timeline.tracks.first { $0.kind == .audio })
        let clip = try project.makeClip(assetID: asset.id)
        try project.insert(clip, onTrack: audioTrack.id)
        try project.setTranscript(assetID: asset.id, segments: [
            TranscriptSegment(start: SourceTime(seconds: 2), end: SourceTime(seconds: 6),
                              text: "ANO CHCI a slibuji"),
        ])
        return (project, asset.id)
    }

    func testSplitAtCursorGivesTwoSegmentsWithProportionalTimes() throws {
        var (project, assetID) = try projectWithSpeech()
        // Kurzor za „ANO CHCI" (8 znaků z 18) → řez v 44,4 % délky úseku.
        XCTAssertTrue(try project.splitTranscriptSegment(assetID: assetID, segmentIndex: 0,
                                                         atCharacter: 8))
        let segments = try XCTUnwrap(project.asset(assetID)?.transcript)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "ANO CHCI")
        XCTAssertEqual(segments[1].text, "a slibuji")
        // Časy: první končí tam, kde druhý začíná, a řez je uvnitř.
        XCTAssertEqual(segments[0].end.seconds, segments[1].start.seconds, accuracy: 0.0001)
        XCTAssertEqual(segments[0].start.seconds, 2, accuracy: 0.0001)
        XCTAssertEqual(segments[1].end.seconds, 6, accuracy: 0.0001)
        XCTAssertEqual(segments[0].end.seconds, 2 + 4 * (8.0 / 18.0), accuracy: 0.01)
    }

    /// Kurzor na kraji nedělá nic — prázdná půlka není úsek.
    func testSplitAtEdgesDoesNothing() throws {
        var (project, assetID) = try projectWithSpeech()
        XCTAssertFalse(try project.splitTranscriptSegment(assetID: assetID, segmentIndex: 0,
                                                          atCharacter: 0))
        XCTAssertFalse(try project.splitTranscriptSegment(assetID: assetID, segmentIndex: 0,
                                                          atCharacter: 18))
        XCTAssertEqual(project.asset(assetID)?.transcript?.count, 1)
    }

    /// Rozsah úseku na ose: klip začíná v nule, takže 2–6 s zdroje je
    /// 60–180 snímků osy.
    func testSpeechCueRangeMapsToTimeline() throws {
        let (project, assetID) = try projectWithSpeech()
        let ranges = project.speechCueRanges(assetID: assetID, segmentIndex: 0)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowerBound.count, 60)
        XCTAssertEqual(ranges.first?.upperBound.count, 180)
    }

    /// Týž zdroj položený dvakrát → úsek je vidět na obou klipech.
    func testSpeechCueRangeOnTwoClips() throws {
        var (project, assetID) = try projectWithSpeech()
        let audioTrack = try XCTUnwrap(project.timeline.tracks.first { $0.kind == .audio })
        let second = try project.makeClip(assetID: assetID, at: Frames(900))
        try project.insert(second, onTrack: audioTrack.id)
        XCTAssertEqual(project.speechCueRanges(assetID: assetID, segmentIndex: 0).count, 2)
    }
}
