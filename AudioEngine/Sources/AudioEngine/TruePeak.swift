//
//  TruePeak.swift
//  Projekt AIditor — AudioEngine (fáze 16)
//
//  True peak (dBTP): špička zvuku měřená na 4× převzorkovaném signálu
//  podle principu ITU-R BS.1770-4, Annex 2. Špička VZORKŮ mezivzorkové
//  špičky nevidí — sinus na čtvrtině vzorkovací frekvence s fází π/4 má
//  vzorky nejvýš 0,707, ale skutečná vlna jde do 1,0 (+3 dB). DA převodník
//  a ztrátové kodéry tu vlnu vyrobí, a „strop −1 dB" měřený vzorky pak
//  ve skutečnosti přetéká.
//
//  Převzorkování dělá polyfázový interpolátor: okénkovaný sinc (Hann,
//  12 taps na fázi, prototyp 48 taps), tři mezifáze mezi každými dvěma
//  vzorky. Koeficienty se POČÍTAJÍ, neopisují — týž princip jako
//  K-váhování (bilineární transformace místo tabulky) — a každá fáze se
//  normalizuje na jednotkový součet, aby stejnosměrný signál prošel
//  přesně. Správnost drží kotvy v testech: mezivzorková špička +3 dB,
//  nízkofrekvenční sinus beze změny, true peak ≥ špička vzorků.
//
//  Streamování: na mezihodnoty je potřeba i „budoucnost" (6 vzorků),
//  takže se měří se zpožděním kruhového bufferu; posledních ~6 vzorků
//  souboru se mezivzorkově nedoměří — u reálného zvuku (dojezdy do
//  ticha) bez významu.
//

import Foundation

public struct TruePeakMeter {

    /// Taps na fázi. 12 odpovídá 48-tap prototypu ze standardu.
    private static let taps = 12
    /// Interpolační fáze mezi dvěma vzorky (4× převzorkování = 3 mezifáze).
    private static let phases: [[Double]] = {
        (1...3).map { phase in
            let fraction = Double(phase) / 4.0
            let center = Double(taps / 2 - 1) + fraction   // mezi tapy 5 a 6
            var coefficients = (0..<taps).map { k -> Double in
                let t = Double(k) - center
                // sinc × Hannovo okno přes celý prototyp
                let sinc = t == 0 ? 1.0 : sin(.pi * t) / (.pi * t)
                let window = 0.5 + 0.5 * cos(.pi * t / Double(taps / 2))
                return sinc * window
            }
            let sum = coefficients.reduce(0, +)
            for i in coefficients.indices { coefficients[i] /= sum }
            return coefficients
        }
    }()

    private let channelCount: Int
    /// Kruhové okno posledních `taps` vzorků per kanál.
    private var windows: [[Double]]
    private var filled: [Int]

    private(set) public var linearPeak: Double = 0
    private(set) public var samplePeak: Double = 0

    public init(channelCount: Int = 1) {
        self.channelCount = max(1, channelCount)
        self.windows = Array(repeating: [Double](repeating: 0, count: Self.taps),
                             count: self.channelCount)
        self.filled = Array(repeating: 0, count: self.channelCount)
    }

    /// True peak v dBTP; ticho hlásí −120 (žádné −∞ do UI).
    public var decibelsTruePeak: Double {
        linearPeak > 0 ? max(-120, 20 * log10(linearPeak)) : -120
    }

    /// Prokládané vzorky (kanály střídavě, jako `LoudnessMeter`).
    public mutating func addInterleaved(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        for (index, sample) in samples.enumerated() {
            let channel = index % channelCount
            let value = Double(sample)
            let magnitude = abs(value)
            if magnitude > samplePeak { samplePeak = magnitude }
            if magnitude > linearPeak { linearPeak = magnitude }

            windows[channel].removeFirst()
            windows[channel].append(value)
            filled[channel] += 1
            guard filled[channel] >= Self.taps else { continue }

            let window = windows[channel]
            for coefficients in Self.phases {
                var interpolated = 0.0
                for k in 0..<Self.taps {
                    interpolated += window[k] * coefficients[k]
                }
                let level = abs(interpolated)
                if level > linearPeak { linearPeak = level }
            }
        }
    }

    /// Jednorázové měření mono signálu.
    public static func linearPeak(samples: [Float]) -> Double {
        var meter = TruePeakMeter(channelCount: 1)
        meter.addInterleaved(samples)
        return meter.linearPeak
    }
}
