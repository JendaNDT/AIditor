//
//  AudioOps.swift
//  Projekt Krása — TimelineModel
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
