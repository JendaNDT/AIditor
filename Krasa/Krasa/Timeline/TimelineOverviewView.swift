//
//  TimelineOverviewView.swift
//  Projekt Krása
//
//  Přehled celé osy — fáze 18, modul 6. Pás 46 bodů pod stopami: bloky
//  klipů, hlava, rámeček viditelného výřezu, celková délka.
//
//  ⚠️ VLASTNÍ MAPOVÁNÍ, NE `TimelineGeometry`. Geometrie osy je o ZOOMU:
//  převádí snímky na body podle `pointsPerFrame`. Přehled je přesně naopak —
//  vždycky ukazuje CELOU osu na své šířce, ať je zoom jakýkoli. Kdyby se
//  počítal geometrií, měnil by se s pinchem a nebylo by k čemu se v něm
//  vztahovat.
//
//  ⚠️ ŽÁDNÉ `draw(_:)`. Kreslí se vrstvami (past s celookenní `ContentLayer`
//  u `TimelinePane` sice platí jen pro kořen representable, ale hlavní důvod
//  je jiný): hlava a rámeček výřezu se hýbou při každém tiku přehrávání
//  a při každém scrollnutí, a to má být přepis rámce jedné vrstvy, ne
//  překreslení celého pásu.
//
//  ⚠️ BLOKY SE SLÉVAJÍ. Na hodinové ose je klip široký půl bodu — dvě tisícovky
//  vrstev, ze kterých je stejně jen šmouha. Sousedící klipy, mezi kterými by
//  byla mezera pod bod, se proto slévají do jednoho bloku: přehled říká „tady
//  je materiál a tady díra", ne „tady je 2000 klipů".
//

import AppKit
import TimelineModel

final class TimelineOverviewView: NSView {

    /// Výška pásu podle návrhu.
    static let height: CGFloat = 46

    /// Vnitřní pás s bloky (návrh: 26 bodů, radius 5).
    private static let stripHeight: Double = 26
    /// Popisek „přehled" vlevo a celková délka vpravo.
    private static let labelWidth: Double = 56
    private static let durationWidth: Double = 68
    private static let padding: Double = 12
    private static let gap: Double = 10
    /// Odsazení bloků od hran pásu, aby se nelepily na obrys.
    private static let inset: Double = 2

    private let controller: TimelineController

    /// Klik do přehledu = skok hlavou. Překládá `TimelinePane`.
    var onSeek: ((Frames) -> Void)?
    /// Tažení rámečku = scroll osy. Předává se cílový `scrollX` v bodech
    /// DOKUMENTU osy — přehled o scroll view nic neví.
    var onScrollTo: ((Double) -> Void)?
    /// Začátek a konec tažení rámečku. `TimelinePane` tím vypíná následování
    /// hlavy — dvě ruce na jednom scrollu je past, před kterou varuje plán
    /// (riziko modulu 6).
    var onViewportDragChange: ((Bool) -> Void)?

    private let stripLayer = CALayer()
    private var videoBlocks: [CALayer] = []
    private var audioBlocks: [CALayer] = []
    private let playheadLayer = CALayer()
    private let viewportLayer = CALayer()
    private let label = CATextLayer()
    private let durationLabel = CATextLayer()

    /// Otisk toho, z čeho jsou bloky postavené. Přestavba je drahá (na dlouhé
    /// ose desítky vrstev), a `reload()` v `TimelinePane` chodí i při zoomu,
    /// kdy se v přehledu NEMĚNÍ NIC — otisk ten případ utne.
    private struct BlockFingerprint: Equatable {
        let duration: Int
        let clipCount: Int
        let width: Double
    }
    private var lastFingerprint: BlockFingerprint?

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true

        stripLayer.cornerRadius = 5
        stripLayer.borderWidth = 1
        stripLayer.masksToBounds = true
        layer?.addSublayer(stripLayer)

        viewportLayer.cornerRadius = 4
        viewportLayer.borderWidth = 1
        stripLayer.addSublayer(viewportLayer)
        stripLayer.addSublayer(playheadLayer)

        // ⚠️ Animace se vypínají PŘES `actions`, ne transakcí u každého
        // zápisu. Hlava a rámeček se hýbou při každém tiku scrollu i
        // přehrávání, a `CATransaction.commit()` v té cestě je drahý:
        // změřeno 30. 07. 2026, medián práce na tik vyskočil z 1,00 na
        // 2,46 ms. `actions` s `NSNull()` udělá totéž (žádná animace) a nechá
        // vrstvy odejít v běžném cyklu smyčky.
        // <https://developer.apple.com/documentation/quartzcore/calayer/actions>
        for moving in [playheadLayer, viewportLayer] {
            moving.actions = ["position": NSNull(), "bounds": NSNull(),
                              "frame": NSNull(), "hidden": NSNull()]
        }

        for text in [label, durationLabel] {
            text.fontSize = 9
            text.font = NSFont.systemFont(ofSize: 9)
            layer?.addSublayer(text)
        }
        label.string = "přehled"
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        durationLabel.alignmentMode = .right

        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    /// Stejná soustava jako zbytek osy — počátek vlevo nahoře.
    override var isFlipped: Bool { true }

    // MARK: - Mapování

    /// Plocha pásu v souřadnicích view.
    private var stripFrame: CGRect {
        let x = Self.padding + Self.labelWidth + Self.gap
        let right = Double(bounds.width) - Self.padding - Self.durationWidth - Self.gap
        return CGRect(x: x, y: (Double(bounds.height) - Self.stripHeight) / 2,
                      width: max(0, right - x), height: Self.stripHeight)
    }

    /// Šířka, na kterou se mapuje celá osa (bez odsazení u obrysu).
    private var usableWidth: Double { max(1, Double(stripFrame.width) - 2 * Self.inset) }

    /// Délka osy ve snímcích. **Uložená, ne počítaná.**
    ///
    /// ⚠️ `Project.duration` prochází VŠECHNY klipy a alokuje přitom dvě pole
    /// (`flatMap` + `map` v `Queries.swift`). Na 2000 klipech to stojí
    /// **1,5 ms**, a přehled tu hodnotu potřebuje při každém tiku scrollu
    /// (rámeček výřezu) i přehrávání (hlava). První verze modulu 6 ji volala
    /// pokaždé a medián práce na tik vyskočil z **0,95 na 2,45 ms** — čtvrtina
    /// rozpočtu z jednoho zdánlivě nevinného přístupu k vlastnosti.
    /// Aktualizuje se v `rebuild()`, tedy tam, kde se délka mění.
    private var cachedTotalFrames: Double = 1
    private var totalFrames: Double { cachedTotalFrames }

    /// Kolik snímků osy padne na jeden bod přehledu. Na hodinové ose jsou to
    /// stovky — proto je tolerance kliknutí VLASTNOST PŘEHLEDU, ne chyba
    /// (viz `--overview-check`).
    var framesPerPoint: Double { totalFrames / usableWidth }

    // MARK: Měřicí okna pro `--overview-check`

    /// Kolikrát se opravdu přestavovaly bloky. Kritérium „reload při zoomu
    /// přehled nepřestavuje" se nedá měřit časem (je to pod šumem), ale tímhle
    /// počítadlem ano.
    private(set) var rebuildCount = 0
    var measuredStripFrame: CGRect { stripFrame }
    var measuredInset: Double { Self.inset }
    /// `nil` = rámeček se nekreslí (celá osa je ve výřezu).
    var measuredViewportFrame: CGRect? { viewportLayer.isHidden ? nil : viewportLayer.frame }
    var measuredBlockCounts: (video: Int, audio: Int) {
        (videoBlocks.filter { !$0.isHidden }.count,
         audioBlocks.filter { !$0.isHidden }.count)
    }

    /// Snímek → x v souřadnicích PÁSU (ne view).
    private func x(for frame: Frames) -> Double {
        Self.inset + usableWidth * min(1, max(0, Double(frame.count) / totalFrames))
    }

    /// x v souřadnicích pásu → snímek.
    private func frame(atStripX x: Double) -> Frames {
        let unit = min(1, max(0, (x - Self.inset) / usableWidth))
        return Frames(Int((unit * totalFrames).rounded()))
    }

    // MARK: - Rozvržení

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        stripLayer.frame = stripFrame
        label.frame = CGRect(x: Self.padding, y: (Double(bounds.height) - 12) / 2,
                             width: Self.labelWidth, height: 12)
        durationLabel.frame = CGRect(
            x: Double(bounds.width) - Self.padding - Self.durationWidth,
            y: (Double(bounds.height) - 12) / 2,
            width: Self.durationWidth, height: 12)

        rebuild()
        syncPlayhead()
    }

    /// Přestavba bloků. Volá se z `reload()` osy; vlastní práci udělá jen
    /// když se opravdu změnil projekt nebo šířka.
    func rebuild() {
        let project = controller.project
        let duration = project.duration
        // Jediné místo, kde se `duration` čte — a rovnou se uloží.
        cachedTotalFrames = Double(max(1, duration.count))
        let fingerprint = BlockFingerprint(
            duration: duration.count,
            clipCount: project.timeline.tracks.reduce(0) { $0 + $1.clips.count },
            width: Double(stripFrame.width))
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        rebuildCount += 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        durationLabel.string = Timecode(duration,
                                        frameRate: project.timeline.frameRate).text

        // Návrh: obraz 9 bodů u horní hrany pásu, zvuk 8 pod ním.
        layout(blocks: &videoBlocks,
               spans: spans(of: project, kind: .video),
               y: 3, height: 9,
               color: TimelinePalette.clipVideoFill.cgColor)
        layout(blocks: &audioBlocks,
               spans: spans(of: project, kind: .audio),
               y: 14, height: 8,
               color: TimelinePalette.clipAudioFill.cgColor)

        syncViewport()
    }

    /// Slité úseky, kde na stopách daného druhu leží materiál — v bodech pásu.
    /// Titulková stopa se nekreslí: v pásu 26 bodů na ni není místo a návrh ji
    /// v přehledu taky nemá.
    private func spans(of project: Project, kind: TrackKind) -> [(x: Double, width: Double)] {
        var edges: [(start: Double, end: Double)] = []
        for track in project.timeline.tracks where track.kind == kind {
            for clip in track.clips {
                edges.append((x(for: clip.timelineStart), x(for: clip.timelineEnd)))
            }
        }
        guard !edges.isEmpty else { return [] }
        edges.sort { $0.start < $1.start }

        var merged: [(start: Double, end: Double)] = []
        for edge in edges {
            // Slévá se, když by mezi bloky byla mezera pod bod — na dlouhé ose
            // by se jinak kreslily tisíce nerozlišitelných vrstev. Dvě stopy
            // téhož druhu (A1 řeč, A2 hudba) tím splynou v jeden pruh, přesně
            // jak to má návrh.
            if var last = merged.last, edge.start <= last.end + 1 {
                last.end = max(last.end, edge.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(edge)
            }
        }
        return merged.map { (x: $0.start, width: max(2, $0.end - $0.start)) }
    }

    private func layout(blocks: inout [CALayer],
                        spans: [(x: Double, width: Double)],
                        y: Double, height: Double, color: CGColor) {
        while blocks.count < spans.count {
            let block = CALayer()
            block.cornerRadius = 2
            // Bloky patří POD rámeček výřezu a hlavu, jinak by je zakryly.
            stripLayer.insertSublayer(block, at: 0)
            blocks.append(block)
        }
        for (index, block) in blocks.enumerated() {
            guard index < spans.count else { block.isHidden = true; continue }
            block.isHidden = false
            block.backgroundColor = color
            block.frame = CGRect(x: spans[index].x, y: y,
                                 width: spans[index].width, height: height)
        }
    }

    // MARK: - Hlava a výřez

    /// Hlava se hýbe 30×/s — jen přepis rámce jedné vrstvy, bez transakce
    /// (animaci drží `actions`, viz init).
    func syncPlayhead() {
        playheadLayer.frame = CGRect(x: x(for: controller.playhead) - 1, y: 0,
                                     width: 2, height: Self.stripHeight)
    }

    /// Rámeček viditelného výřezu. Píše ho `TimelinePane` při každém scrollu
    /// a při zoomu — dvě čísla v bodech DOKUMENTU osy.
    var visibleDocumentRange: (origin: Double, width: Double) = (0, 0) {
        didSet {
            guard visibleDocumentRange != oldValue else { return }
            syncViewport()
        }
    }

    private func syncViewport() {
        let pointsPerFrame = controller.geometry.pointsPerFrame
        guard pointsPerFrame > 0, visibleDocumentRange.width > 0 else {
            if !viewportLayer.isHidden { viewportLayer.isHidden = true }
            return
        }
        let fromFrame = visibleDocumentRange.origin / pointsPerFrame
        let toFrame = (visibleDocumentRange.origin + visibleDocumentRange.width) / pointsPerFrame
        let fromX = Self.inset + usableWidth * min(1, max(0, fromFrame / totalFrames))
        let toX = Self.inset + usableWidth * min(1, max(0, toFrame / totalFrames))

        // Celá osa ve výřezu (odzoomováno na fit) → rámeček se NEKRESLÍ.
        // Rámeček přes celý pás a žádný rámeček by vypadaly stejně, a přitom
        // znamenají dvě různé věci (vzorec pruhu výřezu v pravítku, F17).
        let hidden = toX - fromX >= usableWidth - 1
        if viewportLayer.isHidden != hidden { viewportLayer.isHidden = hidden }
        viewportLayer.frame = CGRect(x: fromX, y: 0,
                                     width: max(6, toX - fromX), height: Self.stripHeight)
    }

    // MARK: - Barvy

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = TimelinePalette.overviewBackground.cgColor
            stripLayer.backgroundColor = TimelinePalette.overviewStrip.cgColor
            stripLayer.borderColor = TimelinePalette.separator.cgColor
            playheadLayer.backgroundColor = TimelinePalette.playhead.cgColor
            viewportLayer.backgroundColor = TimelinePalette.clipSelectedStroke
                .withAlphaComponent(0.08).cgColor
            viewportLayer.borderColor = TimelinePalette.clipSelectedStroke
                .withAlphaComponent(0.7).cgColor
            label.foregroundColor = TimelinePalette.headerMeta.cgColor
            durationLabel.foregroundColor = TimelinePalette.headerMeta.cgColor
            CATransaction.commit()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        stripLayer.contentsScale = scale
        label.contentsScale = scale
        durationLabel.contentsScale = scale
        for block in videoBlocks + audioBlocks { block.contentsScale = scale }
    }

    // MARK: - Události

    /// Probíhající tažení rámečku: kde v rámečku myš „chytila".
    private var viewportGrabOffset: Double?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard stripFrame.contains(point) else { return }
        let stripX = Double(point.x) - Double(stripFrame.origin.x)

        // Uvnitř rámečku se TÁHNE, jinde se SKÁČE hlavou. Kdyby klik uvnitř
        // rámečku skákal hlavou, nešel by výřez uchopit — a to je jediný
        // způsob, jak se v přehledu naviguje bez přesouvání hlavy.
        if !viewportLayer.isHidden, viewportLayer.frame.insetBy(dx: -3, dy: 0)
            .contains(CGPoint(x: stripX, y: Double(point.y) - Double(stripFrame.origin.y))) {
            viewportGrabOffset = stripX - Double(viewportLayer.frame.origin.x)
            onViewportDragChange?(true)
            return
        }
        onSeek?(frame(atStripX: stripX))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let stripX = Double(point.x) - Double(stripFrame.origin.x)

        if let grab = viewportGrabOffset {
            scroll(toViewportLeft: stripX - grab)
        } else if stripFrame.insetBy(dx: 0, dy: -Self.height).contains(point) {
            // Tažení po pásu vede hlavu dál — jinak by se muselo klikat po
            // krocích. Svisle se tolerance pouští: při rychlém tažení myš
            // z pásu vyjede a hlava by se zastavila na místě.
            onSeek?(frame(atStripX: stripX))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if viewportGrabOffset != nil {
            viewportGrabOffset = nil
            onViewportDragChange?(false)
        }
    }

    /// Levá hrana rámečku v bodech pásu → scroll osy v bodech dokumentu.
    private func scroll(toViewportLeft stripX: Double) {
        let unit = (stripX - Self.inset) / usableWidth
        let frame = unit * totalFrames
        onScrollTo?(max(0, frame * controller.geometry.pointsPerFrame))
    }
}
