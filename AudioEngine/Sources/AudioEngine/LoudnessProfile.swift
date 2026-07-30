//
//  LoudnessProfile.swift
//  Projekt AIditor — AudioEngine (fáze 7)
//
//  Dva profily normalizace podle rozhodnutí ve specifikaci (sekce 7.1,
//  revidovaná): výchozí je Web −14 LUFS (YouTube nad tento práh jen
//  ztišuje, nikdy nezesiluje), Vysílání −23 LUFS dle EBU R128 pro
//  dodávky do TV. Jeden pevný cíl −23 pro všechno byla chyba původní
//  specifikace — pro sociální sítě je citelně tichý.
//

import Foundation

public enum LoudnessProfile: String, Codable, CaseIterable, Sendable {
    /// Výchozí. „−14" je zavedený zvyk, ne garance platforem.
    case web
    /// EBU R128, −23 LUFS ±0,5 LU.
    case broadcast

    public var targetLUFS: Double {
        switch self {
        case .web: return -14.0
        case .broadcast: return -23.0
        }
    }

    public var displayName: String {
        switch self {
        case .web: return "Web / sociální sítě (−14 LUFS)"
        case .broadcast: return "Vysílání EBU R128 (−23 LUFS)"
        }
    }
}

public enum LoudnessNormalization {

    /// Gain v dB, který dostane změřený materiál na cíl. Kladný = zesílit.
    public static func gainDecibels(measured: Double, target: Double) -> Double {
        target - measured
    }

    /// Převod dB → lineární násobitel vzorků.
    public static func linearGain(decibels: Double) -> Double {
        pow(10.0, decibels / 20.0)
    }
}
