//
//  CompositionBuilder.swift
//  Projekt Krása
//
//  Fáze 3, moduly 1 a 2: z timeline projektu postavit `AVComposition`, aby
//  přehrávač hrál CELOU OSU — sekvenci klipů se správnými výřezy zdrojů —
//  včetně rychlostních křivek.
//
//  Rozhodnutí, která tu platí:
//  - Časy výhradně v timescale projektu (90 000). Frames → CMTime přes
//    počet ticků na snímek; nikdy přes sekundy s plovoucí čárkou.
//  - Zdrojový výřez počítá MODEL (`sourceOffset`, `sourceConsumption`) —
//    tady se jen převádí na `CMTime`. Kdyby si to počítala kompozice sama,
//    rozejde se s trimem a splitem.
//  - Rampu počítá také model (`rampPlaybackPlan` — segmentace v celých
//    tickách, mez skoku 1,5 % ze Spiku 0). Tady se jen volá `scaleTimeRange`
//    POZPÁTKU, od posledního úseku k prvnímu: škálování úseku posune všechno
//    ZA ním, ale nic před ním — vzorec ověřený nástrojem `Ramp`.
//  - Který soubor hraje, říká `Asset.url(usingProxies:)` — jediné místo
//    v projektu, kde se vybírá mezi originálem a proxy.
//  - Mezery na stopě jsou legální: prázdný úsek kompozice je černá/ticho.
//
//  <https://developer.apple.com/documentation/avfoundation/avmutablecomposition>
//  <https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/inserttimerange(_:of:at:)>
//  <https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/scaletimerange(_:toduration:)>
//

import AVFoundation
import Foundation
import TimelineModel

enum CompositionBuilder {

    /// Postaví kompozici z projektu. Vrací `nil`, když na ose není žádný
    /// klip — prázdnou kompozici nemá smysl dávat přehrávači.
    static func build(project: Project, usingProxies: Bool = false) async throws -> AVMutableComposition? {
        let timeline = project.timeline
        guard timeline.tracks.contains(where: { !$0.clips.isEmpty }) else { return nil }

        let composition = AVMutableComposition()
        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(timeline.frameRate)

        // Jeden AVURLAsset na soubor, ať se metadata nenačítají pro každý
        // klip téhož assetu znovu.
        var loadedAssets: [URL: AVURLAsset] = [:]
        func asset(for url: URL) -> AVURLAsset {
            if let cached = loadedAssets[url] { return cached }
            let created = AVURLAsset(url: url)
            loadedAssets[url] = created
            return created
        }

        for track in timeline.tracks {
            guard !track.clips.isEmpty else { continue }

            let mediaType: AVMediaType = track.kind == .video ? .video : .audio
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }

            for clip in track.clips {
                guard let source = project.asset(clip.assetID) else { continue }
                let sourceAsset = asset(for: source.url(usingProxies: usingProxies))
                guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: mediaType).first
                else { continue }   // klip bez odpovídající stopy se přeskočí, nespadne

                // Výřez zdroje: začátek i spotřebu počítá model.
                let start = clip.sourceStart.converted(to: SourceTime.projectTimescale)
                let consumed = project.sourceConsumption(of: clip)
                    .converted(to: SourceTime.projectTimescale)
                let range = CMTimeRange(
                    start: CMTime(value: start.value, timescale: SourceTime.projectTimescale),
                    duration: CMTime(value: consumed.value, timescale: SourceTime.projectTimescale))

                let at = CMTime(value: Int64(clip.timelineStart.count) * ticksPerFrame,
                                timescale: SourceTime.projectTimescale)
                try compositionTrack.insertTimeRange(range, of: sourceTrack, at: at)

                // Rychlostní křivka: vložený rozsah (zatím 1:1) se přeškáluje
                // po úsecích plánu. Pozpátku — škálování posouvá jen obsah za
                // úsekem, takže pozice dřívějších úseků zůstávají platné.
                // Po posledním škálování zabírá klip přesně svůj slot na ose.
                if let plan = project.rampPlaybackPlan(of: clip) {
                    for segment in plan.segments.reversed() {
                        guard segment.sourceDurationTicks > 0, segment.outputTicks > 0 else { continue }
                        let segmentRange = CMTimeRange(
                            start: CMTime(value: at.value + segment.sourceStartTicks,
                                          timescale: SourceTime.projectTimescale),
                            duration: CMTime(value: segment.sourceDurationTicks,
                                             timescale: SourceTime.projectTimescale))
                        compositionTrack.scaleTimeRange(
                            segmentRange,
                            toDuration: CMTime(value: segment.outputTicks,
                                               timescale: SourceTime.projectTimescale))
                    }
                }
            }
        }

        return composition
    }

    /// Snímek osy → čas kompozice. Celé ticky, žádné sekundy s čárkou.
    static func time(of frame: Frames, frameRate: Int) -> CMTime {
        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(frameRate)
        return CMTime(value: Int64(frame.count) * ticksPerFrame,
                      timescale: SourceTime.projectTimescale)
    }

    /// Čas kompozice → snímek osy. Zaokrouhluje dolů — hlava ukazuje snímek,
    /// který se právě zobrazuje, ne ten příští.
    static func frame(of time: CMTime, frameRate: Int) -> Frames {
        guard time.isValid, time.isNumeric else { return .zero }
        let ticks = CMTimeConvertScale(time, timescale: SourceTime.projectTimescale,
                                       method: .default).value
        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(frameRate)
        return Frames(Int(max(0, ticks / ticksPerFrame)))
    }
}
