//
//  DesignTokens.swift
//  Projekt AIditor — UI/Shell
//
//  Fáze 18, modul 1. Barvy, rozměry a typografie přestavěného UI.
//  Zdroj: `design_handoff_aiditor_ui/README.md`, sekce „Designové tokeny".
//
//  ⚠️ JEDINÁ VARIANTA JE TMAVÁ (rozhodnuto 29. 07. 2026, `FAZE_18_UI.md` 2.2).
//  Okno si vynucuje `.darkAqua` ve `WindowConfigurator`; adaptivní dvojice
//  v `TimelinePalette` a `RampEditorPalette` jsou tím zrušené. Kdyby sem
//  někdy světlá varianta měla přijít zpátky, patří do NÍ, ne do jednotlivých
//  view — dvě místa s barvami už jednou stála za chybou (fáze 2).
//
//  Tokeny signální řady se schválně SHODUJÍ s `TimelinePalette` (accent =
//  `clipSelectedStroke`, playhead, quality*): osa a chrome mluví jednou
//  paletou, takže žlutá v panelu znamená totéž co žlutá na klipu.
//

import SwiftUI
import TimelineModel

enum AIditorUI {

    // MARK: - Barvy: chrome

    static let surfaceWindow = Color(aiditorHex: 0x0E0F11)
    static let surfaceChrome = Color(aiditorHex: 0x17181B)
    static let surfaceRail = Color(aiditorHex: 0x131417)
    static let surfacePanel = Color(aiditorHex: 0x16181C)
    static let surfaceRow = Color(aiditorHex: 0x1B1D21)
    static let surfaceControl = Color(aiditorHex: 0x1E2024)
    static let surfaceControlActive = Color(aiditorHex: 0x23262B)
    /// Aktivní ikona railu — o stupeň světlejší než vybraný přepínač.
    static let surfaceRailActive = Color(aiditorHex: 0x2C3037)
    static let surfaceViewer = Color(aiditorHex: 0x08090A)

    static let border = Color(aiditorHex: 0x24262B)
    static let borderStrong = Color(aiditorHex: 0x2F3238)
    static let borderActive = Color(aiditorHex: 0x3A3F47)

    static let textPrimary = Color(aiditorHex: 0xE9EAEC)
    static let textSecondary = Color(aiditorHex: 0x9AA0A8)
    static let textTertiary = Color(aiditorHex: 0x6B7280)
    static let textDisabled = Color(aiditorHex: 0x5C6067)

    // MARK: - Barvy: signální (shodné s `TimelinePalette`, tmavá větev)

    /// Výběr, výřez, aktivní záložka. `clipSelectedStroke` (1,00 0,79 0,28).
    static let accent = Color(aiditorHex: 0xFFC947)
    /// Text NA akcentu. Žlutá je světlá — bílý text by na ní zmizel.
    static let accentText = Color(aiditorHex: 0x191A1C)
    static let playhead = Color(aiditorHex: 0xFF453B)
    static let rampCurve = Color(aiditorHex: 0x8CB8FF)
    /// Hotový stav, hlasitost v mezích.
    static let ok = Color(aiditorHex: 0x3ECF8E)
    /// Běžící analýza, přiznaná mez. Totéž co `TimelinePalette.beat`.
    static let warn = Color(aiditorHex: 0xFF9F0A)

    // MARK: - Rozměry

    enum Metric {
        /// Toolbar v okně × na celé obrazovce (fullscreen je o 2 vyšší kvůli
        /// paddingu 16 místo odsazení za puntíky).
        static let toolbarHeightWindow: CGFloat = 46
        static let toolbarHeightFullscreen: CGFloat = 48
        /// Odsazení obsahu toolbaru zleva v okně: puntíky zavření/minimalizace
        /// leží v ploše obsahu (`fullSizeContentView`), takže se musí obejít.
        /// Ve fullscreenu puntíky nejsou a odsazení je obyčejný padding.
        static let toolbarLeadingWindow: CGFloat = 78
        static let toolbarLeadingFullscreen: CGFloat = 16

        /// Horní pás (přehrávač + knihovna). Ve fullscreenu dostane
        /// získaných 56 bodů, aby se zbytek okna nemusel přepočítávat.
        static let topBandHeightWindow: CGFloat = 372
        static let topBandHeightFullscreen: CGFloat = 426

        static let railWidth: CGFloat = 60
        static let railItemSize: CGFloat = 44
        static let railItemRadius: CGFloat = 11

        static let statusBarHeight: CGFloat = 26
        static let timelineToolbarHeight: CGFloat = 32
        static let pinnedPanelWidth: CGFloat = 452
        static let libraryWidth: CGFloat = 330

        static let controlHeight: CGFloat = 28
        static let controlRadius: CGFloat = 7
        static let chipRadius: CGFloat = 5

        static let transportPillHeight: CGFloat = 44
        static let transportPillRadius: CGFloat = 22
        static let transportPlayButton: CGFloat = 44

        /// Odsazení obrazu od hran plochy přehrávače.
        static let viewerPadding: CGFloat = 16

        static let minWindowWidth: CGFloat = 1180
        static let minWindowHeight: CGFloat = 760
    }

    // MARK: - Typografie

    enum Font {
        static let projectName = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let projectMeta = SwiftUI.Font.system(size: 9)
        static let control = SwiftUI.Font.system(size: 11)
        static let controlStrong = SwiftUI.Font.system(size: 11, weight: .medium)
        static let sectionTitle = SwiftUI.Font.system(size: 10, weight: .regular)
        static let chip = SwiftUI.Font.system(size: 9)
        static let railLabel = SwiftUI.Font.system(size: 8)
        static let status = SwiftUI.Font.system(size: 10)
        /// Timecode v transportu: 13 v okně, 22 ve fullscreen náhledu (M13).
        static let timecode = SwiftUI.Font.system(size: 13, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 10, design: .monospaced)
    }
}

// MARK: - Názvy barevných presetů

/// Jak se preset jmenuje v UI. **Jediné místo** — dřív si názvy psal
/// rozbalovátko v `ColorGradePanel` sám a čip na obraze (fáze 18) by byl
/// druhý; dvě tabulky téhož se rozejdou, jakmile přibude preset.
///
/// Model schválně žádný název nenese: `ColorPreset` je VOLBA, ne text.
/// Co preset opticky znamená, ví `ColorPresetFilter`; jak se jmenuje, ví
/// tahle tabulka. Pořadí i znění odpovídají zadání návrhu.
extension ColorPreset {
    var displayName: String {
        switch self {
        case .softWedding: return "Jemný svatební"
        case .warmFilm: return "Teplý film"
        case .cleanSkin: return "Čistá pleť"
        case .blackAndWhite: return "Černobílá"
        }
    }
}

extension Color {
    /// `0xRRGGBB` — tokeny jsou v zadání zapsané hexadecimálně a přepisovat
    /// je na trojice desetinných čísel by jen přidalo místo, kde udělat chybu.
    ///
    /// Pojmenovaný popisek `aiditorHex`, ne prosté `hex:` — kdyby SwiftUI nebo
    /// jiný balíček někdy `Color(hex:)` doplnil, tichý překryv by se hledal
    /// dlouho.
    init(aiditorHex value: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: opacity)
    }
}
