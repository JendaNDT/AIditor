//
//  Layout.swift
//  TimelineModel — Projekt Krása
//
//  Rozvržení viditelných klipů a rozhodnutí o recyklaci vrstev.
//  Krok 4 z `FAZE_2_VIEW.md`, sekce 2.4.
//
//  Recyklace vrstev je místo, kde v editorech vznikají nejotravnější chyby:
//  klip zůstane viset po smazání, dva klipy sdílí jednu vrstvu, po zoomu se
//  vrstva nepřepočítá. Všechny jsou to chyby v MNOŽINOVÉ logice, ne v kreslení
//  — proto se rozhoduje tady, kde na to jsou testy, a ne ve view.
//
//  Do view zbývá jediná smyčka: vezmi `placements`, spočítej `diff` proti
//  vrstvám, které právě visí, odpoj `toRecycle`, připoj `toMount` z fondu
//  a VŠEM viditelným přepiš rámec. Deset řádků, nedá se v nich ztratit.
//

import Foundation

/// Rozdíl mezi tím, co na ose visí, a tím, co na ní má viset.
public struct LayerDiff: Hashable, Sendable {
    /// Připojit z fondu — na ose je nově vidět.
    public let toMount: [ClipID]
    /// Vrátit do fondu — odscrolloval, smazali ho, nebo se odzoomoval pryč.
    public let toRecycle: [ClipID]
    /// Zůstává viset. Rámec se mu přepíše VŽDY, ne jen „když se změnil":
    /// diff dostává jen množinu ID, takže starý rámec nezná — a zápis rámce
    /// s vypnutými akcemi je levnější než účetnictví, které by ho ušetřilo.
    public let toUpdate: [ClipID]

    public init(toMount: [ClipID], toRecycle: [ClipID], toUpdate: [ClipID]) {
        self.toMount = toMount
        self.toRecycle = toRecycle
        self.toUpdate = toUpdate
    }

    /// Nic k práci — view nemusí ani otevírat `CATransaction`.
    public var isEmpty: Bool {
        toMount.isEmpty && toRecycle.isEmpty && toUpdate.isEmpty
    }
}

/// Čisté funkce rozvržení: z projektu, geometrie a scrollu spočítají, KTERÉ
/// klipy jsou vidět a KDE přesně leží. Žádný stav, žádný AppKit.
public enum TimelineLayout {

    /// Umístění jednoho klipu na obrazovce, v souřadnicích dokumentu
    /// (počátek vlevo nahoře — view je `isFlipped`).
    public struct Placement: Hashable, Sendable {
        public let clipID: ClipID
        public let trackID: TrackID
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public let isSelected: Bool

        public init(clipID: ClipID, trackID: TrackID,
                    x: Double, y: Double, width: Double, height: Double,
                    isSelected: Bool) {
            self.clipID = clipID
            self.trackID = trackID
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.isSelected = isSelected
        }
    }

    /// Rozvržení klipů viditelných v okně.
    ///
    /// Pořadí je deterministické: stopy odshora dolů, uvnitř stopy klipy
    /// zleva doprava. Viditelnost hledá `visibleClips` binárním půlením,
    /// takže cena roste s počtem VIDITELNÝCH klipů, ne všech.
    ///
    /// `overscanPoints` (výchozí 200) nechává klipy existovat už kousek za
    /// hranou okna, aby při scrollování nenaskakovaly — stejná hodnota jako
    /// ve `visibleFrameRange`.
    public static func placements(project: Project,
                                  geometry: TimelineGeometry,
                                  scrollX: Double,
                                  width: Double,
                                  selection: Set<ClipID> = [],
                                  overscanPoints: Double = 200) -> [Placement] {
        guard width > 0 else { return [] }
        let range = geometry.visibleFrameRange(scrollX: scrollX, width: width,
                                               overscanPoints: overscanPoints)
        let timeline = project.timeline

        var out: [Placement] = []
        for (index, track) in timeline.tracks.enumerated() {
            let y = geometry.y(ofTrackAt: index, in: timeline)
            let height = geometry.height(of: track.kind)

            for clip in geometry.visibleClips(on: track, in: range) {
                out.append(Placement(clipID: clip.id,
                                     trackID: track.id,
                                     x: geometry.x(for: clip.timelineStart),
                                     y: y,
                                     width: geometry.width(of: clip.duration),
                                     height: height,
                                     isSelected: selection.contains(clip.id)))
            }
        }
        return out
    }

    /// Rozhodnutí o recyklaci: co připojit, co vrátit do fondu, co jen přepsat.
    ///
    /// Záruky, na kterých view stojí (a testy je vymáhají):
    /// - `toMount ∪ toUpdate` = přesně ID z `next`, každé právě jednou,
    ///   v pořadí `next` — smyčka ve view může indexovat `next` souběžně.
    /// - `toRecycle` = `previous` minus ID z `next`, seřazené podle
    ///   `rawValue`. Množina nemá pořadí a nechat ho na iterátoru by
    ///   znamenalo nedeterministický výstup — stejný vstup musí dát stejný
    ///   výsledek, jinak se testy nedají psát.
    /// - Žádné ID není ve dvou seznamech zároveň.
    public static func diff(previous: Set<ClipID>, next: [Placement]) -> LayerDiff {
        var toMount: [ClipID] = []
        var toUpdate: [ClipID] = []
        var nextIDs = Set<ClipID>()
        nextIDs.reserveCapacity(next.count)

        for placement in next {
            // Duplicitní ID by znamenalo dva klipy s jednou vrstvou — model
            // ho invarianty nepustí, ale diff na tom nesmí stavět mlčky.
            guard nextIDs.insert(placement.clipID).inserted else { continue }
            if previous.contains(placement.clipID) {
                toUpdate.append(placement.clipID)
            } else {
                toMount.append(placement.clipID)
            }
        }

        let toRecycle = previous.subtracting(nextIDs)
            .sorted { $0.rawValue < $1.rawValue }

        return LayerDiff(toMount: toMount, toRecycle: toRecycle, toUpdate: toUpdate)
    }
}
