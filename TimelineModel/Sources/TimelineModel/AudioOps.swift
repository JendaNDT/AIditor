//
//  AudioOps.swift
//  Projekt AIditor — TimelineModel
//
//  Fáze 7, modul 2: hlasitost a mute zvukové stopy. Mix je vlastnost
//  STOPY, ne klipu — Alena míchá „řeč proti hudbě" (A1 proti A2),
//  ne klip proti klipu. Per-klip obálky můžou přijít později, tohle
//  jim nestojí v cestě.
//
//  Hodnoty žijí v `Track.audio` (`AudioSettings`), takže se vezou
//  v projektu, undo snapshotech i `ProjectFile` zadarmo — testy to hlídají.
//

import Foundation

extension Project {

    /// Rozsah hlasitosti stopy: 0 až 2× (=+6 dB). Horní mez je vědomé
    /// omezení UI — hlubší zásahy patří do budoucího audio inspektoru,
    /// posuvník v hlavičce stopy má být bezpečný.
    public static let trackVolumeRange = 0.0...2.0

    /// Nastaví hlasitost zvukové stopy. Hodnota se zařezává do
    /// `trackVolumeRange` — posuvník nemá jak poslat nesmysl, ale model
    /// se nespoléhá na slušnost volajícího.
    public mutating func setTrackVolume(trackID: TrackID, volume: Double) throws {
        try updateAudioSettings(trackID: trackID) {
            $0.volume = min(max(volume, Self.trackVolumeRange.lowerBound),
                            Self.trackVolumeRange.upperBound)
        }
    }

    public mutating func setTrackMuted(trackID: TrackID, isMuted: Bool) throws {
        try updateAudioSettings(trackID: trackID) { $0.isMuted = isMuted }
    }

    private mutating func updateAudioSettings(
        trackID: TrackID, _ change: (inout AudioSettings) -> Void) throws {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
            throw TimelineError.trackNotFound(trackID)
        }
        let kind = timeline.tracks[index].kind
        guard kind == .audio else {
            throw TimelineError.wrongTrackKind(expected: .audio, got: kind)
        }
        var settings = timeline.tracks[index].audio ?? AudioSettings()
        change(&settings)
        timeline.tracks[index].audio = settings
    }

    /// Účinná hlasitost pro mix: mute = 0, jinak volume. Jediné místo,
    /// kde se ta dvojice skládá — přehrávání i export ji čtou odsud,
    /// aby nemohly interpretovat mute každý jinak.
    public func effectiveVolume(of track: Track) -> Double {
        guard track.kind == .audio, let audio = track.audio else { return 1.0 }
        return audio.isMuted ? 0.0 : audio.volume
    }
}

// MARK: - Zvukové fade na klipu (fáze 16)

/// Nájezd a dojezd zvuku na hranách klipu, ve snímcích osy. Nula = bez
/// fade; obě hodnoty se vejdou do klipu (vymáhá `setAudioFades`).
/// Trim smí klip pod součet fade zkrátit — kompozice délky poctivě
/// zařeže (`effectiveAudioFades`), model kvůli tomu nepřepisuje šest
/// trim operací.
public struct AudioFades: Hashable, Codable, Sendable {
    public var fadeIn: Frames
    public var fadeOut: Frames

    public init(fadeIn: Frames = .zero, fadeOut: Frames = .zero) {
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    public var isEmpty: Bool { fadeIn <= .zero && fadeOut <= .zero }
}

extension Project {

    /// Nastaví (nebo `nil` smaže) fade klipu. Jen na zvukové stopě —
    /// fade je volume rampa v mixu a obraz žádnou hlasitost nemá
    /// (zatmívačku obrazu dělá přechod). Prázdné fade se ukládají
    /// jako `nil`, ať se projekty zbytečně nenafukují.
    public mutating func setAudioFades(clipID: ClipID, _ fades: AudioFades?) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
        var stored = fades
        if let fades {
            guard timeline.tracks[at.trackIndex].kind == .audio else {
                throw TimelineError.wrongTrackKind(expected: .audio,
                                                   got: timeline.tracks[at.trackIndex].kind)
            }
            guard fades.fadeIn >= .zero, fades.fadeOut >= .zero,
                  fades.fadeIn + fades.fadeOut <= clip.duration else {
                throw TimelineError.invalidAudioFades(maxTotal: clip.duration)
            }
            if fades.isEmpty { stored = nil }
        }
        var tracks = timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex].audioFades = stored
        timeline.tracks = tracks
    }

    /// Fade zařezané do AKTUÁLNÍ délky klipu — jediné místo, odkud je
    /// čte kompozice. Trim pod součet fade není chyba modelu; tady se
    /// dojezd zkrátí o to, co nájezd nechá.
    public func effectiveAudioFades(of clip: Clip) -> AudioFades? {
        guard let fades = clip.audioFades, !fades.isEmpty else { return nil }
        let fadeIn = min(max(fades.fadeIn, .zero), clip.duration)
        let fadeOut = min(max(fades.fadeOut, .zero), clip.duration - fadeIn)
        let clamped = AudioFades(fadeIn: fadeIn, fadeOut: fadeOut)
        return clamped.isEmpty ? nil : clamped
    }
}

extension Timeline {

    /// Kopie s výchozím mixem na všech zvukových stopách. Odpovídá na
    /// otázku „změnilo se něco KROMĚ mixu?": kompozice přehrávače se při
    /// změně hlasitosti nesmí přestavovat (výměna player itemu zastaví
    /// přehrávání zrovna ve chvíli, kdy uživatel míchá poslechem) —
    /// stačí jí vyměnit `audioMix`. Porovnání těchhle kopií to rozhodne.
    public func withDefaultAudioSettings() -> Timeline {
        var copy = self
        for index in copy.tracks.indices where copy.tracks[index].kind == .audio {
            copy.tracks[index].audio = AudioSettings()
        }
        return copy
    }
}
