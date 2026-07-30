//
//  ColorGradeTests.swift
//  TimelineModel — Projekt AIditor
//
//  Fáze 13, modul 1: barevné presety na klipu.
//

import XCTest
@testable import TimelineModel

final class ColorGradeTests: XCTestCase {

    // MARK: - Nastavení a mazání

    func testSetColorGradeOnVideoClip() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)

        let grade = ColorGrade(preset: .warmFilm, intensity: 0.6)
        try f.project.setColorGrade(clipID: clip, grade)
        XCTAssertEqual(f.project.timeline.clip(clip)?.colorGrade, grade)
        XCTAssertValid(f.project)

        // `nil` maže.
        try f.project.setColorGrade(clipID: clip, nil)
        XCTAssertNil(f.project.timeline.clip(clip)?.colorGrade)
        XCTAssertValid(f.project)
    }

    func testSetColorGradeOnStillClip() throws {
        // Fotka je obrazový klip — preset dostat smí.
        var f = Fixture()
        let photo = Asset.still(url: URL(fileURLWithPath: "/tmp/fotka.heic"))
        f.project.addAsset(photo)
        let clip = try f.project.makeClip(assetID: photo.id)
        try f.project.insert(clip, onTrack: f.v1)

        try f.project.setColorGrade(clipID: clip.id,
                                    ColorGrade(preset: .blackAndWhite))
        XCTAssertEqual(f.project.timeline.clip(clip.id)?.colorGrade?.preset,
                       .blackAndWhite)
        XCTAssertValid(f.project)
    }

    func testZeroIntensityIsLegal() throws {
        // Nula = obraz beze změny, ale volba presetu zůstává.
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        try f.project.setColorGrade(clipID: clip,
                                    ColorGrade(preset: .softWedding, intensity: 0))
        XCTAssertValid(f.project)
    }

    // MARK: - Odmítnuté stavy

    func testColorGradeOnAudioClipRejected() throws {
        var f = Fixture()
        let audioClip = try f.addClip(start: 0, duration: 100, on: f.a1)
        XCTAssertThrowsUnchanged(&f.project, .colorGradeNeedsVideoTrack) {
            try $0.setColorGrade(clipID: audioClip,
                                 ColorGrade(preset: .warmFilm))
        }
    }

    func testInvalidIntensityRejected() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        for bad in [1.5, -0.1, Double.nan, .infinity] {
            XCTAssertThrowsUnchanged(&f.project, .invalidColorGrade) {
                try $0.setColorGrade(clipID: clip,
                                     ColorGrade(preset: .cleanSkin, intensity: bad))
            }
        }
    }

    func testUnknownClipRejected() {
        var f = Fixture()
        let ghost = ClipID()
        XCTAssertThrowsUnchanged(&f.project, .clipNotFound(ghost)) {
            try $0.setColorGrade(clipID: ghost, ColorGrade(preset: .warmFilm))
        }
    }

    // MARK: - Validace natvrdo rozbitých stavů

    func testColorGradeOnWrongTrackValidated() throws {
        var f = Fixture()
        let audioClip = try f.addClip(start: 0, duration: 100, on: f.a1)
        var tracks = f.project.timeline.tracks
        tracks[1].clips[0].colorGrade = ColorGrade(preset: .warmFilm)
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.colorGradeOnWrongTrack(audioClip)))
    }

    func testInvalidIntensityValidated() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].colorGrade = ColorGrade(preset: .warmFilm, intensity: 7)
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.invalidColorGrade(clip)))
    }

    // MARK: - Dědění operacemi

    func testSplitKeepsColorGradeOnBothHalves() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        let grade = ColorGrade(preset: .softWedding, intensity: 0.8)
        try f.project.setColorGrade(clipID: clip, grade)

        let (left, right) = try f.project.split(clipID: clip, at: Frames(40))
        XCTAssertEqual(f.project.timeline.clip(left)?.colorGrade, grade)
        XCTAssertEqual(f.project.timeline.clip(right)?.colorGrade, grade)
        XCTAssertValid(f.project)
    }

    func testDuplicateKeepsColorGrade() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        let grade = ColorGrade(preset: .blackAndWhite, intensity: 1)
        try f.project.setColorGrade(clipID: clip, grade)

        let copy = try f.project.duplicate(clipID: clip, onto: f.v1, at: Frames(200))
        XCTAssertEqual(f.project.timeline.clip(copy)?.colorGrade, grade)
        XCTAssertValid(f.project)
    }

    func testOverwriteTailKeepsColorGrade() throws {
        var f = Fixture()
        let long = try f.addClip(start: 0, duration: 300)
        let grade = ColorGrade(preset: .warmFilm, intensity: 0.5)
        try f.project.setColorGrade(clipID: long, grade)

        // Přepis prostředka: hlava je kopie (preset drží sama), ocásek je
        // NOVÝ klip — preset musí dostat výslovně.
        let insert = try f.project.makeClip(assetID: f.assetID, at: Frames(100))
        var short = insert
        short.duration = Frames(50)
        try f.project.overwrite(short, onTrack: f.v1)

        let clips = f.clips(on: f.v1)
        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips[0].colorGrade, grade, "hlava drží preset")
        XCTAssertEqual(clips[2].colorGrade, grade, "ocásek drží preset")
        XCTAssertNil(clips[1].colorGrade, "vložený klip preset nedědí")
        XCTAssertValid(f.project)
    }

    // MARK: - Formát souboru

    func testClipWithoutColorGradeFieldDecodes() throws {
        // Klip zapsaný před fází 13 — pole `colorGrade` neexistuje.
        let json = """
        {"id": "C-1", "assetID": "A-1",
         "timelineStart": 0, "duration": 100,
         "sourceStart": {"value": 0, "timescale": 90000}}
        """.data(using: .utf8)!
        let clip = try JSONDecoder().decode(Clip.self, from: json)
        XCTAssertNil(clip.colorGrade)
    }

    func testPresetRawValuesAreStable() {
        // Syrové hodnoty jsou smlouva formátu souboru — přejmenovat case
        // jde, rawValue ne. Kdo tenhle test mění, rozbíjí staré projekty.
        XCTAssertEqual(ColorPreset.softWedding.rawValue, "softWedding")
        XCTAssertEqual(ColorPreset.warmFilm.rawValue, "warmFilm")
        XCTAssertEqual(ColorPreset.cleanSkin.rawValue, "cleanSkin")
        XCTAssertEqual(ColorPreset.blackAndWhite.rawValue, "blackAndWhite")
        XCTAssertEqual(ColorPreset.allCases.count, 4)
    }

    func testProjectFileRoundtripWithColorGrade() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 100)
        try f.project.setColorGrade(
            clipID: clip, ColorGrade(preset: .cleanSkin, intensity: 0.35))

        let file = ProjectFile(project: f.project, name: "S barvou")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, f.project)
    }
}
