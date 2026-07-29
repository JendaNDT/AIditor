//
//  QualityTests.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 15, modul 1: metrika ostrosti a promítnutí problémových úseků.
//

import XCTest
@testable import TimelineModel

final class QualityTests: XCTestCase {

    // MARK: - Metrika

    /// Šachovnice — nejostřejší možný obraz (hrana na každém pixelu).
    private func checkerboard(width: Int, height: Int, cell: Int = 2) -> [UInt8] {
        (0..<(width * height)).map { i in
            let x = i % width, y = i / width
            return ((x / cell + y / cell) % 2 == 0) ? 235 : 16
        }
    }

    /// Trojúhelníkové rozostření šachovnice — dvojí klouzavý průměr
    /// po řádcích i sloupcích (deterministická náhrada Gaussova filtru).
    private func blurred(_ luma: [UInt8], width: Int, height: Int,
                         radius: Int) -> [UInt8] {
        var doubles = luma.map(Double.init)
        for _ in 0..<2 {
            var horizontal = doubles
            for y in 0..<height {
                for x in 0..<width {
                    var sum = 0.0, n = 0.0
                    for dx in -radius...radius where (0..<width).contains(x + dx) {
                        sum += doubles[y * width + x + dx]; n += 1
                    }
                    horizontal[y * width + x] = sum / n
                }
            }
            var vertical = horizontal
            for y in 0..<height {
                for x in 0..<width {
                    var sum = 0.0, n = 0.0
                    for dy in -radius...radius where (0..<height).contains(y + dy) {
                        sum += horizontal[(y + dy) * width + x]; n += 1
                    }
                    vertical[y * width + x] = sum / n
                }
            }
            doubles = vertical
        }
        return doubles.map { UInt8(min(255, max(0, $0.rounded()))) }
    }

    func testSharpBeatsBlurred() {
        let width = 64, height = 36
        let sharp = checkerboard(width: width, height: height)
        let soft = blurred(sharp, width: width, height: height, radius: 3)

        let sharpScore = SharpnessMetric.laplacianVariance(luma: sharp,
                                                           width: width, height: height)
        let softScore = SharpnessMetric.laplacianVariance(luma: soft,
                                                          width: width, height: height)
        XCTAssertGreaterThan(sharpScore, softScore * 5,
                             "rozostření musí skóre srazit řádově")
        XCTAssertGreaterThan(softScore, 0)
    }

    func testUniformImageScoresZero() {
        let flat = [UInt8](repeating: 128, count: 64 * 36)
        XCTAssertEqual(SharpnessMetric.laplacianVariance(luma: flat, width: 64, height: 36), 0)
    }

    func testDegenerateSizesScoreZero() {
        XCTAssertEqual(SharpnessMetric.laplacianVariance(luma: [1, 2], width: 2, height: 1), 0)
        XCTAssertEqual(SharpnessMetric.laplacianVariance(luma: [], width: 0, height: 0), 0)
    }

    // MARK: - Klasifikace a promítnutí

    /// Vzorky 3/s: skóre 100, s propadem na `dipScore` v [dipStart, dipEnd).
    private func samples(duration: Double, dip: (start: Double, end: Double, score: Double)?)
        -> [SharpnessSample] {
        stride(from: 0.0, to: duration, by: 1.0 / 3).map { t in
            if let dip, t >= dip.start, t < dip.end {
                return SharpnessSample(time: t, score: dip.score)
            }
            return SharpnessSample(time: t, score: 100)
        }
    }

    func testBlurDipBecomesBadSegment() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 300)   // celý 10s asset
        // Propad na 10 (pod tvrdý práh 100 × 0,25) mezi 4–6 s.
        let marks = f.project.qualityMarks(samples: [
            f.assetID: samples(duration: 10, dip: (4, 6, 10)),
        ])
        let segments = try XCTUnwrap(marks[clip])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].level, .bad)
        XCTAssertEqual(segments[0].start, Frames(120))   // 4 s × 30
        XCTAssertEqual(segments[0].end, Frames(180))     // 6 s × 30
    }

    func testSoftDipAndSensitivity() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 300)
        let dipped = samples(duration: 10, dip: (2, 4, 40))
        // Výchozí citlivost 0,5: měkký práh 100 × 0,5 → 40 je oranžová.
        let normal = f.project.qualityMarks(samples: [f.assetID: dipped])
        XCTAssertEqual(normal[clip]?.first?.level, .soft)
        // Citlivost 0: měkký práh 0,3 → 40 projde jako v pořádku.
        let tolerant = f.project.qualityMarks(samples: [f.assetID: dipped], sensitivity: 0)
        XCTAssertNil(tolerant[clip])
    }

    func testShortBlipIsIgnored() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 300)
        // Jediný nízký vzorek (běh 1/3 s) — projíždějící objekt, ne vada
        // záběru. Propad [4; 4,3) zasáhne jen vzorek na 4,0.
        let marks = f.project.qualityMarks(samples: [
            f.assetID: samples(duration: 10, dip: (4, 4.3, 10)),
        ])
        XCTAssertNil(marks[clip])
    }

    func testTrimmedClipGetsOnlyItsWindow() throws {
        var f = Fixture()
        // Klip [60, 210) na ose, zdroj od 2 s: okno zdroje [2, 7).
        let clip = Clip(assetID: f.assetID, timelineStart: Frames(60),
                        duration: Frames(150),
                        sourceStart: f.project.timeline.sourceTime(Frames(60)))
        try f.project.insert(clip, onTrack: f.v1)
        // Propad 4–6 s zdroje → na ose [60 + (4−2)·30, 60 + (6−2)·30) = [120, 180).
        let marks = f.project.qualityMarks(samples: [
            f.assetID: samples(duration: 10, dip: (4, 6, 10)),
        ])
        let segments = try XCTUnwrap(marks[clip.id])
        XCTAssertEqual(segments[0].start, Frames(120))
        XCTAssertEqual(segments[0].end, Frames(180))

        // Propad mimo okno klipu se nehlásí.
        let outside = f.project.qualityMarks(samples: [
            f.assetID: samples(duration: 10, dip: (8, 9.5, 10)),
        ])
        XCTAssertNil(outside[clip.id])
    }

    func testDarkAssetReportsNothing() throws {
        var f = Fixture()
        let clip = try f.addClip(start: 0, duration: 300)
        // Samá nula (tma): medián 0 → konzervativně žádné návrhy.
        let dark = stride(from: 0.0, to: 10, by: 1.0 / 3)
            .map { SharpnessSample(time: $0, score: 0) }
        XCTAssertNil(f.project.qualityMarks(samples: [f.assetID: dark])[clip])
    }
}
