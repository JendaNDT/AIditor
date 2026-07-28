//
//  WaveformSyncTests.swift
//  Projekt Krása — AudioEngine (fáze 7)
//
//  Kotvy: FFT proti naivnímu DFT (dvě nezávislé formulace, O(n²) vs
//  O(n·log n)) a korelace proti přímému součtu. Syntetické nahrávky mají
//  AMPLITUDOVOU strukturU (bursty) — čistý bílý šum má plochou obálku
//  a obálková korelace by na něm neměla co chytit; řeč a hudba strukturu
//  mají, testovací signál ji proto musí mít taky.
//

import XCTest
@testable import AudioEngine

// MARK: - Pomůcky

/// Deterministický xorshift64 — testy musí být opakovatelné.
private struct Random {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000.0
    }
}

/// Šum s náhodnou amplitudou po 50ms segmentech — „program", jehož
/// obálka nese otisk, podle kterého se dá synchronizovat.
private func burstSignal(seconds: Double, sampleRate: Double, seed: UInt64) -> [Float] {
    var random = Random(seed: seed)
    let count = Int(seconds * sampleRate)
    let segment = max(1, Int(sampleRate * 0.05))
    var out = [Float](repeating: 0, count: count)
    var amplitude = 0.0
    for i in 0..<count {
        if i % segment == 0 { amplitude = random.next() }
        out[i] = Float(amplitude * (random.next() * 2 - 1))
    }
    return out
}

private let testRate = 8_000.0   // malá frekvence = rychlé testy, na principu nic nemění

// MARK: - FFT

final class FFTTests: XCTestCase {

    /// FFT musí dát totéž co naivní DFT — dvě formulace, jeden výsledek.
    func testFFTProtiNaivnimuDFT() {
        var random = Random(seed: 7)
        let n = 16
        let inputReal = (0..<n).map { _ in random.next() * 2 - 1 }
        let inputImag = (0..<n).map { _ in random.next() * 2 - 1 }

        var real = inputReal
        var imag = inputImag
        FFT.transform(real: &real, imag: &imag)

        for k in 0..<n {
            var sumReal = 0.0
            var sumImag = 0.0
            for t in 0..<n {
                let angle = -2.0 * .pi * Double(k * t) / Double(n)
                sumReal += inputReal[t] * cos(angle) - inputImag[t] * sin(angle)
                sumImag += inputReal[t] * sin(angle) + inputImag[t] * cos(angle)
            }
            XCTAssertEqual(real[k], sumReal, accuracy: 1e-9)
            XCTAssertEqual(imag[k], sumImag, accuracy: 1e-9)
        }
    }

    func testInverzniFFTVraciVstup() {
        var random = Random(seed: 11)
        let original = (0..<64).map { _ in random.next() * 2 - 1 }
        var real = original
        var imag = [Double](repeating: 0, count: 64)
        FFT.transform(real: &real, imag: &imag)
        FFT.transform(real: &real, imag: &imag, inverse: true)
        for i in 0..<64 {
            XCTAssertEqual(real[i], original[i], accuracy: 1e-10)
            XCTAssertEqual(imag[i], 0, accuracy: 1e-10)
        }
    }

    /// Korelace přes FFT proti přímému součtu — všechny posuny.
    func testKorelaceProtiPrimemuSoucty() {
        var random = Random(seed: 13)
        let a = (0..<23).map { _ in random.next() * 2 - 1 }   // schválně ne mocniny dvou
        let b = (0..<17).map { _ in random.next() * 2 - 1 }
        let viaFFT = FFT.crossCorrelation(a, b)
        XCTAssertEqual(viaFFT.count, a.count + b.count - 1)

        for lag in -(b.count - 1)...(a.count - 1) {
            var direct = 0.0
            for i in 0..<b.count {
                let j = i + lag
                if j >= 0 && j < a.count { direct += a[j] * b[i] }
            }
            XCTAssertEqual(viaFFT[lag + b.count - 1], direct, accuracy: 1e-9,
                           "lag \(lag)")
        }
    }
}

// MARK: - Obálka

final class EnvelopeTests: XCTestCase {

    func testKonstantniSignalDaKonstantniObalku() {
        let signal = [Float](repeating: 0.5, count: 400)
        let envelope = WaveformSync.envelope(signal, window: 40)
        XCTAssertEqual(envelope.count, 10)
        for value in envelope { XCTAssertEqual(value, 0.5, accuracy: 1e-6) }
    }

    func testImpulsSkonciVeSpravnemBinu() {
        var signal = [Float](repeating: 0, count: 400)
        signal[250] = 1.0   // bin 6 při okně 40
        let envelope = WaveformSync.envelope(signal, window: 40)
        XCTAssertEqual(envelope.firstIndex(of: envelope.max()!), 6)
    }
}

// MARK: - Synchronizace

final class WaveformSyncTests: XCTestCase {

    /// Rekordér spuštěný POZDĚJI: kandidátovi chybí začátek → jeho
    /// soubor patří na kladnou pozici. Shodné vzorky → po doladění přesně.
    func testKandidatZacalPozdeji() throws {
        let reference = burstSignal(seconds: 30, sampleRate: testRate, seed: 42)
        let skip = Int(1.2345 * testRate)   // schválně mimo mřížku obálky
        let candidate = Array(reference[skip...])
        let match = try XCTUnwrap(WaveformSync.offset(
            reference: reference, candidate: candidate, sampleRate: testRate))
        XCTAssertEqual(match.offsetSeconds, 1.2345, accuracy: 0.001)
        XCTAssertGreaterThan(match.confidence, 0.8)
    }

    /// Rekordér spuštěný DŘÍV: kandidát má navíc úvod → záporná pozice.
    func testKandidatZacalDriv() throws {
        let reference = burstSignal(seconds: 30, sampleRate: testRate, seed: 43)
        let lead = [Float](repeating: 0, count: Int(1.5 * testRate))
        let candidate = lead + reference
        let match = try XCTUnwrap(WaveformSync.offset(
            reference: reference, candidate: candidate, sampleRate: testRate))
        XCTAssertEqual(match.offsetSeconds, -1.5, accuracy: 0.001)
        XCTAssertGreaterThan(match.confidence, 0.8)
    }

    /// Jiný gain nesmí vadit — klopák a kamera nikdy nemají stejnou úroveň.
    func testJinyGainNevadi() throws {
        let reference = burstSignal(seconds: 30, sampleRate: testRate, seed: 44)
        let skip = Int(2.0 * testRate)
        let candidate = reference[skip...].map { $0 * 0.1 }
        let match = try XCTUnwrap(WaveformSync.offset(
            reference: reference, candidate: candidate, sampleRate: testRate))
        XCTAssertEqual(match.offsetSeconds, 2.0, accuracy: 0.001)
    }

    /// Dvě „různá mikrofonní snímání" téže události: společný zdroj
    /// + nezávislý šum srovnatelné úrovně v každém. Posun se najde
    /// a jistota zůstane vysoko nad úrovní nesouvisejících nahrávek.
    func testPrezijeNezavislySum() throws {
        let source = burstSignal(seconds: 30, sampleRate: testRate, seed: 45)
        let noiseA = burstSignal(seconds: 30, sampleRate: testRate, seed: 46)
        let noiseB = burstSignal(seconds: 30, sampleRate: testRate, seed: 47)

        let reference = zip(source, noiseA).map { 0.5 * $0 + 0.25 * $1 }
        let skip = Int(3.0 * testRate)
        let candidate = zip(source[skip...], noiseB[skip...]).map { 0.8 * $0 + 0.4 * $1 }

        let match = try XCTUnwrap(WaveformSync.offset(
            reference: reference, candidate: candidate, sampleRate: testRate))
        XCTAssertEqual(match.offsetSeconds, 3.0, accuracy: 0.002)
        XCTAssertGreaterThan(match.confidence, 0.4)
    }

    /// Nesouvisející nahrávky: nějaký „nejlepší posun" vyjde vždycky,
    /// ale jistota ho musí prozradit. Tohle je pojistka proti tichému
    /// položení cizího zvuku na špatné místo.
    func testNesouvisejiciNahravkyMajiNizkouJistotu() throws {
        let reference = burstSignal(seconds: 30, sampleRate: testRate, seed: 48)
        let unrelated = burstSignal(seconds: 30, sampleRate: testRate, seed: 99)
        let match = try XCTUnwrap(WaveformSync.offset(
            reference: reference, candidate: unrelated, sampleRate: testRate))
        XCTAssertLessThan(match.confidence, 0.2)
    }

    func testKratkySignalVraciNil() {
        let reference = burstSignal(seconds: 30, sampleRate: testRate, seed: 50)
        let tiny = [Float](repeating: 0.5, count: 10)
        XCTAssertNil(WaveformSync.offset(reference: reference, candidate: tiny,
                                         sampleRate: testRate))
    }

    func testSameTichoVraciNil() {
        let silence = [Float](repeating: 0, count: Int(10 * testRate))
        XCTAssertNil(WaveformSync.offset(reference: silence, candidate: silence,
                                         sampleRate: testRate))
    }
}
