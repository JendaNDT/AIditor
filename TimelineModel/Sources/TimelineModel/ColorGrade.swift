//
//  ColorGrade.swift
//  TimelineModel — Projekt AIditor
//
//  Barevné presety (fáze 13). Model nese JEN volbu: který preset a jak
//  silně. Co preset znamená opticky (které CIFiltry s jakými parametry),
//  ví až kompoziční vrstva v aplikaci — model se překládá bez CoreImage
//  a vzhled presetu jde ladit bez zásahu do formátu souboru.
//
//  Preset patří KLIPU, ne stopě ani projektu (plán fáze 13: „per klip,
//  intenzita 0–100 %"). Sedí jen na klipu obrazové stopy — fotka ano
//  (je to obrazový klip), zvukový klip ne. Split/duplicate ho dědí
//  s kopií struktury, stejně jako Ken Burns.
//

import Foundation

// MARK: - Typy

/// Pojmenovaný barevný vzhled. Syrové hodnoty jsou SMLOUVA formátu
/// souboru — přejmenovat case jde, rawValue ne.
public enum ColorPreset: String, Codable, Sendable, CaseIterable {
    /// Jemný svatební vzhled.
    case softWedding
    /// Teplý film.
    case warmFilm
    /// Čistá pleť.
    case cleanSkin
    /// Černobílá.
    case blackAndWhite
}

/// Barevný preset klipu: který a jak silně.
public struct ColorGrade: Hashable, Codable, Sendable {
    public var preset: ColorPreset
    /// Síla efektu 0–1 (UI ukazuje 0–100 %). Nula je legální — obraz beze
    /// změny, ale volba presetu zůstává; uživatel si posuvník stáhne a zase
    /// vytáhne, aniž by o výběr přišel.
    public var intensity: Double

    public init(preset: ColorPreset, intensity: Double = 1.0) {
        self.preset = preset
        self.intensity = intensity
    }

    /// Použitelná intenzita: konečné číslo v 0–1.
    public var isUsable: Bool {
        intensity.isFinite && intensity >= 0 && intensity <= 1
    }
}

// MARK: - Operace

extension Project {

    /// Nastaví (nebo `nil` smaže) barevný preset klipu. Jen na obrazové
    /// stopě — zvukový klip barvy nemá; fotka je obrazový klip a preset
    /// dostat smí.
    public mutating func setColorGrade(clipID: ClipID, _ grade: ColorGrade?) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        if let grade {
            guard timeline.tracks[at.trackIndex].kind == .video else {
                throw TimelineError.colorGradeNeedsVideoTrack
            }
            guard grade.isUsable else { throw TimelineError.invalidColorGrade }
        }
        var tracks = timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex].colorGrade = grade
        timeline.tracks = tracks
    }
}
