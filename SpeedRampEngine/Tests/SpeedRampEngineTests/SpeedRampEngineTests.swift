//
//  SpeedRampEngineTests.swift
//  Projekt AIditor
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

// MARK: - Segmentace podle meze skoku rychlosti

/// Pevný počet snímků na úsek je špatná veličina: skok rychlosti závisí na
/// délce klipu. Tyhle testy ověřují variantu, kde si engine počet úseků
/// dopočítá sám tak, aby skok nikde nepřekročil zadanou mez.
final class SpeedRampAdaptiveSegmentTests: XCTestCase {

    /// Kontrakt zní: **buď se mez dodrží, nebo se přizná, že nešla dodržet** —
    /// a přiznat ji smí jen tehdy, když se došlo až na jeden snímek na úsek.
    /// Tichý návrat něčeho horšího je to jediné, co je zakázané.
    func testMezSeDodrziNeboSePrizna() throws {
        for sourceDuration in [11.358, 38.620, 44.938, 300.0] {
            for fps in [24.0, 30.0, 60.0] {
                for limit in [0.005, 0.015, 0.05] {
                    let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: sourceDuration,
                                                               slowSpeed: 0.25)
                    let plan = try ramp.segmentation(outputFrameRate: fps, maxSpeedStep: limit)
                    let popis = "zdroj \(sourceDuration) s, \(fps) fps, mez \(limit)"

                    if plan.limitedByFrameRate {
                        XCTAssertEqual(plan.framesPerSegment, 1,
                                       "vzdát to smí až na jednom snímku — \(popis)")
                        XCTAssertGreaterThan(plan.achievedMaxStep, limit, popis)
                    } else {
                        XCTAssertLessThanOrEqual(plan.achievedMaxStep, limit, popis)
                    }
                }
            }
        }
    }

    /// U typických svatebních délek a 30 fps musí mez 1,5 % vyjít vždy.
    /// Kdyby ne, výchozí hodnota v produktu je špatně zvolená.
    func testVychoziMezVychaziNaBeznychDelkach() throws {
        for sourceDuration in [5.0, 11.358, 20.0, 38.620, 44.938, 120.0, 300.0] {
            let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: sourceDuration,
                                                       slowSpeed: 0.25)
            let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)
            XCTAssertFalse(plan.limitedByFrameRate,
                           "výchozí mez 1,5 % nevyšla na \(sourceDuration) s")
            XCTAssertLessThanOrEqual(plan.achievedMaxStep, 0.015)
        }
    }

    /// Kde je hranice dosažitelnosti: krátký klip na nízké fps má míň snímků,
    /// takže minimální krok je hrubší. Tohle je vlastnost mřížky, ne chyba.
    func testNizsiFpsMaHrubsiPodlahu() throws {
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 11.358, slowSpeed: 0.25)

        let podlaha24 = try ramp.segmentation(outputFrameRate: 24, maxSpeedStep: 1e-9).achievedMaxStep
        let podlaha60 = try ramp.segmentation(outputFrameRate: 60, maxSpeedStep: 1e-9).achievedMaxStep

        XCTAssertGreaterThan(podlaha24, podlaha60,
                             "míň snímků za sekundu = hrubší nejmenší možný krok")
    }

    /// Tohle je jádro změny: stejná mez má na různě dlouhých klipech dát
    /// různý počet snímků na úsek. Kdyby to vracelo pořád stejné číslo,
    /// nová varianta by nic neřešila.
    func testDelsiKlipDostaneHrubsiDeleni() throws {
        let kratky = try SpeedRamp.classicSlowMotion(sourceDuration: 11.358, slowSpeed: 0.25)
        let dlouhy = try SpeedRamp.classicSlowMotion(sourceDuration: 44.938, slowSpeed: 0.25)

        let planKratky = try kratky.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)
        let planDlouhy = try dlouhy.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)

        XCTAssertGreaterThan(planDlouhy.framesPerSegment, planKratky.framesPerSegment,
                             "delší klip snese hrubší dělení při stejné kvalitě")
        XCTAssertLessThanOrEqual(planKratky.achievedMaxStep, 0.015)
        XCTAssertLessThanOrEqual(planDlouhy.achievedMaxStep, 0.015)
    }

    /// Přísnější mez nesmí dát míň úseků.
    func testPrisnejsiMezNedaMeneUseku() throws {
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 44.938, slowSpeed: 0.25)
        var predchozi = Int.max

        for limit in [0.05, 0.02, 0.01, 0.005, 0.002] {
            let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: limit)
            XCTAssertLessThanOrEqual(plan.segmentCount, predchozi == Int.max ? Int.max : predchozi * 4,
                                     "skok v počtu úseků je nečekaně velký")
            XCTAssertGreaterThanOrEqual(plan.segmentCount, 1)
            if predchozi != Int.max {
                XCTAssertGreaterThanOrEqual(plan.segmentCount, predchozi,
                                            "přísnější mez \(limit) dala míň úseků")
            }
            predchozi = plan.segmentCount
        }
    }

    /// Krátký a strmý ramp mez nemusí splnit ani při jednom snímku na úsek.
    /// Engine to musí přiznat, ne tiše vrátit něco horšího.
    func testNedosazitelnaMezSePrizna() throws {
        // 1,5 s zdroje → 2,4 s výstupu, celá křivka v pár snímcích.
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 1.5, slowSpeed: 0.25)
        let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.001)

        XCTAssertEqual(plan.framesPerSegment, 1, "mělo se dojít až na jeden snímek")
        XCTAssertTrue(plan.limitedByFrameRate, "nedosažitelná mez se musí přiznat")
        XCTAssertGreaterThan(plan.achievedMaxStep, plan.requestedMaxStep)
    }

    /// Konstantní rychlost nemá co segmentovat — jeden úsek stačí.
    func testKonstantniRychlostNepotrebujeDeleni() throws {
        let ramp = try SpeedRamp.constant(speed: 0.5, outputDuration: 10)
        let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)

        XCTAssertEqual(plan.segmentCount, 1, "konstantní rychlost se nemá proč krájet")
        XCTAssertEqual(plan.achievedMaxStep, 0, accuracy: 1e-12)
        XCTAssertFalse(plan.limitedByFrameRate)
    }

    /// Invarianty z původní segmentace musí platit i tady: úseky na sebe
    /// navazují bez mezer a součty sedí.
    func testSouctySediANavazujiNaSebe() throws {
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 44.938, slowSpeed: 0.25)
        let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)
        let segments = plan.segments

        let sourceTotal = segments.reduce(0) { $0 + $1.sourceDuration }
        let outputTotal = segments.reduce(0) { $0 + $1.outputDuration }
        XCTAssertEqual(sourceTotal, ramp.sourceConsumed, accuracy: 1e-9)
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

    func testOdmitneNeplatnouMez() throws {
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 10, slowSpeed: 0.25)
        for mez in [0.0, -0.01, Double.nan] {
            XCTAssertThrowsError(try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: mez),
                                 "mez \(mez) měla být odmítnutá")
        }
    }

    /// Strmost křivky se musí měřit jemněji než snímková mřížka, jinak by
    /// se podcenila a mez by se tiše překročila.
    func testStrmostOdpovidaKrivce() throws {
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 44.938, slowSpeed: 0.25)
        let slope = ramp.maxSpeedSlope(outputFrameRate: 30)

        // Hrubá kontrola proti ručnímu odhadu: rozsah rychlosti 0,75
        // přes polovinu výstupu, easeInOut zvedá špičkovou strmost
        // zhruba 1,5–2× nad průměr.
        let prumernaStrmost = 0.75 / (ramp.outputDuration / 2)
        XCTAssertGreaterThan(slope, prumernaStrmost)
        XCTAssertLessThan(slope, prumernaStrmost * 3)
    }
}

// MARK: - Zdrojově kotvené uzly

final class SourceAnchoredTests: XCTestCase {

    func testLinearniPrechodMaAnalytickouDelku() throws {
        // Lineární ease 1,0 → 0,5: průměrná rychlost 0,75. Zdrojový úsek 1,5 s
        // tedy trvá přesně 2,0 s výstupu.
        let ramp = try SpeedRamp.anchoredToSource([
            SourceAnchoredNode(sourceOffset: 0.0, speed: 1.0, easeToNext: .linear),
            SourceAnchoredNode(sourceOffset: 1.5, speed: 0.5, easeToNext: .linear),
        ])
        XCTAssertEqual(ramp.outputDuration, 2.0, accuracy: 1e-9)
        XCTAssertEqual(ramp.sourceConsumed, 1.5, accuracy: 1e-9)
    }

    func testUzlyLeziNaSvychZdrojovychPozicich() throws {
        // Křivka s různými easingy — zdrojová pozice každého uzlu musí sedět
        // přesně, protože kvadratura konstrukce je táž jako u integrální tabulky.
        let sources = [0.0, 0.8, 2.3, 3.125]
        let speeds = [1.0, 0.25, 0.6, 1.0]
        let eases: [BezierEase] = [.easeInOut, .easeOut, .easeIn, .linear]
        let ramp = try SpeedRamp.anchoredToSource(zip(zip(sources, speeds), eases).map {
            SourceAnchoredNode(sourceOffset: $0.0, speed: $0.1, easeToNext: $1)
        })

        for (i, node) in ramp.nodes.enumerated() {
            XCTAssertEqual(ramp.sourceTime(atOutput: node.outputOffset), sources[i],
                           accuracy: 1e-9, "uzel \(i) neleží na své zdrojové pozici")
            XCTAssertEqual(node.speed, speeds[i], accuracy: 1e-12)
        }
    }

    func testKlasickyTvarOdpovidaReferenci() throws {
        // Zdrojově kotvená obdoba referenční hodnoty: ramp 1,0 → 0,25 → 1,0
        // s easeInOut, který má spotřebovat přesně 3,125 s zdroje za 5 s
        // výstupu. EaseInOut je symetrický (∫ = 0,5), takže uzly leží na
        // 0 / 1,5625 / 3,125 s zdroje.
        let ramp = try SpeedRamp.anchoredToSource([
            SourceAnchoredNode(sourceOffset: 0.0, speed: 1.0, easeToNext: .easeInOut),
            SourceAnchoredNode(sourceOffset: 1.5625, speed: 0.25, easeToNext: .easeInOut),
            SourceAnchoredNode(sourceOffset: 3.125, speed: 1.0, easeToNext: .easeInOut),
        ])
        XCTAssertEqual(ramp.outputDuration, 5.0, accuracy: 1e-9)
        XCTAssertEqual(ramp.sourceConsumed, 3.125, accuracy: 1e-9)
    }

    func testOdmitneNerostouciZdrojoveCasy() {
        XCTAssertThrowsError(try SpeedRamp.anchoredToSource([
            SourceAnchoredNode(sourceOffset: 0.0, speed: 1.0),
            SourceAnchoredNode(sourceOffset: 0.0, speed: 0.5),
        ])) {
            XCTAssertEqual($0 as? SpeedRampError, .nonIncreasingTime(index: 1))
        }
    }

    func testOdmitneJedinyUzel() {
        XCTAssertThrowsError(try SpeedRamp.anchoredToSource([
            SourceAnchoredNode(sourceOffset: 0.0, speed: 1.0),
        ])) {
            XCTAssertEqual($0 as? SpeedRampError, .tooFewNodes)
        }
    }

    func testOdmitneNulovouRychlost() {
        XCTAssertThrowsError(try SpeedRamp.anchoredToSource([
            SourceAnchoredNode(sourceOffset: 0.0, speed: 0.0),
            SourceAnchoredNode(sourceOffset: 1.0, speed: 1.0),
        ]))
    }
}

// MARK: - Okénková segmentace

final class WindowedSegmentationTests: XCTestCase {

    private func classicRamp() throws -> SpeedRamp {
        try SpeedRamp.fitting(sourceDuration: 8.0, shape: [
            SpeedNode(outputOffset: 0, speed: 1.0, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 1, speed: 0.25, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 2, speed: 1.0, easeToNext: .easeInOut),
        ])
    }

    func testCeleOknoSoucetSediNaZdrojIVystup() throws {
        let ramp = try classicRamp()
        let frames = Int((ramp.outputDuration * 30).rounded(.down))
        let segments = try ramp.segments(outputFrameRate: 30, framesPerSegment: 3,
                                         windowStart: 0, windowFrames: frames)

        let outputSum = segments.reduce(0) { $0 + $1.outputDuration }
        XCTAssertEqual(outputSum, Double(frames) / 30.0, accuracy: 1e-9)

        let sourceSum = segments.reduce(0) { $0 + $1.sourceDuration }
        XCTAssertEqual(sourceSum, ramp.sourceTime(atOutput: Double(frames) / 30.0), accuracy: 1e-9)
    }

    func testUsekyNavazujiBezeZbytku() throws {
        let ramp = try classicRamp()
        let segments = try ramp.segments(outputFrameRate: 30, framesPerSegment: 4,
                                         windowStart: 2.2, windowFrames: 90)
        var cursor = 0.0
        for segment in segments {
            XCTAssertEqual(segment.sourceStart, cursor, accuracy: 1e-12)
            cursor += segment.sourceDuration
        }
    }

    func testVysekOdpovidaMapovaniKrivky() throws {
        // Zdroj spotřebovaný oknem [t0, t0 + D] musí být rozdíl mapování,
        // ne „kus celokřivkové segmentace" — okno začíná uprostřed easingu.
        let ramp = try classicRamp()
        let t0 = 1.7
        let frames = 60
        let segments = try ramp.segments(outputFrameRate: 30, framesPerSegment: 2,
                                         windowStart: t0, windowFrames: frames)
        let sourceSum = segments.reduce(0) { $0 + $1.sourceDuration }
        let expected = ramp.sourceTime(atOutput: t0 + Double(frames) / 30.0) - ramp.sourceTime(atOutput: t0)
        XCTAssertEqual(sourceSum, expected, accuracy: 1e-9)
    }

    func testOknoZaKoncemKrivkyJedeRychlostiPoslednihoUzlu() throws {
        let ramp = try classicRamp()
        // Okno celé za koncem křivky: rychlost konstantní 1,0 → jediný úsek.
        let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015,
                                        windowStart: ramp.outputDuration + 1, windowFrames: 30)
        XCTAssertEqual(plan.segmentCount, 1)
        XCTAssertEqual(plan.segments[0].speed, 1.0, accuracy: 1e-9)
        XCTAssertFalse(plan.limitedByFrameRate)
    }

    func testOkenkovaMezSeDodrzi() throws {
        let ramp = try classicRamp()
        let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015,
                                        windowStart: 0.9, windowFrames: 150)
        XCTAssertLessThanOrEqual(plan.achievedMaxStep, 0.015)
        XCTAssertFalse(plan.limitedByFrameRate)
        let outputFrames = plan.segments.reduce(0) { $0 + Int(($1.outputDuration * 30).rounded()) }
        XCTAssertEqual(outputFrames, 150)
    }

    func testPrumerEasinguSediNaAnalytickychHodnotach() {
        XCTAssertEqual(BezierEase.linear.integralAverage, 0.5, accuracy: 1e-9)
        XCTAssertEqual(BezierEase.easeInOut.integralAverage, 0.5, accuracy: 1e-9)  // symetrie
    }
}
