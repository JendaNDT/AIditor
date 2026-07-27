import XCTest
@testable import TimelineModel

/// Krok 4 fáze 2: `TimelineLayout.placements` a `TimelineLayout.diff`.
///
/// Chyby recyklace jsou množinové (klip visí po smazání, dva klipy na jedné
/// vrstvě, vrstva se po zoomu nepřepočítá) — proto se tu vymáhají záruky nad
/// množinami, ne obrázky.
final class LayoutTests: XCTestCase {

    // Výchozí geometrie: 4 body na snímek, V1 vysoká 64, zvuk 44, mezera 2.
    private let geometry = TimelineGeometry()

    // MARK: - Placements: kde klip leží

    func testEmptyProjectHasNoPlacements() {
        let f = Fixture()
        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)
        XCTAssertEqual(placements, [])
    }

    func testPlacementGeometryMatchesClip() throws {
        var f = Fixture()
        let id = try f.addClip(start: 30, duration: 60)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)

        XCTAssertEqual(placements.count, 1)
        let p = try XCTUnwrap(placements.first)
        XCTAssertEqual(p.clipID, id)
        XCTAssertEqual(p.trackID, f.v1)
        XCTAssertEqual(p.x, 120)          // 30 snímků × 4 body
        XCTAssertEqual(p.y, 0)            // V1 je první stopa
        XCTAssertEqual(p.width, 240)      // 60 snímků × 4 body
        XCTAssertEqual(p.height, 64)      // výška obrazové stopy
        XCTAssertFalse(p.isSelected)
    }

    func testAudioTrackPlacementUsesTrackOffsetAndHeight() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 60, on: f.a1)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)

        let p = try XCTUnwrap(placements.first)
        XCTAssertEqual(p.y, 66)           // 64 (V1) + 2 (mezera)
        XCTAssertEqual(p.height, 44)      // výška zvukové stopy
    }

    func testSelectionFlagIsSetOnlyForSelectedClips() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 30)
        let b = try f.addClip(start: 30, duration: 30)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800,
                                                   selection: [b])

        XCTAssertEqual(placements.map(\.isSelected),
                       placements.map { $0.clipID == b })
        XCTAssertTrue(placements.contains { $0.clipID == a && !$0.isSelected })
    }

    func testWidthScalesWithZoom() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 60)
        var zoomed = geometry
        zoomed.setZoom(8)

        let p = TimelineLayout.placements(project: f.project, geometry: zoomed,
                                          scrollX: 0, width: 800)
        XCTAssertEqual(p.first?.width, 480)   // 60 snímků × 8 bodů
    }

    // MARK: - Placements: co je vidět

    func testClipBeyondWindowAndOverscanIsExcluded() throws {
        var f = Fixture()
        // Okno 800 bodů + overscan 200 = 1000 bodů = 250 snímků.
        try f.addClip(start: 260, duration: 30)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)
        XCTAssertEqual(placements, [])
    }

    func testClipInsideOverscanIsIncluded() throws {
        var f = Fixture()
        // Začíná za pravou hranou okna (200 snímků), ale uvnitř overscanu.
        try f.addClip(start: 210, duration: 30)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)
        XCTAssertEqual(placements.count, 1)
    }

    func testScrolledPastClipIsExcluded() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 30)   // končí na x = 120

        // Scroll daleko za klip: 120 + overscan 200 < 400.
        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 400, width: 800)
        XCTAssertEqual(placements, [])
    }

    func testClipPartiallyVisibleAtLeftEdgeIsIncluded() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 200)  // 800 bodů

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 700, width: 800)
        XCTAssertEqual(placements.count, 1)
        // Rámec se NEořezává na okno — vrstva leží v dokumentu, ořez dělá clip view.
        XCTAssertEqual(placements.first?.x, 0)
        XCTAssertEqual(placements.first?.width, 800)
    }

    func testZeroWidthWindowHasNoPlacements() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 30)
        XCTAssertEqual(TimelineLayout.placements(project: f.project, geometry: geometry,
                                                 scrollX: 0, width: 0), [])
    }

    func testOrderIsTracksTopToBottomThenClipsLeftToRight() throws {
        var f = Fixture()
        let v = try f.addClip(start: 60, duration: 30)
        let vEarlier = try f.addClip(start: 0, duration: 30)
        let a = try f.addClip(start: 30, duration: 30, on: f.a1)

        let placements = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: 0, width: 800)
        XCTAssertEqual(placements.map(\.clipID), [vEarlier, v, a])
    }

    // MARK: - Diff: základní přechody

    func testInitialDiffMountsEverything() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 30)
        let b = try f.addClip(start: 30, duration: 30)

        let next = TimelineLayout.placements(project: f.project, geometry: geometry,
                                             scrollX: 0, width: 800)
        let diff = TimelineLayout.diff(previous: [], next: next)

        XCTAssertEqual(diff.toMount, [a, b])
        XCTAssertEqual(diff.toRecycle, [])
        XCTAssertEqual(diff.toUpdate, [])
        XCTAssertFalse(diff.isEmpty)
    }

    func testStayingClipsGoToUpdateNotMount() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 30)

        let next = TimelineLayout.placements(project: f.project, geometry: geometry,
                                             scrollX: 0, width: 800)
        let diff = TimelineLayout.diff(previous: [a], next: next)

        XCTAssertEqual(diff.toMount, [])
        XCTAssertEqual(diff.toRecycle, [])
        XCTAssertEqual(diff.toUpdate, [a])
    }

    func testGoneClipIsRecycled() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 30)
        let ghost = ClipID()    // visel dřív, teď už v projektu není

        let next = TimelineLayout.placements(project: f.project, geometry: geometry,
                                             scrollX: 0, width: 800)
        let diff = TimelineLayout.diff(previous: [a, ghost], next: next)

        XCTAssertEqual(diff.toMount, [])
        XCTAssertEqual(diff.toRecycle, [ghost])
        XCTAssertEqual(diff.toUpdate, [a])
    }

    func testEmptyToEmptyDiffIsEmpty() {
        let diff = TimelineLayout.diff(previous: [], next: [])
        XCTAssertTrue(diff.isEmpty)
    }

    /// Scroll doprava: levý klip odjede (recyklace), pravý přijede (mount),
    /// prostřední zůstane (update). Přesně scénář, kvůli kterému diff existuje.
    func testScrollTransitionSplitsIntoAllThreeBuckets() throws {
        var f = Fixture(seconds: 60)
        let left = try f.addClip(start: 0, duration: 30)          // 0–120 bodů
        let middle = try f.addClip(start: 240, duration: 30)      // 960–1080
        let right = try f.addClip(start: 500, duration: 30)       // 2000–2120

        let before = TimelineLayout.placements(project: f.project, geometry: geometry,
                                               scrollX: 0, width: 1200)
        XCTAssertEqual(before.map(\.clipID), [left, middle])

        let after = TimelineLayout.placements(project: f.project, geometry: geometry,
                                              scrollX: 900, width: 1200)
        let diff = TimelineLayout.diff(previous: Set(before.map(\.clipID)), next: after)

        XCTAssertEqual(diff.toMount, [right])
        XCTAssertEqual(diff.toRecycle, [left])
        XCTAssertEqual(diff.toUpdate, [middle])
    }

    // MARK: - Diff: záruky, na kterých stojí view

    func testRecycleOrderIsDeterministic() {
        // Množina nemá pořadí — výstup ho mít MUSÍ, jinak stejný vstup dává
        // různé výsledky a nedá se na tom stavět.
        let ids = (0..<20).map { ClipID(rawValue: String(format: "%02d", $0)) }
        let diff = TimelineLayout.diff(previous: Set(ids), next: [])
        XCTAssertEqual(diff.toRecycle, ids)
    }

    func testDuplicatePlacementIDsAreNotMountedTwice() {
        // Model duplicitní ID invarianty nepustí; diff na tom ale nesmí
        // stavět mlčky — dva mounty téhož ID = dva klipy na jedné vrstvě.
        let id = ClipID()
        let track = TrackID()
        let p = TimelineLayout.Placement(clipID: id, trackID: track,
                                         x: 0, y: 0, width: 10, height: 10,
                                         isSelected: false)
        let diff = TimelineLayout.diff(previous: [], next: [p, p])
        XCTAssertEqual(diff.toMount, [id])
    }

    /// Property test: pro náhodné projekty a náhodná okna platí množinové
    /// záruky diffu. Semínko je v názvu chyby, aby šel červený běh zopakovat.
    func testDiffSetGuaranteesHoldForRandomWindows() throws {
        var rng = SeededRandom(seed: 0xC0FFEE)

        for round in 0..<50 {
            var f = Fixture(seconds: 120)
            var start = 0
            for _ in 0..<Int.random(in: 0...12, using: &rng) {
                let gap = Int.random(in: 0...40, using: &rng)
                let duration = Int.random(in: 1...90, using: &rng)
                try f.addClip(start: start + gap, duration: duration,
                              on: Bool.random(using: &rng) ? f.v1 : f.a1)
                start += gap + duration
            }

            let scrollA = Double.random(in: 0...4000, using: &rng)
            let scrollB = Double.random(in: 0...4000, using: &rng)
            let width = Double.random(in: 100...2000, using: &rng)

            let before = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                   scrollX: scrollA, width: width)
            let after = TimelineLayout.placements(project: f.project, geometry: geometry,
                                                  scrollX: scrollB, width: width)

            let previous = Set(before.map(\.clipID))
            let diff = TimelineLayout.diff(previous: previous, next: after)

            let nextIDs = after.map(\.clipID)
            let message = "kolo \(round), seed \(rng.seed)"

            // mount ∪ update = přesně next, v pořadí next.
            XCTAssertEqual(Set(diff.toMount + diff.toUpdate), Set(nextIDs), message)
            XCTAssertEqual(diff.toMount.count + diff.toUpdate.count, nextIDs.count, message)
            // recycle = previous − next.
            XCTAssertEqual(Set(diff.toRecycle), previous.subtracting(nextIDs), message)
            // Nic není ve dvou seznamech.
            XCTAssertTrue(Set(diff.toMount).isDisjoint(with: diff.toRecycle), message)
            XCTAssertTrue(Set(diff.toMount).isDisjoint(with: diff.toUpdate), message)
            XCTAssertTrue(Set(diff.toUpdate).isDisjoint(with: diff.toRecycle), message)
            // Mount jen to, co neviselo; update jen to, co viselo.
            XCTAssertTrue(previous.isDisjoint(with: diff.toMount), message)
            XCTAssertTrue(Set(diff.toUpdate).isSubset(of: previous), message)
        }
    }
}
