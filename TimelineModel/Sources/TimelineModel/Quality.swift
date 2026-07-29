//
//  Quality.swift
//  TimelineModel — Projekt Krása
//
//  Analýzy kvality záběrů (fáze 15): NÁVRHOVÁ vrstva. Model umí spočítat
//  ostrost obrazu, klasifikovat vzorky a promítnout problémová místa na
//  klipy — nikdy nic sám nestříhá ani nemaže (rozhodnutí plánu).
//
//  Vzorky patří ASSETU a jsou kotvené ve ZDROJOVÉM čase (jako přepis a
//  doby hudby), ale do projektového souboru se NEUKLÁDAJÍ — jsou levně
//  spočitatelné a drží je disková cache otiskem souboru (vzorec vln,
//  `SharpnessStore` v aplikaci). Model je dostává parametrem.
//
//  Klasifikace je RELATIVNÍ k mediánu skóre assetu: absolutní prahy
//  nefungují, ostrost se mezi kamerami a scénami liší o řády. Pohybové
//  rozmazání se řeší KONZERVATIVNĚ nastavitelnou citlivostí — žádná
//  chytristika (plán F15).
//

import Foundation

// MARK: - Typy

/// Jeden vzorek ostrosti: rozptyl Laplaciánu v čase zdroje.
public struct SharpnessSample: Hashable, Codable, Sendable {
    public let time: Double
    public let score: Double
    public init(time: Double, score: Double) {
        self.time = time
        self.score = score
    }
}

/// Semafor kvality — zelená se nekreslí (ticho je dobrá zpráva),
/// oranžová a červená se ukazují na klipu.
public enum QualityLevel: Int, Hashable, Comparable, Sendable {
    case good = 0
    case soft = 1
    case bad = 2
    public static func < (a: QualityLevel, b: QualityLevel) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// Problémový úsek promítnutý NA OSU (absolutní snímky, uvnitř klipu).
public struct QualitySegment: Hashable, Sendable {
    public let start: Frames
    public let end: Frames
    public let level: QualityLevel
}

// MARK: - Metrika

public enum SharpnessMetric {

    /// Rozptyl Laplaciánu na luma mřížce — klasická míra ostrosti:
    /// ostré hrany dávají Laplaciánu velké výkyvy, rozmazané malé.
    /// Krajní pixely se vynechávají (jádro 3×3 potřebuje sousedy).
    public static func laplacianVariance(luma: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2, luma.count >= width * height else { return 0 }
        var sum = 0.0
        var sumOfSquares = 0.0
        let count = Double((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let laplacian = 4 * Int(luma[i])
                    - Int(luma[i - 1]) - Int(luma[i + 1])
                    - Int(luma[i - width]) - Int(luma[i + width])
                let value = Double(laplacian)
                sum += value
                sumOfSquares += value * value
            }
        }
        let mean = sum / count
        return sumOfSquares / count - mean * mean
    }
}

// MARK: - Klasifikace a promítnutí

extension Project {

    /// Prahy z citlivosti (0–1, výchozí 0,5): měkký práh je zlomek mediánu
    /// skóre assetu 0,3–0,7, tvrdý jeho polovina. Vyšší citlivost = víc
    /// nahlášených míst. Vzorec je schválně jednoduchý a čitelný —
    /// konzervativní návrhy, ne chytristika.
    static func qualityThresholds(sensitivity: Double) -> (soft: Double, bad: Double) {
        let s = min(max(sensitivity, 0), 1)
        let soft = 0.3 + 0.4 * s
        return (soft, soft * 0.5)
    }

    /// Problémové úseky ostrosti na klipech obrazových stop.
    ///
    /// - Parameters:
    ///   - samples: vzorky per asset (z cache aplikace; model je neukládá)
    ///   - sensitivity: 0–1, viz `qualityThresholds`
    ///   - minimumDuration: kratší úseky se zahazují — jednosnímkový
    ///     zákmit (projíždějící objekt) není vada záběru
    public func qualityMarks(samples: [AssetID: [SharpnessSample]],
                             sensitivity: Double = 0.5,
                             minimumDuration: Double = 0.5) -> [ClipID: [QualitySegment]] {
        var out: [ClipID: [QualitySegment]] = [:]
        let thresholds = Self.qualityThresholds(sensitivity: sensitivity)

        for track in timeline.tracks where track.kind == .video {
            for clip in track.clips {
                guard let assetSamples = samples[clip.assetID],
                      assetSamples.count >= 2 else { continue }

                // Medián PŘES CELÝ asset — nezávisí na trimu, takže se
                // klasifikace klipu nemění tím, jak je střižený.
                let sorted = assetSamples.map(\.score).sorted()
                let median = sorted[sorted.count / 2]
                guard median > 0 else { continue }   // tma/jednolitost — nic nehlásit

                let windowStart = clip.sourceStart.seconds
                let windowEnd = (clip.sourceStart + sourceConsumption(of: clip)).seconds

                func level(of score: Double) -> QualityLevel {
                    if score < median * thresholds.bad { return .bad }
                    if score < median * thresholds.soft { return .soft }
                    return .good
                }

                // Souvislé běhy stejné úrovně; konec běhu = čas prvního
                // vzorku jiné úrovně (nebo konec okna).
                var segments: [QualitySegment] = []
                var runLevel: QualityLevel = .good
                var runStart = windowStart

                func close(at time: Double) {
                    guard runLevel != .good,
                          time - runStart >= minimumDuration else { return }
                    let startFrame = clip.timelineStart + frameOffset(
                        forSource: SourceTime(seconds: max(runStart, windowStart)), in: clip)
                    let endFrame = clip.timelineStart + frameOffset(
                        forSource: SourceTime(seconds: min(time, windowEnd)), in: clip)
                    guard endFrame > startFrame else { return }
                    segments.append(QualitySegment(start: startFrame,
                                                   end: min(endFrame, clip.timelineEnd),
                                                   level: runLevel))
                }

                for sample in assetSamples {
                    guard sample.time >= windowStart, sample.time < windowEnd else { continue }
                    let sampleLevel = level(of: sample.score)
                    if sampleLevel != runLevel {
                        close(at: sample.time)
                        runLevel = sampleLevel
                        runStart = sample.time
                    }
                }
                close(at: windowEnd)

                if !segments.isEmpty { out[clip.id] = segments }
            }
        }
        return out
    }
}
