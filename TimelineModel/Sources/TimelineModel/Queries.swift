//
//  Queries.swift
//  TimelineModel — Projekt Krása
//
//  Tažení potřebuje vědět, KAM SMÍ, ne se dozvědět po překročení, že nesmělo.
//  Bez těchhle funkcí si meze dopočítá AppKit view samo — a od té chvíle jsou
//  v projektu dvě implementace týchž pravidel, které se dřív nebo později
//  rozejdou.
//

import Foundation

extension Project {

    /// Meze, ve kterých smí klip na dané stopě začínat, aniž by narazil
    /// do souseda. Vrací `nil`, když se na stopu nevejde vůbec.
    public func legalRange(movingClip clipID: ClipID, toTrack trackID: TrackID) -> ClosedRange<Frames>? {
        guard let clip = timeline.clip(clipID),
              let track = timeline.track(id: trackID) else { return nil }

        let others = track.clips.filter { $0.id != clipID }
        guard !others.isEmpty else { return Frames.zero ... Frames(Int.max / 2) }

        // Kde přesně klip je, tam smí zůstat; jinak hledáme mezery.
        var gaps: [ClosedRange<Frames>] = []
        var cursor = Frames.zero
        for other in others {
            let gap = other.timelineStart - cursor
            if gap >= clip.duration {
                gaps.append(cursor ... (other.timelineStart - clip.duration))
            }
            cursor = max(cursor, other.timelineEnd)
        }
        gaps.append(cursor ... Frames(Int.max / 2))

        // Vrátí mezeru nejbližší současné pozici klipu.
        return gaps.min { a, b in
            distance(from: clip.timelineStart, to: a) < distance(from: clip.timelineStart, to: b)
        }
    }

    private func distance(from f: Frames, to range: ClosedRange<Frames>) -> Int {
        if range.contains(f) { return 0 }
        return f < range.lowerBound ? (range.lowerBound - f).count : (f - range.upperBound).count
    }

    /// Nejmenší pozice, na kterou lze táhnout začátek klipu.
    /// Omezuje ho zdrojový materiál před ním i případný soused.
    public func maxTrimStart(clipID: ClipID) -> Frames? {
        guard let at = timeline.locate(clipID) else { return nil }
        let track = timeline.tracks[at.trackIndex]
        let clip = track.clips[at.clipIndex]

        let bySource = clip.timelineStart - availableSourceFramesBefore(clip)
        let byNeighbour = at.clipIndex > 0 ? track.clips[at.clipIndex - 1].timelineEnd : Frames.zero
        return Frames(max(0, max(bySource.count, byNeighbour.count)))
    }

    /// Největší pozice, na kterou lze táhnout konec klipu.
    public func maxTrimEnd(clipID: ClipID) -> Frames? {
        guard let at = timeline.locate(clipID) else { return nil }
        let track = timeline.tracks[at.trackIndex]
        let clip = track.clips[at.clipIndex]

        let bySource = clip.timelineEnd + remainingSourceFrames(after: clip)
        let byNeighbour = at.clipIndex + 1 < track.clips.count
            ? track.clips[at.clipIndex + 1].timelineStart
            : Frames(Int.max / 2)
        return min(bySource, byNeighbour)
    }

    /// Ramena přechodů, která musí zůstat UVNITŘ klipu (fáze 16):
    /// `leading` je část oblasti za střihem na LEVÉ hraně klipu,
    /// `trailing` část před střihem na PRAVÉ hraně.
    ///
    /// **Z toho UI dělá zarážku trimu.** Bez ní tažení dojede až na
    /// mez zdroje, operace ho odmítne `blockedByTransition` a uživatel
    /// vidí jen to, že se nic nestalo (koukanec F10). Zarážka je
    /// poctivější než zčervenání: ruka se opře o zeď a klip se doveze
    /// přesně tam, kam smí.
    ///
    /// Trim, který střih ZRUŠÍ (odtažení od souseda → mezera), rameno
    /// neomezuje — tam přechod legálně umírá s ním (pravidlo ① fáze 10).
    public func transitionArms(clipID: ClipID) -> (leading: Frames, trailing: Frames) {
        guard let at = timeline.locate(clipID) else { return (.zero, .zero) }
        let track = timeline.tracks[at.trackIndex]
        var leading = Frames.zero
        var trailing = Frames.zero
        for transition in track.transitions {
            if transition.rightClipID == clipID {
                leading = max(leading, transition.framesAfterCut)
            }
            if transition.leftClipID == clipID {
                trailing = max(trailing, transition.framesBeforeCut)
            }
        }
        return (leading, trailing)
    }

    /// O kolik snímků lze posunout zdrojový výřez klipu.
    public func slipRange(clipID: ClipID) -> ClosedRange<Frames>? {
        guard let clip = timeline.clip(clipID) else { return nil }
        let back = availableSourceFramesBefore(clip)
        let forward = remainingSourceFrames(after: clip)
        return Frames(-back.count) ... forward
    }

    /// Klipy svázané s tímhle (bez něj samotného).
    public func linkedPartners(of clipID: ClipID) -> [Clip] {
        guard let clip = timeline.clip(clipID), let link = clip.linkID else { return [] }
        return timeline.tracks.flatMap(\.clips).filter { $0.linkID == link && $0.id != clipID }
    }

    /// Celková délka projektu — konec nejpozdějšího klipu NEBO titulku.
    /// Titulky se počítají schválně: závěrečné poděkování smí ležet za
    /// posledním záběrem (přes černou) a film končí až s ním.
    public var duration: Frames {
        let clipEnd = timeline.tracks.flatMap(\.clips).map(\.timelineEnd).max() ?? .zero
        let titleEnd = timeline.tracks.flatMap(\.titles).map(\.timelineEnd).max() ?? .zero
        return max(clipEnd, titleEnd)
    }
}
