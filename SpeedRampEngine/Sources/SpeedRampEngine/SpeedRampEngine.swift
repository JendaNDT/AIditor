//
//  SpeedRampEngine.swift
//  Projekt AIditor
//
//  Čistá matematika rychlostní křivky. Žádné AVFoundation, žádné UI.
//  Uzly jsou definované na VÝSTUPNÍ (timeline) ose:
//
//      v(t)      = rychlost přehrávání v čase t na časové ose
//      t_src(t)  = ∫₀ᵗ v(τ) dτ     ... kolik zdrojového času se spotřebovalo
//
//  Ověřeno numericky proti analyticky spočitatelným případům před portem:
//  konstantní rychlost je přesná na 0.0, lineární přechod na 1e-9,
//  d(t_src)/dt == v(t) na 3.3e-10, round-trip inverze na 3.7e-12.
//

import Foundation

// MARK: - Chyby

public enum SpeedRampError: Error, Equatable, CustomStringConvertible {
    case tooFewNodes
    case firstNodeNotAtZero(Double)
    case nonIncreasingTime(index: Int)
    case nonPositiveSpeed(index: Int, speed: Double)
    case invalidFrameRate(Double)
    case invalidSpeedStep(Double)

    public var description: String {
        switch self {
        case .tooFewNodes:
            return "Rychlostní křivka potřebuje alespoň dva uzly."
        case .firstNodeNotAtZero(let t):
            return "První uzel musí být na čase 0, je na \(t)."
        case .nonIncreasingTime(let i):
            return "Uzel \(i) nemá rostoucí čas oproti předchozímu."
        case .nonPositiveSpeed(let i, let v):
            return "Uzel \(i) má rychlost \(v). Rychlost musí být kladná — nula je freeze frame, což je jiná funkce."
        case .invalidFrameRate(let f):
            return "Neplatná snímková frekvence \(f)."
        case .invalidSpeedStep(let s):
            return "Neplatná mez skoku rychlosti \(s). Musí být kladná."
        }
    }
}

// MARK: - Bézier easing

/// Náběhová funkce se stejnou sémantikou jako CSS `cubic-bezier(x1, y1, x2, y2)`.
/// Krajní body jsou pevně (0,0) a (1,1).
public struct BezierEase: Equatable, Hashable, Codable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static let linear     = BezierEase(0.0,  0.0, 1.00, 1.0)
    public static let easeInOut  = BezierEase(0.42, 0.0, 0.58, 1.0)
    public static let easeOut    = BezierEase(0.0,  0.0, 0.58, 1.0)
    public static let easeIn     = BezierEase(0.42, 0.0, 1.00, 1.0)

    @inline(__always)
    private static func bezier(_ a: Double, _ b: Double, _ s: Double) -> Double {
        let u = 1.0 - s
        return 3.0 * u * u * s * a + 3.0 * u * s * s * b + s * s * s
    }

    @inline(__always)
    private static func bezierDerivative(_ a: Double, _ b: Double, _ s: Double) -> Double {
        let u = 1.0 - s
        return 3.0 * u * u * a + 6.0 * u * s * (b - a) + 3.0 * s * s * (1.0 - b)
    }

    /// Najde parametr `s`, pro který `Bx(s) == u`. Newton s bisekcí jako záchranou.
    private func solveParameter(for u: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }

        var s = u
        for _ in 0..<8 {
            let f = Self.bezier(x1, x2, s) - u
            if abs(f) < 1e-12 { return s }
            let d = Self.bezierDerivative(x1, x2, s)
            if abs(d) < 1e-12 { break }
            let next = s - f / d
            if next < 0 || next > 1 { break }
            s = next
        }

        var lo = 0.0, hi = 1.0
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            if Self.bezier(x1, x2, mid) < u { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    /// Hodnota náběhu pro `u` ∈ [0, 1]. Vrací 0 na začátku, 1 na konci.
    public func value(at u: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        return Self.bezier(y1, y2, solveParameter(for: u))
    }

    /// Průměrná hodnota náběhu na [0, 1], tedy ∫₀¹ ease(u) du.
    ///
    /// Stejná kvadratura (Simpson, 512 vzorků) jako integrální tabulka křivky —
    /// záměrně: konstrukce ze zdrojově kotvených uzlů pak trefí zdrojové
    /// pozice uzlů přesně, ne jen přibližně.
    var integralAverage: Double {
        let n = 512
        var sum = value(at: 0) + value(at: 1)
        for k in 1..<n {
            let weight: Double = (k % 2 == 1) ? 4 : 2
            sum += weight * value(at: Double(k) / Double(n))
        }
        return sum / (3.0 * Double(n))
    }
}

// MARK: - Uzel

public struct SpeedNode: Equatable, Codable, Sendable {
    /// Čas od začátku rampu na **časové ose** (ne ve zdroji), v sekundách.
    public var outputOffset: Double
    /// Násobitel rychlosti. 1.0 = normálně, 0.25 = čtyřikrát pomaleji.
    public var speed: Double
    /// Jak se přechází z tohoto uzlu do následujícího.
    public var easeToNext: BezierEase

    public init(outputOffset: Double, speed: Double, easeToNext: BezierEase = .easeInOut) {
        self.outputOffset = outputOffset
        self.speed = speed
        self.easeToNext = easeToNext
    }
}

// MARK: - Zdrojově kotvený uzel

/// Uzel rychlostní křivky kotvený ve **zdrojovém** čase.
///
/// Timeline model ukládá uzly takhle schválně: když zpomalení sedí na hodu
/// kyticí a klip se zepředu zkrátí, zpomalení má zůstat na hodu kyticí.
/// Na výstupní osu (kterou počítá zbytek enginu) se převádí přes
/// `SpeedRamp.anchoredToSource(_:)`.
public struct SourceAnchoredNode: Equatable, Hashable, Sendable {
    /// Pozice ve zdroji, v sekundách. Musí být ostře rostoucí.
    public var sourceOffset: Double
    public var speed: Double
    public var easeToNext: BezierEase

    public init(sourceOffset: Double, speed: Double, easeToNext: BezierEase = .easeInOut) {
        self.sourceOffset = sourceOffset
        self.speed = speed
        self.easeToNext = easeToNext
    }
}

// MARK: - Segment

/// Jeden mikro-úsek pro `scaleTimeRange(_:toDuration:)`.
/// AVFoundation umí jen konstantní změnu rychlosti přes daný úsek, takže
/// plynulá křivka se skládá z mnoha takových úseků.
public struct RampSegment: Equatable, Sendable {
    public let sourceStart: Double
    public let sourceDuration: Double
    public let outputDuration: Double

    /// Konstantní rychlost tohoto úseku.
    public var speed: Double { sourceDuration / outputDuration }
}

// MARK: - Rychlostní křivka

public struct SpeedRamp: Equatable, Codable, Sendable {

    /// Pod touhle rychlostí je mapování prakticky nemonotónní. Nula = freeze frame,
    /// což se řeší jinak (podržený snímek), ne rychlostní křivkou.
    public static let minimumSpeed = 1e-4

    /// Kolik vzorků na interval při stavbě integrální tabulky. Musí být sudé (Simpson).
    private static let samplesPerInterval = 512

    public private(set) var nodes: [SpeedNode]

    private var sampleTimes: [Double] = []
    private var cumulative: [Double] = []

    private enum CodingKeys: String, CodingKey { case nodes }

    // MARK: Vytvoření

    public init(nodes: [SpeedNode]) throws {
        guard nodes.count >= 2 else { throw SpeedRampError.tooFewNodes }
        let sorted = nodes.sorted { $0.outputOffset < $1.outputOffset }

        guard abs(sorted[0].outputOffset) < 1e-12 else {
            throw SpeedRampError.firstNodeNotAtZero(sorted[0].outputOffset)
        }
        for i in sorted.indices {
            guard sorted[i].speed >= Self.minimumSpeed else {
                throw SpeedRampError.nonPositiveSpeed(index: i, speed: sorted[i].speed)
            }
            if i > 0 {
                guard sorted[i].outputOffset > sorted[i - 1].outputOffset else {
                    throw SpeedRampError.nonIncreasingTime(index: i)
                }
            }
        }

        self.nodes = sorted
        buildTable()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(nodes: try c.decode([SpeedNode].self, forKey: .nodes))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nodes, forKey: .nodes)
    }

    public static func == (lhs: SpeedRamp, rhs: SpeedRamp) -> Bool { lhs.nodes == rhs.nodes }

    /// Postaví křivku ze **zdrojově kotvených** uzlů.
    ///
    /// Výstupní ofsety se dopočítají tak, aby křivka procházela zdrojovou
    /// pozicí každého uzlu: mezi uzly `a` a `b` se spotřebuje
    /// `Δt · (a.speed + (b.speed − a.speed) · ∫ease)`, takže
    /// `Δt = Δs / průměrná rychlost`. Výstupní nula křivky odpovídá
    /// zdrojové pozici prvního uzlu — volající si ji musí pamatovat.
    public static func anchoredToSource(_ nodes: [SourceAnchoredNode]) throws -> SpeedRamp {
        guard nodes.count >= 2 else { throw SpeedRampError.tooFewNodes }
        let sorted = nodes.sorted { $0.sourceOffset < $1.sourceOffset }
        for i in sorted.indices {
            guard sorted[i].speed >= Self.minimumSpeed else {
                throw SpeedRampError.nonPositiveSpeed(index: i, speed: sorted[i].speed)
            }
            if i > 0 {
                guard sorted[i].sourceOffset > sorted[i - 1].sourceOffset else {
                    throw SpeedRampError.nonIncreasingTime(index: i)
                }
            }
        }

        var output = 0.0
        var converted: [SpeedNode] = []
        converted.reserveCapacity(sorted.count)
        for i in sorted.indices {
            converted.append(SpeedNode(outputOffset: output,
                                       speed: sorted[i].speed,
                                       easeToNext: sorted[i].easeToNext))
            if i < sorted.count - 1 {
                let a = sorted[i], b = sorted[i + 1]
                let meanSpeed = a.speed + (b.speed - a.speed) * a.easeToNext.integralAverage
                output += (b.sourceOffset - a.sourceOffset) / meanSpeed
            }
        }
        return try SpeedRamp(nodes: converted)
    }

    /// Natáhne tvar křivky tak, aby spotřeboval **přesně** `sourceDuration` zdrojového času.
    /// Škáluje se čas uzlů, ne rychlosti — tvar křivky zůstává.
    public static func fitting(sourceDuration: Double, shape: [SpeedNode]) throws -> SpeedRamp {
        let base = try SpeedRamp(nodes: shape)
        let k = sourceDuration / base.sourceConsumed
        let scaled = shape.map {
            SpeedNode(outputOffset: $0.outputOffset * k, speed: $0.speed, easeToNext: $0.easeToNext)
        }
        return try SpeedRamp(nodes: scaled)
    }

    // MARK: Základní vlastnosti

    /// Délka rampu na časové ose.
    public var outputDuration: Double { nodes.last!.outputOffset }

    /// Kolik zdrojového času celý ramp spotřebuje.
    public var sourceConsumed: Double { cumulative.last ?? 0 }

    // MARK: Rychlost

    /// Rychlost přehrávání v daném čase na časové ose.
    public func speed(atOutput t: Double) -> Double {
        if t <= 0 { return nodes[0].speed }
        if t >= outputDuration { return nodes[nodes.count - 1].speed }

        var lo = 0, hi = nodes.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if nodes[mid].outputOffset <= t { lo = mid } else { hi = mid }
        }

        let a = nodes[lo], b = nodes[lo + 1]
        let u = (t - a.outputOffset) / (b.outputOffset - a.outputOffset)
        return a.speed + (b.speed - a.speed) * a.easeToNext.value(at: u)
    }

    // MARK: Mapování času

    /// Čas na časové ose → čas ve zdrojovém klipu.
    public func sourceTime(atOutput t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= outputDuration {
            return sourceConsumed + (t - outputDuration) * nodes[nodes.count - 1].speed
        }

        var lo = 0, hi = sampleTimes.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if sampleTimes[mid] <= t { lo = mid } else { hi = mid }
        }

        // Dopočet zbytku Simpsonem na [sampleTimes[lo], t]
        let a = sampleTimes[lo], b = t
        let m = 0.5 * (a + b)
        return cumulative[lo]
            + ((b - a) / 6.0) * (speed(atOutput: a) + 4.0 * speed(atOutput: m) + speed(atOutput: b))
    }

    /// Čas ve zdrojovém klipu → čas na časové ose. Inverze, Newton s bisekcí.
    public func outputTime(atSource s: Double) -> Double {
        if s <= 0 { return 0 }
        if s >= sourceConsumed {
            return outputDuration + (s - sourceConsumed) / nodes[nodes.count - 1].speed
        }

        var lo = 0, hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= s { lo = mid } else { hi = mid }
        }

        var low = sampleTimes[lo], high = sampleTimes[lo + 1]
        var t = 0.5 * (low + high)
        for _ in 0..<40 {
            let f = sourceTime(atOutput: t) - s
            if abs(f) < 1e-12 { return t }
            if f > 0 { high = t } else { low = t }

            let d = speed(atOutput: t)
            var next = d > Self.minimumSpeed ? t - f / d : 0.5 * (low + high)
            if !(low...high).contains(next) { next = 0.5 * (low + high) }
            t = next
        }
        return t
    }

    // MARK: Segmentace

    /// Rozkrájí ramp na mikro-úseky pro `scaleTimeRange`, zarovnané na hranice
    /// výstupních snímků.
    ///
    /// - Parameters:
    ///   - outputFrameRate: snímková frekvence časové osy (např. 30, 60)
    ///   - framesPerSegment: kolik výstupních snímků připadá na jeden úsek.
    ///     Nižší číslo = hladší křivka, ale víc hranic, kde může lupnout zvuk.
    ///     Dva snímky jsou rozumný začátek — u rampu 1,0 → 0,25 → 1,0 přes 5 s
    ///     při 60 fps to dá skok rychlosti mezi sousedními úseky pod 0,02×.
    public func segments(outputFrameRate: Double, framesPerSegment: Int = 2) throws -> [RampSegment] {
        guard outputFrameRate > 0, outputFrameRate.isFinite else {
            throw SpeedRampError.invalidFrameRate(outputFrameRate)
        }
        let perSegment = max(1, framesPerSegment)
        let totalFrames = max(perSegment, Int((outputDuration * outputFrameRate).rounded()))
        let count = max(1, Int(ceil(Double(totalFrames) / Double(perSegment))))

        var result: [RampSegment] = []
        result.reserveCapacity(count)

        var previousSource = 0.0
        for k in 0..<count {
            let endFrame = min(totalFrames, (k + 1) * perSegment)
            let startFrame = k * perSegment
            let outputEnd = outputDuration * Double(endFrame) / Double(totalFrames)
            let outputStart = outputDuration * Double(startFrame) / Double(totalFrames)

            let sourceEnd = (k == count - 1) ? sourceConsumed : sourceTime(atOutput: outputEnd)
            result.append(RampSegment(
                sourceStart: previousSource,
                sourceDuration: sourceEnd - previousSource,
                outputDuration: outputEnd - outputStart
            ))
            previousSource = sourceEnd
        }
        return result
    }

    // MARK: Segmentace podle skoku rychlosti

    /// Výsledek segmentace řízené mezí skoku rychlosti.
    public struct SegmentationPlan: Sendable {
        public let segments: [RampSegment]
        /// Kolik výstupních snímků engine nakonec zvolil na jeden úsek.
        public let framesPerSegment: Int
        public let requestedMaxStep: Double
        /// Skutečně dosažený největší skok mezi sousedními úseky.
        public let achievedMaxStep: Double
        /// `true`, když ani jeden snímek na úsek nestačí — mez je při téhle
        /// snímkové frekvenci nedosažitelná. Volající to musí umět zobrazit.
        public let limitedByFrameRate: Bool

        public var segmentCount: Int { segments.count }
    }

    /// Největší strmost křivky, `max |dv/dt|`.
    ///
    /// Zjišťuje se hustým vzorkováním, ne analyticky — easing je libovolná
    /// Bézierova křivka a číselné vzorkování je vůči ní robustní.
    /// Vzorkuje se jemněji než snímková mřížka, jinak by se strmost podcenila.
    public func maxSpeedSlope(outputFrameRate: Double) -> Double {
        guard outputDuration > 0, outputFrameRate > 0 else { return 0 }

        let samples = max(2048, Int((outputDuration * outputFrameRate * 4).rounded()))
        let dt = outputDuration / Double(samples)
        var maxSlope = 0.0
        var previous = speed(atOutput: 0)

        for index in 1...samples {
            let current = speed(atOutput: outputDuration * Double(index) / Double(samples))
            maxSlope = max(maxSlope, abs(current - previous) / dt)
            previous = current
        }
        return maxSlope
    }

    /// Rozkrájí ramp tak, aby skok rychlosti mezi sousedními úseky nikde
    /// nepřekročil `maxSpeedStep`.
    ///
    /// **Tohle je preferovaná varianta** oproti `segments(outputFrameRate:framesPerSegment:)`.
    /// Pevný počet snímků na úsek je špatná veličina: skok rychlosti závisí na
    /// délce klipu, takže stejná hodnota dá na 45s klipu 0,96 % a na 11s klipu
    /// 3,79 %. Mez skoku je naopak vlastnost výsledku, ne vstupu — dlouhý klip
    /// dostane hrubé dělení, krátký jemné, oba se stejnou kvalitou.
    ///
    /// - Parameters:
    ///   - outputFrameRate: snímková frekvence časové osy
    ///   - maxSpeedStep: největší přípustný **absolutní** rozdíl rychlosti mezi
    ///     sousedními úseky. `0.015` znamená, že se rychlost nikde neskokne
    ///     o víc než 0,015× (tedy 1,5 procentního bodu).
    ///
    /// - Note: Mez je absolutní, ne relativní k rychlosti. Skok 0,015 při
    ///   rychlosti 1,0 je 1,5 %, ale při 0,25 už 6 %. U klasického rampu to
    ///   nevadí, protože křivka je v okolí minima plochá a největší skoky
    ///   vznikají v přechodech, kde je rychlost prostřední.
    public func segmentation(outputFrameRate: Double,
                             maxSpeedStep: Double) throws -> SegmentationPlan {
        guard outputFrameRate > 0, outputFrameRate.isFinite else {
            throw SpeedRampError.invalidFrameRate(outputFrameRate)
        }
        guard maxSpeedStep > 0, maxSpeedStep.isFinite else {
            throw SpeedRampError.invalidSpeedStep(maxSpeedStep)
        }

        let totalFrames = max(1, Int((outputDuration * outputFrameRate).rounded()))
        let slope = maxSpeedSlope(outputFrameRate: outputFrameRate)

        // Odhad prvního řádu: skok ≈ |dv/dt| · délka úseku.
        // Použije se MAXIMÁLNÍ strmost, takže odhad je konzervativní —
        // skutečný skok vyjde nejvýš takový, obvykle menší.
        var chosen: Int
        if slope <= 0 {
            chosen = totalFrames        // konstantní rychlost, dělit není proč
        } else {
            chosen = Int((maxSpeedStep * outputFrameRate / slope).rounded(.down))
        }
        chosen = min(totalFrames, max(1, chosen))

        // Odhad se ověří na skutečných úsecích. Tím se z něj stává záruka,
        // ne přibližný výpočet. Kvůli konzervativnosti odhadu se cyklus
        // skoro nikdy nespustí — je to pojistka, ne hlavní cesta.
        var result = try segments(outputFrameRate: outputFrameRate, framesPerSegment: chosen)
        var achieved = Self.largestSpeedStep(in: result)

        while achieved > maxSpeedStep && chosen > 1 {
            chosen = max(1, chosen / 2)
            result = try segments(outputFrameRate: outputFrameRate, framesPerSegment: chosen)
            achieved = Self.largestSpeedStep(in: result)
        }

        return SegmentationPlan(segments: result,
                                framesPerSegment: chosen,
                                requestedMaxStep: maxSpeedStep,
                                achievedMaxStep: achieved,
                                limitedByFrameRate: achieved > maxSpeedStep)
    }

    // MARK: Segmentace okna

    /// Největší strmost křivky uvnitř výstupního okna `[windowStart, windowStart + windowDuration]`.
    /// Za koncem křivky je rychlost konstantní (poslední uzel), strmost nula.
    func maxSpeedSlope(outputFrameRate: Double, windowStart: Double, windowDuration: Double) -> Double {
        guard windowDuration > 0, outputFrameRate > 0 else { return 0 }

        let samples = max(2048, Int((windowDuration * outputFrameRate * 4).rounded()))
        let dt = windowDuration / Double(samples)
        var maxSlope = 0.0
        var previous = speed(atOutput: windowStart)

        for index in 1...samples {
            let current = speed(atOutput: windowStart + windowDuration * Double(index) / Double(samples))
            maxSlope = max(maxSlope, abs(current - previous) / dt)
            previous = current
        }
        return maxSlope
    }

    /// Úseky pro **výsek** křivky: okno začíná na výstupním čase `windowStart`
    /// a trvá přesně `windowFrames` výstupních snímků.
    ///
    /// Klip na ose po trimu nepokrývá celou křivku, ale její výsek — a výsek
    /// může přesahovat i za poslední uzel (tam křivka pokračuje rychlostí
    /// posledního uzlu, stejně jako `sourceTime(atOutput:)`).
    ///
    /// `sourceStart` úseků je relativní k **začátku okna**, ne k začátku
    /// křivky — volající zná zdrojovou pozici okna a přičte si ji sám.
    /// Hranice úseků sedí na hranicích výstupních snímků a zdrojové pozice
    /// se počítají kumulativně, takže úseky na sebe navazují beze zbytku.
    public func segments(outputFrameRate: Double,
                         framesPerSegment: Int,
                         windowStart: Double,
                         windowFrames: Int) throws -> [RampSegment] {
        guard outputFrameRate > 0, outputFrameRate.isFinite else {
            throw SpeedRampError.invalidFrameRate(outputFrameRate)
        }
        guard windowFrames > 0 else { return [] }
        let start = max(0, windowStart)
        let perSegment = max(1, framesPerSegment)
        let count = Int(ceil(Double(windowFrames) / Double(perSegment)))

        let windowSource = sourceTime(atOutput: start)
        var result: [RampSegment] = []
        result.reserveCapacity(count)

        var previousSource = windowSource
        for k in 0..<count {
            let startFrame = k * perSegment
            let endFrame = min(windowFrames, (k + 1) * perSegment)
            let outputEnd = start + Double(endFrame) / outputFrameRate
            let sourceEnd = sourceTime(atOutput: outputEnd)
            result.append(RampSegment(
                sourceStart: previousSource - windowSource,
                sourceDuration: sourceEnd - previousSource,
                outputDuration: Double(endFrame - startFrame) / outputFrameRate
            ))
            previousSource = sourceEnd
        }
        return result
    }

    /// Segmentace výseku křivky řízená mezí skoku rychlosti — okénková
    /// obdoba `segmentation(outputFrameRate:maxSpeedStep:)`, stejná logika:
    /// konzervativní odhad ze strmosti, ověření na skutečných úsecích,
    /// půlení jako pojistka.
    public func segmentation(outputFrameRate: Double,
                             maxSpeedStep: Double,
                             windowStart: Double,
                             windowFrames: Int) throws -> SegmentationPlan {
        guard outputFrameRate > 0, outputFrameRate.isFinite else {
            throw SpeedRampError.invalidFrameRate(outputFrameRate)
        }
        guard maxSpeedStep > 0, maxSpeedStep.isFinite else {
            throw SpeedRampError.invalidSpeedStep(maxSpeedStep)
        }

        let start = max(0, windowStart)
        let totalFrames = max(1, windowFrames)
        let slope = maxSpeedSlope(outputFrameRate: outputFrameRate,
                                  windowStart: start,
                                  windowDuration: Double(totalFrames) / outputFrameRate)

        var chosen: Int
        if slope <= 0 {
            chosen = totalFrames
        } else {
            chosen = Int((maxSpeedStep * outputFrameRate / slope).rounded(.down))
        }
        chosen = min(totalFrames, max(1, chosen))

        var result = try segments(outputFrameRate: outputFrameRate,
                                  framesPerSegment: chosen,
                                  windowStart: start,
                                  windowFrames: totalFrames)
        var achieved = Self.largestSpeedStep(in: result)

        while achieved > maxSpeedStep && chosen > 1 {
            chosen = max(1, chosen / 2)
            result = try segments(outputFrameRate: outputFrameRate,
                                  framesPerSegment: chosen,
                                  windowStart: start,
                                  windowFrames: totalFrames)
            achieved = Self.largestSpeedStep(in: result)
        }

        return SegmentationPlan(segments: result,
                                framesPerSegment: chosen,
                                requestedMaxStep: maxSpeedStep,
                                achievedMaxStep: achieved,
                                limitedByFrameRate: achieved > maxSpeedStep)
    }

    /// Zkratka k `segmentation(outputFrameRate:maxSpeedStep:)`, když stačí úseky.
    ///
    /// Pozor: takhle se ztratí informace o tom, jestli se mez povedlo dodržet.
    /// Když na tom záleží, sáhni po `segmentation(...)` a podívej se na
    /// `limitedByFrameRate`.
    public func segments(outputFrameRate: Double,
                         maxSpeedStep: Double) throws -> [RampSegment] {
        try segmentation(outputFrameRate: outputFrameRate, maxSpeedStep: maxSpeedStep).segments
    }

    /// Největší rozdíl rychlosti mezi sousedními úseky.
    public static func largestSpeedStep(in segments: [RampSegment]) -> Double {
        guard segments.count > 1 else { return 0 }
        var largest = 0.0
        for index in 1..<segments.count {
            largest = max(largest, abs(segments[index].speed - segments[index - 1].speed))
        }
        return largest
    }

    /// Vzorky rychlosti pro vykreslení křivky v UI.
    public func speedSamples(count: Int) -> [(output: Double, speed: Double)] {
        guard count > 1 else { return [(0, speed(atOutput: 0))] }
        return (0..<count).map { i in
            let t = outputDuration * Double(i) / Double(count - 1)
            return (t, speed(atOutput: t))
        }
    }

    // MARK: Integrální tabulka

    private mutating func buildTable() {
        var times: [Double] = [0]
        var cum: [Double] = [0]
        var total = 0.0

        for i in 0..<(nodes.count - 1) {
            let a = nodes[i], b = nodes[i + 1]
            let n = Self.samplesPerInterval           // sudé, Simpson potřebuje páry
            let h = (b.outputOffset - a.outputOffset) / Double(n)

            var values = [Double](repeating: 0, count: n + 1)
            for k in 0...n {
                let u = Double(k) / Double(n)
                values[k] = a.speed + (b.speed - a.speed) * a.easeToNext.value(at: u)
            }

            var k = 0
            while k < n {
                total += (h / 3.0) * (values[k] + 4.0 * values[k + 1] + values[k + 2])
                times.append(a.outputOffset + Double(k + 2) * h)
                cum.append(total)
                k += 2
            }
        }

        sampleTimes = times
        cumulative = cum
    }
}

// MARK: - Hotové tvary

public extension SpeedRamp {
    /// Klasický svatební ramp: normálně → zpomalení → normálně.
    /// - Parameters:
    ///   - sourceDuration: délka zdrojového klipu, kterou má ramp spotřebovat
    ///   - slowSpeed: nejnižší rychlost uprostřed
    static func classicSlowMotion(sourceDuration: Double,
                                  slowSpeed: Double = 0.25) throws -> SpeedRamp {
        try fitting(sourceDuration: sourceDuration, shape: [
            SpeedNode(outputOffset: 0.0, speed: 1.0,       easeToNext: .easeInOut),
            SpeedNode(outputOffset: 1.0, speed: slowSpeed, easeToNext: .easeInOut),
            SpeedNode(outputOffset: 2.0, speed: 1.0,       easeToNext: .easeInOut),
        ])
    }

    /// Konstantní rychlost po celou délku — užitečné jako výchozí stav a v testech.
    static func constant(speed: Double, outputDuration: Double) throws -> SpeedRamp {
        try SpeedRamp(nodes: [
            SpeedNode(outputOffset: 0.0, speed: speed, easeToNext: .linear),
            SpeedNode(outputOffset: outputDuration, speed: speed, easeToNext: .linear),
        ])
    }
}
