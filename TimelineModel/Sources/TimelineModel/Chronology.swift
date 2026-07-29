//
//  Chronology.swift
//  TimelineModel — Projekt Krása
//
//  Chronologie materiálu a rozsah exportu (fáze 17, modul 3).
//
//  Svatba je chronologická UDÁLOST. Dokud jede jedna kamera, projde řazení
//  podle jména (název souboru bývá časové razítko) — jenže druhá kamera
//  a telefony hostů mají jiné jmenné konvence a materiál se rozsype.
//  Proto se řadí podle času natočení, a kde ten chybí, řekne se to.
//

import Foundation

extension Project {

    /// Čas natočení klipu = čas jeho assetu.
    public func creationDate(of clipID: ClipID) -> Date? {
        guard let clip = timeline.clip(clipID) else { return nil }
        return asset(clip.assetID)?.creationDate
    }

    /// Přeskládá klipy stopy podle času natočení, těsně za sebe.
    ///
    /// Začíná se tam, kde začínal PRVNÍ klip stopy — uspořádání nemá osu
    /// posouvat k nule, když si uživatel nechal vpředu místo na titulek.
    ///
    /// **Mezery zanikají.** Uspořádat chronologicky znamená „poskládej mi
    /// to za sebe v pořadí, jak se to stalo"; ponechat mezery na místě by
    /// dalo pořadí bez souvislosti s původními dírami.
    ///
    /// **Svázaná dvojčata jdou s klipem** — o tolik, o kolik se posunul on.
    /// Bez toho by se obraz rozešel se zvukem, což je nejdražší chyba,
    /// jakou tahle operace umí udělat.
    ///
    /// Klipy BEZ času natočení zůstávají v dosavadním pořadí na KONCI —
    /// hádat se nemá, a schovat je doprostřed by vypadalo jako chyba.
    /// Vrací počet takových klipů, aby to UI mohlo přiznat.
    @discardableResult
    public mutating func arrangeChronologically(trackID: TrackID) throws -> Int {
        guard let ti = timeline.index(of: trackID) else { throw TimelineError.trackNotFound(trackID) }
        let clips = timeline.tracks[ti].clips
        guard clips.count > 1 else { return 0 }

        // Stabilní řazení: klipy se známým časem podle něj, ostatní za ně
        // v dosavadním pořadí. `sorted` v Swiftu stabilní NENÍ, proto se
        // do klíče přidává původní index.
        let decorated = clips.enumerated().map { (index: $0.offset, clip: $0.element,
                                                  date: creationDate(of: $0.element.id)) }
        let sorted = decorated.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x == y ? a.index < b.index : x < y
            case (nil, _?): return false        // bez data až za ty s datem
            case (_?, nil): return true
            case (nil, nil): return a.index < b.index
            }
        }
        let undated = decorated.filter { $0.date == nil }.count

        // Nové pozice a posuny. Klip, který se nehne, dvojče netahá.
        var shifts: [ClipID: Frames] = [:]
        var cursor = clips[0].timelineStart
        for entry in sorted {
            let shift = cursor - entry.clip.timelineStart
            if shift.count != 0 { shifts[entry.clip.id] = shift }
            cursor = cursor + entry.clip.duration
        }
        guard !shifts.isEmpty else { return undated }

        var copy = self
        var tracks = copy.timeline.tracks
        for (i, track) in tracks.enumerated() {
            for (j, clip) in track.clips.enumerated() {
                // Posun buď vlastní, nebo zděděný od svázaného partnera.
                var shift = shifts[clip.id]
                if shift == nil, let link = clip.linkID {
                    shift = clips.first { $0.linkID == link && shifts[$0.id] != nil }
                        .flatMap { shifts[$0.id] }
                }
                if let shift { tracks[i].clips[j].timelineStart = clip.timelineStart + shift }
            }
            tracks[i].clips.sort { $0.timelineStart < $1.timelineStart }
        }
        copy.timeline.tracks = tracks

        // Atomické: přeskládání, které by vyrobilo překryv (na sousední
        // stopě leží něco, co s dvojčaty nesouvisí), se neprovede vůbec.
        if let violation = copy.validate().first {
            throw TimelineError.notJoinable(reason: "uspořádání by rozbilo osu (\(violation))")
        }
        // Přeskládáním zanikly původní střihy — přechody na nich jdou s nimi.
        copy.reconcileTransitions(pruneConflicts: true)
        self = copy
        return undated
    }

    /// Rozsah k exportu ve snímcích osy: zadaný výřez, ořezaný na délku
    /// projektu. Chybějící nebo obrácené body znamenají CELÝ projekt —
    /// export nikdy nesmí tiše vyrobit prázdný soubor.
    public func exportRange(inPoint: Frames?, outPoint: Frames?) -> Range<Frames> {
        let total = duration
        let whole = Frames.zero ..< total
        guard total.count > 0 else { return whole }

        let lower = Frames(Swift.max(0, Swift.min(inPoint?.count ?? 0, total.count)))
        let upper = Frames(Swift.max(0, Swift.min(outPoint?.count ?? total.count, total.count)))
        guard upper.count > lower.count else { return whole }
        return lower ..< upper
    }
}
