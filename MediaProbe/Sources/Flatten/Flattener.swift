//
//  Flattener.swift
//  Projekt AIditor / Flatten
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
//  Vlastní render dělá `CFRRenderer` v ProbeKitu — sdílený s nástrojem `Ramp`.
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
    let render: CFRRenderResult
}

enum Flattener {

    static func flatten(source: URL, to outputURL: URL) async throws -> FlattenResult {
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

        // 3) Render. Rychlost se nemění, takže korekce výšky hlasu nemá co řešit.
        let render = try await CFRRenderer.render(asset: composition,
                                                  videoTrack: compVideo,
                                                  audioTracks: compAudio.map { [$0] } ?? [],
                                                  frameDuration: frameDuration,
                                                  audioTimePitchAlgorithm: nil,
                                                  to: outputURL)

        return FlattenResult(outputURL: outputURL,
                             frameDuration: frameDuration,
                             measuredFrameRate: stats.measuredFrameRate,
                             sourceVerdict: stats.verdict,
                             sourceFrameCount: stats.sampleCount,
                             render: render)
    }
}
