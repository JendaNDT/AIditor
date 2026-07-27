//
//  CompositionBuilder.swift
//  Projekt Krása
//
//  Fáze 3, modul 1: z timeline projektu postavit `AVComposition`, aby
//  přehrávač hrál CELOU OSU — sekvenci klipů se správnými výřezy zdrojů —
//  a ne jediný soubor. Rychlostní křivky (segmentace přes `SpeedRampEngine`)
//  přijdou v dalším modulu na tomhle základě; teď hrají všechny klipy 1×.
//
//  Rozhodnutí, která tu platí:
//  - Časy výhradně v timescale projektu (90 000). Frames → CMTime přes
//    počet ticků na snímek; nikdy přes sekundy s plovoucí čárkou.
//  - Zdrojový výřez počítá MODEL (`sourceOffset`, `sourceConsumption`) —
//    tady se jen převádí na `CMTime`. Kdyby si to počítala kompozice sama,
//    rozejde se s trimem a splitem.
//  - Který soubor hraje, říká `Asset.url(usingProxies:)` — jediné místo
//    v projektu, kde se vybírá mezi originálem a proxy.
//  - Mezery na stopě jsou legální: prázdný úsek kompozice je černá/ticho.
//
//  <https://developer.apple.com/documentation/avfoundation/avmutablecomposition>
//  <https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/inserttimerange(_:of:at:)>
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
