import XCTest
@testable import TimelineModel

/// Tažení: co se stane mezi stiskem a puštěním. Tohle by se jinak dalo
/// ověřit jen myší na běžící aplikaci.
final class InteractionTests: XCTestCase {

    private func setup(pointsPerFrame: Double = 4) throws -> (Fixture, TimelineInteraction, ClipID) {
        var f = Fixture(seconds: 100)
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 50)
        let g = TimelineGeometry(pointsPerFrame: pointsPerFrame, snapTolerance: 10)
        return (f, TimelineInteraction(geometry: g), id)
    }

    // MARK: Určení druhu tažení

    func testBodyHitStartsMove() throws {
        var (f, i, id) = try setup()
        let hit = i.geometry.hitTest(x: i.geometry.x(for: Frames(150)), y: 10, in: f.project.timeline)!
        i.begin(hit: hit, in: f.project)
        XCTAssertEqual(i.drag?.kind, .move)
        XCTAssertEqual(i.drag?.clipID, id)
        XCTAssertTrue(i.isDragging)
    }

    func testEdgeHitStartsTrim() throws {
        var (f, i, _) = try setup()
        let startX = i.geometry.x(for: Frames(100))
        let hit = i.geometry.hitTest(x: startX + 1, y: 10, in: f.project.timeline)!
        i.begin(hit: hit, in: f.project)
        XCTAssertEqual(i.drag?.kind, .trimStart)
    }

    /// Roll bez souseda nemá co posouvat — musí spadnout zpátky na trim,
    /// ne se pokusit o nemožné.
    func testRollWithoutNeighbourFallsBackToTrim() throws {
        var (f, i, _) = try setup()
        let endX = i.geometry.x(for: Frames(200))
        let hit = i.geometry.hitTest(x: endX - 1, y: 10, in: f.project.timeline)!
        i.begin(hit: hit, in: f.project, forcing: .roll)
        XCTAssertEqual(i.drag?.kind, .trimEnd)
        XCTAssertNil(i.drag?.partnerID)
    }

    func testRollWithNeighbourKeepsRoll() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 200)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        let hit = TimelineHit(clipID: a, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100))
        i.begin(hit: hit, in: f.project, forcing: .roll)
        XCTAssertEqual(i.drag?.kind, .roll)
        XCTAssertEqual(i.drag?.partnerID, b)
    }

    // MARK: Tažení klipu

    /// Klip musí držet tam, kde se chytil — nesmí skočit počátkem pod kurzor.
    func testMoveKeepsGrabOffset() throws {
        var (f, i, id) = try setup()
        // Chytneme klip 30 snímků od začátku.
        let hit = TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: Frames(30))
        i.begin(hit: hit, in: f.project)
        // Myš na snímku 530 → začátek klipu na 500.
        let p = i.preview(atX: i.geometry.x(for: Frames(530)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.start, Frames(500))
        XCTAssertEqual(p?.duration, Frames(100))
    }

    func testMoveClampsAtOrigin() throws {
        var (f, i, id) = try setup()
        let hit = TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: Frames(30))
        i.begin(hit: hit, in: f.project)
        let p = i.preview(atX: 0, y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.start, .zero, "před nulou osa není")
    }

    func testMoveOntoOccupiedSpaceIsInvalid() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 200, duration: 100)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let p = i.preview(atX: i.geometry.x(for: Frames(250)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.isValid, false, "view to má nakreslit jako neplatné")
    }

    func testMoveToOtherTrackReportsTargetTrack() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        // y = 70 je A1
        let p = i.preview(atX: i.geometry.x(for: Frames(400)), y: 70, in: f.project, snapping: false)
        XCTAssertEqual(p?.trackID, f.a1)
        XCTAssertEqual(p?.isValid, true)
    }

    func testMoveOfVideoOntoAudioTrackIsInvalid() throws {
        var f = Fixture(seconds: 100, hasVideo: true, hasAudio: false)
        let id = try f.addClip(start: 0, duration: 100)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let p = i.preview(atX: 400, y: 70, in: f.project, snapping: false)
        XCTAssertEqual(p?.isValid, false)
    }

    // MARK: Přichytávání při tažení

    /// Přichytává se začátek i konec klipu, ne jen bod pod myší.
    func testMoveSnapsByClipEnd() throws {
        var f = Fixture(seconds: 100)
        let dragged = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 500, duration: 100)
        var i = TimelineInteraction(geometry: TimelineGeometry(pointsPerFrame: 4, snapTolerance: 12))
        i.begin(hit: TimelineHit(clipID: dragged, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        // Začátek na 398 → konec na 498, dva snímky (8 bodů) od hrany 500.
        let p = i.preview(atX: i.geometry.x(for: Frames(398)), y: 10, in: f.project)
        XCTAssertEqual(p?.start, Frames(400), "konec klipu se má přichytit na 500")
        XCTAssertEqual(p?.snappedTo?.frame, Frames(500))
    }

    func testSnappingCanBeTurnedOff() throws {
        var f = Fixture(seconds: 100)
        let dragged = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 500, duration: 100)
        var i = TimelineInteraction(geometry: TimelineGeometry(pointsPerFrame: 4, snapTolerance: 12))
        i.begin(hit: TimelineHit(clipID: dragged, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let p = i.preview(atX: i.geometry.x(for: Frames(398)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.start, Frames(398))
        XCTAssertNil(p?.snappedTo)
    }

    func testDraggedClipDoesNotSnapToItself() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        // Klip je na 100..200; kdyby se přichytával na vlastní hrany,
        // zasekl by se na místě.
        let p = i.preview(atX: i.geometry.x(for: Frames(101)), y: 10, in: f.project)
        XCTAssertNotEqual(p?.snappedTo?.frame, Frames(100))
    }

    // MARK: Trim s mezemi

    func testTrimEndStopsAtNeighbour() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 150, duration: 100)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100)),
                in: f.project)
        let p = i.preview(atX: i.geometry.x(for: Frames(400)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p!.start + p!.duration, Frames(150), "tažení se zarazí u souseda")
    }

    func testTrimEndStopsAtEndOfSource() throws {
        var f = Fixture(seconds: 10)        // 300 snímků
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100)),
                in: f.project)
        let p = i.preview(atX: i.geometry.x(for: Frames(9999)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p!.start + p!.duration, Frames(300), "dál materiál není")
    }

    func testTrimStartCannotCrossOwnEnd() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .leadingEdge, offsetInClip: .zero),
                in: f.project)
        let p = i.preview(atX: i.geometry.x(for: Frames(9999)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.duration, Frames(1), "nejmíň jeden snímek musí zůstat")
    }

    // MARK: Roll

    func testRollPreviewMovesBothClips() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 200)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100)),
                in: f.project, forcing: .roll)

        let p = i.preview(atX: i.geometry.x(for: Frames(130)), y: 10, in: f.project, snapping: false)
        XCTAssertEqual(p?.duration, Frames(130), "levý se prodlouží")
        XCTAssertEqual(p?.partner?.clipID, b)
        XCTAssertEqual(p?.partner?.start, Frames(130))
        XCTAssertEqual(p?.partner?.duration, Frames(70), "pravý se o tolik zkrátí")
    }

    // MARK: Commit

    func testCommitMoveAppliesToModel() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let moved = try i.commit(atX: i.geometry.x(for: Frames(400)), y: 10,
                                 into: &f.project, snapping: false)
        XCTAssertTrue(moved)
        XCTAssertEqual(f.clip(id)?.timelineStart, Frames(400))
        XCTAssertFalse(i.isDragging)
        XCTAssertValid(f.project)
    }

    /// Puštění na stejném místě nesmí vyrobit změnu — jinak by vznikl
    /// prázdný undo krok a Cmd+Z by zdánlivě nic neudělalo.
    func testCommitWithoutMovementChangesNothing() throws {
        var (f, i, id) = try setup()
        let before = f.project
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let changed = try i.commit(atX: i.geometry.x(for: Frames(100)), y: 10,
                                   into: &f.project, snapping: false)
        XCTAssertFalse(changed)
        XCTAssertEqual(f.project, before)
    }

    func testCommitOfInvalidMoveDoesNothing() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 200, duration: 100)
        let before = f.project
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let changed = try i.commit(atX: i.geometry.x(for: Frames(250)), y: 10,
                                   into: &f.project, snapping: false)
        XCTAssertFalse(changed)
        XCTAssertEqual(f.project, before)
    }

    func testCommitTrimEndAppliesToModel() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100)),
                in: f.project)
        try i.commit(atX: i.geometry.x(for: Frames(160)), y: 10, into: &f.project, snapping: false)
        XCTAssertEqual(f.clip(id)?.timelineEnd, Frames(160))
        XCTAssertValid(f.project)
    }

    func testCommitRollAppliesToBothClips() throws {
        var f = Fixture(seconds: 100)
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 200)
        var i = TimelineInteraction(geometry: TimelineGeometry())
        i.begin(hit: TimelineHit(clipID: a, trackID: f.v1, zone: .trailingEdge, offsetInClip: Frames(100)),
                in: f.project, forcing: .roll)
        try i.commit(atX: i.geometry.x(for: Frames(130)), y: 10, into: &f.project, snapping: false)

        XCTAssertEqual(f.clip(a)?.duration, Frames(130))
        XCTAssertEqual(f.clip(b)?.timelineStart, Frames(130))
        XCTAssertEqual(f.clip(b)?.duration, Frames(70))
        XCTAssertValid(f.project)
    }

    func testCommitSlipChangesSourceOnly() throws {
        var (f, i, id) = try setup()
        let before = f.clip(id)!
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project, forcing: .slip)
        try i.commit(atX: i.geometry.x(for: Frames(120)), y: 10, into: &f.project, snapping: false)

        let after = f.clip(id)!
        XCTAssertEqual(after.timelineStart, before.timelineStart)
        XCTAssertEqual(after.duration, before.duration)
        XCTAssertNotEqual(after.sourceStart, before.sourceStart)
        XCTAssertValid(f.project)
    }

    // MARK: Zrušení

    func testCancelLeavesModelUntouched() throws {
        var (f, i, id) = try setup()
        let before = f.project
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        _ = i.preview(atX: 2000, y: 10, in: f.project)
        i.cancel()
        XCTAssertFalse(i.isDragging)
        XCTAssertEqual(f.project, before, "během tažení se do modelu nezapisuje")
    }

    func testPreviewWithoutDragIsNil() throws {
        var (f, i, _) = try setup()
        XCTAssertNil(i.preview(atX: 100, y: 10, in: f.project))
    }

    /// Náhled se během tažení volá při každém pohybu myši, takže nesmí
    /// model měnit ani omylem.
    func testPreviewIsPure() throws {
        var (f, i, id) = try setup()
        i.begin(hit: TimelineHit(clipID: id, trackID: f.v1, zone: .body, offsetInClip: .zero),
                in: f.project)
        let before = f.project
        for x in stride(from: 0.0, to: 2000.0, by: 37) {
            _ = i.preview(atX: x, y: 10, in: f.project)
        }
        XCTAssertEqual(f.project, before)
    }
}
