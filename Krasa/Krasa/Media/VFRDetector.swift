//
//  VFRDetector.swift
//  Projekt Krása
//
//  Obálka nad ProbeKit. Měřicí logika se tady NEPÍŠE ZNOVU — je ověřená
//  ve Spiku 0 a sdílí ji sonda i zplošťovač. Kdyby appka měřila jinak než
//  nástroje, projevilo by se to jako „v terminálu to vyjde, v appce ne".
//
//  Tahle vrstva jen překládá `TimingStats` na to, co potřebuje UI.
//

import AVFoundation
import Foundation
import ProbeKit

struct ClipTiming {
    let url: URL
    let measuredFrameRate: Double
    let nominalFrameRate: Double
    let verdict: FrameRateVerdict
    let droppedFrames: Int
    let sampleCount: Int
    let interiorJitterPercent: Double
    let editListIsIdentity: Bool
    /// Kde v médiích začíná první prezentovaný zvukový vzorek.
    /// U AAC bývá nenulové (priming) — zvuk se pak nesmí číst syrově.
    let audioSourceOffset: CMTime?

    var isVariable: Bool {
        if case .variable = verdict { return true }
        return false
    }

    var name: String { url.lastPathComponent }

    /// Nejnižší rychlost, kterou klip utáhne bez duplikace snímků.
    ///
    /// `zdrojFps × rychlost ≥ výstupFps`. Pod touhle hodnotou se snímky
    /// opakují a zpomalený úsek trhá — v editoru křivky to bude žlutá zóna.
    func cleanSlowestSpeed(outputFrameRate: Double) -> Double {
        guard measuredFrameRate > 0 else { return 1 }
        return min(1, outputFrameRate / measuredFrameRate)
    }
}

enum VFRDetector {

    /// Změří časování klipu. Chybu nevyhazuje — zabalí ji, aby jeden
    /// rozbitý soubor nezastavil import celé složky.
    static func inspect(url: URL) async -> Result<ClipTiming, Error> {
        do {
            let asset = AVURLAsset(url: url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw VFRError.noVideoTrack
            }
            let (nominal, naturalTimeScale, segments) =
                try await videoTrack.load(.nominalFrameRate, .naturalTimeScale, .segments)

            let timing = await SampleTimingReader.read(track: videoTrack,
                                                       asset: asset,
                                                       naturalTimeScale: naturalTimeScale)
            guard let stats = timing.stats else {
                throw VFRError.timingUnavailable(timing.note ?? "neznámý důvod")
            }

            var audioOffset: CMTime?
            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let audioSegments = try await audioTrack.load(.segments)
                audioOffset = EditListInfo(track: audioSegments).sourceStartOffset
            }

            return .success(ClipTiming(
                url: url,
                measuredFrameRate: stats.measuredFrameRate,
                nominalFrameRate: Double(nominal),
                verdict: stats.verdict,
                droppedFrames: stats.droppedFrames,
                sampleCount: stats.sampleCount,
                interiorJitterPercent: stats.interiorJitterPercent,
                editListIsIdentity: EditListInfo(track: segments).isIdentity,
                audioSourceOffset: audioOffset))
        } catch {
            return .failure(error)
        }
    }
}

enum VFRError: LocalizedError {
    case noVideoTrack
    case timingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Soubor nemá video stopu."
        case .timingUnavailable(let why): return "Nepodařilo se změřit délky vzorků: \(why)"
        }
    }
}
