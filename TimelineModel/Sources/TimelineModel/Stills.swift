//
//  Stills.swift
//  TimelineModel — Projekt Krása
//
//  Fotky na ose a Ken Burns (fáze 12).
//
//  Fotka je asset bez časování (`Asset.isStill`): klip z ní zdroj
//  NEspotřebovává a jeho délka není ničím omezená — stejné chování jako
//  titulek, jen na obrazové stopě. Větve jsou VÝHRADNĚ ve čtyřech
//  schválených místech zdrojové matematiky (`sourceConsumption`,
//  `sourceOffset`, `remainingSourceFrames`, `availableSourceFramesBefore`)
//  a v `makeClip` — všechno ostatní (trim, split, přesun, přechody,
//  interakce) z nich meze dostává zadarmo.
//
//  Ken Burns = počáteční a koncový VÝŘEZ fotky, oba v normalizovaných
//  souřadnicích (0–1 vůči obrazu fotky). Kompozice z nich udělá lineární
//  `TransformRamp` (plán fáze 12: pohyb je pomalý a krátký, lineár stačí).
//  Rychlostní křivka na fotce nemá smysl (co by zpomalovala?) a je
//  ZAKÁZANÁ — freeze frame se dělá fotkou, ne nulovou rychlostí
//  (invertibilita mapování v `SpeedRampEngine` je nedotknutelná).
//

import Foundation

// MARK: - Typy

/// Obdélník v normalizovaných souřadnicích obrazu: (0,0) levý horní roh,
/// (1,1) pravý dolní. Vlastní typ, ne `CGRect` — model se překládá i bez
/// CoreGraphics (vzorec `CanvasSize`).
public struct NormalizedRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Celý obraz.
    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    /// Použitelný výřez: leží v obraze a má rozumnou velikost. Spodní mez
    /// 5 % hlídá degenerované zoomy — výřez menší než dvacetina obrazu je
    /// rozmazaná kaše, ne záběr.
    public var isUsableCrop: Bool {
        x >= 0 && y >= 0
            && width >= 0.05 && height >= 0.05
            && x + width <= 1 && y + height <= 1
    }
}

/// Ken Burns: odkud kam se výřez plynule veze přes trvání klipu.
public struct KenBurns: Hashable, Codable, Sendable {
    public var start: NormalizedRect
    public var end: NormalizedRect

    public init(start: NormalizedRect, end: NormalizedRect) {
        self.start = start
        self.end = end
    }

    public var isUsable: Bool { start.isUsableCrop && end.isUsableCrop }
}

// MARK: - Operace

extension Project {

    /// Nastaví (nebo `nil` smaže) Ken Burns na klipu fotky. Na klipu videa
    /// se odmítne — plán fáze 12 dává pohyb výřezu jen fotkám; povolit ho
    /// videu jde později bez změny formátu.
    public mutating func setKenBurns(clipID: ClipID, _ kenBurns: KenBurns?) throws {
        guard let at = timeline.locate(clipID) else { throw TimelineError.clipNotFound(clipID) }
        if let kenBurns {
            let clip = timeline.tracks[at.trackIndex].clips[at.clipIndex]
            guard asset(clip.assetID)?.isStill == true else {
                throw TimelineError.kenBurnsNeedsStill
            }
            guard kenBurns.isUsable else { throw TimelineError.invalidKenBurns }
        }
        var tracks = timeline.tracks
        tracks[at.trackIndex].clips[at.clipIndex].kenBurns = kenBurns
        timeline.tracks = tracks
    }
}
