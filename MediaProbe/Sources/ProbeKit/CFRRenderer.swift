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

    /// Vyrenderuje `asset` na mřížku `frameDuration`.
    ///
    /// - Parameters:
    ///   - audioTimePitchAlgorithm: korekce výšky hlasu při změně rychlosti.
    ///     Má smysl jen tam, kde kompozice obsahuje škálované úseky. Bez
    ///     změny rychlosti nechat `nil`.
    public static func render(asset: AVAsset,
                              videoTrack: AVAssetTrack,
                              audioTrack: AVAssetTrack?,
                              frameDuration: CMTime,
                              audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm? = nil,
                              to outputURL: URL) async throws -> CFRRenderResult {
        let started = Date()

        guard frameDuration.isValid, frameDuration.value > 0 else {
            throw ProbeError.message("Neplatná délka snímku.")
        }

        let (naturalSize, transform, formats) =
            try await videoTrack.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let depth = bitDepth(from: formats.first)
        let pixelFormat = depth.value >= 10
            ? kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_422YpCbCr8

        // MARK: Čtečka

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ProbeError.message("Čtečka nepřijala video výstup s formátem \(fourCC(pixelFormat)).")
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioChannels: UInt32 = 0
        var audioSampleRate: Double = 0
        if let audioTrack {
            let audioFormats = try await audioTrack.load(.formatDescriptions)
            if let asbd = audioFormats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0) }) {
                audioChannels = asbd.pointee.mChannelsPerFrame
                audioSampleRate = asbd.pointee.mSampleRate
            }
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: pcmSettings(channels: audioChannels, sampleRate: audioSampleRate))
            output.alwaysCopiesSampleData = false
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
        }

        // MARK: Zapisovač

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
        ]
        if let colorProperties = colorProperties(from: formats.first) {
            videoSettings[AVVideoColorPropertiesKey] = colorProperties
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform

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
            // LPCM schválně. AAC by výstupu přidal vlastní priming delay.
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: pcmSettings(channels: audioChannels, sampleRate: audioSampleRate))
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

        let group = DispatchGroup()
        group.enter()
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "cfr.video")) {
            if resampler.pump() { group.leave() }
        }

        if let audioInput, let audioOutput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "cfr.audio")) {
                while audioInput.isReadyForMoreMediaData {
                    guard let buffer = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
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

    public static func fourCC(_ code: OSType) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "?" })
    }
}
