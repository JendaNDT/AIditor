import XCTest
@testable import TimelineModel

/// Trim, slip, roll. Testy 30–41 a 49–53 z návrhu.
/// Tady bydlí off-by-one chyby, takže se hranice testují z obou stran.
final class TrimTests: XCTestCase {

    // MARK: Trim (30–38)

    // 30. trimStart posune timelineStart I sourceStart o stejný čas.
    func testTrimStartMovesBothTimelineAndSource() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 50)
        let before = f.clip(id)!
        try f.project.trimStart(clipID: id, to: Frames(120))
        let after = f.clip(id)!

        XCTAssertEqual(after.timelineStart, Frames(120))
        XCTAssertEqual(after.duration, Frames(80))
        let expected = before.sourceStart + f.project.timeline.sourceTime(Frames(20))
        XCTAssertEqual(after.sourceStart, expected,
                       "když se posune jen jedno, klip se ve zdroji ujede")
        XCTAssertValid(f.project)
    }

    // 31.
    func testTrimEndChangesOnlyDuration() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 50)
        let before = f.clip(id)!
        try f.project.trimEnd(clipID: id, to: Frames(150))
        let after = f.clip(id)!
        XCTAssertEqual(after.timelineStart, before.timelineStart)
        XCTAssertEqual(after.sourceStart, before.sourceStart)
        XCTAssertEqual(after.duration, Frames(50))
        XCTAssertValid(f.project)
    }

    // 32.
    func testTrimToZeroLengthRejected() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) { p in
            try p.trimEnd(clipID: id, to: .zero)
        }
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) { p in
            try p.trimStart(clipID: id, to: Frames(100))
        }
    }

    // 33. + 34. Hranice zdroje z obou stran — tady bydlí off-by-one.
    func testTrimToExactEndOfSourcePasses() throws {
        // asset 10 s = 300 snímků při základně 30
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 100)
        try f.project.trimEnd(clipID: id, to: Frames(300))
        XCTAssertEqual(f.clip(id)?.duration, Frames(300))
        XCTAssertValid(f.project)
    }

    func testTrimOneFrameBeyondSourceRejected() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 100)
        do {
            try f.project.trimEnd(clipID: id, to: Frames(301))
            XCTFail("mělo hodit")
        } catch TimelineError.exceedsSourceMaterial(let available) {
            XCTAssertEqual(available, Frames(200), "zbývá 300 − 100 snímků")
        }
    }

    // 35.
    func testTrimStartLeftOfSourceStartRejected() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 0)
        XCTAssertThrowsUnchanged(&f.project,
                                 .exceedsSourceMaterial(availableFrames: .zero)) { p in
            try p.trimStart(clipID: id, to: Frames(90))
        }
    }

    func testTrimStartLeftWithinAvailableSourcePasses() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 30)
        try f.project.trimStart(clipID: id, to: Frames(80))
        XCTAssertEqual(f.clip(id)?.duration, Frames(120))
        XCTAssertValid(f.project)
    }

    // 36.
    func testExtendIntoGapPasses() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 50)
        try f.addClip(start: 200, duration: 50)
        try f.project.trimEnd(clipID: id, to: Frames(150))
        XCTAssertEqual(f.clip(id)?.duration, Frames(150))
        XCTAssertValid(f.project)
    }

    // 37.
    func testExtendIntoNeighbourRejected() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 50)
        try f.addClip(start: 100, duration: 50)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.trimEnd(clipID: id, to: Frames(120))
        }
    }

    // 38. Když narazí obojí naráz, vyhrává vždycky zdroj — pevné pořadí.
    func testSourceLimitWinsOverNeighbourLimit() throws {
        var f = Fixture(seconds: 5)      // 150 snímků materiálu
        let id = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 120, duration: 30)
        do {
            try f.project.trimEnd(clipID: id, to: Frames(400))
            XCTFail("mělo hodit")
        } catch TimelineError.exceedsSourceMaterial {
            // správně
        } catch {
            XCTFail("pořadí kontrol musí být pevné, dostal jsem \(error)")
        }
    }

    // MARK: Slip (39–40)

    // 39.
    func testSlipChangesOnlySourceStart() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 100, sourceStartFrames: 50)
        let before = f.clip(id)!
        try f.project.slip(clipID: id, by: Frames(10))
        let after = f.clip(id)!
        XCTAssertEqual(after.timelineStart, before.timelineStart)
        XCTAssertEqual(after.duration, before.duration)
        XCTAssertEqual(after.sourceStart,
                       before.sourceStart + f.project.timeline.sourceTime(Frames(10)))
        XCTAssertValid(f.project)
    }

    // 40.
    func testSlipBeyondSourceRejected() throws {
        var f = Fixture(seconds: 10)     // 300 snímků
        let id = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.slip(clipID: id, by: Frames(-1))     // před začátkem nic není
        }
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.slip(clipID: id, by: Frames(201))    // za koncem zbývá 200
        }
    }

    func testSlipRangeMatchesWhatSlipAccepts() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 100, sourceStartFrames: 30)
        let range = f.project.slipRange(clipID: id)!
        XCTAssertEqual(range.lowerBound, Frames(-30))
        XCTAssertEqual(range.upperBound, Frames(170))
        // Krajní hodnoty musí projít.
        var a = f.project
        XCTAssertNoThrow(try a.slip(clipID: id, by: range.lowerBound))
        var b = f.project
        XCTAssertNoThrow(try b.slip(clipID: id, by: range.upperBound))
    }

    // 41. VFR: zdrojový vzorek pokrývá víc snímků — trim musí použít
    // pokrývající vzorek, ne selhat. Model počítá v celých snímcích osy,
    // takže musí projít i u zdroje s nepravidelným časováním.
    func testTrimWorksWithNonIntegerSourceDuration() throws {
        var f = Fixture(seconds: 14.517)      // 435 snímků, 17 ms se zahodí
        let id = try f.addClip(start: 0, duration: 100)
        try f.project.trimEnd(clipID: id, to: Frames(435))
        XCTAssertEqual(f.clip(id)?.duration, Frames(435))
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.trimEnd(clipID: id, to: Frames(436))
        }
    }

    // MARK: Roll (49–53)

    private func makeAdjacentPair(_ f: inout Fixture) throws -> (ClipID, ClipID) {
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 150)
        return (a, b)
    }

    // 49. Posun doprava prodlouží levý a zkrátí pravý.
    func testRollRightExtendsLeftShortensRight() throws {
        var f = Fixture(seconds: 20)
        let (a, b) = try makeAdjacentPair(&f)
        try f.project.rollEdit(leftID: a, rightID: b, to: Frames(120))
        XCTAssertEqual(f.clip(a)?.duration, Frames(120))
        XCTAssertEqual(f.clip(b)?.timelineStart, Frames(120))
        XCTAssertEqual(f.clip(b)?.duration, Frames(80))
        XCTAssertValid(f.project)
    }

    // 50.
    func testRollPreservesPairDuration() throws {
        var f = Fixture(seconds: 20)
        let (a, b) = try makeAdjacentPair(&f)
        let total = f.clip(a)!.duration + f.clip(b)!.duration
        try f.project.rollEdit(leftID: a, rightID: b, to: Frames(70))
        XCTAssertEqual(f.clip(a)!.duration + f.clip(b)!.duration, total)
        XCTAssertValid(f.project)
    }

    func testRollAdjustsRightSourceStart() throws {
        var f = Fixture(seconds: 20)
        let (a, b) = try makeAdjacentPair(&f)
        let before = f.clip(b)!
        try f.project.rollEdit(leftID: a, rightID: b, to: Frames(120))
        let expected = before.sourceStart + f.project.timeline.sourceTime(Frames(20))
        XCTAssertEqual(f.clip(b)?.sourceStart, expected)
    }

    // 51. Došlý zdroj LEVÉHO klipu při rozšiřování jeho konce.
    func testRollBeyondLeftSourceRejected() throws {
        var f = Fixture(seconds: 20)     // 600 snímků
        // Levému zbývá za koncem jen 10 snímků materiálu (490 + 100 = 590 z 600).
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 490)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 0)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.rollEdit(leftID: a, rightID: b, to: Frames(120))   // chce 20, má 10
        }
        // Přesně na hranici projít musí.
        XCTAssertNoThrow(try f.project.rollEdit(leftID: a, rightID: b, to: Frames(110)))
    }

    // 52. Došlý zdroj PRAVÉHO klipu při posunu doleva.
    func testRollBeyondRightSourceRejected() throws {
        var f = Fixture(seconds: 20)
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 10)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.rollEdit(leftID: a, rightID: b, to: Frames(80))   // chce 20 zpět, má 10
        }
    }

    // 53.
    func testRollBetweenNonAdjacentRejected() throws {
        var f = Fixture(seconds: 20)
        let a = try f.addClip(start: 0, duration: 50)
        let b = try f.addClip(start: 100, duration: 50)
        XCTAssertThrowsUnchanged(&f.project, .notAdjacent(a, b)) { p in
            try p.rollEdit(leftID: a, rightID: b, to: Frames(60))
        }
    }

    // MARK: Dotazy

    func testMaxTrimEndRespectsNeighbourAndSource() throws {
        var f = Fixture(seconds: 10)     // 300 snímků
        let id = try f.addClip(start: 0, duration: 50)
        try f.addClip(start: 100, duration: 50)
        XCTAssertEqual(f.project.maxTrimEnd(clipID: id), Frames(100), "soused je blíž než konec zdroje")
    }

    func testMaxTrimStartRespectsSource() throws {
        var f = Fixture()
        let id = try f.addClip(start: 100, duration: 50, sourceStartFrames: 20)
        XCTAssertEqual(f.project.maxTrimStart(clipID: id), Frames(80))
    }
}
