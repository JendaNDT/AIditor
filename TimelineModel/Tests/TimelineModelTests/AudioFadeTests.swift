//
//  AudioFadeTests.swift
//  TimelineModel — Projekt AIditor
//
//  Fáze 16, modul 1: zvukové fade na hranách klipu.
//

import XCTest
@testable import TimelineModel

final class AudioFadeTests: XCTestCase {

    /// Zvukový klip [0, 120) na A1.
    private func makeFixture() throws -> (f: Fixture, clipID: ClipID) {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 120, on: f.a1)
        return (f, clip)
    }

    func testSetAndClearFades() throws {
        var (f, clip) = try makeFixture()
        let fades = AudioFades(fadeIn: Frames(15), fadeOut: Frames(30))
        try f.project.setAudioFades(clipID: clip, fades)
        XCTAssertEqual(f.clip(clip)?.audioFades, fades)
        XCTAssertValid(f.project)

        try f.project.setAudioFades(clipID: clip, nil)
        XCTAssertNil(f.clip(clip)?.audioFades)
    }

    func testEmptyFadesStoreAsNil() throws {
        var (f, clip) = try makeFixture()
        try f.project.setAudioFades(clipID: clip, AudioFades())
        XCTAssertNil(f.clip(clip)?.audioFades, "prázdné fade se neukládají")
    }

    func testFadesOnVideoClipRejected() throws {
        var f = Fixture()
        let video = try f.addClip(start: 0, duration: 100)
        XCTAssertThrowsUnchanged(&f.project,
                                 .wrongTrackKind(expected: .audio, got: .video)) {
            try $0.setAudioFades(clipID: video, AudioFades(fadeIn: Frames(10)))
        }
    }

    func testOversizedFadesRejected() throws {
        var (f, clip) = try makeFixture()
        XCTAssertThrowsUnchanged(&f.project, .invalidAudioFades(maxTotal: Frames(120))) {
            try $0.setAudioFades(clipID: clip, AudioFades(fadeIn: Frames(100),
                                                         fadeOut: Frames(30)))
        }
        XCTAssertThrowsUnchanged(&f.project, .invalidAudioFades(maxTotal: Frames(120))) {
            try $0.setAudioFades(clipID: clip, AudioFades(fadeIn: Frames(-1)))
        }
    }

    func testEffectiveFadesClampAfterTrim() throws {
        var (f, clip) = try makeFixture()
        try f.project.setAudioFades(clipID: clip, AudioFades(fadeIn: Frames(45),
                                                             fadeOut: Frames(45)))
        // Zkrácení na 60 snímků: součet fade (90) přesahuje délku — model
        // to dovolí (invariant hlídá jen zápornost a stopu), kompozice
        // čte zařezanou verzi: nájezd celý, dojezd o zbytek.
        try f.project.trimEnd(clipID: clip, to: Frames(60))
        XCTAssertValid(f.project)
        let effective = try XCTUnwrap(
            f.project.effectiveAudioFades(of: f.clip(clip)!))
        XCTAssertEqual(effective.fadeIn, Frames(45))
        XCTAssertEqual(effective.fadeOut, Frames(15))
    }

    func testSplitDistributesFadesByEdge() throws {
        var (f, clip) = try makeFixture()
        try f.project.setAudioFades(clipID: clip, AudioFades(fadeIn: Frames(15),
                                                             fadeOut: Frames(30)))
        let (left, right) = try f.project.split(clipID: clip, at: Frames(60))
        XCTAssertEqual(f.clip(left)?.audioFades, AudioFades(fadeIn: Frames(15)),
                       "nájezd patří začátku — levé polovině")
        XCTAssertEqual(f.clip(right)?.audioFades, AudioFades(fadeOut: Frames(30)),
                       "dojezd patří konci — pravé polovině")
        XCTAssertValid(f.project)
    }

    func testFadesOnWrongTrackValidated() throws {
        var f = Fixture()
        let video = try f.addClip(start: 0, duration: 100)
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].audioFades = AudioFades(fadeIn: Frames(10))
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.invalidAudioFades(video)))
    }

    func testClipWithoutFadesFieldDecodes() throws {
        let json = """
        {"id": "C-1", "assetID": "A-1",
         "timelineStart": 0, "duration": 100,
         "sourceStart": {"value": 0, "timescale": 90000}}
        """.data(using: .utf8)!
        let clip = try JSONDecoder().decode(Clip.self, from: json)
        XCTAssertNil(clip.audioFades)
    }

    func testProjectFileRoundtripWithFades() throws {
        var (f, clip) = try makeFixture()
        try f.project.setAudioFades(clipID: clip, AudioFades(fadeIn: Frames(10),
                                                             fadeOut: Frames(20)))
        let file = ProjectFile(project: f.project, name: "S fady")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, f.project)
    }
}
