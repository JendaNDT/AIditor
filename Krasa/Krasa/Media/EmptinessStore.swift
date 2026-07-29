//
//  EmptinessStore.swift
//  Projekt Krása
//
//  Vzorky „hluchosti" záběrů (fáze 15, modul 2): hlasitost + jas +
//  entropie + pohyb, 1 vzorek za sekundu (hluché místo je ≥ 5 s nudy,
//  hustěji netřeba).
//
//  Obraz: týž sekvenční průchod s decimací jako `SharpnessStore` (a týž
//  `LumaSampler`); statistiky počítá otestovaný `LumaStats` z modelu.
//  Zvuk: mono 8 kHz přes `MonoAudioReader` (edit listy ctí — pravidlo
//  projektu), RMS v oknech 1 s → dBFS. Soubor bez zvukové stopy je
//  z definice ticho (−120 dBFS) — fotky a němé záběry rozhoduje obraz.
//
//  Cache otiskem s verzí výpočtu (vzorec `SharpnessStore`).
//

import AVFoundation
import CryptoKit
import Foundation
import TimelineModel

actor EmptinessStore {

    static let shared = EmptinessStore()

    static let samplesPerSecond = 1.0

    private var memory: [URL: [EmptinessSample]] = [:]
    private var inFlight: Set<URL> = []

    /// Vzorky souboru — z paměti, z diskové cache, nebo se spočítají.
    func samples(for url: URL) async -> [EmptinessSample]? {
        if let cached = memory[url] { return cached }
        while inFlight.contains(url) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let cached = memory[url] { return cached }
        }
        inFlight.insert(url)
        defer { inFlight.remove(url) }

        if let cacheURL = Self.cacheURL(for: url),
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([EmptinessSample].self, from: data) {
            memory[url] = cached
            return cached
        }

        guard let computed = try? await Self.compute(url: url) else { return nil }
        memory[url] = computed
        if let cacheURL = Self.cacheURL(for: url),
           let data = try? JSONEncoder().encode(computed) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return computed
    }

    // MARK: - Výpočet

    private static func compute(url: URL) async throws -> [EmptinessSample]? {
        // Zvuk: RMS dBFS v oknech 1 s. Bez stopy = ticho.
        let audioRate = 8_000.0
        let loudness: [Double]
        if let audio = try? await MonoAudioReader.samples(url: url, sampleRate: audioRate),
           !audio.isEmpty {
            let window = Int(audioRate / samplesPerSecond)
            var levels: [Double] = []
            var start = 0
            while start < audio.count {
                let end = min(start + window, audio.count)
                var sum = 0.0
                for i in start..<end {
                    let value = Double(audio[i])
                    sum += value * value
                }
                let rms = (sum / Double(end - start)).squareRoot()
                levels.append(rms > 0 ? max(-120, 20 * log10(rms)) : -120)
                start = end
            }
            loudness = levels
        } else {
            loudness = []
        }

        // Obraz: sekvenční dekódování s decimací na 1/s (vzorec
        // `SharpnessStore` — kadence kompozice by výstup neproředila).
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

        var samples: [EmptinessSample] = []
        var previousLuma: [UInt8]?
        let step = 1.0 / samplesPerSecond
        var nextSampleTime = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time + 1e-9 >= nextSampleTime else { continue }
            while nextSampleTime <= time { nextSampleTime += step }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer),
                  let grid = LumaSampler.downsampledLuma(of: pixelBuffer) else { continue }

            let index = min(loudness.isEmpty ? 0 : loudness.count - 1,
                            Int(time * samplesPerSecond))
            let loudnessDB = loudness.isEmpty ? -120.0 : loudness[index]
            let motion = previousLuma.map { LumaStats.meanDifference($0, grid.luma) } ?? 0
            samples.append(EmptinessSample(
                time: time,
                loudnessDB: loudnessDB,
                brightness: LumaStats.brightness(luma: grid.luma),
                entropy: LumaStats.entropy(luma: grid.luma),
                motion: motion))
            previousLuma = grid.luma
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return samples
    }

    // MARK: - Disková mezipaměť

    private static func cacheURL(for url: URL) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("Emptiness", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        // Verze výpočtu v otisku — vzorec `SharpnessStore`.
        let fingerprint = "v1|\(url.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}
