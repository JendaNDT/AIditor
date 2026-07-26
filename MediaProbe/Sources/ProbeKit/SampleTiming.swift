//
//  SampleTiming.swift
//  Projekt Krása / ProbeKit
//
//  Měřicí jádro: klasifikace délek vzorků a verdikt CFR/VFR.
//
//  Sdílené mezi `MediaProbe` (měří) a `Flatten` (zplošťuje). Schválně jeden
//  kód — kdyby nástroj zplošťoval podle jednoho modu a sonda ověřovala podle
//  jiného, projevilo by se to jako „ověření prošlo, ale soubor je špatně".
//

import CoreMedia
import Foundation

// MARK: - Odkud se četly délky vzorků

public enum TimingSource: String, Sendable {
    case sampleCursor = "AVSampleCursor"
    case assetReader = "AVAssetReader"
}

// MARK: - Klasifikace jednoho vzorku

/// Do jaké kategorie spadá délka jednoho vzorku vůči modu.
///
/// Rozlišení mezi `dropped` a `irregular` je celý smysl téhle sondy: zahozený
/// snímek se opraví doplněním duplikátu, nepravidelné časování se musí přepočítat.
public enum SampleClass: Equatable, Sendable {
    /// Přesně na modu.
    case normal
    /// Do jednoho ticku od modu — artefakt celočíselné časové základny.
    case rounding
    /// Celočíselný násobek modu. Kolik snímků chybí.
    case dropped(missing: Int)
    /// Cokoli jiného. Skutečně proměnlivé časování.
    case irregular

    /// Tolerance kolem celočíselného násobku, v podílu délky snímku.
    /// 10 % je dost na jitter kolem zahozeného snímku, málo na to, aby to spolklo
    /// délku 1,79× modu (ta je opravdu nepravidelná, ne zahozený snímek).
    public static let multipleTolerance = 0.10

    public static func classify(tick: Int64, mode: Int64) -> SampleClass {
        if tick == mode { return .normal }
        if abs(tick - mode) <= 1 { return .rounding }
        guard mode > 0 else { return .irregular }

        let ratio = Int((Double(tick) / Double(mode)).rounded())
        guard ratio >= 2 else { return .irregular }

        let expected = Int64(ratio) * mode
        let tolerance = max(Int64(1), Int64((Double(mode) * multipleTolerance).rounded()))
        return abs(tick - expected) <= tolerance ? .dropped(missing: ratio - 1) : .irregular
    }
}

// MARK: - Okrajový vzorek

/// První a poslední vzorek stopy. Do kolísání uvnitř stopy se nepočítají —
/// useknutý krajní vzorek je běžný a nafoukl by číslo o řád. Nezmizí ale:
/// hlásí se vlastním řádkem, ať je vidět, co přesně se z výpočtu vyjmulo.
public struct EdgeSample: Sendable {
    public let index: Int
    public let tick: Int64
    public let position: String
    public let classification: SampleClass
    /// Kolikanásobek modu tenhle vzorek je.
    public let ratioToMode: Double

    public var isAnomalous: Bool { classification != .normal }

    /// Zkratka do tabulky. „první" a „poslední" mají stejné první písmeno,
    /// takže se zkracovat nesmí strojově.
    public var shortPosition: String { index == 0 ? "1." : "posl." }
}

// MARK: - Verdikt CFR / VFR

public enum FrameRateVerdict: Sendable {
    /// Všechny vzorky mají naprosto stejnou délku.
    case constant
    /// Délky se liší, ale nejvýš o jeden tick timescale — zaokrouhlování, ne VFR.
    case constantWithRounding(spreadTicks: Int64)
    /// Konstantní časování se zahozenými snímky. Opravitelné duplikací.
    case constantWithDroppedFrames(events: Int, frames: Int)
    /// Nepravidelný je jen první a/nebo poslední vzorek. Typicky useknutý okraj.
    case constantWithEdgeOutliers(indices: [Int], droppedFrames: Int)
    /// Skutečný rozptyl uvnitř stopy.
    case variable(irregular: Int, droppedFrames: Int)

    public var shortLabel: String {
        switch self {
        case .constant: return "CFR"
        case .constantWithRounding: return "CFR≈"
        case .constantWithDroppedFrames(_, let frames): return "CFR↓\(frames)"
        case .constantWithEdgeOutliers: return "CFR±"
        case .variable: return "VFR"
        }
    }

    /// Je časování pod zahozenými snímky konstantní? Rozhoduje o tom,
    /// jestli stačí doplnit duplikáty, nebo je nutný přepočet.
    public var isConstantUnderneath: Bool {
        switch self {
        case .constant, .constantWithRounding, .constantWithDroppedFrames: return true
        case .constantWithEdgeOutliers, .variable: return false
        }
    }

    /// Je to dokonale pravidelná mřížka? Tohle musí platit po zploštění.
    public var isPerfectlyConstant: Bool {
        if case .constant = self { return true }
        return false
    }

    public var explanation: String {
        switch self {
        case .constant:
            return "CFR — všechny vzorky mají identickou délku."
        case .constantWithRounding(let spread):
            return "CFR se zaokrouhlením — délky se liší o \(spread) tick(y) timescale. "
                 + "To je artefakt celočíselné časové základny, ne proměnná snímková frekvence."
        case .constantWithDroppedFrames(let events, let frames):
            return "CFR se zahozenými snímky — časování je jinak konstantní, ale v \(events) "
                 + "místě/místech je vzorek celočíselným násobkem délky snímku. Chybí \(frames) "
                 + "snímek/snímků. Tohle se řeší doplněním duplikátů, ne přepočtem časování."
        case .constantWithEdgeOutliers(let indices, let frames):
            let list = indices.map(String.init).joined(separator: ", ")
            let dropped = frames > 0 ? " Navíc \(frames) zahozený snímek/snímků." : ""
            return "CFR s odchylkou na okraji — nepravidelný je pouze vzorek/vzorky na indexu "
                 + "\(list) (první a/nebo poslední). Uvnitř stopy je frekvence konstantní. "
                 + "Useknutý krajní vzorek je běžný a neznamená VFR.\(dropped)"
        case .variable(let irregular, let frames):
            let dropped = frames > 0 ? " Z toho \(frames) zahozený snímek/snímků." : ""
            return "VFR — \(irregular) vzorek/vzorků má délku, kterou nevysvětlí ani zaokrouhlení, "
                 + "ani zahozený snímek. Časování je skutečně proměnlivé a před střihem "
                 + "se musí přepočítat na CFR.\(dropped)"
        }
    }
}

// MARK: - Statistika délek vzorků

/// Naměřené délky vzorků jedné stopy a všechno, co z nich plyne.
///
/// Délky se drží jako **celá čísla v tickách timescale**, ne v sekundách.
/// Kdyby se porovnávaly `Double` sekundy, plovoucí aritmetika by vyrobila
/// rozptyl, který v souboru není.
public struct TimingStats {
    public let source: TimingSource
    public let timescale: CMTimeScale
    /// Musely se délky převádět mezi různými timescale? Pak čísla nejsou přesná.
    public let rescaled: Bool
    /// Délky vzorků v tickách, seřazené podle prezentačního času.
    public let ticks: [Int64]

    public let mode: Int64
    public let minTick: Int64
    public let maxTick: Int64
    /// Histogram seřazený sestupně podle četnosti.
    public let histogram: [(tick: Int64, count: Int)]
    /// Indexy (v prezentačním pořadí) vzorků, které se liší od modu.
    public let outlierIndices: [Int]
    public let stdDevTicks: Double
    public let verdict: FrameRateVerdict

    /// Kolik vzorků spadá do které kategorie.
    public let normalCount: Int
    public let roundingCount: Int
    /// Počet vzorků, které jsou celočíselným násobkem modu.
    public let droppedEvents: Int
    /// Kolik snímků dohromady chybí.
    public let droppedFrames: Int
    /// Indexy vzorků, které nevysvětlí ani zaokrouhlení, ani zahozený snímek.
    public let irregularIndices: [Int]
    /// Největší odchylka od modu **uvnitř stopy** — bez zahozených snímků
    /// a bez prvního a posledního vzorku. Tohle je „jak moc kolísá časování".
    public let interiorDeviationTicks: Int64
    /// Kolik vzorků do výpočtu kolísání vůbec vstoupilo.
    public let interiorSampleCount: Int
    /// První a poslední vzorek. Z kolísání vyjmuté, ale hlášené zvlášť.
    public let edges: [EdgeSample]

    public var sampleCount: Int { ticks.count }
    public var distinctCount: Int { histogram.count }

    /// Snímková frekvence odvozená z nejčastější délky vzorku.
    ///
    /// **Tohle je číslo, podle kterého se zplošťuje** — ne `nominalFrameRate`,
    /// která na slow-mo klipu hlásí 119,369 místo naměřených 120,000.
    public var measuredFrameRate: Double {
        guard mode > 0 else { return 0 }
        return Double(timescale) / Double(mode)
    }

    /// Délka snímku jako přesný zlomek, ne desetinné číslo.
    /// `1500/90000`, ne `0.016666…` — z tohohle se staví výstupní mřížka.
    public var frameDuration: CMTime {
        CMTime(value: mode, timescale: timescale)
    }

    public var msPerTick: Double { 1000.0 / Double(timescale) }

    public func milliseconds(_ tick: Int64) -> Double { Double(tick) * msPerTick }

    /// Největší odchylka od modu v tickách.
    public var maxDeviationTicks: Int64 {
        max(maxTick - mode, mode - minTick)
    }

    public var maxDeviationPercent: Double {
        guard mode > 0 else { return 0 }
        return Double(maxDeviationTicks) / Double(mode) * 100.0
    }

    /// Kolísání časování uvnitř stopy, v procentech délky snímku.
    /// Bez zahozených snímků a bez okrajových vzorků — ty mají vlastní hlášení.
    public var interiorJitterPercent: Double {
        guard mode > 0 else { return 0 }
        return Double(interiorDeviationTicks) / Double(mode) * 100.0
    }

    public var irregularCount: Int { irregularIndices.count }

    /// Okrajové vzorky, které nesedí na modu. Prázdné pole = okraje jsou v pořádku.
    public var anomalousEdges: [EdgeSample] { edges.filter(\.isAnomalous) }

    // MARK: Výpočet

    /// Spočítá statistiku z délek v tickách. `ticks` musí být v prezentačním pořadí.
    public init?(source: TimingSource, timescale: CMTimeScale, rescaled: Bool, ticks: [Int64]) {
        guard !ticks.isEmpty else { return nil }

        self.source = source
        self.timescale = timescale
        self.rescaled = rescaled
        self.ticks = ticks

        var counts: [Int64: Int] = [:]
        for t in ticks { counts[t, default: 0] += 1 }

        // Modus: nejčastější délka. Při rovnosti bere kratší, ať je výsledek deterministický.
        var entries: [(tick: Int64, count: Int)] = []
        entries.reserveCapacity(counts.count)
        for (tick, count) in counts {
            entries.append((tick: tick, count: count))
        }
        entries.sort { lhs, rhs in
            lhs.count == rhs.count ? lhs.tick < rhs.tick : lhs.count > rhs.count
        }

        let sortedHistogram = entries
        self.histogram = sortedHistogram
        let modeValue = sortedHistogram[0].tick
        self.mode = modeValue
        self.minTick = ticks.min()!
        self.maxTick = ticks.max()!
        self.outlierIndices = ticks.indices.filter { ticks[$0] != modeValue }

        let mean = ticks.reduce(0.0) { $0 + Double($1) } / Double(ticks.count)
        let variance = ticks.reduce(0.0) { acc, t in
            let d = Double(t) - mean
            return acc + d * d
        } / Double(ticks.count)
        self.stdDevTicks = variance.squareRoot()

        // Klasifikace. Počítá se jednou na každou různou délku, ne na každý vzorek.
        var classByTick: [Int64: SampleClass] = [:]
        for tick in counts.keys {
            classByTick[tick] = SampleClass.classify(tick: tick, mode: modeValue)
        }

        // Okraje stopy. U kratších stop než tři vzorky by vyjmutí okrajů nenechalo
        // co počítat, takže se v tom případě nevyjímá nic.
        let lastIndex = ticks.count - 1
        let edgeIndices: Set<Int> = ticks.count >= 3 ? [0, lastIndex] : []

        var edgeList: [EdgeSample] = []
        for index in edgeIndices.sorted() {
            let tick = ticks[index]
            edgeList.append(EdgeSample(
                index: index,
                tick: tick,
                position: index == 0 ? "první" : "poslední",
                classification: classByTick[tick] ?? .irregular,
                ratioToMode: modeValue > 0 ? Double(tick) / Double(modeValue) : 0))
        }
        self.edges = edgeList

        var normal = 0, rounding = 0, events = 0, frames = 0
        var irregular: [Int] = []
        var interiorDeviation: Int64 = 0
        var interiorCount = 0

        for (index, tick) in ticks.enumerated() {
            switch classByTick[tick] ?? .irregular {
            case .normal:
                normal += 1
            case .rounding:
                rounding += 1
            case .dropped(let missing):
                events += 1
                frames += missing
                continue  // zahozený snímek není kolísání časování
            case .irregular:
                irregular.append(index)
            }

            // Okraje se do kolísání nepočítají — hlásí se zvlášť v `edges`.
            guard !edgeIndices.contains(index) else { continue }
            interiorCount += 1
            interiorDeviation = max(interiorDeviation, abs(tick - modeValue))
        }

        self.normalCount = normal
        self.roundingCount = rounding
        self.droppedEvents = events
        self.droppedFrames = frames
        self.irregularIndices = irregular
        self.interiorDeviationTicks = interiorDeviation
        self.interiorSampleCount = interiorCount

        // Verdikt. Pořadí testů je od nejpřísnějšího k nejvolnějšímu.
        let spread = maxTick - minTick
        if counts.count == 1 {
            self.verdict = .constant
        } else if irregular.isEmpty && events == 0 {
            self.verdict = .constantWithRounding(spreadTicks: spread)
        } else if irregular.isEmpty {
            // Časování je pod zahozenými snímky konstantní — stačí doplnit duplikáty.
            self.verdict = .constantWithDroppedFrames(events: events, frames: frames)
        } else if Set(irregular).isSubset(of: [0, ticks.count - 1]) {
            // Nepravidelný je jen okraj. Useknutý krajní vzorek není VFR.
            self.verdict = .constantWithEdgeOutliers(indices: irregular, droppedFrames: frames)
        } else {
            self.verdict = .variable(irregular: irregular.count, droppedFrames: frames)
        }
    }
}
