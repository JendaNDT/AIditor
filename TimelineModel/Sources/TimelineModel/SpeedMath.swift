//
//  SpeedMath.swift
//  TimelineModel — Projekt Krása
//
//  Most mezi rychlostní křivkou modelu (uzly kotvené ve ZDROJOVÉM čase,
//  aby zpomalení po trimu zůstalo na události) a `SpeedRampEngine`
//  (matematika po VÝSTUPNÍ ose, ověřená 53 testy).
//
//  Křivka enginu se staví nad celou doménou zdroje assetu: výstupní nula
//  enginu = zdrojová nula assetu. Před prvním uzlem a za posledním jede
//  křivka konstantní krajní rychlostí. Díky tomu je pozice klipu na křivce
//  prostě `outputTime(atSource: clip.sourceStart)` a trim, slip i split
//  nepotřebují žádné zvláštní případy.
//
//  Zaokrouhlování: engine počítá v sekundách (`Double`), model v celých
//  tickách. Na hranici se zaokrouhluje DOLŮ s tolerancí 1e-3 ticku — dolů
//  ze stejného důvodu jako `availableFrames` (nahoru by dovolilo sáhnout
//  za konec souboru), tolerance proto, aby analyticky přesná hodnota
//  nepropadla o tick kvůli šumu ve `Double`.
//

import Foundation
import SpeedRampEngine

/// Interní zkratka — `SpeedRamp` v tomhle modulu znamená typ modelu.
typealias EngineRamp = SpeedRampEngine.SpeedRamp

// MARK: - Platnost křivky

extension SpeedRamp {
    /// Křivka, se kterou se dá počítat: aspoň jeden uzel, ostře rostoucí
    /// zdrojové časy, rychlosti nad minimem enginu. Jediný uzel znamená
    /// konstantní rychlost. Nepoužitelnou křivku výpočty ignorují (klip
    /// hraje 1×) a `validate()` ji hlásí jako `invalidSpeedRamp`.
    public var isUsable: Bool {
        guard !nodes.isEmpty else { return false }
        for (i, node) in nodes.enumerated() {
            guard node.speed >= EngineRamp.minimumSpeed, node.speed.isFinite else { return false }
            if i > 0, !(nodes[i - 1].sourceTime < node.sourceTime) { return false }
        }
        return true
    }

    /// Klasický svatební ramp 1,0 → `slowSpeed` → 1,0 s easeInOut přes
    /// zdrojový úsek `[start, start + span]`. EaseInOut je symetrický,
    /// takže prostřední uzel leží v polovině úseku a výstupní délka vyjde
    /// `span / ((1 + slowSpeed) / 2)`.
    public static func classicSlowMotion(from start: SourceTime,
                                         spanning span: SourceTime,
                                         slowSpeed: Double = 0.25) -> SpeedRamp {
        let startSeconds = start.seconds
        let spanSeconds = span.seconds
        return SpeedRamp(nodes: [
            SpeedNode(sourceTime: SourceTime(seconds: startSeconds),
                      speed: 1.0, easeToNext: .easeInOut),
            SpeedNode(sourceTime: SourceTime(seconds: startSeconds + spanSeconds / 2),
                      speed: slowSpeed, easeToNext: .easeInOut),
            SpeedNode(sourceTime: SourceTime(seconds: startSeconds + spanSeconds),
                      speed: 1.0, easeToNext: .easeInOut),
        ])
    }
}

// MARK: - Okno klipu na křivce

/// Křivka enginu + výstupní čas, na kterém na ní klip začíná.
struct RampWindow {
    let ramp: EngineRamp
    /// Výstupní čas začátku klipu na křivce (křivka běží od zdrojové nuly assetu).
    let t0: Double
}

extension Project {

    /// Křivka klipu v enginu, nebo `nil` když klip hraje 1× (žádná nebo
    /// nepoužitelná rampa). Všechny rampové výpočty začínají tady.
    func rampWindow(for clip: Clip) -> RampWindow? {
        guard let model = clip.speedRamp, model.isUsable else { return nil }

        var anchored: [SourceAnchoredNode] = []
        anchored.reserveCapacity(model.nodes.count + 2)

        // Před prvním uzlem jede zdroj rychlostí prvního uzlu — kotva na
        // zdrojové nule dává křivce celou doménu assetu.
        if let first = model.nodes.first, first.sourceTime.seconds > 1e-12 {
            anchored.append(SourceAnchoredNode(sourceOffset: 0,
                                               speed: first.speed,
                                               easeToNext: .linear))
        }
        for node in model.nodes {
            anchored.append(SourceAnchoredNode(sourceOffset: node.sourceTime.seconds,
                                               speed: node.speed,
                                               easeToNext: node.easeToNext))
        }
        // Jediný uzel na nule = konstantní rychlost; engine chce dva uzly.
        if anchored.count == 1 {
            anchored.append(SourceAnchoredNode(sourceOffset: 1,
                                               speed: anchored[0].speed,
                                               easeToNext: .linear))
        }

        guard let ramp = try? EngineRamp.anchoredToSource(anchored) else { return nil }
        return RampWindow(ramp: ramp, t0: ramp.outputTime(atSource: clip.sourceStart.seconds))
    }

    /// Sekundy → ticky projektové báze, dolů s tolerancí (viz hlavička souboru).
    private func flooredTicks(seconds: Double) -> Int64 {
        Int64((seconds * Double(SourceTime.projectTimescale) + 1e-3).rounded(.down))
    }

    /// Zdroj spotřebovaný prvními `frames` snímky klipu s rampou.
    /// Společný vnitřek `sourceConsumption` a `sourceOffset` — obě funkce
    /// MUSÍ počítat stejně, jinak se rozejde `join`.
    func rampConsumption(window: RampWindow, clip: Clip, frames: Frames) -> SourceTime {
        let dt = Double(frames.count) / Double(timeline.frameRate)
        let consumed = window.ramp.sourceTime(atOutput: window.t0 + dt) - clip.sourceStart.seconds
        return SourceTime(value: flooredTicks(seconds: consumed),
                          timescale: SourceTime.projectTimescale)
    }

    /// Kolik snímků osy lze klip prodloužit, než křivka dojede na konec
    /// assetu. Zaokrouhluje se dolů s malou srážkou (−1e-6 snímku), aby šum
    /// ve `Double` nepustil trim o vlásek za konec souboru.
    func rampRemainingFrames(window: RampWindow, clip: Clip, assetDuration: SourceTime) -> Frames {
        let fps = Double(timeline.frameRate)
        let clipEnd = window.t0 + Double(clip.duration.count) / fps
        let assetEnd = window.ramp.outputTime(atSource: assetDuration.seconds)
        let remaining = (assetEnd - clipEnd) * fps - 1e-6
        guard remaining > 0 else { return .zero }
        return Frames(Int(remaining.rounded(.down)))
    }

    /// Kolik snímků osy leží na křivce před začátkem klipu.
    func rampAvailableFramesBefore(window: RampWindow) -> Frames {
        let frames = window.t0 * Double(timeline.frameRate) - 1e-6
        guard frames > 0 else { return .zero }
        return Frames(Int(frames.rounded(.down)))
    }
}

// MARK: - Nastavení křivky (operace)

extension Project {

    /// Nastaví (nebo `nil` smaže) rychlostní křivku klipu — a **svázanému
    /// dvojčeti tutéž**, jinak se rozejde obraz se zvukem.
    ///
    /// Délka klipu na ose se nemění; mění se spotřeba zdroje. Když by nová
    /// křivka chtěla víc zdroje, než za `sourceStart` zbývá (zrychlení na
    /// konci souboru), operace selže a projekt zůstane nedotčený.
    public mutating func setSpeedRamp(clipID: ClipID, ramp: SpeedRamp?) throws {
        guard let clip = timeline.clip(clipID) else { throw TimelineError.clipNotFound(clipID) }
        if let ramp {
            guard ramp.isUsable else { throw TimelineError.invalidSpeedRamp }
            // Fotka se nezpomaluje — stojí z definice (fáze 12).
            guard asset(clip.assetID)?.isStill != true else {
                throw TimelineError.rampOnStillClip
            }
        }

        var copy = self
        var affected: [ClipID] = [clipID]
        affected += linkedPartners(of: clipID).map(\.id)

        var tracks = copy.timeline.tracks
        for id in affected {
            guard let at = copy.timeline.locate(id) else { continue }
            tracks[at.trackIndex].clips[at.clipIndex].speedRamp = ramp
        }
        copy.timeline.tracks = tracks

        for id in affected {
            guard let clip = copy.timeline.clip(id),
                  let asset = copy.asset(clip.assetID) else { continue }
            if clip.sourceStart + copy.sourceConsumption(of: clip) > asset.duration {
                let available = clip.duration + copy.remainingSourceFrames(after: clip)
                throw TimelineError.exceedsSourceMaterial(availableFrames: available)
            }
        }

        // Rampovaný střih je v první verzi zakázaný oběma směry (fáze 10):
        // rampa na klipu, jehož střihu sedí přechod, se odmítá — smaž nebo
        // přesuň přechod, pak zpomaluj.
        try copy.reconcileTransitionsOrThrow()

        self = copy
    }
}

// MARK: - Plán přehrávání pro kompozici

/// Segmentace křivky klipu převedená na celé ticky projektové báze —
/// přesně to, co `CompositionBuilder` předhodí `scaleTimeRange`.
/// Zdrojové hranice se zaokrouhlují KUMULATIVNĚ (poslední úsek je dotažený
/// na spotřebu klipu) a výstup je násobek celých snímků, takže úseky na
/// sebe navazují beze zbytku — stejný princip jako `Ramper.tickPlan`
/// ověřený ve Spiku 0.
public struct RampPlaybackPlan: Sendable {
    public struct Segment: Hashable, Sendable {
        /// Začátek úseku ve zdroji, relativně k `sourceStart` klipu.
        public let sourceStartTicks: Int64
        public let sourceDurationTicks: Int64
        /// Délka úseku na ose — celé snímky × ticky na snímek.
        public let outputTicks: Int64
    }
    public let segments: [Segment]
    /// Mez skoku rychlosti je při dané snímkové frekvenci nedosažitelná.
    /// UI to musí umět zobrazit, ne to spolknout.
    public let limitedByFrameRate: Bool
    public let achievedMaxStep: Double
}

extension Project {

    /// Plán segmentů pro `scaleTimeRange`. `nil` = klip hraje 1× a volající
    /// vloží rozsah bez škálování. Výchozí mez skoku 1,5 procentního bodu —
    /// rozhodnutí ze Spiku 0.
    public func rampPlaybackPlan(of clip: Clip,
                                 maxSpeedStep: Double = 0.015) -> RampPlaybackPlan? {
        guard let window = rampWindow(for: clip) else { return nil }
        let fps = Double(timeline.frameRate)
        guard let plan = try? window.ramp.segmentation(outputFrameRate: fps,
                                                       maxSpeedStep: maxSpeedStep,
                                                       windowStart: window.t0,
                                                       windowFrames: clip.duration.count)
        else { return nil }

        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(timeline.frameRate)
        let totalSource = sourceConsumption(of: clip)
            .converted(to: SourceTime.projectTimescale).value

        var segments: [RampPlaybackPlan.Segment] = []
        segments.reserveCapacity(plan.segments.count)
        var cursor: Int64 = 0
        var cumulative = 0.0

        for (index, segment) in plan.segments.enumerated() {
            cumulative += segment.sourceDuration
            let isLast = index == plan.segments.count - 1
            let end = isLast
                ? totalSource
                : min(totalSource,
                      Int64((cumulative * Double(SourceTime.projectTimescale)).rounded()))
            let frames = Int64((segment.outputDuration * fps).rounded())
            segments.append(RampPlaybackPlan.Segment(
                sourceStartTicks: cursor,
                sourceDurationTicks: max(0, end - cursor),
                outputTicks: frames * ticksPerFrame))
            cursor = end
        }

        return RampPlaybackPlan(segments: segments,
                                limitedByFrameRate: plan.limitedByFrameRate,
                                achievedMaxStep: plan.achievedMaxStep)
    }
}
