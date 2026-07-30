//
//  EditList.swift
//  Projekt AIditor / ProbeKit
//
//  Edit list stopy. Sdílené — sonda ho hlásí, nástroj na zploštění se podle
//  něj musí zařídit, protože každý testovací klip zahazuje prvních 44 ms zvuku.
//

import AVFoundation
import CoreMedia
import Foundation

/// Jeden segment stopy: mapování z časové osy médií na časovou osu stopy.
public struct SegmentInfo: Sendable {
    public let index: Int
    public let isEmpty: Bool
    public let mapping: CMTimeMapping

    public init(index: Int, isEmpty: Bool, mapping: CMTimeMapping) {
        self.index = index
        self.isEmpty = isEmpty
        self.mapping = mapping
    }

    /// Poměr `source.duration / target.duration`.
    ///
    /// 1,0 = přehrává se v původní rychlosti. 4,0 = do stopy se vejde čtyřnásobek
    /// zdrojového času, takže se přehrává 4× zpomaleně.
    public var rate: Double? {
        guard !isEmpty else { return nil }
        let target = mapping.target.duration.seconds
        let source = mapping.source.duration.seconds
        guard target > 0, source.isFinite, target.isFinite else { return nil }
        return source / target
    }
}

/// Souhrn edit listu stopy.
public struct EditListInfo: Sendable {
    public let segments: [SegmentInfo]

    public init(segments: [SegmentInfo]) {
        self.segments = segments
    }

    /// Postaví souhrn ze segmentů stopy.
    public init(track segments: [AVAssetTrackSegment]) {
        self.segments = segments.enumerated().map { index, segment in
            SegmentInfo(index: index, isEmpty: segment.isEmpty, mapping: segment.timeMapping)
        }
    }

    /// Je mapování triviální, tedy jeden neprázdný segment 1:1 bez posunu?
    public var isIdentity: Bool {
        guard segments.count == 1, let seg = segments.first, !seg.isEmpty else { return false }
        guard let rate = seg.rate, abs(rate - 1.0) < 1e-6 else { return false }
        return seg.mapping.source.start == seg.mapping.target.start
    }

    /// Výsledná rychlost, pokud ji lze vyjádřit jedním číslem.
    public var overallRate: Double? {
        let rates = segments.compactMap(\.rate)
        guard let first = rates.first else { return nil }
        return rates.allSatisfy { abs($0 - first) < 1e-6 } ? first : nil
    }

    public var hasEmptySegments: Bool { segments.contains(where: \.isEmpty) }

    /// Kde v médiích začíná první skutečně prezentovaný vzorek.
    ///
    /// U AAC je to typicky nenulové — kodér si na začátek přidá priming vzorky,
    /// které se nemají přehrát, a edit list je odřízne. Kdo edit list ignoruje
    /// a čte syrové vzorky, dostane zvuk posunutý o tenhle offset.
    public var sourceStartOffset: CMTime? {
        segments.first(where: { !$0.isEmpty })?.mapping.source.start
    }

    /// Kde na časové ose stopy začíná první prezentovaný vzorek.
    /// Nenulové znamená, že stopa začíná mezerou (prázdný edit).
    public var targetStartOffset: CMTime? {
        segments.first(where: { !$0.isEmpty })?.mapping.target.start
    }
}
