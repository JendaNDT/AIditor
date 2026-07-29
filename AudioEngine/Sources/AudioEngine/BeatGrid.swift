//
//  BeatGrid.swift
//  Projekt Krása — AudioEngine (fáze 14)
//
//  Mřížka dob hudebního podkladu: tempo, fáze (čas první doby) a takty.
//  Čistá matematika bez signálu — signál analyzuje `BeatDetector`, tahle
//  struktura jen odpovídá na „kde leží doby" a nese ruční korekce.
//
//  `Codable`, protože mřížka patří k assetu hudby a ukládá se do
//  projektového souboru (modul 2) — jako `Asset.transcript`.
//
//  Detekce taktů (která doba je „raz") se automaticky NEURČUJE — je to
//  nespolehlivé i pro velké systémy. Výchozí takt začíná první dobou
//  a uživatel ho posune ručně (`markDownbeat`), přesně podle plánu
//  „ruční korekce prvního taktu a násobku tempa".
//

import Foundation

public struct BeatGrid: Hashable, Codable, Sendable {

    /// Tempo v dobách za minutu.
    public var bpm: Double
    /// Čas doby s indexem 0, v sekundách od začátku analyzovaného
    /// signálu. Je to FÁZE mřížky (první doba mřížky od začátku), ne
    /// nutně první slyšitelný úder — hudba může začínat i předtaktím.
    public var firstBeatTime: Double
    /// Dob na takt. Výchozí 4 — svatební hudba je skoro vždy sudá;
    /// trojné metrum si uživatel přepne.
    public var beatsPerBar: Int
    /// Index doby (mod `beatsPerBar`), která je „raz". Ruční korekce
    /// přes `markDownbeat`.
    public var downbeatOffset: Int
    /// Jistota detekce 0–1 (normalizovaná autokorelace v nalezeném
    /// tempu). Nízká hodnota = mřížce nevěř a řekni to uživateli.
    public var confidence: Double

    public init(bpm: Double,
                firstBeatTime: Double,
                beatsPerBar: Int = 4,
                downbeatOffset: Int = 0,
                confidence: Double = 1.0) {
        self.bpm = bpm
        self.firstBeatTime = firstBeatTime
        self.beatsPerBar = max(1, beatsPerBar)
        self.downbeatOffset = downbeatOffset
        self.confidence = confidence
    }

    /// Délka jedné doby v sekundách.
    public var beatInterval: Double { 60.0 / bpm }

    // MARK: - Doby

    public struct Beat: Hashable, Sendable {
        public let index: Int
        public let time: Double
        /// Hlavní doba („raz" taktu) — kreslí se výrazněji a magnet
        /// ji může vážit silněji.
        public let isDownbeat: Bool
    }

    public func isDownbeat(index: Int) -> Bool {
        let m = (index - downbeatOffset) % beatsPerBar
        return (m + beatsPerBar) % beatsPerBar == 0
    }

    /// Doby v polouzavřeném intervalu [from, to). Jen indexy ≥ 0 —
    /// mřížka začíná první dobou, před ní hudba nemá metrum.
    public func beats(from: Double, to: Double) -> [Beat] {
        guard bpm > 0, to > from else { return [] }
        let interval = beatInterval
        // Epsilon proti chybě plovoucí čárky: doba přesně na `from`
        // do výsledku patří.
        let firstIndex = max(0, Int(((from - firstBeatTime) / interval - 1e-9).rounded(.up)))
        var result: [Beat] = []
        var index = firstIndex
        while true {
            let time = firstBeatTime + Double(index) * interval
            guard time < to else { break }
            result.append(Beat(index: index, time: time, isDownbeat: isDownbeat(index: index)))
            index += 1
        }
        return result
    }

    /// Nejbližší doba k času (indexy ≥ 0).
    public func nearestBeat(to time: Double) -> Beat {
        guard bpm > 0 else { return Beat(index: 0, time: firstBeatTime, isDownbeat: isDownbeat(index: 0)) }
        let index = max(0, Int(((time - firstBeatTime) / beatInterval).rounded()))
        return Beat(index: index,
                    time: firstBeatTime + Double(index) * beatInterval,
                    isDownbeat: isDownbeat(index: index))
    }

    // MARK: - Ruční korekce (plán F14: první takt a násobek tempa)

    /// Detekce občas chytí poloviční/dvojnásobné tempo (obě jsou pravda,
    /// liší se jen úrovní členění) — uživatel si přepne.
    public mutating func doubleTempo() { bpm *= 2 }
    public mutating func halveTempo() { bpm /= 2 }

    /// Posune FÁZI mřížky tak, aby nejbližší doba padla přesně na čas.
    /// Tempo se nemění.
    public mutating func alignBeat(to time: Double) {
        firstBeatTime += time - nearestBeat(to: time).time
    }

    /// Doba nejblíž času se stane „raz" — začátky taktů se přepočítají.
    public mutating func markDownbeat(at time: Double) {
        downbeatOffset = nearestBeat(to: time).index % beatsPerBar
    }
}
