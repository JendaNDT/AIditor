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

// MARK: - Ticho a prázdno (fáze 15, modul 2)

/// Vzorek „hluchosti": hlasitost + tři obrazové signály v čase zdroje.
/// Pohyb se vklasifikaci v1 NEPOUŽÍVÁ (kapesní záběr se hýbe, dekorace
/// stojí — pohyb hluchost neurčuje ani jedním směrem), ale měří se a
/// ukládá: ladění prahů ho jednou může chtít a přepočítávat cache kvůli
/// tomu by byla škoda.
public struct EmptinessSample: Hashable, Codable, Sendable {
    public let time: Double
    /// RMS hlasitost v dBFS; soubor bez zvukové stopy dává −120 (ticho).
    public let loudnessDB: Double
    /// Střední luma 0–255.
    public let brightness: Double
    /// Entropie histogramu luma, 0–8 bitů.
    public let entropy: Double
    /// Střední |rozdíl| proti předchozímu vzorku, 0–255.
    public let motion: Double

    public init(time: Double, loudnessDB: Double, brightness: Double,
                entropy: Double, motion: Double) {
        self.time = time
        self.loudnessDB = loudnessDB
        self.brightness = brightness
        self.entropy = entropy
        self.motion = motion
    }
}

/// Hluchý úsek promítnutý na osu — binární, žádné úrovně: buď je co
/// stříhat, nebo ne. Rozhodnutí zůstává na uživateli (návrhová vrstva).
public struct EmptySegment: Hashable, Sendable {
    public let start: Frames
    public let end: Frames
}

/// Čisté obrazové statistiky pro vzorkovače — v modelu kvůli testům
/// (aplikace je volá nad podvzorkovanou luma rovinou).
public enum LumaStats {

    public static func brightness(luma: [UInt8]) -> Double {
        guard !luma.isEmpty else { return 0 }
        return Double(luma.reduce(0) { $0 + Int($1) }) / Double(luma.count)
    }

    /// Shannonova entropie histogramu, v bitech (0 = jednolitá plocha,
    /// 8 = dokonale rozprostřené hodnoty).
    public static func entropy(luma: [UInt8]) -> Double {
        guard !luma.isEmpty else { return 0 }
        var histogram = [Int](repeating: 0, count: 256)
        for value in luma { histogram[Int(value)] += 1 }
        let total = Double(luma.count)
        var bits = 0.0
        for count in histogram where count > 0 {
            let p = Double(count) / total
            bits -= p * log2(p)
        }
        return bits
    }

    /// Střední absolutní rozdíl dvou stejně velkých mřížek (pohyb).
    public static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count)
    }
}

extension Project {

    /// Prahy hluchosti z citlivosti 0–1: ticho pod −50…−40 dBFS, tma pod
    /// jas 30–50, prázdno pod entropii 3–4 bity. Konzervativní a čitelné.
    static func emptinessThresholds(sensitivity: Double)
        -> (quietDB: Double, darkLuma: Double, lowEntropy: Double) {
        let s = min(max(sensitivity, 0), 1)
        return (-50 + 10 * s, 30 + 20 * s, 3 + s)
    }

    /// Hluchá místa na klipech obrazových stop: TICHO **a zároveň**
    /// prázdný obraz (tma NEBO nízká entropie). Tichý statický záběr na
    /// dekoraci není chyba — je ostrý, prosvětlený a bohatý, obrazový
    /// test jím neprojde (rozhodnutí plánu F15: kombinovat oba signály,
    /// nikdy nehlásit jen z ticha).
    ///
    /// Minimální délka úseku výchozích 5 s (plán: 3–10) — hluché místo
    /// je NUDA, ne mezera mezi dvěma větami.
    public func emptinessMarks(samples: [AssetID: [EmptinessSample]],
                               sensitivity: Double = 0.5,
                               minimumDuration: Double = 5) -> [ClipID: [EmptySegment]] {
        var out: [ClipID: [EmptySegment]] = [:]
        let thresholds = Self.emptinessThresholds(sensitivity: sensitivity)

        for track in timeline.tracks where track.kind == .video {
            for clip in track.clips {
                guard let assetSamples = samples[clip.assetID],
                      assetSamples.count >= 2 else { continue }

                let windowStart = clip.sourceStart.seconds
                let windowEnd = (clip.sourceStart + sourceConsumption(of: clip)).seconds

                func isEmpty(_ sample: EmptinessSample) -> Bool {
                    sample.loudnessDB < thresholds.quietDB
                        && (sample.brightness < thresholds.darkLuma
                            || sample.entropy < thresholds.lowEntropy)
                }

                var segments: [EmptySegment] = []
                var runStart: Double?

                func close(at time: Double) {
                    guard let start = runStart else { return }
                    runStart = nil
                    guard time - start >= minimumDuration else { return }
                    let startFrame = clip.timelineStart + frameOffset(
                        forSource: SourceTime(seconds: max(start, windowStart)), in: clip)
                    let endFrame = clip.timelineStart + frameOffset(
                        forSource: SourceTime(seconds: min(time, windowEnd)), in: clip)
                    guard endFrame > startFrame else { return }
                    segments.append(EmptySegment(start: startFrame,
                                                 end: min(endFrame, clip.timelineEnd)))
                }

                for sample in assetSamples {
                    guard sample.time >= windowStart, sample.time < windowEnd else { continue }
                    if isEmpty(sample) {
                        if runStart == nil { runStart = sample.time }
                    } else {
                        close(at: sample.time)
                    }
                }
                close(at: windowEnd)

                if !segments.isEmpty { out[clip.id] = segments }
            }
        }
        return out
    }
}
