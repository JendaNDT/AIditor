//
//  SpeedRampEngineTests.swift
//  Projekt Krása
//
//  Testy odpovídají numerickému ověření provedenému před portem do Swiftu.
//  Když některý spadne, matematika je rozbitá — ne test.
//

import XCTest
@testable import SpeedRampEngine

final class BezierEaseTests: XCTestCase {

    func testKrajniHodnoty() {
        for ease: BezierEase in [.linear, .easeInOut, .easeIn, .easeOut] {
            XCTAssertEqual(ease.value(at: 0.0), 0.0, accuracy: 1e-12)
            XCTAssertEqual(ease.value(at: 1.0), 1.0, accuracy: 1e-12)
            XCTAssertEqual(ease.value(at: -5.0), 0.0, accuracy: 1e-12)
            XCTAssertEqual(ease.value(at: 42.0), 1.0, accuracy: 1e-12)
        }
    }

    func testMonotonie() {
        for ease: BezierEase in [.linear, .easeInOut, .easeIn, .easeOut] {
            var previous = -1.0
            for i in 0...1000 {
                let v = ease.value(at: Double(i) / 1000.0)
                XCTAssertGreaterThanOrEqual(v, previous - 1e-12, "easing musí být neklesající")
                previous = v
            }
        }
    }

    func testLinearJeIdentita() {
        for i in 0...200 {
            let u = Double(i) / 200.0
            XCTAssertEqual(BezierEase.linear.value(at: u), u, accuracy: 1e-9)
        }
    }

    func testEaseInOutJeSymetricky() {
        XCTAssertEqual(BezierEase.easeInOut.value(at: 0.25)
                     + BezierEase.easeInOut.value(at: 0.75), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BezierEase.easeInOut.value(at: 0.5), 0.5, accuracy: 1e-9)
    }
}

final class SpeedRampValidationTests: XCTestCase {

    func testOdmitneJedinyUzel() {
        XCTAssertThrowsError(try SpeedRamp(nodes: [SpeedNode(outputOffset: 0, speed: 1)])) {
            XCTAssertEqual($0 as? SpeedRampError, .tooFewNodes)
        }
    }

    func testOdmitnePrvniUzelMimoNulu() {
        XCTAssertThrowsError(try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.5, speed: 1),
            SpeedNode(outputOffset: 1.0, speed: 1),
        ]))
    }

    func testOdmitneNulovouRychlost() {
        XCTAssertThrowsError(try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: 0.0),
            SpeedNode(outputOffset: 1.0, speed: 1.0),
        ]))
    }

    func testOdmitneZapornouRychlost() {
        XCTAssertThrowsError(try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: 1.0),
            SpeedNode(outputOffset: 1.0, speed: -0.5),
        ]))
    }

    func testOdmitneDuplicitniCasy() {
        XCTAssertThrowsError(try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: 1.0),
            SpeedNode(outputOffset: 1.0, speed: 0.5),
            SpeedNode(outputOffset: 1.0, speed: 0.25),
        ]))
    }

    func testSeradiUzlyPodleCasu() throws {
        let ramp = try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 2.0, speed: 1.0),
            SpeedNode(outputOffset: 0.0, speed: 1.0),
            SpeedNode(outputOffset: 1.0, speed: 0.5),
        ])
        XCTAssertEqual(ramp.nodes.map(\.outputOffset), [0.0, 1.0, 2.0])
    }
}

final class SpeedRampMathTests: XCTestCase {

    /// Konstantní rychlost je analyticky přesná: t_src(t) = c·t
    func testKonstantniRychlostJePresna() throws {
        for c in [0.25, 0.5, 1.0, 2.0, 4.0] {
            let ramp = try SpeedRamp.constant(speed: c, outputDuration: 10.0)
            for i in 0...100 {
                let t = Double(i) / 10.0
                XCTAssertEqual(ramp.sourceTime(atOutput: t), c * t, accuracy: 1e-9)
            }
            XCTAssertEqual(ramp.sourceConsumed, c * 10.0, accuracy: 1e-9)
        }
    }

    /// Lineární přechod: ∫ = v₀·T + (v₁−v₀)·T/2
    func testLinearniPrechodJePresny() throws {
        let cases: [(Double, Double, Double)] = [(1.0, 0.25, 4.0), (0.25, 1.0, 3.0), (2.0, 0.5, 5.0)]
        for (v0, v1, T) in cases {
            let ramp = try SpeedRamp(nodes: [
                SpeedNode(outputOffset: 0.0, speed: v0, easeToNext: .linear),
                SpeedNode(outputOffset: T,   speed: v1, easeToNext: .linear),
            ])
            XCTAssertEqual(ramp.sourceConsumed, v0 * T + (v1 - v0) * T / 2.0, accuracy: 1e-9)
        }
    }

    /// Referenční hodnota z ověřené Python implementace.
    func testHlavniRampSpotrebujePresne3125() throws {
        let ramp = try Self.klasickyRamp()
        XCTAssertEqual(ramp.outputDuration, 5.0, accuracy: 1e-12)
        XCTAssertEqual(ramp.sourceConsumed, 3.125, accuracy: 1e-9)
    }

    func testMapovaniZacinaVNule() throws {
        XCTAssertEqual(try Self.klasickyRamp().sourceTime(atOutput: 0.0), 0.0, accuracy: 1e-12)
    }

    /// Nejdůležitější vlastnost: mapování musí být striktně rostoucí.
    /// Kdyby nebylo, video by se na chvíli přehrávalo pozpátku.
    func testMapovaniJeStriktneRostouci() throws {
        let ramp = try Self.klasickyRamp()
        var previous = -1.0
        var smallestStep = Double.infinity
        for i in 0...20_000 {
            let t = 5.0 * Double(i) / 20_000.0
            let s = ramp.sourceTime(atOutput: t)
            XCTAssertGreaterThanOrEqual(s, previous, "mapování couvlo v čase \(t)")
            if previous >= 0 { smallestStep = min(smallestStep, s - previous) }
            previous = s
        }
        XCTAssertGreaterThan(smallestStep, 0, "nikde nesmí být plochý úsek")
    }

    /// Derivace mapování musí odpovídat rychlostní křivce.
    func testDerivaceOdpovidaRychlosti() throws {
        let ramp = try Self.klasickyRamp()
        let h = 1e-6
        for i in 1..<2000 {
            let t = 5.0 * Double(i) / 2000.0
            let numeric = (ramp.sourceTime(atOutput: t + h) - ramp.sourceTime(atOutput: t - h)) / (2 * h)
            XCTAssertEqual(numeric, ramp.speed(atOutput: t), accuracy: 1e-5)
        }
    }

    func testSpojitostVUzlech() throws {
        let ramp = try Self.klasickyRamp()
        let left = ramp.sourceTime(atOutput: 2.5 - 1e-9)
        let right = ramp.sourceTime(atOutput: 2.5 + 1e-9)
        XCTAssertEqual(left, right, accuracy: 1e-7)
    }

    func testRychlostVUzlechSedi() throws {
        let ramp = try Self.klasickyRamp()
        XCTAssertEqual(ramp.speed(atOutput: 0.0), 1.00, accuracy: 1e-12)
        XCTAssertEqual(ramp.speed(atOutput: 2.5), 0.25, accuracy: 1e-9)
        XCTAssertEqual(ramp.speed(atOutput: 5.0), 1.00, accuracy: 1e-12)
    }

    func testExtremniRampZustaneMonotonni() throws {
        let ramp = try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: 1.00),
            SpeedNode(outputOffset: 1.0, speed: 0.05),
            SpeedNode(outputOffset: 2.0, speed: 4.00),
        ])
        var previous = -1.0
        for i in 0...5000 {
            let s = ramp.sourceTime(atOutput: 2.0 * Double(i) / 5000.0)
            XCTAssertGreaterThanOrEqual(s, previous)
            previous = s
        }
    }

    static func klasickyRamp() throws -> SpeedRamp {
        try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: 1.00, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 2.5, speed: 0.25, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 5.0, speed: 1.00, easeToNext: .easeInOut),
        ])
    }
}

final class SpeedRampInverseTests: XCTestCase {

    func testRoundTripZCasoveOsy() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        for i in 1..<5000 {
            let t = 5.0 * Double(i) / 5000.0
            XCTAssertEqual(ramp.outputTime(atSource: ramp.sourceTime(atOutput: t)), t, accuracy: 1e-7)
        }
    }

    func testRoundTripZeZdroje() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        let total = ramp.sourceConsumed
        for i in 1..<5000 {
            let s = total * Double(i) / 5000.0
            XCTAssertEqual(ramp.sourceTime(atOutput: ramp.outputTime(atSource: s)), s, accuracy: 1e-7)
        }
    }

    func testMimoRozsahExtrapolujeKonstantne() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        XCTAssertEqual(ramp.sourceTime(atOutput: -1.0), 0.0, accuracy: 1e-12)
        // za koncem rampu pokračuje poslední rychlostí (1.0)
        XCTAssertEqual(ramp.sourceTime(atOutput: 6.0), ramp.sourceConsumed + 1.0, accuracy: 1e-9)
    }
}

final class SpeedRampSegmentTests: XCTestCase {

    func testSouctySediANavazujiNaSebe() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        for fps in [24.0, 25.0, 30.0, 60.0] {
            for perSegment in [1, 2, 4] {
                let segments = try ramp.segments(outputFrameRate: fps, framesPerSegment: perSegment)

                let sourceTotal = segments.reduce(0) { $0 + $1.sourceDuration }
                let outputTotal = segments.reduce(0) { $0 + $1.outputDuration }
                XCTAssertEqual(sourceTotal, ramp.sourceConsumed, accuracy: 1e-9,
                               "fps \(fps), \(perSegment) snímků/segment")
                XCTAssertEqual(outputTotal, ramp.outputDuration, accuracy: 1e-9)

                for i in 0..<(segments.count - 1) {
                    XCTAssertEqual(segments[i].sourceStart + segments[i].sourceDuration,
                                   segments[i + 1].sourceStart, accuracy: 1e-12,
                                   "mezera mezi segmenty \(i) a \(i+1)")
                }
                for s in segments {
                    XCTAssertGreaterThan(s.sourceDuration, 0)
                    XCTAssertGreaterThan(s.outputDuration, 0)
                }
            }
        }
    }

    /// Jemnější segmentace = menší skoky rychlosti = méně lupanců ve zvuku.
    func testJemnejsiSegmentaceZmensujeSkoky() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        var previousJump = Double.infinity
        for perSegment in [8, 4, 2, 1] {
            let segments = try ramp.segments(outputFrameRate: 60.0, framesPerSegment: perSegment)
            let speeds = segments.map(\.speed)
            let maxJump = (0..<(speeds.count - 1)).map { abs(speeds[$0 + 1] - speeds[$0]) }.max() ?? 0
            XCTAssertLessThan(maxJump, previousJump, "jemnější dělení musí zmenšit skoky")
            previousJump = maxJump
        }
        XCTAssertLessThan(previousJump, 0.02, "při 1 snímku/segment má být skok pod 0,02×")
    }

    func testOdmitneNeplatnouSnimkovouFrekvenci() throws {
        let ramp = try SpeedRampMathTests.klasickyRamp()
        XCTAssertThrowsError(try ramp.segments(outputFrameRate: 0))
        XCTAssertThrowsError(try ramp.segments(outputFrameRate: -30))
    }

    func testKonstantniRychlostDavaKonstantniSegmenty() throws {
        let ramp = try SpeedRamp.constant(speed: 0.5, outputDuration: 4.0)
        let segments = try ramp.segments(outputFrameRate: 30.0, framesPerSegment: 2)
        for s in segments {
            XCTAssertEqual(s.speed, 0.5, accuracy: 1e-9)
        }
    }
}

final class SpeedRampFittingTests: XCTestCase {

    func testFittingSpotrebujePresnouDelkuZdroje() throws {
        let shape = [
            SpeedNode(outputOffset: 0.0, speed: 1.00, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 1.0, speed: 0.25, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 2.0, speed: 1.00, easeToNext: .easeInOut),
        ]
        for duration in [3.0, 8.0, 14.5] {
            let ramp = try SpeedRamp.fitting(sourceDuration: duration, shape: shape)
            XCTAssertEqual(ramp.sourceConsumed, duration, accuracy: 1e-8)
        }
    }

    func testKlasickeZpomaleniProtahneKlip() throws {
        // 8 s zdroje, ramp na 0,25× uprostřed -> na časové ose musí být delší
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 8.0)
        XCTAssertEqual(ramp.sourceConsumed, 8.0, accuracy: 1e-8)
        XCTAssertGreaterThan(ramp.outputDuration, 8.0)
    }

    /// Případ ze specifikace: 120 fps zdroj na 0,25× dá přesně 30 fps výstup,
    /// tedy 1:1 poměr snímků a žádné dopočítávané mezisnímky.
    func testPripadZeSpecifikace120fps() throws {
        let ramp = try SpeedRamp.constant(speed: 0.25, outputDuration: 4.0)
        XCTAssertEqual(ramp.sourceConsumed, 1.0, accuracy: 1e-9)

        let outputFrames = 4.0 * 30.0     // 4 s výstupu při 30 fps
        let sourceFrames = 1.0 * 120.0    // 1 s zdroje při 120 fps
        XCTAssertEqual(outputFrames, sourceFrames, accuracy: 1e-12)
    }
}

final class SpeedRampCodableTests: XCTestCase {

    func testProjdeSerializaci() throws {
        let original = try SpeedRampMathTests.klasickyRamp()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SpeedRamp.self, from: data)

        XCTAssertEqual(original, restored)
        XCTAssertEqual(restored.sourceConsumed, original.sourceConsumed, accuracy: 1e-12)
        XCTAssertEqual(restored.sourceTime(atOutput: 3.0),
                       original.sourceTime(atOutput: 3.0), accuracy: 1e-12)
    }

    func testDekoderValidujeVstup() {
        let json = #"{"nodes":[{"outputOffset":0,"speed":0,"easeToNext":{"x1":0,"y1":0,"x2":1,"y2":1}}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SpeedRamp.self, from: Data(json.utf8)))
    }
}
