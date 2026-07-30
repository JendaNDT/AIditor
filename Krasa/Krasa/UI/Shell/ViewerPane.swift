//
//  ViewerPane.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 1. Plocha náhledu: obraz, čipy stavu, měřidlo hlasitosti,
//  titulkové overlaye a pilulka transportu.
//
//  ⚠️ POZOR NA GPU (riziko R2 plánu fáze 18).
//  Podle měření z 27. 07. 2026 nesleduje GPU rezidence náhledu plochu obrazu,
//  ale NUTNOST KOMPOZICE: dokud je náhled holé video a nic přes něj neleží,
//  jde na displej jako samostatná vrstva (0,25 %). Návrh klade na obraz čipy,
//  měřidlo i pilulku — tím se skládání zapne natrvalo. Proto:
//
//    · při měření (`chromeHidden` / `isMeasuring`) se overlaye NEKRESLÍ vůbec,
//      jinak by přestaly být srovnatelné všechny starší benchmarky,
//    · `overlaysSuppressed` umí overlaye vypnout i mimo měřicí režim —
//      `--shell-gpu` tím měří tentýž klip s nimi a bez nich a rozdíl se
//      zapíše do `PROJECT_STATUS.md`, místo aby se odhadoval.
//

import AVFoundation
import SwiftUI
import TimelineModel

struct ViewerPane: View {
    @ObservedObject var model: AppModel

    /// Overlaye jsou vidět, jen když se nic neměří a nejsou potlačené.
    private var overlaysVisible: Bool {
        !model.chromeHidden && !model.isMeasuring && !model.overlaysSuppressed
    }

    var body: some View {
        ZStack {
            KrasaUI.surfaceViewer

            PlayerView(player: model.controller.player) { view in
                model.attach(view)
            }
            // Odsazení jen v běžném provozu. Při měření dostane obraz
            // celou plochu — jinak by se měřila jiná plocha než dřív.
            .padding(model.chromeHidden ? 0 : KrasaUI.Metric.viewerPadding)

            if overlaysVisible {
                ViewerChips(timeline: model.timeline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 28)
                    .padding(.top, 28)

                LoudnessGauge(readout: model.lastLoudness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 28)

                // Grafické titulky POD řečovými — řeč je dole u spodní hrany,
                // grafika výš; pořadí v ZStacku rozhoduje jen při překryvu.
                TitleOverlay(timeline: model.timeline)
                SubtitleOverlay(timeline: model.timeline)

                TransportPill(controller: model.controller,
                              frameRate: model.timeline.project.timeline.frameRate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
            }

            // Prázdný start (modul 12): zóna přetažení PŘES plochu náhledu.
            //
            // ⚠️ Překrývá, neodebírá — a je to výjimka z pravidla „chrome se
            // odebírá" schválně. `PlayerView` musí zůstat na svém místě ve
            // stromu: kdyby se při každém přechodu prázdno ↔ materiál
            // přetvářel, vznikl by nový `PlayerHostView` a měřicí běhy
            // (i `attach`) by držely ten starý. Layout se tím nezkresluje —
            // zóna je uvnitř pásu s pevnou výškou, ne kolem něj.
            if model.showsEmptyStart {
                EmptyStartDropZone(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Čipy na obraze

/// Co je zrovna na obraze zapnuté: proxy, rampa vybraného klipu, preset.
///
/// Kreslí se jen to, co PLATÍ — prázdný čip by zabíral místo a nic neříkal.
private struct ViewerChips: View {
    @ObservedObject var timeline: TimelineController

    var body: some View {
        HStack(spacing: 6) {
            if timeline.project.usesProxies {
                chip("Proxy 1/2", color: KrasaUI.textPrimary)
            }
            if let ramp = rampText {
                chip(ramp, color: KrasaUI.rampCurve)
            }
            if let grade = gradeText {
                chip(grade, color: Color(krasaHex: 0xFFD88A))
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(KrasaUI.Font.chip)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                    .fill(Color.black.opacity(0.55))
            )
    }

    /// Jediný vybraný klip — u víc vybraných by čip musel lhát průměrem.
    private var selectedClip: Clip? {
        guard timeline.selection.count == 1, let id = timeline.selection.first else { return nil }
        return timeline.project.timeline.clip(id)
    }

    private var rampText: String? {
        guard let clip = selectedClip, let ramp = clip.speedRamp else { return nil }
        let speeds = ramp.nodes.map(\.speed)
        guard let slowest = speeds.min() else { return nil }
        return "rampa " + Self.number.string(from: NSNumber(value: slowest))! + "×"
    }

    private var gradeText: String? {
        guard let clip = selectedClip, let grade = clip.colorGrade else { return nil }
        return "\(grade.preset.displayName) \(Int((grade.intensity * 100).rounded())) %"
    }

    private static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

// MARK: - Měřidlo hlasitosti

/// Svislé měřidlo vpravo na obraze. **Nekreslí se, dokud není co ukázat** —
/// hlasitost se měří při exportu (fáze 7), ne za běhu přehrávače, a měřidlo,
/// které ukazuje vymyšlené hodnoty, je horší než žádné.
private struct LoudnessGauge: View {
    let readout: LoudnessReadout?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("LUFS")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)

            HStack(spacing: 3) {
                bar
                bar
            }
            .frame(height: 92)

            Text(readout.map { Self.decimal($0.lufs) } ?? "—")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textSecondary)
            Text(readout.map { Self.decimal($0.truePeakDB) + " TP" } ?? "— TP")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(readout == nil ? KrasaUI.textTertiary : KrasaUI.warn)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                .fill(Color.black.opacity(0.45))
        )
        .help(readout == nil
              ? "Hlasitost se změří při exportu."
              : "Naměřeno při posledním exportu.")
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(readout == nil ? KrasaUI.textTertiary.opacity(0.35) : KrasaUI.ok)
            .frame(width: 6)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

/// Poslední naměřená hlasitost dodávky. Drží ji `AppModel`, plní export.
struct LoudnessReadout: Equatable {
    var lufs: Double
    var truePeakDB: Double
}

// MARK: - Pilulka transportu

/// Transport dole na obraze. Hierarchie místo řady stejně velkých tlačítek:
/// play/pauza je kruh 44, krokování a shuttle jsou vedlejší.
///
/// ⚠️ Vlastní view a `@ObservedObject` na controlleru ze stejného důvodu jako
/// dosavadní `TransportBar`: čas se mění 30×/s a překreslovat kvůli tomu celé
/// okno by třicetkrát za sekundu volalo `updateNSView` na časové ose.
private struct TransportPill: View {
    @ObservedObject var controller: PlaybackController
    let frameRate: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(timecode)
                .font(KrasaUI.Font.timecode)
                .foregroundStyle(KrasaUI.textPrimary)
                .monospacedDigit()

            divider

            glyphButton("J", help: "Zpět (JKL)") { _ = controller.shuttle(.backward) }
            glyphButton("◀", help: "O snímek zpět") { controller.step(frames: -1) }

            Button {
                controller.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(KrasaUI.textPrimary)
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KrasaUI.surfaceRail)
                }
                .frame(width: KrasaUI.Metric.transportPlayButton,
                       height: KrasaUI.Metric.transportPlayButton)
            }
            .buttonStyle(.plain)
            .help(controller.isPlaying ? "Pauza (mezerník)" : "Přehrát (mezerník)")

            glyphButton("▶", help: "O snímek vpřed") { controller.step(frames: 1) }
            glyphButton("L", help: "Vpřed (JKL)") { _ = controller.shuttle(.forward) }

            // Čip rychlosti jen když se opravdu shuttluje. Oranžový je
            // vyhrazený krokovacímu fallbacku — je to přiznaná mez, ne ozdoba.
            if controller.shuttleRate != 0 {
                divider
                Text(controller.shuttleDescription)
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(controller.isSteppingFallback
                                     ? KrasaUI.warn : KrasaUI.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                            .fill(controller.isSteppingFallback
                                  ? KrasaUI.warn.opacity(0.14)
                                  : Color.white.opacity(0.08))
                    )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: KrasaUI.Metric.transportPillHeight)
        .background(
            RoundedRectangle(cornerRadius: KrasaUI.Metric.transportPillRadius)
                .fill(Color(krasaHex: 0x121418, opacity: 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: KrasaUI.Metric.transportPillRadius)
                .strokeBorder(KrasaUI.borderActive, lineWidth: 1)
        )
    }

    private func glyphButton(_ glyph: String, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(KrasaUI.Font.controlStrong)
                .foregroundStyle(KrasaUI.textSecondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var divider: some View {
        Color.white.opacity(0.12).frame(width: 1, height: 20)
    }

    /// Plný čtyřskupinový timecode — `MM:SS:FF` by se četlo jako `HH:MM:SS`
    /// (pravidlo pravítka z fáze 2).
    private var timecode: String {
        let time = controller.currentTime
        guard time.isValid, time.seconds.isFinite, time.seconds >= 0 else { return "—" }
        let frame = Frames(Int((time.seconds * Double(frameRate)).rounded()))
        return Timecode(frame, frameRate: frameRate).text
    }
}
