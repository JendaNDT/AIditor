import XCTest
@testable import TimelineModel

/// Popisky pravítka. Tohle je přesně ta část, která by se ve view ověřovala
/// jen okem — a poslední popisek před hranou okna si nikdo neprohlédne.
final class TimecodeTests: XCTestCase {

    // MARK: Převod

    func testZero() {
        XCTAssertEqual(Frames(0).timecode(frameRate: 30).text, "00:00:00:00")
    }

    func testFramesBelowOneSecond() {
        XCTAssertEqual(Frames(29).timecode(frameRate: 30).text, "00:00:00:29")
    }

    /// Základna je celé číslo, takže po posledním snímku sekundy následuje
    /// rovnou další sekunda. Žádné drop-frame přeskakování.
    func testSecondRollover() {
        XCTAssertEqual(Frames(30).timecode(frameRate: 30).text, "00:00:01:00")
        XCTAssertEqual(Frames(31).timecode(frameRate: 30).text, "00:00:01:01")
    }

    func testMinuteAndHourRollover() {
        XCTAssertEqual(Frames(30 * 60).timecode(frameRate: 30).text, "00:01:00:00")
        XCTAssertEqual(Frames(30 * 3600).timecode(frameRate: 30).text, "01:00:00:00")
    }

    func testCompositeValue() {
        // 1 h 23 min 45 s 12 snímků
        let total = ((1 * 3600) + (23 * 60) + 45) * 30 + 12
        XCTAssertEqual(Frames(total).timecode(frameRate: 30).text, "01:23:45:12")
    }

    /// Minuty se nesmí přelít do hodin a zůstat i v minutách.
    func testMinutesWrapAtSixty() {
        let tc = Frames(30 * 3600 + 30 * 60).timecode(frameRate: 30)
        XCTAssertEqual(tc.hours, 1)
        XCTAssertEqual(tc.minutes, 1)
    }

    func testOtherFrameRate() {
        XCTAssertEqual(Frames(24).timecode(frameRate: 24).text, "00:00:01:00")
        XCTAssertEqual(Frames(23).timecode(frameRate: 24).text, "00:00:00:23")
    }

    /// `Frames` umí být záporné (meze tažení). Radši znaménko, než `00:00:-1:-5`.
    func testNegative() {
        let tc = Frames(-31).timecode(frameRate: 30)
        XCTAssertTrue(tc.isNegative)
        XCTAssertEqual(tc.seconds, 1)
        XCTAssertEqual(tc.frames, 1)
        XCTAssertEqual(tc.text, "−00:00:01:01")
    }

    func testShortTextDropsHoursUntilNeeded() {
        XCTAssertEqual(Frames(30 * 65).timecode(frameRate: 30).shortText, "01:05:00")
        XCTAssertEqual(Frames(30 * 3600).timecode(frameRate: 30).shortText, "1:00:00:00")
    }

    // MARK: Rozteč rysek

    /// Žebřík musí být seřazený — `rulerInterval` bere první vyhovující.
    func testLadderIsAscending() {
        let ladder = TimelineGeometry.rulerIntervals(frameRate: 30)
        XCTAssertEqual(ladder, ladder.sorted())
        XCTAssertEqual(ladder.first, Frames(1))
    }

    /// Sub-sekundové hodnoty se filtrují podle základny — při 12 fps nemá
    /// smysl nabízet „15 snímků" jako zlomek sekundy.
    func testLadderFiltersSubSecondByFrameRate() {
        let ladder = TimelineGeometry.rulerIntervals(frameRate: 12)
        XCTAssertFalse(ladder.contains(Frames(15)), "15 snímků je při 12 fps víc než sekunda")
        XCTAssertTrue(ladder.contains(Frames(10)))
    }

    func testIntervalGrowsAsYouZoomOut() {
        let close = TimelineGeometry(pointsPerFrame: 40)
        let far = TimelineGeometry(pointsPerFrame: 0.5)
        let a = close.rulerInterval(frameRate: 30, minimumSpacing: 80)
        let b = far.rulerInterval(frameRate: 30, minimumSpacing: 80)
        XCTAssertLessThan(a, b)
    }

    /// Vybraná rozteč musí opravdu zabrat aspoň požadovanou šířku.
    func testChosenIntervalSatisfiesSpacing() {
        for pointsPerFrame in [0.05, 0.5, 1.0, 4.0, 20.0, 100.0] {
            let g = TimelineGeometry(pointsPerFrame: pointsPerFrame)
            let interval = g.rulerInterval(frameRate: 30, minimumSpacing: 80)
            let width = Double(interval.count) * pointsPerFrame
            XCTAssertGreaterThanOrEqual(width, 80, "při \(pointsPerFrame) bodech na snímek")
        }
    }

    /// Při extrémním odzoomování žebřík dojde. Vrátit se má největší, ne nic.
    ///
    /// Práh musí být opravdu nedosažitelný: největší rozteč je 10 hodin,
    /// což při nejmenším zoomu dělá 21 600 bodů. S 10 000 by ještě vyhověla
    /// pětihodinová a záložní větev by se nespustila — první verze testu
    /// tímhle procházela, aniž by testovala, co měla.
    func testFallsBackToLargestInterval() {
        let g = TimelineGeometry(pointsPerFrame: TimelineGeometry.minPointsPerFrame)
        let largest = TimelineGeometry.rulerIntervals(frameRate: 30).last!
        let unreachable = Double(largest.count) * g.pointsPerFrame + 1
        XCTAssertEqual(g.rulerInterval(frameRate: 30, minimumSpacing: unreachable), largest)
    }

    // MARK: Které snímky popsat

    /// ⚠️ Jádro věci: popisky stojí na NÁSOBCÍCH rozteče, ne na začátku
    /// viditelného rozsahu. Jinak by při scrollování jely s obsahem.
    func testFramesAreMultiplesNotRangeStart() {
        let g = TimelineGeometry()
        let frames = g.rulerFrames(in: Frames(7)..<Frames(31), interval: Frames(10))
        XCTAssertEqual(frames, [Frames(10), Frames(20), Frames(30)])
    }

    func testLowerBoundOnMultipleIsIncluded() {
        let g = TimelineGeometry()
        let frames = g.rulerFrames(in: Frames(10)..<Frames(31), interval: Frames(10))
        XCTAssertEqual(frames.first, Frames(10))
    }

    /// Horní mez je výlučná — jinak by se popisek kreslil o snímek za oknem.
    func testUpperBoundIsExclusive() {
        let g = TimelineGeometry()
        let frames = g.rulerFrames(in: Frames(0)..<Frames(30), interval: Frames(10))
        XCTAssertEqual(frames, [Frames(0), Frames(10), Frames(20)])
    }

    func testNegativeRange() {
        let g = TimelineGeometry()
        let frames = g.rulerFrames(in: Frames(-7)..<Frames(11), interval: Frames(5))
        XCTAssertEqual(frames, [Frames(-5), Frames(0), Frames(5), Frames(10)])
    }

    func testEmptyAndDegenerateInputs() {
        let g = TimelineGeometry()
        XCTAssertTrue(g.rulerFrames(in: Frames(10)..<Frames(10), interval: Frames(5)).isEmpty)
        XCTAssertTrue(g.rulerFrames(in: Frames(0)..<Frames(100), interval: Frames(0)).isEmpty)
    }

    /// Rozteč větší než okno nesmí vrátit nic navíc ani spadnout.
    func testIntervalLargerThanRange() {
        let g = TimelineGeometry()
        let frames = g.rulerFrames(in: Frames(11)..<Frames(19), interval: Frames(100))
        XCTAssertTrue(frames.isEmpty)
    }
}
