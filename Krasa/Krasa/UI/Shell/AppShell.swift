//
//  AppShell.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 1. Kořen okna: toolbar → tělo → stavový řádek.
//  Zdroj: `design_handoff_krasa_ui/README.md`, obrazovka 1 a 5.
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
            ? KrasaUI.Metric.toolbarHeightWindow
            : KrasaUI.Metric.toolbarHeightFullscreen
    }

    /// V okně se musí obejít puntíky, které leží v ploše obsahu
    /// (`fullSizeContentView`). Ve fullscreenu žádné nejsou.
    var toolbarLeading: CGFloat {
        self == .window
            ? KrasaUI.Metric.toolbarLeadingWindow
            : KrasaUI.Metric.toolbarLeadingFullscreen
    }

    /// Získaných 56 bodů dostane přehrávač. Osa, hlavičky ani panel si
    /// rozměry nemění — jinak by se po přepnutí muselo přepočítat všechno.
    var topBandHeight: CGFloat {
        self == .window
            ? KrasaUI.Metric.topBandHeightWindow
            : KrasaUI.Metric.topBandHeightFullscreen
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
    private var chromeVisible: Bool { !model.chromeHidden }

    var body: some View {
        VStack(spacing: 0) {
            if chromeVisible {
                KrasaToolbar(model: model, mode: mode)
                hairline
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
        .background(KrasaUI.surfaceWindow)
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
        .frame(minWidth: model.chromeHidden ? 0 : KrasaUI.Metric.minWindowWidth,
               minHeight: model.chromeHidden ? 0 : KrasaUI.Metric.minWindowHeight)
        .background(WindowConfigurator(model: model))
    }

    // MARK: - Sloupec obsahu

    private var contentColumn: some View {
        VStack(spacing: 0) {
            topBand
            if chromeVisible {
                hairline
                TimelineLayerBar(model: model)
                hairline
                timelineRow
            }
        }
    }

    /// Horní pás: přehrávač (pružný) a vpravo knihovna (M9 — zatím nic).
    ///
    /// ⚠️ Výška je pevná, dokud je chrome vidět. Při měření se uvolní na
    /// `nil`, aby přehrávač dostal celé okno — tehdy je pod ním prázdno,
    /// protože osa i lišty jsou z hierarchie pryč.
    private var topBand: some View {
        HStack(spacing: 0) {
            ViewerPane(model: model)
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

            if model.panelVisible {
                verticalHairline
                PinnedPanel(model: model)
                    .frame(width: KrasaUI.Metric.pinnedPanelWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Předěly

    private var hairline: some View {
        KrasaUI.border.frame(height: 1)
    }

    private var verticalHairline: some View {
        KrasaUI.border.frame(width: 1)
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

// MARK: - Lišta osy (M1: jen rám a to, co je čtení stavu)

/// Pás 32 px nad osou. Přepínače vrstev, citlivost a zoom sem doplní
/// modul 3 — M1 drží rozměr a ukazuje jen to, co už dnes existuje jako
/// stav (výřez a nápověda k přichytávání). Prázdné místo je schválně
/// prázdné: falešná tlačítka, která nic nedělají, jsou horší než mezera.
struct TimelineLayerBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Text("Na ose:")
                .font(KrasaUI.Font.control)
                .foregroundStyle(KrasaUI.textTertiary)

            Spacer()

            if let range = exportRangeText {
                Text(range)
                    .font(KrasaUI.Font.monoSmall)
                    .foregroundStyle(KrasaUI.accent)
            }

            Text("Přichytávání · Shift vypne")
                .font(KrasaUI.Font.control)
                .foregroundStyle(KrasaUI.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: KrasaUI.Metric.timelineToolbarHeight)
        .frame(maxWidth: .infinity)
        .background(KrasaUI.surfaceChrome)
    }

    /// Kreslí se jen když je výřez opravdu výřez — pravidlo z fáze 17.
    private var exportRangeText: String? {
        let timeline = model.timeline
        guard let inPoint = timeline.inPoint, let outPoint = timeline.outPoint,
              outPoint > inPoint else { return nil }
        let rate = timeline.project.timeline.frameRate
        return "výřez \(Timecode(inPoint, frameRate: rate).shortText)"
            + "–\(Timecode(outPoint, frameRate: rate).shortText)"
    }
}

// MARK: - Připnutý panel (M1: hostí dosavadní inspektor)

/// Panel vpravo od osy, 452 px. Modul 7 sem dá záložky Rychlost / Barva /
/// Zvuk / Info; M1 do něj přestěhoval dosavadní `InspectorStrip`, aby
/// křivka rychlosti dostala místo hned a nic se cestou neztratilo.
struct PinnedPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            KrasaUI.border.frame(height: 1)

            if model.railSection == .settings {
                ScrollView { LegacySettingsPanel(model: model) }
            } else {
                InspectorStrip(timeline: model.timeline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            }
        }
        .background(KrasaUI.surfacePanel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.railSection == .settings ? "Nastavení" : "Inspektor")
                .font(KrasaUI.Font.controlStrong)
                .foregroundStyle(KrasaUI.textPrimary)
            Spacer()
            Text("⌘4 skryje")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}
