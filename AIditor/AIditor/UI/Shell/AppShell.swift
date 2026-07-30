//
//  AppShell.swift
//  Projekt AIditor — UI/Shell
//
//  Fáze 18, modul 1. Kořen okna: toolbar → tělo → stavový řádek.
//  Zdroj: `design_handoff_aiditor_ui/README.md`, obrazovka 1 a 5.
//
//  ⚠️ JEDEN STROM, PODMÍNĚNÍ SOUROZENCI.
//  Skořápka se při měření (`chromeHidden`) NEPŘEPÍNÁ na jinou větev `if`,
//  jen se z ní odeberou chrome kusy. Kdyby se přepínala celá, SwiftUI by
//  `PlayerView` přetvořil, vznikl by nový `PlayerHostView` a měření by
//  drželo ten starý — přesně chyba, kterou `PlayerView.updateNSView` musel
//  jednou obcházet. Takhle zůstává přehrávač po celou dobu na témže místě
//  stromu a mění se jen to, co je kolem něj.
//
//  ⚠️ Chrome se ODEBÍRÁ, nekryje. Pravidlo z fáze 1: skrývání nulovým
//  rámcem už jednou natáhlo layout na 4398 bodů a měření to nepoznalo.
//

import AppKit
import SwiftUI
import TimelineModel

/// Okno, nebo celá obrazovka. Rozdíl je jen v číslech — rozvržení je totéž,
/// aby se ve fullscreenu nic nekreslilo podruhé a souřadnice osy seděly.
enum ShellMode {
    case window
    case fullscreenApp

    var toolbarHeight: CGFloat {
        self == .window
            ? AIditorUI.Metric.toolbarHeightWindow
            : AIditorUI.Metric.toolbarHeightFullscreen
    }

    /// V okně se musí obejít puntíky, které leží v ploše obsahu
    /// (`fullSizeContentView`). Ve fullscreenu žádné nejsou.
    var toolbarLeading: CGFloat {
        self == .window
            ? AIditorUI.Metric.toolbarLeadingWindow
            : AIditorUI.Metric.toolbarLeadingFullscreen
    }

    /// Získaných 56 bodů dostane přehrávač. Osa, hlavičky ani panel si
    /// rozměry nemění — jinak by se po přepnutí muselo přepočítat všechno.
    var topBandHeight: CGFloat {
        self == .window
            ? AIditorUI.Metric.topBandHeightWindow
            : AIditorUI.Metric.topBandHeightFullscreen
    }
}

/// Šest položek ikonového railu. Rail určuje, co je v panelu vpravo —
/// nahrazuje vývojářský sidebar.
enum RailSection: String, CaseIterable, Identifiable {
    case media, text, color, audio, speech, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .media: return "Média"
        case .text: return "Text"
        case .color: return "Barva"
        case .audio: return "Zvuk"
        case .speech: return "Řeč"
        case .settings: return "Nastavení"
        }
    }

    /// SF Symbols. Názvy ověřené proti katalogu SF Symbols; všechny
    /// existují od macOS 11, deployment target projektu je 14.
    var symbol: String {
        switch self {
        case .media: return "film"
        case .text: return "textformat"
        case .color: return "paintpalette"
        case .audio: return "waveform"
        case .speech: return "text.bubble"
        case .settings: return "gearshape"
        }
    }
}

struct AppShell: View {
    @ObservedObject var model: AppModel

    private var mode: ShellMode { model.isFullscreen ? .fullscreenApp : .window }
    /// Chrome je pryč při měření (M1) i ve fullscreen náhledu (M13). V obou
    /// případech se ODEBÍRÁ z hierarchie, nekryje — a `ViewerPane` v obou
    /// zůstává na témže místě stromu, takže se `PlayerView` nepřetváří.
    private var chromeVisible: Bool { !model.chromeHidden && !model.previewFullscreen }

    var body: some View {
        VStack(spacing: 0) {
            if chromeVisible {
                AIditorToolbar(model: model, mode: mode)
                hairline
                // Nabídka obnovy zálohy je PRUH pod toolbarem, ne dialog
                // (modul 12). Jde ignorovat — a dokud se ignoruje, záloha leží.
                if let offer = model.recoveryOffer {
                    RecoveryBar(model: model, offer: offer)
                }
            }

            HStack(spacing: 0) {
                if chromeVisible {
                    IconRail(model: model)
                    verticalHairline
                }
                contentColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if chromeVisible {
                hairline
                ShellStatusBar(model: model, mode: mode)
            }
        }
        // List exportu leží NAD celou skořápkou (fáze 18, modul 10).
        // Overlay, ne `.sheet`: návrh chce vlastní list 660 bodů se ztmavením
        // okna, a systémový sheet by přinesl vlastní rám i animaci.
        // Při měření (`chromeHidden`) se nekreslí — R4.
        .overlay {
            if chromeVisible, model.exportSheet != nil {
                ExportSheet(model: model)
            }
        }
        .background(AIditorUI.surfaceWindow)
        // ⚠️ Bez tohohle si SwiftUI drží nahoře bezpečnou zónu titulkového
        // pruhu a celá skořápka sjede o 32 bodů dolů — v okně, ve fullscreenu
        // ne (tam titulkový pruh není). Naměřeno `--shell-check`: osa v okně
        // začínala na 485 místo 453, ve fullscreenu na 509 správně.
        //
        // Návrh chce puntíky UVNITŘ toolbaru, takže se zóna ignoruje a místo
        // pro ně dělá `ShellMode.toolbarLeading` (78 bodů v okně).
        .ignoresSafeArea()
        // Minimální rozměr se při měření pouští k nule ze stejného důvodu
        // jako dřív u sidebaru: měřicí běh okno zmenšuje a tvrdé minimum
        // by mu v tom bránilo.
        .frame(minWidth: model.chromeHidden ? 0 : AIditorUI.Metric.minWindowWidth,
               minHeight: model.chromeHidden ? 0 : AIditorUI.Metric.minWindowHeight)
        .background(WindowConfigurator(model: model))
    }

    // MARK: - Sloupec obsahu

    private var contentColumn: some View {
        VStack(spacing: 0) {
            topBand
            if chromeVisible {
                hairline
                // Prázdná osa nemá co kreslit ani co přiblížit — lišta je
                // ztlumená (zadání: `opacity .4`), ale zůstává na místě, aby
                // se okno po importu nepřeskládalo.
                TimelineLayerBar(model: model, bar: model.timelineBar)
                    .opacity(model.showsEmptyStart ? 0.4 : 1)
                    .disabled(model.showsEmptyStart)
                hairline
                timelineRow
            }
        }
    }

    /// Horní pás: přehrávač (pružný) a vpravo knihovna médií (M9).
    ///
    /// ⚠️ Výška je pevná, dokud je chrome vidět. Při měření se uvolní na
    /// `nil`, aby přehrávač dostal celé okno — tehdy je pod ním prázdno,
    /// protože osa i lišty jsou z hierarchie pryč.
    ///
    /// ⚠️ Knihovna se při měření ODEBÍRÁ, nekryje (pravidlo R4) — jinak by
    /// přehrávač nedostal celou šířku a měřicí běhy by porovnávaly jiná čísla,
    /// než která platila dřív.
    private var topBand: some View {
        HStack(spacing: 0) {
            ViewerPane(model: model)
            if chromeVisible {
                verticalHairline
                // Rail rozhoduje, co je vpravo (zadání, sekce 1.2). Na `Řeč`
                // to jsou Zdroje řeči, jinak knihovna médií — a bez materiálu
                // Poslední projekty (modul 12).
                if model.showsEmptyStart {
                    RecentProjectsPane(model: model, store: model.projectStore)
                        .frame(width: AIditorUI.Metric.libraryWidth)
                } else if model.railSection == .speech {
                    SpeechSourcesPane(model: model, timeline: model.timeline,
                                      transcription: model.transcription)
                        .frame(width: AIditorUI.Metric.libraryWidth)
                } else {
                    LibraryPane(model: model)
                        .frame(width: AIditorUI.Metric.libraryWidth)
                }
            }
        }
        .frame(height: chromeVisible ? mode.topBandHeight : nil)
        .frame(maxWidth: .infinity, maxHeight: chromeVisible ? nil : .infinity)
    }

    /// Osa a připnutý panel vedle sebe.
    private var timelineRow: some View {
        HStack(spacing: 0) {
            TimelinePaneView(controller: model.timeline,
                             onMake: { model.attachTimeline($0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bez materiálu není co inspektovat, takže panel podle zadání
            // nesvítí — s výjimkou Nastavení, které na projektu nezávisí
            // (a bez něj by se na prázdném startu nedalo dostat ke správě
            // proxy a modelu přepisu).
            if model.panelVisible, !model.showsEmptyStart || model.railSection == .settings {
                verticalHairline
                PinnedPanel(model: model)
                    .frame(width: AIditorUI.Metric.pinnedPanelWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Předěly

    private var hairline: some View {
        AIditorUI.border.frame(height: 1)
    }

    private var verticalHairline: some View {
        AIditorUI.border.frame(width: 1)
    }
}

// MARK: - Nastavení okna

/// Jednorázová konfigurace okna a sledování fullscreenu.
///
/// Dělá se z `NSViewRepresentable`, protože SwiftUI okno jinak do ruky
/// nedá. `configure` se pouští jen jednou — `updateNSView` chodí při každé
/// změně a opakované nastavování `styleMask` by ve fullscreenu skončilo
/// výjimkou (viz `FullScreenSwitch`).
///
/// <https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent>
/// <https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview>
/// <https://developer.apple.com/documentation/appkit/nswindow/didenterfullscreennotification>
struct WindowConfigurator: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.alphaValue = 0
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Okno v `updateNSView` ještě nemusí být — view se do hierarchie
        // dostane až po prvním layoutu.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window, model: model)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var configured = false
        private var observers: [NSObjectProtocol] = []

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        @MainActor
        func configure(window: NSWindow, model: AppModel) {
            guard !configured else { return }
            configured = true

            // Tmavý režim natvrdo (rozhodnutí 29. 07. 2026). Přepínač
            // vzhledu tím přestává mít na aplikaci vliv — je to záměr.
            window.appearance = NSAppearance(named: .darkAqua)

            // Puntíky mají ležet v ploše toolbaru, ne nad ním.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.backgroundColor = NSColor(red: 0x0E / 255.0, green: 0x0F / 255.0,
                                             blue: 0x11 / 255.0, alpha: 1)

            model.isFullscreen = window.styleMask.contains(.fullScreen)

            let center = NotificationCenter.default
            // `queue: .main` doručuje na hlavním vlákně, ale překladač to
            // z typu uzávěry nepozná — `assumeIsolated` mu to potvrdí bez
            // odkladu o jeden běh smyčky (ten by při přechodu do fullscreenu
            // stihl překreslit skořápku ještě starými rozměry).
            observers.append(center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { model.isFullscreen = true }
                })
            observers.append(center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { model.isFullscreen = false }
                })
        }
    }
}
