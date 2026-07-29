//
//  Interaction.swift
//  TimelineModel — Projekt Krása
//
//  Co se stane při tažení. Stavový automat mezi `mouseDown`, `mouseDragged`
//  a `mouseUp` — ale bez AppKitu, takže se dá otestovat.
//
//  Rozdělení odpovědnosti:
//    view          — dostane událost, předá souřadnice, nakreslí náhled
//    interakce     — spočítá, kam by klip šel a jestli to jde (tenhle soubor)
//    model         — provede výslednou operaci a ohlídá invarianty
//
//  ⚠️ Během tažení se do modelu NEZAPISUJE. Každý mezistav při přetahování
//  přes souseda by byl překryv, tedy chyba, a to šedesátkrát za sekundu.
//  Model se dozví až výsledek, přes `commit(into:)`.
//

import Foundation

/// Druh tažení, určený tím, co bylo pod myší při stisku.
public enum DragKind: Hashable, Sendable {
    /// Tažení celého klipu, i na jinou stopu.
    case move
    /// Trim začátku.
    case trimStart
    /// Trim konce.
    case trimEnd
    /// Posun hranice mezi dvěma sousedy.
    case roll
    /// Posun zdrojového výřezu beze změny pozice a délky.
    case slip
}

/// Co má view nakreslit, dokud se drží tlačítko.
public struct DragPreview: Hashable, Sendable {
    public let clipID: ClipID
    public let trackID: TrackID
    public let start: Frames
    public let duration: Frames
    /// `false` = cíl je neplatný, view má kreslit jinou barvou.
    public let isValid: Bool
    /// Na co se přichytilo. View podle toho kreslí vodicí čáru.
    public let snappedTo: SnapCandidate?
    /// Druhý klip u rollu — ten se hýbe taky.
    public let partner: (clipID: ClipID, start: Frames, duration: Frames)?

    public static func == (a: DragPreview, b: DragPreview) -> Bool {
        a.clipID == b.clipID && a.trackID == b.trackID && a.start == b.start
            && a.duration == b.duration && a.isValid == b.isValid && a.snappedTo == b.snappedTo
            && a.partner?.clipID == b.partner?.clipID && a.partner?.start == b.partner?.start
            && a.partner?.duration == b.partner?.duration
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(clipID); hasher.combine(start); hasher.combine(duration)
    }
}

/// Stav probíhajícího tažení. Vytvoří se při stisku, zahodí při puštění.
public struct TimelineDrag: Sendable {
    public let kind: DragKind
    public let clipID: ClipID
    /// Stopa, ze které se táhne.
    public let originTrackID: TrackID
    /// Kolik snímků od začátku klipu se chytlo. Bez toho by klip při tažení
    /// skočil počátkem pod kurzor.
    public let grabOffset: Frames
    /// Pozice a délka při stisku — pro `cancel` a pro výpočet rozdílu.
    public let originalStart: Frames
    public let originalDuration: Frames
    /// Soused u rollu.
    public let partnerID: ClipID?

    /// Kandidáti na přichycení, spočítaní jednou na začátku tažení.
    /// Přepočítávat je při každém pohybu myši by bylo zbytečné — timeline
    /// se během tažení nemění.
    public let candidates: [SnapCandidate]
}

// MARK: - Řízení tažení

public struct TimelineInteraction: Sendable {

    public var geometry: TimelineGeometry
    /// Aktuální tažení, nebo `nil`.
    public private(set) var drag: TimelineDrag?

    public init(geometry: TimelineGeometry) {
        self.geometry = geometry
    }

    public var isDragging: Bool { drag != nil }

    // MARK: Začátek

    /// Začne tažení podle toho, co je pod myší.
    ///
    /// - Parameters:
    ///   - hit: výsledek `geometry.hitTest`
    ///   - modifiers: `slip` vynutí posun zdrojového výřezu, `roll` posun hranice
    ///   - playhead: přidá se mezi kandidáty na přichycení
    public mutating func begin(hit: TimelineHit,
                               in project: Project,
                               forcing forced: DragKind? = nil,
                               playhead: Frames? = nil) {
        guard let clip = project.timeline.clip(hit.clipID) else { return }

        var kind: DragKind
        switch hit.zone {
        case .body: kind = .move
        case .leadingEdge: kind = .trimStart
        case .trailingEdge: kind = .trimEnd
        }
        if let forced { kind = forced }

        // U rollu potřebujeme souseda na správné straně.
        var partner: ClipID?
        if kind == .roll, let at = project.timeline.locate(hit.clipID) {
            let clips = project.timeline.tracks[at.trackIndex].clips
            let neighbourIndex = hit.zone == .leadingEdge ? at.clipIndex - 1 : at.clipIndex + 1
            if clips.indices.contains(neighbourIndex) {
                let neighbour = clips[neighbourIndex]
                let touching = hit.zone == .leadingEdge
                    ? neighbour.timelineEnd == clip.timelineStart
                    : clip.timelineEnd == neighbour.timelineStart
                if touching { partner = neighbour.id }
            }
            // Bez souseda nemá roll co posouvat — spadne zpátky na trim.
            if partner == nil { kind = hit.zone == .leadingEdge ? .trimStart : .trimEnd }
        }

        // Na vlastní hrany se přichytávat nemá smysl; u rollu ani na hrany souseda.
        var excluded: Set<ClipID> = [hit.clipID]
        if let partner { excluded.insert(partner) }

        drag = TimelineDrag(kind: kind,
                            clipID: hit.clipID,
                            originTrackID: hit.trackID,
                            grabOffset: hit.offsetInClip,
                            originalStart: clip.timelineStart,
                            originalDuration: clip.duration,
                            partnerID: partner,
                            candidates: geometry.snapCandidates(in: project.timeline,
                                                                playhead: playhead,
                                                                excluding: excluded,
                                                                beats: project.beatMarks().map(\.frame)))
    }

    // MARK: Průběh

    /// Kam by to šlo, kdyby uživatel teď pustil.
    ///
    /// - Parameter snapping: `false` (typicky s podrženým Shiftem) přichytávání vypne.
    public func preview(atX x: Double, y: Double,
                        in project: Project,
                        snapping: Bool = true) -> DragPreview? {
        guard let drag, let clip = project.timeline.clip(drag.clipID) else { return nil }

        let rawFrame = geometry.frame(atX: x)
        let snapResult = snapping ? geometry.snap(rawFrame, to: drag.candidates) : (frame: rawFrame, candidate: nil)

        switch drag.kind {
        case .move:
            return movePreview(drag: drag, clip: clip, pointer: rawFrame, y: y,
                               snapping: snapping, in: project)
        case .trimStart:
            return trimStartPreview(drag: drag, clip: clip, to: snapResult.frame,
                                    snapped: snapResult.candidate, in: project)
        case .trimEnd:
            return trimEndPreview(drag: drag, clip: clip, to: snapResult.frame,
                                  snapped: snapResult.candidate, in: project)
        case .roll:
            return rollPreview(drag: drag, clip: clip, to: snapResult.frame,
                               snapped: snapResult.candidate, in: project)
        case .slip:
            return slipPreview(drag: drag, clip: clip, pointer: rawFrame, in: project)
        }
    }

    private func movePreview(drag: TimelineDrag, clip: Clip, pointer: Frames, y: Double,
                             snapping: Bool, in project: Project) -> DragPreview {
        // Klip drží tam, kde se chytil — nesmí skočit počátkem pod kurzor.
        var start = pointer - drag.grabOffset
        var snapped: SnapCandidate?

        if snapping {
            // Přichytává se ZAČÁTEK i KONEC klipu, ne jen ten bod, kde myš drží.
            let byStart = geometry.snap(start, to: drag.candidates)
            let byEnd = geometry.snap(start + clip.duration, to: drag.candidates)
            let dStart = byStart.candidate.map { abs(geometry.x(for: $0.frame) - geometry.x(for: start)) } ?? .infinity
            let dEnd = byEnd.candidate.map { abs(geometry.x(for: $0.frame) - geometry.x(for: start + clip.duration)) } ?? .infinity
            if dStart <= dEnd, let c = byStart.candidate {
                start = c.frame; snapped = c
            } else if let c = byEnd.candidate {
                start = c.frame - clip.duration; snapped = c
            }
        }
        if start.count < 0 { start = .zero }

        let targetTrackIndex = geometry.trackIndex(atY: y, in: project.timeline)
        let targetTrack = targetTrackIndex.map { project.timeline.tracks[$0] }
            ?? project.timeline.track(id: drag.originTrackID)!

        let valid = isPlacementValid(clipID: drag.clipID, start: start,
                                     duration: clip.duration, on: targetTrack, in: project)

        return DragPreview(clipID: drag.clipID, trackID: targetTrack.id,
                           start: start, duration: clip.duration,
                           isValid: valid, snappedTo: snapped, partner: nil)
    }

    private func trimStartPreview(drag: TimelineDrag, clip: Clip, to frame: Frames,
                                  snapped: SnapCandidate?, in project: Project) -> DragPreview {
        let lowest = project.maxTrimStart(clipID: drag.clipID) ?? .zero
        let highest = clip.timelineEnd - Frames(1)
        let start = Frames(Swift.min(Swift.max(frame.count, lowest.count), highest.count))
        return DragPreview(clipID: drag.clipID, trackID: drag.originTrackID,
                           start: start, duration: clip.timelineEnd - start,
                           isValid: true,           // meze jsou už zaříznuté
                           snappedTo: snapped, partner: nil)
    }

    private func trimEndPreview(drag: TimelineDrag, clip: Clip, to frame: Frames,
                                snapped: SnapCandidate?, in project: Project) -> DragPreview {
        let highest = project.maxTrimEnd(clipID: drag.clipID) ?? clip.timelineEnd
        let lowest = clip.timelineStart + Frames(1)
        let end = Frames(Swift.min(Swift.max(frame.count, lowest.count), highest.count))
        return DragPreview(clipID: drag.clipID, trackID: drag.originTrackID,
                           start: clip.timelineStart, duration: end - clip.timelineStart,
                           isValid: true,
                           snappedTo: snapped, partner: nil)
    }

    private func rollPreview(drag: TimelineDrag, clip: Clip, to frame: Frames,
                             snapped: SnapCandidate?, in project: Project) -> DragPreview? {
        guard let partnerID = drag.partnerID,
              let partner = project.timeline.clip(partnerID) else { return nil }

        let leftIsClip = clip.timelineEnd == partner.timelineStart
        let left = leftIsClip ? clip : partner
        let right = leftIsClip ? partner : clip

        // Meze: kolik zdroje má levý za koncem a pravý před začátkem.
        let maxRight = left.timelineEnd + project.remainingSourceFrames(after: left)
        let maxLeft = left.timelineEnd - project.availableSourceFramesBefore(right)
        let hardMin = left.timelineStart + Frames(1)
        let hardMax = right.timelineEnd - Frames(1)

        var boundary = frame
        boundary = Frames(Swift.max(boundary.count, Swift.max(maxLeft.count, hardMin.count)))
        boundary = Frames(Swift.min(boundary.count, Swift.min(maxRight.count, hardMax.count)))

        let newLeft = (left.id, left.timelineStart, boundary - left.timelineStart)
        let newRight = (right.id, boundary, right.timelineEnd - boundary)
        let primary = clip.id == left.id ? newLeft : newRight
        let other = clip.id == left.id ? newRight : newLeft

        return DragPreview(clipID: primary.0, trackID: drag.originTrackID,
                           start: primary.1, duration: primary.2,
                           isValid: true, snappedTo: snapped,
                           partner: (clipID: other.0, start: other.1, duration: other.2))
    }

    private func slipPreview(drag: TimelineDrag, clip: Clip, pointer: Frames,
                             in project: Project) -> DragPreview {
        // Slip nemění pozici ani délku — náhled je stejný, mění se jen obsah.
        // Rozsah se stejně ohlídá při commitu; tady jen držíme původní tvar.
        DragPreview(clipID: drag.clipID, trackID: drag.originTrackID,
                    start: clip.timelineStart, duration: clip.duration,
                    isValid: true, snappedTo: nil, partner: nil)
    }

    /// Vejde se klip na stopu, když se ignoruje sám sebe?
    private func isPlacementValid(clipID: ClipID, start: Frames, duration: Frames,
                                  on track: Track, in project: Project) -> Bool {
        guard start.count >= 0, duration.count > 0 else { return false }

        // Druh stopy musí sedět.
        if let clip = project.timeline.clip(clipID), let asset = project.asset(clip.assetID) {
            let ok = (track.kind == .video) ? asset.hasVideo : asset.hasAudio
            if !ok { return false }
        }

        let end = start + duration
        for other in track.clips where other.id != clipID {
            if start < other.timelineEnd && other.timelineStart < end { return false }
        }
        return true
    }

    // MARK: Konec

    /// Provede tažení na modelu. Vrací `false`, když nebylo co dělat.
    ///
    /// Volající si má kolem toho zapsat undo krok — u `move` jedním
    /// `record()` před voláním, u trimu a rollu přes `beginInteraction`
    /// a `endInteraction`, protože tam jsou mezistavy legální.
    @discardableResult
    public mutating func commit(atX x: Double, y: Double,
                                into project: inout Project,
                                snapping: Bool = true) throws -> Bool {
        guard let drag, let preview = preview(atX: x, y: y, in: project, snapping: snapping) else {
            return false
        }
        defer { self.drag = nil }

        switch drag.kind {
        case .move:
            guard preview.isValid else { return false }
            let unchanged = preview.start == drag.originalStart
                && preview.trackID == drag.originTrackID
            if unchanged { return false }
            try project.move(clipID: drag.clipID, toTrack: preview.trackID, start: preview.start)

        case .trimStart:
            guard preview.start != drag.originalStart else { return false }
            try project.trimStart(clipID: drag.clipID, to: preview.start)

        case .trimEnd:
            let newEnd = preview.start + preview.duration
            guard newEnd != drag.originalStart + drag.originalDuration else { return false }
            try project.trimEnd(clipID: drag.clipID, to: newEnd)

        case .roll:
            guard let partnerID = drag.partnerID,
                  let partner = project.timeline.clip(partnerID),
                  let clip = project.timeline.clip(drag.clipID) else { return false }
            let leftIsClip = clip.timelineEnd == partner.timelineStart
            let leftID = leftIsClip ? drag.clipID : partnerID
            let rightID = leftIsClip ? partnerID : drag.clipID
            let boundary = leftIsClip ? preview.start + preview.duration : preview.start
            guard boundary != clip.timelineEnd || !leftIsClip else { return false }
            try project.rollEdit(leftID: leftID, rightID: rightID, to: boundary)

        case .slip:
            let delta = geometry.frame(atX: x) - drag.originalStart - drag.grabOffset
            guard delta.count != 0 else { return false }
            let range = project.slipRange(clipID: drag.clipID) ?? (Frames.zero ... Frames.zero)
            let clamped = Frames(Swift.min(Swift.max(delta.count, range.lowerBound.count),
                                           range.upperBound.count))
            guard clamped.count != 0 else { return false }
            try project.slip(clipID: drag.clipID, by: clamped)
        }
        return true
    }

    /// Zrušené tažení (Escape). Model se nesahal, takže stačí zapomenout stav.
    public mutating func cancel() {
        drag = nil
    }
}
