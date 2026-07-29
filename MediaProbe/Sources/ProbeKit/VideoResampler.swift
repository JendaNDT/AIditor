//
//  VideoResampler.swift
//  Projekt Krása / ProbeKit
//
//  Zero-order hold: pro každý výstupní slot se vezme poslední zdrojový
//  snímek, jehož prezentační čas ≤ času slotu.
//
//  Jeden mechanismus pokryje všechny zvláštnosti zdroje:
//    · zahozený snímek (2× modus) → tentýž snímek se trefí do dvou slotů
//    · delší první vzorek         → navzorkuje se na pravidelné sloty
//    · useknutý poslední          → zmizí, mřížka končí na celém snímku
//    · nepravidelné časování      → slot si vezme, co v tu chvíli platí
//
//  Zvláštnosti zdroje se schválně NEpřenášejí. Cílem je pravidelný takt.
//

import AVFoundation
import CoreMedia
import Foundation

final class VideoResampler {

    private let output: AVAssetReaderOutput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let input: AVAssetWriterInput
    /// Kvůli chybové hlášce — `AVAssetWriterInput` na svůj zapisovač neukazuje.
    private weak var writer: AVAssetWriter?
    private let frameDuration: CMTime
    private let slotCount: Int
    /// Zdrojový čas prvního slotu. Nenulový při exportu výřezu (fáze 17):
    /// čtečka pak dodává vzorky od `startTime` a zapisovač dostal tentýž
    /// čas jako začátek session, takže výsledný soubor stejně začíná nulou.
    private let startTime: CMTime
    /// Úprava snímku před zápisem (fáze 11: titulky). Dostává slot, ne PTS —
    /// tentýž zdrojový snímek podržený přes víc slotů může v každém slotu
    /// potřebovat jinou dekoraci (titulek začíná/končí uprostřed držení).
    private let frameDecorator: ((CVPixelBuffer, Int) -> CVPixelBuffer)?

    /// Snímek, který právě platí pro aktuální slot.
    private var current: (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)?
    /// Už přečtený snímek, který ale patří až některému pozdějšímu slotu.
    private var lookahead: (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)?
    private var sourceExhausted = false

    private(set) var slot = 0
    private(set) var written = 0
    private(set) var held = 0
    private(set) var failure: Error?

    /// Zlomek hotových slotů — pro ukazatel průběhu exportu. Volá se na
    /// frontě zapisovače, volající si musí přeskočit na main sám.
    var onProgress: ((Double) -> Void)?

    /// PTS snímku použitého v předchozím slotu — kvůli počítání podržených.
    private var lastUsedPTS: CMTime?

    init(output: AVAssetReaderOutput,
         adaptor: AVAssetWriterInputPixelBufferAdaptor,
         input: AVAssetWriterInput,
         writer: AVAssetWriter,
         frameDuration: CMTime,
         slotCount: Int,
         startTime: CMTime = .zero,
         frameDecorator: ((CVPixelBuffer, Int) -> CVPixelBuffer)? = nil) {
        self.output = output
        self.adaptor = adaptor
        self.input = input
        self.writer = writer
        self.frameDuration = frameDuration
        self.slotCount = slotCount
        self.startTime = startTime
        self.frameDecorator = frameDecorator
    }

    /// Naplní zapisovač, dokud přijímá data. Vrací `true`, když je hotovo.
    func pump() -> Bool {
        while input.isReadyForMoreMediaData {
            guard failure == nil else { return finish() }
            guard slot < slotCount else { return finish() }

            // Čas slotu se počítá násobením indexu, ne přičítáním v cyklu —
            // sčítání CMTime by po tisících snímcích nakumulovalo chybu.
            // Při exportu výřezu je mřížka posunutá o začátek rozsahu.
            let slotTime = CMTimeAdd(startTime,
                                     CMTime(value: frameDuration.value * Int64(slot),
                                            timescale: frameDuration.timescale))

            advance(to: slotTime)

            guard let frame = current ?? peek() else {
                // Zdroj došel dřív, než se sloty vyčerpaly.
                return finish()
            }
            if current == nil { current = consume() }

            let pixel = frameDecorator?(frame.pixel, slot) ?? frame.pixel
            if !adaptor.append(pixel, withPresentationTime: slotTime) {
                failure = writer?.error
                    ?? ProbeError.message("Snímek \(slot) se nepodařilo zapsat.")
                return finish()
            }

            if let last = lastUsedPTS, last == frame.pts { held += 1 }
            lastUsedPTS = frame.pts
            written += 1
            slot += 1

            // Jednou za sekundu obrazu — častěji nemá na ukazateli co ukázat.
            if written % 30 == 0, slotCount > 0 {
                onProgress?(Double(written) / Double(slotCount))
            }
        }
        return false
    }

    // MARK: - Posun zdrojem

    /// Posune `current` na poslední snímek, jehož PTS ≤ `time`.
    private func advance(to time: CMTime) {
        while let next = peek(), next.pts <= time {
            current = consume()
        }
    }

    private func peek() -> (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)? {
        if let lookahead { return lookahead }
        guard !sourceExhausted else { return nil }

        while let buffer = output.copyNextSampleBuffer() {
            guard let pixel = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            guard pts.isValid else { continue }
            lookahead = (pts: pts, sample: buffer, pixel: pixel)
            return lookahead
        }
        sourceExhausted = true
        return nil
    }

    private func consume() -> (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)? {
        defer { lookahead = nil }
        return lookahead
    }

    private func finish() -> Bool {
        input.markAsFinished()
        current = nil
        lookahead = nil
        return true
    }
}
