//
//  StillTests.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 12, modul 1: fotky na ose a Ken Burns.
//

import XCTest
@testable import TimelineModel

final class StillTests: XCTestCase {

    /// Fixture s fotkou navíc.
    private func makeFixture() -> (f: Fixture, photoID: AssetID) {
        var f = Fixture()
        let photo = Asset.still(url: URL(fileURLWithPath: "/tmp/fotka.heic"))
        f.project.addAsset(photo)
        return (f, photo.id)
    }

    // MARK: - Asset

    func testStillFactoryFlags() {
        let photo = Asset.still(url: URL(fileURLWithPath: "/tmp/f.jpg"))
        XCTAssertTrue(photo.isStill)
        XCTAssertTrue(photo.hasVideo)
        XCTAssertFalse(photo.hasAudio, "fotka nesmí předstírat zvuk")
        XCTAssertEqual(photo.duration, .zero)
    }

    func testStillAssetPassesValidation() {
        let (f, _) = makeFixture()
        XCTAssertValid(f.project)
    }

    func testAssetWithoutIsStillFieldDecodes() throws {
        // Asset zapsaný před fází 12 — pole `isStill` neexistuje.
        let json = """
        {"id": "A-1", "originalURL": "file:///tmp/a.mov",
         "duration": {"value": 90000, "timescale": 90000},
         "measuredFrameRate": 60, "hasVideo": true, "hasAudio": true,
         "isOffline": false}
        """.data(using: .utf8)!
        let asset = try JSONDecoder().decode(Asset.self, from: json)
        XCTAssertFalse(asset.isStill)
    }

    // MARK: - Klip fotky

    func testMakeClipOnStillGetsDefaultDuration() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        XCTAssertEqual(clip.duration, Frames(150), "výchozích 5 s při 30 fps")
        XCTAssertEqual(clip.sourceStart, .zero)
        try f.project.insert(clip, onTrack: f.v1)
        XCTAssertValid(f.project)
    }

    func testStillConsumesNoSourceAndTrimsFreely() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)

        XCTAssertEqual(f.project.sourceConsumption(of: clip), .zero)

        // Natáhnout fotku na minutu — žádný zdroj ji nezarazí.
        try f.project.trimEnd(clipID: clip.id, to: Frames(1800))
        XCTAssertEqual(f.project.timeline.clip(clip.id)?.duration, Frames(1800))
        XCTAssertValid(f.project)

        // A trim začátku doleva k nule taky projde.
        try f.project.trimStart(clipID: clip.id, to: Frames(0))
        XCTAssertValid(f.project)
    }

    func testSplitStillKeepsSourceStartZero() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)

        let (left, right) = try f.project.split(clipID: clip.id, at: Frames(60))
        XCTAssertEqual(f.project.timeline.clip(left)?.sourceStart, .zero)
        XCTAssertEqual(f.project.timeline.clip(right)?.sourceStart, .zero,
                       "fotka stojí — obě poloviny ukazují totéž")
        XCTAssertValid(f.project)
    }

    func testLinkedClipsOnStillFail() {
        var (f, photoID) = makeFixture()
        XCTAssertThrowsError(try f.project.makeLinkedClips(assetID: photoID)) { _ in }
        _ = f   // fixture se nemění
    }

    // MARK: - Rampa na fotce zakázaná

    func testRampOnStillRejectedAndValidated() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)

        let ramp = SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 1.0),
            SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 0.25),
        ])
        XCTAssertThrowsUnchanged(&f.project, .rampOnStillClip) {
            try $0.setSpeedRamp(clipID: clip.id, ramp: ramp)
        }

        // Natvrdo rozbitý stav hlásí validace.
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].speedRamp = ramp
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.rampOnStill(clip.id)))
    }

    // MARK: - Ken Burns

    func testSetKenBurnsOnStill() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)

        let kb = KenBurns(start: .full,
                          end: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        try f.project.setKenBurns(clipID: clip.id, kb)
        XCTAssertEqual(f.project.timeline.clip(clip.id)?.kenBurns, kb)
        XCTAssertValid(f.project)

        // `nil` maže.
        try f.project.setKenBurns(clipID: clip.id, nil)
        XCTAssertNil(f.project.timeline.clip(clip.id)?.kenBurns)
    }

    func testKenBurnsOnVideoClipRejected() throws {
        var f = Fixture()
        let videoClip = try f.addClip(start: 0, duration: 100)
        XCTAssertThrowsUnchanged(&f.project, .kenBurnsNeedsStill) {
            try $0.setKenBurns(clipID: videoClip,
                               KenBurns(start: .full, end: .full))
        }
    }

    func testInvalidKenBurnsRejectedAndValidated() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)

        // Výřez mimo obraz.
        XCTAssertThrowsUnchanged(&f.project, .invalidKenBurns) {
            try $0.setKenBurns(clipID: clip.id, KenBurns(
                start: .full,
                end: NormalizedRect(x: 0.8, y: 0, width: 0.5, height: 0.5)))
        }
        // Degenerovaně malý výřez.
        XCTAssertThrowsUnchanged(&f.project, .invalidKenBurns) {
            try $0.setKenBurns(clipID: clip.id, KenBurns(
                start: NormalizedRect(x: 0, y: 0, width: 0.01, height: 0.01),
                end: .full))
        }

        // Natvrdo rozbité stavy hlásí validace.
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].kenBurns = KenBurns(
            start: .full, end: NormalizedRect(x: 2, y: 0, width: 1, height: 1))
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.invalidKenBurns(clip.id)))
    }

    func testKenBurnsOnNonStillValidated() throws {
        var f = Fixture()
        let videoClip = try f.addClip(start: 0, duration: 100)
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].kenBurns = KenBurns(start: .full, end: .full)
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.kenBurnsOnNonStill(videoClip)))
    }

    func testSplitKeepsKenBurnsOnBothHalves() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)
        let kb = KenBurns(start: .full,
                          end: NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6))
        try f.project.setKenBurns(clipID: clip.id, kb)

        let (left, right) = try f.project.split(clipID: clip.id, at: Frames(60))
        XCTAssertEqual(f.project.timeline.clip(left)?.kenBurns, kb)
        XCTAssertEqual(f.project.timeline.clip(right)?.kenBurns, kb)
        XCTAssertValid(f.project)
    }

    // MARK: - Přechody s fotkou

    func testDissolveNextToStillHasRoom() throws {
        var (f, photoID) = makeFixture()
        let video = try f.addClip(start: 0, duration: 90, sourceStartFrames: 60)
        let photo = try f.project.makeClip(assetID: photoID, at: Frames(90))
        try f.project.insert(photo, onTrack: f.v1)

        // Prolínačka potřebuje zdroj za hranou na OBOU stranách — fotka
        // ho má „nekonečně", video podle souboru. Nesmí to přetéct.
        let maxD = f.project.maxTransitionDuration(kind: .crossDissolve,
                                                   betweenLeft: video, andRight: photo.id)
        XCTAssertGreaterThanOrEqual(maxD.count, 30)

        try f.project.setTransition(.crossDissolve, duration: Frames(20),
                                    betweenLeft: video, andRight: photo.id)
        XCTAssertValid(f.project)
    }

    // MARK: - Projektový soubor

    func testProjectFileRoundtripWithStillAndKenBurns() throws {
        var (f, photoID) = makeFixture()
        let clip = try f.project.makeClip(assetID: photoID)
        try f.project.insert(clip, onTrack: f.v1)
        try f.project.setKenBurns(clipID: clip.id, KenBurns(
            start: .full, end: NormalizedRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)))

        let file = ProjectFile(project: f.project, name: "S fotkou")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, f.project)
    }
}
