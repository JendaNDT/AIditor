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
