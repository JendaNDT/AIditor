//
//  Validation.swift
//  TimelineModel — Projekt Krása
//
//  Deset invariantů, které musí platit po KAŽDÉ operaci. Testy je kontrolují
//  po každém volání, takže chytí i chyby, na které test přímo necílil.
//

import Foundation

public enum Violation: Hashable, Sendable {
    /// 1. Klipy na stopě nejsou seřazené vzestupně.
    case unsortedClips(TrackID)
    /// 2. Dva klipy na téže stopě se překrývají. (Dotyk konec == začátek překryv NENÍ.)
    case overlappingClips(ClipID, ClipID)
    /// 3. Klip nulové nebo záporné délky.
    case nonPositiveDuration(ClipID)
    /// 4. Klip začíná před nulou.
    case negativeStart(ClipID)
    /// 5. Klip spotřebuje víc zdroje, než asset má.
    case exceedsSource(ClipID)
    /// 6. Klip odkazuje na neexistující asset.
    case unknownAsset(ClipID, AssetID)
    /// 7. Dva klipy sdílejí ID.
    case duplicateClipID(ClipID)
    /// 8. Klip na stopě špatného druhu (obraz na zvukové stopě nebo naopak).
    case wrongTrackKind(ClipID, TrackKind)
    /// 9. Vazba obraz–zvuk je porušená: víc než dvojice, nebo obě na stopě téhož druhu.
    case brokenLink(LinkID)
    /// 10. Nesmyslné hodnoty času.
    case invalidTime(ClipID)
    case invalidAsset(AssetID)
    /// 11. Rychlostní křivka s neplatnými uzly. Výpočty ji ignorují (klip
    /// hraje 1×), ale mlčky by se ztratit neměla.
    case invalidSpeedRamp(ClipID)
    /// 12. Přechod bez střihu — klip chybí, nebo dvojice nesousedí.
    case transitionWithoutCut(TransitionID)
    /// 13. Oblast přechodu se nevejde do dvojice klipů (nebo délka < 1).
    case transitionOutOfBounds(TransitionID)
    /// 14. Prolínačce/crossfadu chybí zdrojový přesah za hranou střihu.
    case transitionExceedsSource(TransitionID)
    /// 15. Přechod na rampovaném střihu — v první verzi zakázaná kombinace.
    case transitionOnRampedCut(TransitionID)
    /// 16. Druh přechodu nesedí na druh stopy (crossfade na obraze apod.).
    case transitionKindMismatch(TransitionID)
    /// 17. Oblasti dvou přechodů na téže stopě se překrývají
    /// (dva na jednom střihu se překrývají vždy).
    case overlappingTransitions(TransitionID, TransitionID)
}

extension Project {

    /// Vrací **všechna** porušení, ne první. Při ladění operace potřebuješ
    /// vidět celý rozsah škody, ne jen to, na co se narazilo dřív.
    public func validate() -> [Violation] {
        var out: [Violation] = []
        var seenClipIDs = Set<ClipID>()
        var linkGroups: [LinkID: [(ClipID, TrackKind)]] = [:]

        for asset in assets {
            if asset.duration.value <= 0 || asset.measuredFrameRate <= 0 {
                out.append(.invalidAsset(asset.id))
            }
        }

        for track in timeline.tracks {
            // 1. seřazenost
            if zip(track.clips, track.clips.dropFirst()).contains(where: { $0.timelineStart > $1.timelineStart }) {
                out.append(.unsortedClips(track.id))
            }

            for (i, clip) in track.clips.enumerated() {
                // 7. jedinečnost ID
                if !seenClipIDs.insert(clip.id).inserted {
                    out.append(.duplicateClipID(clip.id))
                }
                // 3. kladná délka
                if clip.duration.count <= 0 {
                    out.append(.nonPositiveDuration(clip.id))
                }
                // 4. nezáporný začátek
                if clip.timelineStart.count < 0 {
                    out.append(.negativeStart(clip.id))
                }
                // 10. platný zdrojový čas
                if clip.sourceStart.value < 0 {
                    out.append(.invalidTime(clip.id))
                }
                // 11. použitelná rychlostní křivka
                if let ramp = clip.speedRamp, !ramp.isUsable {
                    out.append(.invalidSpeedRamp(clip.id))
                }
                // 2. překryv — stačí porovnat se sousedem, pole je seřazené
                if i + 1 < track.clips.count, clip.overlaps(track.clips[i + 1]) {
                    out.append(.overlappingClips(clip.id, track.clips[i + 1].id))
                }
                // 6. + 5. + 8. vztah k assetu
                if let asset = asset(clip.assetID) {
                    let end = clip.sourceStart + sourceConsumption(of: clip)
                    if end > asset.duration {
                        out.append(.exceedsSource(clip.id))
                    }
                    let ok = (track.kind == .video) ? asset.hasVideo : asset.hasAudio
                    if !ok {
                        out.append(.wrongTrackKind(clip.id, track.kind))
                    }
                } else {
                    out.append(.unknownAsset(clip.id, clip.assetID))
                }
                // 9. sběr vazeb
                if let link = clip.linkID {
                    linkGroups[link, default: []].append((clip.id, track.kind))
                }
            }
        }

        // 9. vyhodnocení vazeb
        for (link, members) in linkGroups {
            let kinds = Set(members.map(\.1))
            if members.count > 2 || (members.count == 2 && kinds.count != 2) {
                out.append(.brokenLink(link))
            }
        }

        // 12.–17. přechody — pravidla vyhodnocuje jediné místo
        // (`transitionDefects` v Transitions.swift), tady se jen překládají.
        for (id, defect) in transitionDefects() {
            switch defect {
            case .withoutCut: out.append(.transitionWithoutCut(id))
            case .outOfBounds: out.append(.transitionOutOfBounds(id))
            case .exceedsSource: out.append(.transitionExceedsSource(id))
            case .rampedCut: out.append(.transitionOnRampedCut(id))
            case .kindMismatch: out.append(.transitionKindMismatch(id))
            case .overlapping(let other): out.append(.overlappingTransitions(id, other))
            }
        }

        return out
    }

    public var isValid: Bool { validate().isEmpty }
}
