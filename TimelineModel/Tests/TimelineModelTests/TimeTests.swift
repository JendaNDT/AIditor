import XCTest
@testable import TimelineModel

/// Hranice mezi soustavami. Testy 4–8 z návrhu.
final class TimeTests: XCTestCase {

    let timeline = Timeline()   // 30 fps

    // 4.
    func testSourceTimeAndAvailableFramesAreInverse() {
        for n in [0, 1, 7, 30, 431, 5000] {
            let t = timeline.sourceTime(Frames(n))
            XCTAssertEqual(timeline.availableFrames(from: t), Frames(n))
        }
    }

    func testSourceTimeIsExactAt30fps() {
        // 90000 / 30 = 3000 ticků na snímek, nic se nezaokrouhluje
        XCTAssertEqual(timeline.sourceTime(Frames(1)),
                       SourceTime(value: 3000, timescale: 90_000))
    }

    // 5. Asset 14,517 s → 435 snímků, ne 436.
    func testAvailableFramesRoundsDown() {
        let t = SourceTime(seconds: 14.517)
        XCTAssertEqual(timeline.availableFrames(from: t), Frames(435))
    }

    func testAvailableFramesNeverOverestimates() {
        // O jeden tick míň než celý snímek musí dát o snímek míň.
        let justUnder = SourceTime(value: 3000 * 10 - 1, timescale: 90_000)
        XCTAssertEqual(timeline.availableFrames(from: justUnder), Frames(9))
    }

    func testAvailableFramesOfZeroIsZero() {
        XCTAssertEqual(timeline.availableFrames(from: .zero), .zero)
        XCTAssertEqual(timeline.availableFrames(from: SourceTime(value: -5, timescale: 90_000)), .zero)
    }

    // 6. Dvojí vložení klipu z assetu s neceločíselnou délkou dá totéž.
    func testRepeatedFullClipIsIdentical() throws {
        var f = Fixture(seconds: 14.517)
        let a = try f.project.makeClip(assetID: f.assetID)
        let b = try f.project.makeClip(assetID: f.assetID)
        XCTAssertEqual(a.duration, b.duration)
        XCTAssertEqual(a.duration, Frames(435))
    }

    // 7. Klip má vždy přesně duration.count snímků na ose, ať zdroj časuje jakkoli.
    func testClipLengthIsIndependentOfSourceFrameRate() throws {
        for fps in [29.97, 30.01, 59.68, 120.0] {
            var p = Project.empty()
            let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/a.mov"),
                              duration: SourceTime(seconds: 10),
                              measuredFrameRate: fps)
            p.addAsset(asset)
            let clip = try p.makeClip(assetID: asset.id)
            XCTAssertEqual(clip.duration, Frames(300),
                           "zdroj \(fps) fps: délka na ose se musí řídit základnou projektu")
        }
    }

    // 8.
    func testAvailableFramesIsALowerBound() {
        // 0,999 snímku nesmí vyjít jako celý snímek
        let t = SourceTime(value: 2999, timescale: 90_000)
        XCTAssertEqual(timeline.availableFrames(from: t), .zero)
    }

    // MARK: SourceTime aritmetika

    func testSourceTimeAddsAcrossTimescales() {
        let a = SourceTime(value: 1, timescale: 2)      // 0,5 s
        let b = SourceTime(value: 1, timescale: 4)      // 0,25 s
        XCTAssertEqual((a + b).seconds, 0.75, accuracy: 1e-9)
    }

    func testSourceTimeComparesAcrossTimescales() {
        XCTAssertEqual(SourceTime(value: 1, timescale: 2), SourceTime(value: 2, timescale: 4))
        XCTAssertLessThan(SourceTime(value: 1, timescale: 4), SourceTime(value: 1, timescale: 2))
    }

    func testSourceTimeHashMatchesEquality() {
        let a = SourceTime(value: 1, timescale: 2)
        let b = SourceTime(value: 45000, timescale: 90_000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: Kódování

    func testFramesEncodesAsBareNumber() throws {
        let data = try JSONEncoder().encode(["x": Frames(42)])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(json, #"{"x":42}"#)
    }

    func testProjectRoundTripsThroughJSON() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        let data = try JSONEncoder().encode(f.project)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back, f.project)
    }

    /// Assety se kódují jako pole objektů, ne jako plochý seznam
    /// střídajících se klíčů a hodnot (což by udělal slovník s ne-String klíčem).
    func testAssetsEncodeAsArrayOfObjects() throws {
        let f = Fixture()
        let data = try JSONEncoder().encode(f.project)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["assets"] as? [[String: Any]])
    }
}
