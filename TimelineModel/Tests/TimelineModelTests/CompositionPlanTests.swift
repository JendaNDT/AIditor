import XCTest
@testable import TimelineModel

/// Plán A/B rozkladu stopy pro kompozici s přechody (fáze 10, modul 2).
final class CompositionPlanTests: XCTestCase {

    /// Dva sousedi na V1: L = [0, 100) od snímku 0, R = [100, 200) od 120.
    private func makeCut() throws -> (fx: Fixture, left: ClipID, right: ClipID) {
        var fx = Fixture()
        let l = try fx.addClip(start: 0, duration: 100)
        let r = try fx.addClip(start: 100, duration: 100, sourceStartFrames: 120)
        return (fx, l, r)
    }

    func testBezPrechoduJeJednaDrahaAVkladyZrcadliKlipy() throws {
        let (fx, l, r) = try makeCut()
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        XCTAssertEqual(plan.laneCount, 1)
        XCTAssertTrue(plan.overlays.isEmpty)
        XCTAssertEqual(plan.placements.map(\.clipID), [l, r])
        XCTAssertEqual(plan.placements.map(\.lane), [0, 0])
        XCTAssertEqual(plan.placements[0].start, Frames(0))
        XCTAssertEqual(plan.placements[0].duration, Frames(100))
        XCTAssertEqual(plan.placements[1].start, Frames(100))
        XCTAssertEqual(plan.placements[1].sourceStart,
                       fx.project.timeline.sourceTime(Frames(120)))
    }

    func testProlinackaProdlouziVkladyANastupujeNaDrahuB() throws {
        var (fx, l, r) = try makeCut()
        let id = try fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                              betweenLeft: l, andRight: r)
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        XCTAssertEqual(plan.laneCount, 2)

        // Levý: [0, 115) — rameno 15 za střih; zdroj jede dál 1:1.
        let left = plan.placements[0]
        XCTAssertEqual(left.lane, 0)
        XCTAssertEqual(left.start, Frames(0))
        XCTAssertEqual(left.duration, Frames(115))
        XCTAssertEqual(left.sourceStart, fx.project.timeline.sourceTime(Frames(0)))
        XCTAssertEqual(left.sourceDuration, fx.project.timeline.sourceTime(Frames(115)))

        // Pravý: nastupuje už na 85 a zdroj má posunutý ZPĚT o 15.
        let right = plan.placements[1]
        XCTAssertEqual(right.lane, 1)
        XCTAssertEqual(right.start, Frames(85))
        XCTAssertEqual(right.duration, Frames(115))
        XCTAssertEqual(right.sourceStart, fx.project.timeline.sourceTime(Frames(105)))

        // Předpis přechodu: oblast [85, 115), střih 100, dráhy 0 → 1.
        XCTAssertEqual(plan.overlays.count, 1)
        let o = plan.overlays[0]
        XCTAssertEqual(o.transitionID, id)
        XCTAssertEqual(o.start, Frames(85))
        XCTAssertEqual(o.cut, Frames(100))
        XCTAssertEqual(o.end, Frames(115))
        XCTAssertEqual(o.outgoingLane, 0)
        XCTAssertEqual(o.incomingLane, 1)
    }

    func testZatmivackaNechavaJednuDrahuBezRamen() throws {
        var (fx, l, r) = try makeCut()
        try fx.project.setTransition(.dipToBlack, duration: Frames(20),
                                     betweenLeft: l, andRight: r)
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        XCTAssertEqual(plan.laneCount, 1)
        XCTAssertEqual(plan.placements.map(\.lane), [0, 0])
        XCTAssertEqual(plan.placements[0].duration, Frames(100))
        XCTAssertEqual(plan.placements[1].start, Frames(100))
        XCTAssertEqual(plan.overlays.count, 1)
        XCTAssertEqual(plan.overlays[0].start, Frames(90))
        XCTAssertEqual(plan.overlays[0].end, Frames(110))
    }

    func testRetezProlinacekStridaDrahyABA() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 80)
        let b = try fx.addClip(start: 80, duration: 80, sourceStartFrames: 100)
        let c = try fx.addClip(start: 160, duration: 80, sourceStartFrames: 210)
        try fx.project.setTransition(.crossDissolve, duration: Frames(20),
                                     betweenLeft: a, andRight: b)
        try fx.project.setTransition(.crossDissolve, duration: Frames(20),
                                     betweenLeft: b, andRight: c)
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        XCTAssertEqual(plan.placements.map(\.lane), [0, 1, 0])
        // Prostřední klip má ramena na OBOU stranách: [70, 170).
        XCTAssertEqual(plan.placements[1].start, Frames(70))
        XCTAssertEqual(plan.placements[1].duration, Frames(100))
        XCTAssertEqual(plan.overlays.map(\.outgoingLane), [0, 1])
        XCTAssertEqual(plan.overlays.map(\.incomingLane), [1, 0])
    }

    func testRampovanyKlipJdePlanemBezeZmeny() throws {
        var (fx, l, _) = try makeCut()
        try fx.project.setSpeedRamp(clipID: l, ramp: SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0.5),
        ]))
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        let placement = plan.placements[0]
        XCTAssertTrue(placement.hasRamp)
        XCTAssertEqual(placement.start, Frames(0))
        XCTAssertEqual(placement.duration, Frames(100))
        // Spotřebu určuje křivka (0,5× → polovina), ne délka na ose.
        XCTAssertEqual(placement.sourceDuration,
                       fx.project.sourceConsumption(of: fx.clip(l)!))
    }

    func testVadnyPrechodSeDoPlanuNepusti() throws {
        var (fx, l, r) = try makeCut()
        let id = try fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                              betweenLeft: l, andRight: r)
        // Rozbít napřímo: zdroj pravého klipu na začátek souboru → přesah 0.
        var tracks = fx.project.timeline.tracks
        tracks[0].clips[1].sourceStart = .zero
        fx.project.timeline.tracks = tracks
        XCTAssertFalse(fx.project.validate().isEmpty, "stav má být vadný")

        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        // Klipy hrají natvrdo — žádná ramena, žádný předpis.
        XCTAssertEqual(plan.laneCount, 1)
        XCTAssertTrue(plan.overlays.isEmpty)
        XCTAssertEqual(plan.placements[0].duration, Frames(100))
        XCTAssertNil(plan.overlays.first { $0.transitionID == id })
    }

    func testCrossfadeNaZvukoveStopeMaStejnouMechaniku() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 100, on: fx.a1)
        let b = try fx.addClip(start: 100, duration: 100, sourceStartFrames: 120, on: fx.a1)
        try fx.project.setTransition(.audioCrossfade, duration: Frames(24),
                                     betweenLeft: a, andRight: b)
        let plan = fx.project.compositionPlan(forTrack: fx.a1)!
        XCTAssertEqual(plan.laneCount, 2)
        XCTAssertEqual(plan.placements[0].duration, Frames(112))
        XCTAssertEqual(plan.placements[1].start, Frames(88))
        XCTAssertEqual(plan.overlays[0].kind, .audioCrossfade)
    }

    func testMezeraMeziKlipyDrahyNestrida() throws {
        var fx = Fixture()
        _ = try fx.addClip(start: 0, duration: 50)
        _ = try fx.addClip(start: 80, duration: 50, sourceStartFrames: 60)
        let plan = fx.project.compositionPlan(forTrack: fx.v1)!
        XCTAssertEqual(plan.placements.map(\.lane), [0, 0])
        XCTAssertEqual(plan.laneCount, 1)
    }
}
