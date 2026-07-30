//
//  LoudnessMeter.swift
//  Projekt AIditor — AudioEngine (fáze 7)
//
//  Integrovaná hlasitost podle ITU-R BS.1770-4 (na ní stojí EBU R128):
//  K-váhování → bloky 400 ms s krokem 100 ms → dvojité gatování
//  (absolutní práh −70 LKFS, relativní −10 LU pod průměrem přeživších).
//
//  Gatování je důvod, proč se hlasitost nedá měřit prostým RMS: svatební
//  film je z poloviny ticho mezi záběry a bez gate by ho normalizace
//  „dorovnala" zesílením řeči do řevu.
//
//  Kalibrační kotva ze standardu: full-scale sinus 997 Hz v jednom
//  kanálu čte −3,01 LKFS. Test to vymáhá.
//
//  Vstup jsou Float vzorky BEZ ořezu — 32-bit float zdroje (DJI Mic,
//  Zoom F3) smí nést hodnoty přes ±1 a metr s nimi počítá; ořez je věc
//  až finálního zápisu, ne měření.
//

import Foundation

public struct LoudnessMeter {

    public let sampleRate: Double
    public let channelCount: Int

    /// Váhy kanálů dle BS.1770: L, R, C plnou vahou, surroundy 1,41.
    /// LFE se do hlasitosti nepočítá vůbec — víc než 5 kanálů proto
    /// tenhle metr záměrně nebere (zdroje jsou mono/stereo z telefonů
    /// a rekordérů).
    private let weights: [Double]

    private var shelf: [Biquad]
    private var highPass: [Biquad]

    /// Délka podbloku 100 ms ve vzorcích. Blok = 4 podbloky (400 ms),
    /// krok 1 podblok = překryv 75 % podle standardu.
    private let subBlockLength: Int
    /// Rozpracovaný podblok: suma čtverců filtrovaného signálu na kanál.
    private var subBlockSquares: [Double]
    private var subBlockFilled = 0
    /// Vážené střední výkony uzavřených podbloků (přes kanály sečtené).
    private var subBlockPowers: [Double] = []

    public init(sampleRate: Double, channelCount: Int) {
        precondition(sampleRate > 0)
        precondition((1...5).contains(channelCount),
                     "metr je na mono až 5.0; LFE a vícekanál nepodporuje")
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        weights = Array([1.0, 1.0, 1.0, 1.41, 1.41].prefix(channelCount))

        let shelfCoefficients = KWeighting.shelf(sampleRate: sampleRate)
        let highPassCoefficients = KWeighting.highPass(sampleRate: sampleRate)
        shelf = (0..<channelCount).map { _ in Biquad(shelfCoefficients) }
        highPass = (0..<channelCount).map { _ in Biquad(highPassCoefficients) }

        subBlockLength = Int((sampleRate * 0.1).rounded())
        subBlockSquares = Array(repeating: 0, count: channelCount)
    }

    // MARK: Vstup

    /// Přidá vzorky po kanálech (`channels[kanál][vzorek]`, stejně
    /// dlouhé). Streamované volání po kusech dává tentýž výsledek jako
    /// jedno velké — vymáhá test.
    public mutating func add(_ channels: [[Float]]) {
        precondition(channels.count == channelCount)
        let length = channels[0].count
        precondition(channels.allSatisfy { $0.count == length },
                     "kanály musí být stejně dlouhé")

        var index = 0
        while index < length {
            let take = min(subBlockLength - subBlockFilled, length - index)
            for channel in 0..<channelCount {
                var sum = 0.0
                channels[channel].withUnsafeBufferPointer { buffer in
                    for i in index..<(index + take) {
                        let y = highPass[channel].process(
                            shelf[channel].process(Double(buffer[i])))
                        sum += y * y
                    }
                }
                subBlockSquares[channel] += sum
            }
            subBlockFilled += take
            index += take
            if subBlockFilled == subBlockLength { closeSubBlock() }
        }
    }

    /// Prokládané vzorky (LRLRLR…) — formát bufferů z AVFoundation.
    public mutating func addInterleaved(_ samples: [Float]) {
        precondition(samples.count % channelCount == 0)
        let frames = samples.count / channelCount
        var channels = Array(repeating: [Float](), count: channelCount)
        for channel in 0..<channelCount {
            channels[channel].reserveCapacity(frames)
            var i = channel
            while i < samples.count {
                channels[channel].append(samples[i])
                i += channelCount
            }
        }
        add(channels)
    }

    private mutating func closeSubBlock() {
        var power = 0.0
        for channel in 0..<channelCount {
            power += weights[channel] * subBlockSquares[channel] / Double(subBlockLength)
            subBlockSquares[channel] = 0
        }
        subBlockPowers.append(power)
        subBlockFilled = 0
    }

    // MARK: Výsledek

    /// Hlasitost z výkonu: −0,691 + 10·log₁₀(z). Ofset je ze standardu —
    /// kompenzuje zisk K-váhování tak, aby sinus 997 Hz vyšel přesně.
    private static func loudness(ofPower power: Double) -> Double {
        -0.691 + 10.0 * log10(power)
    }

    /// Integrovaná hlasitost v LUFS (LKFS — totéž číslo, dvě jména).
    /// `nil` = není co měřit: ticho, nebo signál kratší než jeden blok
    /// (400 ms). Neuzavřený zbytek posledního podbloku se zahazuje,
    /// přesně podle standardu.
    public var integrated: Double? {
        guard subBlockPowers.count >= 4 else { return nil }

        // Výkony bloků 400 ms = průměr čtyř sousedních podbloků.
        var blocks: [Double] = []
        blocks.reserveCapacity(subBlockPowers.count - 3)
        for i in 3..<subBlockPowers.count {
            blocks.append((subBlockPowers[i - 3] + subBlockPowers[i - 2]
                           + subBlockPowers[i - 1] + subBlockPowers[i]) / 4.0)
        }

        // Absolutní gate: pryč s bloky pod −70 LKFS.
        let absoluteThreshold = -70.0
        let aboveAbsolute = blocks.filter { Self.loudness(ofPower: $0) > absoluteThreshold }
        guard !aboveAbsolute.isEmpty else { return nil }

        // Relativní gate: −10 LU pod průměrem přeživších.
        let meanPower = aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)
        let relativeThreshold = Self.loudness(ofPower: meanPower) - 10.0
        let gated = aboveAbsolute.filter { Self.loudness(ofPower: $0) > relativeThreshold }
        guard !gated.isEmpty else { return nil }

        return Self.loudness(ofPower: gated.reduce(0, +) / Double(gated.count))
    }
}
