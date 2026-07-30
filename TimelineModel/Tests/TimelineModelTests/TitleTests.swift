//
//  TitleTests.swift
//  TimelineModel — Projekt AIditor
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

    // MARK: - Promítnutí do náhledu (modul 2)

    func testTitleCuesSortedAndCarryStyle() throws {
        var (f, t1) = makeFixture()
        let late = try f.project.makeTitle(text: "kapitola", template: .chapter,
                                           at: Frames(200), duration: Frames(60))
        let early = try f.project.makeTitle(text: "jména", template: .names,
                                            alignment: .leading,
                                            at: Frames(10), duration: Frames(90))
        try f.project.addTitle(late, onTrack: t1)
        try f.project.addTitle(early, onTrack: t1)

        // Druhá titulková stopa se do cues počítá taky.
        let t2 = f.project.addTrack(kind: .title, name: "T2")
        let second = try f.project.makeTitle(text: "druhá stopa", at: Frames(50),
                                             duration: Frames(30))
        try f.project.addTitle(second, onTrack: t2)

        let cues = f.project.titleCues()
        XCTAssertEqual(cues.map(\.text), ["jména", "druhá stopa", "kapitola"])
        XCTAssertEqual(cues[0].template, .names)
        XCTAssertEqual(cues[0].alignment, .leading)
        XCTAssertEqual(cues[0].start, Frames(10))
        XCTAssertEqual(cues[0].end, Frames(100))
    }

    // MARK: - Rozvržení na ose (modul 2)

    func testTitlePlacementsCoordinatesAndVisibility() throws {
        var (f, t1) = makeFixture()
        let visible = try f.project.makeTitle(text: "vidět", at: Frames(10),
                                              duration: Frames(20))
        let farAway = try f.project.makeTitle(text: "daleko", at: Frames(10_000),
                                              duration: Frames(20))
        try f.project.addTitle(visible, onTrack: t1)
        try f.project.addTitle(farAway, onTrack: t1)

        let g = TimelineGeometry()   // 4 body/snímek
        let placements = TimelineLayout.titlePlacements(
            project: f.project, geometry: g, scrollX: 0, width: 800)

        XCTAssertEqual(placements.map(\.text), ["vidět"], "daleký titulek se filtruje")
        let p = placements[0]
        XCTAssertEqual(p.titleID, visible.id)
        XCTAssertEqual(p.x, 40)                      // 10 snímků × 4 body
        XCTAssertEqual(p.width, 80)                  // 20 snímků × 4 body
        XCTAssertEqual(p.y, 158, "pruh T1 je pod V1+A1+A2")
        XCTAssertEqual(p.height, 28)
    }

    func testSubtitleStripPlacementsMapToTitleLane() {
        let (f, _) = makeFixture()
        let cues = [SubtitleCue(start: Frames(30), end: Frames(60), text: "řeč"),
                    SubtitleCue(start: Frames(9_000), end: Frames(9_030), text: "daleko")]
        let g = TimelineGeometry()
        let strips = TimelineLayout.subtitleStripPlacements(
            cues: cues, project: f.project, geometry: g, scrollX: 0, width: 800)

        XCTAssertEqual(strips.count, 1, "daleký cue se filtruje")
        XCTAssertEqual(strips[0].x, 120)
        XCTAssertEqual(strips[0].width, 120)
        XCTAssertEqual(strips[0].y, 158)
        XCTAssertEqual(strips[0].height, 28)
    }

    func testSubtitleStripPlacementsEmptyWithoutTitleTrack() {
        // Projekt z doby před fází 11 — bez T1 se pásky nekreslí nikam.
        let p = Project(timeline: Timeline(tracks: [
            Track(kind: .video, name: "V1"),
            Track(kind: .audio, name: "A1"),
        ]))
        let strips = TimelineLayout.subtitleStripPlacements(
            cues: [SubtitleCue(start: Frames(0), end: Frames(30), text: "x")],
            project: p, geometry: TimelineGeometry(), scrollX: 0, width: 800)
        XCTAssertTrue(strips.isEmpty)
    }

    // MARK: - Hit testing (modul 3)

    func testTitleHitTestZones() throws {
        var (f, t1) = makeFixture()
        // 4 body/snímek: titulek 10–60 leží na 40–240 bodech.
        let title = try f.project.makeTitle(text: "x", at: Frames(10), duration: Frames(50))
        try f.project.addTitle(title, onTrack: t1)
        let g = TimelineGeometry()
        let laneY = 160.0    // uvnitř T1 (158–186)

        XCTAssertEqual(g.titleHitTest(x: 42, y: laneY, in: f.project.timeline)?.zone,
                       .leadingEdge)
        XCTAssertEqual(g.titleHitTest(x: 238, y: laneY, in: f.project.timeline)?.zone,
                       .trailingEdge)
        let body = g.titleHitTest(x: 140, y: laneY, in: f.project.timeline)
        XCTAssertEqual(body?.zone, .body)
        XCTAssertEqual(body?.offsetInTitle, Frames(25))
        XCTAssertEqual(body?.titleID, title.id)

        // Mimo titulek a mimo pruh T1 nic.
        XCTAssertNil(g.titleHitTest(x: 400, y: laneY, in: f.project.timeline))
        XCTAssertNil(g.titleHitTest(x: 140, y: 10, in: f.project.timeline),
                     "na V1 se titulky nechytají")
    }

    // MARK: - Náhledy tažení (modul 3)

    func testTitleMovePreviewSnapsAndValidates() throws {
        var (f, t1) = makeFixture()
        try f.addClip(start: 100, duration: 60)   // hrana klipu na 100 a 160
        let a = try f.project.makeTitle(text: "a", at: Frames(0), duration: Frames(30))
        let b = try f.project.makeTitle(text: "b", at: Frames(50), duration: Frames(30))
        try f.project.addTitle(a, onTrack: t1)
        try f.project.addTitle(b, onTrack: t1)

        let g = TimelineGeometry()
        let candidates = g.snapCandidates(in: f.project.timeline,
                                          excludingTitles: [a.id])

        // Ukazatel u snímku 99 (drženo za snímek 0) → začátek se přichytí
        // na hranu klipu 100.
        let snap = f.project.titleMovePreview(id: a.id, pointerFrame: Frames(99),
                                              grabOffset: .zero,
                                              candidates: candidates, geometry: g)
        XCTAssertEqual(snap?.start, Frames(100))
        XCTAssertEqual(snap?.snappedTo?.frame, Frames(100))
        XCTAssertEqual(snap?.isValid, true)

        // Cíl v překryvu s B je neplatný — hlásí se, nezařezává.
        let invalid = f.project.titleMovePreview(id: a.id, pointerFrame: Frames(60),
                                                 grabOffset: .zero,
                                                 candidates: [], geometry: g)
        XCTAssertEqual(invalid?.isValid, false)

        // Záporný začátek se zařeže na nulu.
        let clamped = f.project.titleMovePreview(id: a.id, pointerFrame: Frames(3),
                                                 grabOffset: Frames(20),
                                                 candidates: [], geometry: g)
        XCTAssertEqual(clamped?.start, .zero)
    }

    func testTitleTrimPreviewsClampAtNeighbours() throws {
        var (f, t1) = makeFixture()
        let a = try f.project.makeTitle(text: "a", at: Frames(0), duration: Frames(40))
        let b = try f.project.makeTitle(text: "b", at: Frames(60), duration: Frames(40))
        try f.project.addTitle(a, onTrack: t1)
        try f.project.addTitle(b, onTrack: t1)
        let g = TimelineGeometry()

        // Trim začátku B doleva se zarazí o konec A (40).
        let start = f.project.titleTrimStartPreview(id: b.id, frame: Frames(10),
                                                    candidates: [], geometry: g)
        XCTAssertEqual(start?.start, Frames(40))
        XCTAssertEqual(start?.duration, Frames(60))

        // Trim konce A doprava se zarazí o začátek B (60).
        let end = f.project.titleTrimEndPreview(id: a.id, frame: Frames(90),
                                                candidates: [], geometry: g)
        XCTAssertEqual(end?.duration, Frames(60))

        // Minimální délka 1 snímek na obou stranách.
        let tiny = f.project.titleTrimEndPreview(id: a.id, frame: Frames(-5),
                                                 candidates: [], geometry: g)
        XCTAssertEqual(tiny?.duration, Frames(1))
    }

    func testMaxNewTitleDuration() throws {
        var (f, t1) = makeFixture()
        let title = try f.project.makeTitle(text: "x", at: Frames(100), duration: Frames(50))
        try f.project.addTitle(title, onTrack: t1)

        XCTAssertEqual(f.project.maxNewTitleDuration(at: Frames(40), onTrack: t1),
                       Frames(60), "mezera po nejbližší titulek")
        XCTAssertEqual(f.project.maxNewTitleDuration(at: Frames(120), onTrack: t1),
                       .zero, "uvnitř titulku není místo")
        XCTAssertTrue(f.project.maxNewTitleDuration(at: Frames(200), onTrack: t1).count > 100_000,
                      "za posledním titulkem není mez")
        XCTAssertEqual(f.project.maxNewTitleDuration(at: Frames(40), onTrack: f.v1),
                       .zero, "na netitulkové stopě nic")
    }

    // MARK: - Titulky z řeči: adresa a editace (modul 3, splátka fáze 8)

    private func makeSpeechFixture() throws -> (f: Fixture, clipID: ClipID) {
        var f = Fixture()
        let clipID = try f.addClip(start: 0, duration: 120, on: f.a1)
        try f.project.setTranscript(assetID: f.assetID, segments: [
            TranscriptSegment(start: SourceTime(seconds: 1.0),
                              end: SourceTime(seconds: 2.0), text: "první"),
            TranscriptSegment(start: SourceTime(seconds: 3.0),
                              end: SourceTime(seconds: 3.5), text: "druhý"),
        ])
        return (f, clipID)
    }

    func testSpeechCueRefFindsSegmentWithAddress() throws {
        let (f, _) = try makeSpeechFixture()
        // 1–2 s zdroje = snímky 30–60 na ose (rychlost 1×).
        let ref = f.project.speechCueRef(at: Frames(45))
        XCTAssertEqual(ref?.assetID, f.assetID)
        XCTAssertEqual(ref?.segmentIndex, 0)
        XCTAssertEqual(ref?.text, "první")
        XCTAssertEqual(ref?.start, Frames(30))
        XCTAssertEqual(ref?.end, Frames(60))

        XCTAssertEqual(f.project.speechCueRef(at: Frames(100))?.text, "druhý")
        XCTAssertNil(f.project.speechCueRef(at: Frames(70)), "mezi úseky nic")
    }

    func testSetTranscriptTextEditsAndEmptyRemoves() throws {
        var (f, _) = try makeSpeechFixture()
        try f.project.setTranscriptText(assetID: f.assetID, segmentIndex: 0,
                                        text: "opravený")
        XCTAssertEqual(f.project.speechCueRef(at: Frames(45))?.text, "opravený")

        // Prázdný text úsek maže; druhý úsek se posune na index 0.
        try f.project.setTranscriptText(assetID: f.assetID, segmentIndex: 0, text: "  ")
        XCTAssertNil(f.project.speechCueRef(at: Frames(45)))
        XCTAssertEqual(f.project.speechCueRef(at: Frames(100))?.segmentIndex, 0)

        XCTAssertThrowsUnchanged(&f.project, .invalidTranscriptSegment) {
            try $0.setTranscriptText(assetID: f.assetID, segmentIndex: 5, text: "x")
        }
    }
}
