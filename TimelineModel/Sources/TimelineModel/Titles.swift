//
//  Titles.swift
//  TimelineModel — Projekt Krása
//
//  Grafické titulky na stopě T1 (fáze 11): jména, datum a místo, kapitoly,
//  závěrečné poděkování.
//
//  Titulek NENÍ `Clip`. Nemá asset, zdrojový čas, rychlostní křivku ani
//  vazbu na zvuk — nacpat ho do `Clip` by znamenalo udělat `assetID`
//  volitelné a každé místo v projektu by navěky řešilo `nil`. Vlastní typ
//  s vlastním úložištěm na stopě je týž vzorec, který se osvědčil
//  u přechodů (`Transition`).
//
//  Co titulek s klipem SDÍLÍ, je chování na ose: pozice a délka ve snímcích,
//  dotyk není překryv, seřazenost na stopě. Pravidla vymáhají operace níže
//  a `validate()` — stejná dělba jako u klipů.
//
//  Titulky z řeči (fáze 8) sem NEPATŘÍ: ty žijí na assetu (`transcript`)
//  a na osu se jen promítají. Pruh T1 je bude KRESLIT (modul UI), ale
//  modelové objekty z nich nedělá — dvojí pravda o témže textu by se rozešla.
//

import Foundation

// MARK: - Typy

public struct TitleClipID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

/// Šablona určuje vzhled (písmo, velikost, umístění na plátně). Model nese
/// jen JMÉNO šablony — konkrétní fonty a velikosti jsou věc vykreslení,
/// modul náhledu/exportu si je přeloží. České popisky dostane UI.
public enum TitleTemplate: String, Codable, Sendable, CaseIterable {
    /// Prostý text — výchozí, bez ambicí.
    case plain
    /// Jména novomanželů — velký titul přes střed.
    case names
    /// Datum a místo — menší doprovodný řádek.
    case dateAndPlace
    /// Nadpis kapitoly (obřad, hostina, první tanec…).
    case chapter
    /// Závěrečné poděkování — text přes tmavé pozadí na konci filmu.
    case thanks
}

/// Vodorovné zarovnání textu v rámci šablony.
public enum TitleAlignment: String, Codable, Sendable, CaseIterable {
    case leading, center, trailing
}

/// Titulkový klip na stopě T1.
///
/// Zapisuj přes `Project.addTitle` / `moveTitle` / `trimTitleStart` /
/// `trimTitleEnd` / `setTitleText` a spol. — operace hlídají překryvy
/// a meze, které struktura sama neunese.
public struct TitleClip: Identifiable, Hashable, Codable, Sendable {
    public let id: TitleClipID
    public var text: String
    public var template: TitleTemplate
    public var alignment: TitleAlignment
    /// Kde titulek začíná NA OSE.
    public var timelineStart: Frames
    /// Jak dlouho trvá NA OSE. Žádný zdroj nemá, takže délku nic neomezuje.
    public var duration: Frames

    init(id: TitleClipID = TitleClipID(),
         text: String,
         template: TitleTemplate,
         alignment: TitleAlignment,
         timelineStart: Frames,
         duration: Frames) {
        self.id = id
        self.text = text
        self.template = template
        self.alignment = alignment
        self.timelineStart = timelineStart
        self.duration = duration
    }

    /// Exkluzivní konec — stejná sémantika jako u `Clip`.
    public var timelineEnd: Frames { timelineStart + duration }

    /// Dotyk (konec == začátek) překryv NENÍ, stejně jako u klipů.
    public func overlaps(_ other: TitleClip) -> Bool {
        timelineStart < other.timelineEnd && other.timelineStart < timelineEnd
    }

    public func contains(frame: Frames) -> Bool {
        frame >= timelineStart && frame < timelineEnd
    }
}

// MARK: - Dotazy

extension Timeline {

    /// Najde titulek napříč stopami.
    public func locateTitle(_ id: TitleClipID) -> (trackIndex: Int, titleIndex: Int)? {
        for (t, track) in tracks.enumerated() {
            if let i = track.index(ofTitle: id) { return (t, i) }
        }
        return nil
    }

    public func titleClip(_ id: TitleClipID) -> TitleClip? {
        guard let at = locateTitle(id) else { return nil }
        return tracks[at.trackIndex].titles[at.titleIndex]
    }
}

// MARK: - Operace

extension Project {

    /// Výchozí délka nového titulku: 4 sekundy osy. Dost na přečtení dvou
    /// řádků, málo na to, aby překážel — UI ji stejně nechá přetáhnout.
    public var defaultTitleDuration: Frames { Frames(4 * timeline.frameRate) }

    /// Vyrobí titulek. **Model razí ID i výchozí délku, ne UI** — stejné
    /// pravidlo jako `makeClip`: jinak je jedinečnost ID nevymahatelná.
    /// Titulek zatím nikde neleží; na stopu ho dává `addTitle`.
    public func makeTitle(text: String,
                          template: TitleTemplate = .plain,
                          alignment: TitleAlignment = .center,
                          at start: Frames = .zero,
                          duration: Frames? = nil) throws -> TitleClip {
        let d = duration ?? defaultTitleDuration
        guard d.count > 0 else { throw TimelineError.zeroLength }
        guard start.count >= 0 else { throw TimelineError.negativePosition }
        return TitleClip(text: text, template: template, alignment: alignment,
                         timelineStart: start, duration: d)
    }

    /// Ověří, že titulek smí na stopu — druh stopy a překryv s ostatními
    /// titulky. Stejná stavba jako `checkPlacement` u klipů, včetně
    /// `nearestLegal` v chybě, na kterém UI zarazí tažení.
    private func checkTitlePlacement(_ title: TitleClip, on track: Track,
                                     ignoring: TitleClipID? = nil) throws {
        guard track.kind == .title else {
            throw TimelineError.wrongTrackKind(expected: .title, got: track.kind)
        }
        guard title.duration.count > 0 else { throw TimelineError.zeroLength }
        guard title.timelineStart.count >= 0 else { throw TimelineError.negativePosition }

        for other in track.titles where other.id != ignoring && other.id != title.id {
            if title.overlaps(other) {
                let before = other.timelineStart - title.duration
                let after = other.timelineEnd
                let nearest = abs((before - title.timelineStart).count) <= abs((after - title.timelineStart).count)
                    ? before : after
                throw TimelineError.titleWouldOverlap(with: other.id,
                                                      nearestLegal: Frames(max(0, nearest.count)))
            }
        }
    }

    public mutating func addTitle(_ title: TitleClip, onTrack trackID: TrackID) throws {
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        try checkTitlePlacement(title, on: timeline.tracks[ti])
        var tracks = timeline.tracks
        tracks[ti].insertSorted(title)
        timeline.tracks = tracks
    }

    public mutating func removeTitle(id: TitleClipID) throws {
        guard let at = timeline.locateTitle(id) else { throw TimelineError.titleNotFound(id) }
        var tracks = timeline.tracks
        tracks[at.trackIndex].titles.remove(at: at.titleIndex)
        timeline.tracks = tracks
    }

    /// Přesune titulek — v rámci stopy, nebo na jinou titulkovou stopu.
    public mutating func moveTitle(id: TitleClipID, toTrack trackID: TrackID? = nil,
                                   start: Frames) throws {
        guard let at = timeline.locateTitle(id) else { throw TimelineError.titleNotFound(id) }
        let sourceTrackID = timeline.tracks[at.trackIndex].id
        let targetID = trackID ?? sourceTrackID
        guard let ti = timeline.index(of: targetID) else { throw TimelineError.trackNotFound(targetID) }

        let title = timeline.tracks[at.trackIndex].titles[at.titleIndex]
        if targetID == sourceTrackID && title.timelineStart == start { return }

        var moved = title
        moved.timelineStart = start

        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].titles.remove(at: at.titleIndex)
        copy.timeline.tracks = tracks
        try copy.checkTitlePlacement(moved, on: copy.timeline.tracks[ti])
        tracks = copy.timeline.tracks
        tracks[ti].insertSorted(moved)
        copy.timeline.tracks = tracks
        self = copy
    }

    /// Posune začátek titulku. Žádný zdrojový materiál neexistuje, takže
    /// jediné meze jsou sousedi, nula osy a nenulová délka.
    public mutating func trimTitleStart(id: TitleClipID, to newStart: Frames) throws {
        guard let at = timeline.locateTitle(id) else { throw TimelineError.titleNotFound(id) }
        let title = timeline.tracks[at.trackIndex].titles[at.titleIndex]

        guard newStart < title.timelineEnd else { throw TimelineError.zeroLength }
        guard newStart.count >= 0 else { throw TimelineError.negativePosition }

        var trimmed = title
        trimmed.timelineStart = newStart
        trimmed.duration = title.timelineEnd - newStart
        try replaceTitle(at: at, with: trimmed)
    }

    /// Posune konec titulku.
    public mutating func trimTitleEnd(id: TitleClipID, to newEnd: Frames) throws {
        guard let at = timeline.locateTitle(id) else { throw TimelineError.titleNotFound(id) }
        let title = timeline.tracks[at.trackIndex].titles[at.titleIndex]

        guard newEnd > title.timelineStart else { throw TimelineError.zeroLength }

        var trimmed = title
        trimmed.duration = newEnd - title.timelineStart
        try replaceTitle(at: at, with: trimmed)
    }

    /// Výměna na místě s kontrolou umístění — společný konec obou trimů.
    private mutating func replaceTitle(at: (trackIndex: Int, titleIndex: Int),
                                       with title: TitleClip) throws {
        var copy = self
        var tracks = copy.timeline.tracks
        tracks[at.trackIndex].titles.remove(at: at.titleIndex)
        copy.timeline.tracks = tracks
        try copy.checkTitlePlacement(title, on: copy.timeline.tracks[at.trackIndex])
        tracks = copy.timeline.tracks
        tracks[at.trackIndex].insertSorted(title)
        copy.timeline.tracks = tracks
        self = copy
    }

    // MARK: Obsah titulku — pro inspektor

    public mutating func setTitleText(id: TitleClipID, _ text: String) throws {
        try mutateTitle(id: id) { $0.text = text }
    }

    public mutating func setTitleTemplate(id: TitleClipID, _ template: TitleTemplate) throws {
        try mutateTitle(id: id) { $0.template = template }
    }

    public mutating func setTitleAlignment(id: TitleClipID, _ alignment: TitleAlignment) throws {
        try mutateTitle(id: id) { $0.alignment = alignment }
    }

    private mutating func mutateTitle(id: TitleClipID,
                                      _ change: (inout TitleClip) -> Void) throws {
        guard let at = timeline.locateTitle(id) else { throw TimelineError.titleNotFound(id) }
        var tracks = timeline.tracks
        change(&tracks[at.trackIndex].titles[at.titleIndex])
        timeline.tracks = tracks
    }

    // MARK: Stopa T1

    /// Vrátí první titulkovou stopu; když žádná není, přidá ji na konec.
    /// Projekty uložené před fází 11 T1 nemají — tudy si ji UI vyrobí,
    /// aniž by muselo vědět, jak stopa vzniká.
    @discardableResult
    public mutating func ensureTitleTrack(named name: String = "T1") -> TrackID {
        if let existing = timeline.tracks.first(where: { $0.kind == .title }) {
            return existing.id
        }
        return addTrack(kind: .title, name: name)
    }
}
