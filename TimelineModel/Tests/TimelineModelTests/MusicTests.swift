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
