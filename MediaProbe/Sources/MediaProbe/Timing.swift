//
//  Timing.swift
//  Projekt Krása / MediaProbe
//
//  Čtení skutečných délek jednotlivých vzorků. Tohle je jádro celé sondy —
//  Apple nemá API, které by řeklo „tenhle soubor je VFR", takže se délky
//  musí přečíst a rozptyl v nich najít ručně.
//
//  Primárně přes AVSampleCursor: prochází tabulku vzorků v kontejneru,
//  nedekóduje a nealokuje buffery. Fallback přes AVAssetReader s
//  outputSettings: nil (taky bez dekomprese) pro stopy, které kurzory neumí.
//

import AVFoundation
import CoreMedia
import Foundation

/// Jeden vzorek tak, jak je zapsaný v médiích. Časy jsou v ose médií, ne stopy.
struct SampleTiming {
    let presentationTime: CMTime
    let duration: CMTime
}

struct TimingReadResult {
    let stats: TimingStats?
    /// Varování nebo důvod selhání. Může být vyplněné i při úspěchu.
    let note: String?
}

enum SampleTimingReader {

    // MARK: - Veřejný vstup

    /// Přečte délky vzorků stopy. Nejdřív zkusí kurzor, při neúspěchu čtečku.
    ///
    /// `naturalTimeScale` se předává zvenčí, protože synchronní přístup k němu
    /// je ve Swiftu deprecated a volající ho stejně už načetl.
    static func read(track: AVAssetTrack,
                     asset: AVAsset,
                     naturalTimeScale: CMTimeScale) async -> TimingReadResult {
        var notes: [String] = []

        // 1) AVSampleCursor
        do {
            if try await track.load(.canProvideSampleCursors) {
                if let samples = readWithCursor(track: track) {
                    return finish(samples: samples, source: .sampleCursor,
                                  fallbackTimescale: naturalTimeScale, notes: notes)
                }
                notes.append("Kurzor se nepodařilo vytvořit, přešlo se na AVAssetReader.")
            } else {
                notes.append("Stopa nepodporuje AVSampleCursor, čteno přes AVAssetReader.")
            }
        } catch {
            notes.append("Dotaz na canProvideSampleCursors selhal (\(error.localizedDescription)), "
                       + "čteno přes AVAssetReader.")
        }

        // 2) AVAssetReader
        do {
            let samples = try readWithReader(track: track, asset: asset)
            return finish(samples: samples, source: .assetReader,
                          fallbackTimescale: naturalTimeScale, notes: notes)
        } catch {
            notes.append("AVAssetReader selhal: \(error.localizedDescription)")
            return TimingReadResult(stats: nil, note: notes.joined(separator: " "))
        }
    }

    // MARK: - AVSampleCursor

    /// Projde vzorky v dekódovacím pořadí. Každý vzorek se navštíví právě jednou,
    /// takže množina délek je stejná jako v prezentačním pořadí — seřadí se až potom.
    private static func readWithCursor(track: AVAssetTrack) -> [SampleTiming]? {
        guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return nil }

        var samples: [SampleTiming] = []
        repeat {
            samples.append(SampleTiming(presentationTime: cursor.presentationTimeStamp,
                                        duration: cursor.currentSampleDuration))
            // Vrací počet skutečně provedených kroků — na konci stopy 0.
        } while cursor.stepInDecodeOrder(byCount: 1) == 1

        return samples.isEmpty ? nil : samples
    }

    // MARK: - AVAssetReader

    private static func readWithReader(track: AVAssetTrack, asset: AVAsset) throws -> [SampleTiming] {
        let reader = try AVAssetReader(asset: asset)
        // nil = vzorky se vrátí v uloženém formátu, tedy bez dekomprese.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw ProbeError.message("AVAssetReader výstup stopy nepřijal.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ProbeError.message("AVAssetReader se nepodařilo spustit.")
        }
        defer { reader.cancelReading() }

        var samples: [SampleTiming] = []
        while let buffer = output.copyNextSampleBuffer() {
            samples.append(contentsOf: timings(from: buffer))
        }

        if reader.status == .failed {
            throw reader.error ?? ProbeError.message("Čtení skončilo ve stavu .failed.")
        }
        return samples
    }

    /// Rozebere buffer na jednotlivé vzorky. U komprimovaného videa je v bufferu
    /// obvykle jeden vzorek, ale spoléhat se na to nejde.
    private static func timings(from buffer: CMSampleBuffer) -> [SampleTiming] {
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count > 1 else {
            return [SampleTiming(presentationTime: CMSampleBufferGetPresentationTimeStamp(buffer),
                                 duration: CMSampleBufferGetDuration(buffer))]
        }

        var needed: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0,
                                                     arrayToFill: nil,
                                                     entriesNeededOut: &needed) == noErr,
              needed > 0 else {
            return []
        }

        let blank = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: .invalid,
                                       decodeTimeStamp: .invalid)
        var infos = [CMSampleTimingInfo](repeating: blank, count: needed)
        guard CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: needed,
                                                     arrayToFill: &infos,
                                                     entriesNeededOut: nil) == noErr else {
            return []
        }

        // Jediný záznam znamená „všechny vzorky v bufferu mají tohle časování".
        if infos.count == 1 {
            let info = infos[0]
            return (0..<count).map { i in
                let offset = CMTimeMultiply(info.duration, multiplier: Int32(i))
                return SampleTiming(presentationTime: info.presentationTimeStamp + offset,
                                    duration: info.duration)
            }
        }

        return infos.map {
            SampleTiming(presentationTime: $0.presentationTimeStamp, duration: $0.duration)
        }
    }

    // MARK: - Převod na statistiku

    private static func finish(samples: [SampleTiming],
                               source: TimingSource,
                               fallbackTimescale: CMTimeScale,
                               notes: [String]) -> TimingReadResult {
        var notes = notes

        // Vzorky bez použitelné délky se do statistiky nepustí — pokazily by modus
        // i směrodatnou odchylku. Nezahazují se ale potichu.
        let usable = samples.filter { $0.duration.isValid && !$0.duration.isIndefinite && $0.duration.value > 0 }
        let dropped = samples.count - usable.count
        if dropped > 0 {
            notes.append("\(dropped) vzork(ů) mělo neplatnou nebo nulovou délku a do statistiky se nepočítá.")
        }
        guard !usable.isEmpty else {
            notes.append("Stopa nevrátila žádný vzorek s použitelnou délkou.")
            return TimingReadResult(stats: nil, note: notes.joined(separator: " "))
        }

        // Seřadit podle prezentačního času — kvůli rozpoznání okrajového vzorku
        // musí být „první" a „poslední" opravdu první a poslední na obrazovce.
        let ordered = usable.sorted { lhs, rhs in
            guard lhs.presentationTime.isValid, rhs.presentationTime.isValid else { return false }
            return lhs.presentationTime < rhs.presentationTime
        }

        // Porovnává se v celých tickách. Když se timescale liší napříč vzorky,
        // převede se na nejjemnější a označí, že čísla prošla konverzí.
        let scales = Set(ordered.map(\.duration.timescale))
        let base = scales.max() ?? fallbackTimescale
        let rescaled = scales.count > 1
        if rescaled {
            notes.append("Vzorky mají různé timescale (\(scales.sorted().map(String.init).joined(separator: ", "))); "
                       + "délky převedeny na \(base). Rozptyl může být zkreslený zaokrouhlením.")
        }

        let ticks: [Int64] = ordered.map { sample in
            sample.duration.timescale == base
                ? sample.duration.value
                : CMTimeConvertScale(sample.duration, timescale: base,
                                     method: .roundHalfAwayFromZero).value
        }

        let stats = TimingStats(source: source, timescale: base, rescaled: rescaled, ticks: ticks)
        return TimingReadResult(stats: stats, note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }
}

// MARK: - Chyba sondy

enum ProbeError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
