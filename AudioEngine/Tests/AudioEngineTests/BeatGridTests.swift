//
//  BeatGridTests.swift
//  Projekt AIditor — AudioEngine (fáze 14, modul 1)
//
//  Syntetické klikové stopy se ZNÁMÝM tempem — detektor musí tempo
//  i fázi najít v toleranci. Fáze se porovnává MODULO perioda: mřížka
//  smí legálně začít o celé doby jinde, než padl první klik.
//

import XCTest
@testable import AudioEngine

// MARK: - Pomůcky

/// Deterministický xorshift64 — testy musí být opakovatelné.
private struct Random {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000.0
    }
}

private let testRate = 48_000.0

/// Kliková stopa: 8ms úder (1 kHz sinus s doznívánm) na každé době.
private func clickTrack(bpm: Double,
                        seconds: Double = 12,
                        firstClick: Double = 0.5,
                        noise: Double = 0,
                        seed: UInt64 = 1) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(seconds * testRate))
    let clickLength = Int(0.008 * testRate)
    let interval = 60.0 / bpm
    var t = firstClick
    while t < seconds {
        let start = Int(t * testRate)
        for i in 0..<clickLength where start + i < samples.count {
            let envelope = 1.0 - Double(i) / Double(clickLength)
            let tone = sin(2.0 * .pi * 1000.0 * Double(i) / testRate)
            samples[start + i] += Float(0.8 * envelope * tone)
        }
        t += interval
    }
    if noise > 0 {
        var random = Random(seed: seed)
        for i in samples.indices {
            samples[i] += Float((random.next() - 0.5) * 2 * noise)
        }
    }
    return samples
}

/// Chyba fáze modulo perioda: vzdálenost mřížky od očekávaného času
/// doby, v sekundách (0 … perioda/2).
private func phaseError(_ grid: BeatGrid, expectedBeatAt time: Double) -> Double {
    let interval = grid.beatInterval
    let remainder = (time - grid.firstBeatTime).truncatingRemainder(dividingBy: interval)
    let wrapped = remainder < 0 ? remainder + interval : remainder
    return min(wrapped, interval - wrapped)
}

// MARK: - Detekce

final class BeatDetectorTests: XCTestCase {

    func testFindsTempo120() throws {
        let grid = try XCTUnwrap(BeatDetector.analyze(
            samples: clickTrack(bpm: 120), sampleRate: testRate))
        XCTAssertEqual(grid.bpm, 120, accuracy: 0.1)
        XCTAssertLessThan(phaseError(grid, expectedBeatAt: 0.5), 0.015,
                          "doby mřížky mají ležet na klicích")
        XCTAssertGreaterThan(grid.confidence, 0.3)
    }

    func testFindsOddTempo() throws {
        // Neceločíselné BPM — perioda nesedí na rozlišení rámců, jemnost
        // musí dodat parabolická interpolace a regrese přes onsety.
        let grid = try XCTUnwrap(BeatDetector.analyze(
            samples: clickTrack(bpm: 97.4), sampleRate: testRate))
        XCTAssertEqual(grid.bpm, 97.4, accuracy: 0.1)
    }

    func testFindsPhaseOffset() throws {
        let grid = try XCTUnwrap(BeatDetector.analyze(
            samples: clickTrack(bpm: 110, firstClick: 0.37), sampleRate: testRate))
        XCTAssertEqual(grid.bpm, 110, accuracy: 0.1)
        XCTAssertLessThan(phaseError(grid, expectedBeatAt: 0.37), 0.015)
    }

    func testSurvivesNoise() throws {
        let grid = try XCTUnwrap(BeatDetector.analyze(
            samples: clickTrack(bpm: 128, noise: 0.1, seed: 5), sampleRate: testRate))
        XCTAssertEqual(grid.bpm, 128, accuracy: 0.3)
        XCTAssertLessThan(phaseError(grid, expectedBeatAt: 0.5), 0.02)
    }

    func testSlowTempoInRange() throws {
        // 70 BPM: dvojnásobek 140 je taky v mezích, ale kliková stopa
        // na 140 žádnou autokorelaci nemá — nesmí vyhrát jen kvůli
        // preferenci rychlejších temp.
        let grid = try XCTUnwrap(BeatDetector.analyze(
            samples: clickTrack(bpm: 70), sampleRate: testRate))
        XCTAssertEqual(grid.bpm, 70, accuracy: 0.1)
    }

    func testPureNoiseReturnsNil() {
        var random = Random(seed: 9)
        let noise = (0..<Int(10 * testRate)).map { _ in Float((random.next() - 0.5) * 0.6) }
        XCTAssertNil(BeatDetector.analyze(samples: noise, sampleRate: testRate),
                     "šum nemá tempo — mřížka se nesmí vymyslet")
    }

    func testTooShortReturnsNil() {
        XCTAssertNil(BeatDetector.analyze(
            samples: clickTrack(bpm: 120, seconds: 0.4), sampleRate: testRate))
    }

    func testOnsetsMatchClicks() {
        // 12 s na 100 BPM od 0,5 s → kliky na 0,5 + k·0,6 do 12 s = 20.
        let onsets = BeatDetector.onsets(
            samples: clickTrack(bpm: 100, seconds: 12), sampleRate: testRate)
        XCTAssertEqual(onsets.count, 20, "počet onsetů = počet kliků")
        for (k, onset) in onsets.enumerated() {
            XCTAssertEqual(onset.time, 0.5 + Double(k) * 0.6, accuracy: 0.025,
                           "onset \(k) sedí na kliku")
        }
    }
}

// MARK: - Mřížka

final class BeatGridTests: XCTestCase {

    private let grid = BeatGrid(bpm: 120, firstBeatTime: 0.5)

    func testBeatsInRange() {
        let beats = grid.beats(from: 0, to: 3.0)
        // Doby: 0,5 · 1,0 · 1,5 · 2,0 · 2,5 (3,0 už je za intervalem).
        XCTAssertEqual(beats.map(\.time), [0.5, 1.0, 1.5, 2.0, 2.5])
        XCTAssertEqual(beats.map(\.index), [0, 1, 2, 3, 4])
        // Výchozí takt od první doby: „raz" na indexech 0 a 4.
        XCTAssertEqual(beats.map(\.isDownbeat), [true, false, false, false, true])
    }

    func testBeatOnRangeStartIsIncluded() {
        let beats = grid.beats(from: 1.0, to: 1.6)
        XCTAssertEqual(beats.map(\.time), [1.0, 1.5])
    }

    func testNoBeatsBeforeGridStart() {
        XCTAssertTrue(grid.beats(from: 0, to: 0.5).isEmpty,
                      "před první dobou metrum neexistuje")
    }

    func testNearestBeat() {
        XCTAssertEqual(grid.nearestBeat(to: 1.7).time, 1.5)
        XCTAssertEqual(grid.nearestBeat(to: 1.8).time, 2.0)
        XCTAssertEqual(grid.nearestBeat(to: -3.0).index, 0, "před mřížkou je nejbližší doba nula")
    }

    func testMarkDownbeat() {
        var adjusted = grid
        adjusted.markDownbeat(at: 1.55)   // nejblíž je doba s indexem 2
        XCTAssertEqual(adjusted.downbeatOffset, 2)
        let beats = adjusted.beats(from: 0, to: 3.0)
        XCTAssertEqual(beats.map(\.isDownbeat), [false, false, true, false, false])
    }

    func testAlignBeatShiftsPhaseOnly() {
        var adjusted = grid
        adjusted.alignBeat(to: 1.52)      // doba 1,5 se posune na 1,52
        XCTAssertEqual(adjusted.firstBeatTime, 0.52, accuracy: 1e-12)
        XCTAssertEqual(adjusted.bpm, 120)
    }

    func testTempoMultipleKeepsPhase() {
        var adjusted = grid
        adjusted.doubleTempo()
        XCTAssertEqual(adjusted.bpm, 240)
        XCTAssertEqual(adjusted.firstBeatTime, 0.5)
        adjusted.halveTempo()
        adjusted.halveTempo()
        XCTAssertEqual(adjusted.bpm, 60)
        XCTAssertEqual(adjusted.firstBeatTime, 0.5)
    }

    func testCodableRoundtrip() throws {
        var original = grid
        original.markDownbeat(at: 1.0)
        original.confidence = 0.87
        let decoded = try JSONDecoder().decode(
            BeatGrid.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
