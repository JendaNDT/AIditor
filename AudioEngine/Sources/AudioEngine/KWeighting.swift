//
//  KWeighting.swift
//  Projekt Krása — AudioEngine (fáze 7)
//
//  K-váhovací filtr podle ITU-R BS.1770-4: shelf modelující hlavu
//  posluchače + RLB horní propust. Standard uvádí koeficienty jen pro
//  48 kHz; pro ostatní frekvence se přepočítávají z analogového
//  prototypu bilineární transformací s prewarpingem — týž postup
//  a tytéž konstanty používá referenční implementace libebur128.
//  Že přepočet sedí, hlídá test proti tabulce ze standardu.
//
//  Čistý Swift, žádné AVFoundation — testovatelné i na Linuxu.
//

import Foundation

public enum KWeighting {

    /// Koeficienty bikvadratického filtru v normalizovaném tvaru (a0 = 1):
    /// y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]
    public struct Coefficients: Equatable, Sendable {
        public let b0, b1, b2, a1, a2: Double
    }

    /// První stupeň: shelf zvedající pásmo nad ~2 kHz o ~4 dB
    /// (akustický vliv hlavy posluchače).
    public static func shelf(sampleRate: Double) -> Coefficients {
        let f0 = 1681.974450955533
        let gain = 3.999843853973347          // dB
        let q = 0.7071752369554196

        let k = tan(.pi * f0 / sampleRate)
        let vh = pow(10.0, gain / 20.0)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1.0 + k / q + k * k

        return Coefficients(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2.0 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2.0 * (k * k - 1.0) / a0,
            a2: (1.0 - k / q + k * k) / a0)
    }

    /// Druhý stupeň: RLB horní propust (~38 Hz) — basy pod ní lidské
    /// vnímání hlasitosti skoro neovlivňují. Čitatel {1, −2, 1} je přímo
    /// ze standardu, nenormalizuje se.
    public static func highPass(sampleRate: Double) -> Coefficients {
        let f0 = 38.13547087602444
        let q = 0.5003270373238773

        let k = tan(.pi * f0 / sampleRate)
        let a0 = 1.0 + k / q + k * k

        return Coefficients(
            b0: 1.0,
            b1: -2.0,
            b2: 1.0,
            a1: 2.0 * (k * k - 1.0) / a0,
            a2: (1.0 - k / q + k * k) / a0)
    }
}

/// Bikvadratický filtr se stavem — Direct Form I, stav v Double.
/// Vstupy jsou Float (formát bufferů), počítá se v Double: dva kaskádní
/// filtry nad hodinami materiálu by ve Floatu střádaly šum.
struct Biquad {
    private let c: KWeighting.Coefficients
    private var x1 = 0.0, x2 = 0.0
    private var y1 = 0.0, y2 = 0.0

    init(_ coefficients: KWeighting.Coefficients) {
        c = coefficients
    }

    mutating func process(_ x: Double) -> Double {
        let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
