//
//  Flattener.swift
//  Projekt Krása / Flatten
//
//  Přepis VFR souboru na pevnou snímkovou mřížku.
//
//  Tři věci, na kterých to stojí:
//
//  1. Cílová frekvence je MĚŘENÁ z modu délek vzorků, ne `nominalFrameRate`.
//     Ta na slow-mo klipu hlásí 119,369 místo skutečných 120,000.
//  2. Čte se přes AVComposition, ne ze souboru. Kompozice aplikuje edit list,
//     a každý testovací klip zahazuje edit listem prvních 44 ms zvuku.
//  3. Převzorkování je zero-order hold: každý výstupní slot dostane poslední
//     zdrojový snímek, který v tu chvíli platil. Zahozený snímek se tím sám
//     podrží, useknutý okraj sám zmizí.
//

import AVFoundation
import CoreMedia
import Foundation
import ProbeKit

struct FlattenResult {
    let outputURL: URL
    let frameDuration: CMTime
    let measuredFrameRate: Double
    let sourceVerdict: FrameRateVerdict
    let sourceFrameCount: Int
    let writtenFrameCount: Int
    /// Kolik slotů dostalo tentýž snímek jako slot předchozí.
    let heldFrames: Int
    let pixelFormat: String
    let bitDepth: Int
    let bitDepthWasDetected: Bool
    let audioChannels: UInt32
    let audioSampleRate: Double
    let outputDuration: CMTime
    let sourceDuration: CMTime
    let elapsedSeconds: Double
}

enum Flattener {

    // MARK: - Hlavní běh

    static func flatten(source: URL, to outputURL: URL) async throws -> FlattenResult {
        let started = Date()

        let asset = AVURLAsset(url: source)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.message("Soubor nemá video stopu.")
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first

        // 1) Změřit časování zdroje. Modus určí cílovou mřížku.
        let (videoTimeRange, naturalTimeScale) = try await sourceVideo.load(.timeRange, .naturalTimeScale)
        let timing = await SampleTimingReader.read(track: sourceVideo, asset: asset,
                                                   naturalTimeScale: naturalTimeScale)
        guard let stats = timing.stats else {
            throw ProbeError.message("Nepodařilo se změřit délky vzorků: \(timing.note ?? "neznámý důvod")")
        }
        let frameDuration = stats.frameDuration
        guard frameDuration.isValid, frameDuration.value > 0 else {
            throw ProbeError.message("Z modu vyšla neplatná délka snímku.")
        }

        // 2) Kompozice. Tady se aplikuje edit list — u zvuku je to povinné,
        //    u videa to zachrání budoucí klipy se slow-mo v edit listu.
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProbeError.message("Nepodařilo se založit video stopu kompozice.")
        }
        try compVideo.insertTimeRange(videoTimeRange, of: sourceVideo, at: .zero)

        var compAudio: AVMutableCompositionTrack?
        if let sourceAudio {
            let audioTimeRange = try await sourceAudio.load(.timeRange)
            let track = composition.addMutableTrack(withMediaType: .audio,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid)
            try track?.insertTimeRange(audioTimeRange, of: sourceAudio, at: .zero)
            compAudio = track
        }

        // 3) Vlastnosti obrazu ze zdroje. Rozměry v plném rozlišení — produkční
        //    proxy bude poloviční, ale ve spiku se smí měnit jen časování.
        let (naturalSize, transform, formats) =
            try await sourceVideo.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let depth = bitDepth(from: formats.first)
        let pixelFormat = depth.value >= 10
            ? kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_422YpCbCr8

        // 4) Čtečka nad kompozicí.
        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderTrackOutput(
            track: compVideo,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ProbeError.message("Čtečka nepřijala video výstup s formátem \(fourCC(pixelFormat)).")
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioChannels: UInt32 = 0
        var audioSampleRate: Double = 0
        if let compAudio, let sourceAudio {
            let audioFormats = try await sourceAudio.load(.formatDescriptions)
            if let asbd = audioFormats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0) }) {
                audioChannels = asbd.pointee.mChannelsPerFrame
                audioSampleRate = asbd.pointee.mSampleRate
            }
            let output = AVAssetReaderTrackOutput(track: compAudio,
                                                  outputSettings: pcmSettings(channels: audioChannels,
                                                                              sampleRate: audioSampleRate))
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        // 5) Zapisovač.
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
        ]
        // Barvu přenést beze změny — jinak by se ve spiku měnily dvě věci naráz.
        if let colorProperties = colorProperties(from: formats.first) {
            videoSettings[AVVideoColorPropertiesKey] = colorProperties
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform  // orientace se musí přenést

        // Timescale stopy musí být ta, ve které vychází délka snímku celočíselně.
        // Bez tohohle si zapisovač zvolí 600 a kvantizuje do ní — u 60p to vyjde
        // (1500/90000 = 10/600), ale u 30,01 fps je 2999/90000 v šestistovkách
        // 19,993 ticku a výstup vyleze jako CFR≈ s 5% kolísáním místo CFR.
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
            // LPCM schválně. AAC by výstupu přidal vlastní priming delay
            // a test synchronu by pak měřil chybu, kterou jsme sami vyrobili.
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: pcmSettings(channels: audioChannels,
                                                                       sampleRate: audioSampleRate))
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

        // 6) Kolik slotů se vejde. Neúplný poslední snímek se nezapisuje.
        let compositionDuration = try await composition.load(.duration)
        let slotCount = frameSlotCount(duration: compositionDuration, frameDuration: frameDuration)

        let resampler = VideoResampler(output: videoOutput,
                                       adaptor: adaptor,
                                       input: videoInput,
                                       writer: writer,
                                       frameDuration: frameDuration,
                                       slotCount: slotCount)

        let group = DispatchGroup()
        group.enter()
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "flatten.video")) {
            if resampler.pump() { group.leave() }
        }

        if let audioInput, let audioOutput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "flatten.audio")) {
                // Zvuk se jen přepošle. Vzorkovací frekvence je konstantní
                // už ve zdroji, není co převzorkovávat.
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
            group.notify(queue: DispatchQueue.global()) {
                continuation.resume()
            }
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

        return FlattenResult(outputURL: outputURL,
                             frameDuration: frameDuration,
                             measuredFrameRate: stats.measuredFrameRate,
                             sourceVerdict: stats.verdict,
                             sourceFrameCount: stats.sampleCount,
                             writtenFrameCount: resampler.written,
                             heldFrames: resampler.held,
                             pixelFormat: fourCC(pixelFormat),
                             bitDepth: depth.value,
                             bitDepthWasDetected: depth.detected,
                             audioChannels: audioChannels,
                             audioSampleRate: audioSampleRate,
                             outputDuration: outputDuration,
                             sourceDuration: compositionDuration,
                             elapsedSeconds: Date().timeIntervalSince(started))
    }

    // MARK: - Pomocné

    /// Kolik celých snímků se do délky vejde.
    static func frameSlotCount(duration: CMTime, frameDuration: CMTime) -> Int {
        guard duration.isValid, frameDuration.isValid, frameDuration.value > 0 else { return 0 }
        let scale = frameDuration.timescale
        let durationTicks = CMTimeConvertScale(duration, timescale: scale,
                                               method: .roundHalfAwayFromZero).value
        return max(0, Int(durationTicks / frameDuration.value))
    }

    /// Bitová hloubka zdroje. `BitsPerComponent` je podle dokumentace
    /// „often not present", takže se počítá s tím, že tam nebude.
    static func bitDepth(from format: CMFormatDescription?) -> (value: Int, detected: Bool) {
        guard let format,
              let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any],
              let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int
        else {
            return (8, false)
        }
        return (bits, true)
    }

    /// Barevné vlastnosti zdroje pro výstupní nastavení.
    static func colorProperties(from format: CMFormatDescription?) -> [String: Any]? {
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

    static func pcmSettings(channels: UInt32, sampleRate: Double) -> [String: Any] {
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

    static func fourCC(_ code: OSType) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "?" })
    }
}
