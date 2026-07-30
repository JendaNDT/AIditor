//
//  Timecode.swift
//  TimelineModel — Projekt AIditor
//
//  Popisky pravítka: převod snímků na timecode a volba rozteče rysek.
//
//  Proč to je v modelu a ne v `TimelineRulerView`: obojí je čistá funkce
//  s návratovou hodnotou, kterou jde porovnat s očekáváním. Ve view by to
//  nikdo neotestoval a chyba by se poznala jen tím, že si toho někdo všimne
//  na obrazovce — což u posledního popisku před hranou okna nikdo neudělá.
//
//  ⚠️ **Žádný drop-frame.** Timecode s vynechávanými čísly řeší rozpor mezi
//  29,97 snímku za sekundu a hodinami na zdi. Základna projektu je celé
//  číslo (30, rozhodnuto 26. 07. 2026), takže žádný rozpor nevzniká
//  a `00:00:29:29` po něm rovnou následuje `00:00:30:00`. Kdyby se někdy
//  zaváděla necelá základna, tenhle soubor je jedno ze dvou míst, která
//  se musí přepsat.
//

import Foundation

/// Snímek na ose vyjádřený jako `HH:MM:SS:FF`.
public struct Timecode: Hashable, Sendable {

    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let frames: Int
    /// Osa začíná na nule, ale `Frames` umí být záporné (meze tažení, offsety).
    /// Radši znaménko nést, než tiše vrátit `00:00:-1:-5`.
    public let isNegative: Bool

    public init(_ frame: Frames, frameRate: Int) {
        precondition(frameRate > 0, "Základna projektu musí být kladná.")

        isNegative = frame.count < 0
        let total = abs(frame.count)

        frames = total % frameRate
        let totalSeconds = total / frameRate
        seconds = totalSeconds % 60
        minutes = (totalSeconds / 60) % 60
        hours = totalSeconds / 3600
    }

    /// Plný tvar `HH:MM:SS:FF`.
    public var text: String {
        let sign = isNegative ? "−" : ""
        return sign + String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Zkrácený tvar: hodiny se vypouštějí, dokud nejsou potřeba.
    ///
    /// ⚠️ **Na pravítko se nehodí a schválně se tam nepoužívá.** Tři skupiny
    /// si čtenář přečte jako `HH:MM:SS`, takže `00:04:00` vypadá na čtyři
    /// minuty a znamená čtyři sekundy. Je to určené na místa, kde je jasné,
    /// o jaký údaj jde — třeba délka vybraného klipu vedle jeho jména.
    public var shortText: String {
        let sign = isNegative ? "−" : ""
        if hours > 0 {
            return sign + String(format: "%d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        }
        return sign + String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

extension Frames {
    public func timecode(frameRate: Int) -> Timecode {
        Timecode(self, frameRate: frameRate)
    }
}

// MARK: - Rozteč rysek

extension TimelineGeometry {

    /// Žebřík rozumných roztečí ve snímcích, od jednoho snímku po hodinu.
    ///
    /// Není to mocninná řada — člověk čte čas po půlsekundách, pětisekundách
    /// a čtvrtminutách, ne po šestnáctinách. Sub-sekundové hodnoty se filtrují
    /// podle základny, aby se při jiné frekvenci nenabízela rozteč větší než
    /// sekunda tvářící se jako zlomek.
    public static func rulerIntervals(frameRate: Int) -> [Frames] {
        let subSecond = [1, 2, 5, 10, 15].filter { $0 < frameRate }
        let seconds = [1, 2, 5, 10, 15, 30].map { $0 * frameRate }
        let minutes = [1, 2, 5, 10, 15, 30].map { $0 * frameRate * 60 }
        let hours = [1, 2, 5, 10].map { $0 * frameRate * 3600 }
        return (subSecond + seconds + minutes + hours).map(Frames.init)
    }

    /// Nejmenší rozteč z žebříku, která na obrazovce zabere aspoň
    /// `minimumSpacing` bodů. Když ani ta největší nestačí (extrémní
    /// odzoomování), vrátí se největší — víc už žebřík nenabízí.
    public func rulerInterval(frameRate: Int, minimumSpacing: Double) -> Frames {
        let ladder = Self.rulerIntervals(frameRate: frameRate)
        for interval in ladder where Double(interval.count) * pointsPerFrame >= minimumSpacing {
            return interval
        }
        return ladder.last ?? Frames(frameRate)
    }

    /// Snímky, na kterých má pravítko něco nakreslit.
    ///
    /// ⚠️ Začíná se na prvním NÁSOBKU rozteče uvnitř rozsahu, ne na jeho
    /// začátku. Jinak by se popisky při scrollování posouvaly s obsahem
    /// místo aby stály na kulatých časech — a `00:00:03:07` je popisek,
    /// který nikdo nechce.
    public func rulerFrames(in range: Range<Frames>, interval: Frames) -> [Frames] {
        let step = interval.count
        guard step > 0, range.lowerBound < range.upperBound else { return [] }

        let low = range.lowerBound.count
        let high = range.upperBound.count

        // První násobek uvnitř rozsahu, tedy `ceil(low / step)` celočíselně.
        // Swift dělí k nule, takže u záporných hodnot vyjde podíl rovnou
        // nahoru a korekce se neuplatní — proto ta podmínka, ne `+ step - 1`.
        var index = low / step
        if index * step < low { index += 1 }

        var result: [Frames] = []
        var value = index * step
        while value < high {
            result.append(Frames(value))
            value += step
        }
        return result
    }
}
