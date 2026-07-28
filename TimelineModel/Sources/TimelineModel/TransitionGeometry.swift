//
//  TransitionGeometry.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 10, modul 3: matematika UI přechodů. Kde na obrazovce leží
//  lichoběžník přechodu, co je pod myší, který střih je poblíž kliknutí
//  (kontextové menu) a jak se tažení okraje přeloží na novou délku.
//
//  Platí zásadní pravidlo `Geometry.swift`: úchopy a tolerance jsou
//  v BODECH a přepočítávají se zoomem — ve snímcích by po odzoomování
//  nešly chytit a po přiblížení by skákaly přes půl obrazovky.
//

import Foundation

// MARK: - Rozvržení

/// Umístění lichoběžníku přechodu v souřadnicích dokumentu.
public struct TransitionPlacement: Hashable, Sendable {
    public let transitionID: TransitionID
    public let trackID: TrackID
    public let kind: TransitionKind
    /// Levá hrana oblasti.
    public let x: Double
    /// Šířka oblasti.
    public let width: Double
    /// Svislá čára střihu — bottom hrana lichoběžníku se k ní sbíhá.
    public let cutX: Double
    public let y: Double
    public let height: Double

    public init(transitionID: TransitionID, trackID: TrackID, kind: TransitionKind,
                x: Double, width: Double, cutX: Double, y: Double, height: Double) {
        self.transitionID = transitionID
        self.trackID = trackID
        self.kind = kind
        self.x = x
        self.width = width
        self.cutX = cutX
        self.y = y
        self.height = height
    }
}

extension TimelineLayout {

    /// Lichoběžníky přechodů viditelné v okně. Stejná smlouva jako
    /// `placements`: deterministické pořadí (stopy odshora, uvnitř zleva),
    /// souřadnice dokumentu. Přechodů jsou jednotky až desítky, takže se
    /// neřeší binární půlení — ale viditelnost se filtruje, aby vrstvy
    /// mimo okno vůbec nevznikaly.
    public static func transitionPlacements(project: Project,
                                            geometry: TimelineGeometry,
                                            scrollX: Double,
                                            width: Double,
                                            overscanPoints: Double = 200) -> [TransitionPlacement] {
        guard width > 0 else { return [] }
        let range = geometry.visibleFrameRange(scrollX: scrollX, width: width,
                                               overscanPoints: overscanPoints)
        let timeline = project.timeline

        var out: [TransitionPlacement] = []
        for (index, track) in timeline.tracks.enumerated() {
            guard !track.transitions.isEmpty else { continue }
            let y = geometry.y(ofTrackAt: index, in: timeline)
            let height = geometry.height(of: track.kind)

            for transition in track.transitions {
                guard let region = project.transitionRegion(of: transition.id),
                      region.start < range.upperBound, range.lowerBound < region.end
                else { continue }   // bez střihu (rozbité) nebo mimo okno
                let startX = geometry.x(for: region.start)
                out.append(TransitionPlacement(
                    transitionID: transition.id,
                    trackID: track.id,
                    kind: transition.kind,
                    x: startX,
                    width: geometry.x(for: region.end) - startX,
                    cutX: geometry.x(for: region.start + transition.framesBeforeCut),
                    y: y,
                    height: height))
            }
        }
        return out
    }
}

// MARK: - Hit testing

/// Přechod pod myší.
public struct TransitionHit: Hashable, Sendable {
    public enum Zone: Hashable, Sendable {
        /// Tělo lichoběžníku.
        case body
        /// Levý okraj oblasti — tažení délky.
        case leadingEdge
        /// Pravý okraj oblasti — tažení délky.
        case trailingEdge
    }

    public let transitionID: TransitionID
    public let trackID: TrackID
    public let zone: Zone

    public init(transitionID: TransitionID, trackID: TrackID, zone: Zone) {
        self.transitionID = transitionID
        self.trackID = trackID
        self.zone = zone
    }
}

/// Střih (dotyk dvou sousedů) poblíž kliknutí — cíl kontextového menu.
public struct CutHit: Hashable, Sendable {
    public let trackID: TrackID
    public let leftClipID: ClipID
    public let rightClipID: ClipID
    public let frame: Frames

    public init(trackID: TrackID, leftClipID: ClipID, rightClipID: ClipID, frame: Frames) {
        self.trackID = trackID
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.frame = frame
    }
}

extension TimelineGeometry {

    /// Přechod pod bodem. Volá se PŘED `hitTest` na klipy — lichoběžník
    /// leží nad klipy, takže má přednost; jinak by se pod ním trimovalo
    /// naslepo něco, co uživatel nevidí.
    public func transitionHitTest(x: Double, y: Double, in project: Project) -> TransitionHit? {
        guard let ti = trackIndex(atY: y, in: project.timeline) else { return nil }
        let track = project.timeline.tracks[ti]

        for transition in track.transitions {
            guard let region = project.transitionRegion(of: transition.id) else { continue }
            let startX = self.x(for: region.start)
            let endX = self.x(for: region.end)
            guard x >= startX - edgeGrabWidth / 2, x <= endX + edgeGrabWidth / 2 else { continue }

            // Stejný vzorec jako u klipů: u titěrné oblasti se plocha dělí
            // napůl, aby šly chytit obě strany.
            let grab = Swift.min(edgeGrabWidth, (endX - startX) / 2)
            let zone: TransitionHit.Zone
            if x <= startX + grab {
                zone = .leadingEdge
            } else if x >= endX - grab {
                zone = .trailingEdge
            } else {
                zone = .body
            }
            return TransitionHit(transitionID: transition.id, trackID: track.id, zone: zone)
        }
        return nil
    }

    /// Nejbližší střih (dotyk dvou sousedů) do tolerance od bodu.
    ///
    /// Tolerance je volnější než úchop okraje klipu — na kontextové menu
    /// se neklika s pixelovou přesností. Výchozí = 2× `edgeGrabWidth`.
    public func cutHit(x: Double, y: Double, in project: Project,
                       tolerancePoints: Double? = nil) -> CutHit? {
        guard let ti = trackIndex(atY: y, in: project.timeline) else { return nil }
        let track = project.timeline.tracks[ti]
        let tolerance = tolerancePoints ?? edgeGrabWidth * 2

        var best: CutHit?
        var bestDistance = Double.infinity
        for (left, right) in zip(track.clips, track.clips.dropFirst()) {
            guard left.timelineEnd == right.timelineStart else { continue }
            let distance = abs(self.x(for: left.timelineEnd) - x)
            guard distance <= tolerance, distance < bestDistance else { continue }
            best = CutHit(trackID: track.id, leftClipID: left.id,
                          rightClipID: right.id, frame: left.timelineEnd)
            bestDistance = distance
        }
        return best
    }
}

// MARK: - Tažení délky

extension Project {

    /// Nová délka přechodu při tažení okraje na snímek `edgeFrame`.
    ///
    /// Délka se drží SYMETRICKY kolem střihu (2× vzdálenost okraje od
    /// střihu) — tažení jednoho okraje roztahuje oblast na obě strany,
    /// stejně jako to dělá FCPX s vycentrovaným přechodem. Výsledek je
    /// zaražený o `maxTransitionDuration` (zdroje, sousední přechody,
    /// klipy) a zdola o 2 snímky — snímek na každou stranu střihu.
    ///
    /// `nil`, když přechod nebo jeho střih už neexistuje.
    public func transitionDraggedDuration(id: TransitionID, edgeFrame: Frames) -> Frames? {
        guard let transition = transition(id: id),
              let region = transitionRegion(of: id) else { return nil }
        let cut = region.start + transition.framesBeforeCut
        let distance = abs(edgeFrame.count - cut.count)
        let maxDuration = maxTransitionDuration(kind: transition.kind,
                                                betweenLeft: transition.leftClipID,
                                                andRight: transition.rightClipID)
        guard maxDuration.count >= 1 else { return nil }
        return Frames(Swift.max(Swift.min(2 * distance, maxDuration.count),
                                Swift.min(2, maxDuration.count)))
    }
}
