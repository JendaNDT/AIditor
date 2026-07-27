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
import Combine
import SwiftUI
import TimelineModel

final class TimelinePane: NSView {

    let controller: TimelineController
    /// Odběry změn controlleru. Pane si o změnách říká SÁM — spoléhat na
    /// `updateNSView` nestačí: SwiftUI ho přeskočí, když se hodnoty
    /// representable nezměnily, a reference na controller se nemění nikdy.
    /// Přesně tak zůstala osa prázdná po prvním importu klipů (28. 07. 2026):
    /// projekt se naplnil, ale nikdo to view neřekl.
    ///
    /// Odběry jsou CÍLENÉ, ne plošný `objectWillChange`: hlava se během
    /// přehrávání mění 30×/s a plošná reakce by třicetkrát za sekundu
    /// přestavovala pruhy a překreslovala pravítko. Takhle hlava stojí
    /// jediný přepis rámce jedné vrstvy.
    ///
    /// `@Published` publisher posílá novou hodnotu ve `willSet`, kdy má
    /// vlastnost ještě starou — proto všude `receive(on:)`, který doručení
    /// odloží až za zápis. Bez něj by se kreslilo o krok pozadu.
    private var changeSubscriptions: [AnyCancellable] = []
    let scrollView = NSScrollView()
    let documentView: TimelineDocumentView
    let rulerView: TimelineRulerView
    let headersView: TrackHeadersView
    private let cornerView = CornerView()

    /// Roh mezi pravítkem a hlavičkami. ŽÁDNÉ `draw(_:)` — jen vrstva
    /// s barvou. Kreslené view tady dostane vadnou celookenní `ContentLayer`
    /// (viz varování u `isFlipped` níž) — stalo se to `TimelinePane` i první
    /// verzi tohohle rohu. Barva vrstvy se překládá přes
    /// `performAsCurrentDrawingAppearance` a znovu při změně vzhledu,
    /// stejný vzorec jako `TimelineDocumentView.applyColors()`.
    private final class CornerView: NSView {
        init() {
            super.init(frame: .zero)
            wantsLayer = true
            applyColor()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("nepoužívá se") }

        private func applyColor() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = TimelinePalette.chrome.cgColor
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyColor()
        }
    }

    init(controller: TimelineController) {
        self.controller = controller
        self.documentView = TimelineDocumentView(controller: controller)
        self.rulerView = TimelineRulerView(controller: controller)
        self.headersView = TrackHeadersView(controller: controller)
        super.init(frame: .zero)

        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        // Dynamickou `NSColor` si `NSScrollView` překládá při kreslení sám,
        // takže tahle jedna se na rozdíl od barev vrstev o tmavý režim
        // starat nemusí. Táž barva jako pozadí dokumentu, ať mezi plochou
        // osy a zbytkem scroll view není vidět šev.
        scrollView.backgroundColor = TimelinePalette.background

        // ⚠️ Zoom osy NIKDY přes `magnification`. Ta škáluje pixely, takže by
        // se s obsahem roztáhly i popisky a čáry, a hlavně by o tom
        // `TimelineGeometry` nevěděla — hit testing i přichytávání by počítaly
        // s jiným měřítkem, než co je vidět. Zoom je `pointsPerFrame` a nic
        // jiného (krok 8). Výchozí hodnota je `false`; tenhle řádek je
        // pojistka proti tomu, aby ji někdo v dobré víře přepnul.
        scrollView.allowsMagnification = false

        scrollView.documentView = documentView
        addSubview(scrollView)
        addSubview(rulerView)
        addSubview(headersView)
        addSubview(cornerView)

        // ⚠️ **Bez tohohle řádku notifikace nechodí vůbec.** Výchozí hodnota
        // je `false` a `NSScrollView` ji sám nezapíná. Chyba se navíc
        // neprojeví ničím jiným než tím, že pravítko stojí — žádný warning,
        // žádný pád.
        //
        // A druhá půlka téže pasti: při změně `frame` se tahle notifikace
        // neposílá vůbec, jen při změně `bounds`. Scroll mění `bounds`
        // klipované plochy, takže na scrollování to stačí; na změnu
        // velikosti okna ne — tu pokrývá `layout()`.
        //
        // <https://developer.apple.com/documentation/appkit/nsview/boundsdidchangenotification>
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)

        changeSubscriptions = [
            controller.$project
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
            controller.$interaction
                .map(\.geometry)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
            controller.$selection
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            controller.$playhead
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.documentView.updatePlayhead() },
        ]
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    /// Počátek vlevo nahoře, ať se pravítko a hlavičky umisťují ve stejné
    /// soustavě jako všechno ostatní na ose.
    override var isFlipped: Bool { true }

    // ⚠️ **TimelinePane NESMÍ mít override `draw(_:)` — černí náhled videa.**
    //
    // Odhaleno 27. 07. 2026 diffem stromu vrstev: kořen `NSViewRepresentable`,
    // který je `isFlipped` a zároveň kreslí, dostane na macOS 26 kreslicí
    // `ContentLayer` s rámcem posunutým o zápornou pozici pane v okně —
    // tady (0,-454 640×718), tedy přes CELÉ okno včetně přehrávače. Tmavá
    // výplň osy se pak nakreslí přes video a náhled vypadá černý, přestože
    // video vrstva obsah má. Přitom `TimelineRulerView` a `TrackHeadersView`
    // kreslí úplně stejně a jejich vrstvy sedí — rozdíl je jen v tom, že
    // nejsou kořenem representable. Roh proto kreslí samostatné `CornerView`.
    //
    // Pozor: rozhoduje EXISTENCE overridu, ne jeho obsah. Prázdné
    // `draw(_:)` s okamžitým `return` vrstvu založí taky a náhled černí
    // stejně — vyzkoušeno.

    override func layout() {
        super.layout()

        let headerWidth = TrackHeadersView.width
        let rulerHeight = TimelineRulerView.height

        cornerView.frame = NSRect(x: 0, y: 0, width: headerWidth, height: rulerHeight)
        rulerView.frame = NSRect(x: headerWidth, y: 0,
                                 width: bounds.width - headerWidth, height: rulerHeight)
        headersView.frame = NSRect(x: 0, y: rulerHeight,
                                   width: headerWidth, height: bounds.height - rulerHeight)
        scrollView.frame = NSRect(x: headerWidth, y: rulerHeight,
                                  width: bounds.width - headerWidth,
                                  height: bounds.height - rulerHeight)

        sizeDocument()
        // Změna velikosti okna posune `bounds` klipované plochy, ale
        // notifikace se při ní nepošle. Bez tohohle by pravítko po zvětšení
        // okna zůstalo posunuté podle staré pozice.
        syncChrome()
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

    // MARK: Synchronizace se scrollem

    @objc private func clipViewBoundsChanged(_ notification: Notification) {
        syncChrome()
    }

    /// Pravítko bere z posunu jen `x`, hlavičky jen `y`. Kdyby braly obojí,
    /// odjelo by pravítko svisle a hlavičky vodorovně pryč z okna.
    /// Klipy se přepočítávají na tomtéž místě — scroll je jediná událost,
    /// při které se mění viditelný výřez bez layoutu.
    private func syncChrome() {
        let origin = scrollView.contentView.bounds.origin
        rulerView.scrollX = Double(origin.x)
        headersView.scrollY = Double(origin.y)
        documentView.refreshClips()
    }

    /// Změnila se sada stop nebo obsah projektu.
    func reload() {
        documentView.rebuildLanes()
        documentView.refreshClips()
        rulerView.needsDisplay = true
        headersView.needsDisplay = true
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
