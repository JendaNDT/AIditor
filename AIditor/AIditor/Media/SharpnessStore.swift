//
//  SharpnessStore.swift
//  Projekt AIditor
//
//  Vzorky ostrosti záběrů (fáze 15, modul 1).
//
//  Čte se SEKVENČNĚ přes `AVAssetReaderTrackOutput` (hardwarový dekodér,
//  žádné seekování — `AVAssetImageGenerator` by pro tisíce vzorků seekoval
//  zero tolerance a trval řádově déle) a DECIMUJE se na vzorkovací mřížku
//  3/s (plán říká 2–5): metrika se počítá jen u snímků, které překročí
//  další bod mřížky, zbytek se zahodí po dekódování.
//  ⚠️ Kadenci NEŘEŠÍ škálovací kompozice: `frameDuration` pod frekvencí
//  zdroje výstup čtečky NEprořeďuje (změřeno — 60fps klip dál dával 60
//  vzorků/s) a přepsané `renderSize` u kompozice z `withPropertiesOf`
//  u still movie vracelo prázdný obraz. Decimace po dekódování je
//  dokumentovaně nezáludná.
//
//  Skóre počítá `SharpnessMetric.laplacianVariance` z TimelineModelu na
//  luma rovině NV12, blokově podvzorkované na ~192 sloupců — metrika na
//  plném rozlišení by měřila šum senzoru, průměrování bloků ho ruší
//  a skóre je souměřitelné napříč rozlišeními. Rotace (`preferredTransform`)
//  se neaplikuje — ostrost je na orientaci nezávislá.
//
//  Disková mezipaměť otiskem cesta|velikost|mtime (vzorec vln) — po
//  překódování souboru se vzorky spočítají znovu, místo aby se mlčky
//  použily staré. Do projektového souboru se NEUKLÁDAJÍ (rozhodnutí
//  fáze 15: levně spočitatelné, cache stačí).
//

import AVFoundation
import CryptoKit
import Foundation
import TimelineModel

actor SharpnessStore {

    static let shared = SharpnessStore()

    /// Vzorkovací frekvence: 3/s — kompromis plánu (2–5). Hustěji = delší
    /// analýza, řidčeji = krátké rozmazání proklouzne.
    static let samplesPerSecond = 3.0
    /// Malý náhled: na ostrost stačí, dekodér ho škáluje sám.
    static let analysisSize = CGSize(width: 192, height: 108)

    private var memory: [URL: [SharpnessSample]] = [:]
    private var inFlight: Set<URL> = []

    /// Vzorky souboru — z paměti, z diskové cache, nebo se spočítají.
    /// `nil`, když soubor nemá video stopu nebo se nedá číst.
    func samples(for url: URL) async -> [SharpnessSample]? {
        if let cached = memory[url] { return cached }
        // Dva souběžné dotazy na týž soubor: druhý počká na první.
        while inFlight.contains(url) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let cached = memory[url] { return cached }
        }
        inFlight.insert(url)
        defer { inFlight.remove(url) }

        if let cacheURL = Self.cacheURL(for: url),
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([SharpnessSample].self, from: data) {
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

    private static func compute(url: URL) async throws -> [SharpnessSample]? {
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

        var samples: [SharpnessSample] = []
        let step = 1.0 / samplesPerSecond
        var nextSampleTime = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            // Decimace: metrika jen u snímku, který překročil mřížku.
            guard time + 1e-9 >= nextSampleTime else { continue }
            while nextSampleTime <= time { nextSampleTime += step }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { continue }
            if let score = lumaScore(of: pixelBuffer) {
                samples.append(SharpnessSample(time: time, score: score))
            }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return samples
    }

    /// Luma rovina NV12 → blokový podvzorek → rozptyl Laplaciánu.
    private static func lumaScore(of pixelBuffer: CVPixelBuffer) -> Double? {
        guard let grid = LumaSampler.downsampledLuma(of: pixelBuffer) else { return nil }
        return SharpnessMetric.laplacianVariance(luma: grid.luma,
                                                 width: grid.width, height: grid.height)
    }

    // MARK: - Disková mezipaměť

    /// Klíč z cesty, velikosti a času změny — vzorec `WaveformStore`.
    private static func cacheURL(for url: URL) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("Sharpness", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        // Verze VÝPOČTU je součást otisku — po změně metriky nebo vzorkování
        // se staré soubory cache přestanou trefovat a spočítá se znovu.
        let fingerprint = "v2|\(url.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}

// MARK: - Sdílený podvzorkovač

/// Blokový podvzorek luma roviny NV12 na ~192 sloupců — společný základ
/// metrik kvality (ostrost F15/1, hluchost F15/2). Bloky se čtou přímo
/// z roviny (s ohledem na `bytesPerRow`), žádná mezikopie plného rozlišení,
/// a průměr bloku se počítá z PODVZORKU ~4×4 pixelů: šum ředí stejně
/// a je to řádově méně čtení — plný průměr 4K bloků stál na 45s klipu
/// přes 6 minut, tohle sekundy.
enum LumaSampler {

    static func downsampledLuma(of pixelBuffer: CVPixelBuffer)
        -> (luma: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 2, height > 2 else { return nil }

        let block = max(1, width / Int(SharpnessStore.analysisSize.width))
        let outWidth = width / block
        let outHeight = height / block
        guard outWidth > 2, outHeight > 2 else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let tap = max(1, block / 4)
        let tapsPerAxis = (block + tap - 1) / tap
        var luma = [UInt8](repeating: 0, count: outWidth * outHeight)
        for oy in 0..<outHeight {
            for ox in 0..<outWidth {
                var sum = 0
                var dy = 0
                while dy < block {
                    let row = (oy * block + dy) * stride + ox * block
                    var dx = 0
                    while dx < block {
                        sum += Int(bytes[row + dx])
                        dx += tap
                    }
                    dy += tap
                }
                luma[oy * outWidth + ox] = UInt8(sum / (tapsPerAxis * tapsPerAxis))
            }
        }
        return (luma, outWidth, outHeight)
    }
}
