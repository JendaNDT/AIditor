//
//  LoudnessMeterTests.swift
//  Projekt Krása — AudioEngine (fáze 7)
//
//  Kotvy jsou z ITU-R BS.1770-4, ne vymyšlené:
//  – tabulka koeficientů K-váhování pro 48 kHz (příloha 1),
//  – „full-scale sinus 997 Hz v jednom kanálu čte −3,01 LKFS".
//  Když spadnou, je rozbitá matematika, ne test.
//

import XCTest
@testable import AudioEngine

// MARK: - Pomůcky

private func sine(frequency: Double, amplitude: Double, seconds: Double,
                  sampleRate: Double) -> [Float] {
    let count = Int(seconds * sampleRate)
    return (0..<count).map { i in
        Float(amplitude * sin(2.0 * .pi * frequency * Double(i) / sampleRate))
    }
}

private func integratedLoudness(of channels: [[Float]], sampleRate: Double) -> Double? {
    var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: channels.count)
    meter.add(channels)
    return meter.integrated
}

// MARK: - Koeficienty proti tabulce ze standardu

final class KWeightingTests: XCTestCase {

    /// Příloha 1 BS.1770-4 dává koeficienty pro 48 kHz na 14 míst.
    /// Náš přepočet z analogového prototypu je musí reprodukovat.
    func testShelf48kSediSTabulkouStandardu() {
        let c = KWeighting.shelf(sampleRate: 48_000)
        XCTAssertEqual(c.b0, 1.53512485958697, accuracy: 1e-10)
        XCTAssertEqual(c.b1, -2.69169618940638, accuracy: 1e-10)
        XCTAssertEqual(c.b2, 1.19839281085285, accuracy: 1e-10)
        XCTAssertEqual(c.a1, -1.69065929318241, accuracy: 1e-10)
        XCTAssertEqual(c.a2, 0.73248077421585, accuracy: 1e-10)
    }

    func testHighPass48kSediSTabulkouStandardu() {
        let c = KWeighting.highPass(sampleRate: 48_000)
        XCTAssertEqual(c.b0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(c.b1, -2.0, accuracy: 1e-12)
        XCTAssertEqual(c.b2, 1.0, accuracy: 1e-12)
        XCTAssertEqual(c.a1, -1.99004745483398, accuracy: 1e-10)
        XCTAssertEqual(c.a2, 0.99007225036621, accuracy: 1e-10)
    }
}

// MARK: - Kalibrace metru

final class LoudnessCalibrationTests: XCTestCase {

    /// Věta ze standardu: 0 dBFS sinus 997 Hz v L, C nebo R → −3,01 LKFS.
    func testFullScaleSinus997Mono() {
        let signal = sine(frequency: 997, amplitude: 1.0, seconds: 10, sampleRate: 48_000)
        let loudness = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: 48_000))
        XCTAssertEqual(loudness, -3.01, accuracy: 0.05)
    }

    /// Lineárnost: −20 dBFS = o 20 LU méně.
    func testSinusMinus20dB() {
        let signal = sine(frequency: 997, amplitude: pow(10, -20.0 / 20.0),
                          seconds: 10, sampleRate: 48_000)
        let loudness = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: 48_000))
        XCTAssertEqual(loudness, -23.01, accuracy: 0.05)
    }

    /// Dva shodné kanály = dvojnásobný výkon = +3,01 LU proti monu.
    func testStereoObaKanalyPlnaUroven() {
        let signal = sine(frequency: 997, amplitude: 1.0, seconds: 10, sampleRate: 48_000)
        let loudness = try! XCTUnwrap(integratedLoudness(of: [signal, signal], sampleRate: 48_000))
        XCTAssertEqual(loudness, 0.0, accuracy: 0.06)
    }

    /// Přepočet koeficientů: na 44,1 kHz musí sinus vyjít stejně.
    func testJinaVzorkovaciFrekvence() {
        let signal = sine(frequency: 997, amplitude: 1.0, seconds: 10, sampleRate: 44_100)
        let loudness = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: 44_100))
        XCTAssertEqual(loudness, -3.01, accuracy: 0.05)
    }

    /// 32-bit float headroom: vzorky přes ±1 se měří, ne ořezávají.
    /// +6 dB nad full scale musí vyjít o 6 LU výš, ne saturovat na −3.
    func testHeadroomNadPlnouUrovni() {
        let signal = sine(frequency: 997, amplitude: 2.0, seconds: 10, sampleRate: 48_000)
        let loudness = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: 48_000))
        XCTAssertEqual(loudness, 3.01, accuracy: 0.05)
    }

    /// Tvar K-váhování: basy pod horní propustí čtou míň, výšky se
    /// shelfem víc. Nerovnosti, ne přesná čísla — přesnost drží kotvy výš.
    func testKVahovaniTvar() {
        let reference = try! XCTUnwrap(integratedLoudness(
            of: [sine(frequency: 997, amplitude: 1.0, seconds: 10, sampleRate: 48_000)],
            sampleRate: 48_000))
        let bass = try! XCTUnwrap(integratedLoudness(
            of: [sine(frequency: 60, amplitude: 1.0, seconds: 10, sampleRate: 48_000)],
            sampleRate: 48_000))
        let treble = try! XCTUnwrap(integratedLoudness(
            of: [sine(frequency: 8_000, amplitude: 1.0, seconds: 10, sampleRate: 48_000)],
            sampleRate: 48_000))
        XCTAssertLessThan(bass, reference - 2.0)
        XCTAssertGreaterThan(treble, reference + 2.5)
    }
}

// MARK: - Gatování

final class GatingTests: XCTestCase {

    /// Ticho za signálem nesmí integrovanou hlasitost stáhnout dolů —
    /// přesně kvůli tomu absolutní gate existuje. Prostý RMS by z 5 s
    /// tónu a 20 s ticha udělal −30: o ~7 dB vedle.
    ///
    /// Tolerance 0,2 LU je záměrná, ne z nouze: tři bloky na rozhraní
    /// tón→ticho nesou částečně obojí (75/50/25 % tónu), gate právem
    /// přežijí a výsledek o ~0,13 LU zředí. To je chování podle
    /// standardu — bloky se prostě překrývají přes hranici.
    func testAbsolutniGateIgnorujeTicho() {
        let sampleRate = 48_000.0
        let tone = sine(frequency: 997, amplitude: pow(10, -20.0 / 20.0),
                        seconds: 5, sampleRate: sampleRate)
        let toneAlone = try! XCTUnwrap(integratedLoudness(of: [tone], sampleRate: sampleRate))

        let silence = [Float](repeating: 0, count: Int(20 * sampleRate))
        let loudness = try! XCTUnwrap(integratedLoudness(of: [tone + silence], sampleRate: sampleRate))
        XCTAssertEqual(loudness, toneAlone, accuracy: 0.2)
    }

    /// Relativní gate: pasáž 25 LU pod hlasitou (ale nad −70) se vyloučí.
    /// Průměr obou bloků je ~3 LU pod hlasitou pasáží, práh −10 LU pod
    /// ním, tichá pasáž na −48 je hluboko pod prahem → integrovaná
    /// hlasitost je hlasitost hlasité pasáže samotné.
    func testRelativniGateVylouciTichouPasaz() {
        let sampleRate = 48_000.0
        let loud = sine(frequency: 997, amplitude: pow(10, -20.0 / 20.0),
                        seconds: 10, sampleRate: sampleRate)     // ≈ −23 LUFS
        let quiet = sine(frequency: 997, amplitude: pow(10, -45.0 / 20.0),
                         seconds: 10, sampleRate: sampleRate)    // ≈ −48 LUFS
        let loudness = try! XCTUnwrap(integratedLoudness(of: [loud + quiet], sampleRate: sampleRate))
        XCTAssertEqual(loudness, -23.01, accuracy: 0.3)
    }

    /// Pasáž jen ~5 LU pod hlasitou relativní gate přežít MUSÍ —
    /// gate je na ticho a šum, ne na dynamiku hudby.
    func testRelativniGateNechaMirneTissiPasaz() {
        let sampleRate = 48_000.0
        let loud = sine(frequency: 997, amplitude: pow(10, -20.0 / 20.0),
                        seconds: 10, sampleRate: sampleRate)     // ≈ −23 LUFS
        let softer = sine(frequency: 997, amplitude: pow(10, -25.0 / 20.0),
                          seconds: 10, sampleRate: sampleRate)   // ≈ −28 LUFS
        let loudness = try! XCTUnwrap(integratedLoudness(of: [loud + softer], sampleRate: sampleRate))
        // Energetický průměr obou polovin: 10·log₁₀((10⁻²·⁰ + 10⁻²·⁵)/2) − 0,7 ≈ −24,9.
        XCTAssertEqual(loudness, -24.9, accuracy: 0.3)
        // A hlavně: NENÍ to jen hlasitá polovina.
        XCTAssertLessThan(loudness, -24.0)
    }

    func testTichoNemaHlasitost() {
        let silence = [[Float]](repeating: [Float](repeating: 0, count: 48_000), count: 1)
        XCTAssertNil(integratedLoudness(of: silence, sampleRate: 48_000))
    }

    /// Kratší než jeden blok (400 ms) = není co gatovat.
    func testKratkySignalNemaHlasitost() {
        let signal = sine(frequency: 997, amplitude: 1.0, seconds: 0.3, sampleRate: 48_000)
        XCTAssertNil(integratedLoudness(of: [signal], sampleRate: 48_000))
    }

    /// 450 ms už jeden blok dá.
    func testPulSekundyStaci() {
        let signal = sine(frequency: 997, amplitude: 1.0, seconds: 0.45, sampleRate: 48_000)
        XCTAssertNotNil(integratedLoudness(of: [signal], sampleRate: 48_000))
    }
}

// MARK: - Streamování a prokládání

final class StreamingTests: XCTestCase {

    /// Krmení po kusech nepravidelné délky = týž výsledek jako naráz.
    /// Na tom stojí použití nad AVAssetReaderem, který vydává buffery,
    /// jak se mu zlíbí.
    func testStreamovaniPoKusech() {
        let sampleRate = 48_000.0
        let signal = sine(frequency: 997, amplitude: 0.5, seconds: 8, sampleRate: sampleRate)
        let wholeShot = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: sampleRate))

        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        var index = 0
        var chunk = 1
        while index < signal.count {
            let end = min(index + chunk, signal.count)
            meter.add([Array(signal[index..<end])])
            index = end
            chunk = (chunk * 7 + 13) % 9_999 + 1   // nepravidelné, deterministické
        }
        let streamed = try! XCTUnwrap(meter.integrated)
        XCTAssertEqual(streamed, wholeShot, accuracy: 1e-9)
    }

    func testProkladaneVzorkySediSPlanarnimi() {
        let sampleRate = 48_000.0
        let left = sine(frequency: 997, amplitude: 0.8, seconds: 5, sampleRate: sampleRate)
        let right = sine(frequency: 499, amplitude: 0.3, seconds: 5, sampleRate: sampleRate)
        let planar = try! XCTUnwrap(integratedLoudness(of: [left, right], sampleRate: sampleRate))

        var interleaved = [Float]()
        interleaved.reserveCapacity(left.count * 2)
        for i in 0..<left.count {
            interleaved.append(left[i])
            interleaved.append(right[i])
        }
        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: 2)
        meter.addInterleaved(interleaved)
        let fromInterleaved = try! XCTUnwrap(meter.integrated)
        XCTAssertEqual(fromInterleaved, planar, accuracy: 1e-9)
    }
}

// MARK: - Profily a gain

final class LoudnessProfileTests: XCTestCase {

    func testCileProfilu() {
        XCTAssertEqual(LoudnessProfile.web.targetLUFS, -14.0)
        XCTAssertEqual(LoudnessProfile.broadcast.targetLUFS, -23.0)
    }

    func testGainNaCil() {
        XCTAssertEqual(
            LoudnessNormalization.gainDecibels(measured: -18.5, target: -14.0),
            4.5, accuracy: 1e-12)
        XCTAssertEqual(
            LoudnessNormalization.gainDecibels(measured: -18.5, target: -23.0),
            -4.5, accuracy: 1e-12)
    }

    func testLinearniGain() {
        XCTAssertEqual(LoudnessNormalization.linearGain(decibels: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(LoudnessNormalization.linearGain(decibels: 6.0206), 2.0, accuracy: 1e-4)
        XCTAssertEqual(LoudnessNormalization.linearGain(decibels: -20), 0.1, accuracy: 1e-12)
    }

    /// Kruh se uzavírá: změř → spočítej gain → aplikuj → přeměř → cíl.
    func testNormalizaceKonciNaCili() {
        let sampleRate = 48_000.0
        let signal = sine(frequency: 997, amplitude: 0.05, seconds: 10, sampleRate: sampleRate)
        let measured = try! XCTUnwrap(integratedLoudness(of: [signal], sampleRate: sampleRate))

        let gain = Float(LoudnessNormalization.linearGain(
            decibels: LoudnessNormalization.gainDecibels(
                measured: measured, target: LoudnessProfile.web.targetLUFS)))
        let normalized = signal.map { $0 * gain }
        let remeasured = try! XCTUnwrap(integratedLoudness(of: [normalized], sampleRate: sampleRate))
        XCTAssertEqual(remeasured, -14.0, accuracy: 0.05)
    }
}
