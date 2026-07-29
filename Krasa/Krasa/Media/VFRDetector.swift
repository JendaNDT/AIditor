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
import ImageIO
import ProbeKit
import TimelineModel

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
    /// Kdy byl záběr natočen (fáze 17) a odkud to víme. `fileSystem` je
    /// náhrada — po zkopírování z karty to bývá čas kopírování.
    var creationDate: Date? = nil
    var creationDateSource: CreationDateSource? = nil

    var isVariable: Bool {
        if case .variable = verdict { return true }
        return false
    }

    var name: String { url.lastPathComponent }

    /// Seřadí materiál chronologicky (fáze 17, modul 3).
    ///
    /// ⚠️ Dřív se řadilo podle JMÉNA. U jedné kamery to projde — název je
    /// časové razítko — ale telefon hosta a druhá kamera mají jinou
    /// konvenci a materiál se rozsype. Klipy bez času natočení jdou
    /// dozadu, mezi sebou podle jména (tam je jméno pořád lepší než nic).
    static func chronological(_ timings: [ClipTiming]) -> [ClipTiming] {
        timings.sorted { a, b in
            switch (a.creationDate, b.creationDate) {
            case let (x?, y?): return x == y ? a.name < b.name : x < y
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return a.name < b.name
            }
        }
    }

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

            let creation = await CreationDateReader.read(url: url)

            return .success(ClipTiming(
                url: url,
                measuredFrameRate: stats.measuredFrameRate,
                nominalFrameRate: Double(nominal),
                verdict: stats.verdict,
                droppedFrames: stats.droppedFrames,
                sampleCount: stats.sampleCount,
                interiorJitterPercent: stats.interiorJitterPercent,
                editListIsIdentity: EditListInfo(track: segments).isIdentity,
                audioSourceOffset: audioOffset,
                creationDate: creation.date,
                creationDateSource: creation.source))
        } catch {
            return .failure(error)
        }
    }
}

/// Kdy byl soubor natočen (fáze 17, modul 3).
///
/// ⚠️ **Synchronní `asset.creationDate` je od macOS 13 deprecated** —
/// čte se asynchronně, a hodnota je `AVMetadataItem`, ze kterého se datum
/// teprve vytahuje (`load(.dateValue)`).
/// <https://developer.apple.com/documentation/avfoundation/avasset/creationdate>
///
/// Když metadata chybí (a chybí u přeposlaných a překódovaných souborů
/// běžně), spadne se na datum souboru — a ŘEKNE se to. Datum souboru je
/// po zkopírování z karty čas kopírování, ne natáčení.
enum CreationDateReader {

    static func read(url: URL) async -> (date: Date?, source: CreationDateSource?) {
        let asset = AVURLAsset(url: url)
        if let item = try? await asset.load(.creationDate),
           let date = try? await item.load(.dateValue) {
            return (date, .metadata)
        }
        // Fotka žádná video metadata nemá — u ní je pravda v EXIFu.
        // Po AirDropu nebo rozbalení archivu je datum souboru čas doručení,
        // zatímco `DateTimeOriginal` je pořád okamžik stisknutí spouště.
        if let date = exifDate(url: url) {
            return (date, .metadata)
        }
        // Poslední záchrana. `contentModificationDate` ne: po přejmenování
        // nebo doteku by ujel.
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        if let date = values?.creationDate {
            return (date, .fileSystem)
        }
        return (nil, nil)
    }

    /// Fotka: EXIF, a když chybí, datum souboru. Synchronně — obrazový
    /// soubor žádnou AVFoundation větev nepotřebuje a import fotek běží
    /// na hlavním vlákně hned po dialogu.
    static func readStill(url: URL) -> (date: Date?, source: CreationDateSource?) {
        if let date = exifDate(url: url) { return (date, .metadata) }
        if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            return (date, .fileSystem)
        }
        return (nil, nil)
    }

    /// EXIF `DateTimeOriginal` — formát `yyyy:MM:dd HH:mm:ss`, bez zóny
    /// (fotoaparát zapisuje místní čas). Čte se v aktuální zóně; posun
    /// o hodinu při cestě do zahraničí je menší zlo než datum kopírování.
    /// <https://developer.apple.com/documentation/imageio/kcgimagepropertyexifdatetimeoriginal>
    private static func exifDate(url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = (exif[kCGImagePropertyExifDateTimeOriginal]
                          ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
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
