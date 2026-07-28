//
//  AudioOpsTests.swift
//  Projekt Krása — TimelineModel
//
//  Fáze 7, modul 2: hlasitost a mute stopy.
//

import XCTest
@testable import TimelineModel

final class AudioOpsTests: XCTestCase {

    func testNastaveniHlasitosti() throws {
        var fixture = Fixture()
        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: 0.5)
        XCTAssertEqual(fixture.project.timeline.track(id: fixture.a1)?.audio?.volume, 0.5)
        XCTAssertValid(fixture.project)
    }

    func testHlasitostSeZarezavaDoRozsahu() throws {
        var fixture = Fixture()
        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: 99)
        XCTAssertEqual(fixture.project.timeline.track(id: fixture.a1)?.audio?.volume, 2.0)
        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: -1)
        XCTAssertEqual(fixture.project.timeline.track(id: fixture.a1)?.audio?.volume, 0.0)
    }

    func testMute() throws {
        var fixture = Fixture()
        try fixture.project.setTrackMuted(trackID: fixture.a2, isMuted: true)
        XCTAssertEqual(fixture.project.timeline.track(id: fixture.a2)?.audio?.isMuted, true)
        try fixture.project.setTrackMuted(trackID: fixture.a2, isMuted: false)
        XCTAssertEqual(fixture.project.timeline.track(id: fixture.a2)?.audio?.isMuted, false)
    }

    /// Mute hlasitost NEPŘEPISUJE — po odmutování se vrací původní.
    func testMuteZachovaHlasitost() throws {
        var fixture = Fixture()
        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: 0.7)
        try fixture.project.setTrackMuted(trackID: fixture.a1, isMuted: true)
        XCTAssertEqual(fixture.project.effectiveVolume(
            of: fixture.project.timeline.track(id: fixture.a1)!), 0.0)
        try fixture.project.setTrackMuted(trackID: fixture.a1, isMuted: false)
        XCTAssertEqual(fixture.project.effectiveVolume(
            of: fixture.project.timeline.track(id: fixture.a1)!), 0.7)
    }

    func testObrazovaStopaOdmitne() {
        var fixture = Fixture()
        let v1 = fixture.v1
        XCTAssertThrowsUnchanged(&fixture.project,
                                 .wrongTrackKind(expected: .audio, got: .video)) {
            try $0.setTrackVolume(trackID: v1, volume: 0.5)
        }
    }

    func testNeznamaStopaOdmitne() {
        var fixture = Fixture()
        let ghost = TrackID()
        XCTAssertThrowsUnchanged(&fixture.project, .trackNotFound(ghost)) {
            try $0.setTrackMuted(trackID: ghost, isMuted: true)
        }
    }

    /// „Změnil se jen mix?" — rozhodnutí, jestli se smí ušetřit přestavba
    /// kompozice. Změna hlasitosti rozdíl smaže, posun klipu ne.
    func testPorovnaniBezMixu() throws {
        var fixture = Fixture()
        let clipID = try fixture.addClip(start: 0, duration: 60)
        let before = fixture.project.timeline

        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: 0.3)
        try fixture.project.setTrackMuted(trackID: fixture.a2, isMuted: true)
        XCTAssertNotEqual(fixture.project.timeline, before)
        XCTAssertEqual(fixture.project.timeline.withDefaultAudioSettings(),
                       before.withDefaultAudioSettings())

        try fixture.project.move(clipID: clipID, toTrack: fixture.v1, start: Frames(10))
        XCTAssertNotEqual(fixture.project.timeline.withDefaultAudioSettings(),
                          before.withDefaultAudioSettings())
    }

    /// Mix se veze v projektovém souboru — uložit a načíst ho nesmí ztratit.
    func testMixPrezijeProjektovySoubor() throws {
        var fixture = Fixture()
        try fixture.project.setTrackVolume(trackID: fixture.a1, volume: 0.25)
        try fixture.project.setTrackMuted(trackID: fixture.a2, isMuted: true)

        let file = ProjectFile(project: fixture.project, name: "test",
                               createdAt: Date(), modifiedAt: Date())
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project.timeline.track(id: fixture.a1)?.audio?.volume, 0.25)
        XCTAssertEqual(decoded.project.timeline.track(id: fixture.a2)?.audio?.isMuted, true)
    }
}
