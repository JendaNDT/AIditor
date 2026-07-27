//
//  Time.swift
//  TimelineModel — Projekt Krása
//
//  Dvě časové soustavy a jediná hranice mezi nimi.
//
//  OSA PROJEKTU  — pozice a délky klipů, celé snímky základny (30 fps) → `Frames`
//  ZDROJOVÝ ČAS  — odkud se ve zdroji bere, délka assetu, edit list  → `SourceTime`
//
//  Zdroje mají vlastní frekvenci (30,01 / 59,68 / 120 fps). Míchat ji se
//  základnou projektu je přesně ta chyba, před kterou varuje pravidlo
//  „nikdy neodvozuj čísla snímků ze zdrojových časových značek".
//

import Foundation

// MARK: - Čas na ose

/// Čas na časové ose projektu v celých snímcích. Používá se pro pozici
/// i pro délku, stejně jako `CMTime`.
///
/// **Konce rozsahů jsou vždy exkluzivní:** klip `[10, 20)` sousedí s `[20, 30)`
/// a nepřekrývají se.
///
/// Proč celé snímky a ne sekundy: klip trvá 8 s a další začíná tam, kde
/// předchozí končí. S desetinnými čísly vyjde 7,999999 nebo 8,000001, klipy
/// se o mikrosekundu překryjí nebo mezi nimi zůstane neviditelná mezera, a po
/// padesáti klipech je chyba nasčítaná. Spike 0 tohle řešil u rampu stejně —
/// časy se skládají kumulativně v celých tickách.
public struct Frames: Hashable, Comparable, Codable, Sendable {
    public var count: Int

    public init(_ count: Int) { self.count = count }

    public static let zero = Frames(0)

    public static func < (a: Frames, b: Frames) -> Bool { a.count < b.count }
    public static func + (a: Frames, b: Frames) -> Frames { Frames(a.count + b.count) }
    public static func - (a: Frames, b: Frames) -> Frames { Frames(a.count - b.count) }
    public static prefix func - (a: Frames) -> Frames { Frames(-a.count) }
    public static func += (a: inout Frames, b: Frames) { a = a + b }
    public static func -= (a: inout Frames, b: Frames) { a = a - b }

    /// Zakóduje se jako holé číslo, ne jako `{"count": 5}`.
    public init(from decoder: Decoder) throws {
        count = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(count)
    }
}

// Převod na sekundy tu ZÁMĚRNĚ není. Kdyby byl, nic by nebránilo převést
// osové snímky frekvencí assetu — tedy přesně tou záměnou, které se model
// brání. Převod žije na `Timeline`, která zná základnu projektu.

// MARK: - Zdrojový čas

/// Čas ve zdrojovém souboru jako přesný zlomek `value / timescale`.
///
/// Vlastní typ, ne `CMTime`: **`CMTime` není `Codable`**, takže by se struktura
/// s ním nedala serializovat a `Codable` syntéza by selhala při překladu.
/// https://developer.apple.com/documentation/coremedia/cmtime
/// Navíc formát na disku pak nezávisí na tom, co Apple vygeneruje.
///
/// Na `CMTime` se převádí až na hranici s AVFoundation, mimo tenhle modul.
public struct SourceTime: Hashable, Comparable, Codable, Sendable {
    public var value: Int64
    public var timescale: Int32

    public init(value: Int64, timescale: Int32) {
        precondition(timescale > 0, "timescale musí být kladná")
        self.value = value
        self.timescale = timescale
    }

    public static let zero = SourceTime(value: 0, timescale: 90_000)

    /// Timescale projektu. 90000 je dělitelná 30 i 25 a sedí na to,
    /// co už používá `PlaybackController` při seeku.
    public static let projectTimescale: Int32 = 90_000

    public var seconds: Double { Double(value) / Double(timescale) }

    /// Přepočet na jinou timescale. Zaokrouhluje k nejbližšímu — použití je
    /// jen pro porovnávání a sčítání, kde půltick nehraje roli. Na hranici
    /// soustav (`Timeline.availableFrames`) se zaokrouhluje výhradně dolů.
    public func converted(to newScale: Int32) -> SourceTime {
        guard newScale != timescale else { return self }
        let scaled = (Double(value) * Double(newScale) / Double(timescale)).rounded()
        return SourceTime(value: Int64(scaled), timescale: newScale)
    }

    /// Sečte dva časy ve společné timescale. Aby se nesčítaly zlomky
    /// s různým jmenovatelem přes `Double`, převede se na jemnější z obou.
    private static func aligned(_ a: SourceTime, _ b: SourceTime) -> (Int64, Int64, Int32) {
        let scale = max(a.timescale, b.timescale)
        return (a.converted(to: scale).value, b.converted(to: scale).value, scale)
    }

    public static func + (a: SourceTime, b: SourceTime) -> SourceTime {
        let (x, y, s) = aligned(a, b)
        return SourceTime(value: x + y, timescale: s)
    }

    public static func - (a: SourceTime, b: SourceTime) -> SourceTime {
        let (x, y, s) = aligned(a, b)
        return SourceTime(value: x - y, timescale: s)
    }

    public static func < (a: SourceTime, b: SourceTime) -> Bool {
        let (x, y, _) = aligned(a, b)
        return x < y
    }

    public static func == (a: SourceTime, b: SourceTime) -> Bool {
        let (x, y, _) = aligned(a, b)
        return x == y
    }

    public func hash(into hasher: inout Hasher) {
        // Musí odpovídat ==, které porovnává napříč timescale.
        hasher.combine(converted(to: Self.projectTimescale).value)
    }
}

extension SourceTime {
    public init(seconds: Double, timescale: Int32 = SourceTime.projectTimescale) {
        self.init(value: Int64((seconds * Double(timescale)).rounded()), timescale: timescale)
    }
}
