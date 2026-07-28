//
//  RampEditorTests.swift
//  TimelineModel — Projekt Krása
//
//  Logika editoru rychlostní křivky: škála, pozice uzlů, přidávání, mazání,
//  tažení a mez čistého zpomalení. Kreslení se testuje okem, tohle vším,
//  co má porovnatelnou hodnotu.
//

import XCTest
@testable import TimelineModel

final class RampEditorScaleTests: XCTestCase {

    func testJednickaJeUprostred() {
        // Rozsah 0,125–8 je symetrický kolem 1× v log₂ — jednička půlí osu.
        XCTAssertEqual(RampEditorScale().unit(ofSpeed: 1.0), 0.5, accuracy: 1e-12)
    }

    func testRoundTrip() {
        let scale = RampEditorScale()
        for speed in [0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0] {
            XCTAssertEqual(scale.speed(atUnit: scale.unit(ofSpeed: speed)), speed,
                           accuracy: 1e-9)
        }
    }

    func testOrezavaMimoRozsah() {
        let scale = RampEditorScale()
        XCTAssertEqual(scale.clamp(0.01), 0.125)
        XCTAssertEqual(scale.clamp(100), 8.0)
        XCTAssertEqual(scale.unit(ofSpeed: 0.001), 0, accuracy: 1e-12)
        XCTAssertEqual(scale.speed(atUnit: 2.0), 8.0)
        XCTAssertEqual(scale.speed(atUnit: -1.0), 0.125)
    }

    func testLogaritmickaSymetrie() {
        // 0,5× a 2× jsou stejně daleko od jedničky — o to tu log škála je.
        let scale = RampEditorScale()
        let below = scale.unit(ofSpeed: 1) - scale.unit(ofSpeed: 0.5)
        let above = scale.unit(ofSpeed: 2) - scale.unit(ofSpeed: 1)
        XCTAssertEqual(below, above, accuracy: 1e-12)
    }
}

final class RampEditorReadTests: XCTestCase {

    private func rampedFixture() throws -> (Fixture, ClipID) {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp:
            .classicSlowMotion(from: .zero,
                               spanning: SourceTime(seconds: 3.125),
                               slowSpeed: 0.25))
        return (f, id)
    }

    func testUzlyKlasickehoRampuLeziNaTretinach() throws {
        // Klasický ramp fitnutý na 150 snímků: uzly na výstupech 0 / 75 / 150.
        let (f, id) = try rampedFixture()
        let nodes = f.project.rampEditorNodes(of: f.clip(id)!)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0].outputFrame, 0, accuracy: 1e-6)
        XCTAssertEqual(nodes[1].outputFrame, 75, accuracy: 1e-6)
        XCTAssertEqual(nodes[2].outputFrame, 150, accuracy: 1e-6)
        XCTAssertEqual(nodes[1].speed, 0.25, accuracy: 1e-12)
    }

    func testKlipBezRampyNemaUzlyAProfilJeJednicka() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        let clip = f.clip(id)!
        XCTAssertTrue(f.project.rampEditorNodes(of: clip).isEmpty)
        XCTAssertTrue(f.project.rampSpeedProfile(of: clip, samples: 20)
            .allSatisfy { $0 == 1.0 })
    }

    func testProfilKopirujeKrivku() throws {
        let (f, id) = try rampedFixture()
        let profile = f.project.rampSpeedProfile(of: f.clip(id)!, samples: 301)
        XCTAssertEqual(profile.first!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(profile[150], 0.25, accuracy: 1e-9, "uprostřed je dno rampu")
        XCTAssertEqual(profile.last!, 1.0, accuracy: 1e-9)
    }

    func testMezCistehoZpomaleni() throws {
        // Fixture má measuredFrameRate 60, základna 30 → mez 0,5.
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 60)
        XCTAssertEqual(f.project.pureSlowdownLimit(of: f.clip(id)!)!, 0.5,
                       accuracy: 1e-12)
    }
}

final class RampEditorEditTests: XCTestCase {

    func testPridaniUzluNaPlochyKlipNemeniSpotrebu() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        let before = f.project.sourceConsumption(of: f.clip(id)!)

        let index = try f.project.addRampNode(clipID: id, atOutputFrame: 60)
        XCTAssertEqual(index, 0)

        let clip = f.clip(id)!
        XCTAssertEqual(clip.speedRamp?.nodes.count, 1)
        XCTAssertEqual(clip.speedRamp?.nodes[0].speed, 1.0)
        // Jednouzlová křivka s rychlostí 1 ≡ žádná křivka.
        XCTAssertEqual(f.project.sourceConsumption(of: clip), before)
        XCTAssertValid(f.project)
    }

    func testPridanyUzelLeziNaKrivce() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp:
            .classicSlowMotion(from: .zero, spanning: SourceTime(seconds: 3.125)))
        let clip = f.clip(id)!

        let expectedSpeed = f.project.rampSpeedProfile(of: clip, samples: 151)[40]
        let expectedSource = f.project.sourceOffset(in: clip, atFrame: Frames(40)).seconds
        let index = try f.project.addRampNode(clipID: id, atOutputFrame: 40)

        // Rychlost a zdrojová kotva sedí PŘESNĚ — uzel drží událost ve zdroji.
        // Výstupní pozice se smí o pár snímků lišit: vložení uzlu rozdělí
        // easeInOut přechod na dva easeInOut kusy a výsek Bézierovy křivky
        // není Bézierova křivka téže rodiny, takže se časování okolí mírně
        // přerozdělí. (Naměřeno: 40 → ~43 snímků.)
        let nodes = f.project.rampEditorNodes(of: f.clip(id)!)
        XCTAssertEqual(nodes.count, 4)
        XCTAssertEqual(nodes[index].speed, expectedSpeed, accuracy: 1e-9)
        XCTAssertEqual(f.clip(id)!.speedRamp!.nodes[index].sourceTime.seconds,
                       expectedSource, accuracy: 1e-4)
        XCTAssertEqual(nodes[index].outputFrame, 40, accuracy: 5)
        XCTAssertValid(f.project)
    }

    func testUzelPrilisBlizkoSouseduSeOdmitne() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.addRampNode(clipID: id, atOutputFrame: 60)
        var p = f.project
        XCTAssertThrowsUnchanged(&p, .invalidSpeedRamp) {
            _ = try $0.addRampNode(clipID: id, atOutputFrame: 60.1)
        }
    }

    func testSmazaniPoslednihoUzluVraciKlipNa1x() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.addRampNode(clipID: id, atOutputFrame: 60)
        try f.project.removeRampNode(clipID: id, nodeIndex: 0)
        XCTAssertNil(f.clip(id)!.speedRamp)
        XCTAssertEqual(f.project.sourceConsumption(of: f.clip(id)!),
                       f.project.timeline.sourceTime(Frames(150)))
    }

    func testMazaniSeProjeviIDvojceti() throws {
        var f = Fixture(seconds: 10)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)
        try f.project.addRampNode(clipID: video.id, atOutputFrame: 60)
        XCTAssertEqual(f.clip(audio.id)?.speedRamp?.nodes.count, 1,
                       "přidání jde přes setSpeedRamp, takže je link-aware")
        try f.project.removeRampNode(clipID: video.id, nodeIndex: 0)
        XCTAssertNil(f.clip(audio.id)?.speedRamp)
    }
}

final class RampNodeDragTests: XCTestCase {

    private func rampedFixture() throws -> (Fixture, ClipID) {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp:
            .classicSlowMotion(from: .zero,
                               spanning: SourceTime(seconds: 3.125),
                               slowSpeed: 0.25))
        return (f, id)
    }

    func testSvisleTazeniMeniJenRychlost() throws {
        let (f, id) = try rampedFixture()
        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 1)!
        let moved = drag.ramp(atOutputFrame: nil, speed: 0.5)

        XCTAssertEqual(moved.nodes.count, 3)
        XCTAssertEqual(moved.nodes[1].speed, 0.5)
        XCTAssertEqual(moved.nodes[1].sourceTime,
                       f.clip(id)!.speedRamp!.nodes[1].sourceTime,
                       "svislé tažení nesmí hnout zdrojovou kotvou")
        XCTAssertEqual(moved.nodes[0], f.clip(id)!.speedRamp!.nodes[0])
        XCTAssertEqual(moved.nodes[2], f.clip(id)!.speedRamp!.nodes[2])
    }

    func testRychlostSeOrezavaNaSkalu() throws {
        let (f, id) = try rampedFixture()
        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 1)!
        XCTAssertEqual(drag.ramp(atOutputFrame: nil, speed: 0.0001).nodes[1].speed, 0.125)
        XCTAssertEqual(drag.ramp(atOutputFrame: nil, speed: 50).nodes[1].speed, 8.0)
    }

    func testVodorovneTazeniJdePresZakladnu() throws {
        // Uzel tažený na snímek 40 má skončit tam, kde PŮVODNÍ křivka
        // ukazovala snímek 40 — mapování se nesmí skládat přes měněnou křivku.
        let (f, id) = try rampedFixture()
        let clip = f.clip(id)!
        let expected = f.project.sourceOffset(in: clip, atFrame: Frames(40)).seconds

        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 1)!
        let moved = drag.ramp(atOutputFrame: 40, speed: nil)
        XCTAssertEqual(moved.nodes[1].sourceTime.seconds, expected, accuracy: 1e-4)
        XCTAssertEqual(moved.nodes[1].speed, 0.25, "rychlost se vodorovným tažením nemění")
    }

    func testTazeniNepretahneUzelPresSouseda() throws {
        let (f, id) = try rampedFixture()
        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 1)!
        let moved = drag.ramp(atOutputFrame: 10_000, speed: nil)

        let last = f.clip(id)!.speedRamp!.nodes[2].sourceTime.seconds
        XCTAssertEqual(moved.nodes[1].sourceTime.seconds,
                       last - Project.minimumNodeSourceGap, accuracy: 1e-9,
                       "uzel se zarazí o souseda minus minimální rozestup")
        // Pořadí uzlů drží, křivka zůstává použitelná.
        XCTAssertTrue(moved.isUsable)
    }

    func testKrajniUzelNepodlezeNulu() throws {
        let (f, id) = try rampedFixture()
        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 0)!
        let moved = drag.ramp(atOutputFrame: -500, speed: nil)
        XCTAssertGreaterThanOrEqual(moved.nodes[0].sourceTime.seconds, 0)
        XCTAssertTrue(moved.isUsable)
    }

    func testDragNaKlipBezRampyNevznikne() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        XCTAssertNil(RampNodeDrag(project: f.project, clipID: id, nodeIndex: 0))
    }

    func testCeleTazeniPresSetSpeedRampDrziInvarianty() throws {
        // Simulace celého tahu: každý krok se zapíše, jako to dělá view.
        var (f, id) = try rampedFixture()
        let drag = RampNodeDrag(project: f.project, clipID: id, nodeIndex: 1)!
        for step in 1...20 {
            let speed = 0.25 + Double(step) * 0.02
            try f.project.setSpeedRamp(clipID: id,
                                       ramp: drag.ramp(atOutputFrame: nil, speed: speed))
            XCTAssertValid(f.project)
        }
        XCTAssertEqual(f.clip(id)!.speedRamp!.nodes[1].speed, 0.65, accuracy: 1e-9)
    }
}
