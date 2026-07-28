//
//  FFT.swift
//  Projekt Krása — AudioEngine (fáze 7)
//
//  Iterativní radix-2 FFT (Cooley–Tukey) v čistém Swiftu. Žádný
//  Accelerate — balíček se testuje i na Linuxu a korelace obálek
//  (stovky tisíc binů) je pro tenhle rozsah dost rychlá i takhle.
//
//  Správnost drží test proti naivnímu DFT na malých vstupech — dvě
//  nezávislé formulace téhož, O(n²) proti O(n·log n).
//

import Foundation

enum FFT {

    static func isPowerOfTwo(_ n: Int) -> Bool { n > 0 && n & (n - 1) == 0 }

    static func nextPowerOfTwo(_ n: Int) -> Int {
        var power = 1
        while power < n { power <<= 1 }
        return power
    }

    /// FFT na místě. `real`/`imag` musí mít shodnou délku rovnou mocnině
    /// dvou. Inverzní transformace včetně dělení 1/n — `transform` a
    /// `transform(inverse:)` po sobě vrací vstup.
    static func transform(real: inout [Double], imag: inout [Double], inverse: Bool = false) {
        let n = real.count
        precondition(n == imag.count, "real a imag musí být stejně dlouhé")
        precondition(isPowerOfTwo(n), "délka musí být mocnina dvou")
        guard n > 1 else { return }

        // Přeuspořádání bitovým zrcadlením.
        var j = 0
        for i in 0..<(n - 1) {
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
            var mask = n >> 1
            while j & mask != 0 {
                j &= ~mask
                mask >>= 1
            }
            j |= mask
        }

        // Motýlky po vrstvách.
        var length = 2
        while length <= n {
            let angle = (inverse ? 2.0 : -2.0) * .pi / Double(length)
            let wReal = cos(angle)
            let wImag = sin(angle)
            var start = 0
            while start < n {
                var factorReal = 1.0
                var factorImag = 0.0
                for offset in 0..<(length / 2) {
                    let even = start + offset
                    let odd = even + length / 2
                    let tReal = factorReal * real[odd] - factorImag * imag[odd]
                    let tImag = factorReal * imag[odd] + factorImag * real[odd]
                    real[odd] = real[even] - tReal
                    imag[odd] = imag[even] - tImag
                    real[even] += tReal
                    imag[even] += tImag
                    let nextReal = factorReal * wReal - factorImag * wImag
                    factorImag = factorReal * wImag + factorImag * wReal
                    factorReal = nextReal
                }
                start += length
            }
            length <<= 1
        }

        if inverse {
            let scale = 1.0 / Double(n)
            for i in 0..<n {
                real[i] *= scale
                imag[i] *= scale
            }
        }
    }

    /// Úplná křížová korelace přes FFT: výsledek pro posuny (lag)
    /// −(nb−1) … +(na−1), indexované `lag + (nb − 1)`.
    /// corr[lag] = Σ a[i+lag]·b[i] — kladný lag = `b` sedí dál v `a`.
    static func crossCorrelation(_ a: [Double], _ b: [Double]) -> [Double] {
        let na = a.count
        let nb = b.count
        guard na > 0, nb > 0 else { return [] }
        let n = nextPowerOfTwo(na + nb - 1)

        var aReal = a + [Double](repeating: 0, count: n - na)
        var aImag = [Double](repeating: 0, count: n)
        var bReal = b + [Double](repeating: 0, count: n - nb)
        var bImag = [Double](repeating: 0, count: n)

        transform(real: &aReal, imag: &aImag)
        transform(real: &bReal, imag: &bImag)

        // A · conj(B)
        var productReal = [Double](repeating: 0, count: n)
        var productImag = [Double](repeating: 0, count: n)
        for i in 0..<n {
            productReal[i] = aReal[i] * bReal[i] + aImag[i] * bImag[i]
            productImag[i] = aImag[i] * bReal[i] - aReal[i] * bImag[i]
        }
        transform(real: &productReal, imag: &productImag, inverse: true)

        // Kruhový výsledek přeskládat na lineární: záporné lagy jsou na
        // konci bufferu (kruhová konvoluce), kladné na začátku.
        var result = [Double](repeating: 0, count: na + nb - 1)
        for lag in -(nb - 1)...(na - 1) {
            let index = lag >= 0 ? lag : n + lag
            result[lag + nb - 1] = productReal[index]
        }
        return result
    }
}
