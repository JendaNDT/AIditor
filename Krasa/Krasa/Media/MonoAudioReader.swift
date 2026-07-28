//
//  MonoAudioReader.swift
//  Projekt Krása
//
//  Fáze 7, modul 5: načte zvuk souboru jako mono Float vzorky na
//  společné frekvenci — vstup pro `WaveformSync`.
//
//  Čte se přes `AVComposition`, NE přímo ze stopy: všechny naměřené
//  klipy mají na zvuku edit list zahazující 44 ms AAC primingu a kdo ho
//  ignoruje, dostane zvuk posunutý o 44 ms — u synchronizace přesně ta
//  chyba, kterou tu měříme. Kompozice edit list ctí (pravidlo projektu
//  z měření 25. 07. 2026). Převzorkování na cílovou frekvenci a downmix
//  do mona dělá `AVAssetReaderAudioMixOutput` přes `audioSettings`.
//

import AVFoundation
import Foundation

enum MonoAudioReader {

    /// Mono vzorky celého souboru. `nil` = soubor nemá zvukovou stopu.
    static func samples(url: URL, sampleRate: Double = 48_000) async throws -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first
        else { return nil }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let range = try await sourceTrack.load(.timeRange)
        try compositionTrack.insertTimeRange(range, of: sourceTrack, at: .zero)

        let reader = try AVAssetReader(asset: composition)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: composition.tracks(withMediaType: .audio),
            audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "MonoAudioReader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Čtení zvuku se nepodařilo spustit."])
        }

        var samples = [Float]()
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= MemoryLayout<Float>.size else { continue }
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "MonoAudioReader", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Čtení zvuku selhalo."])
        }
        return samples
    }
}
