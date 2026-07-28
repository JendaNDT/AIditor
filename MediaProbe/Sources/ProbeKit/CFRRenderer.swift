//
//  CFRRenderer.swift
//  Projekt Krása / ProbeKit
//
//  Vyrenderuje libovolný asset na pevnou snímkovou mřížku do ProRes 422 Proxy.
//
//  Sdílené dvěma nástroji:
//    · `Flatten` — vstupem je kompozice postavená ze souboru (VFR → CFR)
//    · `Ramp`    — vstupem je kompozice se `scaleTimeRange` (rychlostní křivka)
//
//  V obou případech je úkol stejný: přijde asset s nepravidelným časováním
//  a má vylézt soubor s pravidelným taktem.
//

import AVFoundation
import Accelerate
import CoreMedia
import Foundation

public struct CFRRenderResult {
    public let writtenFrameCount: Int
    public let heldFrames: Int
    public let pixelFormat: String
    public let bitDepth: Int
    public let bitDepthWasDetected: Bool
    public let audioChannels: UInt32
    public let audioSampleRate: Double
    public let pitchAlgorithm: String?
    public let sourceDuration: CMTime
    public let outputDuration: CMTime
    public let elapsedSeconds: Double
}

public enum CFRRenderer {

    /// Výstupní formát renderu.
    public enum OutputFormat {
        /// ProRes 422 Proxy + LPCM v .mov — mezisoubory (proxy, zploštění).
        /// Dosavadní chování.
        case proResProxyLPCM
        /// HEVC + AAC v .mp4 — finální export (fáze 5). AAC tady nevadí:
        /// dodávka se už nikam nereimportuje, priming řeší přehrávače.
        case hevcAAC(videoBitRate: Int, audioBitRate: Int)
    }

    /// Vyrenderuje `asset` na mřížku `frameDuration`.
    ///
    /// - Parameters:
    ///   - audioTimePitchAlgorithm: korekce výšky hlasu při změně rychlosti.
    ///     Má smysl jen tam, kde kompozice obsahuje škálované úseky. Bez
    ///     změny rychlosti nechat `nil`.
    ///   - outputScale: měřítko výstupního obrazu. `0.5` = proxy v polovičním
    ///     rozlišení (rozhodnutí fáze 4 — plné 4K proxy není žádná úspora).
    ///     Škáluje se při dekódování přes `AVAssetReaderVideoCompositionOutput`
    ///     s `renderSize`, ne po snímcích na CPU. Kompozice zároveň aplikuje
    ///     `preferredTransform`, takže výstup je vzpřímený a zapisuje se
    ///     s identitou.
    ///     <https://developer.apple.com/documentation/avfoundation/avassetreadervideocompositionoutput>
    /// - Parameters:
    ///   - outputSize: pevný cílový rozměr (plátno projektu při exportu) —
    ///     sjednotí mix rozlišení a rotací přes video kompozici.
    ///   - format: mezisoubor (ProRes+LPCM), nebo dodávka (HEVC+AAC).
    ///   - audioMix: per-track hlasitosti (fáze 7). S mixem se čte přes
    ///     `AVAssetReaderAudioMixOutput` i u jediné stopy — hlasitost musí
    ///     do exportu stejnou cestou jako do přehrávače.
    ///     <https://developer.apple.com/documentation/avfoundation/avassetreaderaudiomixoutput/audiomix>
    ///   - audioGainLinear: normalizační gain (fáze 7, modul 3), lineárně.
    ///     Násobí se přímo do vzorků — přes `AVAudioMix.volume` to nejde,
    ///     dokumentace mu dovoluje jen 0,0–1,0 a normalizace potřebuje
    ///     i zesilovat. S gainem se zvuk dekóduje ve float32, aby zesílení
    ///     nemělo strop v celočíselném mezikroku; strop proti clippingu
    ///     (špička ≤ −1 dBFS) hlídá VOLAJÍCÍ, renderer násobí.
    ///   - onProgress: zlomek hotových snímků; chodí z fronty zapisovače.
    public static func render(asset: AVAsset,
                              videoTrack: AVAssetTrack,
                              audioTracks: [AVAssetTrack],
                              frameDuration: CMTime,
                              audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm? = nil,
                              outputScale: Double = 1.0,
                              outputSize: CGSize? = nil,
                              format: OutputFormat = .proResProxyLPCM,
                              audioMix: AVAudioMix? = nil,
                              audioGainLinear: Double = 1.0,
                              videoComposition: AVVideoComposition? = nil,
                              onProgress: (@Sendable (Double) -> Void)? = nil,
                              to outputURL: URL) async throws -> CFRRenderResult {
        let started = Date()

        guard frameDuration.isValid, frameDuration.value > 0 else {
            throw ProbeError.message("Neplatná délka snímku.")
        }
        guard outputScale > 0, outputScale <= 1 else {
            throw ProbeError.message("Neplatné měřítko výstupu \(outputScale).")
        }

        let (naturalSize, transform, formats) =
            try await videoTrack.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let depth = bitDepth(from: formats.first)

        let pixelFormat: OSType
        switch format {
        case .proResProxyLPCM:
            pixelFormat = depth.value >= 10
                ? kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
                : kCVPixelFormatType_422YpCbCr8
        case .hevcAAC:
            // Dodávka je 8bit 4:2:0 — standard distribuce. HDR/10bit je F12.
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }

        // Cílový rozměr: pevný (export na plátno), nebo z měřítka (proxy).
        var targetSize: CGSize? = outputSize
        if targetSize == nil, outputScale != 1.0 {
            let transformed = CGRect(origin: .zero, size: naturalSize)
                .applying(transform).size
            // Sudé rozměry — chroma podvzorkování chce sudou šířku i výšku.
            targetSize = CGSize(
                width: (abs(transformed.width) * outputScale / 2).rounded() * 2,
                height: (abs(transformed.height) * outputScale / 2).rounded() * 2)
        }

        // MARK: Čtečka

        let reader = try AVAssetReader(asset: asset)
        let readerSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        let videoOutput: AVAssetReaderOutput

        if let videoComposition {
            // Vlastní kompozice volajícího (fáze 10: přechody — instrukce
            // s opacity rampami přes VÍC obrazových stop). Musí mít samá
            // `renderSize` i `frameDuration` na cílové mřížce; renderer
            // ji nechává být a čte přes všechny obrazové stopy assetu —
            // co vidíš v přehrávači, to dostaneš v souboru.
            let allVideoTracks = try await asset.loadTracks(withMediaType: .video)
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: allVideoTracks,
                                                             videoSettings: readerSettings)
            output.videoComposition = videoComposition
            output.alwaysCopiesSampleData = false
            videoOutput = output
        } else if let targetSize {
            // Cadence kompozice = cílová mřížka: výstup čtečky je pak už CFR
            // a zero-order hold resampleru jím projde 1:1. Výběr snímku pro
            // daný čas dělá kompozitor stejně — poslední platný snímek.
            // Kompozici staví `ScalingVideoComposition` — od fáze 9 dvojí
            // implementace (Configuration na macOS 26+, jinak deprecated
            // AVMutableVideoComposition).
            let scaling = try await ScalingVideoComposition.make(
                for: asset, renderSize: targetSize, frameDuration: frameDuration)

            let output = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack],
                                                             videoSettings: readerSettings)
            output.videoComposition = scaling
            output.alwaysCopiesSampleData = false
            videoOutput = output
        } else {
            let output = AVAssetReaderTrackOutput(track: videoTrack,
                                                  outputSettings: readerSettings)
            output.alwaysCopiesSampleData = false
            videoOutput = output
        }
        guard reader.canAdd(videoOutput) else {
            throw ProbeError.message("Čtečka nepřijala video výstup s formátem \(fourCC(pixelFormat)).")
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderOutput?
        var audioChannels: UInt32 = 0
        var audioSampleRate: Double = 0
        let hasGain = audioGainLinear != 1.0
        if let firstAudio = audioTracks.first {
            let audioFormats = try await firstAudio.load(.formatDescriptions)
            if let asbd = audioFormats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0) }) {
                audioChannels = asbd.pointee.mChannelsPerFrame
                audioSampleRate = asbd.pointee.mSampleRate
            }
            // S normalizačním gainem se dekóduje ve float32 — násobit se
            // bude do vzorků a celočíselný mezikrok by zesílení ořezal
            // dřív, než by na něj došlo.
            let settings = hasGain
                ? pcmFloatSettings(channels: audioChannels, sampleRate: audioSampleRate)
                : pcmSettings(channels: audioChannels, sampleRate: audioSampleRate)

            if audioTracks.count == 1, audioMix == nil {
                let output = AVAssetReaderTrackOutput(track: firstAudio, outputSettings: settings)
                // S gainem se do bufferů zapisuje — nesmí to být sdílená
                // paměť čtečky, proto kopie.
                output.alwaysCopiesSampleData = hasGain
                // Korekce výšky hlasu se nastavuje TADY. AVAssetExportSession má
                // vlastní `audioTimePitchAlgorithm`, ale tu cestu nepoužíváme —
                // u AVAssetReaderu to sedí přímo na výstupu stopy.
                if let audioTimePitchAlgorithm {
                    output.audioTimePitchAlgorithm = audioTimePitchAlgorithm
                }
                if reader.canAdd(output) {
                    reader.add(output)
                    audioOutput = output
                }
            } else {
                // Víc zvukových stop (A1 + A2 při exportu) → smíchat do jedné.
                // A per-track hlasitost (fáze 7) jde touhle cestou i u jediné
                // stopy — `audioMix` umí jen tenhle výstup.
                // <https://developer.apple.com/documentation/avfoundation/avassetreaderaudiomixoutput>
                let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks,
                                                         audioSettings: settings)
                output.alwaysCopiesSampleData = hasGain
                output.audioMix = audioMix
                if let audioTimePitchAlgorithm {
                    output.audioTimePitchAlgorithm = audioTimePitchAlgorithm
                }
                if reader.canAdd(output) {
                    reader.add(output)
                    audioOutput = output
                }
            }
        }

        // MARK: Zapisovač

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let writerSize = targetSize ?? naturalSize
        let fileType: AVFileType
        var videoSettings: [String: Any]
        switch format {
        case .proResProxyLPCM:
            fileType = .mov
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
                AVVideoWidthKey: Int(writerSize.width),
                AVVideoHeightKey: Int(writerSize.height),
            ]
        case .hevcAAC(let videoBitRate, _):
            fileType = .mp4
            let framesPerSecond =
                (Double(frameDuration.timescale) / Double(frameDuration.value)).rounded()
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: Int(writerSize.width),
                AVVideoHeightKey: Int(writerSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoBitRate,
                    AVVideoExpectedSourceFrameRateKey: Int(framesPerSecond),
                ],
            ]
        }
        if let colorProperties = colorProperties(from: formats.first) {
            videoSettings[AVVideoColorPropertiesKey] = colorProperties
        }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        // Škálovaná/kompoziční cesta dostává pixely už vzpřímené (transform
        // aplikovala kompozice) — druhé otočení by obraz položilo na bok.
        videoInput.transform = targetSize == nil ? transform : .identity

        // Timescale stopy musí být ta, ve které vychází délka snímku celočíselně.
        // Bez tohohle si zapisovač zvolí 600 a kvantizuje do ní — u 60p to vyjde
        // (1500/90000 = 10/600), ale u 30,01 fps je 2999/90000 v šestistovkách
        // 19,993 ticku a výstup vyleze jako CFR≈ místo CFR.
        // U zvuku se mediaTimeScale nastavovat NESMÍ, vyhodilo by to výjimku.
        videoInput.mediaTimeScale = frameDuration.timescale

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        guard writer.canAdd(videoInput) else {
            throw ProbeError.message("Zapisovač nepřijal video vstup.")
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let audioSettings: [String: Any]
            switch format {
            case .proResProxyLPCM:
                // LPCM schválně. AAC by mezisouborům přidal priming delay
                // a rozbil přesně to, kvůli čemu vznikají.
                audioSettings = pcmSettings(channels: audioChannels,
                                            sampleRate: audioSampleRate)
            case .hevcAAC(_, let audioBitRate):
                // Dodávka: AAC stereo. Priming tady nevadí — soubor se už
                // nikam nereimportuje.
                audioSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audioSampleRate > 0 ? audioSampleRate : 48_000,
                    AVNumberOfChannelsKey: Int(max(1, min(2, audioChannels))),
                    AVEncoderBitRateKey: audioBitRate,
                ]
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? ProbeError.message("Zapisovač se nepodařilo spustit.")
        }
        guard reader.startReading() else {
            throw reader.error ?? ProbeError.message("Čtečku se nepodařilo spustit.")
        }
        writer.startSession(atSourceTime: .zero)

        // MARK: Převzorkování

        let sourceDuration = try await asset.load(.duration)
        let slotCount = frameSlotCount(duration: sourceDuration, frameDuration: frameDuration)

        let resampler = VideoResampler(output: videoOutput,
                                       adaptor: adaptor,
                                       input: videoInput,
                                       writer: writer,
                                       frameDuration: frameDuration,
                                       slotCount: slotCount)
        resampler.onProgress = onProgress

        let group = DispatchGroup()
        group.enter()
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "cfr.video")) {
            if resampler.pump() { group.leave() }
        }

        if let audioInput, let audioOutput {
            group.enter()
            let gain = Float(audioGainLinear)
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "cfr.audio")) {
                while audioInput.isReadyForMoreMediaData {
                    guard let buffer = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if hasGain { applyGain(gain, to: buffer) }
                    if !audioInput.append(buffer) {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        // Čekání přes notify, ne group.wait() — blokující wait v async kontextu
        // zabere kooperativní vlákno a ve Swift 6 je to rovnou chyba.
        await withCheckedContinuation { continuation in
            group.notify(queue: DispatchQueue.global()) { continuation.resume() }
        }

        if reader.status == .failed {
            throw reader.error ?? ProbeError.message("Čtení selhalo.")
        }
        if let failure = resampler.failure {
            throw failure
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? ProbeError.message("Zápis selhal.")
        }

        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration = (try? await outputAsset.load(.duration)) ?? .invalid

        return CFRRenderResult(writtenFrameCount: resampler.written,
                               heldFrames: resampler.held,
                               pixelFormat: fourCC(pixelFormat),
                               bitDepth: depth.value,
                               bitDepthWasDetected: depth.detected,
                               audioChannels: audioChannels,
                               audioSampleRate: audioSampleRate,
                               pitchAlgorithm: audioTimePitchAlgorithm?.rawValue,
                               sourceDuration: sourceDuration,
                               outputDuration: outputDuration,
                               elapsedSeconds: Date().timeIntervalSince(started))
    }

    // MARK: - Pomocné

    /// Kolik celých snímků se do délky vejde.
    public static func frameSlotCount(duration: CMTime, frameDuration: CMTime) -> Int {
        guard duration.isValid, frameDuration.isValid, frameDuration.value > 0 else { return 0 }
        let durationTicks = CMTimeConvertScale(duration, timescale: frameDuration.timescale,
                                               method: .roundHalfAwayFromZero).value
        return max(0, Int(durationTicks / frameDuration.value))
    }

    /// Bitová hloubka zdroje. `BitsPerComponent` je podle dokumentace
    /// „often not present", takže se počítá s tím, že tam nebude.
    public static func bitDepth(from format: CMFormatDescription?) -> (value: Int, detected: Bool) {
        guard let format,
              let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any],
              let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int
        else {
            return (8, false)
        }
        return (bits, true)
    }

    /// Barevné vlastnosti zdroje pro výstupní nastavení.
    public static func colorProperties(from format: CMFormatDescription?) -> [String: Any]? {
        guard let format,
              let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] else { return nil }
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String]
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String]
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String]
        guard let primaries, let transfer, let matrix else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
    }

    public static func pcmSettings(channels: UInt32, sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate > 0 ? sampleRate : 48000,
            AVNumberOfChannelsKey: channels > 0 ? Int(channels) : 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Float32 LPCM — dekódovací formát pro cesty, které do vzorků
    /// zapisují (normalizační gain) nebo je měří (LoudnessScanner).
    /// Float nemá strop na 0 dBFS, takže zesílení ani 32-bit float
    /// zdroje s hodnotami přes ±1 se v mezikroku neořežou.
    public static func pcmFloatSettings(channels: UInt32, sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate > 0 ? sampleRate : 48000,
            AVNumberOfChannelsKey: channels > 0 ? Int(channels) : 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Vynásobí vzorky bufferu gainem, na místě. Buffer musí být float32
    /// (zajišťuje `pcmFloatSettings`) a vlastní kopie
    /// (`alwaysCopiesSampleData = true`) — do sdílené paměti čtečky se
    /// zapisovat nesmí. Blokový buffer nemusí být souvislý, proto se jde
    /// po segmentech.
    /// <https://developer.apple.com/documentation/coremedia/cmblockbuffergetdatapointer(_:atoffset:lengthatoffsetout:totallengthout:datapointerout:)>
    /// <https://developer.apple.com/documentation/accelerate/1450020-vdsp_vsmul>
    private static func applyGain(_ gain: Float, to buffer: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return }
        let total = CMBlockBufferGetDataLength(block)
        var offset = 0
        var gainValue = gain
        while offset < total {
            var lengthAtOffset = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: offset,
                                              lengthAtOffsetOut: &lengthAtOffset,
                                              totalLengthOut: nil,
                                              dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                  let pointer, lengthAtOffset > 0 else { return }
            let count = lengthAtOffset / MemoryLayout<Float>.size
            UnsafeMutableRawPointer(pointer).withMemoryRebound(to: Float.self, capacity: count) {
                vDSP_vsmul($0, 1, &gainValue, $0, 1, vDSP_Length(count))
            }
            offset += lengthAtOffset
        }
    }

    public static func fourCC(_ code: OSType) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "?" })
    }
}
