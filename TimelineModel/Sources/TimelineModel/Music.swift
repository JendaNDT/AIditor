//
//  Music.swift
//  TimelineModel — Projekt Krása
//
//  Hudební mapa na ose (fáze 14, modul 2).
//
//  Mřížka dob (`BeatGrid` z AudioEngine) patří ASSETU hudby a je kotvená
//  ve ZDROJOVÉM čase souboru — totéž rozhodnutí jako u přepisu řeči:
//  střih, trim ani přesun klipu s dobami nehnou, drží se na hudbě.
//  `beatMarks()` doby promítá na osu přes klipy zvukových stop; inverzi
//  `sourceOffset` dělá `frameOffset(forSource:in:)`, takže promítnutí
//  funguje i pod rychlostní křivkou (vzorec `subtitleCues`).
//

import AudioEngine
import Foundation

/// Doba promítnutá na osu. Snímek je zaokrouhlení času doby na mřížku
/// projektu — jemněji než na snímek se na 30fps ose stejně nic nestane.
public struct BeatMark: Hashable, Sendable {
    public let frame: Frames
    /// „Raz" taktu — kreslí se výrazněji.
    public let isDownbeat: Bool
}

extension Project {

    /// Nastaví (nebo `nil` smaže) mřížku dob assetu. Hudba je zvuk —
    /// na fotce nemá mřížka co dělat; nesmyslné tempo se odmítá.
    public mutating func setBeatGrid(assetID: AssetID, _ grid: BeatGrid?) throws {
        guard let i = assets.firstIndex(where: { $0.id == assetID }) else {
            throw TimelineError.assetNotFound(assetID)
        }
        if let grid {
            guard assets[i].hasAudio else { throw TimelineError.beatGridNeedsAudio }
            guard grid.bpm.isFinite, grid.bpm > 0,
                  grid.firstBeatTime.isFinite, grid.beatsPerBar >= 1 else {
                throw TimelineError.invalidBeatGrid
            }
        }
        assets[i].beatGrid = grid
    }

    /// Doby všech hudebních klipů promítnuté na osu, seřazené, bez
    /// duplicit (dva klipy téže skladby můžou promítnout touž dobu na
    /// týž snímek — „raz" při slepení vyhrává).
    public func beatMarks() -> [BeatMark] {
        var byFrame: [Frames: Bool] = [:]
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard let asset = asset(clip.assetID),
                      let grid = asset.beatGrid else { continue }
                let windowStart = clip.sourceStart.seconds
                let windowEnd = (clip.sourceStart + sourceConsumption(of: clip)).seconds

                for beat in grid.beats(from: windowStart, to: windowEnd) {
                    let offset = frameOffset(
                        forSource: SourceTime(seconds: beat.time), in: clip)
                    let frame = clip.timelineStart + offset
                    byFrame[frame] = (byFrame[frame] ?? false) || beat.isDownbeat
                }
            }
        }
        return byFrame
            .map { BeatMark(frame: $0.key, isDownbeat: $0.value) }
            .sorted { $0.frame < $1.frame }
    }
}

// MARK: - Dopasování na dobu (fáze 14, modul 3)

/// Výsledek zarovnání konce klipu na dobu — pro status a testy.
public struct BeatFitResult: Hashable, Sendable {
    public let beat: Frames
    public let newDuration: Frames
    /// Násobek rychlosti: 1,05 = zrychlení o 5 %, 0,95 = zpomalení.
    public let speedFactor: Double
}

extension Project {

    /// Nejnižší ČISTÁ rychlost klipu daného assetu: pod `výstupFps/zdrojFps`
    /// se snímky duplikují (pravidlo projektu — z něj plyne LIMIT, ne jen
    /// varování). Nad 1 se rychlost neomezuje.
    func cleanSpeedFloor(for asset: Asset) -> Double {
        guard asset.measuredFrameRate > 0 else { return 1 }
        return min(1, Double(timeline.frameRate) / asset.measuredFrameRate)
    }

    /// „Přizpůsobit klip": KONSTANTNÍ změna rychlosti tak, aby konec klipu
    /// padl na nejbližší dobu hudby. Obsah klipu se nemění — hraje se týž
    /// zdrojový úsek, jen o pár procent rychleji či pomaleji (spotřeba se
    /// zachovává: rychlosti křivky × f, délka ÷ f).
    ///
    /// Meze podle plánu F14: rychlost v `speedRange` (výchozí 90–115 %)
    /// a VŽDY nad limitem čistého zpomalení. Doba, na kterou by se konec
    /// nevešel (soused, meze), se přeskakuje; žádná v dosahu →
    /// `noBeatInReach` s nejbližší dobou — UI poradí trim, NEVYNUCUJE.
    /// Souosé svázané dvojče se přizpůsobuje spolu (délka i rychlost);
    /// nesouosé dostane jen rychlost (nesouosost je záměr trimu).
    @discardableResult
    public mutating func fitClipEndToBeat(
        clipID: ClipID,
        speedRange: ClosedRange<Double> = 0.90...1.15) throws -> BeatFitResult {

        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        guard let sourceAsset = asset(clip.assetID) else {
            throw TimelineError.assetNotFound(clip.assetID)
        }
        guard !sourceAsset.isStill else { throw TimelineError.rampOnStillClip }
        guard sourceAsset.beatGrid == nil else { throw TimelineError.beatFitOnMusicClip }

        let marks = beatMarks()
        guard !marks.isEmpty else { throw TimelineError.noBeatInReach(nearest: nil) }
        let nearestOverall = marks.min {
            abs($0.frame.count - clip.timelineEnd.count)
                < abs($1.frame.count - clip.timelineEnd.count)
        }?.frame

        let durationFrames = Double(clip.duration.count)
        let currentRamp = clip.speedRamp.flatMap { $0.isUsable ? $0 : nil }
        let currentMinSpeed = currentRamp?.nodes.map(\.speed).min() ?? 1.0
        let floor = cleanSpeedFloor(for: sourceAsset)

        // Kam až smí nový konec: začátek dalšího klipu na stopě (dotyk je
        // legální) — a totéž pro souosé dvojče, jehož délka se mění taky.
        func roomEnd(afterIndex index: Int, onTrackIndex trackIndex: Int) -> Frames {
            let clips = timeline.tracks[trackIndex].clips
            return index + 1 < clips.count ? clips[index + 1].timelineStart
                                           : Frames(Int.max / 2)
        }
        var limit = roomEnd(afterIndex: at.clipIndex, onTrackIndex: at.trackIndex)
        let twin = linkedPartners(of: clipID).first
        let twinIsAligned = twin.map {
            $0.timelineStart == clip.timelineStart && $0.duration == clip.duration
        } ?? false
        if let twin, twinIsAligned, let twinAt = timeline.locate(twin.id) {
            limit = min(limit, roomEnd(afterIndex: twinAt.clipIndex,
                                       onTrackIndex: twinAt.trackIndex))
        }

        // Nejbližší POUŽITELNÁ doba ke stávajícímu konci.
        var best: (beat: Frames, factor: Double)?
        for mark in marks {
            guard mark.frame > clip.timelineStart, mark.frame <= limit else { continue }
            let factor = durationFrames / Double(mark.frame.count - clip.timelineStart.count)
            guard speedRange.contains(factor) else { continue }
            // Limit čistého zpomalení: nová minimální rychlost nesmí pod
            // podlahu — leda by klip UŽ pod ní byl a operace ho nezhoršila.
            let newMinSpeed = factor * currentMinSpeed
            guard newMinSpeed >= floor - 1e-9 || newMinSpeed >= currentMinSpeed - 1e-9
            else { continue }
            if best == nil || abs(mark.frame.count - clip.timelineEnd.count)
                < abs(best!.beat.count - clip.timelineEnd.count) {
                best = (mark.frame, factor)
            }
        }
        guard let best else { throw TimelineError.noBeatInReach(nearest: nearestOverall) }

        let newDuration = best.beat - clip.timelineStart
        let result = BeatFitResult(beat: best.beat, newDuration: newDuration,
                                   speedFactor: best.factor)
        guard best.beat != clip.timelineEnd else { return result }   // už sedí

        // Nová křivka: stávající se škáluje po uzlech (kotvy ve zdroji se
        // NEMĚNÍ — zpomalení zůstává na události), bez křivky vzniká jeden
        // uzel konstantní rychlosti.
        let newRamp: SpeedRamp
        if let currentRamp {
            newRamp = SpeedRamp(nodes: currentRamp.nodes.map {
                SpeedNode(sourceTime: $0.sourceTime,
                          speed: $0.speed * best.factor,
                          easeToNext: $0.easeToNext)
            })
        } else {
            newRamp = SpeedRamp(nodes: [
                SpeedNode(sourceTime: clip.sourceStart, speed: best.factor),
            ])
        }

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex].duration = newDuration
        if let twin, twinIsAligned, let twinAt = copy.timeline.locate(twin.id) {
            tracks[twinAt.trackIndex].clips[twinAt.clipIndex].duration = newDuration
        }
        copy.timeline.tracks = tracks
        // `setSpeedRamp` píše i dvojčeti a hlídá zdroj i přechody
        // (rampovaný střih je zakázaný — přes přechod se nedopasovává).
        try copy.setSpeedRamp(clipID: clipID, ramp: newRamp)
        self = copy
        return result
    }

    /// „Rampa na úder": preset 1× → easeInOut → `slowSpeed`, kde zpomalení
    /// DOSEDNE přesně na dobu hudby nejblíž `frame` (typicky hlavě). Od
    /// doby dál jede klip zpomaleně; délka klipu se nemění (rampa mění
    /// spotřebu — vlastnost křivek od fáze 3).
    ///
    /// Kotvy se počítají ANALYTICKY: před rampou jede klip 1×, takže
    /// zdrojový začátek rampy je prostě čas na ose; easeInOut spotřebuje
    /// rozpětí = délka × (1 + slow)/2 (symetrie, tatáž vlastnost jako
    /// referenční hodnota Spiku 0: ramp 1→0,25→1 přes 5 s = 3,125 s).
    ///
    /// Výchozí `slowSpeed` je 0,25 zaražené o limit čistého zpomalení;
    /// zdroj bez rezervy snímků (30fps na 30fps ose) → `noCleanSlowdown`
    /// — automatika limit nepřekračuje, ruční editor se žlutou zónou ano.
    @discardableResult
    public mutating func rampClipToBeat(clipID: ClipID,
                                        near frame: Frames,
                                        slowSpeed: Double? = nil,
                                        rampFrames: Frames = Frames(15)) throws -> Frames {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        guard let sourceAsset = asset(clip.assetID) else {
            throw TimelineError.assetNotFound(clip.assetID)
        }
        guard !sourceAsset.isStill else { throw TimelineError.rampOnStillClip }
        guard sourceAsset.beatGrid == nil else { throw TimelineError.beatFitOnMusicClip }
        guard rampFrames.count >= 1 else { throw TimelineError.invalidSpeedRamp }

        let floor = cleanSpeedFloor(for: sourceAsset)
        let slow = slowSpeed ?? max(0.25, floor)
        guard slow < 1 - 1e-9 else { throw TimelineError.noCleanSlowdown }
        guard slow >= floor - 1e-9 else { throw TimelineError.noCleanSlowdown }

        let marks = beatMarks()
        guard !marks.isEmpty else { throw TimelineError.noBeatInReach(nearest: nil) }
        // Doba musí ležet uvnitř klipu i s místem na nájezd rampy před ní.
        let usable = marks.filter {
            $0.frame - rampFrames >= clip.timelineStart && $0.frame < clip.timelineEnd
        }
        guard let beat = usable.min(by: {
            abs($0.frame.count - frame.count) < abs($1.frame.count - frame.count)
        })?.frame else {
            let nearestOverall = marks.min {
                abs($0.frame.count - frame.count) < abs($1.frame.count - frame.count)
            }?.frame
            throw TimelineError.noBeatInReach(nearest: nearestOverall)
        }

        let fps = Double(timeline.frameRate)
        // Před rampou 1×: zdrojová kotva začátku rampy = čas na ose.
        let easeStartSource = clip.sourceStart.seconds
            + Double((beat - rampFrames - clip.timelineStart).count) / fps
        let easeSpan = Double(rampFrames.count) / fps * (1 + slow) / 2
        let ramp = SpeedRamp(nodes: [
            SpeedNode(sourceTime: SourceTime(seconds: easeStartSource),
                      speed: 1.0, easeToNext: .easeInOut),
            SpeedNode(sourceTime: SourceTime(seconds: easeStartSource + easeSpan),
                      speed: slow),
        ])
        try setSpeedRamp(clipID: clipID, ramp: ramp)
        return beat
    }
}
