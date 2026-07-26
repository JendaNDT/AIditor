//
//  Model.swift
//  Projekt Krása / MediaProbe
//
//  Tvar výsledku sondy. Měřicí jádro (TimingStats, klasifikace vzorků,
//  edit list) žije v ProbeKit, ať ho může použít i nástroj na zploštění.
//

import AVFoundation
import CoreMedia
import Foundation
import ProbeKit

// MARK: - Stopy

struct VideoTrackInfo {
    let naturalSize: CGSize
    let encodedSize: CGSize
    let preferredTransform: CGAffineTransform
    let rotationDegrees: Int
    let displaySize: CGSize
    let codec: String
    let codecFourCC: String
    let nominalFrameRate: Float
    let minFrameDuration: CMTime
    let timeRange: CMTimeRange
    let naturalTimeScale: CMTimeScale
    let estimatedDataRate: Float
    let editList: EditListInfo
    let timing: TimingStats?
    /// Proč se délky vzorků nepodařilo přečíst, pokud `timing == nil`.
    let timingError: String?

    var isPortrait: Bool { displaySize.height > displaySize.width }

    /// Snímková frekvence, jak ji uvidí divák — tedy po započtení edit listu.
    var effectiveFrameRate: Double? {
        guard let measured = timing?.measuredFrameRate, measured > 0 else { return nil }
        guard let rate = editList.overallRate, rate > 0 else { return measured }
        return measured / rate
    }
}

struct AudioTrackInfo {
    let codec: String
    let codecFourCC: String
    let channels: UInt32
    let sampleRate: Double
    let editList: EditListInfo
    let timeRange: CMTimeRange
}

// MARK: - Výsledek za jeden soubor

struct ClipReport {
    let url: URL
    let fileSize: Int64?
    let duration: CMTime
    let formatName: String
    let video: VideoTrackInfo?
    let audio: AudioTrackInfo?
    /// Ručně psaná poznámka z CLIPS.txt — co se na klipu točilo.
    let note: String?
    /// Vyplněné, když se soubor nepodařilo otevřít vůbec.
    let failure: String?

    var name: String { url.lastPathComponent }

    static func failed(url: URL, message: String, note: String? = nil) -> ClipReport {
        ClipReport(url: url, fileSize: nil, duration: .invalid, formatName: "—",
                   video: nil, audio: nil, note: note, failure: message)
    }
}
