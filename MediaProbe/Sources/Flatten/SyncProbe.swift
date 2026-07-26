//
//  SyncProbe.swift
//  Projekt Krása / Flatten
//
//  Hledání ostrých transientů ve zvuku. Dvě použití:
//
//  1. Test synchronu — tleskne v původním i zploštěném souboru ve stejný čas?
//  2. Křížová kontrola, který klip je ten referenční s tlesknutím. Ruční
//     označení v CLIPS.txt je paměť, tohle je měření. Když se rozejdou,
//     je to potřeba vědět dřív než po hodině hledání chyby jinde.
//
//  Zvuk se čte PŘES AVComposition. Bez toho by se měřil edit list
//  (44 ms priming AAC), ne synchron.
//

import AVFoundation
import CoreMedia
import Foundation
import ProbeKit

struct TransientWindow {
    let label: String
    let startSeconds: Double
    let endSeconds: Double
    let peak: Float
    let peakTime: Double
    /// První vzorek, který dosáhl poloviny vrcholu okna. Náběh je u tlesknutí
    /// ostřejší a stabilnější měřítko než samotná špička.
    let onsetTime: Double
    /// Vrchol vůči celkové efektivní hodnotě. U tlesknutí vysoký.
    let crestFactor: Double
    /// Jak daleko je vrchol od kraje stopy. Záměrné tlesknutí na synchron
    /// se tleská hned na začátku a těsně před koncem, takže tohle je malé.
    let distanceFromEdge: Double
    /// Rozestup náběhu a vrcholu. U izolovaného tlesknutí skoro nula,
    /// u souvislého zvuku (řeč, ruch) velký — náběh chytí jinou událost.
    let onsetToPeak: Double
}

struct AudioAnalysis {
    let url: URL
    let duration: Double
    let sampleRate: Double
    let channels: Int
    let frameCount: Int
    let overallRMS: Double
    let start: TransientWindow?
    let end: TransientWindow?

    var name: String { url.lastPathComponent }

    /// Jak daleko od krajů stopy leží oba vrcholy. Menší = spíš záměrná značka.
    var worstEdgeDistance: Double {
        guard let start, let end else { return .infinity }
        return max(start.distanceFromEdge, end.distanceFromEdge)
    }

    /// Heuristika, ne měření pravdy.
    ///
    /// Samotný crest faktor nerozlišuje — na testovací sadě vyšel u všech pěti
    /// klipů mezi 12× a 30×, protože každý obsahuje nějaký hlasitý zvuk.
    /// Rozlišuje až **poloha vrcholu vůči kraji**: kdo tleská na synchron,
    /// tleská hned na začátku a těsně před koncem.
    var looksLikeClap: Bool {
        guard let start, let end else { return false }
        return start.crestFactor >= 4 && end.crestFactor >= 4
            && start.peak >= 0.2 && end.peak >= 0.2
            && worstEdgeDistance <= 1.5
    }
}

enum SyncProbe {

    /// Délka okna na začátku i na konci, ve kterém se transient hledá.
    static let windowSeconds: Double = 5.0

    // MARK: - Analýza jednoho souboru

    static func analyze(url: URL) async throws -> AudioAnalysis {
        let asset = AVURLAsset(url: url)
        guard let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ProbeError.message("\(url.lastPathComponent) nemá zvukovou stopu.")
        }

        // Kompozice kvůli edit listu — jinak by se měřil priming, ne synchron.
        let composition = AVMutableComposition()
        let timeRange = try await sourceAudio.load(.timeRange)
        guard let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProbeError.message("Nepodařilo se založit zvukovou stopu kompozice.")
        }
        try compAudio.insertTimeRange(timeRange, of: sourceAudio, at: .zero)

        let formats = try await sourceAudio.load(.formatDescriptions)
        guard let asbd = formats.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0) }) else {
            throw ProbeError.message("Nepodařilo se přečíst formát zvuku.")
        }
        let sampleRate = asbd.pointee.mSampleRate
        let channels = Int(asbd.pointee.mChannelsPerFrame)

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderTrackOutput(track: compAudio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ProbeError.message("Čtečka nepřijala zvukový výstup.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ProbeError.message("Čtečku se nepodařilo spustit.")
        }
        defer { reader.cancelReading() }

        // Obálka: jedna hodnota na snímek, maximum přes kanály.
        var envelope: [Float] = []
        var sumOfSquares = 0.0

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }

            var bytes = [UInt8](repeating: 0, count: length)
            guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                             destination: &bytes) == noErr else { continue }

            bytes.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Float.self)
                var index = 0
                while index + channels <= samples.count {
                    var peak: Float = 0
                    for channel in 0..<channels {
                        peak = max(peak, abs(samples[index + channel]))
                    }
                    envelope.append(peak)
                    sumOfSquares += Double(peak) * Double(peak)
                    index += channels
                }
            }
        }

        if reader.status == .failed {
            throw reader.error ?? ProbeError.message("Čtení zvuku selhalo.")
        }
        guard !envelope.isEmpty else {
            throw ProbeError.message("Zvuková stopa nevrátila žádné vzorky.")
        }

        let rms = (sumOfSquares / Double(envelope.count)).squareRoot()
        let duration = Double(envelope.count) / sampleRate

        let window = min(windowSeconds, duration / 2)
        let start = transient(in: envelope, sampleRate: sampleRate, rms: rms,
                              from: 0, to: window, label: "začátek",
                              edgeTime: 0)
        let end = transient(in: envelope, sampleRate: sampleRate, rms: rms,
                            from: duration - window, to: duration, label: "konec",
                            edgeTime: duration)

        return AudioAnalysis(url: url,
                             duration: duration,
                             sampleRate: sampleRate,
                             channels: channels,
                             frameCount: envelope.count,
                             overallRMS: rms,
                             start: start,
                             end: end)
    }

    // MARK: - Transient v okně

    private static func transient(in envelope: [Float],
                                  sampleRate: Double,
                                  rms: Double,
                                  from startSeconds: Double,
                                  to endSeconds: Double,
                                  label: String,
                                  edgeTime: Double) -> TransientWindow? {
        let first = max(0, Int(startSeconds * sampleRate))
        let last = min(envelope.count, Int(endSeconds * sampleRate))
        guard first < last else { return nil }

        var peak: Float = 0
        var peakIndex = first
        for index in first..<last where envelope[index] > peak {
            peak = envelope[index]
            peakIndex = index
        }
        guard peak > 0 else { return nil }

        // Náběh: první překročení poloviny vrcholu.
        let threshold = peak * 0.5
        var onsetIndex = peakIndex
        for index in first..<last where envelope[index] >= threshold {
            onsetIndex = index
            break
        }

        let peakTime = Double(peakIndex) / sampleRate
        let onsetTime = Double(onsetIndex) / sampleRate

        return TransientWindow(label: label,
                               startSeconds: startSeconds,
                               endSeconds: endSeconds,
                               peak: peak,
                               peakTime: peakTime,
                               onsetTime: onsetTime,
                               crestFactor: rms > 0 ? Double(peak) / rms : 0,
                               distanceFromEdge: abs(peakTime - edgeTime),
                               onsetToPeak: peakTime - onsetTime)
    }
}
