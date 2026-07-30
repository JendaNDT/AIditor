//
//  LibraryCard.swift
//  Projekt AIditor — UI/Library
//
//  Karta jednoho assetu v knihovně médií (fáze 18, modul 9).
//
//  ⚠️ PEVNÁ VÝŠKA 94 = náhled 62 + popis 32. Past pojmenovaná v zadání:
//  mřížka s `grid-auto-rows` karty bez pevné výšky zmáčkne, a popis se pak
//  slije s náhledem. Výška je proto na kartě, ne v mřížce.
//
//  Náhled si bere z `ThumbnailStore` (modul 5) — táž mezipaměť jako pás
//  miniatur na klipech, jen s jinou hranou dlaždice (104 místo 96), takže si
//  klíče nekolidují a knihovna nezahazuje to, co potřebuje osa.
//
//  ⚠️ Ryska měkké ostrosti se kreslí JEN u materiálu, který je na ose.
//  Klasifikace ostrosti je v modelu vázaná na KLIP (medián se bere z celého
//  assetu, ale úseky se promítají na klip) a asset, který na ose není, žádný
//  klip nemá. Vymyslet si vlastní klasifikaci by znamenalo druhou tabulku
//  prahů — a dvě tabulky téhož se rozejdou (poučení z fáze 13). Asset-level
//  klasifikace je práce pro model, ne pro kartu.
//

import SwiftUI
import TimelineModel

struct LibraryCard: View {

    static let height: CGFloat = 94
    private static let thumbHeight: CGFloat = 62

    let asset: Asset
    /// Naměřené časování ze skenu — `ClipTiming` je výsledek MĚŘENÍ, drží ho
    /// `AppModel` (vzorec z `InfoTab`).
    let timing: ClipTiming?
    let isOnTimeline: Bool
    /// Kolik problémových úseků ostrosti má materiál na ose.
    let softRuns: Int
    let isSelected: Bool
    @ObservedObject var thumbnails: ThumbnailStore
    let usesProxies: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            thumb
            info
        }
        .frame(height: Self.height)
        .background(isSelected ? AIditorUI.surfaceControlActive : AIditorUI.surfaceRow)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? AIditorUI.accent : AIditorUI.border,
                              lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onReveal)
        .onTapGesture(perform: onSelect)
        // Zdroj přetažení. Řetězec je `AssetID.rawValue` — cíl (osa) si podle
        // něj asset najde v projektu. Posílat celý asset by znamenalo vymyslet
        // si pro pasteboard formát, který by se rozešel s projektovým souborem.
        .onDrag { NSItemProvider(object: asset.id.rawValue as NSString) }
        .help(helpText)
    }

    // MARK: - Náhled

    /// ⚠️ Badge jsou v `overlay` ZA rámcem, ne uvnitř `ZStacku` s obrázkem —
    /// a chytil to až screenshot. `Image.resizable().aspectRatio(.fill)`
    /// nahlásí větší velikost, než jaká mu byla nabídnutá (o tom je aspect
    /// fill), takže se `ZStack` rozvrhl podle obrázku a `clipped()` pak
    /// odřízl i badge, které v něm ležely. Overlay dostane přesně velikost
    /// oříznutého náhledu, takže se do něj vejdou vždycky.
    private var thumb: some View {
        ZStack {
            AIditorUI.surfaceWindow
            if let image = posterImage {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isMusic {
                // Hudba nemá obraz. Vlnka místo prázdna — a zelená, protože
                // zvuk je na ose zelený.
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(AIditorUI.ok.opacity(0.7))
            }
        }
        .frame(height: Self.thumbHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay { badges }
    }

    /// Snímek pro kartu. U videa z mřížky `ThumbnailStore` na úrovni 1
    /// (jedna dlaždice = 3,47 s), a u delšího záběru se bere DRUHÁ —
    /// první snímek souboru bývá rozjezd kamery nebo tma.
    private var posterImage: CGImage? {
        let url = asset.url(usingProxies: usesProxies)
        if asset.isStill {
            return thumbnails.stillTile(url: url, side: Self.posterSide, scale: 2)
        }
        guard asset.hasVideo else { return nil }
        let seconds = ThumbnailStore.secondsPerTile(rung: 1, side: Self.posterSide)
        let index = asset.duration.seconds > seconds + 2 ? 1 : 0
        return thumbnails.tile(url: url, rung: 1, index: index,
                               side: Self.posterSide, scale: 2)
    }

    /// Hrana dlaždice pro knihovnu. 104 → render 156×104 bodů, karta ho
    /// ukazuje ve 155×62, takže se ZMENŠUJE (nedotahuje) — poučení z modulu 5.
    private static let posterSide: Double = 104

    private var badges: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                badge(durationText, background: Color.black.opacity(0.6),
                      foreground: AIditorUI.textSecondary)
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 3) {
                // Obojí, když obojí platí — slow-mo klip je typicky VFR
                // a „120p" je přitom to důležitější (jen s ním jde hluboké
                // čisté zpomalení). Vylučovat je navzájem znamenalo zatajit
                // jedno z nich; screenshot to ukázal na tom 120fps záběru.
                if asset.measuredFrameRate >= 100 {
                    badge("\(Int(asset.measuredFrameRate.rounded()))p",
                          background: Color(aiditorHex: 0x78B4FF, opacity: 0.92),
                          foreground: Color(aiditorHex: 0x10131A), bold: true)
                }
                if let timing, timing.isVariable {
                    badge("VFR", background: AIditorUI.warn.opacity(0.9),
                          foreground: Color(aiditorHex: 0x1A1A1A), bold: true)
                }
                Spacer()
                if softRuns > 0 {
                    // Ryska, ne text: je to varování „tady se podívej", ne údaj.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AIditorUI.warn.opacity(0.9))
                        .frame(width: 26, height: 4)
                }
            }
        }
        .padding(4)
    }

    private func badge(_ text: String, background: Color, foreground: Color,
                       bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 8, weight: bold ? .bold : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(background))
    }

    // MARK: - Popis

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shortName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AIditorUI.textPrimary)
                .lineLimit(1)
            Text(metaText)
                .font(.system(size: 8))
                // Datum ze SOUBORU se přiznává oranžově (pravidlo z F17):
                // po kopírování z karty je to čas kopírování, ne natáčení.
                .foregroundStyle(asset.creationDateSource == .fileSystem
                                 ? AIditorUI.warn : AIditorUI.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(height: Self.height - Self.thumbHeight)
    }

    /// Jméno bez přípony a bez data v názvu — v kartě 155 bodů široké se
    /// „20260725_202947.mp4" nevejde a užitečná je až ta druhá půlka.
    private var shortName: String {
        let base = asset.originalURL.deletingPathExtension().lastPathComponent
        if let underscore = base.lastIndex(of: "_"), base.count > 12 {
            return String(base[base.index(after: underscore)...])
        }
        return base
    }

    private var isMusic: Bool { asset.hasAudio && !asset.hasVideo && !asset.isStill }

    private var durationText: String {
        if asset.isStill { return "fotka" }
        let seconds = Int(asset.duration.seconds.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var metaText: String {
        var parts: [String] = []
        if isMusic {
            if let bpm = asset.beatGrid?.bpm {
                parts.append(String(format: "%.1f BPM", bpm))
            } else {
                parts.append("hudba")
            }
        } else if asset.isStill {
            parts.append("fotka")
        } else {
            // Zaokrouhlená standardní frekvence („60p"), ne naměřená hodnota.
            // Do karty 155 bodů široké se „59,68 fps" vejde, ale vytlačí čas
            // natočení — a hlavně: že časování NENÍ konstantní, říká badge
            // `VFR`, ne desetiny za čárkou. Přesné číslo je v tooltipu
            // a v záložce Info (M8).
            parts.append("\(Int(asset.measuredFrameRate.rounded()))p")
        }
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "cs_CZ")
            formatter.dateFormat = "HH:mm"
            parts.append(asset.creationDateSource == .fileSystem
                         ? "\(formatter.string(from: date)) (soubor)"
                         : formatter.string(from: date))
        }
        if isOnTimeline { parts.append("na ose") }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        var lines = [asset.originalURL.lastPathComponent]
        if asset.hasVideo, !asset.isStill {
            lines.append(String(format: "naměřeno %.3f fps", asset.measuredFrameRate))
        }
        if let timing, timing.isVariable {
            lines.append("proměnlivé časování (VFR) — zploštěné v proxy")
        }
        if softRuns > 0 {
            lines.append("na ose \(softRuns)× úsek s měkkou ostrostí")
        }
        if asset.creationDateSource == .fileSystem {
            lines.append("čas je z datumu souboru, ne z metadat kamery")
        }
        lines.append("dvojklik ukáže na ose · tažením se položí na stopu")
        return lines.joined(separator: "\n")
    }
}
