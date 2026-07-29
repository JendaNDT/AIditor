//
//  RampEditorView.swift
//  Projekt Krása
//
//  Editor rychlostní křivky (fáze 3, modul 3). Do view patří kreslení
//  a předávání událostí — souřadnice, uzly, meze i tažení počítá
//  `TimelineModel` (`RampEditorScale`, `rampEditorNodes`, `RampNodeDrag`).
//
//  ⚠️ ŽÁDNÉ `draw(_:)` — kořen `NSViewRepresentable` s kreslením dostane na
//  macOS 26 vadnou celookenní `ContentLayer` a překryje přehrávač (viz
//  rizika v PROJECT_STATUS.md). Všechno jsou vrstvy: zóna, mřížka, křivka
//  jako `CAShapeLayer` path, uzly jako kolečka.
//
//  Undo přesně podle vzorce trimu: mezistavy tažení jsou legální, takže se
//  zapisují průběžně a `beginInteraction`/`endInteraction` z nich složí
//  jeden krok. Escape tažení ruší.
//

import AppKit
import Combine
import SwiftUI
import TimelineModel

/// Barvy editoru — stejný vzorec `NSColor(name:dynamicProvider:)` jako
/// `TimelinePalette`, jen pár položek navíc.
private enum RampEditorPalette {
    /// Jen tmavá varianta — viz `TimelinePalette.adaptive` (fáze 18).
    private static func adaptive(_ name: String, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { _ in dark }
    }

    /// Čára křivky. Výrazná — je to hlavní obsah editoru.
    static let curve = adaptive("rampCurve",
        dark: NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1))
    /// Výplň uzlu.
    static let node = adaptive("rampNode",
        dark: NSColor(white: 0.92, alpha: 1))
    /// Žlutá zóna pod mezí čistého zpomalení. Průhledná — je to podklad,
    /// ne obsah.
    static let zone = adaptive("rampZone",
        dark: NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 0.16))
    /// Hranice žluté zóny a text varování.
    static let zoneEdge = adaptive("rampZoneEdge",
        dark: NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 0.9))
}

final class RampEditorView: NSView {

    private let controller: TimelineController
    private var subscriptions: [AnyCancellable] = []

    private let scale = RampEditorScale()

    // Vrstvy odspodu nahoru: zóna, mřížka, křivka, uzly, texty.
    private let zoneLayer = CALayer()
    private let zoneEdgeLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let curveLayer = CAShapeLayer()
    private var nodeLayers: [CAShapeLayer] = []
    private var gridLabels: [CATextLayer] = []
    private let warningLabel = CATextLayer()
    private let placeholderLabel = CATextLayer()

    /// Rozjeté tažení uzlu. Mapování jde přes základnu zachycenou při stisku.
    private var drag: RampNodeDrag?
    private var selectedNodeIndex: Int?

    // MARK: - Init

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true

        gridLayer.fillColor = nil
        gridLayer.lineWidth = 1
        zoneEdgeLayer.fillColor = nil
        zoneEdgeLayer.lineWidth = 1
        zoneEdgeLayer.lineDashPattern = [4, 3]
        curveLayer.fillColor = nil
        curveLayer.lineWidth = 2
        curveLayer.lineJoin = .round

        warningLabel.fontSize = 11
        warningLabel.alignmentMode = .right
        placeholderLabel.fontSize = 12
        placeholderLabel.alignmentMode = .center

        for sublayer in [zoneLayer, zoneEdgeLayer, gridLayer, curveLayer] as [CALayer] {
            layer?.addSublayer(sublayer)
        }
        layer?.addSublayer(warningLabel)
        layer?.addSublayer(placeholderLabel)

        applyColors()

        // Stejný důvod jako u `TimelinePane`: `updateNSView` se přeskočí,
        // když se reference na controller nezměnila — view si o změnách
        // říká samo. `receive(on:)` kvůli `willSet` publisheru.
        subscriptions = [
            controller.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
            controller.$selection
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.selectedNodeIndex = nil
                    self?.reload()
                },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        reload()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        reload()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let backingScale = window?.backingScaleFactor ?? 2
        (gridLabels + [warningLabel, placeholderLabel]).forEach {
            $0.contentsScale = backingScale
        }
    }

    // MARK: - Geometrie plochy

    /// Okraje: vlevo místo na popisky rychlostí, jinak těsné.
    private var plotRect: CGRect {
        bounds.insetBy(dx: 0, dy: 6)
            .divided(atDistance: 46, from: .minXEdge).remainder
            .divided(atDistance: 8, from: .maxXEdge).remainder
    }

    private func x(forFrame frame: Double, duration: Double) -> CGFloat {
        let plot = plotRect
        guard duration > 0 else { return plot.minX }
        return plot.minX + CGFloat(frame / duration) * plot.width
    }

    private func frame(atX x: CGFloat, duration: Double) -> Double {
        let plot = plotRect
        guard plot.width > 0 else { return 0 }
        return Double((x - plot.minX) / plot.width) * duration
    }

    /// `isFlipped`, takže vyšší rychlost = menší y.
    private func y(forSpeed speed: Double) -> CGFloat {
        let plot = plotRect
        return plot.maxY - CGFloat(scale.unit(ofSpeed: speed)) * plot.height
    }

    private func speed(atY y: CGFloat) -> Double {
        let plot = plotRect
        guard plot.height > 0 else { return 1 }
        return scale.speed(atUnit: Double((plot.maxY - y) / plot.height))
    }

    /// Klip v editoru: právě jeden vybraný.
    private var editedClip: Clip? {
        guard controller.selection.count == 1,
              let id = controller.selection.first else { return nil }
        return controller.project.timeline.clip(id)
    }

    // MARK: - Kreslení (skládání vrstev)

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = TimelinePalette.chrome.cgColor
            zoneLayer.backgroundColor = RampEditorPalette.zone.cgColor
            zoneEdgeLayer.strokeColor = RampEditorPalette.zoneEdge.cgColor
            gridLayer.strokeColor = TimelinePalette.separator.cgColor
            curveLayer.strokeColor = RampEditorPalette.curve.cgColor
            warningLabel.foregroundColor = RampEditorPalette.zoneEdge.cgColor
            placeholderLabel.foregroundColor = TimelinePalette.text.cgColor
        }
    }

    func reload() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let clip = editedClip else {
            showPlaceholder("Vyber na ose klip — křivku rychlosti edituješ tady. Dvojklik přidá uzel.")
            return
        }
        placeholderLabel.isHidden = true

        let project = controller.project
        let duration = Double(clip.duration.count)
        let plot = plotRect

        drawGrid(plot: plot)
        drawZone(limit: project.pureSlowdownLimit(of: clip), plot: plot)
        drawCurve(project: project, clip: clip, duration: duration, plot: plot)
        drawNodes(project: project, clip: clip, duration: duration)
        updateWarning(project: project, clip: clip, plot: plot)
    }

    private func showPlaceholder(_ text: String) {
        zoneLayer.isHidden = true
        zoneEdgeLayer.isHidden = true
        gridLayer.isHidden = true
        curveLayer.isHidden = true
        warningLabel.isHidden = true
        nodeLayers.forEach { $0.isHidden = true }
        gridLabels.forEach { $0.isHidden = true }

        placeholderLabel.isHidden = false
        placeholderLabel.string = text
        placeholderLabel.frame = CGRect(x: 0, y: bounds.midY - 8,
                                        width: bounds.width, height: 16)
        placeholderLabel.contentsScale = window?.backingScaleFactor ?? 2
    }

    private func drawGrid(plot: CGRect) {
        gridLayer.isHidden = false
        let path = CGMutablePath()
        // Vodicí čáry rychlostí; 1× je kotva a kreslí se přes celou šířku
        // stejně, jen popisek je výraznější.
        for speed in RampEditorScale.gridSpeeds {
            let lineY = y(forSpeed: speed)
            path.move(to: CGPoint(x: plot.minX, y: lineY))
            path.addLine(to: CGPoint(x: plot.maxX, y: lineY))
        }
        gridLayer.path = path

        while gridLabels.count < RampEditorScale.gridSpeeds.count {
            let label = CATextLayer()
            label.fontSize = 9
            label.alignmentMode = .right
            layer?.addSublayer(label)
            gridLabels.append(label)
        }
        let backingScale = window?.backingScaleFactor ?? 2
        for (index, speed) in RampEditorScale.gridSpeeds.enumerated() {
            let label = gridLabels[index]
            label.isHidden = false
            label.string = Self.speedLabel(speed)
            label.contentsScale = backingScale
            label.frame = CGRect(x: 0, y: y(forSpeed: speed) - 6, width: 40, height: 12)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                label.foregroundColor = speed == 1.0
                    ? TimelinePalette.clipText.cgColor
                    : TimelinePalette.text.cgColor
            }
        }
    }

    private func drawZone(limit: Double?, plot: CGRect) {
        guard let limit, limit > scale.minSpeed else {
            zoneLayer.isHidden = true
            zoneEdgeLayer.isHidden = true
            return
        }
        // Pod mezí se snímky duplikují a zpomalení trhá. Uživatel to má
        // vidět při tažení křivky, ne až po exportu.
        let edgeY = y(forSpeed: min(limit, scale.maxSpeed))
        zoneLayer.isHidden = false
        zoneLayer.frame = CGRect(x: plot.minX, y: edgeY,
                                 width: plot.width, height: max(0, plot.maxY - edgeY))
        zoneEdgeLayer.isHidden = false
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: plot.minX, y: edgeY))
        edge.addLine(to: CGPoint(x: plot.maxX, y: edgeY))
        zoneEdgeLayer.path = edge
    }

    private func drawCurve(project: Project, clip: Clip, duration: Double, plot: CGRect) {
        curveLayer.isHidden = false
        let samples = max(2, min(400, Int(plot.width)))
        let profile = project.rampSpeedProfile(of: clip, samples: samples)
        let path = CGMutablePath()
        for (index, speed) in profile.enumerated() {
            let point = CGPoint(
                x: x(forFrame: duration * Double(index) / Double(samples - 1), duration: duration),
                y: y(forSpeed: speed))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        curveLayer.path = path
    }

    private func drawNodes(project: Project, clip: Clip, duration: Double) {
        let nodes = project.rampEditorNodes(of: clip)
        while nodeLayers.count < nodes.count {
            let node = CAShapeLayer()
            node.path = CGPath(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10),
                               transform: nil)
            node.lineWidth = 1.5
            layer?.addSublayer(node)
            nodeLayers.append(node)
        }
        for (index, layer) in nodeLayers.enumerated() {
            guard index < nodes.count else { layer.isHidden = true; continue }
            layer.isHidden = false
            layer.position = CGPoint(x: x(forFrame: nodes[index].outputFrame, duration: duration),
                                     y: y(forSpeed: nodes[index].speed))
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.fillColor = RampEditorPalette.node.cgColor
                layer.strokeColor = index == selectedNodeIndex
                    ? TimelinePalette.clipSelectedStroke.cgColor
                    : TimelinePalette.separator.cgColor
            }
        }
    }

    private func updateWarning(project: Project, clip: Clip, plot: CGRect) {
        // Segmentace je na jeden výpočet levná, ale ne na 60×/s — během
        // tažení se varování neaktualizuje a dopočítá se po puštění.
        guard drag == nil else { return }
        let limited = project.rampPlaybackPlan(of: clip)?.limitedByFrameRate == true
        warningLabel.isHidden = !limited
        if limited {
            warningLabel.string = "⚠️ Křivka je moc strmá — mez skoku rychlosti není při "
                + "\(project.timeline.frameRate) fps dosažitelná"
            warningLabel.contentsScale = window?.backingScaleFactor ?? 2
            warningLabel.frame = CGRect(x: plot.minX, y: plot.minY,
                                        width: plot.width - 4, height: 15)
        }
    }

    private static func speedLabel(_ speed: Double) -> String {
        let text = speed == speed.rounded()
            ? String(format: "%.0f", speed)
            : String(format: "%.2f", speed).replacingOccurrences(of: ".", with: ",")
        return text + "×"
    }

    // MARK: - Události

    /// Kde na obrazovce leží uzly křivky (fáze 18, modul 7).
    ///
    /// Měřicí okno pro `--panel-check`: uzel neleží doprostřed plochy, ale
    /// tam, kam ho posadí mapování rychlosti na `y`. Bez tohohle by kontrola
    /// tažení musela pozici hádat — a hádala špatně (první verze táhla ze
    /// středu plochy, kde žádný uzel nebyl, a „prošla" tím, že se nic nestalo).
    var nodePoints: [(index: Int, point: CGPoint)] {
        guard let clip = editedClip else { return [] }
        let duration = Double(clip.duration.count)
        return controller.project.rampEditorNodes(of: clip).map {
            (index: $0.index,
             point: CGPoint(x: x(forFrame: $0.outputFrame, duration: duration),
                            y: y(forSpeed: $0.speed)))
        }
    }

    private func hitNode(at point: NSPoint) -> Int? {
        guard let clip = editedClip else { return nil }
        let duration = Double(clip.duration.count)
        let nodes = controller.project.rampEditorNodes(of: clip)
        // Od nejbližšího: úchop 7 bodů.
        return nodes
            .map { (node: $0, distance: hypot(
                x(forFrame: $0.outputFrame, duration: duration) - point.x,
                y(forSpeed: $0.speed) - point.y)) }
            .filter { $0.distance <= 7 }
            .min { $0.distance < $1.distance }?
            .node.index
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let clip = editedClip else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let index = hitNode(at: point) {
            selectedNodeIndex = index
            if let started = RampNodeDrag(project: controller.project,
                                          clipID: clip.id, nodeIndex: index) {
                drag = started
                controller.rampDragBegan()
            }
            reload()
            return
        }

        if event.clickCount == 2 {
            // Dvojklik do plochy přidá uzel na křivku pod kurzorem.
            let target = frame(atX: point.x, duration: Double(clip.duration.count))
            selectedNodeIndex = controller.addRampNode(clipID: clip.id, atOutputFrame: target)
            reload()
            return
        }

        selectedNodeIndex = nil
        reload()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let clip = editedClip else { return }
        let point = convert(event.locationInWindow, from: nil)
        let ramp = drag.ramp(
            atOutputFrame: frame(atX: point.x, duration: Double(clip.duration.count)),
            speed: speed(atY: point.y))
        controller.rampDragChanged(ramp, clipID: clip.id)
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        controller.rampDragEnded()
        reload()   // dopočítat varování, které se během tažení neaktualizuje
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:   // Escape — zrušit rozjeté tažení
            guard drag != nil else { super.keyDown(with: event); return }
            drag = nil
            controller.rampDragCancelled()
        case 51, 117:   // Delete / Forward Delete — smazat vybraný uzel
            guard let clip = editedClip, let index = selectedNodeIndex else {
                super.keyDown(with: event)
                return
            }
            selectedNodeIndex = nil
            controller.removeRampNode(clipID: clip.id, nodeIndex: index)
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = hitNode(at: point) else { return nil }
        selectedNodeIndex = index
        reload()

        let menu = NSMenu()
        let delete = NSMenuItem(title: "Smazat uzel",
                                action: #selector(menuDeleteNode(_:)), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func menuDeleteNode(_ sender: Any?) {
        guard let clip = editedClip, let index = selectedNodeIndex else { return }
        selectedNodeIndex = nil
        controller.removeRampNode(clipID: clip.id, nodeIndex: index)
    }
}

// MARK: - Most do SwiftUI

struct RampEditorPaneView: NSViewRepresentable {
    let controller: TimelineController

    func makeNSView(context: Context) -> RampEditorView {
        RampEditorView(controller: controller)
    }

    func updateNSView(_ nsView: RampEditorView, context: Context) {
        nsView.reload()
    }
}
