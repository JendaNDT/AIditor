//
//  Validation.swift
//  TimelineModel — Projekt AIditor
//
//  Invarianty (29), které musí platit po KAŽDÉ operaci. Testy je kontrolují
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
    /// 18. Titulek na stopě, která není titulková. (Obrácený směr — asset
    /// klip na titulkové stopě — hlásí č. 8 `wrongTrackKind`.)
    case titleOnWrongTrack(TitleClipID)
    /// 19. Titulky na stopě nejsou seřazené vzestupně.
    case unsortedTitles(TrackID)
    /// 20. Dva titulky na téže stopě se překrývají. (Dotyk překryv NENÍ.)
    case overlappingTitles(TitleClipID, TitleClipID)
    /// 21. Titulek nulové nebo záporné délky.
    case nonPositiveTitleDuration(TitleClipID)
    /// 22. Titulek začíná před nulou.
    case negativeTitleStart(TitleClipID)
    /// 23. Dva titulky sdílejí ID.
    case duplicateTitleID(TitleClipID)
    /// 24. Rychlostní křivka na klipu fotky — zakázaná kombinace (fáze 12).
    case rampOnStill(ClipID)
    /// 25. Ken Burns na klipu, který není fotka.
    case kenBurnsOnNonStill(ClipID)
    /// 26. Výřez Ken Burns mimo obraz nebo degenerovaně malý.
    case invalidKenBurns(ClipID)
    /// 27. Barevný preset na klipu mimo obrazovou stopu (fáze 13).
    case colorGradeOnWrongTrack(ClipID)
    /// 28. Intenzita barevného presetu mimo 0–1.
    case invalidColorGrade(ClipID)
    /// 29. Zvukové fade na klipu mimo zvukovou stopu, nebo záporné
    /// (fáze 16). Součet přes délku klipu invariant NENÍ — trim smí
    /// klip zkrátit a kompozice délky zařeže (`effectiveAudioFades`).
    case invalidAudioFades(ClipID)
}

extension Project {

    /// Vrací **všechna** porušení, ne první. Při ladění operace potřebuješ
    /// vidět celý rozsah škody, ne jen to, na co se narazilo dřív.
    public func validate() -> [Violation] {
        var out: [Violation] = []
        var seenClipIDs = Set<ClipID>()
        var linkGroups: [LinkID: [(ClipID, TrackKind)]] = [:]

        for asset in assets {
            if asset.isStill {
                // Fotka časování nemá a nevymáhá se; nesmí ale předstírat
                // zvuk (pustila by se na zvukovou stopu) ani zapírat obraz.
                if asset.hasAudio || !asset.hasVideo {
                    out.append(.invalidAsset(asset.id))
                }
            } else if asset.duration.value <= 0 || asset.measuredFrameRate <= 0 {
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
                // 27. + 28. barevný preset (fáze 13) — nepotřebuje asset,
                // váže se na druh STOPY: fotka i video ano, zvuk ne.
                if let grade = clip.colorGrade {
                    if track.kind != .video {
                        out.append(.colorGradeOnWrongTrack(clip.id))
                    } else if !grade.isUsable {
                        out.append(.invalidColorGrade(clip.id))
                    }
                }
                // 29. zvukové fade (fáze 16) — jen zvuková stopa, nezáporné.
                if let fades = clip.audioFades,
                   track.kind != .audio || fades.fadeIn < .zero || fades.fadeOut < .zero {
                    out.append(.invalidAudioFades(clip.id))
                }
                // 2. překryv — stačí porovnat se sousedem, pole je seřazené
                if i + 1 < track.clips.count, clip.overlaps(track.clips[i + 1]) {
                    out.append(.overlappingClips(clip.id, track.clips[i + 1].id))
                }
                // 6. + 5. + 8. vztah k assetu
                if let asset = asset(clip.assetID) {
                    // U fotky spotřeba nula → hlásí se jen nesmyslný
                    // `sourceStart` > 0 (fotka žádný zdrojový čas nemá).
                    let end = clip.sourceStart + sourceConsumption(of: clip)
                    if end > asset.duration {
                        out.append(.exceedsSource(clip.id))
                    }
                    let ok: Bool
                    switch track.kind {
                    case .video: ok = asset.hasVideo
                    case .audio: ok = asset.hasAudio
                    case .title: ok = false   // asset klip na T1 nemá co dělat
                    }
                    if !ok {
                        out.append(.wrongTrackKind(clip.id, track.kind))
                    }
                    // 24.–26. fotky (fáze 12)
                    if asset.isStill, clip.speedRamp != nil {
                        out.append(.rampOnStill(clip.id))
                    }
                    if let kenBurns = clip.kenBurns {
                        if !asset.isStill {
                            out.append(.kenBurnsOnNonStill(clip.id))
                        } else if !kenBurns.isUsable {
                            out.append(.invalidKenBurns(clip.id))
                        }
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

        // 18.–23. titulky (fáze 11)
        var seenTitleIDs = Set<TitleClipID>()
        for track in timeline.tracks {
            // 19. seřazenost
            if zip(track.titles, track.titles.dropFirst()).contains(where: { $0.timelineStart > $1.timelineStart }) {
                out.append(.unsortedTitles(track.id))
            }
            for (i, title) in track.titles.enumerated() {
                // 18. jen na titulkové stopě
                if track.kind != .title {
                    out.append(.titleOnWrongTrack(title.id))
                }
                // 23. jedinečnost ID
                if !seenTitleIDs.insert(title.id).inserted {
                    out.append(.duplicateTitleID(title.id))
                }
                // 21. kladná délka
                if title.duration.count <= 0 {
                    out.append(.nonPositiveTitleDuration(title.id))
                }
                // 22. nezáporný začátek
                if title.timelineStart.count < 0 {
                    out.append(.negativeTitleStart(title.id))
                }
                // 20. překryv — stačí soused, pole je seřazené
                if i + 1 < track.titles.count, title.overlaps(track.titles[i + 1]) {
                    out.append(.overlappingTitles(title.id, track.titles[i + 1].id))
                }
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
