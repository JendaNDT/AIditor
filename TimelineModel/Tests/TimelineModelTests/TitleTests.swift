//
//  TitleTests.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 11, modul 1: stopa T1 a titulkové klipy.
//

import XCTest
@testable import TimelineModel

final class TitleTests: XCTestCase {

    /// Fixture s po ruce vytaženou T1.
    private func makeFixture() -> (f: Fixture, t1: TrackID) {
        let f = Fixture()
        let t1 = f.project.timeline.tracks.first { $0.kind == .title }!.id
        return (f, t1)
    }

    // MARK: - Výchozí projekt

    func testEmptyProjectHasTitleTrackLast() {
        let p = Project.empty()
        XCTAssertEqual(p.timeline.tracks.count, 4)
        XCTAssertEqual(p.timeline.tracks.map(\.kind), [.video, .audio, .audio, .title])
        XCTAssertEqual(p.timeline.tracks.last?.name, "T1")
        // Aplikace si domýšlí tracks[0] = V1 a tracks[1] = A1 — T1 na konci
        // je smlouva, ne náhoda. Kdo ji poruší, rozbije CLI ověření v appce.
        XCTAssertEqual(p.timeline.tracks[0].kind, .video)
        XCTAssertEqual(p.timeline.tracks[1].kind, .audio)
        XCTAssertNil(p.timeline.tracks.last?.audio, "titulková stopa nemá mix")
        XCTAssertValid(p)
    }

    // MARK: - Výroba a vkládání

    func testMakeTitleMintsIDAndDefaultDuration() throws {
        let p = Project.empty()
        let a = try p.makeTitle(text: "Anna a Petr")
        let b = try p.makeTitle(text: "Anna a Petr")
        XCTAssertNotEqual(a.id, b.id, "model razí jedinečná ID")
        XCTAssertEqual(a.duration, Frames(120), "výchozí 4 s při 30 fps")
        XCTAssertEqual(a.template, .plain)
        XCTAssertEqual(a.alignment, .center)
    }

    func testMakeTitleRejectsNonsense() {
        let p = Project.empty()
        XCTAssertThrowsError(try p.makeTitle(text: "x", duration: Frames(0)))
        XCTAssertThrowsError(try p.makeTitle(text: "x", at: Frames(-1)))
    }

    func testAddTitleOnTitleTrack() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "Kapitola: obřad", template: .chapter,
                                            at: Frames(60), duration: Frames(90))
        try f.project.addTitle(title, onTrack: t1)
        XCTAssertEqual(f.project.timeline.titleClip(title.id)?.text, "Kapitola: obřad")
        XCTAssertValid(f.project)
    }

    func testAddTitleOnWrongTrackKindThrows() throws {
        var (f, _) = makeFixture()
        let title = try f.project.makeTitle(text: "x")
        XCTAssertThrowsUnchanged(&f.project,
                                 .wrongTrackKind(expected: .title, got: .video)) {
            try $0.addTitle(title, onTrack: f.v1)
        }
    }

    func testAssetClipOnTitleTrackThrows() throws {
        var (f, t1) = makeFixture()
        let clip = try f.project.makeClip(assetID: f.assetID)
        XCTAssertThrowsUnchanged(&f.project) {
            try $0.insert(clip, onTrack: t1)
        }
    }

    func testAddTitleOverlapThrowsWithNearestLegal() throws {
        var (f, t1) = makeFixture()
        let a = try f.project.makeTitle(text: "A", at: Frames(100), duration: Frames(50))
        try f.project.addTitle(a, onTrack: t1)

        // Překryv zleva: nejbližší legální pozice je těsně před A.
        let b = try f.project.makeTitle(text: "B", at: Frames(80), duration: Frames(40))
        XCTAssertThrowsUnchanged(&f.project,
                                 .titleWouldOverlap(with: a.id, nearestLegal: Frames(60))) {
            try $0.addTitle(b, onTrack: t1)
        }

        // Dotyk překryv není.
        let c = try f.project.makeTitle(text: "C", at: Frames(150), duration: Frames(30))
        try f.project.addTitle(c, onTrack: t1)
        XCTAssertValid(f.project)
    }

    func testTitlesKeptSorted() throws {
        var (f, t1) = makeFixture()
        let late = try f.project.makeTitle(text: "pozdní", at: Frames(300), duration: Frames(30))
        let early = try f.project.makeTitle(text: "raný", at: Frames(0), duration: Frames(30))
        try f.project.addTitle(late, onTrack: t1)
        try f.project.addTitle(early, onTrack: t1)
        let texts = f.project.timeline.track(id: t1)!.titles.map(\.text)
        XCTAssertEqual(texts, ["raný", "pozdní"])
        XCTAssertValid(f.project)
    }

    // MARK: - Mazání a přesun

    func testRemoveTitle() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x")
        try f.project.addTitle(title, onTrack: t1)
        try f.project.removeTitle(id: title.id)
        XCTAssertNil(f.project.timeline.titleClip(title.id))
        XCTAssertThrowsUnchanged(&f.project, .titleNotFound(title.id)) {
            try $0.removeTitle(id: title.id)
        }
    }

    func testMoveTitleWithinTrack() throws {
        var (f, t1) = makeFixture()
        let a = try f.project.makeTitle(text: "A", at: Frames(0), duration: Frames(50))
        let b = try f.project.makeTitle(text: "B", at: Frames(100), duration: Frames(50))
        try f.project.addTitle(a, onTrack: t1)
        try f.project.addTitle(b, onTrack: t1)

        // Legální přesun, pole se přerovná.
        try f.project.moveTitle(id: a.id, start: Frames(200))
        XCTAssertEqual(f.project.timeline.track(id: t1)!.titles.map(\.text), ["B", "A"])
        XCTAssertValid(f.project)

        // Přesun do překryvu se odmítne a nic se nezmění.
        XCTAssertThrowsUnchanged(&f.project) {
            try $0.moveTitle(id: a.id, start: Frames(120))
        }

        // Přesun na vlastní pozici je no-op.
        try f.project.moveTitle(id: a.id, start: Frames(200))
        XCTAssertValid(f.project)
    }

    func testMoveTitleToOtherTitleTrackOnly() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x")
        try f.project.addTitle(title, onTrack: t1)

        XCTAssertThrowsUnchanged(&f.project,
                                 .wrongTrackKind(expected: .title, got: .audio)) {
            try $0.moveTitle(id: title.id, toTrack: f.a1, start: Frames(0))
        }

        let t2 = f.project.addTrack(kind: .title, name: "T2")
        try f.project.moveTitle(id: title.id, toTrack: t2, start: Frames(10))
        XCTAssertEqual(f.project.timeline.track(id: t2)!.titles.count, 1)
        XCTAssertTrue(f.project.timeline.track(id: t1)!.titles.isEmpty)
        XCTAssertValid(f.project)
    }

    // MARK: - Trim

    func testTrimTitle() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x", at: Frames(100), duration: Frames(60))
        try f.project.addTitle(title, onTrack: t1)

        try f.project.trimTitleStart(id: title.id, to: Frames(80))
        var now = f.project.timeline.titleClip(title.id)!
        XCTAssertEqual(now.timelineStart, Frames(80))
        XCTAssertEqual(now.timelineEnd, Frames(160), "konec se trimem začátku nehnul")

        try f.project.trimTitleEnd(id: title.id, to: Frames(200))
        now = f.project.timeline.titleClip(title.id)!
        XCTAssertEqual(now.duration, Frames(120))
        XCTAssertValid(f.project)

        // Titulek nemá zdroj — natáhnout ho jde libovolně daleko.
        try f.project.trimTitleEnd(id: title.id, to: Frames(100_000))
        XCTAssertValid(f.project)
    }

    func testTrimTitleRejectsNonsense() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x", at: Frames(100), duration: Frames(60))
        try f.project.addTitle(title, onTrack: t1)

        XCTAssertThrowsUnchanged(&f.project, .zeroLength) {
            try $0.trimTitleStart(id: title.id, to: Frames(160))
        }
        XCTAssertThrowsUnchanged(&f.project, .negativePosition) {
            try $0.trimTitleStart(id: title.id, to: Frames(-5))
        }
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) {
            try $0.trimTitleEnd(id: title.id, to: Frames(100))
        }
    }

    func testTrimTitleIntoNeighbourRejected() throws {
        var (f, t1) = makeFixture()
        let a = try f.project.makeTitle(text: "A", at: Frames(0), duration: Frames(50))
        let b = try f.project.makeTitle(text: "B", at: Frames(60), duration: Frames(50))
        try f.project.addTitle(a, onTrack: t1)
        try f.project.addTitle(b, onTrack: t1)

        XCTAssertThrowsUnchanged(&f.project) {
            try $0.trimTitleEnd(id: a.id, to: Frames(70))
        }
        XCTAssertThrowsUnchanged(&f.project) {
            try $0.trimTitleStart(id: b.id, to: Frames(40))
        }
        // Dotyk projde.
        try f.project.trimTitleEnd(id: a.id, to: Frames(60))
        XCTAssertValid(f.project)
    }

    // MARK: - Obsah

    func testSetTitleContent() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "pracovní")
        try f.project.addTitle(title, onTrack: t1)

        try f.project.setTitleText(id: title.id, "Anna a Petr")
        try f.project.setTitleTemplate(id: title.id, .names)
        try f.project.setTitleAlignment(id: title.id, .leading)

        let now = f.project.timeline.titleClip(title.id)!
        XCTAssertEqual(now.text, "Anna a Petr")
        XCTAssertEqual(now.template, .names)
        XCTAssertEqual(now.alignment, .leading)
        XCTAssertValid(f.project)
    }

    // MARK: - Délka projektu

    func testProjectDurationIncludesTrailingTitle() throws {
        var (f, t1) = makeFixture()
        try f.addClip(start: 0, duration: 120)
        XCTAssertEqual(f.project.duration, Frames(120))

        // Poděkování za posledním záběrem (přes černou) film prodlužuje.
        let thanks = try f.project.makeTitle(text: "Děkujeme", template: .thanks,
                                             at: Frames(150), duration: Frames(90))
        try f.project.addTitle(thanks, onTrack: t1)
        XCTAssertEqual(f.project.duration, Frames(240))
    }

    // MARK: - Stopa T1 u starších projektů

    func testEnsureTitleTrack() throws {
        // Projekt „z doby před fází 11": bez titulkové stopy.
        var p = Project(timeline: Timeline(tracks: [
            Track(kind: .video, name: "V1"),
            Track(kind: .audio, name: "A1"),
        ]))
        let made = p.ensureTitleTrack()
        XCTAssertEqual(p.timeline.track(id: made)?.kind, .title)
        XCTAssertEqual(p.timeline.tracks.count, 3)

        // Podruhé vrací tutéž, nevyrábí další.
        XCTAssertEqual(p.ensureTitleTrack(), made)
        XCTAssertEqual(p.timeline.tracks.count, 3)
    }

    // MARK: - Zpětná kompatibilita formátu

    func testTrackWithoutTitlesFieldDecodes() throws {
        // Stopa zapsaná před fází 11 — pole `titles` neexistuje.
        let json = """
        {"id": "T-1", "kind": "video", "name": "V1", "clips": []}
        """.data(using: .utf8)!
        let track = try JSONDecoder().decode(Track.self, from: json)
        XCTAssertTrue(track.titles.isEmpty)
        XCTAssertTrue(track.transitions.isEmpty)
    }

    func testProjectFileRoundtripWithTitles() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "Anna a Petr", template: .names,
                                            alignment: .trailing,
                                            at: Frames(30), duration: Frames(90))
        try f.project.addTitle(title, onTrack: t1)

        let file = ProjectFile(project: f.project, name: "Svatba")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, f.project)
        XCTAssertEqual(decoded.formatVersion, 2, "druh stopy .title zvedl formát na 2")
    }

    func testVersion1FileStillLoads() throws {
        // Soubor verze 1 (před fází 11): tři stopy, žádné `titles`.
        let json = """
        {
          "formatVersion": 1,
          "name": "Starý projekt",
          "createdAt": "2026-07-27T10:00:00Z",
          "modifiedAt": "2026-07-27T10:00:00Z",
          "project": {
            "assets": [],
            "usesProxies": false,
            "timeline": {
              "frameRate": 30,
              "canvasSize": {"width": 3840, "height": 2160},
              "tracks": [
                {"id": "V", "kind": "video", "name": "V1", "clips": []},
                {"id": "A", "kind": "audio", "name": "A1", "clips": [],
                 "audio": {"volume": 1, "isMuted": false}}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let file = try ProjectFile.decode(json)
        XCTAssertEqual(file.project.timeline.tracks.count, 2)
        XCTAssertNil(file.project.timeline.tracks.first { $0.kind == .title },
                     "starý soubor T1 nemá — doplní ji až ensureTitleTrack, ne dekodér")
        XCTAssertValid(file.project)
    }

    // MARK: - Invarianty (rozbité stavy natvrdo, přes @testable)

    func testValidateCatchesTitleOnWrongTrack() {
        var (f, _) = makeFixture()
        let title = TitleClip(text: "x", template: .plain, alignment: .center,
                              timelineStart: Frames(0), duration: Frames(10))
        var tracks = f.project.timeline.tracks
        tracks[0].titles = [title]     // V1
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.titleOnWrongTrack(title.id)))
    }

    func testValidateCatchesUnsortedAndOverlappingTitles() {
        var (f, t1) = makeFixture()
        let a = TitleClip(text: "a", template: .plain, alignment: .center,
                          timelineStart: Frames(100), duration: Frames(50))
        let b = TitleClip(text: "b", template: .plain, alignment: .center,
                          timelineStart: Frames(0), duration: Frames(120))
        let ti = f.project.timeline.index(of: t1)!
        var tracks = f.project.timeline.tracks
        tracks[ti].titles = [a, b]     // špatné pořadí; b navíc přesahuje do a
        f.project.timeline.tracks = tracks
        let violations = f.project.validate()
        XCTAssertTrue(violations.contains(.unsortedTitles(t1)))
        XCTAssertTrue(violations.contains(.overlappingTitles(a.id, b.id)))
    }

    func testValidateCatchesDegenerateTitles() {
        var (f, t1) = makeFixture()
        let zero = TitleClip(text: "x", template: .plain, alignment: .center,
                             timelineStart: Frames(-5), duration: Frames(0))
        let dup = TitleClip(id: zero.id, text: "y", template: .plain, alignment: .center,
                            timelineStart: Frames(100), duration: Frames(10))
        let ti = f.project.timeline.index(of: t1)!
        var tracks = f.project.timeline.tracks
        tracks[ti].titles = [zero, dup]
        f.project.timeline.tracks = tracks
        let violations = f.project.validate()
        XCTAssertTrue(violations.contains(.nonPositiveTitleDuration(zero.id)))
        XCTAssertTrue(violations.contains(.negativeTitleStart(zero.id)))
        XCTAssertTrue(violations.contains(.duplicateTitleID(dup.id)))
    }

    // MARK: - Geometrie

    func testGeometryHeightsWithTitleTrack() {
        let p = Project.empty()      // V1 + A1 + A2 + T1
        let g = TimelineGeometry()
        XCTAssertEqual(g.height(of: .title), 28)
        // V(64) + 2 + A(44) + 2 + A(44) + 2 + T(28) = 186
        XCTAssertEqual(g.totalHeight(of: p.timeline), 186)
        // T1 začíná pod třemi stopami a mezerami: 64+2+44+2+44+2 = 158.
        XCTAssertEqual(g.y(ofTrackAt: 3, in: p.timeline), 158)
        XCTAssertEqual(g.trackIndex(atY: 160, in: p.timeline), 3)
    }

    func testSnapCandidatesIncludeTitleEdges() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x", at: Frames(40), duration: Frames(20))
        try f.project.addTitle(title, onTrack: t1)
        let g = TimelineGeometry()
        let frames = g.snapCandidates(in: f.project.timeline).map(\.frame)
        XCTAssertTrue(frames.contains(Frames(40)))
        XCTAssertTrue(frames.contains(Frames(60)))
    }
}
