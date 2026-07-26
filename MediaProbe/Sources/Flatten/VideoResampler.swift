//
//  VideoResampler.swift
//  Projekt Krása / Flatten
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
import ProbeKit

final class VideoResampler {

    private let output: AVAssetReaderTrackOutput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let input: AVAssetWriterInput
    /// Kvůli chybové hlášce — `AVAssetWriterInput` na svůj zapisovač neukazuje.
    private weak var writer: AVAssetWriter?
    private let frameDuration: CMTime
    private let slotCount: Int

    /// Snímek, který právě platí pro aktuální slot.
    private var current: (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)?
    /// Už přečtený snímek, který ale patří až některému pozdějšímu slotu.
    private var lookahead: (pts: CMTime, sample: CMSampleBuffer, pixel: CVPixelBuffer)?
    private var sourceExhausted = false

    private(set) var slot = 0
    private(set) var written = 0
    private(set) var held = 0
    private(set) var failure: Error?

    /// PTS snímku použitého v předchozím slotu — kvůli počítání podržených.
    private var lastUsedPTS: CMTime?

    init(output: AVAssetReaderTrackOutput,
         adaptor: AVAssetWriterInputPixelBufferAdaptor,
         input: AVAssetWriterInput,
         writer: AVAssetWriter,
         frameDuration: CMTime,
         slotCount: Int) {
        self.output = output
        self.adaptor = adaptor
        self.input = input
        self.writer = writer
        self.frameDuration = frameDuration
        self.slotCount = slotCount
    }

    /// Naplní zapisovač, dokud přijímá data. Vrací `true`, když je hotovo.
    func pump() -> Bool {
        while input.isReadyForMoreMediaData {
            guard failure == nil else { return finish() }
            guard slot < slotCount else { return finish() }

            // Čas slotu se počítá násobením indexu, ne přičítáním v cyklu —
            // sčítání CMTime by po tisících snímcích nakumulovalo chybu.
            let slotTime = CMTime(value: frameDuration.value * Int64(slot),
                                  timescale: frameDuration.timescale)

            advance(to: slotTime)

            guard let frame = current ?? peek() else {
                // Zdroj došel dřív, než se sloty vyčerpaly.
                return finish()
            }
            if current == nil { current = consume() }

            if !adaptor.append(frame.pixel, withPresentationTime: slotTime) {
                failure = writer?.error
                    ?? ProbeError.message("Snímek \(slot) se nepodařilo zapsat.")
                return finish()
            }

            if let last = lastUsedPTS, last == frame.pts { held += 1 }
            lastUsedPTS = frame.pts
            written += 1
            slot += 1
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
