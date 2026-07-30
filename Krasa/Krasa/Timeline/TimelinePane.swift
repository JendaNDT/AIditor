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
    /// Přehled celé osy (fáze 18, modul 6) — pás pod stopami.
    let overviewView: TimelineOverviewView
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

    }

    init(controller: TimelineController) {
        self.controller = controller
        self.documentView = TimelineDocumentView(controller: controller)
        self.rulerView = TimelineRulerView(controller: controller)
        self.headersView = TrackHeadersView(controller: controller)
        self.overviewView = TimelineOverviewView(controller: controller)
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
        addSubview(overviewView)
        addSubview(cornerView)

        // Přehled: klik skočí hlavou, tažení rámečku scrolluje osu.
        overviewView.onSeek = { [weak self] frame in
            guard let self else { return }
            // Klik do přehledu je VÝSLOVNÁ navigace, takže ruší i odstavené
            // následování hlavy z dřívějšího ručního scrollu — jinak by
            // uživatel skočil hlavou a osa by zůstala stát jinde.
            self.followSuspended = false
            self.controller.setPlayheadFromUser(frame)
        }
        overviewView.onScrollTo = { [weak self] documentX in
            guard let self else { return }
            let clipView = self.scrollView.contentView
            let maxX = max(0, Double(self.documentView.frame.width - clipView.bounds.width))
            clipView.scroll(to: NSPoint(x: min(documentX, maxX),
                                        y: clipView.bounds.origin.y))
            self.scrollView.reflectScrolledClipView(clipView)
        }
        overviewView.onViewportDragChange = { [weak self] isDragging in
            guard let self else { return }
            self.isDraggingOverview = isDragging
            // Po puštění platí totéž co po ručním scrollu: kdo si odjel od
            // hlavy, toho osa nechá být, dokud hlava sama nevjede do výřezu.
            if !isDragging { self.followSuspended = self.playheadTargetScroll() != nil }
        }

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

        // Uživatel scrolluje rukou (fáze 17). Po tu dobu se osa za hlavou
        // netahá — dvě ruce na jednom scrollu je přesně ta past, před
        // kterou plán varuje. `boundsDidChange` tohle nerozliší: chodí
        // stejně za scroll od uživatele i za scroll programový.
        // <https://developer.apple.com/documentation/appkit/nsscrollview/willstartlivescrollnotification>
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveScrollWillStart(_:)),
            name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveScrollDidEnd(_:)),
            name: NSScrollView.didEndLiveScrollNotification, object: scrollView)

        controller.onFitRequest = { [weak self] in self?.zoomToFit() }

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
            // Výběr titulku (fáze 11) — rámeček kreslí refresh, stejná cesta.
            controller.$selectedTitle
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            // Výběr přechodu (fáze 16) — totéž.
            controller.$selectedTransition
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            // Vybraný úsek řeči (F18/M11) — zvýrazněný rozsah na zvukové stopě.
            controller.$selectedSpeech
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            controller.$playhead
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.documentView.updatePlayhead()
                    self?.overviewView.syncPlayhead()
                    self?.followPlayhead()
                },
            // Dopočítané špičky a dlaždice vlny (krok 10). Verze roste na
            // pozadí dokončenou prací — refresh si hotové kusy vyzvedne.
            // Throttle: při scrollu přes neviděný obsah doběhne desítky
            // dlaždic za sekundu a každá by spustila celý refresh navíc
            // k tomu scrollovacímu — výkonový test to měřil jako vypadlé
            // tiky. Deset sběrů za sekundu hotové dlaždice ukáže stejně.
            controller.waveforms.$version
                .dropFirst()
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            // Dogenerované miniatury (fáze 18, modul 5) — týž throttle
            // a z tého důvodu: dlaždice dorazí po dávkách a každá by jinak
            // spustila celý refresh navíc k tomu scrollovacímu.
            controller.thumbnails.$version
                .dropFirst()
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] _ in self?.documentView.refreshClips() },
            // Dopočítané vzorky ostrosti a hluchosti (fáze 15) — přijdou
            // jednou za asset z pozadí, reload přepočítá značky kvality.
            // In/out výřezu (fáze 17, modul 3) — mění se jen pruh v pravítku.
            controller.$inPoint
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.rulerView.needsDisplay = true },
            controller.$outPoint
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.rulerView.needsDisplay = true },
            controller.$sharpnessSamples
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
            controller.$emptinessSamples
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
            // Vrstvy osy (fáze 18, modul 3). Reload i pravítko — doby se
            // kreslí tam, zbytek tady.
            controller.$layers
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.reload()
                    self?.rulerView.needsDisplay = true
                },
            // Citlivost klasifikace: přepočítá se jen mapování vzorků na
            // značky, vzorky se nesahají — proto stačí reload.
            controller.$qualitySensitivity
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reload() },
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

        // Přehled ukrajuje ze spodu celou šířku — popisek „přehled" leží
        // pod hlavičkami stop, jak to má návrh.
        let overviewHeight = TimelineOverviewView.height
        let bodyHeight = max(0, bounds.height - rulerHeight - overviewHeight)

        cornerView.frame = NSRect(x: 0, y: 0, width: headerWidth, height: rulerHeight)
        rulerView.frame = NSRect(x: headerWidth, y: 0,
                                 width: bounds.width - headerWidth, height: rulerHeight)
        headersView.frame = NSRect(x: 0, y: rulerHeight,
                                   width: headerWidth, height: bodyHeight)
        scrollView.frame = NSRect(x: headerWidth, y: rulerHeight,
                                  width: bounds.width - headerWidth,
                                  height: bodyHeight)
        overviewView.frame = NSRect(x: 0, y: rulerHeight + bodyHeight,
                                    width: bounds.width, height: overviewHeight)

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
        // Osa se hýbe → miniatury se zatím negenerují (fáze 18, modul 5).
        // Bez tohohle spadne brána R1: dekodéry na pozadí soutěží o výpočetní
        // čas s hlavním vláknem a tiky vypadávají, i když je práce na tik
        // dvacetinásobně pod rozpočtem. Zdůvodnění v `ThumbnailStore`.
        controller.thumbnails.deferGeneration()
        documentView.refreshClips()
        // Rámeček výřezu v přehledu (F18/M6) — dvě čísla, žádná přestavba.
        let clipBounds = scrollView.contentView.bounds
        overviewView.visibleDocumentRange = (origin: Double(clipBounds.origin.x),
                                             width: Double(clipBounds.width))
    }

    /// Uživatel právě táhne rámečkem v přehledu (F18/M6). Po tu dobu se osa
    /// za hlavou netahá — týž důvod jako u `isLiveScrolling`.
    private var isDraggingOverview = false

    // MARK: - Osa sleduje hlavu (fáze 17)

    /// Uživatel právě scrolluje rukou.
    private var isLiveScrolling = false
    /// Uživatel si odscrolloval pryč od hlavy — následování se do odvolání
    /// nechá být. Zruší se samo, jakmile je hlava zase ve výřezu: klik do
    /// pravítka je vždycky uvnitř výřezu, takže „vrať se k hlavě" nepotřebuje
    /// žádnou další cestu.
    private var followSuspended = false

    @objc private func liveScrollWillStart(_ notification: Notification) {
        isLiveScrolling = true
    }

    @objc private func liveScrollDidEnd(_ notification: Notification) {
        isLiveScrolling = false
        followSuspended = playheadTargetScroll() != nil
    }

    /// Kam by se osa posunula, aby hlava zůstala vidět. `nil` = je vidět.
    private func playheadTargetScroll() -> Double? {
        let clipView = scrollView.contentView
        let viewportWidth = Double(clipView.bounds.width)
        return controller.geometry.scrollToKeep(
            playhead: controller.playhead,
            scrollX: Double(clipView.bounds.origin.x),
            viewportWidth: viewportWidth,
            maxScrollX: Double(documentView.frame.width) - viewportWidth)
    }

    /// Stránkovací posun za hlavou. Rozhodnutí KAM dělá `TimelineGeometry`
    /// (otestované bez UI), tady zbývá jen „kdy ne" a samotný scroll.
    private func followPlayhead() {
        guard !controller.isUserScrubbing, !documentView.hasActiveDrag,
              !isLiveScrolling, !isDraggingOverview else { return }
        guard let target = playheadTargetScroll() else {
            followSuspended = false      // hlava je vidět → následování zase platí
            return
        }
        guard !followSuspended else { return }

        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: target, y: clipView.bounds.origin.y))
        // Bez tohohle scroller nezná novou pozici a `boundsDidChange`
        // nedorazí — pravítko i klipy by zůstaly na starém výřezu.
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Zoom (krok 8)

    /// Zoom kotvený na kurzoru: snímek pod kurzorem zůstane pod kurzorem.
    ///
    /// Pořadí je důležité a je tu schválně synchronně, bez čekání na odběry:
    /// 1. nová geometrie, 2. HNED přerozměřit dokument (jinak by se scroll
    /// zařízl o starou šířku a obsah při zoomu dovnitř poskočil), 3. scroll
    /// tak, aby kotva zůstala na místě. Kotva se drží ve ZLOMKOVÝCH snímcích —
    /// zaokrouhlení na celý snímek by při každém kroku pinche obsah posouvalo.
    ///
    /// Během tažení se zoom ignoruje (`FAZE_2_VIEW.md` 2.6): kandidáti
    /// přichytávání jsou spočítaní při `begin` a změna měřítka by uprostřed
    /// tažení posunula tolerance.
    func zoom(scale: Double, atWindowLocation location: NSPoint) {
        guard !controller.interaction.isDragging, scale > 0 else { return }

        let clipView = scrollView.contentView
        let documentX = Double(documentView.convert(location, from: nil).x)
        let viewportX = documentX - Double(clipView.bounds.origin.x)

        let oldPointsPerFrame = controller.geometry.pointsPerFrame
        var geometry = controller.geometry
        geometry.setZoom(oldPointsPerFrame * scale)
        guard geometry.pointsPerFrame != oldPointsPerFrame else { return }

        let anchorFrame = documentX / oldPointsPerFrame     // zlomkové snímky
        controller.geometry = geometry

        sizeDocument()
        documentView.needsLayout = true

        let newDocumentX = anchorFrame * geometry.pointsPerFrame
        let target = NSPoint(x: max(0, newDocumentX - viewportX),
                             y: clipView.bounds.origin.y)
        clipView.scroll(to: target)
        scrollView.reflectScrolledClipView(clipView)

        // Scroll pošle boundsDidChange a odběr geometrie doručí reload,
        // ale až v dalším průchodu smyčkou — tohle drží obraz bez mezikroku.
        documentView.refreshClips()
        documentView.updatePlayhead()
        rulerView.needsDisplay = true
        syncChrome()
    }

    /// Změnila se sada stop nebo obsah projektu.
    /// Zoom „celá osa do okna" (⇧Z, fáze 18/M3).
    ///
    /// Šířka výřezu se bere z `contentView`, ne z rámce pane — hlavičky stop
    /// zabírají 104 bodů vlevo a bez toho by konec osy zůstal za pravou hranou.
    /// Rezerva 8 bodů, aby poslední klip nekončil přesně na hraně.
    ///
    /// Prázdná osa se nezoomuje: `duration == 0` by dělilo nulou a `setZoom`
    /// by hodnotu jen ořízl na maximum, tedy nesmyslné přiblížení.
    func zoomToFit() {
        let width = Double(scrollView.contentView.bounds.width) - 8
        let frames = Double(controller.project.duration.count)
        guard width > 0, frames > 0 else { return }
        var geometry = controller.geometry
        geometry.setZoom(width / frames)
        controller.geometry = geometry
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncChrome()
    }

    func reload() {
        documentView.rebuildLanes()
        documentView.refreshClips()
        // Přehled si sám pozná, že se v něm nic nemění (otisk projektu),
        // takže reload při zoomu ho nepřestavuje — jen se srovná výřez.
        overviewView.rebuild()
        overviewView.syncPlayhead()
        rulerView.needsDisplay = true
        headersView.needsDisplay = true
        headersView.reloadControls()   // mute a hlasitost (fáze 7)
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
    /// Ohlásí čerstvě vytvořený pane — výkonový test potřebuje scroll view.
    var onMake: ((TimelinePane) -> Void)? = nil

    func makeNSView(context: Context) -> TimelinePane {
        let pane = TimelinePane(controller: controller)
        onMake?(pane)
        return pane
    }

    func updateNSView(_ nsView: TimelinePane, context: Context) {
        nsView.reload()
    }
}
