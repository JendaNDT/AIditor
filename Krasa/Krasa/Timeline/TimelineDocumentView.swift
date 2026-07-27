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

    private static func adaptive(_ name: String,
                                 dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        }
    }

    private static func adaptive(_ name: String,
                                 dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// Plocha pod stopami a za koncem projektu.
    static let background = adaptive("timelineBackground", dark: 0.09, light: 0.78)
    /// Pruh obrazové stopy. Nejsvětlejší — obraz je hlavní.
    static let videoLane = adaptive("timelineVideoLane", dark: 0.24, light: 0.95)
    /// Pruh zvukové stopy.
    static let audioLane = adaptive("timelineAudioLane", dark: 0.17, light: 0.88)

    static func lane(for kind: TrackKind) -> NSColor {
        kind == .video ? videoLane : audioLane
    }

    /// Pozadí pravítka a hlaviček. Mezi pozadím osy a pruhy, ať je poznat,
    /// že je to ovládací lišta a ne obsah.
    static let chrome = adaptive("timelineChrome", dark: 0.14, light: 0.86)
    /// Popisky timecode a jména stop.
    static let text = adaptive("timelineText", dark: 0.68, light: 0.28)
    /// Rysky pravítka.
    static let tick = adaptive("timelineTick", dark: 0.42, light: 0.52)
    /// Předěly mezi pravítkem, hlavičkami a plochou osy.
    static let separator = adaptive("timelineSeparator", dark: 0.28, light: 0.66)

    // MARK: Klipy
    //
    // Jediné barevné plochy na ose. Modrá pro obraz a zelená pro zvuk je
    // konvence, kterou zná každý, kdo kdy viděl NLE — není důvod vymýšlet
    // vlastní. Výplně jsou tlumené, aby na nich stálo písmo.

    /// Výplň obrazového klipu.
    static let clipVideoFill = adaptive(
        "clipVideoFill",
        dark: NSColor(calibratedRed: 0.23, green: 0.34, blue: 0.55, alpha: 1),
        light: NSColor(calibratedRed: 0.58, green: 0.69, blue: 0.87, alpha: 1))
    /// Výplň zvukového klipu.
    static let clipAudioFill = adaptive(
        "clipAudioFill",
        dark: NSColor(calibratedRed: 0.16, green: 0.41, blue: 0.30, alpha: 1),
        light: NSColor(calibratedRed: 0.56, green: 0.78, blue: 0.64, alpha: 1))
    /// Obrys klipu — ztmavená hrana, ať se sousedící klipy neslijí.
    static let clipStroke = adaptive(
        "clipStroke",
        dark: NSColor(white: 0, alpha: 0.45),
        light: NSColor(white: 0, alpha: 0.25))
    /// Obrys vybraného klipu. Výběr přijde s krokem 7, barva ale patří sem,
    /// ať se paleta nerozšiřuje nadvakrát.
    static let clipSelectedStroke = adaptive(
        "clipSelectedStroke",
        dark: NSColor(calibratedRed: 1.00, green: 0.79, blue: 0.28, alpha: 1),
        light: NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.00, alpha: 1))
    /// Jméno klipu.
    static let clipText = adaptive("clipText", dark: 0.94, light: 0.10)

    /// Přehrávací hlava. Červená je konvence — jediná svislá červená čára
    /// v celém okně, nesmí se s ničím plést.
    static let playhead = adaptive(
        "timelinePlayhead",
        dark: NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1),
        light: NSColor(calibratedRed: 0.80, green: 0.00, blue: 0.05, alpha: 1))
}

/// Vrstva jednoho klipu. ŽÁDNÉ kreslení — jen barvy, obrys a `CATextLayer`
/// se jménem. Kreslené view by tu dostalo vadnou celookenní `ContentLayer`
/// (viz `TimelinePane`), vrstvy s barvami jsou imunní.
final class ClipLayer: CALayer {

    let title = CATextLayer()

    override init() {
        super.init()
        cornerRadius = 3
        masksToBounds = true
        borderWidth = 1
        title.fontSize = 11
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.truncationMode = .end
        addSublayer(title)
    }

    /// Core Animation si přes tenhle init dělá kopie pro prezentační strom.
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
    /// Fond odložených vrstev. Vrstva se nikdy nezahazuje, jen odpojuje —
    /// zakládání vrstev při každém scrollnutí je přesně to, čemu se recyklací
    /// předchází.
    private var clipLayerPool: [ClipLayer] = []

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
    func rebuildLanes() {
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for clipID in diff.toRecycle {
            guard let layer = mountedClipLayers.removeValue(forKey: clipID) else { continue }
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
                apply(placement, to: layer)
            }
        }
    }

    /// Rámec, barvy a jméno jedné vrstvy. Volat UVNITŘ
    /// `performAsCurrentDrawingAppearance` — `cgColor` se vyhodnocuje pro
    /// aktuální appearance a vrstva si výsledek pamatuje jako hodnotu.
    private func apply(_ placement: TimelineLayout.Placement, to layer: ClipLayer) {
        layer.frame = CGRect(x: placement.x, y: placement.y,
                             width: placement.width, height: placement.height)

        let kind = controller.project.timeline.track(id: placement.trackID)?.kind ?? .video
        let fill = kind == .video ? TimelinePalette.clipVideoFill : TimelinePalette.clipAudioFill
        layer.backgroundColor = fill.cgColor
        layer.borderColor = placement.isSelected
            ? TimelinePalette.clipSelectedStroke.cgColor
            : TimelinePalette.clipStroke.cgColor
        layer.borderWidth = placement.isSelected ? 2 : 1

        layer.title.string = clipName(placement.clipID)
        layer.title.foregroundColor = TimelinePalette.clipText.cgColor
        layer.title.frame = CGRect(x: 6, y: 2,
                                   width: max(0, placement.width - 12), height: 15)
    }

    /// Jméno souboru bez přípony. Klip vlastní jméno nemá — bere ho z assetu.
    private func clipName(_ clipID: ClipID) -> String {
        guard let clip = controller.project.timeline.clip(clipID),
              let asset = controller.project.asset(clip.assetID) else { return "—" }
        return asset.originalURL.deletingPathExtension().lastPathComponent
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        guard let hit = controller.geometry.hitTest(x: point.x, y: point.y,
                                                    in: controller.project.timeline) else {
            if !controller.selection.isEmpty { controller.selection = [] }
            return
        }

        if controller.selection != [hit.clipID] { controller.selection = [hit.clipID] }
        controller.interaction.begin(hit: hit, in: controller.project,
                                     playhead: controller.playhead)

        // Roll a slip mají modifikátory až v kroku 9; trim vzniká ze zóny.
        switch controller.interaction.drag?.kind {
        case .trimStart, .trimEnd, .roll:
            controller.undo.beginInteraction(controller.project)
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard controller.interaction.isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let preview = controller.interaction.preview(
            atX: point.x, y: point.y,
            in: controller.project,
            snapping: !event.modifierFlags.contains(.shift))
        updateDragOverlay(preview)
    }

    override func mouseUp(with event: NSEvent) {
        guard controller.interaction.isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let kind = controller.interaction.drag?.kind

        let before = controller.project
        var updated = controller.project
        let changed = (try? controller.interaction.commit(
            atX: point.x, y: point.y,
            into: &updated,
            snapping: !event.modifierFlags.contains(.shift))) ?? false

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
    }

    override func keyDown(with event: NSEvent) {
        // Escape ruší rozjeté tažení. Model se během tažení nesahal, takže
        // stačí zapomenout stav interakce a základnu undo.
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
        super.keyDown(with: event)
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
