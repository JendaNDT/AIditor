//
//  Operations.swift
//  TimelineModel — Projekt Krása
//
//  Volné pozice: mezery jsou legální a samy se nezavírají. Ripple je zvláštní
//  operace, o kterou si uživatel řekne.
//
//  ⚠️ KAŽDÁ operace pracuje na kopii a přiřadí ji až na konci. Tím je zdarma
//  splněné pravidlo, že chyba nechá projekt nezměněný — žádná polovičatá
//  mutace, ze které se nedá vycouvat.
//
//  ⚠️ POŘADÍ KONTROL je pevné: nejdřív zdrojový materiál, pak sousedi.
//  UI podle vrácené chyby zaráží tažení a nedeterministické pořadí by
//  znamenalo, že se tažení zarazí pokaždé jinde.
//

import Foundation

public enum TimelineError: Error, Hashable, Sendable {
    case clipNotFound(ClipID)
    case trackNotFound(TrackID)
    case assetNotFound(AssetID)
    /// Nese i mez, na které se má tažení zarazit.
    case wouldOverlap(with: ClipID, nearestLegal: Frames)
    case negativePosition
    case zeroLength
    case exceedsSourceMaterial(availableFrames: Frames)
    case splitOutsideClip
    case notAdjacent(ClipID, ClipID)
    case wrongTrackKind(expected: TrackKind, got: TrackKind)
    case assetStillInUse(AssetID)
    case notJoinable(reason: String)
    /// Rychlostní křivka s neplatnými uzly (nerostoucí časy, nulová rychlost).
    case invalidSpeedRamp
    /// Úsek přepisu s koncem před začátkem (fáze 8).
    case invalidTranscriptSegment
    /// Přechod je delší, než střih unese — nese největší legální délku,
    /// na které UI zarazí tažení (vzorec `wouldOverlap.nearestLegal`).
    case transitionTooLong(maxDuration: Frames)
    case transitionNotFound(TransitionID)
    /// Přechod na rampovaném střihu je v první verzi zakázaný (plán fáze 10).
    case transitionOnRampedCut
    /// Operaci brání přechod na dotčeném střihu — napřed ho zkrať nebo smaž.
    /// Hází se místo tichého zkracování: střih žije, přechod by se rozbil.
    case blockedByTransition(TransitionID)
    case titleNotFound(TitleClipID)
    /// Titulek by se překryl s jiným — nese mez, na které UI zarazí tažení
    /// (vzorec `wouldOverlap.nearestLegal`).
    case titleWouldOverlap(with: TitleClipID, nearestLegal: Frames)
}

// MARK: - Assety

extension Project {

    public mutating func addAsset(_ asset: Asset) {
        if let i = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[i] = asset
        } else {
            assets.append(asset)
        }
    }

    public mutating func removeAsset(id: AssetID) throws {
        let used = timeline.tracks.contains { $0.clips.contains { $0.assetID == id } }
        guard !used else { throw TimelineError.assetStillInUse(id) }
        assets.removeAll { $0.id == id }
    }

    public mutating func relink(assetID: AssetID, to url: URL) throws {
        guard let i = assets.firstIndex(where: { $0.id == assetID }) else {
            throw TimelineError.assetNotFound(assetID)
        }
        assets[i].originalURL = url
        assets[i].isOffline = false
    }

    // MARK: Vytváření klipů

    /// Vyrobí klip přes celou délku assetu.
    ///
    /// **Model razí `ClipID` i výchozí délku, ne UI.** Kdyby si UI razilo ID
    /// samo, je invariant „ClipID je jedinečné" nevymahatelný — kopie
    /// struktury si ID vezme s sebou a duplikace přes kopírovat/vložit je
    /// nejběžnější operace vůbec.
    public func makeClip(assetID: AssetID, at start: Frames = .zero) throws -> Clip {
        guard let asset = asset(assetID) else { throw TimelineError.assetNotFound(assetID) }
        let full = timeline.availableFrames(from: asset.duration)
        guard full.count > 0 else { throw TimelineError.zeroLength }
        return Clip(assetID: assetID,
                    timelineStart: start,
                    duration: full,
                    sourceStart: .zero)
    }

    /// Dvojice obraz + zvuk se sdílenou vazbou.
    public func makeLinkedClips(assetID: AssetID, at start: Frames = .zero) throws -> (video: Clip, audio: Clip) {
        guard let asset = asset(assetID) else { throw TimelineError.assetNotFound(assetID) }
        guard asset.hasVideo, asset.hasAudio else {
            throw TimelineError.notJoinable(reason: "asset nemá obraz i zvuk")
        }
        let link = LinkID()
        var v = try makeClip(assetID: assetID, at: start)
        var a = try makeClip(assetID: assetID, at: start)
        v.linkID = link
        a.linkID = link
        return (v, a)
    }

    /// Kopie s **novým** ID.
    public mutating func duplicate(clipID: ClipID, onto trackID: TrackID, at start: Frames) throws -> ClipID {
        guard let original = timeline.clip(clipID) else { throw TimelineError.clipNotFound(clipID) }
        var copy = Clip(assetID: original.assetID,
                        linkID: nil,
                        timelineStart: start,
                        duration: original.duration,
                        sourceStart: original.sourceStart,
                        speedRamp: original.speedRamp)
        copy.linkID = nil
        try insert(copy, onTrack: trackID)
        return copy.id
    }
}

// MARK: - Stopy

extension Project {

    public mutating func addTrack(kind: TrackKind, name: String) -> TrackID {
        let track = Track(kind: kind, name: name)
        timeline.tracks.append(track)
        return track.id
    }

    public mutating func removeTrack(id: TrackID) throws {
        guard let i = timeline.index(of: id) else { throw TimelineError.trackNotFound(id) }
        timeline.tracks.remove(at: i)
    }

    public mutating func renameTrack(id: TrackID, to name: String) throws {
        guard let i = timeline.index(of: id) else { throw TimelineError.trackNotFound(id) }
        timeline.tracks[i].name = name
    }

    public mutating func moveTrack(id: TrackID, toIndex newIndex: Int) throws {
        guard let i = timeline.index(of: id) else { throw TimelineError.trackNotFound(id) }
        let clamped = max(0, min(newIndex, timeline.tracks.count - 1))
        let track = timeline.tracks.remove(at: i)
        timeline.tracks.insert(track, at: clamped)
    }
}

// MARK: - Vkládání a mazání

extension Project {

    /// Ověří, že klip smí na stopu — druh a překryv. Vrací nic, nebo hází.
    private func checkPlacement(_ clip: Clip, on track: Track, ignoring: ClipID? = nil) throws {
        guard clip.duration.count > 0 else { throw TimelineError.zeroLength }
        guard clip.timelineStart.count >= 0 else { throw TimelineError.negativePosition }

        if let asset = asset(clip.assetID) {
            switch track.kind {
            case .video:
                guard asset.hasVideo else {
                    throw TimelineError.wrongTrackKind(expected: .video, got: .audio)
                }
            case .audio:
                guard asset.hasAudio else {
                    throw TimelineError.wrongTrackKind(expected: .audio, got: .video)
                }
            case .title:
                // Titulková stopa asset klipy nenese nikdy — patří na ni
                // jen `TitleClip`y (fáze 11).
                throw TimelineError.wrongTrackKind(expected: .title,
                                                   got: asset.hasVideo ? .video : .audio)
            }
        } else {
            throw TimelineError.assetNotFound(clip.assetID)
        }

        for other in track.clips where other.id != ignoring && other.id != clip.id {
            if clip.overlaps(other) {
                // Nejbližší legální pozice: buď těsně před, nebo těsně za sousedem.
                let before = other.timelineStart - clip.duration
                let after = other.timelineEnd
                let nearest = abs((before - clip.timelineStart).count) <= abs((after - clip.timelineStart).count)
                    ? before : after
                throw TimelineError.wouldOverlap(with: other.id,
                                                 nearestLegal: Frames(max(0, nearest.count)))
            }
        }
    }

    public mutating func insert(_ clip: Clip, onTrack trackID: TrackID) throws {
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        try checkPlacement(clip, on: timeline.tracks[ti])
        var tracks = timeline.tracks
        tracks[ti].insertSorted(clip)
        timeline.tracks = tracks
    }

    /// Vloží dvojici obraz+zvuk na dvě stopy najednou. Buď obojí, nebo nic.
    public mutating func insertLinked(video: Clip, onVideoTrack vt: TrackID,
                                      audio: Clip, onAudioTrack at: TrackID) throws {
        var copy = self
        try copy.insert(video, onTrack: vt)
        try copy.insert(audio, onTrack: at)
        self = copy
    }

    public mutating func remove(clipID: ClipID) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        var tracks = timeline.tracks
        tracks[at.trackIndex].clips.remove(at: at.clipIndex)
        timeline.tracks = tracks
        // Střihy smazaného klipu zanikly — přechody na nich jdou s ním.
        reconcileTransitions(pruneConflicts: true)
    }

    /// Smaže a posune vše za ním.
    ///
    /// **Dosah:** stopa zasaženého klipu a stopy jeho svázaných dvojčat.
    /// Nikdy ostatní. Hudební podkres na A2 je pevná páteř, ke které se
    /// stříhá — kdyby ho ripple posouval, rozsype se celý film. A kdyby
    /// neposunul svázaný zvuk, rozejde se s obrazem.
    public mutating func rippleRemove(clipID: ClipID) throws {
        guard let clip = timeline.clip(clipID) else { throw TimelineError.clipNotFound(clipID) }
        var copy = self
        let shift = clip.duration
        let from = clip.timelineStart

        var toRemove: [ClipID] = [clipID]
        if let link = clip.linkID {
            toRemove = copy.timeline.tracks.flatMap { $0.clips }
                .filter { $0.linkID == link }
                .map(\.id)
        }

        // Stopy, kterých se ripple týká.
        var affected = Set<TrackID>()
        for id in toRemove {
            if let at = copy.timeline.locate(id) {
                affected.insert(copy.timeline.tracks[at.trackIndex].id)
            }
        }

        for id in toRemove { try copy.remove(clipID: id) }

        var tracks = copy.timeline.tracks
        for (i, track) in tracks.enumerated() where affected.contains(track.id) {
            for (j, c) in track.clips.enumerated() where c.timelineStart >= from {
                tracks[i].clips[j].timelineStart -= shift
            }
        }
        copy.timeline.tracks = tracks
        // Posun je rovnoměrný, takže přechody mezi posunutými sousedy přežijí;
        // pohřbít je třeba jen ty na střihách smazaného klipu (udělal remove).
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
    }

    /// Vloží a odsune vše za ním doprava.
    public mutating func rippleInsert(_ clip: Clip, onTrack trackID: TrackID) throws {
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        var copy = self
        var tracks = copy.timeline.tracks
        for (j, c) in tracks[ti].clips.enumerated() where c.timelineStart >= clip.timelineStart {
            tracks[ti].clips[j].timelineStart += clip.duration
        }
        copy.timeline.tracks = tracks
        try copy.insert(clip, onTrack: trackID)
        // Dvojice rozťatá místem vložení už nesousedí — její přechod zaniká.
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
    }

    /// Vloží a přepíše, co je pod ním. Sousedi se ořežou, plně překryté zmizí.
    /// **Atomicky** — když cokoli selže, projekt zůstane nedotčený.
    public mutating func overwrite(_ clip: Clip, onTrack trackID: TrackID) throws {
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        guard clip.duration.count > 0 else { throw TimelineError.zeroLength }
        guard clip.timelineStart.count >= 0 else { throw TimelineError.negativePosition }

        var copy = self
        var tracks = copy.timeline.tracks
        var survivors: [Clip] = []

        for existing in tracks[ti].clips {
            guard existing.overlaps(clip) else { survivors.append(existing); continue }

            let keepsHead = existing.timelineStart < clip.timelineStart
            let keepsTail = existing.timelineEnd > clip.timelineEnd

            if keepsHead {
                var head = existing
                head.duration = clip.timelineStart - existing.timelineStart
                survivors.append(head)
            }
            if keepsTail {
                var tail = existing
                let cut = clip.timelineEnd - existing.timelineStart
                tail.sourceStart = copy.sourceOffset(in: existing, atFrame: cut)
                tail.timelineStart = clip.timelineEnd
                tail.duration = existing.timelineEnd - clip.timelineEnd
                // Ocásek je nový klip, potřebuje vlastní identitu.
                tail = Clip(assetID: tail.assetID, linkID: nil,
                            timelineStart: tail.timelineStart, duration: tail.duration,
                            sourceStart: tail.sourceStart, speedRamp: tail.speedRamp)
                survivors.append(tail)
            }
        }

        tracks[ti].clips = survivors
        tracks[ti].resort()
        copy.timeline.tracks = tracks
        try copy.insert(clip, onTrack: trackID)
        // Přepis je destrukce z podstaty — i konfliktní přechody se mažou,
        // ne odmítají (ocásky mají nová ID, hlavy nové délky).
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
    }
}

// MARK: - Přesun

extension Project {

    public mutating func move(clipID: ClipID, toTrack trackID: TrackID, start: Frames) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        guard start.count >= 0 else { throw TimelineError.negativePosition }

        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        // Přesun na sebe sama je no-op, ne chyba.
        if timeline.tracks[at.trackIndex].id == trackID && clip.timelineStart == start { return }

        var copy = self
        var moved = clip
        let delta = start - clip.timelineStart
        moved.timelineStart = start

        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].clips.remove(at: at.clipIndex)
        copy.timeline.tracks = tracks
        try copy.checkPlacement(moved, on: copy.timeline.tracks[ti])
        tracks = copy.timeline.tracks
        tracks[ti].insertSorted(moved)
        copy.timeline.tracks = tracks

        // Svázané dvojče jde s ním — jinak se rozejde obraz se zvukem.
        if let link = clip.linkID {
            let partners = copy.timeline.tracks.flatMap { $0.clips }
                .filter { $0.linkID == link && $0.id != clipID }
            for partner in partners {
                guard let pat = copy.timeline.locate(partner.id) else { continue }
                var shifted = partner
                shifted.timelineStart += delta
                var t2 = copy.timeline.tracks
                t2[pat.trackIndex].clips.remove(at: pat.clipIndex)
                copy.timeline.tracks = t2
                try copy.checkPlacement(shifted, on: copy.timeline.tracks[pat.trackIndex])
                t2 = copy.timeline.tracks
                t2[pat.trackIndex].insertSorted(shifted)
                copy.timeline.tracks = t2
            }
        }
        // Odsunutý klip opustil své střihy — přechody na nich zanikají.
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
    }

    /// Přitáhne následující klip k tomuhle.
    public mutating func closeGap(afterClipID clipID: ClipID) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let track = timeline.tracks[at.trackIndex]
        let clip = track.clips[at.clipIndex]
        guard at.clipIndex + 1 < track.clips.count else { return }
        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex + 1].timelineStart = clip.timelineEnd
        copy.timeline.tracks = tracks
        // Přitažený klip se utrhl od svého PRAVÉHO souseda — přechod tam zaniká.
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
    }
}

// MARK: - Střih

extension Project {

    /// Rozdělí klip. `at` je **první snímek druhé poloviny**.
    ///
    /// ⚠️ **Svázaný klip se řeže i s dvojčetem, jinak to nejde.** Vazba smí
    /// mít nejvýš dva členy různého druhu (invariant 9) — kdyby se rozřízl
    /// jen jeden z páru, sdílely by jednu vazbu tři klipy. Proto se řez vede
    /// i dvojčetem a poloviny se přepojí po dvojicích: levé sdílí původní
    /// vazbu, pravé dostanou čerstvou. Když řez dvojčetem nevede (posunuté
    /// dvojče), zůstane vazba té polovině, se kterou se dvojče překrývá,
    /// a druhá polovina je bez vazby.
    ///
    /// Návratová hodnota jsou poloviny KLIPU, o který se žádalo — dvojče se
    /// řeže jako vedlejší účinek, stejně jako ho vedlejším účinkem maže
    /// `rippleRemove`.
    @discardableResult
    public mutating func split(clipID: ClipID, at frame: Frames) throws -> (left: ClipID, right: ClipID) {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]

        var copy = self
        let (leftID, rightID) = try copy.splitSingle(at: at, frame: frame)

        if let link = clip.linkID,
           let partner = copy.timeline.tracks.flatMap(\.clips)
               .first(where: { $0.linkID == link && $0.id != leftID && $0.id != rightID }) {

            if partner.contains(frame: frame), frame > partner.timelineStart,
               let partnerAt = copy.timeline.locate(partner.id) {
                // Řez vede i dvojčetem: rozříznout a přepojit po dvojicích.
                let (partnerLeft, partnerRight) = try copy.splitSingle(at: partnerAt, frame: frame)
                let rightLink = LinkID()
                copy.setLink(partnerLeft, to: link)
                copy.setLink(rightID, to: rightLink)
                copy.setLink(partnerRight, to: rightLink)
            } else if partner.timelineStart >= frame {
                // Dvojče leží celé napravo od řezu — vazba patří pravé polovině.
                copy.setLink(leftID, to: nil)
            } else {
                // Dvojče leží celé nalevo — vazba zůstává levé polovině.
                copy.setLink(rightID, to: nil)
            }
        }

        // Řez vedený OBLASTÍ přechodu by přechod rozbil (polovina by byla
        // kratší než jeho rameno) — takový split se odmítá, projekt se nemění.
        try copy.reconcileTransitionsOrThrow()

        self = copy
        return (leftID, rightID)
    }

    /// Holý řez jednoho klipu, bez ohledu na vazby. Pravá polovina dědí
    /// `linkID` — o vazbách rozhoduje `split`, tenhle helper jen řeže.
    private mutating func splitSingle(at: (trackIndex: Int, clipIndex: Int),
                                      frame: Frames) throws -> (left: ClipID, right: ClipID) {
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]

        guard clip.contains(frame: frame) else { throw TimelineError.splitOutsideClip }
        guard frame > clip.timelineStart else { throw TimelineError.zeroLength }

        let offset = frame - clip.timelineStart
        var left = clip
        left.duration = offset

        // Druhá polovina musí navázat ve zdroji. Kdo sem dá clip.sourceStart,
        // dostane opakující se záběr a nevšimne si toho, dokud to nepustí.
        let right = Clip(assetID: clip.assetID,
                         linkID: clip.linkID,
                         timelineStart: frame,
                         duration: clip.duration - offset,
                         sourceStart: sourceOffset(in: clip, atFrame: offset),
                         speedRamp: clip.speedRamp)

        var tracks = timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex] = left
        tracks[at.trackIndex].clips.insert(right, at: at.clipIndex + 1)
        // Levá polovina dědí ID originálu, takže přechod na LEVÉM střihu drží
        // sám. Přechod na PRAVÉM střihu teď sousedí s pravou polovinou —
        // přepojit, jinak by odkazoval na klip, který už u střihu neleží.
        for (k, t) in tracks[at.trackIndex].transitions.enumerated()
        where t.leftClipID == clip.id {
            tracks[at.trackIndex].transitions[k].leftClipID = right.id
        }
        timeline.tracks = tracks
        return (left.id, right.id)
    }

    /// Přepíše vazbu klipu na místě.
    private mutating func setLink(_ clipID: ClipID, to link: LinkID?) {
        guard let at = timeline.locate(clipID) else { return }
        var tracks = timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex].linkID = link
        timeline.tracks = tracks
    }

    /// Opak splitu. Bez toho se špatný řez neopraví jinak než undo.
    public mutating func join(leftID: ClipID, rightID: ClipID) throws {
        guard let la = timeline.locate(leftID) else { throw TimelineError.clipNotFound(leftID) }
        guard let ra = timeline.locate(rightID) else { throw TimelineError.clipNotFound(rightID) }
        guard la.trackIndex == ra.trackIndex, ra.clipIndex == la.clipIndex + 1 else {
            throw TimelineError.notAdjacent(leftID, rightID)
        }
        let left = timeline.tracks[la.trackIndex].clips[la.clipIndex]
        let right = timeline.tracks[ra.trackIndex].clips[ra.clipIndex]

        guard left.assetID == right.assetID else {
            throw TimelineError.notJoinable(reason: "různé zdroje")
        }
        guard left.timelineEnd == right.timelineStart else {
            throw TimelineError.notJoinable(reason: "na ose na sebe nenavazují")
        }
        let expected = sourceOffset(in: left, atFrame: left.duration)
        guard expected == right.sourceStart else {
            throw TimelineError.notJoinable(reason: "ve zdroji na sebe nenavazují")
        }

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[la.trackIndex].clips[la.clipIndex].duration = left.duration + right.duration
        tracks[la.trackIndex].clips.remove(at: ra.clipIndex)
        // Vnitřní střih zanikl — přechod na něm jde s ním. Přechod na pravém
        // střihu pravého klipu se přepojuje na slepenec (dědí levé ID).
        tracks[la.trackIndex].transitions.removeAll {
            $0.leftClipID == leftID && $0.rightClipID == rightID
        }
        for (k, t) in tracks[la.trackIndex].transitions.enumerated()
        where t.leftClipID == rightID {
            tracks[la.trackIndex].transitions[k].leftClipID = leftID
        }
        copy.timeline.tracks = tracks
        try copy.reconcileTransitionsOrThrow()
        self = copy
    }
}

// MARK: - Trim, slip, roll

extension Project {

    /// Posune začátek klipu. Mění `timelineStart` **i** `sourceStart` —
    /// když se posune jen jedno, klip se ve zdroji „ujede" a při dalším
    /// trimu se chyba znásobí.
    public mutating func trimStart(clipID: ClipID, to newStart: Frames) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        let delta = newStart - clip.timelineStart

        guard newStart < clip.timelineEnd else { throw TimelineError.zeroLength }
        guard newStart.count >= 0 else { throw TimelineError.negativePosition }

        // Nejdřív zdrojový materiál, pak sousedi — pevné pořadí.
        if delta.count < 0 {
            let available = availableSourceFramesBefore(clip)
            guard Frames(-delta.count) <= available else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: available)
            }
        }

        var trimmed = clip
        trimmed.timelineStart = newStart
        trimmed.duration = clip.timelineEnd - newStart
        // Přes `sourceOffset`, ne `sourceStart + sourceTime(delta)` — ten
        // vzorec platí jen při rychlosti 1×. Se zápornou deltou (prodloužení
        // doleva) vrací pozici na křivce před začátkem klipu.
        trimmed.sourceStart = sourceOffset(in: clip, atFrame: delta)

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].clips.remove(at: at.clipIndex)
        copy.timeline.tracks = tracks
        try copy.checkPlacement(trimmed, on: copy.timeline.tracks[at.trackIndex])
        tracks = copy.timeline.tracks
        tracks[at.trackIndex].insertSorted(trimmed)
        copy.timeline.tracks = tracks
        // Trim od LEVÉHO souseda odtrhne (přechod tam zaniká — pravidlo 1);
        // přechod na PRAVÉM střihu žije dál a trim, který by mu vzal místo
        // (klip kratší než rameno oblasti), se odmítá — pravidlo 2.
        try copy.reconcileTransitionsOrThrow()
        self = copy
    }

    /// Posune konec. Mění jen `duration`.
    public mutating func trimEnd(clipID: ClipID, to newEnd: Frames) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]

        guard newEnd > clip.timelineStart else { throw TimelineError.zeroLength }
        let delta = newEnd - clip.timelineEnd

        if delta.count > 0 {
            let remaining = remainingSourceFrames(after: clip)
            guard delta <= remaining else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: remaining)
            }
        }

        var trimmed = clip
        trimmed.duration = newEnd - clip.timelineStart

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].clips.remove(at: at.clipIndex)
        copy.timeline.tracks = tracks
        try copy.checkPlacement(trimmed, on: copy.timeline.tracks[at.trackIndex])
        tracks = copy.timeline.tracks
        tracks[at.trackIndex].insertSorted(trimmed)
        copy.timeline.tracks = tracks
        // Zkrácení odtrhne od PRAVÉHO souseda (přechod zaniká); přechod na
        // LEVÉM střihu žije a trim pod jeho rameno se odmítá.
        try copy.reconcileTransitionsOrThrow()
        self = copy
    }

    /// Posune, co se ze zdroje bere, **beze změny pozice a délky**.
    /// Takhle se opraví „ustřihl jsem to o vteřinu dřív".
    public mutating func slip(clipID: ClipID, by delta: Frames) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        guard delta.count != 0 else { return }

        if delta.count < 0 {
            let available = availableSourceFramesBefore(clip)
            guard Frames(-delta.count) <= available else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: available)
            }
        } else {
            let remaining = remainingSourceFrames(after: clip)
            guard delta <= remaining else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: remaining)
            }
        }

        var copy = self
        var tracks = copy.timeline.tracks
        // Přes `sourceOffset` — u klipu s rampou znamená slip o `delta`
        // snímků „ukaž to, co bylo vidět o `delta` snímků dál", ne posun
        // zdroje o délku převedenou při 1×.
        tracks[at.trackIndex].clips[at.clipIndex].sourceStart =
            sourceOffset(in: clip, atFrame: delta)
        copy.timeline.tracks = tracks
        // Slip hýbe zdrojovými přesahy: prolínačka na střihu potřebuje
        // materiál za hranou a slip, který by jí ho vzal, se odmítá.
        try copy.reconcileTransitionsOrThrow()
        self = copy
    }

    /// Posune hranici mezi dvěma sousedy. `to` je nová pozice hranice;
    /// posun doprava **prodlouží levý** a zkrátí pravý. Délka dvojice
    /// zůstává stejná.
    public mutating func rollEdit(leftID: ClipID, rightID: ClipID, to boundary: Frames) throws {
        guard let la = timeline.locate(leftID) else { throw TimelineError.clipNotFound(leftID) }
        guard let ra = timeline.locate(rightID) else { throw TimelineError.clipNotFound(rightID) }
        guard la.trackIndex == ra.trackIndex, ra.clipIndex == la.clipIndex + 1 else {
            throw TimelineError.notAdjacent(leftID, rightID)
        }
        let left = timeline.tracks[la.trackIndex].clips[la.clipIndex]
        let right = timeline.tracks[ra.trackIndex].clips[ra.clipIndex]
        guard left.timelineEnd == right.timelineStart else {
            throw TimelineError.notAdjacent(leftID, rightID)
        }
        guard boundary > left.timelineStart, boundary < right.timelineEnd else {
            throw TimelineError.zeroLength
        }

        let delta = boundary - left.timelineEnd
        if delta.count > 0 {
            let remaining = remainingSourceFrames(after: left)
            guard delta <= remaining else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: remaining)
            }
        } else if delta.count < 0 {
            let available = availableSourceFramesBefore(right)
            guard Frames(-delta.count) <= available else {
                throw TimelineError.exceedsSourceMaterial(availableFrames: available)
            }
        }

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[la.trackIndex].clips[la.clipIndex].duration = boundary - left.timelineStart
        tracks[ra.trackIndex].clips[ra.clipIndex].timelineStart = boundary
        tracks[ra.trackIndex].clips[ra.clipIndex].duration = right.timelineEnd - boundary
        tracks[ra.trackIndex].clips[ra.clipIndex].sourceStart =
            copy.sourceOffset(in: right, atFrame: delta)
        copy.timeline.tracks = tracks
        // Roll střih zachovává, ale hýbe s ním: přechod na něm jede s hranicí
        // a roll, po kterém by se nevešel (do klipů, do zdroje nebo do oblasti
        // sousedního přechodu), se odmítá.
        try copy.reconcileTransitionsOrThrow()
        self = copy
    }
}

// MARK: - Vazba obrazu a zvuku

extension Project {

    public mutating func unlink(clipID: ClipID) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        guard let link = timeline.tracks[at.trackIndex].clips[at.clipIndex].linkID else { return }
        var copy = self
        var tracks = copy.timeline.tracks
        for (i, track) in tracks.enumerated() {
            for (j, c) in track.clips.enumerated() where c.linkID == link {
                tracks[i].clips[j].linkID = nil
            }
        }
        copy.timeline.tracks = tracks
        self = copy
    }

    public mutating func link(_ a: ClipID, _ b: ClipID) throws {
        guard let aa = timeline.locate(a) else { throw TimelineError.clipNotFound(a) }
        guard let ba = timeline.locate(b) else { throw TimelineError.clipNotFound(b) }
        guard timeline.tracks[aa.trackIndex].kind != timeline.tracks[ba.trackIndex].kind else {
            throw TimelineError.notJoinable(reason: "obě stopy jsou téhož druhu")
        }
        let link = LinkID()
        var copy = self
        var tracks = copy.timeline.tracks
        tracks[aa.trackIndex].clips[aa.clipIndex].linkID = link
        tracks[ba.trackIndex].clips[ba.clipIndex].linkID = link
        copy.timeline.tracks = tracks
        self = copy
    }
}
