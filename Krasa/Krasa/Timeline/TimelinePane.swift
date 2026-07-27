//
//  TimelinePane.swift
//  Projekt Krása
//
//  Kompozitní kořen časové osy a most do SwiftUI. `FAZE_2_VIEW.md`, sekce 3.
//
//  Ve výsledku sem přibude pravítko a hlavičky stop (krok 3). Zatím drží
//  jen `NSScrollView` s plochou osy.
//

import AppKit
import SwiftUI
import TimelineModel

final class TimelinePane: NSView {

    let controller: TimelineController
    let scrollView = NSScrollView()
    let documentView: TimelineDocumentView

    init(controller: TimelineController) {
        self.controller = controller
        self.documentView = TimelineDocumentView(controller: controller)
        super.init(frame: .zero)

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        // Dynamickou `NSColor` si `NSScrollView` překládá při kreslení sám,
        // takže tahle jedna se na rozdíl od barev vrstev o tmavý režim
        // starat nemusí.
        scrollView.backgroundColor = .underPageBackgroundColor

        // ⚠️ Zoom osy NIKDY přes `magnification`. Ta škáluje pixely, takže by
        // se s obsahem roztáhly i popisky a čáry, a hlavně by o tom
        // `TimelineGeometry` nevěděla — hit testing i přichytávání by počítaly
        // s jiným měřítkem, než co je vidět. Zoom je `pointsPerFrame` a nic
        // jiného (krok 8). Výchozí hodnota je `false`; tenhle řádek je
        // pojistka proti tomu, aby ji někdo v dobré víře přepnul.
        scrollView.allowsMagnification = false

        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        sizeDocument()
    }

    /// Nastaví plochu, po které jde scrollovat.
    ///
    /// Šířka je z geometrie (délka projektu plus rezerva za posledním klipem),
    /// výška součet stop. Obojí se ale ještě zvedne na velikost viditelné
    /// části: kdyby byl dokument menší než okno, zbyl by pod pruhy holý
    /// `NSScrollView` a osa by vypadala rozbitě.
    ///
    /// Sizing se dělá TADY, ne v `TimelineDocumentView.layout()` — ten by
    /// změnou vlastního rámce spustil sám sebe.
    private func sizeDocument() {
        let visible = scrollView.contentView.bounds.size
        let geometry = controller.geometry
        let project = controller.project

        let size = CGSize(
            width: max(geometry.contentWidth(of: project), visible.width),
            height: max(geometry.totalHeight(of: project.timeline), visible.height))

        guard documentView.frame.size != size else { return }
        documentView.setFrameSize(size)
        documentView.needsLayout = true
    }

    /// Změnila se sada stop nebo obsah projektu.
    func reload() {
        documentView.rebuildLanes()
        needsLayout = true
    }
}

// MARK: - Most do SwiftUI

/// ⚠️ Jmenuje se `TimelinePaneView`, ne `TimelineView` — `SwiftUI.TimelineView`
/// už existuje (macOS 12+) a vlastní typ téhož jména by ho v celém modulu
/// zastínil. Přeložilo by se to a chyba by vylezla až tam, kde by někdo
/// sáhl po tom systémovém.
struct TimelinePaneView: NSViewRepresentable {
    let controller: TimelineController

    func makeNSView(context: Context) -> TimelinePane {
        TimelinePane(controller: controller)
    }

    func updateNSView(_ nsView: TimelinePane, context: Context) {
        nsView.reload()
    }
}
