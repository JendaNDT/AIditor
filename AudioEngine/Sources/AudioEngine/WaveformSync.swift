//
//  WaveformSync.swift
//  Projekt AIditor — AudioEngine (fáze 7)
//
//  Synchronizace dvou nahrávek téže události (zvuk kamery × klopový
//  rekordér) křížovou korelací — spec 7.2. Dvoustupňově:
//
//  1. HRUBĚ na energetických obálkách (RMS na okno, výchozí 200 Hz).
//     Obálka je robustní vůči rozdílným mikrofonům, gainu i barvě zvuku
//     — koreluje se „kdy se dělo něco hlasitého", ne průběh vlny. A je
//     to tisíckrát méně dat než vzorky, takže FFT korelace hodinové
//     nahrávky je otázka sekund.
//  2. JEMNĚ na syrových vzorcích v okolí hrubého odhadu (±1 obálkový
//     bin, výřez ~10 s) — doladí posun na vzorky, tedy hluboko pod
//     jeden snímek obrazu.
//
//  Míra jistoty je normalizovaný korelační koeficient obálek (0–1).
//  Nesouvisející nahrávky dávají hodnoty u nuly — volající podle toho
//  pozná, že „shoda" je náhoda, a nemá ji mlčky použít.
//

import Foundation

public enum WaveformSync {

    public struct Match {
        /// Kam na časovou osu REFERENCE patří začátek kandidáta,
        /// v sekundách. Kladná hodnota: kandidát (rekordér) začal
        /// nahrávat POZDĚJI než reference a jeho soubor se pokládá
        /// doprostřed; záporná: začal dřív a přečnívá před začátek.
        public let offsetSeconds: Double
        /// Normalizovaná korelace obálek v nalezeném posunu, 0–1.
        /// Souvisící nahrávky dávají vysoké hodnoty (testy: > 0,6
        /// i při silném šumu), nesouvisející se drží u nuly.
        public let confidence: Double
    }

    /// Najde časový posun kandidáta vůči referenci. `nil`, když je
    /// některá nahrávka kratší než pár obálkových oken — na tak krátkém
    /// signálu není co korelovat.
    ///
    /// - Parameters:
    ///   - reference: mono vzorky (typicky zvuk kamery)
    ///   - candidate: mono vzorky (typicky klopový rekordér)
    ///   - sampleRate: společná vzorkovací frekvence obou signálů —
    ///     PŘEVZORKOVÁNÍ NA SPOLEČNOU frekvenci je věc volajícího
    ///   - envelopeRate: hrubost obálky v binech za sekundu
    public static func offset(reference: [Float],
                              candidate: [Float],
                              sampleRate: Double,
                              envelopeRate: Double = 200) -> Match? {
        guard sampleRate > 0, envelopeRate > 0, envelopeRate <= sampleRate else { return nil }
        let window = max(1, Int((sampleRate / envelopeRate).rounded()))

        var envelopeA = envelope(reference, window: window)
        var envelopeB = envelope(candidate, window: window)
        guard envelopeA.count >= 4, envelopeB.count >= 4 else { return nil }

        // Odečíst střední hodnotu — jinak korelaci ovládne stejnosměrná
        // složka (obálky jsou nezáporné) a vyhraje střed překryvu.
        subtractMean(&envelopeA)
        subtractMean(&envelopeB)

        let correlation = FFT.crossCorrelation(envelopeA, envelopeB)
        guard let peakIndex = correlation.indices.max(by: { correlation[$0] < correlation[$1] })
        else { return nil }

        let energyA = envelopeA.reduce(0) { $0 + $1 * $1 }
        let energyB = envelopeB.reduce(0) { $0 + $1 * $1 }
        guard energyA > 0, energyB > 0 else { return nil }   // samé ticho
        let confidence = max(0, min(1, correlation[peakIndex] / (energyA * energyB).squareRoot()))

        // corr[lag] = Σ envA[i+lag]·envB[i]: kladný lag říká, že obsah
        // kandidáta sedí `lag` binů ZA začátkem reference.
        let coarseLag = peakIndex - (envelopeB.count - 1)
        let refined = refine(reference: reference, candidate: candidate,
                             coarseLagSamples: coarseLag * window,
                             searchRadius: window)
        return Match(offsetSeconds: Double(refined) / sampleRate, confidence: confidence)
    }

    // MARK: - Stavební díly (interní, testované zvlášť)

    /// RMS obálka: odmocnina střední energie na okno. Zbytek kratší než
    /// okno se zahazuje.
    static func envelope(_ samples: [Float], window: Int) -> [Double] {
        guard window > 0, samples.count >= window else { return [] }
        var result = [Double]()
        result.reserveCapacity(samples.count / window)
        var start = 0
        while start + window <= samples.count {
            var sum = 0.0
            for i in start..<(start + window) {
                let value = Double(samples[i])
                sum += value * value
            }
            result.append((sum / Double(window)).squareRoot())
            start += window
        }
        return result
    }

    static func subtractMean(_ values: inout [Double]) {
        guard !values.isEmpty else { return }
        let mean = values.reduce(0, +) / Double(values.count)
        for i in values.indices { values[i] -= mean }
    }

    /// Doladění na vzorky: přímá korelace syrových signálů v okolí
    /// hrubého odhadu. Prohledává se ±`searchRadius` vzorků; z překryvu
    /// se bere výřez nejvýš `refineSpanSeconds`, ať je to O(rozsah ×
    /// výřez), ne O(rozsah × celá nahrávka).
    static func refine(reference: [Float], candidate: [Float],
                       coarseLagSamples: Int, searchRadius: Int,
                       refineSpanSeconds spanSamples: Int = 480_000) -> Int {
        var bestLag = coarseLagSamples
        var bestScore = -Double.infinity

        for lag in (coarseLagSamples - searchRadius)...(coarseLagSamples + searchRadius) {
            // Překryv reference[i] × candidate[i − lag].
            let start = max(0, lag)
            let end = min(reference.count, candidate.count + lag)
            guard end > start else { continue }
            // Výřez ze středu překryvu — tam bývá signál, ne rozjezd.
            let span = min(end - start, spanSamples)
            let mid = start + (end - start - span) / 2
            var sum = 0.0
            for i in mid..<(mid + span) {
                sum += Double(reference[i]) * Double(candidate[i - lag])
            }
            // Normalizace délkou překryvu, ať kratší překryv nevyhrává
            // jen proto, že je kratší (u kladné korelace to nehrozí, ale
            // sčítají se i záporné hodnoty).
            let score = sum / Double(span)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        return bestLag
    }
}
