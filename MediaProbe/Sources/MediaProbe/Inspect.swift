//
//  Inspect.swift
//  Projekt Krása / MediaProbe
//
//  Načtení vlastností stop. Všechno jde přes async `load(_:)` — synchronní
//  přístupové vlastnosti (naturalSize, nominalFrameRate, formatDescriptions…)
//  jsou ve Swiftu deprecated od macOS 13.
//

import AVFoundation
import CoreMedia
import Foundation

enum ClipInspector {

    /// Prozkoumá jeden soubor. Chybu nevyhazuje — zabalí ji do výsledku,
    /// aby jeden rozbitý klip nezastavil celou dávku.
    static func inspect(url: URL) async -> ClipReport {
        let asset = AVURLAsset(url: url)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil

        do {
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            let video = try await videoTracks.first.asyncMap { try await inspectVideo(track: $0, asset: asset) }
            let audio = try await audioTracks.first.asyncMap { try await inspectAudio(track: $0) }

            return ClipReport(url: url,
                              fileSize: fileSize,
                              duration: duration,
                              formatName: url.pathExtension.uppercased(),
                              video: video,
                              audio: audio,
                              failure: nil)
        } catch {
            return .failed(url: url, message: error.localizedDescription)
        }
    }

    // MARK: - Video

    private static func inspectVideo(track: AVAssetTrack, asset: AVAsset) async throws -> VideoTrackInfo {
        let (naturalSize, transform, nominalFrameRate) =
            try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let (minFrameDuration, timeRange, naturalTimeScale) =
            try await track.load(.minFrameDuration, .timeRange, .naturalTimeScale)
        let (formats, segments, dataRate) =
            try await track.load(.formatDescriptions, .segments, .estimatedDataRate)

        let rotation = rotationDegrees(from: transform)
        let display = displaySize(naturalSize: naturalSize, transform: transform)

        var encoded = CGSize.zero
        var fourCC = "—"
        var codecName = "neznámý"
        if let format = formats.first {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            encoded = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
            let subType = CMFormatDescriptionGetMediaSubType(format)
            fourCC = fourCCString(subType)
            codecName = videoCodecName(subType)
        }

        let timing = await SampleTimingReader.read(track: track, asset: asset,
                                                   naturalTimeScale: naturalTimeScale)

        return VideoTrackInfo(naturalSize: naturalSize,
                              encodedSize: encoded,
                              preferredTransform: transform,
                              rotationDegrees: rotation,
                              displaySize: display,
                              codec: codecName,
                              codecFourCC: fourCC,
                              nominalFrameRate: nominalFrameRate,
                              minFrameDuration: minFrameDuration,
                              timeRange: timeRange,
                              naturalTimeScale: naturalTimeScale,
                              estimatedDataRate: dataRate,
                              editList: editList(from: segments),
                              timing: timing.stats,
                              timingError: timing.note)
    }

    // MARK: - Zvuk

    private static func inspectAudio(track: AVAssetTrack) async throws -> AudioTrackInfo {
        let (formats, segments, timeRange) =
            try await track.load(.formatDescriptions, .segments, .timeRange)

        var fourCC = "—"
        var codecName = "neznámý"
        var channels: UInt32 = 0
        var sampleRate: Double = 0

        if let format = formats.first {
            let subType = CMFormatDescriptionGetMediaSubType(format)
            fourCC = fourCCString(subType)
            codecName = audioCodecName(subType)
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                channels = asbd.pointee.mChannelsPerFrame
                sampleRate = asbd.pointee.mSampleRate
            }
        }

        return AudioTrackInfo(codec: codecName,
                              codecFourCC: fourCC,
                              channels: channels,
                              sampleRate: sampleRate,
                              editList: editList(from: segments),
                              timeRange: timeRange)
    }

    // MARK: - Edit list

    private static func editList(from segments: [AVAssetTrackSegment]) -> EditListInfo {
        EditListInfo(segments: segments.enumerated().map { index, segment in
            SegmentInfo(index: index, isEmpty: segment.isEmpty, mapping: segment.timeMapping)
        })
    }

    // MARK: - Orientace

    /// Úhel z `preferredTransform`. U klipu z telefonu na výšku je to typicky 90°,
    /// zatímco `naturalSize` zůstává na šířku.
    static func rotationDegrees(from t: CGAffineTransform) -> Int {
        let radians = atan2(Double(t.b), Double(t.a))
        var degrees = Int((radians * 180 / .pi).rounded())
        if degrees < 0 { degrees += 360 }
        return degrees % 360
    }

    static func displaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    // MARK: - Kodeky

    static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let scalars = bytes.map { byte -> Character in
            (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        return String(scalars)
    }

    static func videoCodecName(_ subType: FourCharCode) -> String {
        switch subType {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_HEVCWithAlpha: return "HEVC + alfa"
        case kCMVideoCodecType_AppleProRes4444XQ: return "ProRes 4444 XQ"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        case kCMVideoCodecType_AppleProRes422HQ: return "ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes422LT: return "ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy: return "ProRes 422 Proxy"
        case kCMVideoCodecType_AppleProResRAW: return "ProRes RAW"
        case kCMVideoCodecType_AppleProResRAWHQ: return "ProRes RAW HQ"
        case kCMVideoCodecType_JPEG: return "JPEG"
        case kCMVideoCodecType_MPEG4Video: return "MPEG-4"
        default: return "jiný"
        }
    }

    static func audioCodecName(_ subType: FourCharCode) -> String {
        switch subType {
        case kAudioFormatLinearPCM: return "Linear PCM"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEG4AAC_HE: return "AAC-HE"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatAC3: return "AC-3"
        case kAudioFormatEnhancedAC3: return "E-AC-3"
        case kAudioFormatAMR: return "AMR"
        default: return "jiný"
        }
    }
}

// MARK: - Drobná pomůcka

extension Optional {
    /// `map`, který umí await. Ušetří pár `if let` v `inspect`.
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
