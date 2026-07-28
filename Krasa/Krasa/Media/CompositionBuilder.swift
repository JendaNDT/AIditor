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
//  - Zdrojový výřez počítá MODEL (`compositionPlan` → `sourceOffset`,
//    `sourceConsumption`) — tady se jen převádí na `CMTime`. Kdyby si to
//    počítala kompozice sama, rozejde se s trimem a splitem.
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
//  Fáze 7, modul 2: per-track hlasitost a mute přes `AVAudioMix`. Kompozice
//  si pamatuje, která její zvuková stopa patří které stopě osy, a mix se
//  z aktuálních hlasitostí staví ZVLÁŠŤ (`audioMix(project:)`) — díky tomu
//  jde při změně hlasitosti vyměnit jen mix na běžícím player itemu,
//  bez přestavby kompozice a bez zastavení přehrávání.
//  <https://developer.apple.com/documentation/avfoundation/avmutableaudiomix>
//  <https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters>
//
//  Fáze 10, modul 2: přechody. CO se kam vkládá, říká model
//  (`compositionPlan` — dráhy A/B, ramena prolínaček, předpisy oblastí);
//  tady se plán jen převádí na AVFoundation:
//  - členové prolínačky/crossfadu jdou na DVĚ stopy kompozice (A/B roll)
//    s rameny přes hranu střihu,
//  - obraz dostane `AVMutableVideoComposition` s instrukcemi: opacity rampa
//    přes překryv (prolínačka), pokles do barvy pozadí a zpět (zatmívačka),
//    a aspect-fit transformace každého klipu na plátno — bez video kompozice
//    škáluje obraz `AVPlayerLayer`, s ní to MUSÍ udělat instrukce,
//  - zvukový crossfade jsou volume rampy v mixu (`setVolumeRamp`).
//  ⚠️ Video kompozice vzniká JEN když na obrazové stopě opravdu leží
//  přechod — bez něj zůstává přehrávací cesta (a GPU baseline z fáze 1)
//  netknutá, stejný vzorec jako `SubtitleOverlay`.
//  <https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition>
//  <https://developer.apple.com/documentation/avfoundation/avmutablevideocompositionlayerinstruction/setopacityramp(fromstartopacity:toendopacity:timerange:)>
//  <https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters/setvolumeramp(fromstartvolume:toendvolume:timerange:)>
//

import AVFoundation
import Foundation
import TimelineModel

/// Kompozice + mapování zvukových stop (stopa kompozice → stopa osy),
/// ze kterého se staví `AVAudioMix`, + video kompozice s přechody.
struct BuiltTimeline {
    let composition: AVMutableComposition
    let audioTrackMap: [(compositionTrackID: CMPersistentTrackID, timelineTrackID: TrackID)]
    /// Jen když na obrazové stopě leží přechod, jinak `nil` — přehrávač
    /// pak jede po cestě ověřené ve fázích 3–5 a GPU baseline platí.
    let videoComposition: AVVideoComposition?
    /// Zvukové crossfady: rampy se přimíchávají do `audioMix(project:)`,
    /// aby přežily i živou změnu hlasitosti stopy.
    let audioFades: [AudioFade]

    struct AudioFade {
        let compositionTrackID: CMPersistentTrackID
        let range: CMTimeRange
        /// `true` = nástup 0 → hlasitost stopy, `false` = odchod → 0.
        let fadeIn: Bool
    }

    /// Mix z AKTUÁLNÍCH hlasitostí projektu. `nil`, když všechny stopy
    /// hrají naplno a žádný crossfade neexistuje — chování je pak
    /// k nerozeznání od doby před fází 7 a přehrávací cesta se nemění.
    func audioMix(project: Project) -> AVAudioMix? {
        var parameters: [AVMutableAudioMixInputParameters] = []
        var anyAdjusted = false
        for entry in audioTrackMap {
            guard let track = project.timeline.track(id: entry.timelineTrackID) else { continue }
            let volume = Float(project.effectiveVolume(of: track))
            if volume != 1.0 { anyAdjusted = true }
            let input = AVMutableAudioMixInputParameters()
            input.trackID = entry.compositionTrackID
            input.setVolume(volume, at: .zero)
            // Crossfady téhle stopy kompozice, v čase vzestupně — rampy se
            // zadávají do rostoucí časové osy parametrů.
            let fades = audioFades
                .filter { $0.compositionTrackID == entry.compositionTrackID }
                .sorted { $0.range.start < $1.range.start }
            for fade in fades {
                if fade.fadeIn {
                    input.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                                        timeRange: fade.range)
                } else {
                    input.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                                        timeRange: fade.range)
                    // Po odchodu zpátky na hlasitost stopy — na téže dráze
                    // můžou ležet další klipy a nulová hlasitost by jim zbyla.
                    input.setVolume(volume, at: fade.range.end)
                }
            }
            parameters.append(input)
        }
        guard anyAdjusted || !audioFades.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}

enum CompositionBuilder {

    /// Postaví kompozici z projektu. Vrací `nil`, když na ose není žádný
    /// klip — prázdnou kompozici nemá smysl dávat přehrávači.
    static func build(project: Project, usingProxies: Bool = false) async throws -> BuiltTimeline? {
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

        var audioTrackMap: [(CMPersistentTrackID, TrackID)] = []
        var audioFades: [BuiltTimeline.AudioFade] = []
        /// Obrazové skupiny pro instrukce video kompozice, v pořadí stop osy.
        var videoGroups: [VideoLaneGroup] = []
        /// Rozměr a otočení zdroje podle klipu — pro aspect-fit transformace.
        var clipGeometry: [ClipID: (size: CGSize, transform: CGAffineTransform)] = [:]
        /// Ken Burns fotek (fáze 12, modul 3) — vynucuje video kompozici.
        var kenBurnsByClip: [ClipID: KenBurns] = [:]

        for track in timeline.tracks {
            guard !track.clips.isEmpty,
                  let plan = project.compositionPlan(forTrack: track.id) else { continue }

            let mediaType: AVMediaType = track.kind == .video ? .video : .audio

            // Dráhy A/B: stopa bez prolínaček má jednu, přesně jako dřív.
            var laneTracks: [AVMutableCompositionTrack] = []
            for _ in 0..<plan.laneCount {
                guard let laneTrack = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                laneTracks.append(laneTrack)
                if track.kind == .audio {
                    audioTrackMap.append((laneTrack.trackID, track.id))
                }
            }
            guard laneTracks.count == plan.laneCount else { continue }

            for placement in plan.placements {
                guard let clip = track.clip(id: placement.clipID),
                      let source = project.asset(clip.assetID) else { continue }

                // Fotka (fáze 12): nemá video stopu, vkládá se JEDEN snímek
                // mezisouboru (`StillMovieStore` — plátno s vpáleným
                // aspect-fitem) roztažený přes délku klipu. Zdrojový výřez
                // z plánu je u fotky nulový a nepoužije se.
                if source.isStill {
                    guard track.kind == .video,
                          let movieURL = try? await StillMovieStore.shared.movieURL(
                              forPhoto: source.originalURL,
                              canvas: CGSize(width: timeline.canvasSize.width,
                                             height: timeline.canvasSize.height)),
                          let stillTrack = try await asset(for: movieURL)
                              .loadTracks(withMediaType: .video).first
                    else { continue }   // nečitelná fotka = mezera, ne pád

                    let at = CMTime(value: Int64(placement.start.count) * ticksPerFrame,
                                    timescale: SourceTime.projectTimescale)
                    let frameDuration = CMTime(value: ticksPerFrame,
                                               timescale: SourceTime.projectTimescale)
                    let laneTrack = laneTracks[placement.lane]
                    try laneTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: frameDuration),
                        of: stillTrack, at: at)
                    laneTrack.scaleTimeRange(
                        CMTimeRange(start: at, duration: frameDuration),
                        toDuration: CMTime(
                            value: Int64(placement.duration.count) * ticksPerFrame,
                            timescale: SourceTime.projectTimescale))
                    // Mezisoubor má rozměr plátna a žádné otočení — kdyby
                    // kvůli přechodům vznikla video kompozice, aspect-fit
                    // vyjde jako identita.
                    if clipGeometry[clip.id] == nil {
                        clipGeometry[clip.id] = (
                            CGSize(width: timeline.canvasSize.width,
                                   height: timeline.canvasSize.height), .identity)
                    }
                    if let kenBurns = clip.kenBurns, kenBurns.isUsable {
                        kenBurnsByClip[clip.id] = kenBurns
                    }
                    continue
                }

                let sourceAsset = asset(for: source.url(usingProxies: usingProxies))
                guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: mediaType).first
                else { continue }   // klip bez odpovídající stopy se přeskočí, nespadne

                // Výřez zdroje i pozici spočítal model (včetně ramen).
                let start = placement.sourceStart.converted(to: SourceTime.projectTimescale)
                let duration = placement.sourceDuration.converted(to: SourceTime.projectTimescale)
                let range = CMTimeRange(
                    start: CMTime(value: start.value, timescale: SourceTime.projectTimescale),
                    duration: CMTime(value: duration.value, timescale: SourceTime.projectTimescale))

                let at = CMTime(value: Int64(placement.start.count) * ticksPerFrame,
                                timescale: SourceTime.projectTimescale)
                let laneTrack = laneTracks[placement.lane]
                try laneTrack.insertTimeRange(range, of: sourceTrack, at: at)

                if track.kind == .video, clipGeometry[clip.id] == nil {
                    let (naturalSize, preferred) = try await sourceTrack
                        .load(.naturalSize, .preferredTransform)
                    clipGeometry[clip.id] = (naturalSize, preferred)
                }

                // Rychlostní křivka: vložený rozsah (zatím 1:1) se přeškáluje
                // po úsecích plánu. Pozpátku — škálování posouvá jen obsah za
                // úsekem, takže pozice dřívějších úseků zůstávají platné.
                // Po posledním škálování zabírá klip přesně svůj slot na ose.
                if placement.hasRamp, let ramp = project.rampPlaybackPlan(of: clip) {
                    for segment in ramp.segments.reversed() {
                        guard segment.sourceDurationTicks > 0, segment.outputTicks > 0 else { continue }
                        let segmentRange = CMTimeRange(
                            start: CMTime(value: at.value + segment.sourceStartTicks,
                                          timescale: SourceTime.projectTimescale),
                            duration: CMTime(value: segment.sourceDurationTicks,
                                             timescale: SourceTime.projectTimescale))
                        laneTrack.scaleTimeRange(
                            segmentRange,
                            toDuration: CMTime(value: segment.outputTicks,
                                               timescale: SourceTime.projectTimescale))
                    }
                }
            }

            if track.kind == .video {
                videoGroups.append(VideoLaneGroup(laneTracks: laneTracks, plan: plan))
            } else {
                // Zvukový crossfade = dvě volume rampy přes oblast překryvu.
                for overlay in plan.overlays where overlay.kind.needsSourceOverlap {
                    let range = CMTimeRange(
                        start: time(of: overlay.start, frameRate: timeline.frameRate),
                        end: time(of: overlay.end, frameRate: timeline.frameRate))
                    audioFades.append(.init(
                        compositionTrackID: laneTracks[overlay.outgoingLane].trackID,
                        range: range, fadeIn: false))
                    audioFades.append(.init(
                        compositionTrackID: laneTracks[overlay.incomingLane].trackID,
                        range: range, fadeIn: true))
                }
            }
        }

        // Video kompozice JEN když je na obrazu co skládat (přechod, nebo
        // Ken Burns fotky) — jinak zůstává přímá cesta a GPU baseline
        // z fáze 1. S Ken Burns je skok na skládání přes GPU stejná třída
        // jako u přechodů (změřeno ve fázi 10: medián ~12 %).
        let needsVideoComposition = videoGroups.contains { !$0.plan.overlays.isEmpty }
            || !kenBurnsByClip.isEmpty
        let videoComposition: AVVideoComposition? = needsVideoComposition
            ? makeVideoComposition(groups: videoGroups,
                                   clipGeometry: clipGeometry,
                                   kenBurnsByClip: kenBurnsByClip,
                                   canvas: CGSize(width: timeline.canvasSize.width,
                                                  height: timeline.canvasSize.height),
                                   frameRate: timeline.frameRate,
                                   totalDuration: composition.duration)
            : nil

        return BuiltTimeline(composition: composition,
                             audioTrackMap: audioTrackMap,
                             videoComposition: videoComposition,
                             audioFades: audioFades)
    }

    // MARK: - Instrukce video kompozice (fáze 10)

    private struct VideoLaneGroup {
        let laneTracks: [AVMutableCompositionTrack]
        let plan: TrackCompositionPlan
    }

    /// Instrukce pokrývají celou délku beze spár: hranice jsou začátky
    /// a konce oblastí přechodů (u zatmívačky i střih — mění se tam směr
    /// rampy) a instrukce mezi nimi nesou jen aspect-fit transformace.
    private static func makeVideoComposition(
        groups: [VideoLaneGroup],
        clipGeometry: [ClipID: (size: CGSize, transform: CGAffineTransform)],
        kenBurnsByClip: [ClipID: KenBurns],
        canvas: CGSize,
        frameRate: Int,
        totalDuration: CMTime) -> AVVideoComposition? {

        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(frameRate)
        let durationTicks = CMTimeConvertScale(totalDuration,
                                               timescale: SourceTime.projectTimescale,
                                               method: .default).value
        guard durationTicks > 0 else { return nil }

        func ticks(_ frame: Frames) -> Int64 { Int64(frame.count) * ticksPerFrame }

        // Hranice instrukcí. Klipy s Ken Burns dostávají hranice na svých
        // okrajích — jejich úseky pak leží buď celé uvnitř klipu, nebo celé
        // mimo, a transform rampa se dá zadat po úsecích.
        var boundarySet: Set<Int64> = [0, durationTicks]
        for group in groups {
            for overlay in group.plan.overlays {
                boundarySet.insert(ticks(overlay.start))
                boundarySet.insert(ticks(overlay.end))
                if !overlay.kind.needsSourceOverlap {
                    boundarySet.insert(ticks(overlay.cut))
                }
            }
            for placement in group.plan.placements
            where kenBurnsByClip[placement.clipID] != nil {
                boundarySet.insert(ticks(placement.start))
                boundarySet.insert(ticks(placement.start) + Int64(placement.duration.count) * ticksPerFrame)
            }
        }
        let boundaries = boundarySet.filter { $0 >= 0 && $0 <= durationTicks }.sorted()

        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (t0, t1) in zip(boundaries, boundaries.dropFirst()) {
            let span = CMTimeRange(
                start: CMTime(value: t0, timescale: SourceTime.projectTimescale),
                end: CMTime(value: t1, timescale: SourceTime.projectTimescale))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = span

            var layers: [AVMutableVideoCompositionLayerInstruction] = []

            // Pozdější stopa osy překrývá dřívější → do instrukcí jde
            // POZDĚJŠÍ DŘÍV (pole vrstev je odpředu dozadu).
            for group in groups.reversed() {
                let overlay = group.plan.overlays.first {
                    ticks($0.start) <= t0 && t1 <= ticks($0.end)
                }

                // Vrstva dráhy s transformacemi klipů, které do úseku zasahují.
                func makeLayer(lane: Int) -> AVMutableVideoCompositionLayerInstruction {
                    let layer = AVMutableVideoCompositionLayerInstruction(
                        assetTrack: group.laneTracks[lane])
                    for placement in group.plan.placements where placement.lane == lane {
                        let pStart = ticks(placement.start)
                        let pEnd = pStart + Int64(placement.duration.count) * ticksPerFrame
                        guard pStart < t1, t0 < pEnd,
                              let geometry = clipGeometry[placement.clipID] else { continue }

                        // Ken Burns (fáze 12): lineární transform rampa mezi
                        // výřezy. Krajní hodnoty úseku se interpolují PO
                        // SLOŽKÁCH — přesně tak rampu interpoluje i sama
                        // kompozice, takže úseky na sebe navazují beze švů.
                        // <https://developer.apple.com/documentation/avfoundation/avmutablevideocompositionlayerinstruction/settransformramp(fromstart:toend:timerange:)>
                        if let kenBurns = kenBurnsByClip[placement.clipID], pEnd > pStart {
                            let from = cropTransform(kenBurns.start, canvas: canvas)
                            let to = cropTransform(kenBurns.end, canvas: canvas)
                            let f0 = Double(max(pStart, t0) - pStart) / Double(pEnd - pStart)
                            let f1 = Double(min(pEnd, t1) - pStart) / Double(pEnd - pStart)
                            layer.setTransformRamp(
                                fromStart: lerp(from, to, f0),
                                toEnd: lerp(from, to, f1),
                                timeRange: CMTimeRange(
                                    start: CMTime(value: max(pStart, t0),
                                                  timescale: SourceTime.projectTimescale),
                                    end: CMTime(value: min(pEnd, t1),
                                                timescale: SourceTime.projectTimescale)))
                            continue
                        }

                        layer.setTransform(
                            aspectFit(size: geometry.size, preferred: geometry.transform,
                                      into: canvas),
                            at: CMTime(value: max(pStart, t0),
                                       timescale: SourceTime.projectTimescale))
                    }
                    return layer
                }

                guard let overlay else {
                    // Mimo přechody: všechny dráhy natvrdo — média se
                    // nepřekrývají, pořadí drah je jedno.
                    for lane in group.laneTracks.indices { layers.append(makeLayer(lane: lane)) }
                    continue
                }

                let spanFraction = { (t: Int64, from: Int64, to: Int64) -> Float in
                    to > from ? Float(t - from) / Float(to - from) : 1
                }

                if overlay.kind.needsSourceOverlap {
                    // Prolínačka: odcházející NAVRCHU stmívá 1 → 0, nastupující
                    // pod ním drží plnou — lineární směs přes celou oblast.
                    let start = ticks(overlay.start), end = ticks(overlay.end)
                    let outgoing = makeLayer(lane: overlay.outgoingLane)
                    outgoing.setOpacityRamp(
                        fromStartOpacity: 1 - spanFraction(t0, start, end),
                        toEndOpacity: 1 - spanFraction(t1, start, end),
                        timeRange: span)
                    layers.append(outgoing)
                    layers.append(makeLayer(lane: overlay.incomingLane))
                } else {
                    // Zatmívačka: před střihem klesá do barvy pozadí,
                    // za střihem z ní nastupuje. Obě půlky na téže dráze —
                    // před střihem tam leží odcházející klip, za ním nastupující.
                    let cut = ticks(overlay.cut)
                    let layer = makeLayer(lane: overlay.outgoingLane)
                    if t1 <= cut {
                        let start = ticks(overlay.start)
                        layer.setOpacityRamp(
                            fromStartOpacity: 1 - spanFraction(t0, start, cut),
                            toEndOpacity: 1 - spanFraction(t1, start, cut),
                            timeRange: span)
                    } else {
                        let end = ticks(overlay.end)
                        layer.setOpacityRamp(
                            fromStartOpacity: spanFraction(t0, cut, end),
                            toEndOpacity: spanFraction(t1, cut, end),
                            timeRange: span)
                    }
                    layers.append(layer)
                    for lane in group.laneTracks.indices
                    where lane != overlay.outgoingLane {
                        layers.append(makeLayer(lane: lane))
                    }
                    instruction.backgroundColor = overlay.kind == .dipToWhite
                        ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                        : CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                }
            }

            instruction.layerInstructions = layers
            instructions.append(instruction)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: CMTimeValue(ticksPerFrame),
                                                timescale: SourceTime.projectTimescale)
        videoComposition.instructions = instructions
        return videoComposition
    }

    /// Transformace Ken Burns: výřez plátna (normalizovaný, počátek vlevo
    /// nahoře — souřadnice video kompozice) roztažený přes celé plátno.
    /// Mezisoubor fotky má rozměr plátna, takže žádné napřímení netřeba.
    private static func cropTransform(_ rect: NormalizedRect,
                                      canvas: CGSize) -> CGAffineTransform {
        let cropWidth = rect.width * canvas.width
        let cropHeight = rect.height * canvas.height
        guard cropWidth > 0, cropHeight > 0 else { return .identity }
        // Fill, ne fit: výřez má obrazovku VYPLNIT. UI drží poměr plátna
        // (w == h v normalizovaných jednotkách), pak jsou obě měřítka stejná.
        let scale = max(canvas.width / cropWidth, canvas.height / cropHeight)
        let centerX = (rect.x + rect.width / 2) * canvas.width
        let centerY = (rect.y + rect.height / 2) * canvas.height
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: canvas.width / 2 - scale * centerX,
                                 ty: canvas.height / 2 - scale * centerY)
    }

    /// Interpolace transformace po složkách — táž definice, kterou používá
    /// `setTransformRamp` uvnitř úseku.
    private static func lerp(_ a: CGAffineTransform, _ b: CGAffineTransform,
                             _ f: Double) -> CGAffineTransform {
        let t = CGFloat(min(max(f, 0), 1))
        return CGAffineTransform(a: a.a + (b.a - a.a) * t,
                                 b: a.b + (b.b - a.b) * t,
                                 c: a.c + (b.c - a.c) * t,
                                 d: a.d + (b.d - a.d) * t,
                                 tx: a.tx + (b.tx - a.tx) * t,
                                 ty: a.ty + (b.ty - a.ty) * t)
    }

    /// Aspect-fit klipu na plátno: napřímení (`preferredTransform`),
    /// zmenšení a vycentrování. Stejný výsledek, jaký bez video kompozice
    /// dělá `AVPlayerLayer` s `resizeAspect` — s instrukcemi to musí spočítat
    /// kompozice, jinak by klip ležel v levém horním rohu plátna v 1:1.
    private static func aspectFit(size: CGSize, preferred: CGAffineTransform,
                                  into canvas: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: size).applying(preferred)
        let width = abs(rect.width), height = abs(rect.height)
        guard width > 0, height > 0 else { return preferred }
        let scale = min(canvas.width / width, canvas.height / height)
        return preferred
            .concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (canvas.width - width * scale) / 2,
                y: (canvas.height - height * scale) / 2))
    }

    // MARK: - Převody času

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
