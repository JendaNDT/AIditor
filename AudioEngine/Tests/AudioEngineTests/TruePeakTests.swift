//
//  TruePeakTests.swift
//  Projekt AIditor — AudioEngine (fáze 16, modul 2)
//
//  Kotvy true peak měření. Hlavní je klasický případ mezivzorkové
//  špičky: sinus na fs/4 s fází π/4 má VZORKY nejvýš 0,707·A, ale
//  vlna jde do A — špička vzorků lže o 3 dB, true peak ne.
//

import XCTest
@testable import AudioEngine

final class TruePeakTests: XCTestCase {

    private func sine(frequency: Double, sampleRate: Double, seconds: Double,
                      amplitude: Double = 1.0, phase: Double = 0) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { n in
            Float(amplitude * sin(2 * .pi * frequency * Double(n) / sampleRate + phase))
        }
    }

    func testIntersamplePeakOnQuarterRate() {
        // fs/4 s fází π/4: vzorky střídají ±0,707, vlna jde do 1,0.
        let samples = sine(frequency: 12_000, sampleRate: 48_000, seconds: 0.1,
                           phase: .pi / 4)
        var meter = TruePeakMeter()
        meter.addInterleaved(samples)
        XCTAssertEqual(meter.samplePeak, 0.7072, accuracy: 0.001,
                       "vzorky vidí jen 0,707")
        XCTAssertEqual(meter.linearPeak, 1.0, accuracy: 0.02,
                       "true peak vidí celou vlnu")
        XCTAssertEqual(meter.decibelsTruePeak, 0, accuracy: 0.2)
    }

    func testLowFrequencySineIsUnchanged() {
        // 997 Hz na 48 kHz: mezivzorkové špičky zanedbatelné — true peak
        // ≈ špička vzorků ≈ amplituda.
        let samples = sine(frequency: 997, sampleRate: 48_000, seconds: 0.5,
                           amplitude: 0.5)
        var meter = TruePeakMeter()
        meter.addInterleaved(samples)
        XCTAssertEqual(meter.linearPeak, 0.5, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(meter.linearPeak, meter.samplePeak - 1e-9)
    }

    func testSilence() {
        var meter = TruePeakMeter()
        meter.addInterleaved([Float](repeating: 0, count: 4_800))
        XCTAssertEqual(meter.linearPeak, 0)
        XCTAssertEqual(meter.decibelsTruePeak, -120)
    }

    func testTruePeakNeverBelowSamplePeak() {
        var state: UInt64 = 21
        let noise = (0..<48_000).map { _ -> Float in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(Double(state % 2_000_001) / 1_000_000.0 - 1.0) * 0.8
        }
        var meter = TruePeakMeter()
        meter.addInterleaved(noise)
        XCTAssertGreaterThanOrEqual(meter.linearPeak, meter.samplePeak - 1e-9)
    }

    func testStreamingMatchesOneShot() {
        let samples = sine(frequency: 11_997, sampleRate: 48_000, seconds: 0.2,
                           phase: .pi / 5)
        var oneShot = TruePeakMeter()
        oneShot.addInterleaved(samples)
        var chunked = TruePeakMeter()
        var start = 0
        var step = 7
        while start < samples.count {
            let end = min(start + step, samples.count)
            chunked.addInterleaved(Array(samples[start..<end]))
            start = end
            step = step == 7 ? 501 : 7   // nepravidelné kusy
        }
        XCTAssertEqual(oneShot.linearPeak, chunked.linearPeak, accuracy: 1e-12)
    }

    func testStereoFindsPeakInEitherChannel() {
        // Levý kanál tichý nízký tón, pravý mezivzorkově špičkující.
        let left = sine(frequency: 200, sampleRate: 48_000, seconds: 0.1,
                        amplitude: 0.1)
        let right = sine(frequency: 12_000, sampleRate: 48_000, seconds: 0.1,
                         phase: .pi / 4)
        var interleaved = [Float]()
        for i in 0..<left.count {
            interleaved.append(left[i])
            interleaved.append(right[i])
        }
        var meter = TruePeakMeter(channelCount: 2)
        meter.addInterleaved(interleaved)
        XCTAssertEqual(meter.linearPeak, 1.0, accuracy: 0.02,
                       "špičku v pravém kanále nesmí rozředit levý")
    }
}
