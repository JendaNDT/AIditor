//
//  TimelineDocumentView.swift
//  Projekt Krása
//
//  Plocha časové osy uvnitř `NSScrollView`. Krok 2 z `FAZE_2_VIEW.md`, sekce 7.
//
//  Zatím jen pruhy stop. Klipy jsou krok 5, pravítko a hlavičky krok 3.
//  Do view patří kreslení a předávání událostí, nic víc — všechno, co má
//  návratovou hodnotu porovnatelnou s očekáváním, umí `TimelineModel`.
//

import AppKit
import TimelineModel

/// Barvy časové osy.
///
/// ⚠️ **Sémantické systémové barvy se sem nehodí.** První verze kroku 2 brala
/// pruhy z `controlBackgroundColor` a pozadí z `underPageBackgroundColor` —
/// v tmavém režimu jsou obě skoro černé, takže osa vyšla jako jeden slitý
/// tmavý blok a tři pruhy v ní nebyly poznat. Ty barvy mají svůj smysl
/// (obsah okna, plocha pod dokumentem), ale nejsou navržené na to, aby se
/// odlišily od sebe navzájem.
///
/// Proto vlastní paleta. `NSColor(name:dynamicProvider:)` drží obě větve
/// v jedné hodnotě, takže i tady stačí barvu přeložit při změně vzhledu
/// a nikde není druhá sada konstant.
/// <https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)>
enum TimelinePalette {

    /// ⚠️ **Od fáze 18 je paleta JEN TMAVÁ** (rozhodnuto 29. 07. 2026).
    /// Okno si v `WindowConfigurator` vynucuje `.darkAqua`, takže světlá
    /// větev by se nikdy nespustila. Světlé protějšky jsou proto **smazané,
    /// ne zakomentované**: barva, kterou nikdo nevidí, se za rok rozejde se
    /// zbytkem palety a nikdo si toho nevšimne.
    ///
    /// Obal `NSColor(name:dynamicProvider:)` zůstává — vrací pořád tutéž
    /// hodnotu, ale drží čitelné jméno v debuggeru a nechává jedno místo,
    /// kam by se světlá varianta vracela, kdyby se rozhodnutí měnilo.
    private static func adaptive(_ name: String, dark: CGFloat) -> NSColor {
        NSColor(name: NSColor.Name(name)) { _ in NSColor(white: dark, alpha: 1) }
    }

    private static func adaptive(_ name: String, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { _ in dark }
    }

    /// Doba hudby v pravítku (fáze 14) — jantarová, v paletě nová:
    /// neplete se s modrou/zelenou/fialovou/žlutou/terakotovou.
    static let beat = NSColor.systemOrange

    /// Značky kvality na klipu (fáze 15): oranžová = měkký záběr,
    /// červená = rozmazaný. Zelená se nekreslí.
    static let qualitySoft = NSColor.systemOrange.withAlphaComponent(0.9)
    static let qualityBad = NSColor.systemRed
    /// Hluché místo (ticho + prázdný obraz, F15/2) — šedá při SPODNÍ
    /// hraně klipu: jiná dimenze než ostrost, jiná hrana i barva.
    static let qualityEmpty = NSColor.systemGray

    /// Klín zvukového fade (fáze 16) — ztmavení nad křivkou nástupu.
    static let fadeFill = NSColor.black.withAlphaComponent(0.35)

    /// Plocha pod stopami a za koncem projektu.
    static let background = adaptive("timelineBackground", dark: 0.09)
    /// Pruh obrazové stopy. Nejsvětlejší — obraz je hlavní.
    static let videoLane = adaptive("timelineVideoLane", dark: 0.24)
    /// Pruh zvukové stopy.
    static let audioLane = adaptive("timelineAudioLane", dark: 0.17)
    /// Pruh titulkové stopy — nejtmavší; je úzký a vedlejší.
    static let titleLane = adaptive("timelineTitleLane", dark: 0.13)

    static func lane(for kind: TrackKind) -> NSColor {
        switch kind {
        case .video: return videoLane
        case .audio: return audioLane
        case .title: return titleLane
        }
    }

    /// Pozadí pravítka a hlaviček. Mezi pozadím osy a pruhy, ať je poznat,
    /// že je to ovládací lišta a ne obsah.
    static let chrome = adaptive("timelineChrome", dark: 0.14)
    /// Popisky timecode a jména stop.
    static let text = adaptive("timelineText", dark: 0.68)
    /// Rysky pravítka.
    static let tick = adaptive("timelineTick", dark: 0.42)
    /// Předěly mezi pravítkem, hlavičkami a plochou osy.
    static let separator = adaptive("timelineSeparator", dark: 0.28)

    // MARK: Klipy
    //
    // Jediné barevné plochy na ose. Modrá pro obraz a zelená pro zvuk je
    // konvence, kterou zná každý, kdo kdy viděl NLE — není důvod vymýšlet
    // vlastní. Výplně jsou tlumené, aby na nich stálo písmo.

    /// Výplň obrazového klipu.
    static let clipVideoFill = adaptive(
        "clipVideoFill",
        dark: NSColor(calibratedRed: 0.23, green: 0.34, blue: 0.55, alpha: 1))
    /// Výplň zvukového klipu.
    static let clipAudioFill = adaptive(
        "clipAudioFill",
        dark: NSColor(calibratedRed: 0.16, green: 0.41, blue: 0.30, alpha: 1))
    /// Obrys klipu — ztmavená hrana, ať se sousedící klipy neslijí.
    static let clipStroke = adaptive(
        "clipStroke",
        dark: NSColor(white: 0, alpha: 0.45))
    /// Obrys vybraného klipu. Výběr přijde s krokem 7, barva ale patří sem,
    /// ať se paleta nerozšiřuje nadvakrát.
    static let clipSelectedStroke = adaptive(
        "clipSelectedStroke",
        dark: NSColor(calibratedRed: 1.00, green: 0.79, blue: 0.28, alpha: 1))
    /// Jméno klipu.
    static let clipText = adaptive("clipText", dark: 0.94)

    /// Výplň lichoběžníku přechodu. Fialová — jediná na ose, nesmí se plést
    /// s modrým obrazem, zeleným zvukem ani žlutým výběrem. Poloprůhledná,
    /// aby pod ní zůstaly čitelné okraje klipů, přes které se prolíná.
    static let transitionFill = adaptive(
        "transitionFill",
        dark: NSColor(calibratedRed: 0.58, green: 0.44, blue: 0.86, alpha: 0.60))
    /// Obrys lichoběžníku přechodu.
    static let transitionStroke = adaptive(
        "transitionStroke",
        dark: NSColor(calibratedRed: 0.78, green: 0.66, blue: 1.00, alpha: 1))

    /// Výplň titulkového klipu na T1. Terakotová — nesmí se plést s modrým
    /// obrazem, zeleným zvukem, fialovými přechody ani žlutým výběrem;
    /// od žluté ji drží dál ztmavení a příklon k červené.
    static let titleClipFill = adaptive(
        "titleClipFill",
        dark: NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.20, alpha: 1))
    /// Pásek titulku z řeči v pruhu T1. Zvuková zelená s průhledností —
    /// řeč žije ve zvuku a pásek je jen projekce, ne uchopitelný objekt.
    static let speechStripFill = adaptive(
        "speechStripFill",
        dark: NSColor(calibratedRed: 0.16, green: 0.41, blue: 0.30, alpha: 0.60))

    /// Přehrávací hlava. Červená je konvence — jediná svislá červená čára
    /// v celém okně, nesmí se s ničím plést.
    static let playhead = adaptive(
        "timelinePlayhead",
        dark: NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1))
}

/// Vrstva jednoho klipu. ŽÁDNÉ kreslení — jen barvy, obrys a `CATextLayer`
/// se jménem. Kreslené view by tu dostalo vadnou celookenní `ContentLayer`
/// (viz `TimelinePane`), vrstvy s barvami jsou imunní.
final class ClipLayer: CALayer {

    let title = CATextLayer()
    /// Poslední zapsaný titulek — `title.string` se přepisuje jen při změně,
    /// jinak `CATextLayer` rastruje text při každém scrollovacím tiku znova.
    var titleText: String?
    /// Kontejner dlaždic vlny — pod titulkem, ořezaný na klip.
    let waveContainer = CALayer()
    /// Dlaždice podle indexu. Obsah spravuje `TimelineDocumentView`.
    var waveTiles: [Int: CALayer] = [:]
    /// Úroveň zoomu, pro kterou dlaždice platí. Při změně se mění celá sada.
    var waveRung: Double = 0

    override init() {
        super.init()
        cornerRadius = 3
        masksToBounds = true
        borderWidth = 1
        waveContainer.masksToBounds = true
        addSublayer(waveContainer)
        title.fontSize = 11
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.truncationMode = .end
        addSublayer(title)
        for shape in [fadeInShape, fadeOutShape] {
            shape.isHidden = true
            addSublayer(shape)
        }
        for handle in [fadeInHandle, fadeOutHandle] {
            handle.isHidden = true
            handle.cornerRadius = 3
            handle.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            handle.borderWidth = 1
            handle.borderColor = NSColor.black.withAlphaComponent(0.4).cgColor
            addSublayer(handle)
        }
    }

    /// Proužky kvality (fáze 15) při horní hraně klipu — recyklované
    /// indexem, značek jsou na klipu jednotky.
    var qualityLayers: [CALayer] = []
    /// Proužky hluchosti (F15/2) při SPODNÍ hraně klipu.
    var emptinessLayers: [CALayer] = []
    /// Klíny zvukových fade (fáze 16) — `CAShapeLayer`, žádné `draw`
    /// (past `ContentLayer` platí). Úchyt je kolečko na vrcholu klínu.
    let fadeInShape = CAShapeLayer()
    let fadeOutShape = CAShapeLayer()
    let fadeInHandle = CALayer()
    let fadeOutHandle = CALayer()

    /// Překreslí klíny fade. Šířky v bodech; nulová šířka nechá jen úchyt
    /// v rohu (jen na zvukovém klipu — `visible`).
    func setFades(inWidth: Double, outWidth: Double, visible: Bool, color: CGColor) {
        fadeInShape.isHidden = !visible || inWidth <= 0
        fadeOutShape.isHidden = !visible || outWidth <= 0
        fadeInHandle.isHidden = !visible
        fadeOutHandle.isHidden = !visible
        guard visible else { return }
        let h = bounds.height
        if inWidth > 0 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: inWidth, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.closeSubpath()
            fadeInShape.path = path
            fadeInShape.fillColor = color
        }
        if outWidth > 0 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: bounds.width, y: h))
            path.addLine(to: CGPoint(x: bounds.width - outWidth, y: 0))
            path.addLine(to: CGPoint(x: bounds.width, y: 0))
            path.closeSubpath()
            fadeOutShape.path = path
            fadeOutShape.fillColor = color
        }
        fadeInHandle.frame = CGRect(x: inWidth - 3, y: 1, width: 6, height: 6)
        fadeOutHandle.frame = CGRect(x: bounds.width - outWidth - 3, y: 1,
                                     width: 6, height: 6)
    }

    /// Odpojí všechny dlaždice — při recyklaci a při změně úrovně.
    func clearWaveTiles() {
        for tile in waveTiles.values { tile.removeFromSuperlayer() }
        waveTiles = [:]
    }

    /// Rozmístí proužky kvality; prázdné pole je všechny schová.
    func setQualityMarks(_ marks: [(x: Double, width: Double, color: CGColor)]) {
        Self.layoutStrips(&qualityLayers, marks: marks, in: self, y: 1)
    }

    /// Totéž pro hluchost — při spodní hraně (výška vrstvy je známá
    /// až po `frame`, proto se `y` počítá při každém rozmístění).
    func setEmptinessMarks(_ marks: [(x: Double, width: Double, color: CGColor)]) {
        Self.layoutStrips(&emptinessLayers, marks: marks, in: self,
                          y: bounds.height - 5)
    }

    private static func layoutStrips(_ strips: inout [CALayer],
                                     marks: [(x: Double, width: Double, color: CGColor)],
                                     in parent: CALayer, y: Double) {
        while strips.count < marks.count {
            let strip = CALayer()
            strip.cornerRadius = 1.5
            parent.addSublayer(strip)
            strips.append(strip)
        }
        for (index, strip) in strips.enumerated() {
            guard index < marks.count else { strip.isHidden = true; continue }
            let mark = marks[index]
            strip.isHidden = false
            strip.backgroundColor = mark.color
            strip.frame = CGRect(x: mark.x, y: y, width: mark.width, height: 4)
        }
    }

    /// Core Animation si přes tenhle init dělá kopie pro prezentační strom.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }
}

/// Lichoběžník přechodu přes hranu střihu (fáze 10, modul 3). Horní hrana
/// pokrývá celou oblast, spodní se sbíhá ke střihu — tvar říká „tady se
/// dva klipy prolínají do jednoho bodu". `CAShapeLayer`, žádné `draw`
/// (past s celookenní `ContentLayer`, viz `TimelinePane`).
final class TransitionLayer: CAShapeLayer {

    override init() {
        super.init()
        lineWidth = 1
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    /// Rámec = obdélník oblasti; cesta se počítá v souřadnicích vrstvy.
    /// `cutX` je v souřadnicích DOKUMENTU, tady se převádí na lokální.
    func apply(frame rect: CGRect, cutX: Double) {
        frame = rect
        let localCut = cutX - rect.origin.x
        let foot = min(4.0, rect.width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: min(localCut + foot, rect.width), y: rect.height))
        path.addLine(to: CGPoint(x: max(localCut - foot, 0), y: rect.height))
        path.closeSubpath()
        self.path = path
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }
}

/// Vrstva titulkového klipu na pruhu T1 (fáze 11, modul 2). Jen barvy,
/// obrys a `CATextLayer` s textem — ŽÁDNÉ `draw`, platí past s celookenní
/// `ContentLayer` (viz `TimelinePane`).
final class TitleLayer: CALayer {

    let label = CATextLayer()
    /// Poslední zapsaný text — stejný důvod jako `ClipLayer.titleText`:
    /// `CATextLayer` rastruje při každém zápisu `string` znova.
    var labelText: String?

    override init() {
        super.init()
        cornerRadius = 3
        masksToBounds = true
        borderWidth = 1
        label.fontSize = 10
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.truncationMode = .end
        addSublayer(label)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }
}

final class TimelineDocumentView: NSView {

    /// Vlastník stavu. Silná reference je v pořádku, protože controller
    /// zpátky na views neukazuje. Až ukazovat bude, ať je ta cesta `weak`.
    private let controller: TimelineController

    /// Pruhy stop pod klipy. Jeden `CALayer` na STOPU — stop jsou jednotky,
    /// takže se recyklovat nemusí. Recyklace se řeší u klipů (krok 5).
    private let backgroundLayer = CALayer()
    private var laneLayers: [CALayer] = []

    /// Kontejner klipových vrstev — nad pruhy, pod budoucím playheadem.
    private let clipsContainer = CALayer()
    /// Vrstvy právě visící na ose, podle klipu.
    private var mountedClipLayers: [ClipID: ClipLayer] = [:]

    /// Co je na nasazených klipech doopravdy nakreslené (fáze 18, modul 3).
    ///
    /// Měřicí okno pro `--layers-check`: přepínač vrstvy se ověřuje tím, že
    /// se prvky přestanou KRESLIT, ne tím, že scroll zrychlí. Rychlost je
    /// dnes pod šumem měření (vlna a proužky jsou levné) — mechanismus se
    /// tím ověřit nedá, přítomností vrstev ano.
    var drawnLayerCounts: (waveTiles: Int, qualityStrips: Int, emptinessStrips: Int) {
        var tiles = 0, quality = 0, emptiness = 0
        for layer in mountedClipLayers.values {
            tiles += layer.waveTiles.count
            quality += layer.qualityLayers.filter { !$0.isHidden }.count
            emptiness += layer.emptinessLayers.filter { !$0.isHidden }.count
        }
        return (tiles, quality, emptiness)
    }
    /// Fond odložených vrstev. Vrstva se nikdy nezahazuje, jen odpojuje —
    /// zakládání vrstev při každém scrollnutí je přesně to, čemu se recyklací
    /// předchází.
    private var clipLayerPool: [ClipLayer] = []

    /// Lichoběžníky přechodů — NAD klipy (kreslí se přes jejich okraje),
    /// pod overlayem tažení. Stejná recyklace jako u klipů, jen ručně:
    /// přechodů jsou jednotky, diff aparát by tu byl kanón na vrabce.
    private let transitionsContainer = CALayer()
    private var mountedTransitionLayers: [TransitionID: TransitionLayer] = [:]
    private var transitionLayerPool: [TransitionLayer] = []

    /// Pruh T1 (fáze 11, modul 2): titulkové klipy a pásky titulků z řeči.
    /// Pásky se přidávají do kontejneru PŘED titulky, takže leží pod nimi.
    /// Recyklace ručně — obou jsou jednotky, stejný důvod jako u přechodů.
    private let titlesContainer = CALayer()
    private var mountedTitleLayers: [TitleClipID: TitleLayer] = [:]
    private var titleLayerPool: [TitleLayer] = []
    /// Pásky nemají identitu (jsou to projekce přepisu, ne objekty) —
    /// recyklují se indexem: přebytek se schová, chybějící se přidá.
    private var speechStripLayers: [CALayer] = []
    /// Titulky z řeči promítnuté na osu. Přepočet není zadarmo, proto
    /// mezipaměť obnovovaná v `rebuildClipInfo` (reload), ne při scrollu.
    private var speechCues: [SubtitleCue] = []

    /// Přehrávací hlava — svislá čára přes celou výšku dokumentu, nad klipy.
    private let playheadLayer = CALayer()

    // MARK: Overlay tažení (krok 7)
    //
    // Během tažení se do modelu NEZAPISUJE (`TimelineInteraction`), takže
    // klipové vrstvy stojí na původních místech a hýbe se jen tenhle náhled.
    // Duch = obrys s poloprůhlednou výplní; při neplatném cíli červeně.

    private let dragOverlay = CALayer()
    private let ghostLayer = CALayer()
    /// Druhý duch pro roll — hýbou se dva klipy naráz.
    private let partnerGhostLayer = CALayer()
    /// Svislá vodicí čára na kandidátovi, na kterého se přichytilo.
    private let snapGuideLayer = CALayer()
    /// Rámeček výběru (fáze 17, modul 2).
    private let bandLayer = CALayer()

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
        // Jen `wantsLayer` — backing vrstvu si vyrobí AppKit a podvrstvy se
        // do ní věší stejně. (Dřívější `layer = CALayer()` bylo při honu na
        // černý náhled 27. 07. 2026 prověřeno a bylo nevinné; zůstává ale
        // jednodušší varianta.)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(clipsContainer)
        layer?.addSublayer(titlesContainer)
        layer?.addSublayer(transitionsContainer)
        layer?.addSublayer(dragOverlay)
        layer?.addSublayer(playheadLayer)

        for ghost in [ghostLayer, partnerGhostLayer] {
            ghost.cornerRadius = 3
            ghost.borderWidth = 1.5
            ghost.isHidden = true
            dragOverlay.addSublayer(ghost)
        }
        snapGuideLayer.isHidden = true
        dragOverlay.addSublayer(snapGuideLayer)

        bandLayer.isHidden = true
        bandLayer.borderWidth = 1
        dragOverlay.addSublayer(bandLayer)

        rebuildLanes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    // MARK: - ⚠️ Svislá osa

    /// ⚠️ **Bez tohohle je celá svislá osa vzhůru nohama.**
    ///
    /// `TimelineGeometry.y(ofTrackAt:)` sčítá výšky stop odshora dolů, takže
    /// stopa 0 má `y = 0`. AppKit má ale ve výchozím stavu počátek vlevo dole.
    /// Nespadne to a nevyhodí to warning — jen `trackIndex(atY:)` vrátí při
    /// kliknutí na V1 poslední zvukovou stopu a klipy se nakreslí obráceně.
    ///
    /// <https://developer.apple.com/documentation/appkit/nsview/isflipped>
    override var isFlipped: Bool { true }

    // MARK: - Stopy

    /// Přepočítá POČET vrstev podle stop. Volá se při změně sady stop,
    /// ne při každém layoutu — ten jen přepisuje rámce.
    /// Data klipu potřebná ke kreslení, jedním slovníkovým sáhnutím.
    ///
    /// ⚠️ `timeline.clip()` je LINEÁRNÍ přes všechny klipy. Volat ho (a hledání
    /// assetu a jména) pro každý viditelný klip při každém tiku scrollu stálo
    /// na ose s 2000 klipy ~5 ms z rozpočtu 16,7 ms — změřeno výkonovým
    /// testem fáze 2. Slovník se přestavuje jen při změně projektu.
    private struct ClipDrawInfo {
        let clip: Clip
        let asset: Asset?
        let kind: TrackKind
        let name: String
    }
    private var clipInfo: [ClipID: ClipDrawInfo] = [:]

    private func rebuildClipInfo() {
        let project = controller.project
        var info: [ClipID: ClipDrawInfo] = [:]
        for track in project.timeline.tracks {
            for clip in track.clips {
                let asset = project.asset(clip.assetID)
                info[clip.id] = ClipDrawInfo(
                    clip: clip,
                    asset: asset,
                    kind: track.kind,
                    name: asset.map { $0.originalURL.deletingPathExtension().lastPathComponent }
                        ?? "—")
            }
        }
        clipInfo = info
        // Titulky z řeči pro pruh T1 — přepočet patří sem (reload), scroll
        // už jen mapuje hotové pole na souřadnice.
        speechCues = project.subtitleCues()
        // Značky kvality (fáze 15) — bez vzorků okamžitý early-out, od fáze 18
        // i s vypnutou vrstvou (modul 3). Citlivost přepočítává jen KLASIFIKACI
        // hotových vzorků, nové vzorkování nespouští.
        qualityMarks = (!controller.layers.qualityMarks || controller.sharpnessSamples.isEmpty)
            ? [:]
            : project.qualityMarks(samples: controller.sharpnessSamples,
                                   sensitivity: controller.qualitySensitivity)
        emptyMarks = (!controller.layers.qualityMarks || controller.emptinessSamples.isEmpty)
            ? [:]
            : project.emptinessMarks(samples: controller.emptinessSamples,
                                     sensitivity: controller.qualitySensitivity)
    }

    /// Problémové úseky ostrosti per klip (fáze 15) — přepočet patří do
    /// reloadu, scroll je jen mapuje na souřadnice.
    private var qualityMarks: [ClipID: [QualitySegment]] = [:]
    /// Hluchá místa per klip (F15/2).
    private var emptyMarks: [ClipID: [EmptySegment]] = [:]

    func rebuildLanes() {
        rebuildClipInfo()
        let count = controller.project.timeline.tracks.count

        while laneLayers.count > count {
            laneLayers.removeLast().removeFromSuperlayer()
        }
        while laneLayers.count < count {
            let lane = CALayer()
            backgroundLayer.addSublayer(lane)
            laneLayers.append(lane)
        }

        applyColors()
        applyContentsScale()
        needsLayout = true
    }

    override func layout() {
        super.layout()

        // ⚠️ `CALayer` animuje změnu `frame` 0,25 s. Při scrollování by pruhy
        // „plavaly" za obsahem. `PlayerView.layout()` řešil v projektu tenhle
        // problém už jednou, stejným způsobem.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        backgroundLayer.frame = bounds

        // ⚠️ Souřadnice vrstev jsou tu shodné se souřadnicemi view, tedy
        // počátek vlevo NAHOŘE. AppKit u převráceného layer-backed view sám
        // nastavuje `layer.isGeometryFlipped = true` (ověřeno měřením
        // 27. 07. 2026) a SDK k té vlastnosti říká „geometry of the layer
        // AND ITS SUBLAYERS is flipped vertically". Proto jde `y(ofTrackAt:)`
        // vrstvě předat rovnou a nic se nepřepočítává.
        //
        // Pozor při ověřování: `CALayer.render(in:)` převrácení IGNORUJE,
        // takže cokoli změřeného přes něj tvrdí opak. Poznat je to okem —
        // V1 je vysoká 64 bodů proti 44 u zvuku, takže při špatném převrácení
        // leží vysoký pruh dole.
        let geometry = controller.geometry
        let timeline = controller.project.timeline

        for (index, track) in timeline.tracks.enumerated() where index < laneLayers.count {
            laneLayers[index].frame = CGRect(x: 0,
                                             y: geometry.y(ofTrackAt: index, in: timeline),
                                             width: bounds.width,
                                             height: geometry.height(of: track.kind))
        }

        clipsContainer.frame = bounds
        titlesContainer.frame = bounds
        transitionsContainer.frame = bounds
        dragOverlay.frame = bounds
        refreshClips()
        updatePlayhead()
    }

    // MARK: - Přehrávací hlava (krok 6)

    /// Přemístí čáru hlavy. Volá se při každé změně `controller.playhead`
    /// (během přehrávání 30×/s) — proto jen přepis rámce jedné vrstvy,
    /// žádné placements, žádný diff.
    func updatePlayhead() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = controller.geometry.x(for: controller.playhead)
        playheadLayer.frame = CGRect(x: x - 1, y: 0, width: 2, height: bounds.height)
        CATransaction.commit()
    }

    // MARK: - Klipy (krok 5)

    /// Ta „desetiřádková smyčka" z návrhu: placements → diff → odpojit,
    /// připojit z fondu, všem přepsat rámec. KTERÉ vrstvy a KAM říká
    /// `TimelineModel` a je to otestované; tady se to jen provádí.
    ///
    /// Volá se při scrollu, layoutu a reloadu. Viditelný výřez si bere
    /// z clip view, protože scroll hýbe jeho `bounds` — vlastní rámec
    /// dokumentu se scrollem nemění.
    func refreshClips() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let visible = clipView.bounds

        let placements = TimelineLayout.placements(project: controller.project,
                                                   geometry: controller.geometry,
                                                   scrollX: visible.origin.x,
                                                   width: visible.width,
                                                   selection: controller.selection)
        let diff = TimelineLayout.diff(previous: Set(mountedClipLayers.keys),
                                       next: placements)

        // Pojistka proti zastaralému slovníku: normálně ho přestaví `reload`,
        // ale kdyby refresh předběhl, doplní se tady místo kreslení pomlček.
        if placements.contains(where: { clipInfo[$0.clipID] == nil }) {
            rebuildClipInfo()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for clipID in diff.toRecycle {
            guard let layer = mountedClipLayers.removeValue(forKey: clipID) else { continue }
            layer.clearWaveTiles()
            layer.waveRung = 0
            layer.setQualityMarks([])
            layer.setEmptinessMarks([])
            layer.removeFromSuperlayer()
            clipLayerPool.append(layer)
        }

        for clipID in diff.toMount {
            let layer = clipLayerPool.popLast() ?? ClipLayer()
            layer.contentsScale = window?.backingScaleFactor ?? 2
            layer.title.contentsScale = layer.contentsScale
            clipsContainer.addSublayer(layer)
            mountedClipLayers[clipID] = layer
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            for placement in placements {
                guard let layer = mountedClipLayers[placement.clipID] else { continue }
                apply(placement, to: layer, visible: visible)
            }
        }

        refreshTitles(visible: visible)
        refreshTransitions(visible: visible)
    }

    // MARK: - Pruh T1 (fáze 11, modul 2)

    /// Titulkové klipy a pásky titulků z řeči. KDE co leží počítá otestovaný
    /// `TimelineModel` (`titlePlacements`, `subtitleStripPlacements`) —
    /// tady se jen vrství. Interakce (tažení, menu, výběr) je modul 3.
    private func refreshTitles(visible: NSRect) {
        let placements = TimelineLayout.titlePlacements(
            project: controller.project,
            geometry: controller.geometry,
            scrollX: visible.origin.x,
            width: visible.width)
        let strips = TimelineLayout.subtitleStripPlacements(
            cues: speechCues,
            project: controller.project,
            geometry: controller.geometry,
            scrollX: visible.origin.x,
            width: visible.width)

        let visibleIDs = Set(placements.map(\.titleID))
        for (id, layer) in mountedTitleLayers where !visibleIDs.contains(id) {
            mountedTitleLayers.removeValue(forKey: id)
            layer.removeFromSuperlayer()
            titleLayerPool.append(layer)
        }

        // Pásky podle indexu: chybějící přidat (POD titulky — vkládají se
        // na začátek kontejneru), přebytečné schovat, vrstvy se nezahazují.
        while speechStripLayers.count < strips.count {
            let strip = CALayer()
            strip.cornerRadius = 2
            titlesContainer.insertSublayer(strip, at: 0)
            speechStripLayers.append(strip)
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (index, strip) in speechStripLayers.enumerated() {
                guard index < strips.count else { strip.isHidden = true; continue }
                strip.isHidden = false
                strip.backgroundColor = TimelinePalette.speechStripFill.cgColor
                let s = strips[index]
                // Tenký proužek při spodní hraně pruhu — plná výška patří
                // titulkovým klipům, pásek je jen ukazatel „tady se mluví".
                let stripHeight = 7.0
                strip.frame = CGRect(x: s.x, y: s.y + s.height - stripHeight - 2,
                                     width: s.width, height: stripHeight)
            }

            for placement in placements {
                let layer: TitleLayer
                if let mounted = mountedTitleLayers[placement.titleID] {
                    layer = mounted
                } else {
                    layer = titleLayerPool.popLast() ?? TitleLayer()
                    layer.contentsScale = window?.backingScaleFactor ?? 2
                    layer.label.contentsScale = layer.contentsScale
                    titlesContainer.addSublayer(layer)
                    mountedTitleLayers[placement.titleID] = layer
                }
                layer.frame = CGRect(x: placement.x, y: placement.y,
                                     width: placement.width, height: placement.height)
                layer.backgroundColor = TimelinePalette.titleClipFill.cgColor
                let isSelected = placement.titleID == controller.selectedTitle
                layer.borderColor = isSelected
                    ? TimelinePalette.clipSelectedStroke.cgColor
                    : TimelinePalette.clipStroke.cgColor
                layer.borderWidth = isSelected ? 2 : 1

                // Stejná pravidla jako jméno klipu: u titěrné šířky schovat
                // úplně, přepisovat jen při změně.
                layer.label.isHidden = placement.width < 40
                if layer.labelText != placement.text {
                    layer.labelText = placement.text
                    layer.label.string = placement.text
                }
                layer.label.foregroundColor = TimelinePalette.clipText.cgColor
                layer.label.frame = CGRect(x: 6, y: 2,
                                           width: max(0, placement.width - 12),
                                           height: 14)
            }
        }
    }

    // MARK: - Lichoběžníky přechodů (fáze 10, modul 3)

    /// Táž smyčka jako u klipů, jen bez diff aparátu — KDE lichoběžníky
    /// leží počítá otestovaný `TimelineLayout.transitionPlacements`.
    private func refreshTransitions(visible: NSRect) {
        let placements = TimelineLayout.transitionPlacements(
            project: controller.project,
            geometry: controller.geometry,
            scrollX: visible.origin.x,
            width: visible.width)

        let visibleIDs = Set(placements.map(\.transitionID))
        for (id, layer) in mountedTransitionLayers where !visibleIDs.contains(id) {
            mountedTransitionLayers.removeValue(forKey: id)
            layer.removeFromSuperlayer()
            transitionLayerPool.append(layer)
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            for placement in placements {
                let layer: TransitionLayer
                if let mounted = mountedTransitionLayers[placement.transitionID] {
                    layer = mounted
                } else {
                    layer = transitionLayerPool.popLast() ?? TransitionLayer()
                    layer.contentsScale = window?.backingScaleFactor ?? 2
                    transitionsContainer.addSublayer(layer)
                    mountedTransitionLayers[placement.transitionID] = layer
                }
                layer.fillColor = TimelinePalette.transitionFill.cgColor
                // Vybraný přechod dostává žlutý obrys — týž jazyk výběru
                // jako klipy a titulky (fáze 16).
                let isSelected = placement.transitionID == controller.selectedTransition
                layer.strokeColor = isSelected
                    ? TimelinePalette.clipSelectedStroke.cgColor
                    : TimelinePalette.transitionStroke.cgColor
                layer.lineWidth = isSelected ? 2 : 1
                layer.apply(frame: CGRect(x: placement.x, y: placement.y,
                                          width: placement.width, height: placement.height),
                            cutX: placement.cutX)
            }
        }
    }

    /// Rámec, barvy a jméno jedné vrstvy. Volat UVNITŘ
    /// `performAsCurrentDrawingAppearance` — `cgColor` se vyhodnocuje pro
    /// aktuální appearance a vrstva si výsledek pamatuje jako hodnotu.
    private func apply(_ placement: TimelineLayout.Placement, to layer: ClipLayer,
                       visible: NSRect) {
        layer.frame = CGRect(x: placement.x, y: placement.y,
                             width: placement.width, height: placement.height)

        let info = clipInfo[placement.clipID]
        let kind = info?.kind ?? .video
        let fill = kind == .video ? TimelinePalette.clipVideoFill : TimelinePalette.clipAudioFill
        layer.backgroundColor = fill.cgColor
        layer.borderColor = placement.isSelected
            ? TimelinePalette.clipSelectedStroke.cgColor
            : TimelinePalette.clipStroke.cgColor
        layer.borderWidth = placement.isSelected ? 2 : 1

        // U titěrných klipů se titulek i vlna schovávají ÚPLNĚ, nezmenšují —
        // zmenšený text je rozsypaný a zmenšená vlna šum (návrh, sekce 6).
        layer.title.isHidden = placement.width < 40
        // Přepsat jen při ZMĚNĚ: `CATextLayer` po každém zápisu `string`
        // rastruje text znova, i když je stejný — při scrollu to dělalo
        // desítky rastrů za tik.
        let name = info?.name ?? "—"
        if layer.titleText != name {
            layer.titleText = name
            layer.title.string = name
        }
        layer.title.foregroundColor = TimelinePalette.clipText.cgColor
        layer.title.frame = CGRect(x: 6, y: 2,
                                   width: max(0, placement.width - 12), height: 15)

        applyWaveform(placement, to: layer, info: info, visible: visible)
        applyQualityMarks(placement, to: layer)
        applyFades(placement, to: layer, info: info)
    }

    /// Klíny zvukových fade (fáze 16): tažený náhled má přednost před
    /// modelem — během tažení se do modelu nepíše (vzorec `move`).
    private func applyFades(_ placement: TimelineLayout.Placement, to layer: ClipLayer,
                            info: ClipDrawInfo?) {
        let isAudio = info?.kind == .audio
        guard isAudio, placement.width >= 24, let clip = info?.clip else {
            layer.setFades(inWidth: 0, outWidth: 0, visible: false, color: TimelinePalette.fadeFill.cgColor)
            return
        }
        let fades: AudioFades
        if let preview = fadePreview, preview.clipID == placement.clipID {
            fades = preview.fades
        } else {
            fades = controller.project.effectiveAudioFades(of: clip) ?? AudioFades()
        }
        let pointsPerFrame = controller.geometry.pointsPerFrame
        layer.setFades(inWidth: Double(fades.fadeIn.count) * pointsPerFrame,
                       outWidth: Double(fades.fadeOut.count) * pointsPerFrame,
                       visible: true,
                       color: TimelinePalette.fadeFill.cgColor)
    }

    /// Proužky kvality (fáze 15): oranžová/červená při horní hraně klipu,
    /// šedá hluchost při spodní. Zelená se nekreslí — ticho je dobrá
    /// zpráva, značka je jen tam, kde stojí za to se podívat (klik = seek).
    private func applyQualityMarks(_ placement: TimelineLayout.Placement, to layer: ClipLayer) {
        let geometry = controller.geometry
        func strips<S>(_ segments: [S]?, frames: (S) -> (Frames, Frames),
                       color: (S) -> NSColor) -> [(x: Double, width: Double, color: CGColor)] {
            guard let segments, placement.width >= 16 else { return [] }
            return segments.map { segment in
                let (start, end) = frames(segment)
                return (x: geometry.x(for: start) - placement.x,
                        width: max(2, geometry.x(for: end) - geometry.x(for: start)),
                        color: color(segment).cgColor)
            }
        }
        layer.setQualityMarks(strips(qualityMarks[placement.clipID],
                                     frames: { ($0.start, $0.end) },
                                     color: { $0.level == .bad
                                         ? TimelinePalette.qualityBad
                                         : TimelinePalette.qualitySoft }))
        layer.setEmptinessMarks(strips(emptyMarks[placement.clipID],
                                       frames: { ($0.start, $0.end) },
                                       color: { _ in TimelinePalette.qualityEmpty }))
    }

    // MARK: - Vlnové průběhy (krok 10)

    /// Poskládá dlaždice vlny pro zvukový klip. Dlaždice jsou ASSETOVÉ
    /// (klíč: asset, mocnina dvou, index) — trim ani slip je nezahazuje,
    /// jen posune výřez. Renderují se líně na pozadí; dokud nejsou, je pod
    /// titulkem prostě jen barva klipu.
    private func applyWaveform(_ placement: TimelineLayout.Placement, to layer: ClipLayer,
                               info: ClipDrawInfo?, visible: NSRect) {
        let pointsPerFrame = controller.geometry.pointsPerFrame
        guard controller.layers.waveforms,     // vypnutá vrstva (F18/M3)
              let info, info.kind == .audio,
              placement.width >= 32,
              let asset = info.asset,
              let peaks = controller.waveforms.peaks(for: asset),
              peaks.count > 0
        else {
            layer.clearWaveTiles()
            layer.waveRung = 0
            return
        }
        let clip = info.clip

        let rung = WaveformStore.rung(for: pointsPerFrame)
        if layer.waveRung != rung {
            layer.clearWaveTiles()
            layer.waveRung = rung
        }
        layer.waveContainer.frame = layer.bounds

        // Viditelný výřez klipu v bodech dokumentu, s malým přesahem.
        let fromX = max(visible.minX - 100, placement.x)
        let toX = min(visible.maxX + 100, placement.x + placement.width)
        guard toX > fromX else {
            layer.clearWaveTiles()
            return
        }

        // Body → sekundy zdroje při AKTUÁLNÍM zoomu; dlaždice jsou na úrovni.
        let secondsPerPoint = 1.0 / (30.0 * pointsPerFrame)
        let clipStartSeconds = clip.sourceStart.seconds
        let secondsPerTile = WaveformStore.tileWidthPoints / (30.0 * rung)
        let scale = window?.backingScaleFactor ?? 2

        let fromSeconds = clipStartSeconds + (fromX - placement.x) * secondsPerPoint
        let toSeconds = clipStartSeconds + (toX - placement.x) * secondsPerPoint
        let firstTile = max(0, Int(fromSeconds / secondsPerTile))
        let lastTile = max(firstTile, Int(toSeconds / secondsPerTile))

        // Pryč s dlaždicemi mimo výřez.
        for (index, tile) in layer.waveTiles where index < firstTile || index > lastTile {
            tile.removeFromSuperlayer()
            layer.waveTiles.removeValue(forKey: index)
        }

        for index in firstTile...lastTile {
            let tile: CALayer
            if let existing = layer.waveTiles[index] {
                tile = existing
            } else {
                tile = CALayer()
                layer.waveContainer.addSublayer(tile)
                layer.waveTiles[index] = tile
            }
            let tileStartSeconds = Double(index) * secondsPerTile
            let xInClip = (tileStartSeconds - clipStartSeconds) / secondsPerPoint
            tile.frame = CGRect(x: xInClip, y: 0,
                                width: secondsPerTile / secondsPerPoint,
                                height: placement.height)
            // `nil` = ještě se renderuje; až doběhne, zvedne store `version`
            // a tenhle průchod se zopakuje.
            tile.contents = controller.waveforms.tile(assetID: asset.id, rung: rung,
                                                      index: index, scale: scale)
        }
    }


    // MARK: - Barvy

    /// ⚠️ **`NSColor.cgColor` se vyhodnotí pro appearance platnou v okamžiku
    /// volání, ne pro tu, ve které vrstva leží.** Systémová barva uložená do
    /// `CALayer.backgroundColor` tedy při přepnutí do tmavého režimu zamrzne
    /// na staré hodnotě. Proto se barvy překládají uvnitř
    /// `performAsCurrentDrawingAppearance` a znovu při každé změně vzhledu.
    ///
    /// <https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)>
    private func applyColors() {
        let tracks = controller.project.timeline.tracks

        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            layer?.backgroundColor = TimelinePalette.background.cgColor
            playheadLayer.backgroundColor = TimelinePalette.playhead.cgColor

            for (index, lane) in laneLayers.enumerated() where index < tracks.count {
                lane.backgroundColor = TimelinePalette.lane(for: tracks[index].kind).cgColor
            }

            CATransaction.commit()
        }

        // Klipy drží barvy taky jako `CGColor` hodnoty — po změně vzhledu
        // se musí přeložit znovu, jinak zamrznou ve starém režimu.
        refreshClips()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    // MARK: - Retina

    /// ⚠️ **Ručně vytvořené vrstvy `contentsScale` nedostanou.** Výchozí
    /// hodnota je 1,0; vrstva připojená k view ji zdědí od view, ale ta,
    /// kterou si vyrobíme sami, ne. U jednobarevných pruhů to ještě nevadí,
    /// u textu a vlny (kroky 5 a 10) je z toho rozmazaná Retina.
    ///
    /// <https://developer.apple.com/documentation/quartzcore/calayer/contentsscale>
    private func applyContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        backgroundLayer.contentsScale = scale
        for lane in laneLayers { lane.contentsScale = scale }
        clipsContainer.contentsScale = scale
        // I fond: vrstva odložená na Retině a připojená na externím displeji
        // (nebo obráceně) by jinak nesla staré měřítko a text by se rozmazal.
        for layer in mountedClipLayers.values + clipLayerPool {
            layer.contentsScale = scale
            layer.title.contentsScale = scale
        }
        for layer in mountedTransitionLayers.values + transitionLayerPool {
            layer.contentsScale = scale
        }
        for layer in mountedTitleLayers.values + titleLayerPool {
            layer.contentsScale = scale
            layer.label.contentsScale = scale
        }
        for strip in speechStripLayers { strip.contentsScale = scale }
    }

    /// Volá se i při přesunu okna na displej s jiným rozlišením, ne jen na začátku.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyContentsScale()
    }

    // MARK: - Cesta události (krok 7)
    //
    // View jen předává souřadnice a kreslí — CO se táhne, KAM to smí a JAK
    // dopadne počítá `TimelineInteraction` a je to otestované. Undo se
    // zapisuje dvěma způsoby a není to nedůslednost: u `move` neexistuje
    // legální mezistav, stačí jeden `record()` před zápisem; u trimu a rollu
    // jsou mezistavy legální, proto `beginInteraction`/`endInteraction`.

    override var acceptsFirstResponder: Bool { true }

    /// Rozjeté tažení okraje přechodu (fáze 10, modul 3). Mezistavy se do
    /// modelu NEZAPISUJÍ — duch ukazuje budoucí oblast a zapisuje se jednou
    /// při puštění, stejný vzorec jako `move`.
    private struct TransitionDragState {
        let transitionID: TransitionID
        let trackID: TrackID
        var duration: Frames? = nil
    }
    private var transitionDrag: TransitionDragState?

    /// Rozjeté tažení titulku (fáze 11, modul 3). Týž vzorec: duch, jeden
    /// zápis při puštění. Kandidáti přichytávání se počítají při stisku.
    private struct TitleDragState {
        let hit: TitleHit
        let candidates: [SnapCandidate]
        var result: TitleDragResult? = nil
    }
    private var titleDrag: TitleDragState?

    /// Rozjeté tažení úchytu fade (fáze 16). Týž vzorec: náhled v klínu,
    /// JEDEN zápis do modelu při puštění.
    private struct FadeDragState {
        let clipID: ClipID
        let isFadeIn: Bool
        let clipStart: Frames
        let clipDuration: Frames
        let otherFade: Frames
    }
    private var fadeDrag: FadeDragState?
    /// Náhled fade během tažení — `applyFades` mu dává přednost před modelem.
    private var fadePreview: (clipID: ClipID, fades: AudioFades)?

    /// Rozjetý rámečkový výběr (fáze 17, modul 2).
    private struct BandDragState {
        let origin: NSPoint
        /// Tažení se shiftem nebo ⌘ k výběru PŘIDÁVÁ.
        let adding: Bool
        var current: NSPoint? = nil
    }
    private var bandDrag: BandDragState?

    /// Klik s modifikátorem, o kterém se rozhodne až při puštění: ⌘ a shift
    /// znamenají při TAŽENÍ něco jiného (slip, vypnuté přichytávání), takže
    /// se výběr mění, jen když se myš nepohnula.
    private enum PendingSelection {
        case toggle(ClipID)
        case extend(ClipID)
    }
    private var pendingSelection: PendingSelection?

    /// Drží uživatel něco rozjetého? Auto-scroll za hlavou (fáze 17) se po
    /// tu dobu MUSÍ vypnout — jinak by osa ujížděla pod taženým klipem.
    var hasActiveDrag: Bool {
        fadeDrag != nil || transitionDrag != nil || titleDrag != nil
            || bandDrag != nil || controller.interaction.isDragging
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        // Lichoběžník leží NAD klipy, proto má i v událostech přednost —
        // jinak by se pod ním naslepo trimovalo něco, co uživatel nevidí.
        if let transitionHit = controller.geometry.transitionHitTest(
            x: point.x, y: point.y, in: controller.project) {
            switch transitionHit.zone {
            case .leadingEdge, .trailingEdge:
                transitionDrag = TransitionDragState(
                    transitionID: transitionHit.transitionID,
                    trackID: transitionHit.trackID)
            case .body:
                // Výběr přechodu (fáze 16 — drobnost z koukanců F10):
                // rámeček + Delete. Tažení tělo nemá, akce jsou v menu.
                controller.selectTransition(transitionHit.transitionID)
            }
            return
        }

        // Titulek na T1: vybrat a případně začít tažení (fáze 11, modul 3).
        if let titleHit = controller.geometry.titleHitTest(
            x: point.x, y: point.y, in: controller.project.timeline) {
            controller.selectTitle(titleHit.titleID)
            titleDrag = TitleDragState(
                hit: titleHit,
                candidates: controller.geometry.snapCandidates(
                    in: controller.project.timeline,
                    playhead: controller.playhead,
                    excludingTitles: [titleHit.titleID],
                    beats: controller.project.beatMarks().map(\.frame)))
            if titleHit.zone == .body { NSCursor.closedHand.set() }
            return
        }

        // Prázdný pruh T1: klik na pásek řeči vybírá úsek přepisu pro
        // inspektor; klik do prázdna výběry ruší.
        if let ti = controller.geometry.trackIndex(atY: point.y,
                                                   in: controller.project.timeline),
           controller.project.timeline.tracks[ti].kind == .title {
            let frame = controller.geometry.frame(atX: point.x)
            if let ref = controller.project.speechCueRef(at: frame) {
                controller.selectSpeech(.init(assetID: ref.assetID,
                                              segmentIndex: ref.segmentIndex))
            } else {
                controller.selectTitle(nil)
                controller.selectSpeech(nil)
            }
            return
        }

        guard let hit = controller.geometry.hitTest(x: point.x, y: point.y,
                                                    in: controller.project.timeline) else {
            // Prázdná plocha: začíná rámečkový výběr (fáze 17). Výběr se
            // ruší až při puštění — kdyby se rušil hned, tažení se shiftem
            // by nemělo co rozšiřovat.
            bandDrag = BandDragState(origin: point,
                                     adding: event.modifierFlags.contains(.shift)
                                          || event.modifierFlags.contains(.command))
            controller.selectTitle(nil)
            controller.selectSpeech(nil)
            controller.selectTransition(nil)
            return
        }

        // Modifikátory u kliku na klip (fáze 17). ⌘ i shift mají na ose
        // druhý význam PŘI TAŽENÍ (⌘ = slip, shift = bez přichytávání),
        // takže se o výběru rozhodne až při puštění — když se nepohnulo,
        // byl to klik a platí výběr; když ano, platí tažení.
        if event.modifierFlags.contains(.shift) {
            pendingSelection = .extend(hit.clipID)
        } else if event.modifierFlags.contains(.command) {
            pendingSelection = .toggle(hit.clipID)
        } else {
            pendingSelection = nil
            // Klik do klipu, který je součástí většího výběru, výběr NEruší —
            // jinak by se nedalo z výběru rovnou spustit hromadná akce
            // z kontextového menu.
            if !controller.selection.contains(hit.clipID) {
                controller.selectClips([hit.clipID])
            }
        }

        // Úchyt zvukového fade (fáze 16): horní pás zvukového klipu,
        // ±8 bodů od vrcholu klínu. Má přednost před trimem — trim bere
        // celou výšku hrany, fade jen horních 10 bodů.
        if let at = controller.project.timeline.locate(hit.clipID),
           controller.project.timeline.tracks[at.trackIndex].kind == .audio,
           let clip = controller.project.timeline.clip(hit.clipID),
           let ti = controller.geometry.trackIndex(atY: point.y,
                                                   in: controller.project.timeline),
           point.y - controller.geometry.y(ofTrackAt: ti,
                                           in: controller.project.timeline) <= 10 {
            let fades = controller.project.effectiveAudioFades(of: clip) ?? AudioFades()
            let inX = controller.geometry.x(for: clip.timelineStart + fades.fadeIn)
            let outX = controller.geometry.x(for: clip.timelineEnd - fades.fadeOut)
            if abs(point.x - inX) <= 8 {
                fadeDrag = FadeDragState(clipID: clip.id, isFadeIn: true,
                                         clipStart: clip.timelineStart,
                                         clipDuration: clip.duration,
                                         otherFade: fades.fadeOut)
                return
            }
            if abs(point.x - outX) <= 8 {
                fadeDrag = FadeDragState(clipID: clip.id, isFadeIn: false,
                                         clipStart: clip.timelineStart,
                                         clipDuration: clip.duration,
                                         otherFade: fades.fadeIn)
                return
            }
        }

        // Klik do proužku kvality (fáze 15) = seek na začátek problému —
        // značka je pozvánka „podívej se", ne dekorace. Jen krajní pásky
        // klipu (nahoře ostrost, dole hluchost), jinak by kolidoval
        // s tažením.
        if let ti = controller.geometry.trackIndex(atY: point.y,
                                                   in: controller.project.timeline) {
            let timeline = controller.project.timeline
            let trackTop = controller.geometry.y(ofTrackAt: ti, in: timeline)
            let trackHeight = controller.geometry.height(of: timeline.tracks[ti].kind)
            let frame = controller.geometry.frame(atX: point.x)
            if point.y - trackTop <= 6,
               let segment = qualityMarks[hit.clipID]?.first(where: {
                   frame >= $0.start && frame < $0.end
               }) {
                controller.setPlayheadFromUser(segment.start)
                return
            }
            if trackTop + trackHeight - point.y <= 6,
               let segment = emptyMarks[hit.clipID]?.first(where: {
                   frame >= $0.start && frame < $0.end
               }) {
                controller.setPlayheadFromUser(segment.start)
                return
            }
        }

        // Modifikátory (krok 9, návrh sekce 4): ⌥ na okraji = roll (operace
        // na hranici), ⌘ v těle = slip (operace na obsahu). Bez souseda
        // spadne roll v interakci zpátky na trim — hlídá to model.
        var forced: DragKind?
        if event.modifierFlags.contains(.option), hit.zone != .body { forced = .roll }
        if event.modifierFlags.contains(.command), hit.zone == .body { forced = .slip }

        controller.interaction.begin(hit: hit, in: controller.project,
                                     forcing: forced,
                                     playhead: controller.playhead)

        switch controller.interaction.drag?.kind {
        case .trimStart, .trimEnd, .roll:
            controller.undo.beginInteraction(controller.project)
        case .move, .slip:
            NSCursor.closedHand.set()
        case nil:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Jakmile se táhne, klik s modifikátorem přestává být klikem —
        // platí tažení (slip / bez přichytávání).
        pendingSelection = nil

        if var band = bandDrag {
            band.current = convert(event.locationInWindow, from: nil)
            bandDrag = band
            updateBandOverlay(band)
            return
        }
        if let drag = fadeDrag {
            let point = convert(event.locationInWindow, from: nil)
            updateFadeDrag(drag, atX: point.x)
            return
        }
        if transitionDrag != nil {
            let point = convert(event.locationInWindow, from: nil)
            updateTransitionDrag(atX: point.x)
            return
        }
        if titleDrag != nil {
            let point = convert(event.locationInWindow, from: nil)
            updateTitleDrag(atX: point.x,
                            snapping: snapping(for: event))
            return
        }
        guard controller.interaction.isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let preview = controller.interaction.preview(
            atX: point.x, y: point.y,
            in: controller.project,
            snapping: snapping(for: event))
        updateDragOverlay(preview)
    }

    /// Rámeček výběru. Jen rám a průsvitná výplň, žádný diff — vrstva se
    /// při tažení jen přepisuje (vzorec ducha).
    private func updateBandOverlay(_ band: BandDragState) {
        guard let current = band.current else { bandLayer.isHidden = true; return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bandLayer.borderColor = TimelinePalette.clipSelectedStroke.cgColor
            bandLayer.backgroundColor = TimelinePalette.clipSelectedStroke
                .withAlphaComponent(0.15).cgColor
        }
        bandLayer.isHidden = false
        bandLayer.frame = CGRect(x: min(band.origin.x, current.x),
                                 y: min(band.origin.y, current.y),
                                 width: abs(current.x - band.origin.x),
                                 height: abs(current.y - band.origin.y))
        CATransaction.commit()
    }

    /// Náhled tažení fade: délka od hrany klipu ke kurzoru, zaražená
    /// o druhý fade a délku klipu. Do modelu se nepíše — klín kreslí
    /// `applyFades` z `fadePreview`.
    private func updateFadeDrag(_ drag: FadeDragState, atX x: Double) {
        let frame = controller.geometry.frame(atX: x)
        let limit = drag.clipDuration - drag.otherFade
        let fades: AudioFades
        if drag.isFadeIn {
            let length = min(max(frame - drag.clipStart, .zero), limit)
            fades = AudioFades(fadeIn: length, fadeOut: drag.otherFade)
        } else {
            let end = drag.clipStart + drag.clipDuration
            let length = min(max(end - frame, .zero), limit)
            fades = AudioFades(fadeIn: drag.otherFade, fadeOut: length)
        }
        fadePreview = (drag.clipID, fades)
        refreshClips()
    }

    /// Náhled tažení okraje přechodu: model přeloží pozici kurzoru na
    /// zaraženou délku (`transitionDraggedDuration` — symetrie, meze,
    /// podlaha), duch ukáže budoucí oblast. Model se nesahá.
    private func updateTransitionDrag(atX x: Double) {
        guard var drag = transitionDrag,
              let transition = controller.project.transition(id: drag.transitionID),
              let region = controller.project.transitionRegion(of: drag.transitionID),
              let duration = controller.project.transitionDraggedDuration(
                  id: drag.transitionID,
                  edgeFrame: controller.geometry.frame(atX: x)) else { return }
        drag.duration = duration
        transitionDrag = drag

        let cut = region.start + transition.framesBeforeCut
        let start = cut - Frames(duration.count / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ghostLayer.borderColor = TimelinePalette.transitionStroke.cgColor
            ghostLayer.backgroundColor = TimelinePalette.transitionFill.cgColor
        }
        ghostLayer.isHidden = false
        ghostLayer.frame = ghostFrame(trackID: drag.trackID, start: start,
                                      duration: duration,
                                      timeline: controller.project.timeline,
                                      geometry: controller.geometry)
    }

    /// Náhled tažení titulku: model přeloží pozici kurzoru na zaraženou
    /// pozici/délku (`titleMovePreview` a spol.), duch ukáže výsledek.
    /// Model se nesahá.
    /// Přichytávat? Globální přepínač z lišty osy A zároveň nedržený shift.
    /// Dvě cesty k témuž rozhodnutí, ale jinak dlouhé: přepínač na celé
    /// sezení, shift na jedno tažení.
    private func snapping(for event: NSEvent) -> Bool {
        controller.snappingEnabled && !event.modifierFlags.contains(.shift)
    }

    private func updateTitleDrag(atX x: Double, snapping: Bool) {
        guard var drag = titleDrag else { return }
        let geometry = controller.geometry
        let frame = geometry.frame(atX: x)

        let result: TitleDragResult?
        switch drag.hit.zone {
        case .body:
            result = controller.project.titleMovePreview(
                id: drag.hit.titleID, pointerFrame: frame,
                grabOffset: drag.hit.offsetInTitle,
                candidates: drag.candidates, geometry: geometry, snapping: snapping)
        case .leadingEdge:
            result = controller.project.titleTrimStartPreview(
                id: drag.hit.titleID, frame: frame,
                candidates: drag.candidates, geometry: geometry, snapping: snapping)
        case .trailingEdge:
            result = controller.project.titleTrimEndPreview(
                id: drag.hit.titleID, frame: frame,
                candidates: drag.candidates, geometry: geometry, snapping: snapping)
        }
        guard let result else { return }
        drag.result = result
        titleDrag = drag

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = result.isValid ? TimelinePalette.clipSelectedStroke
                                        : TimelinePalette.playhead
            ghostLayer.borderColor = accent.cgColor
            ghostLayer.backgroundColor = TimelinePalette.titleClipFill
                .withAlphaComponent(0.4).cgColor
            snapGuideLayer.backgroundColor = TimelinePalette.clipSelectedStroke.cgColor
        }
        ghostLayer.isHidden = false
        ghostLayer.frame = ghostFrame(trackID: drag.hit.trackID,
                                      start: result.start, duration: result.duration,
                                      timeline: controller.project.timeline,
                                      geometry: geometry)
        if let snapped = result.snappedTo {
            snapGuideLayer.isHidden = false
            let sx = geometry.x(for: snapped.frame)
            snapGuideLayer.frame = CGRect(x: sx - 0.5, y: 0, width: 1, height: bounds.height)
        } else {
            snapGuideLayer.isHidden = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Klik s modifikátorem, který se nerozvinul v tažení (fáze 17).
        if let pending = pendingSelection {
            pendingSelection = nil
            controller.interaction.cancel()
            _ = controller.undo.cancelInteraction()
            updateDragOverlay(nil)
            switch pending {
            case .toggle(let id): controller.toggleSelection(id)
            case .extend(let id): controller.extendSelection(to: id)
            }
            return
        }

        if let band = bandDrag {
            bandDrag = nil
            bandLayer.isHidden = true
            if let current = band.current {
                controller.selectClips(in: TimelineRect(from: (x: band.origin.x, y: band.origin.y),
                                                        to: (x: current.x, y: current.y)),
                                       adding: band.adding)
            } else if !band.adding {
                // Klik do prázdna bez tažení = zrušit výběr (dosavadní chování).
                if !controller.selection.isEmpty { controller.selectClips([]) }
            }
            return
        }

        if let drag = fadeDrag {
            fadeDrag = nil
            let committed = fadePreview
            fadePreview = nil
            if let committed, committed.clipID == drag.clipID {
                // Hromadná varianta (fáze 17): stejný fade dostanou všechny
                // zvukové klipy výběru, když jich je víc a tažený je mezi nimi.
                if controller.selection.count > 1, controller.selection.contains(drag.clipID) {
                    controller.setAudioFadesOnSelection(committed.fades)
                } else {
                    controller.setAudioFades(drag.clipID, committed.fades)
                }
            }
            refreshClips()
            return
        }
        if let drag = transitionDrag {
            transitionDrag = nil
            ghostLayer.isHidden = true
            if let duration = drag.duration {
                controller.resizeTransition(drag.transitionID, to: duration)
            }
            return
        }
        if let drag = titleDrag {
            titleDrag = nil
            ghostLayer.isHidden = true
            snapGuideLayer.isHidden = true
            if let result = drag.result {
                switch drag.hit.zone {
                case .body:
                    if result.isValid {
                        controller.commitTitleMove(drag.hit.titleID, to: result.start)
                    }
                case .leadingEdge, .trailingEdge:
                    controller.commitTitleTrim(drag.hit.titleID,
                                               start: result.start,
                                               duration: result.duration)
                }
            }
            let point = convert(event.locationInWindow, from: nil)
            updateCursor(at: point)
            return
        }
        guard controller.interaction.isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let kind = controller.interaction.drag?.kind

        let before = controller.project
        var updated = controller.project
        let changed = (try? controller.interaction.commit(
            atX: point.x, y: point.y,
            into: &updated,
            snapping: snapping(for: event))) ?? false

        switch kind {
        case .move, .slip:
            if changed {
                controller.undo.record(before)
                controller.project = updated
            }
        case .trimStart, .trimEnd, .roll:
            if changed { controller.project = updated }
            // Když se nic nezměnilo, krok nevznikne — hlídá si to stack sám.
            controller.undo.endInteraction(updated)
        case nil:
            break
        }
        updateDragOverlay(nil)
        updateCursor(at: point)
    }

    override func keyDown(with event: NSEvent) {
        // Escape ruší rozjeté tažení. Model se během tažení nesahal, takže
        // stačí zapomenout stav interakce a základnu undo.
        if event.keyCode == 53, fadeDrag != nil {
            fadeDrag = nil
            fadePreview = nil
            refreshClips()
            return
        }
        if event.keyCode == 53, transitionDrag != nil {
            transitionDrag = nil
            ghostLayer.isHidden = true
            return
        }
        if event.keyCode == 53, titleDrag != nil {
            titleDrag = nil
            ghostLayer.isHidden = true
            snapGuideLayer.isHidden = true
            return
        }
        if event.keyCode == 53, bandDrag != nil {
            bandDrag = nil
            bandLayer.isHidden = true
            return
        }
        if event.keyCode == 53, controller.interaction.isDragging {
            controller.interaction.cancel()
            _ = controller.undo.cancelInteraction()
            updateDragOverlay(nil)
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                controller.redoStep()
            } else {
                controller.undoStep()
            }
            return
        }

        // Delete i forward delete mažou výběr (svázaná dvojčata jdou s ním);
        // vybraný titulek má přednost — výběry se navzájem vylučují.
        if event.keyCode == 51 || event.keyCode == 117 {
            if let titleID = controller.selectedTitle {
                controller.deleteTitle(titleID)
            } else if let transitionID = controller.selectedTransition {
                controller.removeTransition(transitionID)
            } else {
                controller.deleteClips(controller.selection)
            }
            return
        }

        // ⌘B = řez vybraných klipů v hlavě (blade, konvence z NLE).
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "b" {
            for clipID in controller.selection {
                controller.splitAtPlayhead(clipID)
            }
            return
        }

        // Schránka (fáze 17, modul 2). ⌘A vybere všechny klipy — bez něj
        // je hromadná operace na dvě stě klipů pořád rámeček přes celou osu.
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": controller.copySelection(); return
            case "x": controller.cutSelection(); return
            case "v": controller.pasteAtPlayhead(); return
            case "a": controller.selectAllClips(); return
            default: break
            }
        }

        // JKL (fáze 17). Písmena bez modifikátoru, proto AŽ za zkratkami
        // s ⌘ — jinak by ⌘J spadlo sem. Zachytává se v ose, ne přes
        // `keyboardShortcut` v SwiftUI: shortcut bez modifikátoru by
        // střílel i při psaní textu titulku.
        // ⇧Z: celá osa do okna. Taky na `keyDown` osy, ne na SwiftUI
        // `keyboardShortcut` — „Z" je při psaní titulku pořád jen písmeno.
        if event.modifierFlags.contains(.shift),
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            controller.onFitRequest?()
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "l": controller.onShuttle?(.forward); return
            case "j": controller.onShuttle?(.backward); return
            case "k": controller.onShuttle?(.pause); return
            // In a out bod výřezu (fáze 17, modul 3) — konvence z NLE.
            // ⌥I / ⌥O bod zase zruší.
            case "i": controller.setInPoint(controller.playhead); return
            case "o": controller.setOutPoint(controller.playhead); return
            default: break
            }
        }
        if event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "i": controller.setInPoint(nil); return
            case "o": controller.setOutPoint(nil); return
            case "x": controller.clearExportRange(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Kurzory (krok 9)

    /// ⚠️ Kurzor pro okraj má dvě jména podle verze systému:
    /// `resizeLeftRight` (od 10.0, deprecated 27.0) a `columnResize`
    /// (až od 15.0). Deployment target je 14.0, proto runtime gate —
    /// stejný vzorec jako `AVMutableVideoComposition` vs `Configuration`.
    private static var edgeCursor: NSCursor {
        if #available(macOS 15.0, *) { return .columnResize }
        return .resizeLeftRight
    }

    /// Přes `NSTrackingArea` s `.cursorUpdate`, NE přes `addCursorRect` —
    /// ta se smí volat jen z `resetCursorRects` a u tisíce klipů by se
    /// obdélníky stejně přestavovaly při každém scrollu. `.inVisibleRect`
    /// drží oblast srovnanou s viditelným výřezem sám. ⚠️ `.cursorUpdate`
    /// se neposílá v kombinaci s `.activeAlways` — proto `.activeInKeyWindow`.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at point: NSPoint) {
        guard !controller.interaction.isDragging,
              transitionDrag == nil, titleDrag == nil else { return }
        // Přechod má přednost i u kurzoru — jeho okraje leží NAD klipy.
        if let transitionHit = controller.geometry.transitionHitTest(
            x: point.x, y: point.y, in: controller.project) {
            switch transitionHit.zone {
            case .leadingEdge, .trailingEdge: Self.edgeCursor.set()
            case .body: NSCursor.arrow.set()
            }
            return
        }
        if let titleHit = controller.geometry.titleHitTest(
            x: point.x, y: point.y, in: controller.project.timeline) {
            switch titleHit.zone {
            case .leadingEdge, .trailingEdge: Self.edgeCursor.set()
            case .body: NSCursor.arrow.set()
            }
            return
        }
        switch controller.geometry.hitTest(x: point.x, y: point.y,
                                           in: controller.project.timeline)?.zone {
        case .leadingEdge, .trailingEdge:
            Self.edgeCursor.set()
        case .body, nil:
            NSCursor.arrow.set()
        }
    }

    // MARK: - Kontextové menu (krok 9)

    /// Klip, na který se ukázalo pravým tlačítkem — cíl akcí menu.
    private var menuClipID: ClipID?
    /// Střih, ke kterému míří položky přechodů — cíl `menuAddTransition`.
    private var menuCut: CutHit?
    /// Přechod pod pravým tlačítkem — cíl `menuRemoveTransition`.
    private var menuTransitionID: TransitionID?
    /// Titulek pod pravým tlačítkem — cíl `menuDeleteTitle`.
    private var menuTitleID: TitleClipID?
    /// Místo na T1, kam míří „Přidat titulek" — snímek a stopa.
    private var menuTitleSpot: (trackID: TrackID, frame: Frames)?
    /// Stopa pod pravým tlačítkem — cíl „Uspořádat chronologicky" (fáze 17).
    private var menuTrackID: TrackID?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)

        // Pravý klik na lichoběžník: menu přechodu, ne klipu pod ním.
        if let transitionHit = controller.geometry.transitionHitTest(
            x: point.x, y: point.y, in: controller.project) {
            menuTransitionID = transitionHit.transitionID
            let menu = NSMenu()
            menu.autoenablesItems = false
            let remove = NSMenuItem(title: "Odebrat přechod",
                                    action: #selector(menuRemoveTransition(_:)),
                                    keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
            return menu
        }

        // Pruh T1 (fáze 11, modul 3): na titulku Smazat, jinde Přidat.
        if let titleHit = controller.geometry.titleHitTest(
            x: point.x, y: point.y, in: controller.project.timeline) {
            controller.selectTitle(titleHit.titleID)
            menuTitleID = titleHit.titleID
            let menu = NSMenu()
            menu.autoenablesItems = false
            let remove = NSMenuItem(title: "Smazat titulek",
                                    action: #selector(menuDeleteTitle(_:)),
                                    keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
            return menu
        }
        if let ti = controller.geometry.trackIndex(atY: point.y,
                                                   in: controller.project.timeline),
           controller.project.timeline.tracks[ti].kind == .title {
            let trackID = controller.project.timeline.tracks[ti].id
            let frame = controller.geometry.frame(atX: point.x)
            menuTitleSpot = (trackID, frame)
            let room = controller.project.maxNewTitleDuration(at: frame, onTrack: trackID)

            let menu = NSMenu()
            menu.autoenablesItems = false
            let templates: [(TitleTemplate, String)] = [
                (.names, "Jména"),
                (.dateAndPlace, "Datum a místo"),
                (.chapter, "Kapitola"),
                (.thanks, "Poděkování"),
                (.plain, "Prostý text"),
            ]
            for (template, name) in templates {
                let item = NSMenuItem(title: "Přidat titulek: \(name)",
                                      action: #selector(menuAddTitle(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = template.rawValue
                item.isEnabled = room.count >= 1
                if room.count < 1 {
                    item.toolTip = "Tady už titulek leží — přidat jde jen do volného místa."
                }
                menu.addItem(item)
            }
            return menu
        }

        guard let hit = controller.geometry.hitTest(x: point.x, y: point.y,
                                                    in: controller.project.timeline) else {
            // Prázdné místo na stopě s klipy: uspořádání a výřez (fáze 17).
            guard let ti = controller.geometry.trackIndex(atY: point.y,
                                                          in: controller.project.timeline),
                  controller.project.timeline.tracks[ti].clips.count > 1 else { return nil }
            menuTrackID = controller.project.timeline.tracks[ti].id

            let menu = NSMenu()
            menu.autoenablesItems = false
            let arrange = NSMenuItem(title: "Uspořádat chronologicky",
                                     action: #selector(menuArrangeChronologically(_:)),
                                     keyEquivalent: "")
            arrange.target = self
            let dated = controller.project.timeline.tracks[ti].clips
                .filter { controller.project.creationDate(of: $0.id) != nil }.count
            arrange.isEnabled = dated > 0
            arrange.toolTip = dated > 0
                ? "Seřadí klipy stopy podle času natočení a zavře mezery."
                : "Žádný klip stopy nemá čas natočení — není podle čeho řadit."
            menu.addItem(arrange)

            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Zrušit výřez exportu",
                                   action: #selector(menuClearExportRange(_:)),
                                   keyEquivalent: "")
            clear.target = self
            clear.isEnabled = controller.hasExportRange
            menu.addItem(clear)
            return menu
        }
        // Pravý klik do klipu, který je součástí výběru, výběr NECHÁ být —
        // jinak by se hromadná akce nedala z menu vůbec spustit (fáze 17).
        if !controller.selection.contains(hit.clipID) {
            controller.selectClips([hit.clipID])
        }
        menuClipID = hit.clipID

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Přechody (fáze 10): jen když se kliklo POBLÍŽ střihu se sousedem.
        // Nedosažitelný druh (chybí zdrojové přesahy, rampa) zůstává v menu
        // vypnutý s vysvětlením — přiznané meze, ne zmizelá položka.
        menuCut = controller.geometry.cutHit(x: point.x, y: point.y,
                                             in: controller.project)
        if let cut = menuCut,
           let track = controller.project.timeline.track(id: cut.trackID) {
            let kinds: [(TransitionKind, String)] = track.kind == .video
                ? [(.crossDissolve, "Prolínačka"),
                   (.dipToBlack, "Zatmívačka do černé"),
                   (.dipToWhite, "Zatmívačka do bílé")]
                : [(.audioCrossfade, "Prolnutí zvuku")]
            for (kind, name) in kinds {
                let maxD = controller.project.maxTransitionDuration(
                    kind: kind, betweenLeft: cut.leftClipID, andRight: cut.rightClipID)
                let item = NSMenuItem(title: "\(name) na střihu",
                                      action: #selector(menuAddTransition(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = kind.rawValue
                item.isEnabled = maxD.count >= 1
                if maxD.count < 1 {
                    item.toolTip = kind.needsSourceOverlap
                        ? "Klipy nemají za hranou střihu dost zdrojového materiálu."
                        : "Na střihu není pro přechod místo."
                }
                menu.addItem(item)
            }
            if let existing = controller.project.transition(
                betweenLeft: cut.leftClipID, andRight: cut.rightClipID) {
                menuTransitionID = existing.id
                let remove = NSMenuItem(title: "Odebrat přechod",
                                        action: #selector(menuRemoveTransition(_:)),
                                        keyEquivalent: "")
                remove.target = self
                menu.addItem(remove)
            }
            menu.addItem(.separator())
        }

        let split = NSMenuItem(title: "Rozdělit v hlavě",
                               action: #selector(menuSplit(_:)), keyEquivalent: "")
        split.target = self
        if let clip = controller.project.timeline.clip(hit.clipID) {
            split.isEnabled = clip.timelineStart < controller.playhead
                && controller.playhead < clip.timelineEnd
        } else {
            split.isEnabled = false
        }
        menu.addItem(split)
        menu.addItem(.separator())

        let delete = NSMenuItem(title: "Smazat",
                                action: #selector(menuDelete(_:)), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)

        let ripple = NSMenuItem(title: "Smazat s dosunutím",
                                action: #selector(menuRippleDelete(_:)), keyEquivalent: "")
        ripple.target = self
        menu.addItem(ripple)

        // Fotka (fáze 12): rampa, sync ani přepis na ní nedávají smysl —
        // položky zůstávají VYPNUTÉ s vysvětlením, nemizí (přiznané meze).
        let menuClip = controller.project.timeline.clip(hit.clipID)
        let isStillClip = menuClip.flatMap { controller.project.asset($0.assetID) }?
            .isStill == true

        // Preset klasického svatebního rampu — jemné doladění je na editoru
        // křivky pod přehrávačem (modul 3).
        menu.addItem(.separator())
        let hasRamp = menuClip?.speedRamp != nil
        // Hromadná varianta (fáze 17): s víc vybranými klipy jede preset
        // na celý výběr. Každý klip dostane rampu počítanou ze SVÉ spotřeby —
        // uzly jsou kotvené ve zdrojovém čase konkrétního záběru, kopírovat
        // je z cizího klipu nejde.
        let videoSelection = controller.selection.filter { id in
            controller.project.timeline.locate(id).map {
                controller.project.timeline.tracks[$0.trackIndex].kind == .video
            } ?? false
        }
        let bulkRamp = videoSelection.count > 1 && videoSelection.contains(hit.clipID)
        let ramp = NSMenuItem(title: bulkRamp
                              ? (hasRamp ? "Zrušit rychlostní křivku (\(videoSelection.count) klipů)"
                                         : "Zpomalit 0,25× (\(videoSelection.count) klipů)")
                              : (hasRamp ? "Zrušit rychlostní křivku"
                                         : "Zpomalit 0,25× (klasický ramp)"),
                              action: #selector(menuToggleRamp(_:)), keyEquivalent: "")
        ramp.target = self
        ramp.isEnabled = !isStillClip || bulkRamp
        if isStillClip && !bulkRamp { ramp.toolTip = "Fotka stojí sama — zpomalovat není co." }
        menu.addItem(ramp)

        // Zmrazit snímek (fáze 12, modul 3): z videa pod hlavou se udělá
        // fotka na konci osy. Jen když hlava vede vnitřkem klipu.
        if !isStillClip {
            let freeze = NSMenuItem(title: "Zmrazit snímek (fotka na konec osy)",
                                    action: #selector(menuFreezeFrame(_:)),
                                    keyEquivalent: "")
            freeze.target = self
            if let clip = menuClip {
                freeze.isEnabled = clip.contains(frame: controller.playhead)
                    && controller.project.timeline.track(id: hit.trackID)?.kind == .video
            } else {
                freeze.isEnabled = false
            }
            if !freeze.isEnabled {
                freeze.toolTip = "Postav hlavu na snímek uvnitř obrazového klipu."
            }
            menu.addItem(freeze)
        }

        // Dopasování na dobu hudby (fáze 14, modul 3). Jestli je akce
        // proveditelná, rozhodne ZKUŠEBNÍ BĚH operace na kopii projektu —
        // menu pak nelže: vypnutá položka nese v tooltipu důvod z chyby
        // modelu (přiznané meze, žádné tiché selhání po kliknutí).
        if !isStillClip,
           controller.project.timeline.track(id: hit.trackID)?.kind == .video {
            menu.addItem(.separator())

            let fit = NSMenuItem(title: "Zarovnat konec na dobu hudby",
                                 action: #selector(menuFitToBeat(_:)), keyEquivalent: "")
            fit.target = self
            var fitProbe = controller.project
            do {
                _ = try fitProbe.fitClipEndToBeat(clipID: hit.clipID)
                fit.isEnabled = true
            } catch let error as TimelineError {
                fit.isEnabled = false
                fit.toolTip = beatFitExcuse(for: error)
            } catch { fit.isEnabled = false }
            menu.addItem(fit)

            let rampBeat = NSMenuItem(title: "Zpomalení na dobu (rampa na úder)",
                                      action: #selector(menuRampToBeat(_:)), keyEquivalent: "")
            rampBeat.target = self
            var rampProbe = controller.project
            do {
                _ = try rampProbe.rampClipToBeat(clipID: hit.clipID,
                                                 near: controller.playhead)
                rampBeat.isEnabled = true
            } catch let error as TimelineError {
                rampBeat.isEnabled = false
                rampBeat.toolTip = beatFitExcuse(for: error)
            } catch { rampBeat.isEnabled = false }
            menu.addItem(rampBeat)
        }

        // Sync klopáku (fáze 7, modul 5). U klipu s rampou vypnuto —
        // zvuk položený lineárně by se s křivkou rozjel.
        menu.addItem(.separator())
        let sync = NSMenuItem(title: "Synchronizovat externí zvuk…",
                              action: #selector(menuSyncAudio(_:)), keyEquivalent: "")
        sync.target = self
        sync.isEnabled = !hasRamp && !isStillClip
        if isStillClip { sync.toolTip = "Fotka nemá zvuk, ke kterému by se synchronizovalo." }
        menu.addItem(sync)

        // Titulky z řeči (fáze 8) — přepis patří assetu, takže stačí
        // jednou na kterémkoli klipu téhož zdroje.
        let transcribe = NSMenuItem(title: "Vytvořit titulky z řeči",
                                    action: #selector(menuTranscribe(_:)), keyEquivalent: "")
        transcribe.target = self
        transcribe.isEnabled = !isStillClip
        if isStillClip { transcribe.toolTip = "Fotka nemá řeč k přepisu." }
        menu.addItem(transcribe)

        return menu
    }

    @objc private func menuFreezeFrame(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.onFreezeFrameRequest?(clipID)
    }

    @objc private func menuAddTitle(_ sender: NSMenuItem) {
        guard let spot = menuTitleSpot,
              let raw = sender.representedObject as? String,
              let template = TitleTemplate(rawValue: raw) else { return }
        controller.addTitle(template: template, at: spot.frame, onTrack: spot.trackID)
    }

    @objc private func menuDeleteTitle(_ sender: Any?) {
        guard let id = menuTitleID else { return }
        controller.deleteTitle(id)
    }

    @objc private func menuAddTransition(_ sender: NSMenuItem) {
        guard let cut = menuCut,
              let raw = sender.representedObject as? String,
              let kind = TransitionKind(rawValue: raw) else { return }
        controller.addTransition(kind, betweenLeft: cut.leftClipID,
                                 andRight: cut.rightClipID)
    }

    @objc private func menuRemoveTransition(_ sender: Any?) {
        guard let id = menuTransitionID else { return }
        controller.removeTransition(id)
    }

    @objc private func menuTranscribe(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.onTranscribeRequest?(clipID)
    }

    @objc private func menuSyncAudio(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.onSyncAudioRequest?(clipID)
    }

    @objc private func menuArrangeChronologically(_ sender: Any?) {
        guard let trackID = menuTrackID else { return }
        controller.arrangeChronologically(trackID: trackID)
    }

    @objc private func menuClearExportRange(_ sender: Any?) {
        controller.clearExportRange()
    }

    @objc private func menuToggleRamp(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        // S víc vybranými klipy jede dávka (jeden undo krok, přeskočené
        // klipy se přiznají ve stavu); jinak jen ten pod kurzorem.
        if controller.selection.count > 1, controller.selection.contains(clipID) {
            controller.toggleClassicRampOnSelection()
        } else {
            controller.toggleClassicRamp(clipID)
        }
    }

    @objc private func menuFitToBeat(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.fitClipEndToBeat(clipID)
    }

    @objc private func menuRampToBeat(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.rampClipToBeat(clipID)
    }

    /// Důvod, proč dopasování nejde — z chyby modelu na lidskou radu.
    /// Plán F14: při velké odchylce NEVYNUCOVAT, nabídnout trim nebo jiný bod.
    ///
    /// Text drží `TimelineError.beatFitReason` — od fáze 18 ho čte i připnutý
    /// panel a dvě kopie téhož by se rozešly, jakmile v modelu přibude případ.
    private func beatFitExcuse(for error: TimelineError) -> String {
        error.beatFitReason(frameRate: controller.project.timeline.frameRate)
    }

    @objc private func menuSplit(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.splitAtPlayhead(clipID)
    }

    @objc private func menuDelete(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.deleteClips([clipID])
    }

    @objc private func menuRippleDelete(_ sender: Any?) {
        guard let clipID = menuClipID else { return }
        controller.rippleDelete(clipID)
    }

    // MARK: - Zoom (krok 8)

    /// Kotvení a přerozměření dělá pane — vlastní scroll view i pravítko.
    private var pane: TimelinePane? {
        enclosingScrollView?.superview as? TimelinePane
    }

    /// Pinch. `magnification` je PŘÍRŮSTEK, ne absolutní hodnota.
    /// <https://developer.apple.com/documentation/appkit/nsevent/magnification>
    override func magnify(with event: NSEvent) {
        pane?.zoom(scale: 1 + Double(event.magnification),
                   atWindowLocation: event.locationInWindow)
    }

    /// ⌘ + kolečko/trackpad = zoom; bez ⌘ jde událost dál a scroll view
    /// normálně scrolluje. Událost dostává dokument dřív než scroll view,
    /// takže se dá takhle vybrat, co si nechat.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let scale = 1 + Double(event.scrollingDeltaY) * 0.015
        pane?.zoom(scale: scale, atWindowLocation: event.locationInWindow)
    }

    // MARK: - Kreslení náhledu tažení

    /// Přepíše duchy podle `DragPreview`, `nil` všechno schová.
    private func updateDragOverlay(_ preview: DragPreview?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let preview else {
            ghostLayer.isHidden = true
            partnerGhostLayer.isHidden = true
            snapGuideLayer.isHidden = true
            return
        }

        let timeline = controller.project.timeline
        let geometry = controller.geometry

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = preview.isValid ? TimelinePalette.clipSelectedStroke
                                         : TimelinePalette.playhead
            ghostLayer.borderColor = accent.cgColor
            ghostLayer.backgroundColor = accent.withAlphaComponent(0.22).cgColor
            partnerGhostLayer.borderColor = accent.cgColor
            partnerGhostLayer.backgroundColor = accent.withAlphaComponent(0.12).cgColor
            snapGuideLayer.backgroundColor = TimelinePalette.clipSelectedStroke.cgColor
        }

        ghostLayer.isHidden = false
        ghostLayer.frame = ghostFrame(trackID: preview.trackID,
                                      start: preview.start, duration: preview.duration,
                                      timeline: timeline, geometry: geometry)

        if let partner = preview.partner {
            partnerGhostLayer.isHidden = false
            partnerGhostLayer.frame = ghostFrame(trackID: preview.trackID,
                                                 start: partner.start, duration: partner.duration,
                                                 timeline: timeline, geometry: geometry)
        } else {
            partnerGhostLayer.isHidden = true
        }

        if let snapped = preview.snappedTo {
            snapGuideLayer.isHidden = false
            let x = geometry.x(for: snapped.frame)
            snapGuideLayer.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: bounds.height)
        } else {
            snapGuideLayer.isHidden = true
        }
    }

    private func ghostFrame(trackID: TrackID, start: Frames, duration: Frames,
                            timeline: Timeline, geometry: TimelineGeometry) -> CGRect {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
            return .zero
        }
        return CGRect(x: geometry.x(for: start),
                      y: geometry.y(ofTrackAt: index, in: timeline),
                      width: geometry.width(of: duration),
                      height: geometry.height(of: timeline.tracks[index].kind))
    }
}
