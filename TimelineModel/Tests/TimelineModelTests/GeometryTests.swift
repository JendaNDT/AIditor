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
        let p = Project.empty()          // V1 (64) + A1 (44) + A2 (44) + T1 (28), mezera 2
        let g = TimelineGeometry()
        XCTAssertEqual(g.y(ofTrackAt: 0, in: p.timeline), 0)
        XCTAssertEqual(g.y(ofTrackAt: 1, in: p.timeline), 66)
        XCTAssertEqual(g.y(ofTrackAt: 2, in: p.timeline), 112)
        XCTAssertEqual(g.y(ofTrackAt: 3, in: p.timeline), 158)
        XCTAssertEqual(g.totalHeight(of: p.timeline), 186, "bez koncové mezery")
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

    // MARK: Osa sleduje hlavu (fáze 17)

    /// Hlava uprostřed okna se scrollem nehýbe. Tohle je ta podstatná
    /// vlastnost: mezi skoky osa STOJÍ.
    func testFollowDoesNothingWhilePlayheadIsVisible() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        for frame in [Frames(30), Frames(60), Frames(100)] {          // 120–400 bodů
            XCTAssertNil(g.scrollToKeep(playhead: frame, scrollX: 0,
                                        viewportWidth: 800, maxScrollX: 10_000),
                         "hlava na \(frame.count) je vidět, scroll se nesahá")
        }
    }

    /// Vyjetí vpravo = skok o stránku tak, aby hlava dosedla do levé třetiny.
    func testFollowJumpsSoPlayheadLandsInLeadingThird() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        // Hlava na 900 bodů, okno 0–800 → je za pravou hranou.
        let target = g.scrollToKeep(playhead: Frames(225), scrollX: 0,
                                    viewportWidth: 800, maxScrollX: 10_000)
        // 900 − 800/3 = 633,33
        XCTAssertEqual(try XCTUnwrap(target), 900 - 800.0 / 3, accuracy: 0.001)
        // A po skoku už je hlava v klidové zóně — jinak by se skákalo pořád.
        XCTAssertNil(g.scrollToKeep(playhead: Frames(225), scrollX: try XCTUnwrap(target),
                                    viewportWidth: 800, maxScrollX: 10_000))
    }

    /// Rezerva u hrany: skok přijde JEŠTĚ než hlava zmizí za okrajem.
    /// Bez ní by se hlava při přehrávání ztrácela do hrany okna.
    func testFollowTriggersBeforePlayheadReachesEdge() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        // Okno 0–800, rezerva 16 → spouštěč na 784 bodů = snímek 196.
        XCTAssertNil(g.scrollToKeep(playhead: Frames(196), scrollX: 0,
                                    viewportWidth: 800, maxScrollX: 10_000),
                     "přesně na hranici rezervy se ještě nescrolluje")
        XCTAssertNotNil(g.scrollToKeep(playhead: Frames(197), scrollX: 0,
                                       viewportWidth: 800, maxScrollX: 10_000))
    }

    /// Vyjetí VLEVO (skok zpět, přehrávání pozpátku) položí hlavu do pravé
    /// třetiny — proti směru pohybu. Kdyby dosedla vlevo, další snímek
    /// pozpátku by ji hned zase vystrčil a osa by skákala po snímcích.
    func testFollowBackwardsLandsInTrailingThird() throws {
        let g = TimelineGeometry(pointsPerFrame: 4)
        // Okno 2000–2800, hlava na 1600 bodů (snímek 400) → před oknem.
        let target = try XCTUnwrap(g.scrollToKeep(playhead: Frames(400), scrollX: 2000,
                                                  viewportWidth: 800, maxScrollX: 10_000))
        XCTAssertEqual(target, 1600 - 800.0 * 2 / 3, accuracy: 0.001)
        XCTAssertNil(g.scrollToKeep(playhead: Frames(400), scrollX: target,
                                    viewportWidth: 800, maxScrollX: 10_000))
    }

    /// Cíl se ořezává na rozsah scrollu — a když z ořezu vyjde tam, kde
    /// stojíme, vrací se `nil` místo scrollu o nula bodů.
    func testFollowClampsToScrollRange() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        // Na začátku osy: hlava na snímku 2 (8 bodů), okno posunuté na 100.
        // Cíl by byl záporný → ořez na 0.
        XCTAssertEqual(g.scrollToKeep(playhead: Frames(2), scrollX: 100,
                                      viewportWidth: 800, maxScrollX: 10_000), 0)
        // Už stojíme na nule a hlava je vlevo mimo (nedosažitelná) → nic.
        XCTAssertNil(g.scrollToKeep(playhead: Frames(-10), scrollX: 0,
                                    viewportWidth: 800, maxScrollX: 10_000))
        // Konec osy: cíl za maximem se ořízne a víc už se scrollovat nedá.
        XCTAssertEqual(g.scrollToKeep(playhead: Frames(1000), scrollX: 500,
                                      viewportWidth: 800, maxScrollX: 600), 600)
        XCTAssertNil(g.scrollToKeep(playhead: Frames(1000), scrollX: 600,
                                    viewportWidth: 800, maxScrollX: 600),
                     "dál to nejde — hlava zůstane za hranou, ale scroll se netrhá")
    }

    /// Zoom mění, kolik snímků se do okna vejde — funkce počítá v BODECH,
    /// takže při jiném `pointsPerFrame` vychází jiný spouštěč i cíl.
    func testFollowRespectsZoom() throws {
        let far = TimelineGeometry(pointsPerFrame: 0.5)
        XCTAssertNil(far.scrollToKeep(playhead: Frames(1000), scrollX: 0,
                                      viewportWidth: 800, maxScrollX: 10_000),
                     "odzoomováno se snímek 1000 do okna vejde")
        let close = TimelineGeometry(pointsPerFrame: 20)
        let target = try XCTUnwrap(close.scrollToKeep(playhead: Frames(1000), scrollX: 0,
                                                      viewportWidth: 800, maxScrollX: 100_000))
        XCTAssertEqual(target, 20_000 - 800.0 / 3, accuracy: 0.001)
    }

    /// Degenerované vstupy nesmějí nic vrátit: nulové okno (osa ještě nemá
    /// rozměr) ani nulový zoom.
    func testFollowIgnoresDegenerateViewport() {
        let g = TimelineGeometry(pointsPerFrame: 4)
        XCTAssertNil(g.scrollToKeep(playhead: Frames(500), scrollX: 0,
                                    viewportWidth: 0, maxScrollX: 10_000))
        var zero = g
        zero.pointsPerFrame = 0
        XCTAssertNil(zero.scrollToKeep(playhead: Frames(500), scrollX: 0,
                                       viewportWidth: 800, maxScrollX: 10_000))
    }
}
