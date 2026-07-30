//
//  Transitions.swift
//  TimelineModel — Projekt AIditor
//
//  Přechody na střihu (fáze 10). Přechod patří STŘIHU mezi dvěma sousedy,
//  ne klipu — proto je přivázaný k dvojici (levý, pravý) a žije jen dokud
//  ty dva klipy na ose skutečně sousedí.
//
//  Dvě pravidla pro editace, obě vymáhaná operacemi:
//
//  1. **Střih zanikl → přechod umírá s ním.** Smazání klipu, přesun, mezera
//     po trimu — přechod bez střihu nemá význam, mlčky se odstraní (undo ho
//     vrátí i se střihem, snapshoty nesou celý projekt).
//  2. **Střih žije, ale přechod by se na něm rozbil → operace se ODMÍTNE**
//     (`blockedByTransition`). Trim těsně k přechodu, slip pod zdrojový
//     přesah, roll do sousedního přechodu, rampa na klipu s přechodem.
//     Tiché zkracování nebo mazání přechodu při živém střihu by byla ztráta
//     práce, které si uživatel všimne až při přehrání.
//
//  Prolínačka a zvukový crossfade SPOTŘEBOVÁVAJÍ ZDROJ ZA HRANOU střihu na
//  obou stranách — levý klip musí mít materiál za svým koncem, pravý před
//  svým začátkem. Zatmívačka žádný přesah nepotřebuje: levý dojede do barvy
//  ve svých snímcích, pravý se z ní vynoří ve svých.
//
//  Rampovaný střih je v první verzi zakázaný oběma směry (přechod na rampu
//  nejde přidat, rampa na klip s přechodem taky ne) — kombinace je snůška
//  zvláštních případů a povolí se, až bude důvod. Zapsáno v plánu fáze 10.
//

import Foundation

// MARK: - Typy

public struct TransitionID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public enum TransitionKind: String, Codable, Sendable, CaseIterable {
    /// Prolínačka — oba obrazy přes sebe. Potřebuje zdrojové přesahy.
    case crossDissolve
    /// Zatmívačka do černé. Bez přesahů.
    case dipToBlack
    /// Zatmívačka do bílé. Bez přesahů.
    case dipToWhite
    /// Zvukový crossfade. Potřebuje zdrojové přesahy.
    case audioCrossfade

    /// Na jaký druh stopy přechod patří.
    public var trackKind: TrackKind {
        switch self {
        case .crossDissolve, .dipToBlack, .dipToWhite: return .video
        case .audioCrossfade: return .audio
        }
    }

    /// Jestli oba klipy hrají přes celou oblast přechodu — pak potřebují
    /// zdrojový materiál ZA hranou střihu.
    public var needsSourceOverlap: Bool {
        switch self {
        case .crossDissolve, .audioCrossfade: return true
        case .dipToBlack, .dipToWhite: return false
        }
    }
}

/// Přechod na střihu mezi dvěma sousedními klipy jedné stopy.
///
/// Zapisuj výhradně přes `Project.setTransition` / `removeTransition` /
/// `setTransitionDuration` — operace vymáhají meze, které tahle struktura
/// sama neunese (sousedství, zdrojové přesahy, překryvy s okolními přechody).
public struct Transition: Identifiable, Hashable, Codable, Sendable {
    public let id: TransitionID
    public internal(set) var kind: TransitionKind
    public internal(set) var leftClipID: ClipID
    public internal(set) var rightClipID: ClipID
    /// Celková délka přes střih, v snímcích osy. Vždy ≥ 1.
    public internal(set) var duration: Frames

    init(id: TransitionID = TransitionID(),
         kind: TransitionKind,
         leftClipID: ClipID,
         rightClipID: ClipID,
         duration: Frames) {
        self.id = id
        self.kind = kind
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.duration = duration
    }

    /// Kolik snímků oblasti leží PŘED střihem (uvnitř levého klipu; pravý
    /// klip tam u prolínačky potřebuje předtočený zdroj).
    public var framesBeforeCut: Frames { Frames(duration.count / 2) }
    /// Kolik snímků leží ZA střihem. Liché délky dávají snímek navíc sem —
    /// dělení je pevné, aby stejná délka dala vždy stejnou oblast.
    public var framesAfterCut: Frames { duration - framesBeforeCut }
}

// MARK: - Dotazy

extension Project {

    /// Přechod na střihu mezi dvěma klipy, pokud existuje.
    public func transition(betweenLeft leftID: ClipID, andRight rightID: ClipID) -> Transition? {
        for track in timeline.tracks {
            if let t = track.transitions.first(where: { $0.leftClipID == leftID && $0.rightClipID == rightID }) {
                return t
            }
        }
        return nil
    }

    public func transition(id: TransitionID) -> Transition? {
        for track in timeline.tracks {
            if let t = track.transitions.first(where: { $0.id == id }) { return t }
        }
        return nil
    }

    /// Oblast přechodu na ose: `[start, konec)` v snímcích. `nil`, když
    /// přechod neexistuje nebo jeho střih zanikl. Pro kompozici (fáze 10,
    /// modul 2) i kreslení lichoběžníku na ose (modul 3).
    public func transitionRegion(of id: TransitionID) -> (start: Frames, end: Frames)? {
        for track in timeline.tracks {
            guard let t = track.transitions.first(where: { $0.id == id }) else { continue }
            guard let li = track.index(of: t.leftClipID),
                  let ri = track.index(of: t.rightClipID),
                  ri == li + 1,
                  track.clips[li].timelineEnd == track.clips[ri].timelineStart else { return nil }
            let cut = track.clips[li].timelineEnd
            return (cut - t.framesBeforeCut, cut + t.framesAfterCut)
        }
        return nil
    }

    /// Největší délka přechodu, kterou daný střih unese. Nula = přechod tam
    /// nejde vůbec (střih neexistuje, špatný druh stopy, rampa, nebo chybí
    /// zdrojové přesahy). **UI z téhle hodnoty dělá zarážku tažení** —
    /// `setTransition` ji vymáhá a při překročení ji vrací v chybě.
    ///
    /// Meze: oblast se musí vejít do dvojice klipů, nesmí zasáhnout oblasti
    /// přechodů na vnějších střihách téže dvojice, a u prolínačky/crossfadu
    /// musí být za hranou střihu zdrojový materiál na obou stranách.
    public func maxTransitionDuration(kind: TransitionKind,
                                      betweenLeft leftID: ClipID,
                                      andRight rightID: ClipID) -> Frames {
        guard let la = timeline.locate(leftID), let ra = timeline.locate(rightID),
              la.trackIndex == ra.trackIndex, ra.clipIndex == la.clipIndex + 1 else { return .zero }
        let track = timeline.tracks[la.trackIndex]
        let left = track.clips[la.clipIndex]
        let right = track.clips[ra.clipIndex]
        guard left.timelineEnd == right.timelineStart,
              kind.trackKind == track.kind,
              left.speedRamp == nil, right.speedRamp == nil else { return .zero }

        // Přechody na vnějších střihách dvojice ukusují z místa pro oblast.
        let onLeftCut = track.transitions.first { $0.rightClipID == left.id }
        let onRightCut = track.transitions.first { $0.leftClipID == right.id }

        var beforeMax = left.duration.count - (onLeftCut?.framesAfterCut.count ?? 0)
        var afterMax = right.duration.count - (onRightCut?.framesBeforeCut.count ?? 0)
        if kind.needsSourceOverlap {
            beforeMax = min(beforeMax, availableSourceFramesBefore(right).count)
            afterMax = min(afterMax, remainingSourceFrames(after: left).count)
        }
        beforeMax = max(0, beforeMax)
        afterMax = max(0, afterMax)

        // před = ⌊D/2⌋ ≤ beforeMax a za = ⌈D/2⌉ ≤ afterMax; největší D:
        return Frames(afterMax <= beforeMax ? 2 * afterMax : 2 * beforeMax + 1)
    }
}

// MARK: - Operace

extension Project {

    /// Nastaví přechod na střihu mezi dvěma sousedy. Na témže střihu smí být
    /// nejvýš jeden — opakované volání ho přepíše a **zachová mu ID** (výběr
    /// v UI se nemá rozpadnout kvůli změně délky).
    @discardableResult
    public mutating func setTransition(_ kind: TransitionKind,
                                       duration: Frames,
                                       betweenLeft leftID: ClipID,
                                       andRight rightID: ClipID) throws -> TransitionID {
        guard let la = timeline.locate(leftID) else { throw TimelineError.clipNotFound(leftID) }
        guard let ra = timeline.locate(rightID) else { throw TimelineError.clipNotFound(rightID) }
        guard la.trackIndex == ra.trackIndex, ra.clipIndex == la.clipIndex + 1 else {
            throw TimelineError.notAdjacent(leftID, rightID)
        }
        let track = timeline.tracks[la.trackIndex]
        let left = track.clips[la.clipIndex]
        let right = track.clips[ra.clipIndex]
        guard left.timelineEnd == right.timelineStart else {
            throw TimelineError.notAdjacent(leftID, rightID)
        }
        guard kind.trackKind == track.kind else {
            throw TimelineError.wrongTrackKind(expected: kind.trackKind, got: track.kind)
        }
        guard left.speedRamp == nil, right.speedRamp == nil else {
            throw TimelineError.transitionOnRampedCut
        }
        guard duration.count >= 1 else { throw TimelineError.zeroLength }
        let maxD = maxTransitionDuration(kind: kind, betweenLeft: leftID, andRight: rightID)
        guard duration <= maxD else {
            throw TimelineError.transitionTooLong(maxDuration: maxD)
        }

        var tracks = timeline.tracks
        if let k = tracks[la.trackIndex].transitions.firstIndex(where: {
            $0.leftClipID == leftID && $0.rightClipID == rightID
        }) {
            tracks[la.trackIndex].transitions[k].kind = kind
            tracks[la.trackIndex].transitions[k].duration = duration
            timeline.tracks = tracks
            return tracks[la.trackIndex].transitions[k].id
        }
        let t = Transition(kind: kind, leftClipID: leftID, rightClipID: rightID, duration: duration)
        tracks[la.trackIndex].transitions.append(t)
        timeline.tracks = tracks
        return t.id
    }

    public mutating func removeTransition(id: TransitionID) throws {
        var tracks = timeline.tracks
        for i in tracks.indices {
            if let k = tracks[i].transitions.firstIndex(where: { $0.id == id }) {
                tracks[i].transitions.remove(at: k)
                timeline.tracks = tracks
                return
            }
        }
        throw TimelineError.transitionNotFound(id)
    }

    /// Změna délky = přepsání na témže střihu; validuje stejné meze jako
    /// `setTransition` a ID zůstává.
    public mutating func setTransitionDuration(id: TransitionID, to duration: Frames) throws {
        guard let t = transition(id: id) else { throw TimelineError.transitionNotFound(id) }
        try setTransition(t.kind, duration: duration,
                          betweenLeft: t.leftClipID, andRight: t.rightClipID)
    }
}

// MARK: - Vady a srovnání po operacích

/// Co je s přechodem špatně. `withoutCut` je zánik střihu (přechod se maže),
/// všechno ostatní je konflikt na živém střihu (operace se odmítá).
enum TransitionDefect: Hashable {
    case withoutCut
    case outOfBounds
    case exceedsSource
    case rampedCut
    case kindMismatch
    case overlapping(TransitionID)
}

extension Project {

    /// Projde všechny přechody a vrátí jejich vady. Jediné místo, kde se
    /// pravidla přechodů vyhodnocují — `validate()` z toho dělá porušení
    /// invariantů, operace přes `reconcileTransitions` mazání a odmítání.
    /// Kdo by si pravidla počítal po svém, rozjede se s ostatními.
    func transitionDefects() -> [(id: TransitionID, defect: TransitionDefect)] {
        var out: [(id: TransitionID, defect: TransitionDefect)] = []
        for track in timeline.tracks {
            /// Oblasti už zkontrolovaných přechodů stopy, na překryvy.
            var regions: [(id: TransitionID, start: Int, end: Int)] = []
            for t in track.transitions {
                guard let li = track.index(of: t.leftClipID),
                      let ri = track.index(of: t.rightClipID),
                      ri == li + 1,
                      track.clips[li].timelineEnd == track.clips[ri].timelineStart else {
                    out.append((t.id, .withoutCut))
                    continue
                }
                let left = track.clips[li]
                let right = track.clips[ri]

                if t.kind.trackKind != track.kind {
                    out.append((t.id, .kindMismatch))
                }
                if t.duration.count < 1
                    || t.framesBeforeCut > left.duration
                    || t.framesAfterCut > right.duration {
                    out.append((t.id, .outOfBounds))
                }
                if left.speedRamp != nil || right.speedRamp != nil {
                    out.append((t.id, .rampedCut))
                }
                if t.kind.needsSourceOverlap,
                   remainingSourceFrames(after: left) < t.framesAfterCut
                    || availableSourceFramesBefore(right) < t.framesBeforeCut {
                    out.append((t.id, .exceedsSource))
                }

                let cut = left.timelineEnd.count
                let start = cut - t.framesBeforeCut.count
                let end = cut + t.framesAfterCut.count
                for r in regions where r.start < end && start < r.end {
                    out.append((t.id, .overlapping(r.id)))
                }
                regions.append((t.id, start, end))
            }
        }
        return out
    }

    /// Srovná přechody se stavem střihů po operaci:
    ///
    /// - přechody, jejichž střih zanikl, SMAŽE (pravidlo 1 z hlavičky souboru),
    /// - přechody v konfliktu na živém střihu vrátí volajícímu.
    ///
    /// Přesné operace (trim, slip, roll, split, rampa) na neprázdný návrat
    /// hází `blockedByTransition` — pracují na kopii, projekt zůstane celý.
    /// Destruktivní operace (overwrite) zavolají `pruneConflicts: true`
    /// a konfliktní přechody smažou taky — přepis je destrukce z podstaty.
    @discardableResult
    mutating func reconcileTransitions(pruneConflicts: Bool = false) -> [TransitionID] {
        let defects = transitionDefects()
        guard !defects.isEmpty else { return [] }

        var dead = Set(defects.filter { $0.defect == .withoutCut }.map(\.id))
        var conflicts: [TransitionID] = []
        for (id, defect) in defects where defect != .withoutCut && !dead.contains(id) {
            if !conflicts.contains(id) { conflicts.append(id) }
        }
        if pruneConflicts {
            dead.formUnion(conflicts)
            conflicts = []
        }
        if !dead.isEmpty {
            var tracks = timeline.tracks
            for i in tracks.indices {
                tracks[i].transitions.removeAll { dead.contains($0.id) }
            }
            timeline.tracks = tracks
        }
        return conflicts
    }

    /// Zkratka pro přesné operace: srovnej přechody a při konfliktu hoď.
    /// Volá se na KOPII projektu — když hodí, kopie se zahodí a projekt
    /// zůstane nedotčený, přesně podle pravidla operací.
    mutating func reconcileTransitionsOrThrow() throws {
        if let first = reconcileTransitions().first {
            throw TimelineError.blockedByTransition(first)
        }
    }
}
