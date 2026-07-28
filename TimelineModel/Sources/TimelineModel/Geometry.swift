//
//  Geometry.swift
//  TimelineModel — Projekt Krása
//
//  Veškerá matematika časové osy: kde na obrazovce leží snímek, které klipy
//  jsou vidět, na co se má tažení přichytit, co je pod myší.
//
//  Záměrně BEZ AppKitu. `TimelineView` pak jen kreslí a předává události —
//  a to je ta část, která se testovat nedá. Čím tenčí bude, tím líp.
//
//  ⚠️ ZÁSADNÍ PRAVIDLO CELÉHO SOUBORU
//  Šířka úchopu okraje klipu a tolerance přichytávání jsou pevné v PIXELECH
//  a na snímky se přepočítávají podle zoomu. Kdyby byly ve snímcích:
//    — po odzoomování by okraj klipu zabíral zlomek pixelu a nešel by chytit,
//    — po přiblížení by přichytávání skákalo přes půl obrazovky.
//  Uživatel má prstem pořád stejně velký, ať je zoom jakýkoli.
//

import Foundation

/// Popis rozvržení: kolik pixelů zabírá snímek a jak jsou vysoké stopy.
public struct TimelineGeometry: Hashable, Sendable {

    /// Kolik bodů na obrazovce zabírá jeden snímek. Zoom.
    public var pointsPerFrame: Double

    /// Výška obrazové stopy v bodech.
    public var videoTrackHeight: Double
    /// Výška zvukové stopy v bodech.
    public var audioTrackHeight: Double
    /// Výška titulkové stopy v bodech. Nejnižší — nese jen krátký text,
    /// vlna ani náhled na ní nikdy nebudou.
    public var titleTrackHeight: Double
    /// Mezera mezi stopami.
    public var trackSpacing: Double

    /// Jak široká je citlivá zóna na okraji klipu, v BODECH.
    public var edgeGrabWidth: Double
    /// Jak blízko musí být tažená hrana ke kandidátovi, aby se přichytila, v BODECH.
    public var snapTolerance: Double

    public init(pointsPerFrame: Double = 4,
                videoTrackHeight: Double = 64,
                audioTrackHeight: Double = 44,
                titleTrackHeight: Double = 28,
                trackSpacing: Double = 2,
                edgeGrabWidth: Double = 8,
                snapTolerance: Double = 10) {
        self.pointsPerFrame = pointsPerFrame
        self.videoTrackHeight = videoTrackHeight
        self.audioTrackHeight = audioTrackHeight
        self.titleTrackHeight = titleTrackHeight
        self.trackSpacing = trackSpacing
        self.edgeGrabWidth = edgeGrabWidth
        self.snapTolerance = snapTolerance
    }

    /// Rozumné meze zoomu. Pod dolní hranicí se klipy slijí do čáry,
    /// nad horní je jeden snímek přes celou obrazovku.
    public static let minPointsPerFrame: Double = 0.02
    public static let maxPointsPerFrame: Double = 120

    public mutating func setZoom(_ value: Double) {
        pointsPerFrame = Swift.min(Swift.max(value, Self.minPointsPerFrame), Self.maxPointsPerFrame)
    }

    // MARK: - Čas ↔ vodorovná souřadnice

    public func x(for frame: Frames) -> Double {
        Double(frame.count) * pointsPerFrame
    }

    /// Zaokrouhluje na NEJBLIŽŠÍ snímek, ne dolů. Uživatel míří doprostřed
    /// snímku, ne na jeho začátek — zaokrouhlení dolů by posouvalo všechno
    /// systematicky o půl snímku vlevo.
    public func frame(atX x: Double) -> Frames {
        guard pointsPerFrame > 0 else { return .zero }
        return Frames(Int((x / pointsPerFrame).rounded()))
    }

    /// Šířka klipu v bodech.
    public func width(of duration: Frames) -> Double {
        Double(duration.count) * pointsPerFrame
    }

    /// Přepočet vzdálenosti v bodech na snímky. Používá se pro tolerance —
    /// nikdy neukládej toleranci ve snímcích, viz hlavička souboru.
    public func frames(fromPoints points: Double) -> Frames {
        guard pointsPerFrame > 0 else { return .zero }
        return Frames(Int((points / pointsPerFrame).rounded()))
    }

    // MARK: - Svislé rozvržení

    public func height(of kind: TrackKind) -> Double {
        switch kind {
        case .video: return videoTrackHeight
        case .audio: return audioTrackHeight
        case .title: return titleTrackHeight
        }
    }

    /// Horní hrana stopy na daném indexu.
    public func y(ofTrackAt index: Int, in timeline: Timeline) -> Double {
        var offset = 0.0
        for i in 0..<Swift.min(index, timeline.tracks.count) {
            offset += height(of: timeline.tracks[i].kind) + trackSpacing
        }
        return offset
    }

    /// Celková výška všech stop.
    public func totalHeight(of timeline: Timeline) -> Double {
        guard !timeline.tracks.isEmpty else { return 0 }
        return timeline.tracks.reduce(0.0) { $0 + height(of: $1.kind) + trackSpacing } - trackSpacing
    }

    /// Na které stopě leží svislá souřadnice. `nil` = pod poslední stopou
    /// nebo v mezeře mezi nimi.
    public func trackIndex(atY y: Double, in timeline: Timeline) -> Int? {
        guard y >= 0 else { return nil }
        var offset = 0.0
        for (i, track) in timeline.tracks.enumerated() {
            let h = height(of: track.kind)
            if y < offset + h { return i }
            offset += h + trackSpacing
            if y < offset { return nil }        // mezera mezi stopami
        }
        return nil
    }

    // MARK: - Rozsah obsahu

    /// Šířka obsahu pro `NSScrollView`. Přidává rezervu, aby šlo scrollovat
    /// kousek za konec posledního klipu — jinak se na něj špatně napojuje.
    public func contentWidth(of project: Project, trailingFrames: Frames = Frames(300)) -> Double {
        width(of: project.duration + trailingFrames)
    }
}

// MARK: - Viditelný rozsah a recyklace

extension TimelineGeometry {

    /// Rozsah snímků viditelný v okně. Rozšířený o `overscan`, aby se klipy
    /// objevovaly už kousek před hranou a nenaskakovaly při scrollování.
    public func visibleFrameRange(scrollX: Double, width: Double,
                                  overscanPoints: Double = 200) -> Range<Frames> {
        let from = frame(atX: Swift.max(0, scrollX - overscanPoints))
        let to = frame(atX: scrollX + width + overscanPoints)
        return from ..< Frames(Swift.max(to.count, from.count + 1))
    }

    /// Klipy stopy protínající daný rozsah.
    ///
    /// Binárním půlením, ne průchodem celého pole. Při tisících klipů se
    /// tohle volá při každém scrollnutí, takže lineární průchod by se sčítal
    /// do sekání — a klipy jsou seřazené, takže není důvod ho dělat.
    public func visibleClips(on track: Track, in range: Range<Frames>) -> ArraySlice<Clip> {
        let clips = track.clips
        guard !clips.isEmpty else { return clips[clips.startIndex..<clips.startIndex] }

        // První klip, jehož KONEC je za začátkem rozsahu.
        var lo = 0, hi = clips.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if clips[mid].timelineEnd <= range.lowerBound { lo = mid + 1 } else { hi = mid }
        }
        let first = lo

        // První klip, jehož ZAČÁTEK je za koncem rozsahu.
        lo = first; hi = clips.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if clips[mid].timelineStart < range.upperBound { lo = mid + 1 } else { hi = mid }
        }
        let end = lo

        return clips[first..<end]
    }
}

// MARK: - Hit testing

/// Co je pod myší.
public struct TimelineHit: Hashable, Sendable {
    public enum Zone: Hashable, Sendable {
        /// Tělo klipu — tažení celého klipu.
        case body
        /// Levý okraj — trim začátku.
        case leadingEdge
        /// Pravý okraj — trim konce.
        case trailingEdge
    }

    public let clipID: ClipID
    public let trackID: TrackID
    public let zone: Zone
    /// Kolik snímků od začátku klipu se kliklo. Pro tažení, aby klip
    /// „neskočil" počátkem pod kurzor.
    public let offsetInClip: Frames
}

extension TimelineGeometry {

    /// Co leží na daném bodě.
    ///
    /// Okraje mají přednost před tělem — u úzkých klipů se okraje překrývají
    /// a uživatel skoro vždycky míří na okraj, když je blízko něj.
    public func hitTest(x: Double, y: Double, in timeline: Timeline) -> TimelineHit? {
        guard let ti = trackIndex(atY: y, in: timeline) else { return nil }
        let track = timeline.tracks[ti]
        let frame = self.frame(atX: x)

        for clip in track.clips {
            let startX = self.x(for: clip.timelineStart)
            let endX = self.x(for: clip.timelineEnd)
            guard x >= startX - edgeGrabWidth / 2, x <= endX + edgeGrabWidth / 2 else { continue }

            let offset = Frames(Swift.max(0, frame.count - clip.timelineStart.count))
            // U klipu užšího než dva úchopy se plocha rozdělí napůl, aby
            // zbyl aspoň nějaký způsob, jak chytit obě strany.
            let grab = Swift.min(edgeGrabWidth, (endX - startX) / 2)

            if x <= startX + grab {
                return TimelineHit(clipID: clip.id, trackID: track.id,
                                   zone: .leadingEdge, offsetInClip: offset)
            }
            if x >= endX - grab {
                return TimelineHit(clipID: clip.id, trackID: track.id,
                                   zone: .trailingEdge, offsetInClip: offset)
            }
            return TimelineHit(clipID: clip.id, trackID: track.id,
                               zone: .body, offsetInClip: offset)
        }
        return nil
    }
}

// MARK: - Přichytávání

/// Na co se dá přichytit. Model dostane až zaokrouhlený výsledek — sám
/// o přichytávání nic neví a vědět nemá.
public struct SnapCandidate: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable, Comparable {
        /// Nula osy. Nejsilnější — začátek filmu je tvrdý bod.
        case origin = 0
        /// Přehrávací hlava.
        case playhead = 1
        /// Hrana jiného klipu.
        case clipEdge = 2
        /// Marker, později i beat z hudby (fáze 6).
        case marker = 3

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public let frame: Frames
    public let kind: Kind

    public init(frame: Frames, kind: Kind) {
        self.frame = frame
        self.kind = kind
    }
}

extension TimelineGeometry {

    /// Sesbírá kandidáty na přichycení.
    ///
    /// - Parameters:
    ///   - excluding: klipy, které se právě táhnou — na vlastní hrany
    ///     se přichytávat nemá smysl a vyrobilo by to zaseknutí na místě.
    ///   - excludingTitles: totéž pro tažený titulek (fáze 11).
    public func snapCandidates(in timeline: Timeline,
                               playhead: Frames? = nil,
                               excluding: Set<ClipID> = [],
                               excludingTitles: Set<TitleClipID> = [],
                               onlyTracks: Set<TrackID>? = nil) -> [SnapCandidate] {
        var out: [SnapCandidate] = [SnapCandidate(frame: .zero, kind: .origin)]
        if let playhead { out.append(SnapCandidate(frame: playhead, kind: .playhead)) }

        for track in timeline.tracks {
            if let onlyTracks, !onlyTracks.contains(track.id) { continue }
            for clip in track.clips where !excluding.contains(clip.id) {
                out.append(SnapCandidate(frame: clip.timelineStart, kind: .clipEdge))
                out.append(SnapCandidate(frame: clip.timelineEnd, kind: .clipEdge))
            }
            // Hrany titulků přitahují stejně jako hrany klipů — titulek se
            // typicky zarovnává na střih a střih na titulek.
            for title in track.titles where !excludingTitles.contains(title.id) {
                out.append(SnapCandidate(frame: title.timelineStart, kind: .clipEdge))
                out.append(SnapCandidate(frame: title.timelineEnd, kind: .clipEdge))
            }
        }
        return out
    }

    /// Přichytí pozici k nejbližšímu kandidátovi v toleranci.
    ///
    /// Tolerance je v BODECH a přepočítává se zoomem — při odzoomování je
    /// tedy ve snímcích velká, při přiblížení malá. Přesně tak se to chová
    /// správně: uživatel míří okem na obrazovku, ne na snímky.
    ///
    /// Při shodné vzdálenosti vyhrává silnější druh (nula > playhead > hrana),
    /// aby výsledek nezávisel na pořadí v poli.
    public func snap(_ frame: Frames, to candidates: [SnapCandidate]) -> (frame: Frames, candidate: SnapCandidate?) {
        guard !candidates.isEmpty, snapTolerance > 0 else { return (frame, nil) }
        let tolerancePoints = snapTolerance

        var best: SnapCandidate?
        var bestDistance = Double.infinity

        for candidate in candidates {
            let distance = abs(x(for: candidate.frame) - x(for: frame))
            guard distance <= tolerancePoints else { continue }
            if distance < bestDistance || (distance == bestDistance && candidate.kind < (best?.kind ?? .marker)) {
                best = candidate
                bestDistance = distance
            }
        }
        return (best?.frame ?? frame, best)
    }

    /// Pohodlný obal: zaokrouhlí souřadnici na snímek a rovnou přichytí.
    public func snappedFrame(atX x: Double, candidates: [SnapCandidate]) -> Frames {
        snap(frame(atX: x), to: candidates).frame
    }
}
