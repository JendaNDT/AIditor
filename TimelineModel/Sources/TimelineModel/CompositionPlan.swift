//
//  CompositionPlan.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 10, modul 2: plán A/B rozkladu stopy pro kompozici s přechody.
//
//  Prolínačka a crossfade potřebují, aby OBA klipy hrály přes oblast
//  přechodu — na jedné stopě kompozice to nejde, klipy by se přepsaly.
//  Plán proto rozdává klipy do dvou „drah" (lane A/B): kdo se s předchozím
//  překrývá, jde na druhou dráhu. Zatmívačka překryv nepotřebuje, její
//  klipy zůstávají na dráze A a stmívá se jen průhlednost.
//
//  Tady je ČISTÁ LOGIKA — snímky, zlomky, dráhy. Převod na AVFoundation
//  (CMTime, AVMutableComposition, instrukce video kompozice, volume rampy)
//  dělá `CompositionBuilder` v aplikaci; tenhle plán je jediné místo, kde
//  se počítá, CO se kam vkládá. Kdyby si builder počítal ramena sám,
//  rozejde se s modelem při první změně pravidel.
//

import Foundation

/// Rozklad jedné stopy osy na dráhy kompozice.
public struct TrackCompositionPlan: Hashable, Sendable {

    /// Jeden vklad do kompozice: klip, jeho dráha a rozsah — u členů
    /// prolínačky/crossfadu PRODLOUŽENÝ o rameno přes hranu střihu.
    public struct Placement: Hashable, Sendable {
        public let clipID: ClipID
        /// 0 = dráha A, 1 = dráha B.
        public let lane: Int
        /// Začátek na ose. U pravého člena prolínačky PŘED `timelineStart`
        /// klipu — klip nastupuje už během odcházejícího souseda.
        public let start: Frames
        /// Délka na ose včetně ramen.
        public let duration: Frames
        /// Odkud číst zdroj (u pravého člena posunutý zpět o rameno).
        public let sourceStart: SourceTime
        /// Kolik zdroje vklad spotřebuje. Bez rampy 1:1 k `duration`;
        /// s rampou integrál křivky (a ramena jsou nulová — rampovaný
        /// střih přechod mít nesmí, hlídá to validace).
        public let sourceDuration: SourceTime
        /// Builder má na vklad pustit `rampPlaybackPlan` a škálovat úseky.
        public let hasRamp: Bool
    }

    /// Předpis jednoho přechodu pro instrukce kompozice: kde je oblast,
    /// kde střih a na kterých drahách leží odcházející/nastupující klip.
    public struct Overlay: Hashable, Sendable {
        public let transitionID: TransitionID
        public let kind: TransitionKind
        public let start: Frames
        public let cut: Frames
        public let end: Frames
        public let outgoingClipID: ClipID
        public let incomingClipID: ClipID
        public let outgoingLane: Int
        public let incomingLane: Int
    }

    /// 1, dokud žádný klip nepotřebuje dráhu B — stopa bez prolínaček se
    /// skládá přesně jako před fází 10.
    public let laneCount: Int
    /// V pořadí klipů na ose.
    public let placements: [Placement]
    /// Seřazené podle začátku oblasti.
    public let overlays: [Overlay]
}

extension Project {

    /// Plán rozkladu stopy do drah kompozice. `nil` pro neznámou stopu.
    ///
    /// Vadné přechody (ručně rozbitý projekt) se do plánu nepouštějí —
    /// operace je nevyrobí, ale tohle je čtecí funkce a musí přežít cokoli.
    /// Klip s vadným přechodem hraje natvrdo, přesně jako klip s vadnou
    /// rampou hraje 1× — vada se hlásí ve `validate()`, ne tady.
    public func compositionPlan(forTrack trackID: TrackID) -> TrackCompositionPlan? {
        guard let track = timeline.track(id: trackID) else { return nil }

        let defective = Set(transitionDefects().map(\.id))
        let usable = track.transitions.filter { !defective.contains($0.id) }

        // Ramena z prolínaček/crossfadů, podle klipu.
        var extendEnd: [ClipID: Frames] = [:]
        var extendStart: [ClipID: Frames] = [:]
        for t in usable where t.kind.needsSourceOverlap {
            extendEnd[t.leftClipID] = t.framesAfterCut
            extendStart[t.rightClipID] = t.framesBeforeCut
        }

        var placements: [TrackCompositionPlan.Placement] = []
        var lanes: [ClipID: Int] = [:]

        for clip in track.clips {
            let extS = extendStart[clip.id] ?? .zero
            let extE = extendEnd[clip.id] ?? .zero
            let start = clip.timelineStart - extS
            let duration = clip.duration + extS + extE
            let hasRamp = clip.speedRamp != nil

            // Rampovaný klip nemá ramena (validace nedovolí přechod na jeho
            // střihu), takže obě větve zdroje jsou konzistentní.
            let sourceStart = hasRamp
                ? clip.sourceStart
                : clip.sourceStart - timeline.sourceTime(extS)
            let sourceDuration = hasRamp
                ? sourceConsumption(of: clip)
                : timeline.sourceTime(duration)

            // Dráhu B dostane jen klip, který se s předchozím vkladem
            // překrývá. Překrývat se můžou jen sousedi (oblasti přechodů
            // se nesmí protínat — invariant 17), dvě dráhy proto stačí.
            let lane: Int
            if let last = placements.last, start < last.start + last.duration {
                lane = 1 - last.lane
            } else {
                lane = 0
            }
            lanes[clip.id] = lane

            placements.append(.init(clipID: clip.id, lane: lane,
                                    start: start, duration: duration,
                                    sourceStart: sourceStart,
                                    sourceDuration: sourceDuration,
                                    hasRamp: hasRamp))
        }

        var overlays: [TrackCompositionPlan.Overlay] = []
        for t in usable {
            guard let left = track.clip(id: t.leftClipID),
                  let outgoingLane = lanes[t.leftClipID],
                  let incomingLane = lanes[t.rightClipID] else { continue }
            let cut = left.timelineEnd
            overlays.append(.init(transitionID: t.id, kind: t.kind,
                                  start: cut - t.framesBeforeCut,
                                  cut: cut,
                                  end: cut + t.framesAfterCut,
                                  outgoingClipID: t.leftClipID,
                                  incomingClipID: t.rightClipID,
                                  outgoingLane: outgoingLane,
                                  incomingLane: incomingLane))
        }
        overlays.sort { $0.start < $1.start }

        return TrackCompositionPlan(
            laneCount: placements.contains { $0.lane == 1 } ? 2 : 1,
            placements: placements,
            overlays: overlays)
    }
}
