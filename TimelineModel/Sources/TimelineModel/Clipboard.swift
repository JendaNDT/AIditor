//
//  Clipboard.swift
//  TimelineModel — Projekt AIditor
//
//  Schránka osy (fáze 17, modul 2): kopírovat, vyjmout, vložit na hlavu.
//
//  ⚠️ HLAVNÍ PAST CELÉHO SOUBORU: SVÁZANÉ DVOJICE.
//  Obraz a zvuk jednoho záběru drží pohromadě sdílené `linkID`. Kdyby se
//  kopie vložila se STEJNOU vazbou, sdílely by ji tři klipy (originál,
//  kopie obrazu, kopie zvuku) a `validate()` ohlásí `brokenLink`. Vložení
//  proto každé skupině razí ČERSTVÝ `LinkID`.
//  Je to táž past, kterou už jednou chytil split svázaného páru (fáze 2).
//
//  Druhá půlka téhož pravidla: dvojice se kopíruje CELÁ, i když uživatel
//  vybral jen jednu její půlku — stejně jako se celá maže. Vložit půlku
//  záběru a druhou nechat na ose je vždycky chyba uživatele, ne záměr.
//

import Foundation

/// Jeden klip ve schránce.
///
/// Klip je tu jako ŠABLONA: jeho `id`, `linkID` ani `timelineStart`
/// vložení nepoužije — razí si vlastní. Zbytek (zdroj, délka, rampa,
/// Ken Burns, preset, fade) se přenáší beze změny.
public struct ClipboardItem: Hashable, Sendable {
    public var clip: Clip
    /// Odkud klip pochází. Vkládá se tam zpátky, pokud stopa pořád existuje
    /// a je téhož druhu — jinak by hudba z A2 přistála na A1 pod řečí.
    public var trackID: TrackID
    public var trackKind: TrackKind
    /// Posun od nejlevější hrany celého výběru. Vzájemná poloha klipů se
    /// vložením zachovává, jinak by se rozsypal střih i sync dvojic.
    public var offset: Frames

    public init(clip: Clip, trackID: TrackID, trackKind: TrackKind, offset: Frames) {
        self.clip = clip
        self.trackID = trackID
        self.trackKind = trackKind
        self.offset = offset
    }
}

/// Obsah schránky. Není `Codable` a do projektového souboru nepatří —
/// je to stav sezení, ne dokumentu.
public struct Clipboard: Hashable, Sendable {
    public var items: [ClipboardItem]

    public init(items: [ClipboardItem] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// Jak dlouhý úsek osy obsah zabere.
    public var duration: Frames {
        items.reduce(Frames.zero) { Frames(Swift.max($0.count, ($1.offset + $1.clip.duration).count)) }
    }
}

// MARK: - Kopie klipu

extension Clip {

    /// Kopie s NOVÝM `id`.
    ///
    /// ⚠️ JEDINÉ místo, kde se klip klonuje. `Clip` má dnes osm polí a při
    /// každé fázi přibylo jedno — split, duplicate i ocásek overwrite si
    /// kdysi stavěly kopii vlastním konstruktorem a fáze 13 v nich našla
    /// tři místa, kudy nový barevný preset tiše propadl. Kdo přidá pole,
    /// přidá ho sem; test `testCopiedCarriesEveryField` mu to připomene
    /// reflexí, ne vypsaným seznamem.
    public func copied(linkID: LinkID?, timelineStart: Frames) -> Clip {
        Clip(assetID: assetID,
             linkID: linkID,
             timelineStart: timelineStart,
             duration: duration,
             sourceStart: sourceStart,
             speedRamp: speedRamp,
             kenBurns: kenBurns,
             colorGrade: colorGrade,
             audioFades: audioFades)
    }
}

// MARK: - Kopírovat, vyjmout, vložit

extension Project {

    /// Sesbírá klipy do schránky. Projekt nemění.
    ///
    /// Výběr se rozšiřuje o svázaná dvojčata (vzorec mazání) a klipy, které
    /// už neexistují, se tiše přeskočí.
    public func clipboard(copying ids: Set<ClipID>) -> Clipboard {
        var wanted = ids
        for id in ids {
            for partner in linkedPartners(of: id) { wanted.insert(partner.id) }
        }

        var found: [(clip: Clip, track: Track)] = []
        for track in timeline.tracks {
            for clip in track.clips where wanted.contains(clip.id) {
                found.append((clip, track))
            }
        }
        guard let origin = found.map(\.clip.timelineStart).min() else { return Clipboard() }

        return Clipboard(items: found.map {
            ClipboardItem(clip: $0.clip,
                          trackID: $0.track.id,
                          trackKind: $0.track.kind,
                          offset: $0.clip.timelineStart - origin)
        })
    }

    /// Zkopíruje a smaže. Buď obojí, nebo nic.
    public mutating func cut(_ ids: Set<ClipID>) throws -> Clipboard {
        let board = clipboard(copying: ids)
        guard !board.isEmpty else { return board }
        var copy = self
        for item in board.items { try copy.remove(clipID: item.clip.id) }
        self = copy
        return board
    }

    /// Vloží obsah schránky tak, aby jeho začátek seděl na `frame`.
    ///
    /// **Atomické:** buď se vejde všechno, nebo se nevloží nic a operace
    /// hodí `wouldOverlap` s nejbližší legální pozicí. Tiché rozstrkávání
    /// po volných místech by rozbilo vzájemnou polohu klipů, a s ní sync
    /// obrazu se zvukem — přesně to, kvůli čemu se offsety uchovávají.
    ///
    /// Vrací ID vložených klipů, aby je UI mohlo rovnou vybrat.
    @discardableResult
    public mutating func paste(_ clipboard: Clipboard, at frame: Frames) throws -> Set<ClipID> {
        guard !clipboard.isEmpty else { return [] }
        guard frame.count >= 0 else { throw TimelineError.negativePosition }

        var copy = self
        // Čerstvá vazba pro každou původní skupinu. Osamocená půlka dvojice
        // (partner mezitím zmizel) vazbu nedostane — vazba na jeden klip
        // není vazba.
        var groupSizes: [LinkID: Int] = [:]
        for item in clipboard.items {
            if let link = item.clip.linkID { groupSizes[link, default: 0] += 1 }
        }
        var freshLinks: [LinkID: LinkID] = [:]
        for (link, size) in groupSizes where size > 1 { freshLinks[link] = LinkID() }

        var inserted = Set<ClipID>()
        for item in clipboard.items {
            let trackID = try targetTrack(for: item, in: copy)
            let link = item.clip.linkID.flatMap { freshLinks[$0] }
            let clip = item.clip.copied(linkID: link, timelineStart: frame + item.offset)
            try copy.insert(clip, onTrack: trackID)
            inserted.insert(clip.id)
        }
        self = copy
        return inserted
    }

    /// Kam klip patří: na svou původní stopu, pokud ještě žije a sedí druh;
    /// jinak na první stopu téhož druhu.
    private func targetTrack(for item: ClipboardItem, in project: Project) throws -> TrackID {
        if let track = project.timeline.tracks.first(where: { $0.id == item.trackID }),
           track.kind == item.trackKind {
            return track.id
        }
        if let track = project.timeline.tracks.first(where: { $0.kind == item.trackKind }) {
            return track.id
        }
        throw TimelineError.trackNotFound(item.trackID)
    }

    /// Vejde se schránka na dané místo? Pro zapínání položky menu — vkládání
    /// samo hází chybu s mezí, tohle je jen levný dotaz bez kopie projektu.
    public func canPaste(_ clipboard: Clipboard, at frame: Frames) -> Bool {
        guard !clipboard.isEmpty, frame.count >= 0 else { return false }
        for item in clipboard.items {
            guard let trackID = try? targetTrack(for: item, in: self),
                  let track = timeline.tracks.first(where: { $0.id == trackID }) else { return false }
            let start = frame + item.offset
            let end = start + item.clip.duration
            if track.clips.contains(where: { $0.timelineStart < end && start < $0.timelineEnd }) {
                return false
            }
        }
        return true
    }
}
