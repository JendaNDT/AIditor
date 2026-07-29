//
//  MusicTests.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 14, modul 2: mřížka dob na assetu, promítnutí na osu, magnet.
//

import XCTest
import AudioEngine
@testable import TimelineModel

final class MusicTests: XCTestCase {

    /// Fixture s hudebním assetem (jen zvuk, 20 s) na A2.
    /// Mřížka 120 BPM od 0,5 s → doba každých 15 snímků osy.
    private func makeFixture() throws -> (f: Fixture, musicID: AssetID, clipID: ClipID) {
        var f = Fixture()
        let music = Asset(originalURL: URL(fileURLWithPath: "/tmp/hudba.m4a"),
                          duration: SourceTime(seconds: 20),
                          measuredFrameRate: 30,
                          hasVideo: false, hasAudio: true)
        f.project.addAsset(music)
        try f.project.setBeatGrid(assetID: music.id,
                                  BeatGrid(bpm: 120, firstBeatTime: 0.5))
        let clip = try f.project.makeClip(assetID: music.id)
        try f.project.insert(clip, onTrack: f.a2)
        return (f, music.id, clip.id)
    }

    // MARK: - Nastavení mřížky

    func testSetAndClearBeatGrid() throws {
        var (f, musicID, _) = try makeFixture()
        XCTAssertEqual(f.project.asset(musicID)?.beatGrid?.bpm, 120)
        XCTAssertValid(f.project)

        try f.project.setBeatGrid(assetID: musicID, nil)
        XCTAssertNil(f.project.asset(musicID)?.beatGrid)
    }

    func testBeatGridOnVideoOnlyAssetRejected() throws {
        var f = Fixture(hasAudio: false)
        XCTAssertThrowsUnchanged(&f.project, .beatGridNeedsAudio) {
            try $0.setBeatGrid(assetID: f.assetID, BeatGrid(bpm: 120, firstBeatTime: 0))
        }
    }

    func testInvalidBeatGridRejected() throws {
        var (f, musicID, _) = try makeFixture()
        for bad in [BeatGrid(bpm: 0, firstBeatTime: 0),
                    BeatGrid(bpm: .nan, firstBeatTime: 0),
                    BeatGrid(bpm: 120, firstBeatTime: .infinity)] {
            XCTAssertThrowsUnchanged(&f.project, .invalidBeatGrid) {
                try $0.setBeatGrid(assetID: musicID, bad)
            }
        }
    }

    // MARK: - Promítnutí na osu

    func testBeatMarksProjection() throws {
        let (f, _, _) = try makeFixture()
        // Klip celé skladby od nuly: doby 0,5 + k·0,5 s → snímky 15 + k·15.
        let marks = f.project.beatMarks()
        XCTAssertEqual(marks.first?.frame, Frames(15))
        XCTAssertEqual(marks[1].frame, Frames(30))
        // 20 s hudby: poslední doba 19,5 s < 20 s → 39 dob.
        XCTAssertEqual(marks.count, 39)
        // Výchozí takt od první doby: „raz" každé 4 doby.
        XCTAssertEqual(marks[0].isDownbeat, true)
        XCTAssertEqual(marks[1].isDownbeat, false)
        XCTAssertEqual(marks[4].isDownbeat, true)
    }

    func testBeatMarksFollowClipPlacementAndTrim() throws {
        var (f, _, clipID) = try makeFixture()
        // Přesun klipu na snímek 60: doby se posunou s ním.
        try f.project.move(clipID: clipID, toTrack: f.a2, start: Frames(60))
        XCTAssertEqual(f.project.beatMarks().first?.frame, Frames(75))

        // Trim začátku o 2 s (60 snímků): mřížka drží na HUDBĚ — okno
        // zdroje teď začíná na 2,0 s a to JE doba (0,5 + 3·0,5), takže
        // první značka padne přesně na nový začátek klipu.
        try f.project.trimStart(clipID: clipID, to: Frames(120))
        let marks = f.project.beatMarks()
        XCTAssertEqual(marks.first?.frame, Frames(120),
                       "doba 2,0 s zdroje leží na začátku klipu")
        XCTAssertEqual(marks[1].frame, Frames(135),
                       "další doba 2,5 s = 0,5 s za začátkem klipu")
    }

    func testBeatMarksEmptyWithoutGrid() throws {
        var (f, musicID, _) = try makeFixture()
        try f.project.setBeatGrid(assetID: musicID, nil)
        XCTAssertTrue(f.project.beatMarks().isEmpty)
    }

    // MARK: - Magnet

    func testSnapToBeat() throws {
        let (f, _, _) = try makeFixture()
        let geometry = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 10)
        let candidates = geometry.snapCandidates(
            in: f.project.timeline,
            beats: f.project.beatMarks().map(\.frame))
        // Snímek 14 je 4 body od doby 15 (zoom 4 b/snímek) → přitáhne se.
        let snapped = geometry.snap(Frames(14), to: candidates)
        XCTAssertEqual(snapped.frame, Frames(15))
        XCTAssertEqual(snapped.candidate?.kind, .beat)
    }

    func testClipEdgeBeatsBeatOnTie() throws {
        // Hrana klipu a doba na TÉMŽE snímku: vyhrává hrana (silnější druh).
        let (f, _, _) = try makeFixture()
        let geometry = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 10)
        var candidates = geometry.snapCandidates(
            in: f.project.timeline,
            beats: f.project.beatMarks().map(\.frame))
        candidates.append(SnapCandidate(frame: Frames(15), kind: .clipEdge))
        let snapped = geometry.snap(Frames(14), to: candidates)
        XCTAssertEqual(snapped.frame, Frames(15))
        XCTAssertEqual(snapped.candidate?.kind, .clipEdge)
    }

    // MARK: - Dopasování: zarovnat konec na dobu (modul 3)

    func testFitClipEndToBeat() throws {
        var (f, _, _) = try makeFixture()
        // Video klip [0, 100): doby po 15 → kandidáti 90 (f 1,111) a 105
        // (f 0,952; podlaha 60fps zdroje je 0,5). Bližší ke konci je 105.
        let video = try f.addClip(start: 0, duration: 100)
        let before = f.project.sourceConsumption(of: f.clip(video)!)

        let result = try f.project.fitClipEndToBeat(clipID: video)
        XCTAssertEqual(result.beat, Frames(105))
        XCTAssertEqual(result.newDuration, Frames(105))
        XCTAssertEqual(result.speedFactor, 100.0 / 105.0, accuracy: 1e-12)

        let fitted = try XCTUnwrap(f.clip(video))
        XCTAssertEqual(fitted.duration, Frames(105))
        XCTAssertEqual(fitted.speedRamp?.nodes.count, 1)
        XCTAssertEqual(try XCTUnwrap(fitted.speedRamp?.nodes.first?.speed),
                       100.0 / 105.0, accuracy: 1e-12)
        // Obsah se nemění: spotřeba zdroje zůstává (až na tick zaokrouhlení).
        let after = f.project.sourceConsumption(of: fitted)
        XCTAssertEqual(after.seconds, before.seconds, accuracy: 0.001)
        XCTAssertValid(f.project)
    }

    func testFitRespectsCleanSlowdownLimit() throws {
        var (f, _, _) = try makeFixture()
        // Zdroj 30 fps na 30fps ose: podlaha 1,0 — zpomalení na dobu 105
        // je zakázané, i když je blíž; vyhrát musí zrychlení na 90.
        let slowSource = Asset(originalURL: URL(fileURLWithPath: "/tmp/pomale.mov"),
                               duration: SourceTime(seconds: 10),
                               measuredFrameRate: 30,
                               hasVideo: true, hasAudio: false)
        f.project.addAsset(slowSource)
        let clip = Clip(assetID: slowSource.id, timelineStart: .zero,
                        duration: Frames(100),
                        sourceStart: .zero)
        try f.project.insert(clip, onTrack: f.v1)

        let result = try f.project.fitClipEndToBeat(clipID: clip.id)
        XCTAssertEqual(result.beat, Frames(90), "zpomalení pod podlahu se přeskočí")
        XCTAssertValid(f.project)
    }

    func testFitNoBeatInReachOffersNearest() throws {
        var (f, _, _) = try makeFixture()
        // Klip [0, 10): dosah 90–115 % je [8,7; 11,1] — žádná doba (první
        // je 15). Chyba nese nejbližší dobu jako radu pro UI.
        let video = try f.addClip(start: 0, duration: 10)
        XCTAssertThrowsUnchanged(&f.project, .noBeatInReach(nearest: Frames(15))) {
            try $0.fitClipEndToBeat(clipID: video)
        }
    }

    func testFitSkipsOccupiedBeat() throws {
        var (f, _, _) = try makeFixture()
        let video = try f.addClip(start: 0, duration: 100)
        // Soused od snímku 100: doba 105 je za ním → vyhrává 90.
        try f.addClip(start: 100, duration: 50)
        let result = try f.project.fitClipEndToBeat(clipID: video)
        XCTAssertEqual(result.beat, Frames(90))
        XCTAssertValid(f.project)
    }

    func testFitAdjustsLinkedTwin() throws {
        var (f, _, _) = try makeFixture()
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        var v = video; v.duration = Frames(100)
        var a = audio; a.duration = Frames(100)
        try f.project.insert(v, onTrack: f.v1)
        try f.project.insert(a, onTrack: f.a1)

        try f.project.fitClipEndToBeat(clipID: v.id)
        XCTAssertEqual(f.clip(v.id)?.duration, Frames(105))
        XCTAssertEqual(f.clip(a.id)?.duration, Frames(105), "souosé dvojče jde s klipem")
        XCTAssertEqual(f.clip(a.id)?.speedRamp, f.clip(v.id)?.speedRamp)
        XCTAssertValid(f.project)
    }

    func testFitOnMusicClipRejected() throws {
        var (f, _, musicClip) = try makeFixture()
        XCTAssertThrowsUnchanged(&f.project, .beatFitOnMusicClip) {
            try $0.fitClipEndToBeat(clipID: musicClip)
        }
    }

    // MARK: - Dopasování: rampa na úder (modul 3)

    func testRampToBeat() throws {
        var (f, _, _) = try makeFixture()
        let video = try f.addClip(start: 0, duration: 150)

        // Hlava u snímku 88 → nejbližší doba 90. Zdroj 60 fps → podlaha
        // 0,5, výchozí slow = max(0,25; 0,5) = 0,5. Nájezd 15 snímků končí
        // PŘESNĚ na době: kotvy 1× do 75/30 = 2,5 s, ease spotřebuje
        // 0,5 s × (1+0,5)/2 = 0,375 s → slow od 2,875 s.
        let beat = try f.project.rampClipToBeat(clipID: video, near: Frames(88))
        XCTAssertEqual(beat, Frames(90))

        let clip = try XCTUnwrap(f.clip(video))
        let ramp = try XCTUnwrap(clip.speedRamp)
        XCTAssertEqual(ramp.nodes.count, 2)
        XCTAssertEqual(ramp.nodes[0].sourceTime.seconds, 2.5, accuracy: 1e-9)
        XCTAssertEqual(ramp.nodes[0].speed, 1.0)
        XCTAssertEqual(ramp.nodes[1].sourceTime.seconds, 2.875, accuracy: 1e-9)
        XCTAssertEqual(ramp.nodes[1].speed, 0.5)
        // Klíčová záruka: zpomalení DOSEDNE na dobu — zdrojová kotva konce
        // rampy leží na ose přesně na snímku 90.
        XCTAssertEqual(f.project.frameOffset(forSource: SourceTime(seconds: 2.875),
                                             in: clip),
                       Frames(90))
        // Délka se rampou nemění (vlastnost křivek od fáze 3).
        XCTAssertEqual(clip.duration, Frames(150))
        XCTAssertValid(f.project)
    }

    func testRampToBeatNoCleanSlowdown() throws {
        var (f, _, _) = try makeFixture()
        let slowSource = Asset(originalURL: URL(fileURLWithPath: "/tmp/pomale.mov"),
                               duration: SourceTime(seconds: 10),
                               measuredFrameRate: 30,
                               hasVideo: true, hasAudio: false)
        f.project.addAsset(slowSource)
        let clip = Clip(assetID: slowSource.id, timelineStart: .zero,
                        duration: Frames(100), sourceStart: .zero)
        try f.project.insert(clip, onTrack: f.v1)

        XCTAssertThrowsUnchanged(&f.project, .noCleanSlowdown) {
            try $0.rampClipToBeat(clipID: clip.id, near: Frames(45))
        }
    }

    func testRampToBeatNeedsBeatInsideClip() throws {
        var (f, _, _) = try makeFixture()
        // Klip [0, 12): první doba 15 je za koncem → není kam dosednout.
        let video = try f.addClip(start: 0, duration: 12)
        XCTAssertThrowsUnchanged(&f.project, .noBeatInReach(nearest: Frames(15))) {
            try $0.rampClipToBeat(clipID: video, near: Frames(10))
        }
    }

    // MARK: - Formát souboru

    func testProjectFileRoundtripWithBeatGrid() throws {
        var (f, musicID, _) = try makeFixture()
        var grid = try XCTUnwrap(f.project.asset(musicID)?.beatGrid)
        grid.markDownbeat(at: 1.0)
        try f.project.setBeatGrid(assetID: musicID, grid)

        let file = ProjectFile(project: f.project, name: "S hudbou")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, f.project)
    }

    func testAssetWithoutBeatGridFieldDecodes() throws {
        // Asset zapsaný před fází 14 — pole `beatGrid` neexistuje.
        let json = """
        {"id": "A-1", "originalURL": "file:///tmp/a.m4a",
         "duration": {"value": 900000, "timescale": 90000},
         "measuredFrameRate": 30, "hasVideo": false, "hasAudio": true,
         "isOffline": false}
        """.data(using: .utf8)!
        let asset = try JSONDecoder().decode(Asset.self, from: json)
        XCTAssertNil(asset.beatGrid)
    }
}
