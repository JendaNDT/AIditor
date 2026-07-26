//
//  SpeechProbe.swift
//  Projekt Krása / Flatten
//
//  Rozpoznání řeči od ruchu podle charakteru amplitudové obálky.
//
//  Proč to potřebujeme: lupnutí na hranici segmentu je širokopásmový
//  transient, který se v širokopásmovém ruchu ztratí. Test lupanců má
//  smysl jen na materiálu s řečí — a který z pěti klipů to je, se
//  z metadat zjistit nedá.
//
//  Čím se řeč liší od ruchu:
//
//  1. MODULACE NA SLABIKOVÉ FREKVENCI. Řeč kolísá v hlasitosti zhruba
//     2–8× za sekundu (rychlost slabik). Vítr a ruch dvora takový výrazný
//     rytmus nemají — jejich modulační spektrum je plošší.
//  2. PAUZY. Mezi slovy a větami klesne energie skoro na nulu. Souvislý
//     ruch se drží kolem své střední hodnoty.
//  3. DYNAMIKA. Rozdíl mezi hlasitými a tichými místy je u řeči větší.
//
//  Je to HEURISTIKA, ne přepis. Rozhoduje poslech, tohle jen zúží výběr.
//

import AVFoundation
import Foundation
import ProbeKit

struct SpeechAnalysis {
    let url: URL
    let duration: Double
    /// Frekvence, na které je modulace obálky nejsilnější.
    let modulationPeakHz: Double
    /// Podíl energie modulace v pásmu 2–8 Hz (slabiky) z pásma 0,5–20 Hz.
    let syllableBandRatio: Double
    /// Podíl času pod prahem ticha. Pauzy mezi slovy.
    let pauseFraction: Double
    /// Rozdíl hlasitých a tichých míst v dB.
    let dynamicRangeDb: Double

    var name: String { url.lastPathComponent }

    /// Heuristika. Silná modulace ve slabikovém pásmu + znatelné pauzy.
    var looksLikeSpeech: Bool {
        syllableBandRatio >= 0.35 && pauseFraction >= 0.08 && dynamicRangeDb >= 18
    }

    /// Skóre na seřazení kandidátů. Vyšší = spíš řeč.
    var score: Double {
        syllableBandRatio * 100 + pauseFraction * 50 + min(dynamicRangeDb, 40)
    }
}

enum SpeechProbe {

    /// Na kolik Hz se obálka podvzorkuje před modulační analýzou.
    /// 100 Hz stačí — slabiková frekvence je pod 20 Hz.
    static let envelopeRate: Double = 100

    /// Práh ticha vůči hlasitým místům. −30 dB je pod úrovní pokojového
    /// ruchu, ale nad úrovní digitálního ticha.
    static let silenceThresholdDb: Double = -30

    static func analyze(url: URL) async throws -> SpeechAnalysis {
        let env = try await SyncProbe.loadEnvelope(url: url)
        let coarse = downsample(env.values, from: env.sampleRate, to: envelopeRate)
        guard coarse.count > 32 else {
            throw ProbeError.message("Stopa je příliš krátká na modulační analýzu.")
        }

        let spectrum = modulationSpectrum(coarse, rate: envelopeRate)
        let syllable = bandEnergy(spectrum, from: 2, to: 8)
        let total = bandEnergy(spectrum, from: 0.5, to: 20)
        let peak = spectrum.max(by: { $0.magnitude < $1.magnitude })?.frequency ?? 0

        let levels = coarse.map { 20 * log10(Double(max($0, 1e-6))) }
        let sorted = levels.sorted()
        let loud = percentile(sorted, 0.95)
        let quiet = percentile(sorted, 0.10)
        let threshold = loud + silenceThresholdDb
        let pauses = Double(levels.filter { $0 < threshold }.count) / Double(levels.count)

        return SpeechAnalysis(url: url,
                              duration: env.duration,
                              modulationPeakHz: peak,
                              syllableBandRatio: total > 0 ? syllable / total : 0,
                              pauseFraction: pauses,
                              dynamicRangeDb: loud - quiet)
    }

    // MARK: - Modulační spektrum

    struct Bin {
        let frequency: Double
        let magnitude: Double
    }

    /// Přímá DFT jen na frekvencích, které nás zajímají. Obálka je krátká
    /// (stovky až tisíce vzorků), takže plná FFT není potřeba.
    static func modulationSpectrum(_ signal: [Double], rate: Double) -> [Bin] {
        let mean = signal.reduce(0, +) / Double(signal.count)
        let centered = signal.map { $0 - mean }   // pryč se stejnosměrnou složkou
        let n = Double(centered.count)

        var bins: [Bin] = []
        var frequency = 0.5
        while frequency <= 20.0 {
            var real = 0.0, imaginary = 0.0
            let omega = 2 * Double.pi * frequency / rate
            for (index, value) in centered.enumerated() {
                let phase = omega * Double(index)
                real += value * cos(phase)
                imaginary -= value * sin(phase)
            }
            bins.append(Bin(frequency: frequency,
                            magnitude: (real * real + imaginary * imaginary).squareRoot() / n))
            frequency += 0.25
        }
        return bins
    }

    static func bandEnergy(_ spectrum: [Bin], from low: Double, to high: Double) -> Double {
        spectrum.filter { $0.frequency >= low && $0.frequency <= high }
                .reduce(0) { $0 + $1.magnitude * $1.magnitude }
    }

    // MARK: - Pomocné

    /// Podvzorkování obálky průměrem přes blok.
    static func downsample(_ values: [Float], from source: Double, to target: Double) -> [Double] {
        let factor = max(1, Int((source / target).rounded()))
        var result: [Double] = []
        result.reserveCapacity(values.count / factor + 1)

        var index = 0
        while index < values.count {
            let end = min(index + factor, values.count)
            var sum = 0.0
            for k in index..<end { sum += Double(values[k]) }
            result.append(sum / Double(end - index))
            index = end
        }
        return result
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))
        return sorted[index]
    }
}
