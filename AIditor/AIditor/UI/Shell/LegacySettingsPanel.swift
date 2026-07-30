//
//  LegacySettingsPanel.swift
//  Projekt AIditor — UI/Shell
//
//  Fáze 18, modul 1. Dosavadní sidebar, přestěhovaný beze změny chování
//  do sekce railu **Nastavení**.
//
//  ⚠️ Je to MEZISTAV, ne cíl. Zadání návrhu vyčítá právě tomuhle panelu, že
//  míchá dokument, nastavení, dodávku i vývojářská měření. Rozebrat se má
//  po kusech: seznam klipů → knihovna (M9), export → list exportu (M10),
//  proxy a model přepisu → stavový řádek a nastavení (M2). Do té doby ale
//  musí být všechno dosažitelné — modul, který funkci nejdřív odstraní
//  a pak ji o pět sessions později vrátí, je modul, který ji ztratil.
//

import AudioEngine
import SwiftUI
import TimelineModel

struct LegacySettingsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Otevřít soubor") { Task { await model.openFiles(directories: false) } }
                Button("Otevřít složku") { Task { await model.openFiles(directories: true) } }
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⚠️ Výběr přes `selection:`, NE přes `.onTapGesture` na řádku.
            //
            // Na macOS stojí `List` nad `NSTableView` a ten si myš bere na
            // vlastní výběr — gesto uvnitř řádku se pak nespustí a klik na
            // klip nedělá nic. Na iOSu tentýž kód funguje, takže se ta chyba
            // snadno napíše a těžko všimne. Odhaleno 27. 07. 2026, ale je
            // v projektu od fáze 1: dokud se první klip vybíral sám, nebylo
            // poznat, že ručně vybrat nejde.
            List(model.clips, id: \.url, selection: clipSelection) { clip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.name).font(.system(.body, design: .monospaced))
                    Text("\(clip.verdict.shortLabel) · \(String(format: "%.2f", clip.measuredFrameRate)) fps"
                         + (clip.droppedFrames > 0 ? " · \(clip.droppedFrames) zahozených" : ""))
                        .font(.caption)
                        .foregroundStyle(clip.isVariable ? .orange : .secondary)
                    // Čas natočení (fáze 17) — seznam je podle něj seřazený,
                    // takže musí být vidět. U data ze SOUBORU se to přizná:
                    // po kopírování z karty to bývá čas kopírování.
                    if let date = clip.creationDate {
                        Text(Self.creationText(date, source: clip.creationDateSource))
                            .font(.caption2)
                            .foregroundStyle(clip.creationDateSource == .fileSystem
                                             ? .orange : .secondary)
                    }
                }
            }
            .frame(minHeight: 180)

            ProxyControls(timeline: model.timeline, proxies: model.proxies,
                          onChangeLocation: { model.changeProxyDirectory() },
                          onDelete: { model.deleteProxies() })

            WhisperModelControls(transcription: model.transcription,
                                 onRelocate: { model.relocateWhisperModel() },
                                 onDelete: { model.deleteWhisperModel() })

            if let progress = model.exportProgress {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                    Text("Exportuju… \(Int(progress * 100)) %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Hlasitost dodávky (fáze 7): normalizace na cílový profil,
                // nebo nechat mix, jak je. Tlačítko exportu je od M1
                // v toolbaru — tady zůstává jen volba profilu.
                Picker("Hlasitost", selection: Binding(
                    get: { model.loudnessProfile?.rawValue ?? "none" },
                    set: { model.loudnessProfile = LoudnessProfile(rawValue: $0) })) {
                    Text("Bez normalizace").tag("none")
                    Text("Web / sociální sítě (−14 LUFS)").tag(LoudnessProfile.web.rawValue)
                    Text("Vysílání EBU R128 (−23 LUFS)").tag(LoudnessProfile.broadcast.rawValue)
                }
                .controlSize(.small)
                .help("Export změří hlasitost celého filmu a dorovná ji na cíl. "
                    + "Zesílení je omezené špičkami (−1 dBTP) — bez limiteru se přes ně nejde dostat poctivě.")
            }

            Divider()

            Text("Měření (vývojářské)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(model.isMeasuring ? "Měřím…" : "Změřit náhled v okně") {
                Task { await model.runBenchmark() }
            }
            .disabled(model.isMeasuring || model.clips.isEmpty)

            Button(model.isMeasuring ? "Měřím…" : "Okno vs celá obrazovka") {
                Task { await model.runFullScreenComparison() }
            }
            .disabled(model.isMeasuring || model.selected == nil)

            Text(verbatim: """
                Srovnání běží na vybraném klipu: zahřívací běh a pak dvě kola v opačném \
                pořadí. Počítej asi 4 minuty.

                ⚠️ Po spuštění se aplikace nesmí dostat na pozadí ani na jiný Space. \
                Když okno není vidět, systém ho přestane skládat, měření vyjde jako \
                dokonalé a přitom neměřilo nic. Klikni na tlačítko a nech myš i \
                klávesnici být.

                Před spuštěním zmenši okno, ať je co porovnávat. A pusť vedle v Terminálu:
                sudo powermetrics --samplers gpu_power,cpu_power -i 1000 > ~/aiditor_gpu.txt
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.reportLines.isEmpty {
                ScrollView {
                    Text(model.reportLines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160)
            }
        }
        .padding(12)
    }

    /// Vybraný klip drží `AppModel`, ne `@State` ve view — jedno úložiště,
    /// žádná synchronizace. Se dvěma kopiemi by se po přetvoření view
    /// rozešel zvýrazněný řádek od klipu načteného v přehrávači.
    private var clipSelection: Binding<URL?> {
        Binding(
            get: { model.selected?.url },
            set: { url in
                guard let url,
                      let clip = model.clips.first(where: { $0.url == url }),
                      clip.url != model.selected?.url else { return }
                Task { await model.select(clip) }
            })
    }

    /// Datum ze SOUBORU se přiznává — po zkopírování z karty to bývá čas
    /// kopírování, ne natáčení.
    private static func creationText(_ date: Date, source: CreationDateSource?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d. M. yyyy HH:mm:ss"
        let text = formatter.string(from: date)
        return source == .fileSystem ? "\(text) (datum souboru)" : text
    }
}
