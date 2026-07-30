//
//  RampEditor.swift
//  TimelineModel — Projekt Krása
//
//  Logika editoru rychlostní křivky (fáze 3, modul 3). Do view patří jen
//  kreslení a předávání událostí — všechno, co má porovnatelnou návratovou
//  hodnotu, je tady: škála svislé osy, pozice uzlů, vzorek křivky, přidání
//  a mazání uzlů, tažení uzlu a mez čistého zpomalení pro žlutou zónu.
//
//  Vodorovná osa editoru = VÝSTUPNÍ snímky klipu [0, duration]. Ta je při
//  editaci stabilní (délka klipu na ose se křivkou nemění — mění se spotřeba
//  zdroje) a sedí na to, co uživatel vidí na timeline nad editorem. Uzly
//  jsou ale kotvené ve zdroji, takže se jejich výstupní pozice přepočítává
//  mapováním křivky.
//

import Foundation
import SpeedRampEngine

// MARK: - Svislá osa

/// Škála rychlosti: log₂ v rozsahu [minSpeed, maxSpeed]. Logaritmická
/// schválně — 0,25× a 4× jsou stejně daleko od 1× a půlení rychlosti je
/// všude stejný kus dráhy. Lineární škála by polovinu plochy věnovala
/// rychlostem nad 4×, které nikdo nepoužívá.
public struct RampEditorScale: Equatable, Sendable {
    public let minSpeed: Double
    public let maxSpeed: Double

    public init(minSpeed: Double = 0.125, maxSpeed: Double = 8.0) {
        precondition(minSpeed > 0 && maxSpeed > minSpeed)
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
    }

    /// Rysky mřížky. 1× je mezi nimi — kreslí se výrazněji, je to kotva oka.
    public static let gridSpeeds: [Double] = [0.25, 0.5, 1.0, 2.0, 4.0]

    public func clamp(_ speed: Double) -> Double {
        min(maxSpeed, max(minSpeed, speed))
    }

    /// Rychlost → poloha na svislé ose: 0 = minSpeed (dole), 1 = maxSpeed
    /// (nahoře). Na body si to převádí view — model o pixelech neví.
    public func unit(ofSpeed speed: Double) -> Double {
        let clamped = clamp(speed)
        return log2(clamped / minSpeed) / log2(maxSpeed / minSpeed)
    }

    public func speed(atUnit unit: Double) -> Double {
        let bounded = min(1, max(0, unit))
        return clamp(minSpeed * pow(maxSpeed / minSpeed, bounded))
    }
}

// MARK: - Čtení pro kreslení

/// Uzel křivky v souřadnicích editoru.
public struct RampEditorNode: Equatable, Sendable {
    public let index: Int
    /// Ofset od začátku klipu ve snímcích osy. Zlomkový — uzel kotvený ve
    /// zdroji obecně neleží na hranici výstupního snímku. Může být i mimo
    /// [0, duration], když trim odsunul okno klipu jinam na křivce.
    public let outputFrame: Double
    public let speed: Double
}

extension Project {

    /// Uzly křivky klipu pro kreslení. Prázdné = klip hraje 1× (žádná nebo
    /// nepoužitelná rampa) a editor kreslí jen vodorovnou čáru na 1×.
    public func rampEditorNodes(of clip: Clip) -> [RampEditorNode] {
        guard let model = clip.speedRamp, model.isUsable,
              let window = rampWindow(for: clip) else { return [] }
        let fps = Double(timeline.frameRate)
        return model.nodes.enumerated().map { index, node in
            let output = window.ramp.outputTime(atSource: node.sourceTime.seconds)
            return RampEditorNode(index: index,
                                  outputFrame: (output - window.t0) * fps,
                                  speed: node.speed)
        }
    }

    /// Rychlost v `samples` rovnoměrných bodech přes délku klipu — z toho
    /// view složí lomenou čáru křivky. Bez rampy samé jedničky.
    public func rampSpeedProfile(of clip: Clip, samples: Int) -> [Double] {
        let count = max(2, samples)
        guard let window = rampWindow(for: clip) else {
            return Array(repeating: 1.0, count: count)
        }
        let fps = Double(timeline.frameRate)
        let duration = Double(clip.duration.count) / fps
        return (0..<count).map { index in
            window.ramp.speed(atOutput: window.t0 + duration * Double(index) / Double(count - 1))
        }
    }

    /// Mez čistého zpomalení klipu: `výstupFps / zdrojFps` z NAMĚŘENÉ
    /// frekvence assetu (`nominalFrameRate` lže). Pod touhle rychlostí se
    /// snímky duplikují a zpomalení trhá — editor pod ní kreslí žlutou zónu.
    /// `nil`, když asset chybí nebo nemá platné měření.
    public func pureSlowdownLimit(of clip: Clip) -> Double? {
        guard let asset = asset(clip.assetID), asset.measuredFrameRate > 0 else { return nil }
        return Double(timeline.frameRate) / asset.measuredFrameRate
    }

    /// Podíl snímků klipu, které při exportu vyjdou jako DUPLIKÁT předchozího
    /// (0 = žádný, 0,375 = tři snímky z osmi).
    ///
    /// Vzorec je pravidlo projektu: průměr z `max(0, 1 − v(t) · zdrojFps /
    /// výstupFps)` přes délku klipu, tedy `max(0, 1 − v(t) / limit)`.
    /// Naměřeno na třech klipech, teorie sedí na desetinu procenta: u zdroje
    /// na úrovni výstupu dá klasický ramp `1 − průměrná rychlost` = 37,5 %.
    ///
    /// `nil` znamená „není co hlásit": klip bez použitelné rampy, fotka nebo
    /// asset bez platného měření frekvence.
    ///
    /// ⚠️ Patří to do MODELU, ne do varovného bloku v exportu. Obě vstupní
    /// veličiny (profil rychlosti a mez čistého zpomalení) tu už jsou a UI by
    /// z nich muselo počítat po svém — a druhý výpočet téhož se rozejde
    /// (poučení z fáze 13).
    public func duplicatedFrameShare(of clip: Clip, samples: Int = 240) -> Double? {
        guard let ramp = clip.speedRamp, ramp.isUsable,
              let limit = pureSlowdownLimit(of: clip), limit > 0 else { return nil }
        let profile = rampSpeedProfile(of: clip, samples: samples)
        guard !profile.isEmpty else { return nil }
        let sum = profile.reduce(0.0) { $0 + Swift.max(0, 1 - $1 / limit) }
        return sum / Double(profile.count)
    }
}

// MARK: - Přidání a smazání uzlu

extension Project {

    /// Nejmenší zdrojová vzdálenost dvou uzlů. Menší rozestup by dal strmost,
    /// kterou žádná segmentace nedožene, a dva uzly v jednom bodě by křivku
    /// zneplatnily.
    static let minimumNodeSourceGap = 0.02

    /// Přidá uzel v daném výstupním snímku klipu. Uzel se položí NA křivku
    /// (rychlost i zdrojová pozice z aktuálního mapování), takže se tvar
    /// v okamžiku přidání nemění — mění se až tažením.
    ///
    /// Na klipu bez rampy vznikne jednouzlová křivka s rychlostí 1× —
    /// vizuálně se nestane nic, ale uzel už jde chytit a táhnout.
    @discardableResult
    public mutating func addRampNode(clipID: ClipID, atOutputFrame frame: Double) throws -> Int {
        guard let clip = timeline.clip(clipID) else { throw TimelineError.clipNotFound(clipID) }
        let fps = Double(timeline.frameRate)
        let bounded = min(Double(clip.duration.count), max(0, frame))

        let sourceSeconds: Double
        let speed: Double
        if let window = rampWindow(for: clip) {
            let output = window.t0 + bounded / fps
            sourceSeconds = window.ramp.sourceTime(atOutput: output)
            speed = window.ramp.speed(atOutput: output)
        } else {
            sourceSeconds = clip.sourceStart.seconds + bounded / fps
            speed = 1.0
        }

        var nodes = (clip.speedRamp?.isUsable == true) ? clip.speedRamp!.nodes : []
        guard !nodes.contains(where: {
            abs($0.sourceTime.seconds - sourceSeconds) < Self.minimumNodeSourceGap
        }) else { throw TimelineError.invalidSpeedRamp }

        let node = SpeedNode(sourceTime: SourceTime(seconds: sourceSeconds),
                             speed: speed, easeToNext: .easeInOut)
        let index = nodes.firstIndex { $0.sourceTime.seconds > sourceSeconds } ?? nodes.count
        nodes.insert(node, at: index)

        try setSpeedRamp(clipID: clipID, ramp: SpeedRamp(nodes: nodes))
        return index
    }

    /// Smaže uzel. Poslední uzel bere křivku s sebou — klip se vrací na 1×.
    public mutating func removeRampNode(clipID: ClipID, nodeIndex: Int) throws {
        guard let clip = timeline.clip(clipID) else { throw TimelineError.clipNotFound(clipID) }
        guard var nodes = clip.speedRamp?.nodes, nodes.indices.contains(nodeIndex) else {
            throw TimelineError.invalidSpeedRamp
        }
        nodes.remove(at: nodeIndex)
        try setSpeedRamp(clipID: clipID, ramp: nodes.isEmpty ? nil : SpeedRamp(nodes: nodes))
    }
}

// MARK: - Tažení uzlu

/// Tažení uzlu editoru. Při stisku zachytí křivku a KAŽDÝ krok myši se
/// mapuje přes tuhle základnu — kdyby se kurzor mapoval přes průběžně měněnou
/// křivku, chyba by se s každým krokem skládala a uzel by kurzoru ujížděl.
///
/// Stejný princip jako `TimelineInteraction`: čistá hodnota, žádný zápis do
/// modelu. Zápis dělá volající (`setSpeedRamp` na každý krok — mezistavy
/// jsou legální jako u trimu, undo přes `beginInteraction`/`endInteraction`).
public struct RampNodeDrag {

    public let clipID: ClipID
    public let nodeIndex: Int

    private let nodes: [SpeedNode]
    private let baseline: EngineRamp
    private let t0: Double
    private let fps: Double
    private let scale: RampEditorScale
    /// Zdrojové meze uzlu: sousedi ± minimální rozestup, konce assetu.
    private let sourceBounds: ClosedRange<Double>

    public init?(project: Project, clipID: ClipID, nodeIndex: Int,
                 scale: RampEditorScale = RampEditorScale()) {
        guard let clip = project.timeline.clip(clipID),
              let ramp = clip.speedRamp, ramp.isUsable,
              ramp.nodes.indices.contains(nodeIndex),
              let window = project.rampWindow(for: clip),
              let asset = project.asset(clip.assetID) else { return nil }

        self.clipID = clipID
        self.nodeIndex = nodeIndex
        self.nodes = ramp.nodes
        self.baseline = window.ramp
        self.t0 = window.t0
        self.fps = Double(project.timeline.frameRate)
        self.scale = scale

        let gap = Project.minimumNodeSourceGap
        let lower = nodeIndex > 0
            ? ramp.nodes[nodeIndex - 1].sourceTime.seconds + gap
            : 0
        let upper = nodeIndex < ramp.nodes.count - 1
            ? ramp.nodes[nodeIndex + 1].sourceTime.seconds - gap
            : asset.duration.seconds
        guard lower <= upper else { return nil }
        self.sourceBounds = lower ... upper
    }

    /// Křivka s uzlem přesunutým pod kurzor. `outputFrame` i `speed` jsou
    /// nezávislé — svislé tažení nechá zdrojovou kotvu být a naopak.
    public func ramp(atOutputFrame outputFrame: Double?, speed: Double?) -> SpeedRamp {
        var moved = nodes
        var node = moved[nodeIndex]
        if let outputFrame {
            let source = baseline.sourceTime(atOutput: max(0, t0 + outputFrame / fps))
            node.sourceTime = SourceTime(
                seconds: min(sourceBounds.upperBound, max(sourceBounds.lowerBound, source)))
        }
        if let speed {
            node.speed = scale.clamp(speed)
        }
        moved[nodeIndex] = node
        return SpeedRamp(nodes: moved)
    }
}
