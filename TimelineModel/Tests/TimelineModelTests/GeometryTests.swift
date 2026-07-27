import XCTest
@testable import TimelineModel

/// Matematika timeline view. Tady se testuje to, co by jinak šlo ověřit
/// jen okem na běžící aplikaci.
final class GeometryTests: XCTestCase {

    // MARK: Mapování čas ↔ pixel

    func testFrameToXAndBack() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        XCTAssertEqual(g.x(for: Frames(100)), 400)
        XCTAssertEqual(g.frame(atX: 400), Frames(100))
    }

    /// Zaokrouhluje se na NEJBLIŽŠÍ snímek, ne dolů — jinak by se všechno
    /// systematicky posouvalo o půl snímku vlevo.
    func testXRoundsToNearestFrame() {
        let g = TimelineGeometry(pointsPerFrame: 10)
        XCTAssertEqual(g.frame(atX: 104), Frames(10), "4 body z desíti = zaokrouhlit dolů")
        XCTAssertEqual(g.frame(atX: 106), Frames(11), "6 bodů z desíti = zaokrouhlit nahoru")
        XCTAssertEqual(g.frame(atX: 105), Frames(11), "přesná půlka nahoru")
    }

    func testZoomIsClamped() {
        var g = TimelineGeometry()
        g.setZoom(10_000)
        XCTAssertEqual(g.pointsPerFrame, TimelineGeometry.maxPointsPerFrame)
        g.setZoom(0)
        XCTAssertEqual(g.pointsPerFrame, TimelineGeometry.minPointsPerFrame)
    }

    func testWidthOfDuration() {
        let g = TimelineGeometry(pointsPerFrame: 2.5)
        XCTAssertEqual(g.width(of: Frames(40)), 100)
    }

    // MARK: Svislé rozvržení

    func testTrackLayoutStacksWithSpacing() {
        let p = Project.empty()          // V1 (64) + A1 (44) + A2 (44), mezera 2
        let g = TimelineGeometry()
        XCTAssertEqual(g.y(ofTrackAt: 0, in: p.timeline), 0)
        XCTAssertEqual(g.y(ofTrackAt: 1, in: p.timeline), 66)
        XCTAssertEqual(g.y(ofTrackAt: 2, in: p.timeline), 112)
        XCTAssertEqual(g.totalHeight(of: p.timeline), 156, "bez koncové mezery")
    }

    func testTrackIndexAtY() {
        let p = Project.empty()
        let g = TimelineGeometry()
        XCTAssertEqual(g.trackIndex(atY: 0, in: p.timeline), 0)
        XCTAssertEqual(g.trackIndex(atY: 63, in: p.timeline), 0)
        XCTAssertNil(g.trackIndex(atY: 65, in: p.timeline), "mezera mezi stopami")
        XCTAssertEqual(g.trackIndex(atY: 66, in: p.timeline), 1)
        XCTAssertNil(g.trackIndex(atY: 1000, in: p.timeline), "pod poslední stopou")
        XCTAssertNil(g.trackIndex(atY: -5, in: p.timeline))
    }

    // MARK: Viditelný rozsah

    func testVisibleRangeCoversWindowPlusOverscan() {
        let g = TimelineGeometry(pointsPerFrame: 2)
        let range = g.visibleFrameRange(scrollX: 1000, width: 800, overscanPoints: 200)
        XCTAssertEqual(range.lowerBound, Frames(400))   // (1000−200)/2
        XCTAssertEqual(range.upperBound, Frames(1000))  // (1000+800+200)/2
    }

    func testVisibleRangeAtOriginDoesNotGoNegative() {
        let g = TimelineGeometry(pointsPerFrame: 2)
        let range = g.visibleFrameRange(scrollX: 0, width: 800, overscanPoints: 200)
        XCTAssertEqual(range.lowerBound, .zero)
    }

    func testVisibleClipsPicksOnlyIntersecting() throws {
        var f = Fixture(seconds: 600)
        for i in 0..<100 { try f.addClip(start: i * 100, duration: 50) }
        let g = TimelineGeometry()
        let track = f.project.timeline.tracks[0]

        let slice = g.visibleClips(on: track, in: Frames(1000) ..< Frames(1300))
        // Klipy [1000,1050), [1100,1150), [1200,1250) — tři.
        XCTAssertEqual(slice.count, 3)
        XCTAssertEqual(slice.first?.timelineStart, Frames(1000))
    }

    func testVisibleClipsIncludesClipStraddlingRangeStart() throws {
        var f = Fixture(seconds: 600)
        try f.addClip(start: 0, duration: 500)
        let g = TimelineGeometry()
        let track = f.project.timeline.tracks[0]
        let slice = g.visibleClips(on: track, in: Frames(100) ..< Frames(200))
        XCTAssertEqual(slice.count, 1, "klip přesahující oknem musí být vidět")
    }

    func testVisibleClipsExcludesTouchingNeighbours() throws {
        var f = Fixture(seconds: 600)
        try f.addClip(start: 0, duration: 100)      // [0,100)
        try f.addClip(start: 100, duration: 100)    // [100,200)
        let g = TimelineGeometry()
        let track = f.project.timeline.tracks[0]
        // Rozsah [100,150) se prvního klipu jen dotýká, nesmí ho vrátit.
        let slice = g.visibleClips(on: track, in: Frames(100) ..< Frames(150))
        XCTAssertEqual(slice.count, 1)
        XCTAssertEqual(slice.first?.timelineStart, Frames(100))
    }

    func testVisibleClipsOnEmptyTrack() {
        let p = Project.empty()
        let g = TimelineGeometry()
        XCTAssertTrue(g.visibleClips(on: p.timeline.tracks[0], in: Frames(0) ..< Frames(100)).isEmpty)
    }

    /// Binární půlení, ne průchod. U tisíce klipů se tohle volá při každém
    /// scrollnutí, takže lineární hledání by se sčítalo do sekání.
    func testVisibleClipsIsFastOnManyClips() throws {
        var f = Fixture(seconds: 2000)
        for i in 0..<2000 { try f.addClip(start: i * 20, duration: 10) }
        let g = TimelineGeometry()
        let track = f.project.timeline.tracks[0]
        measure {
            for start in stride(from: 0, to: 39_000, by: 500) {
                _ = g.visibleClips(on: track, in: Frames(start) ..< Frames(start + 400))
            }
        }
    }

    // MARK: Hit testing

    private func hitFixture() throws -> (Fixture, TimelineGeometry, ClipID) {
        var f = Fixture(seconds: 100)
        let id = try f.addClip(start: 100, duration: 200)   // [100,300)
        let g = TimelineGeometry(pointsPerFrame: 4, edgeGrabWidth: 8)
        return (f, g, id)
    }

    func testHitTestBody() throws {
        let (f, g, id) = try hitFixture()
        let hit = g.hitTest(x: g.x(for: Frames(200)), y: 10, in: f.project.timeline)
        XCTAssertEqual(hit?.clipID, id)
        XCTAssertEqual(hit?.zone, .body)
        XCTAssertEqual(hit?.offsetInClip, Frames(100))
    }

    func testHitTestEdgesWinOverBody() throws {
        let (f, g, id) = try hitFixture()
        let startX = g.x(for: Frames(100))
        let endX = g.x(for: Frames(300))

        XCTAssertEqual(g.hitTest(x: startX + 2, y: 10, in: f.project.timeline)?.zone, .leadingEdge)
        XCTAssertEqual(g.hitTest(x: endX - 2, y: 10, in: f.project.timeline)?.zone, .trailingEdge)
        XCTAssertEqual(g.hitTest(x: startX + 2, y: 10, in: f.project.timeline)?.clipID, id)
    }

    func testHitTestMissesEmptySpace() throws {
        let (f, g, _) = try hitFixture()
        XCTAssertNil(g.hitTest(x: g.x(for: Frames(500)), y: 10, in: f.project.timeline))
    }

    func testHitTestMissesWrongTrack() throws {
        let (f, g, _) = try hitFixture()
        // y = 70 je už na A1, kde klip není
        XCTAssertNil(g.hitTest(x: g.x(for: Frames(200)), y: 70, in: f.project.timeline))
    }

    /// U klipu užšího než dva úchopy se plocha rozdělí napůl — jinak by
    /// jedna strana překryla druhou a nešla by chytit vůbec.
    func testHitTestOnVeryNarrowClip() throws {
        var f = Fixture(seconds: 100)
        try f.addClip(start: 0, duration: 1)          // jeden snímek
        let g = TimelineGeometry(pointsPerFrame: 4, edgeGrabWidth: 8)   // klip je 4 body široký
        let leading = g.hitTest(x: 0.5, y: 10, in: f.project.timeline)
        let trailing = g.hitTest(x: 3.5, y: 10, in: f.project.timeline)
        XCTAssertEqual(leading?.zone, .leadingEdge)
        XCTAssertEqual(trailing?.zone, .trailingEdge)
    }

    /// Okraj klipu musí jít chytit i při odzoomování, kdy je klip
    /// jen pár bodů široký. Proto je úchop v bodech, ne ve snímcích.
    func testEdgeStaysGrabbableWhenZoomedOut() throws {
        var f = Fixture(seconds: 600)
        try f.addClip(start: 0, duration: 3000)
        let g = TimelineGeometry(pointsPerFrame: 0.05, edgeGrabWidth: 8)  // klip 150 bodů
        let hit = g.hitTest(x: 2, y: 10, in: f.project.timeline)
        XCTAssertEqual(hit?.zone, .leadingEdge, "při odzoomu musí okraj pořád jít chytit")
    }

    // MARK: Přichytávání

    func testSnapPullsToNearestCandidate() {
        let g = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 10)
        let candidates = [SnapCandidate(frame: Frames(100), kind: .clipEdge)]
        // 102 snímků = 8 bodů od kandidáta, v toleranci
        XCTAssertEqual(g.snap(Frames(102), to: candidates).frame, Frames(100))
    }

    func testSnapIgnoresCandidatesOutsideTolerance() {
        let g = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 10)
        let candidates = [SnapCandidate(frame: Frames(100), kind: .clipEdge)]
        // 105 snímků = 20 bodů, mimo toleranci
        XCTAssertEqual(g.snap(Frames(105), to: candidates).frame, Frames(105))
    }

    /// Tolerance je v bodech, takže při odzoomování pokrývá víc snímků.
    /// Kdyby byla ve snímcích, chovala by se při každém zoomu jinak.
    func testSnapToleranceScalesWithZoom() {
        let candidates = [SnapCandidate(frame: Frames(1000), kind: .clipEdge)]

        // Přiblíženo: 10 bodů tolerance = jeden snímek.
        let zoomedIn = TimelineGeometry(pointsPerFrame: 10, snapTolerance: 10)
        XCTAssertEqual(zoomedIn.snap(Frames(1001), to: candidates).frame, Frames(1000),
                       "1 snímek = 10 bodů, přesně v toleranci")
        XCTAssertEqual(zoomedIn.snap(Frames(1002), to: candidates).frame, Frames(1002),
                       "2 snímky = 20 bodů, mimo toleranci")

        // Odzoomováno: týchž 10 bodů je dvacet snímků.
        let zoomedOut = TimelineGeometry(pointsPerFrame: 0.5, snapTolerance: 10)
        XCTAssertEqual(zoomedOut.snap(Frames(1015), to: candidates).frame, Frames(1000),
                       "15 snímků je při odzoomu jen 7,5 bodu — přichytit se má")
        XCTAssertEqual(zoomedOut.snap(Frames(1030), to: candidates).frame, Frames(1030),
                       "30 snímků = 15 bodů, mimo")
    }

    /// Při shodné vzdálenosti vyhrává silnější druh, aby výsledek nezávisel
    /// na pořadí v poli.
    func testSnapPrefersStrongerKindOnTie() {
        let g = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 20)
        let candidates = [
            SnapCandidate(frame: Frames(100), kind: .clipEdge),
            SnapCandidate(frame: Frames(100), kind: .origin),
        ]
        XCTAssertEqual(g.snap(Frames(102), to: candidates).candidate?.kind, .origin)
    }

    func testSnapCandidatesExcludeDraggedClip() throws {
        var f = Fixture(seconds: 100)
        let dragged = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 200, duration: 100)
        let g = TimelineGeometry()

        let all = g.snapCandidates(in: f.project.timeline)
        let filtered = g.snapCandidates(in: f.project.timeline, excluding: [dragged])

        XCTAssertTrue(all.contains { $0.frame == Frames(100) && $0.kind == .clipEdge })
        XCTAssertFalse(filtered.contains { $0.frame == Frames(100) && $0.kind == .clipEdge },
                       "na vlastní hrany se tažený klip přichytávat nesmí")
        XCTAssertTrue(filtered.contains { $0.frame == Frames(200) })
    }

    func testSnapCandidatesAlwaysIncludeOrigin() {
        let p = Project.empty()
        let g = TimelineGeometry()
        XCTAssertTrue(g.snapCandidates(in: p.timeline).contains { $0.kind == .origin })
    }

    func testSnapCandidatesIncludePlayhead() {
        let p = Project.empty()
        let g = TimelineGeometry()
        let candidates = g.snapCandidates(in: p.timeline, playhead: Frames(420))
        XCTAssertTrue(candidates.contains { $0.frame == Frames(420) && $0.kind == .playhead })
    }

    func testSnappedFrameCombinesRoundingAndSnapping() throws {
        var f = Fixture(seconds: 100)
        try f.addClip(start: 100, duration: 100)
        let g = TimelineGeometry(pointsPerFrame: 4, snapTolerance: 10)
        let candidates = g.snapCandidates(in: f.project.timeline)
        // x = 406 bodů → snímek 102 (zaokrouhleno) → přichyceno na hranu 100
        XCTAssertEqual(g.snappedFrame(atX: 406, candidates: candidates), Frames(100))
    }

    func testSnapWithNoCandidatesReturnsInput() {
        let g = TimelineGeometry()
        XCTAssertEqual(g.snap(Frames(42), to: []).frame, Frames(42))
    }

    // MARK: Rozsah obsahu

    func testContentWidthLeavesTrailingRoom() throws {
        var f = Fixture(seconds: 100)
        try f.addClip(start: 0, duration: 300)
        let g = TimelineGeometry(pointsPerFrame: 2)
        XCTAssertEqual(g.contentWidth(of: f.project, trailingFrames: Frames(100)), 800)
    }
}
