//
//  WaveformStore.swift
//  Projekt AIditor
//
//  Vlnové průběhy — krok 10 z `FAZE_2_VIEW.md`, sekce 2.7.
//
//  Dvě vrstvy mezipaměti:
//
//  1. ŠPIČKY — dvojice min/max na okno 256 vzorků, jednou na asset,
//     `AVAssetReader` na pozadí, uložené na disk. Jediná drahá operace.
//  2. DLAŽDICE — `CGImage` renderované ze špiček líně na pozadí, klíčem
//     (asset, úroveň zoomu zaokrouhlená na MOCNINU DVOU, index dlaždice).
//     Mezi úrovněmi se dlaždice natáhne — během pinche o kousek rozmazaná,
//     po ustálení ostrá. Cachovat podle spojité hodnoty zoomu by znamenalo
//     zahazovat mezipaměť šedesátkrát za sekundu.
//
//  🚩 Špičky se čtou přes `AVComposition`, NE ze syrové tabulky vzorků.
//  Všech pět měřených klipů má na zvuku edit list zahazující prvních 44 ms
//  (priming AAC) — to je na 30fps základně víc než jeden snímek. Kdo ho
//  ignoruje, dostane vlnu posunutou proti zvuku a bude se podle ní stříhat
//  o snímek vedle. `MediaProbe` tuhle chybu už jednou našel.
//
//  `CATiledLayer` se schválně nepoužívá — jeho úrovně detailu jsou vázané na
//  měřítko vrstvy, což je u vodorovného-jen zoomu přesně to, co nechceme.
//  <https://developer.apple.com/documentation/quartzcore/catiledlayer>
//

import AVFoundation
import AppKit
import CryptoKit
import Foundation
import TimelineModel

// MARK: - Špičky

/// Min/max obálky zvuku jednoho assetu v čase PO uplatnění edit listu.
struct AssetPeaks: Sendable {
    /// Kolik dvojic min/max připadá na sekundu zvuku.
    let peaksPerSecond: Double
    let mins: [Float]
    let maxs: [Float]

    var count: Int { mins.count }
}

/// Čtení špiček z disku a jejich výpočet. Vše mimo hlavní vlákno.
enum PeakExtractor {

    /// Okno jedné dvojice min/max, ve vzorcích. Při 48 kHz ~187 dvojic/s.
    static let samplesPerPeak = 256

    /// Spočítá špičky přes `AVComposition` — kompozice ctí edit list zdroje,
    /// takže vlna sedí na to, co uslyší přehrávač.
    ///
    /// <https://developer.apple.com/documentation/avfoundation/avassetreader>
    /// <https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/inserttimerange(_:of:at:)>
    static func extract(url: URL) async throws -> AssetPeaks {
        let asset = AVURLAsset(url: url)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "Waveform", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "asset nemá zvukovou stopu"])
        }
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "Waveform", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "nejde založit stopa kompozice"])
        }
        try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                             of: sourceTrack, at: .zero)

        let reader = try AVAssetReader(asset: composition)
        // Mono float — na obálku stačí, dvoukanálové čtení by jen zdvojilo data.
        let output = AVAssetReaderTrackOutput(track: compositionTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "Waveform", code: 3)
        }

        var mins: [Float] = []
        var maxs: [Float] = []
        var windowMin = Float.greatestFiniteMagnitude
        var windowMax = -Float.greatestFiniteMagnitude
        var windowFill = 0
        var sampleRate = 48_000.0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let description = CMSampleBufferGetFormatDescription(sampleBuffer),
               let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
               basic.pointee.mSampleRate > 0 {
                sampleRate = basic.pointee.mSampleRate
            }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)

            bytes.withUnsafeBytes { raw in
                for sample in raw.bindMemory(to: Float32.self) {
                    windowMin = Swift.min(windowMin, sample)
                    windowMax = Swift.max(windowMax, sample)
                    windowFill += 1
                    if windowFill == samplesPerPeak {
                        mins.append(windowMin)
                        maxs.append(windowMax)
                        windowMin = .greatestFiniteMagnitude
                        windowMax = -.greatestFiniteMagnitude
                        windowFill = 0
                    }
                }
            }
        }
        if windowFill > 0 {
            mins.append(windowMin)
            maxs.append(windowMax)
        }
        guard reader.status == .completed else {
            throw reader.error ?? NSError(domain: "Waveform", code: 4)
        }

        return AssetPeaks(peaksPerSecond: sampleRate / Double(samplesPerPeak),
                          mins: mins, maxs: maxs)
    }

    // MARK: Disková mezipaměť

    /// Klíč z cesty, velikosti a času změny — po překódování souboru se
    /// špičky spočítají znovu, místo aby se mlčky použily staré.
    static func cacheURL(for url: URL) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fingerprint = "\(url.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".peaks")
    }

    private static let magic: UInt32 = 0x4B_52_41_57   // „KRAW"
    private static let version: UInt32 = 1

    static func save(_ peaks: AssetPeaks, to url: URL) {
        var data = Data()
        withUnsafeBytes(of: magic.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: version.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: peaks.peaksPerSecond.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(peaks.count).littleEndian) { data.append(contentsOf: $0) }
        peaks.mins.withUnsafeBytes { data.append(contentsOf: $0) }
        peaks.maxs.withUnsafeBytes { data.append(contentsOf: $0) }
        try? data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> AssetPeaks? {
        guard let data = try? Data(contentsOf: url), data.count >= 20 else { return nil }
        var offset = 0
        func read<T>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { return nil }
            defer { offset += size }
            return data.subdata(in: offset ..< offset + size).withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }
        guard read(UInt32.self)?.littleEndian == magic,
              read(UInt32.self)?.littleEndian == version,
              let rateBits = read(UInt64.self)?.littleEndian,
              let count32 = read(UInt32.self)?.littleEndian else { return nil }
        let count = Int(count32)
        let floats = count * MemoryLayout<Float32>.size
        guard data.count >= offset + 2 * floats, count > 0 else { return nil }

        let mins = data.subdata(in: offset ..< offset + floats).withUnsafeBytes {
            Array($0.bindMemory(to: Float32.self))
        }
        offset += floats
        let maxs = data.subdata(in: offset ..< offset + floats).withUnsafeBytes {
            Array($0.bindMemory(to: Float32.self))
        }
        return AssetPeaks(peaksPerSecond: Double(bitPattern: rateBits), mins: mins, maxs: maxs)
    }
}

// MARK: - Dlaždice

/// Klíč dlaždice podle návrhu: (asset, úroveň zoomu, index). Úroveň je
/// mocnina dvou; `scale` je backing scale displeje, aby Retina nedostala
/// rozmazanou vlnu z half-res dlaždice.
struct WaveTileKey: Hashable {
    let assetID: AssetID
    let rung: Double
    let index: Int
    let scale: CGFloat
}

@MainActor
final class WaveformStore: ObservableObject {

    /// Roste při každé dopočítané špičce nebo dlaždici. View si na to věší
    /// překreslení — jemnější adresace by tu byla účetnictví navíc.
    @Published private(set) var version = 0

    /// Šířka dlaždice v bodech NA ÚROVNI — na obrazovce se natahuje poměrem
    /// aktuálního zoomu k úrovni. `nonisolated`: čte ji render na pozadí.
    nonisolated static let tileWidthPoints: Double = 512
    /// Výška renderu dlaždice v bodech. Zvuková stopa má 44, vrstva si
    /// obrázek svisle natáhne — u obálky to není vidět.
    nonisolated static let tileHeightPoints: Double = 44

    private var peaksByAsset: [AssetID: AssetPeaks] = [:]
    private var peaksInFlight: Set<AssetID> = []
    private var tiles: [WaveTileKey: CGImage] = [:]
    private var tilesInFlight: Set<WaveTileKey> = []

    /// Snímková frekvence časové základny — na převod bodů na sekundy zdroje.
    private let timelineFrameRate: Double = 30

    // MARK: Špičky

    /// Vrátí špičky, nebo `nil` a spustí výpočet na pozadí. Až doběhne,
    /// zvedne se `version` a view si řekne znovu.
    func peaks(for asset: Asset) -> AssetPeaks? {
        if let cached = peaksByAsset[asset.id] { return cached }
        guard asset.hasAudio, !peaksInFlight.contains(asset.id) else { return nil }
        peaksInFlight.insert(asset.id)

        // Špičky jsou zvuková data — vždy z originálu, ale přes tu jedinou
        // funkci, která o proxy rozhoduje (`FAZE_2_VIEW.md` 2.8).
        let url = asset.url(usingProxies: false)
        let assetID = asset.id

        Task.detached(priority: .utility) {
            let cacheURL = PeakExtractor.cacheURL(for: url)
            var peaks = cacheURL.flatMap { PeakExtractor.load(from: $0) }
            if peaks == nil {
                peaks = try? await PeakExtractor.extract(url: url)
                if let peaks, let cacheURL { PeakExtractor.save(peaks, to: cacheURL) }
            }
            guard let ready = peaks else { return }
            await MainActor.run {
                self.peaksByAsset[assetID] = ready
                self.peaksInFlight.remove(assetID)
                self.version += 1
            }
        }
        return nil
    }

    // MARK: Dlaždice

    /// Nejbližší mocnina dvou k aktuálnímu zoomu, zaříznutá na rozsah zoomu.
    static func rung(for pointsPerFrame: Double) -> Double {
        let exponent = (log2(pointsPerFrame)).rounded()
        return pow(2, Swift.min(Swift.max(exponent, -6), 7))
    }

    /// Vrátí hotovou dlaždici, nebo `nil` a zadá render na pozadí.
    func tile(assetID: AssetID, rung: Double, index: Int, scale: CGFloat) -> CGImage? {
        let key = WaveTileKey(assetID: assetID, rung: rung, index: index, scale: scale)
        if let image = tiles[key] { return image }
        guard let peaks = peaksByAsset[assetID], !tilesInFlight.contains(key) else { return nil }
        tilesInFlight.insert(key)

        // Hrubá pojistka proti neomezenému růstu: dlaždice jsou levné na
        // přepočet, drahé na držení. Při přetečení se prostě začne znovu.
        if tiles.count > 512 { tiles.removeAll() }

        let secondsPerTile = Self.tileWidthPoints / (timelineFrameRate * rung)
        let startSeconds = Double(index) * secondsPerTile

        Task.detached(priority: .userInitiated) {
            let image = Self.renderTile(peaks: peaks,
                                        startSeconds: startSeconds,
                                        secondsPerTile: secondsPerTile,
                                        scale: scale)
            await MainActor.run {
                self.tilesInFlight.remove(key)
                guard let image else { return }
                self.tiles[key] = image
                self.version += 1
            }
        }
        return nil
    }

    /// Render obálky do bitmapy. Černá s alfou — čitelná na zeleném klipu
    /// v tmavém i světlém režimu, takže dlaždice nezávisí na appearance.
    private nonisolated static func renderTile(peaks: AssetPeaks,
                                               startSeconds: Double,
                                               secondsPerTile: Double,
                                               scale: CGFloat) -> CGImage? {
        let width = Int(tileWidthPoints * Double(scale))
        let height = Int(tileHeightPoints * Double(scale))
        guard width > 0, height > 0, peaks.count > 0 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        let midY = Double(height) / 2
        let halfSpan = Double(height) / 2 - Double(scale)   // bod okraje nahoře i dole
        let secondsPerPixel = secondsPerTile / Double(width)

        for column in 0..<width {
            let from = startSeconds + Double(column) * secondsPerPixel
            let to = from + secondsPerPixel
            var bucket = Int(from * peaks.peaksPerSecond)
            let bucketEnd = Swift.max(bucket, Int(to * peaks.peaksPerSecond))
            guard bucket < peaks.count else { break }

            var low: Float = 0, high: Float = 0
            while bucket <= bucketEnd, bucket < peaks.count {
                low = Swift.min(low, peaks.mins[bucket])
                high = Swift.max(high, peaks.maxs[bucket])
                bucket += 1
            }

            let top = midY + halfSpan * Double(Swift.min(1, Swift.max(-1, high)))
            let bottom = midY + halfSpan * Double(Swift.min(1, Swift.max(-1, low)))
            let barHeight = Swift.max(Double(scale), top - bottom)
            context.fill(CGRect(x: Double(column), y: bottom,
                                width: 1, height: barHeight))
        }
        return context.makeImage()
    }
}
