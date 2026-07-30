//
//  InfoTab.swift
//  Projekt Krása — UI/Panels
//
//  Fáze 18, modul 8. Záložka Info připnutého panelu: co je zdroj, jak je
//  načasovaný, kdy se natočil a jede-li se z proxy.
//
//  Všechno jsou MĚŘENÉ nebo přečtené hodnoty, nic se nedomýšlí. Kde hodnota
//  chybí, řekne se to — u času natočení navíc i to, ODKUD je, protože datum
//  souboru je po AirDropu čas doručení, ne stisknutí spouště.
//

import SwiftUI
import TimelineModel

struct InfoTab: View {
    @ObservedObject var timeline: TimelineController
    @ObservedObject var model: AppModel
    let clipID: ClipID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceSection
            timingSection
            creationSection
            proxySection
        }
    }

    private var clip: Clip? { timeline.project.timeline.clip(clipID) }
    private var asset: Asset? { clip.flatMap { timeline.project.asset($0.assetID) } }

    /// Naměřené časování ze skenu (`VFRDetector`). Klíčem je cesta —
    /// `ClipTiming` je výsledek MĚŘENÍ, ne uložený údaj, takže ho drží
    /// `AppModel`, ne projekt.
    private var timing: ClipTiming? {
        guard let asset else { return nil }
        return model.clips.first { $0.url == asset.originalURL }
    }

    // MARK: - Zdroj

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Zdroj")
            if let asset {
                row("soubor", asset.originalURL.lastPathComponent)
                row("délka zdroje", String(format: "%.2f s", asset.duration.seconds))
                if asset.isStill {
                    row("druh", "fotka (přes still movie mezisoubor)")
                }
            } else {
                missing("Klip nemá asset — to je chyba, ne stav.")
            }
        }
    }

    // MARK: - Časování

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Časování")
            if let asset, !asset.isStill {
                row("naměřeno", String(format: "%.3f fps", asset.measuredFrameRate))
                if let timing {
                    row("verdikt", timing.verdict.shortLabel,
                        highlighted: timing.isVariable)
                    if timing.droppedFrames > 0 {
                        row("zahozené snímky", "\(timing.droppedFrames)", highlighted: true)
                    }
                } else {
                    missing("Časování se v tomhle sezení neměřilo.")
                }
                // Mez čistého zpomalení je z naměřené frekvence, ne
                // z `nominalFrameRate` — ten podle měření lže.
                if let clip, let limit = timeline.project.pureSlowdownLimit(of: clip) {
                    row("čisté zpomalení až na", SpeedTab.speedLabel(limit))
                }
            } else if asset?.isStill == true {
                Text("Fotka nemá časování — délku určuje střih.")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
        }
    }

    // MARK: - Čas natočení

    private var creationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Čas natočení")
            if let date = asset?.creationDate ?? timing?.creationDate {
                let source = asset?.creationDateSource ?? timing?.creationDateSource
                row("kdy", Self.dateText(date), highlighted: source == .fileSystem)
                if source == .fileSystem {
                    Text("Je to datum SOUBORU, ne metadata. Po kopírování z karty "
                         + "nebo AirDropu je to čas doručení — řadit podle něj jde, "
                         + "věřit mu na minutu ne.")
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                missing("Soubor čas natočení nenese. Chronologické uspořádání ho "
                        + "zařadí dozadu.")
            }
        }
    }

    // MARK: - Proxy

    private var proxySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Proxy")
            if let asset, asset.proxyURL != nil {
                row("stav", timeline.project.usesProxies
                    ? "hotová, střih z ní jede"
                    : "hotová, ale střih jede z originálu")
                Text("Export jde VŽDY z originálů — proxy je kvůli scrubování "
                     + "(seek 6 ms proti 41–95 ms).")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                missing("Proxy pro tenhle soubor není.")
            }
        }
    }

    // MARK: - Drobnosti

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(KrasaUI.Font.sectionTitle)
            .tracking(0.7)
            .foregroundStyle(KrasaUI.textTertiary)
    }

    private func row(_ label: String, _ value: String, highlighted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(KrasaUI.Font.monoSmall)
                .foregroundStyle(highlighted ? KrasaUI.warn : KrasaUI.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func missing(_ text: String) -> some View {
        Text(text)
            .font(KrasaUI.Font.chip)
            .foregroundStyle(KrasaUI.textDisabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d. M. yyyy HH:mm:ss"
        return formatter.string(from: date)
    }
}
