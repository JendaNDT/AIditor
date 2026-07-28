import XCTest
@testable import TimelineModel

/// Matematika UI přechodů (fáze 10, modul 3): lichoběžníky, hit testy,
/// střih pro kontextové menu a překlad tažení okraje na délku.
final class TransitionGeometryTests: XCTestCase {

    /// V1: L = [0, 100), R = [100, 200) se zdrojem od snímku 120;
    /// prolínačka 30 snímků na střihu 100 → oblast [85, 115).
    /// Geometrie výchozí: 4 body na snímek, V1 vysoká 64.
    private func makeScene() throws -> (fx: Fixture, id: TransitionID,
                                        left: ClipID, right: ClipID,
                                        geometry: TimelineGeometry) {
        var fx = Fixture()
        let l = try fx.addClip(start: 0, duration: 100)
        let r = try fx.addClip(start: 100, duration: 100, sourceStartFrames: 120)
        let id = try fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                              betweenLeft: l, andRight: r)
        return (fx, id, l, r, TimelineGeometry())
    }

    // MARK: Rozvržení

    func testLichobeznikLeziNaOblastiPrechodu() throws {
        let (fx, id, _, _, geometry) = try makeScene()
        let placements = TimelineLayout.transitionPlacements(
            project: fx.project, geometry: geometry, scrollX: 0, width: 1000)
        XCTAssertEqual(placements.count, 1)
        let p = placements[0]
        XCTAssertEqual(p.transitionID, id)
        XCTAssertEqual(p.kind, .crossDissolve)
        // Oblast [85, 115) při 4 b/snímek: x = 340, šířka 120, střih na 400.
        XCTAssertEqual(p.x, 340)
        XCTAssertEqual(p.width, 120)
        XCTAssertEqual(p.cutX, 400)
        XCTAssertEqual(p.y, 0)
        XCTAssertEqual(p.height, 64)
    }

    func testLichobeznikMimoOknoNevznika() throws {
        let (fx, _, _, _, geometry) = try makeScene()
        // Okno daleko za oblastí [340, 460): scroll na 5000 bodů.
        let placements = TimelineLayout.transitionPlacements(
            project: fx.project, geometry: geometry, scrollX: 5000, width: 1000)
        XCTAssertTrue(placements.isEmpty)
    }

    func testRozbityPrechodSeNekresli() throws {
        var (fx, _, _, _, geometry) = try makeScene()
        // Rozbít napřímo: pravý klip odsunout → střih zanikl.
        var tracks = fx.project.timeline.tracks
        tracks[0].clips[1].timelineStart = Frames(150)
        fx.project.timeline.tracks = tracks
        let placements = TimelineLayout.transitionPlacements(
            project: fx.project, geometry: geometry, scrollX: 0, width: 1000)
        XCTAssertTrue(placements.isEmpty)
    }

    // MARK: Hit test přechodu

    func testHitTestTeloAOkraje() throws {
        let (fx, id, _, _, geometry) = try makeScene()
        // Oblast v bodech [340, 460), úchop 8 bodů.
        XCTAssertEqual(geometry.transitionHitTest(x: 400, y: 10, in: fx.project),
                       TransitionHit(transitionID: id, trackID: fx.v1, zone: .body))
        XCTAssertEqual(geometry.transitionHitTest(x: 341, y: 10, in: fx.project)?.zone,
                       .leadingEdge)
        XCTAssertEqual(geometry.transitionHitTest(x: 459, y: 10, in: fx.project)?.zone,
                       .trailingEdge)
        // Mimo oblast (dál než půl úchopu) nic.
        XCTAssertNil(geometry.transitionHitTest(x: 330, y: 10, in: fx.project))
        // Jiná stopa (y pod V1) nic.
        XCTAssertNil(geometry.transitionHitTest(x: 400, y: 100, in: fx.project))
    }

    // MARK: Hit test střihu (kontextové menu)

    func testCutHitNajdeNejblizsiStrihVToleranci() throws {
        let (fx, _, l, r, geometry) = try makeScene()
        // Střih na 100 snímcích = 400 bodech; tolerance 2×8 = 16 bodů.
        let hit = geometry.cutHit(x: 410, y: 10, in: fx.project)
        XCTAssertEqual(hit, CutHit(trackID: fx.v1, leftClipID: l, rightClipID: r,
                                   frame: Frames(100)))
        XCTAssertNil(geometry.cutHit(x: 430, y: 10, in: fx.project))
    }

    func testCutHitIgnorujeMezeru() throws {
        var fx = Fixture()
        _ = try fx.addClip(start: 0, duration: 50)
        _ = try fx.addClip(start: 60, duration: 50, sourceStartFrames: 60)
        let geometry = TimelineGeometry()
        // Konec prvního klipu je na 200 bodech, ale sousedi se nedotýkají.
        XCTAssertNil(geometry.cutHit(x: 200, y: 10, in: fx.project))
    }

    // MARK: Tažení okraje

    func testTazeniOkrajeDrziSymetriiKolemStrihu() throws {
        let (fx, id, _, _, _) = try makeScene()
        // Okraj na snímku 130: vzdálenost od střihu 30 → délka 60.
        XCTAssertEqual(fx.project.transitionDraggedDuration(id: id, edgeFrame: Frames(130)),
                       Frames(60))
        // Levý okraj na 90: vzdálenost 10 → délka 20.
        XCTAssertEqual(fx.project.transitionDraggedDuration(id: id, edgeFrame: Frames(90)),
                       Frames(20))
    }

    func testTazeniOkrajeZarazioMezeADvaSnimky() throws {
        var (fx, id, left, right, _) = try makeScene()
        let maxD = fx.project.maxTransitionDuration(kind: .crossDissolve,
                                                    betweenLeft: left, andRight: right)
        // Tažení daleko za mez → zaražené o maximum.
        XCTAssertEqual(fx.project.transitionDraggedDuration(id: id, edgeFrame: Frames(1000)),
                       maxD)
        // Tažení až na střih → podlaha 2 snímky (snímek na každou stranu).
        XCTAssertEqual(fx.project.transitionDraggedDuration(id: id, edgeFrame: Frames(100)),
                       Frames(2))
        // Výsledek na maximu projde setTransitionDuration — mez je táž.
        try fx.project.setTransitionDuration(id: id, to: maxD)
        XCTAssertValid(fx.project)
    }

    func testTazeniZmizeleHoPrechoduVraciNil() throws {
        var (fx, id, left, _, _) = try makeScene()
        try fx.project.remove(clipID: left)
        XCTAssertNil(fx.project.transitionDraggedDuration(id: id, edgeFrame: Frames(120)))
    }
}
