//
//  BeatDetector.swift
//  Projekt AIditor — AudioEngine (fáze 14)
//
//  Detekce dob hudebního podkladu, plán F14 modul 1:
//
//  1. ONSET OBÁLKA — signál po rámcích (Hann, vlastní FFT), detekční
//     funkce = spektrální tok (půlvlnně usměrněný nárůst magnitud) +
//     nárůst energie, obojí normalizované. Tok vidí i změny bez nárůstu
//     hlasitosti (nové tóny), energie zase tupé údery basy.
//  2. TEMPO — autokorelace obálky (přes vlastní FFT), v mezích
//     minBPM–maxBPM, s mírnou preferencí běžných temp okolo 120 BPM
//     (autokorelace klikové stopy má stejná maxima na násobcích periody
//     — preference vybírá hudebně pravděpodobnou oktávu). Parabolická
//     interpolace vrcholu pro jemnost pod rozlišení rámce.
//  3. FÁZE — posun mřížky, který posbírá největší součet obálky.
//  4. ZPŘESNĚNÍ — lineární regrese časů onsetů proti indexům dob
//     (jen onsety blízko předpovědi — hudba má i onsety mimo doby).
//     Autokorelace dává rozlišení rámce (~11 ms); regrese přes desítky
//     dob stáhne chybu tempa o řád níž. Bez ní by mřížka na konci
//     tříminutové skladby ujížděla o desítky milisekund.
//
//  Vstup je mono [Float] — převzorkování a mix kanálů je věc volajícího
//  (týž kontrakt jako `WaveformSync`).
//

import Foundation

/// Jeden detekovaný nástup (úder, začátek tónu).
public struct Onset: Hashable, Sendable {
    public let time: Double
    /// Síla v jednotkách detekční funkce (relativní; k řazení, ne k měření).
    public let strength: Double
}

public enum BeatDetector {

    // MARK: - Veřejné rozhraní

    /// Najde mřížku dob. `nil`, když signál nemá zřetelnou pulzaci
    /// (jistota pod prahem), je moc krátký, nebo parametry nedávají smysl.
    public static func analyze(samples: [Float],
                               sampleRate: Double,
                               minBPM: Double = 60,
                               maxBPM: Double = 180) -> BeatGrid? {
        guard sampleRate > 0, minBPM > 0, maxBPM > minBPM else { return nil }
        let envelope = onsetEnvelope(samples: samples, sampleRate: sampleRate)
        guard envelope.odf.count >= 32 else { return nil }

        guard let tempo = estimateTempo(odf: envelope.odf,
                                        hopSeconds: envelope.hopSeconds,
                                        minBPM: minBPM, maxBPM: maxBPM) else { return nil }

        let phase = estimatePhase(envelope: envelope, period: tempo.period)
        var grid = BeatGrid(bpm: 60.0 / tempo.period,
                            firstBeatTime: phase,
                            confidence: tempo.confidence)

        // Zpřesnění regresí přes onsety — viz hlavička souboru.
        let detected = pickOnsets(envelope: envelope)
        if let refined = refine(grid: grid, onsets: detected) {
            grid = refined
        }
        return grid
    }

    /// Detekované nástupy — pro značky v UI a pro testy. Tatáž obálka
    /// jako u `analyze`.
    public static func onsets(samples: [Float], sampleRate: Double) -> [Onset] {
        pickOnsets(envelope: onsetEnvelope(samples: samples, sampleRate: sampleRate))
    }

    // MARK: - Onset obálka

    struct OnsetEnvelope {
        /// Detekční funkce; `odf[j]` popisuje nárůst mezi rámci j a j+1.
        let odf: [Double]
        let hopSeconds: Double
        /// Čas hodnoty `odf[j]` = `Double(j) * hopSeconds + timeOffset`.
        let timeOffset: Double
    }

    static func onsetEnvelope(samples: [Float], sampleRate: Double) -> OnsetEnvelope {
        // ~21 ms okno → 1024 vzorků na 48 kHz; poloviční krok.
        let window = FFT.nextPowerOfTwo(max(256, Int(sampleRate * 0.021)))
        let hop = window / 2
        let hopSeconds = Double(hop) / sampleRate
        guard samples.count >= window * 2 else {
            return OnsetEnvelope(odf: [], hopSeconds: hopSeconds, timeOffset: 0)
        }

        var hann = [Double](repeating: 0, count: window)
        for i in 0..<window {
            hann[i] = 0.5 - 0.5 * cos(2.0 * .pi * Double(i) / Double(window - 1))
        }

        let bins = window / 2
        var flux: [Double] = []
        var energyRise: [Double] = []
        var previousMagnitudes: [Double]?
        var previousEnergy = 0.0

        var start = 0
        while start + window <= samples.count {
            var real = [Double](repeating: 0, count: window)
            var imag = [Double](repeating: 0, count: window)
            for i in 0..<window {
                real[i] = Double(samples[start + i]) * hann[i]
            }
            FFT.transform(real: &real, imag: &imag)

            var magnitudes = [Double](repeating: 0, count: bins)
            var energy = 0.0
            for k in 0..<bins {
                let magnitude = (real[k] * real[k] + imag[k] * imag[k]).squareRoot()
                magnitudes[k] = magnitude
                energy += magnitude * magnitude
            }

            if let previous = previousMagnitudes {
                var sum = 0.0
                for k in 0..<bins {
                    let difference = magnitudes[k] - previous[k]
                    if difference > 0 { sum += difference }
                }
                flux.append(sum)
                energyRise.append(max(0, energy - previousEnergy))
            }
            previousMagnitudes = magnitudes
            previousEnergy = energy
            start += hop
        }

        // Součet obou složek, každá normalizovaná na jednotkové maximum —
        // jinak by energie (kvadratická) tok úplně přehlušila.
        let maxFlux = flux.max() ?? 0
        let maxRise = energyRise.max() ?? 0
        var odf = [Double](repeating: 0, count: flux.count)
        for i in flux.indices {
            if maxFlux > 0 { odf[i] += flux[i] / maxFlux }
            if maxRise > 0 { odf[i] += energyRise[i] / maxRise }
        }

        // `odf[j]` je rozdíl rámců se začátky j·hop a (j+1)·hop — nárůst
        // se děje někde uvnitř druhého rámce; jako čas se bere jeho střed.
        let timeOffset = (Double(hop) + Double(window) / 2) / sampleRate
        return OnsetEnvelope(odf: odf, hopSeconds: hopSeconds, timeOffset: timeOffset)
    }

    // MARK: - Tempo

    struct TempoEstimate {
        let period: Double
        let confidence: Double
    }

    static func estimateTempo(odf: [Double], hopSeconds: Double,
                              minBPM: Double, maxBPM: Double) -> TempoEstimate? {
        var zeroMean = odf
        WaveformSync.subtractMean(&zeroMean)
        let correlation = FFT.crossCorrelation(zeroMean, zeroMean)
        let zeroIndex = zeroMean.count - 1
        let energy = correlation[zeroIndex]
        guard energy > 0 else { return nil }

        let minLag = max(1, Int((60.0 / maxBPM / hopSeconds).rounded(.down)))
        let maxLag = min(zeroMean.count - 1, Int((60.0 / minBPM / hopSeconds).rounded(.up)))
        guard maxLag > minLag else { return nil }

        // Mírná log-normální preference okolo 120 BPM: autokorelace má
        // stejná maxima na 1×, 2×, 3× periody (všechno jsou „pravdivá"
        // tempa) — váha vybírá hudebně pravděpodobné. σ ≈ 0,7 oktávy,
        // ať v mezích nic nezakáže, jen rozhodne remízu.
        func weight(_ bpm: Double) -> Double {
            let octaves = log2(bpm / 120.0)
            return exp(-0.5 * (octaves / 0.7) * (octaves / 0.7))
        }

        var bestLag = 0
        var bestScore = -Double.infinity
        var bestRaw = 0.0
        for lag in minLag...maxLag {
            let raw = correlation[zeroIndex + lag] / energy
            let score = raw * weight(60.0 / (Double(lag) * hopSeconds))
            if score > bestScore {
                bestScore = score
                bestLag = lag
                bestRaw = raw
            }
        }
        // Šum nemá periodu: normalizovaná autokorelace se drží u nuly.
        guard bestRaw >= 0.15 else { return nil }

        // Parabolická interpolace vrcholu — jemnost pod rozlišení rámce.
        var refinedLag = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let left = correlation[zeroIndex + bestLag - 1]
            let mid = correlation[zeroIndex + bestLag]
            let right = correlation[zeroIndex + bestLag + 1]
            let denominator = left - 2 * mid + right
            if abs(denominator) > 1e-12 {
                let delta = 0.5 * (left - right) / denominator
                if abs(delta) < 1 { refinedLag += delta }
            }
        }
        return TempoEstimate(period: refinedLag * hopSeconds,
                             confidence: max(0, min(1, bestRaw)))
    }

    // MARK: - Fáze

    /// Posun mřížky (0 ≤ fáze < perioda), který posbírá největší průměr
    /// obálky — doby mají ležet na energii, ne vedle ní.
    static func estimatePhase(envelope: OnsetEnvelope, period: Double) -> Double {
        let periodFrames = period / envelope.hopSeconds
        let offsets = max(1, Int(periodFrames.rounded(.down)))
        var bestOffset = 0
        var bestScore = -Double.infinity
        for offset in 0..<offsets {
            var score = 0.0
            var count = 0
            var position = Double(offset)
            while true {
                let index = Int(position.rounded())
                guard index < envelope.odf.count else { break }
                score += envelope.odf[index]
                count += 1
                position += periodFrames
            }
            guard count > 0 else { continue }
            score /= Double(count)
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
        }
        return Double(bestOffset) * envelope.hopSeconds + envelope.timeOffset
    }

    // MARK: - Onsety (výběr vrcholů)

    static func pickOnsets(envelope: OnsetEnvelope) -> [Onset] {
        let odf = envelope.odf
        guard !odf.isEmpty, let globalMax = odf.max(), globalMax > 0 else { return [] }
        let neighborhood = 3
        let meanWindow = 20
        let floorValue = 0.1 * globalMax
        let minSeparation = 0.06

        var result: [Onset] = []
        for i in odf.indices {
            let value = odf[i]
            guard value >= floorValue else { continue }
            // Lokální maximum…
            let lowNeighbor = max(0, i - neighborhood)
            let highNeighbor = min(odf.count - 1, i + neighborhood)
            guard value >= odf[lowNeighbor...highNeighbor].max()! else { continue }
            // …nad lokálním průměrem (adaptivní práh — hlasitá pasáž
            // nemá pohltit tichou).
            let lowMean = max(0, i - meanWindow)
            let highMean = min(odf.count - 1, i + meanWindow)
            let mean = odf[lowMean...highMean].reduce(0, +) / Double(highMean - lowMean + 1)
            guard value > 1.3 * mean else { continue }

            let time = Double(i) * envelope.hopSeconds + envelope.timeOffset
            if let last = result.last, time - last.time < minSeparation {
                if value > last.strength {
                    result[result.count - 1] = Onset(time: time, strength: value)
                }
                continue
            }
            result.append(Onset(time: time, strength: value))
        }
        return result
    }

    // MARK: - Zpřesnění regresí

    /// Přiřadí onsety nejbližším dobám mřížky (jen ty do 15 % periody —
    /// hudba má i onsety mimo doby) a metodou nejmenších čtverců doladí
    /// periodu i fázi: t ≈ fáze + perioda·index. Dvě kola — po prvním
    /// zpřesnění se přiřazení může změnit.
    static func refine(grid: BeatGrid, onsets: [Onset]) -> BeatGrid? {
        guard onsets.count >= 4 else { return nil }
        var period = grid.beatInterval
        var phase = grid.firstBeatTime

        for _ in 0..<2 {
            var pairs: [(index: Double, time: Double)] = []
            for onset in onsets {
                let beatIndex = ((onset.time - phase) / period).rounded()
                guard beatIndex >= 0 else { continue }
                let predicted = phase + beatIndex * period
                guard abs(onset.time - predicted) <= 0.15 * period else { continue }
                pairs.append((beatIndex, onset.time))
            }
            // Regrese chce rozptyl indexů — tři doby jsou málo na důvěru.
            guard pairs.count >= 4 else { return nil }

            let n = Double(pairs.count)
            let sumX = pairs.reduce(0) { $0 + $1.index }
            let sumY = pairs.reduce(0) { $0 + $1.time }
            let sumXX = pairs.reduce(0) { $0 + $1.index * $1.index }
            let sumXY = pairs.reduce(0) { $0 + $1.index * $1.time }
            let denominator = n * sumXX - sumX * sumX
            guard abs(denominator) > 1e-12 else { return nil }
            let slope = (n * sumXY - sumX * sumY) / denominator
            let intercept = (sumY - slope * sumX) / n
            // Regrese nesmí utéct od odhadu autokorelace — jinak ji
            // stáhla odlehlá přiřazení.
            guard abs(slope - period) < 0.1 * period else { return nil }
            period = slope
            phase = intercept
        }

        var refined = grid
        refined.bpm = 60.0 / period
        refined.firstBeatTime = phase
        // Fáze z regrese může vyjít lehce záporná (obálka předbíhá) —
        // mřížka začíná v signálu, posunout o celé doby dopředu.
        while refined.firstBeatTime < 0 { refined.firstBeatTime += period }
        return refined
    }
}
