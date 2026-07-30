//
//  Ramper.swift
//  Projekt AIditor / Ramp
//
//  Plynulá rychlostní křivka segmentací na mikro-úseky.
//
//  Tohle je jádro celého spiku. `scaleTimeRange` umí jen konstantní rychlost
//  na daném úseku, takže plynulý Bézier vznikne tak, že se klip nakrájí na
//  desítky až stovky krátkých úseků a každý dostane vlastní konstantní
//  rychlost podle křivky.
//
//  Dvě věci, na kterých to stojí a které se dají snadno udělat špatně:
//
//  1. `scaleTimeRange` se aplikuje POZPÁTKU, od posledního úseku k prvnímu.
//     Škálování úseku posune všechno za ním, ale nic před ním. Kdyby se šlo
//     odpředu, musely by se všechny následující rozsahy přepočítávat.
//
//  2. Časy se počítají v CELÝCH TICKÁCH kumulativně, ne zaokrouhlením každého
//     úseku zvlášť. Jinak by se mezi úseky nasčítaly mezery nebo přesahy.
//

import AVFoundation
import CoreMedia
import Foundation
import ProbeKit
import SpeedRampEngine

struct RampResult {
    let outputURL: URL
    let framesPerSegment: Int
    let segmentCount: Int
    /// Zadaná mez skoku rychlosti, když se segmentovalo podle ní.
    let requestedMaxStep: Double?
    let limitedByFrameRate: Bool
    let outputFrameRate: Double
    let expectedOutputDuration: Double
    let compositionDuration: CMTime
    let sourceDuration: CMTime
    let slowestSpeed: Double
    let fastestSpeed: Double
    /// Největší skok rychlosti mezi sousedními úseky. Kandidát na to,
    /// co je slyšet jako lupnutí.
    let largestSpeedStep: Double
    let fileSizeBytes: Int64?
    let render: CFRRenderResult
}

enum Ramper {

    /// Postaví ramp 1,0 → `slowSpeed` → 1,0 přes celý klip a vyrenderuje ho.
    static func run(source: URL,
                    to outputURL: URL,
                    outputFrameRate: Double,
                    framesPerSegment: Int?,
                    maxSpeedStep: Double?,
                    slowSpeed: Double,
                    pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain) async throws -> RampResult {

        let asset = AVURLAsset(url: source)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.message("Soubor nemá video stopu.")
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let sourceDuration = try await asset.load(.duration)

        // 1) Křivka. Matematika je hotová a ověřená 31 testy — tady se s ní
        //    nesmlouvá, jen se převádí na CMTime.
        let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: sourceDuration.seconds,
                                                   slowSpeed: slowSpeed)
        // Výchozí cesta je mez skoku rychlosti. Pevný počet snímků na úsek
        // je špatná veličina — skok závisí na délce klipu, takže stejná
        // hodnota dá na 45s klipu 0,96 % a na 11s klipu 3,79 %.
        let segments: [RampSegment]
        let chosenFramesPerSegment: Int
        let limited: Bool
        if let maxSpeedStep {
            let plan = try ramp.segmentation(outputFrameRate: outputFrameRate,
                                             maxSpeedStep: maxSpeedStep)
            segments = plan.segments
            chosenFramesPerSegment = plan.framesPerSegment
            limited = plan.limitedByFrameRate
        } else {
            let perSegment = framesPerSegment ?? 8
            segments = try ramp.segments(outputFrameRate: outputFrameRate,
                                         framesPerSegment: perSegment)
            chosenFramesPerSegment = perSegment
            limited = false
        }
        guard !segments.isEmpty else {
            throw ProbeError.message("Segmentace vrátila prázdný seznam.")
        }

        // 2) Časová základna. Délka snímku musí v ní vyjít celočíselně.
        let timescale = try await sourceVideo.load(.naturalTimeScale)
        let frameTicks = Int64((Double(timescale) / outputFrameRate).rounded())
        guard frameTicks > 0 else {
            throw ProbeError.message("Snímková frekvence \(outputFrameRate) nejde vyjádřit v timescale \(timescale).")
        }
        let frameDuration = CMTime(value: frameTicks, timescale: timescale)

        // 3) Kompozice se zdrojem 1:1.
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProbeError.message("Nepodařilo se založit video stopu kompozice.")
        }
        let videoTimeRange = try await sourceVideo.load(.timeRange)
        try compVideo.insertTimeRange(videoTimeRange, of: sourceVideo, at: .zero)

        var compAudio: AVMutableCompositionTrack?
        if let sourceAudio {
            let audioTimeRange = try await sourceAudio.load(.timeRange)
            let track = composition.addMutableTrack(withMediaType: .audio,
                                                    preferredTrackID: kCMPersistentTrackID_Invalid)
            try track?.insertTimeRange(audioTimeRange, of: sourceAudio, at: .zero)
            compAudio = track
        }

        // 4) Převod úseků na celé ticky, kumulativně.
        let ticks = tickPlan(segments: segments,
                            timescale: timescale,
                            frameTicks: frameTicks,
                            outputFrameRate: outputFrameRate,
                            sourceDuration: sourceDuration)

        // 5) scaleTimeRange POZPÁTKU. Škálování úseku posune všechno za ním,
        //    ale nic před ním — proto od konce.
        for step in ticks.reversed() {
            guard step.sourceTicks > 0, step.outputTicks > 0 else { continue }
            composition.scaleTimeRange(
                CMTimeRange(start: CMTime(value: step.sourceStartTicks, timescale: timescale),
                            duration: CMTime(value: step.sourceTicks, timescale: timescale)),
                toDuration: CMTime(value: step.outputTicks, timescale: timescale))
        }

        let compositionDuration = try await composition.load(.duration)

        // 6) Render na pevnou mřížku. Korekce výšky hlasu je tady povinná —
        //    kompozice obsahuje škálované zvukové úseky.
        let render = try await CFRRenderer.render(asset: composition,
                                                  videoTrack: compVideo,
                                                  audioTracks: compAudio.map { [$0] } ?? [],
                                                  frameDuration: frameDuration,
                                                  audioTimePitchAlgorithm: pitchAlgorithm,
                                                  to: outputURL)

        let speeds = segments.map(\.speed)
        var largestStep = 0.0
        for index in 1..<max(1, speeds.count) where index < speeds.count {
            largestStep = max(largestStep, abs(speeds[index] - speeds[index - 1]))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? nil

        return RampResult(outputURL: outputURL,
                          framesPerSegment: chosenFramesPerSegment,
                          segmentCount: segments.count,
                          requestedMaxStep: maxSpeedStep,
                          limitedByFrameRate: limited,
                          outputFrameRate: outputFrameRate,
                          expectedOutputDuration: ramp.outputDuration,
                          compositionDuration: compositionDuration,
                          sourceDuration: sourceDuration,
                          slowestSpeed: speeds.min() ?? 0,
                          fastestSpeed: speeds.max() ?? 0,
                          largestSpeedStep: largestStep,
                          fileSizeBytes: size,
                          render: render)
    }

    // MARK: - Převod na ticky

    struct TickStep {
        let sourceStartTicks: Int64
        let sourceTicks: Int64
        let outputTicks: Int64
    }

    /// Převede úseky na celá čísla ticků tak, aby na sebe přesně navazovaly.
    ///
    /// Zaokrouhluje se KUMULATIVNÍ hranice, ne délka každého úseku zvlášť —
    /// jinak by se chyby nasčítaly a mezi úseky by vznikly mezery.
    ///
    /// Výstupní délka se navíc drží na celých snímcích: úsek `k` pokrývá
    /// snímky `[k·N, (k+1)·N)`, takže výsledek je přesný násobek délky snímku
    /// a poslední snímek nezůstane useknutý.
    static func tickPlan(segments: [RampSegment],
                         timescale: CMTimeScale,
                         frameTicks: Int64,
                         outputFrameRate: Double,
                         sourceDuration: CMTime) -> [TickStep] {
        let scale = Double(timescale)
        let sourceTotalTicks = CMTimeConvertScale(sourceDuration, timescale: timescale,
                                                  method: .roundHalfAwayFromZero).value

        var steps: [TickStep] = []
        steps.reserveCapacity(segments.count)

        var sourceCursor: Int64 = 0
        var cumulativeSource = 0.0

        for (index, segment) in segments.enumerated() {
            cumulativeSource += segment.sourceDuration

            // Hranice zdroje: zaokrouhlení kumulativní hodnoty, poslední úsek
            // dotažený přesně na konec klipu, ať nezůstane zbytek.
            let isLast = index == segments.count - 1
            let sourceEnd = isLast
                ? sourceTotalTicks
                : min(sourceTotalTicks, Int64((cumulativeSource * scale).rounded()))

            // Počet snímků se bere z úseku samotného, ne z `framesPerSegment`.
            // Poslední úsek je zkrácený — `SpeedRampEngine.segments()` ho ořezává
            // přes `min(totalFrames, (k+1)*perSegment)`. Kdyby se tady počítalo
            // vždy `framesPerSegment`, výstup by byl delší, a to tím víc, čím
            // hrubší segmentace: u 8 snímků na úsek o 7 snímků = 227 ms.
            let frames = max(1, Int((segment.outputDuration * outputFrameRate).rounded()))
            let outputTicks = Int64(frames) * frameTicks

            steps.append(TickStep(sourceStartTicks: sourceCursor,
                                  sourceTicks: max(0, sourceEnd - sourceCursor),
                                  outputTicks: outputTicks))
            sourceCursor = sourceEnd
        }
        return steps
    }
}
