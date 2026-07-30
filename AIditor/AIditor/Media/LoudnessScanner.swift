//
//  LoudnessScanner.swift
//  Projekt AIditor
//
//  Fáze 7, modul 3: změří integrovanou hlasitost a špičku zvuku
//  kompozice PŘED exportem. Čte tímtéž aparátem jako export
//  (`AVAssetReaderAudioMixOutput` s mixem a `.timeDomain` korekcí),
//  takže měří přesně to, co by se zapsalo do souboru.
//
//  Matematiku dělá `LoudnessMeter` z balíčku `AudioEngine`
//  (ITU-R BS.1770-4, ověřený proti pyloudnorm). Tady je jen čtení
//  bufferů a jejich předání metru.
//
//  <https://developer.apple.com/documentation/coremedia/cmsamplebuffergetdatabuffer(_:)>
//  <https://developer.apple.com/documentation/coremedia/cmblockbuffercopydatabytes(_:atoffset:datalength:destination:)>
//

import AVFoundation
import AudioEngine
import Foundation
import ProbeKit

enum LoudnessScanner {

    struct Result {
        /// Integrovaná hlasitost v LUFS; `nil` = samé ticho.
        let integratedLUFS: Double?
        /// TRUE PEAK, lineárně (1,0 = full scale) — 4× převzorkování
        /// (fáze 16, `TruePeakMeter`), vidí i mezivzorkové špičky.
        /// Dřívější špička vzorků je podmnožina: true peak ≥ špička
        /// vzorků vždy, takže strop normalizace jen zpřísněl.
        let truePeakLinear: Double
    }

    /// Projede zvuk assetu a vrátí hlasitost + špičku. `nil` = asset
    /// nemá zvukovou stopu. Synchronně čte celý zvuk — volá se z async
    /// kontextu mimo hlavní vlákno; u minutových kompozic jde o sekundy.
    static func scan(asset: AVAsset, audioMix: AVAudioMix?) async throws -> Result? {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return nil }

        // Formát prvního zdroje; víc než stereo se do měření skládá
        // stejně jako do exportu (mix output míchá do cílového počtu).
        var sampleRate = 48_000.0
        var channels = 2
        let formats = try await audioTracks[0].load(.formatDescriptions)
        if let asbd = formats.first.flatMap({
            CMAudioFormatDescriptionGetStreamBasicDescription($0) }) {
            if asbd.pointee.mSampleRate > 0 { sampleRate = asbd.pointee.mSampleRate }
            if asbd.pointee.mChannelsPerFrame > 0 {
                channels = min(Int(asbd.pointee.mChannelsPerFrame), 2)
            }
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: CFRRenderer.pcmFloatSettings(channels: UInt32(channels),
                                                       sampleRate: sampleRate))
        output.alwaysCopiesSampleData = false
        output.audioMix = audioMix
        // Stejná korekce výšky jako v exportu — škálované úseky ramp mění
        // zvuk a měřit se musí výsledek, ne zdroj.
        output.audioTimePitchAlgorithm = .timeDomain
        guard reader.canAdd(output) else {
            throw NSError(domain: "LoudnessScanner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Čtečka nepřijala zvukový výstup."])
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "LoudnessScanner", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Čtení zvuku se nepodařilo spustit."])
        }

        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: channels)
        var peakMeter = TruePeakMeter(channelCount: channels)

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= MemoryLayout<Float>.size else { continue }
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            peakMeter.addInterleaved(samples)
            meter.addInterleaved(samples)
        }

        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "LoudnessScanner", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Čtení zvuku selhalo."])
        }
        return Result(integratedLUFS: meter.integrated,
                      truePeakLinear: peakMeter.linearPeak)
    }
}
