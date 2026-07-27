//
//  Model.swift
//  TimelineModel — Projekt Krása
//
//  Datové typy dokumentu. Všechno hodnotové a Sendable; projekt vlastní
//  main actor, protože operace řídí UI.
//

import Foundation

// MARK: - Identifikátory

/// ID jako `RawRepresentable` nad `String` — jinak by se zakódovalo
/// jako `{"raw": "…"}` místo holého řetězce.
public struct AssetID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct ClipID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct TrackID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

/// Vazba mezi obrazem a jeho zvukem. Sdílená dvojicí klipů na různých stopách.
public struct LinkID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

// MARK: - Rychlostní křivka (místo pro fázi 3)

/// Uzel rychlostní křivky.
///
/// Čas je ve **zdrojovém** čase, ne na ose. Když zpomalení sedí na hodu
/// kyticí a klip se zepředu zkrátí, zpomalení má zůstat na hodu kyticí —
/// kdyby uzly visely na ose, ujelo by to jinam.
public struct SpeedNode: Hashable, Codable, Sendable {
    public var sourceTime: SourceTime
    public var speed: Double

    public init(sourceTime: SourceTime, speed: Double) {
        self.sourceTime = sourceTime
        self.speed = speed
    }
}

/// Fáze 3 tohle napojí na `SpeedRampEngine`. Ve fázi 2 je to jen úložiště,
/// aby datový model nemusel měnit tvar.
public struct SpeedRamp: Hashable, Codable, Sendable {
    public var nodes: [SpeedNode]
    public init(nodes: [SpeedNode]) { self.nodes = nodes }
}

// MARK: - Asset

public struct Asset: Identifiable, Hashable, Codable, Sendable {
    public let id: AssetID
    public var originalURL: URL
    /// Vyplní se až ve fázi 4. Struktura tu ale musí být od fáze 2 —
    /// doplnit ji později znamená přepsat model i playback.
    public var proxyURL: URL?
    /// Security-scoped bookmark. Bez něj se po restartu k souboru nedostaneme.
    public var bookmark: Data?
    public var duration: SourceTime
    /// NAMĚŘENÁ frekvence z `VFRDetectoru`, ne `nominalFrameRate`.
    /// Ta na slow-mo klipu hlásí 119,369 místo skutečných 120,000.
    public var measuredFrameRate: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
    /// Soubor zmizel nebo se přejmenoval. Klipy zůstávají a drží si poslední
    /// známou délku — smazat cizí práci kvůli přejmenované složce je horší
    /// chyba než prázdné místo v náhledu.
    public var isOffline: Bool

    public init(id: AssetID = AssetID(),
                originalURL: URL,
                proxyURL: URL? = nil,
                bookmark: Data? = nil,
                duration: SourceTime,
                measuredFrameRate: Double,
                hasVideo: Bool = true,
                hasAudio: Bool = true,
                isOffline: Bool = false) {
        self.id = id
        self.originalURL = originalURL
        self.proxyURL = proxyURL
        self.bookmark = bookmark
        self.duration = duration
        self.measuredFrameRate = measuredFrameRate
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.isOffline = isOffline
    }

    /// Jediné místo v celém projektu, kde se rozhoduje, se kterým souborem
    /// se pracuje. `PlaybackController` i `CompositionBuilder` dostanou
    /// hotovou URL, ne asset — jinak se to rozhodování rozleze na deset míst
    /// a každé bude mít jinou chybu.
    public func url(usingProxies: Bool) -> URL {
        (usingProxies ? proxyURL : nil) ?? originalURL
    }
}

// MARK: - Klip

public struct Clip: Identifiable, Hashable, Codable, Sendable {
    public let id: ClipID
    public var assetID: AssetID
    /// Sdílené s protějškem na druhé stopě. `nil` = samostatný klip.
    public var linkID: LinkID?

    /// Kde klip začíná NA OSE.
    public var timelineStart: Frames
    /// Jak dlouho trvá NA OSE.
    ///
    /// ⚠️ Spotřebu zdroje z toho neodvozuj přímo — od fáze 3 to nebude 1:1.
    /// Používej `Project.sourceConsumption(of:)`.
    public var duration: Frames

    /// Odkud se bere ve ZDROJI. Prezentační čas v originálu,
    /// **s respektovaným edit listem** — čte se přes `AVComposition`.
    /// Všech pět měřených klipů zahazuje na zvuku prvních 44 ms, a to je
    /// na 30fps základně víc než jeden snímek. Kdo edit list ignoruje, bude
    /// tu chybu hledat v synchronizaci místo ve čtení.
    public var sourceStart: SourceTime

    /// Fáze 3.
    public var speedRamp: SpeedRamp?

    public init(id: ClipID = ClipID(),
                assetID: AssetID,
                linkID: LinkID? = nil,
                timelineStart: Frames,
                duration: Frames,
                sourceStart: SourceTime,
                speedRamp: SpeedRamp? = nil) {
        self.id = id
        self.assetID = assetID
        self.linkID = linkID
        self.timelineStart = timelineStart
        self.duration = duration
        self.sourceStart = sourceStart
        self.speedRamp = speedRamp
    }

    /// Exkluzivní konec.
    public var timelineEnd: Frames { timelineStart + duration }

    /// Překrývá se s druhým klipem? Dotyk (konec == začátek) překryv NENÍ.
    public func overlaps(_ other: Clip) -> Bool {
        timelineStart < other.timelineEnd && other.timelineStart < timelineEnd
    }

    public func contains(frame: Frames) -> Bool {
        frame >= timelineStart && frame < timelineEnd
    }
}

// MARK: - Stopa

public enum TrackKind: String, Codable, Sendable {
    case video, audio
}

public struct AudioSettings: Hashable, Codable, Sendable {
    public var volume: Double
    public var isMuted: Bool

    public init(volume: Double = 1.0, isMuted: Bool = false) {
        self.volume = volume
        self.isMuted = isMuted
    }
}

public struct Track: Identifiable, Hashable, Codable, Sendable {
    public let id: TrackID
    public var kind: TrackKind
    public var name: String
    /// Jen u zvukových stop. Optional, ne pole ignorované u poloviny
    /// instancí — takové pole je pozvánka k chybě.
    public var audio: AudioSettings?
    /// Vždy seřazené podle `timelineStart` a nepřekrývající se.
    public internal(set) var clips: [Clip]

    public init(id: TrackID = TrackID(),
                kind: TrackKind,
                name: String,
                audio: AudioSettings? = nil,
                clips: [Clip] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.audio = audio ?? (kind == .audio ? AudioSettings() : nil)
        self.clips = clips
    }

    public func clip(id: ClipID) -> Clip? { clips.first { $0.id == id } }
    public func index(of id: ClipID) -> Int? { clips.firstIndex { $0.id == id } }

    /// Vloží při zachování pořadí. Nekontroluje překryv — to dělá operace.
    mutating func insertSorted(_ clip: Clip) {
        let i = clips.firstIndex { $0.timelineStart > clip.timelineStart } ?? clips.count
        clips.insert(clip, at: i)
    }

    mutating func resort() {
        clips.sort { $0.timelineStart < $1.timelineStart }
    }
}

// MARK: - Timeline

/// Rozlišení plátna. Vlastní typ, ne `CGSize` — model se musí přeložit
/// i tam, kde CoreGraphics není, aby šel testovat mimo macOS.
public struct CanvasSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    public static let uhd4K = CanvasSize(width: 3840, height: 2160)
}

public struct Timeline: Hashable, Codable, Sendable {
    /// Základna projektu. Pevných 30 (rozhodnuto 26. 07. 2026), ale
    /// pojmenované — ať se v kódu nikde neobjeví magická třicítka.
    public let frameRate: Int
    /// Fáze 3 ji potřebuje pro `renderSize`, fáze 5 pro export.
    public var canvasSize: CanvasSize
    /// Pořadí je významné: pozdější obrazová stopa překrývá dřívější.
    public internal(set) var tracks: [Track]

    public init(frameRate: Int = 30,
                canvasSize: CanvasSize = .uhd4K,
                tracks: [Track] = []) {
        self.frameRate = frameRate
        self.canvasSize = canvasSize
        self.tracks = tracks
    }

    public func track(id: TrackID) -> Track? { tracks.first { $0.id == id } }
    public func index(of id: TrackID) -> Int? { tracks.firstIndex { $0.id == id } }

    /// Najde klip napříč stopami.
    public func locate(_ clipID: ClipID) -> (trackIndex: Int, clipIndex: Int)? {
        for (t, track) in tracks.enumerated() {
            if let c = track.index(of: clipID) { return (t, c) }
        }
        return nil
    }

    public func clip(_ id: ClipID) -> Clip? {
        guard let at = locate(id) else { return nil }
        return tracks[at.trackIndex].clips[at.clipIndex]
    }
}

// MARK: - Hranice mezi soustavami

extension Timeline {
    /// **Osa → zdroj.** Jediné povolené místo tímhle směrem.
    ///
    /// Násobí se v celých tickách projektové timescale, nikdy přes `Double`.
    /// Projektová timescale 90000 je dělitelná 30, takže při základně 30 fps
    /// je převod přesný a nic se nezaokrouhluje.
    public func sourceTime(_ frames: Frames) -> SourceTime {
        let ticksPerFrame = Int64(SourceTime.projectTimescale) / Int64(frameRate)
        let exact = Int64(SourceTime.projectTimescale) % Int64(frameRate) == 0
        if exact {
            return SourceTime(value: Int64(frames.count) * ticksPerFrame,
                              timescale: SourceTime.projectTimescale)
        }
        // Nedělitelná základna: použij jemnější timescale, ať zůstane přesná.
        let scale = SourceTime.projectTimescale * Int32(frameRate)
        return SourceTime(value: Int64(frames.count) * Int64(SourceTime.projectTimescale),
                          timescale: scale)
    }

    /// **Zdroj → osa.** Vždy DOLŮ.
    ///
    /// Zaokrouhlení nahoru by dovolilo trim o snímek za konec souboru
    /// a poslední snímek by zamrzl nebo by kompozice vrátila černou.
    ///
    /// ⚠️ U VFR zdrojů může být v daném čase míň skutečných snímků, než
    /// kolik odpovídá základně — ani jeden z pěti měřených klipů nemá
    /// konstantní časování. Tohle je proto **záruka nejmenšího počtu**,
    /// ne odhad: víc snímků než tolik na ose nikdy nevznikne.
    public func availableFrames(from time: SourceTime) -> Frames {
        guard time.value > 0 else { return .zero }
        // frames = time.seconds * frameRate, počítáno celočíselně
        let numerator = time.value * Int64(frameRate)
        let denominator = Int64(time.timescale)
        // Dělení dolů i pro záporné hodnoty (Swift dělí k nule).
        let q = numerator / denominator
        let r = numerator % denominator
        let floored = (r < 0) ? q - 1 : q
        return Frames(Int(floored))
    }
}

// MARK: - Projekt

public struct Project: Hashable, Codable, Sendable {
    /// Pole, ne slovník. `JSONEncoder` kóduje slovník s ne-řetězcovým klíčem
    /// jako plochý seznam střídajících se klíčů a hodnot, ne jako objekt —
    /// a specifikace 6.2 chce objekt. Index se staví při načtení.
    public internal(set) var assets: [Asset]
    public internal(set) var timeline: Timeline
    /// Jedna věc na projekt, ne tisíc na klipy.
    public var usesProxies: Bool

    public init(assets: [Asset] = [], timeline: Timeline = Timeline(), usesProxies: Bool = false) {
        self.assets = assets
        self.timeline = timeline
        self.usesProxies = usesProxies
    }

    public func asset(_ id: AssetID) -> Asset? { assets.first { $0.id == id } }

    /// Výchozí prázdný projekt: V1 + A1 + A2 podle specifikace 8.1.
    public static func empty(canvasSize: CanvasSize = .uhd4K) -> Project {
        Project(timeline: Timeline(canvasSize: canvasSize, tracks: [
            Track(kind: .video, name: "V1"),
            Track(kind: .audio, name: "A1"),
            Track(kind: .audio, name: "A2"),
        ]))
    }

    // MARK: Spotřeba zdroje — jediné místo výpočtu

    /// Kolik zdrojového materiálu klip spotřebuje.
    ///
    /// Fáze 2: `sourceTime(clip.duration)`.
    /// Fáze 3: integrál rychlostní křivky ze `SpeedRampEngine`.
    ///
    /// **Žádná operace ať nepočítá spotřebu jinak než touhle funkcí.** Jinak
    /// bude fáze 3 znamenat přepsat šest operací a jednu validaci místo
    /// vnitřku jedné funkce.
    public func sourceConsumption(of clip: Clip) -> SourceTime {
        timeline.sourceTime(clip.duration)
    }

    /// Kde ve zdroji leží snímek `offset` od začátku klipu.
    ///
    /// Split i trim jdou přes tohle, ne přes „délku převedenou na zdrojový
    /// čas" — ten vzorec platí jen při rychlosti 1×.
    public func sourceOffset(in clip: Clip, atFrame offset: Frames) -> SourceTime {
        clip.sourceStart + timeline.sourceTime(offset)
    }

    /// Kolik snímků zdroje klipu ještě zbývá za jeho koncem.
    public func remainingSourceFrames(after clip: Clip) -> Frames {
        guard let asset = asset(clip.assetID) else { return .zero }
        let used = clip.sourceStart + sourceConsumption(of: clip)
        guard used < asset.duration else { return .zero }
        return timeline.availableFrames(from: asset.duration - used)
    }

    /// Kolik snímků zdroje je k dispozici před začátkem klipu.
    public func availableSourceFramesBefore(_ clip: Clip) -> Frames {
        timeline.availableFrames(from: clip.sourceStart)
    }
}
