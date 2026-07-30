//
//  PinnedPanel.swift
//  Projekt Krása — UI/Panels
//
//  Fáze 18, modul 7. Připnutý panel vpravo od osy (452 px): hlavička s jménem
//  klipu, záložky, tělo se scrollem. `⌘4` ho skryje a šířku dostane osa.
//
//  ⚠️ Panel NENÍ jen širší inspektor. Dosavadní `InspectorStrip` měl 132 bodů
//  výšky na křivku rychlosti I na barvy vedle sebe — to je potíž #2 zadání.
//  Tady má křivka box 150 px a zbytek sekcí pod sebou.
//
//  Výběry se navzájem vylučují (pravidlo z fáze 11): titulek, úsek řeči,
//  fotka a video klip mají každý svůj obsah. Záložky se ukazují jen u video
//  klipu — u titulku by záložka Rychlost nebyla k ničemu.
//

import SwiftUI
import TimelineModel

/// Která záložka panelu je vybraná. Všechny čtyři od modulu 8.
enum PanelTab: String, CaseIterable, Identifiable {
    case speed, color, audio, info

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed: return "Rychlost"
        case .color: return "Barva"
        case .audio: return "Zvuk"
        case .info: return "Info"
        }
    }
}

struct PinnedPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            KrasaUI.border.frame(height: 1)
            content
        }
        .background(KrasaUI.surfacePanel)
    }

    private var timeline: TimelineController { model.timeline }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(KrasaUI.Font.controlStrong)
                    .foregroundStyle(KrasaUI.textPrimary)
                    .lineLimit(1)
                if let meta = headerMeta {
                    Text(meta)
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("⌘4 skryje")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var headerTitle: String {
        if model.railSection == .settings { return "Nastavení" }
        if model.railSection == .speech { return "Přepis řeči" }
        if timeline.selectedTitle != nil { return "Titulek" }
        if timeline.selectedSpeech != nil { return "Úsek řeči" }
        guard let clip = selectedClip,
              let asset = timeline.project.asset(clip.assetID) else { return "Inspektor" }
        return asset.originalURL.deletingPathExtension().lastPathComponent
    }

    /// „zdroj 120 fps · 0:22" — čte se z assetu a z délky klipu, nic se
    /// nedomýšlí. U fotky frekvence zdroje nemá smysl, takže tam není.
    private var headerMeta: String? {
        guard model.railSection != .settings, model.railSection != .speech,
              let clip = selectedClip,
              let asset = timeline.project.asset(clip.assetID) else { return nil }
        let rate = timeline.project.timeline.frameRate
        let length = Timecode(clip.duration, frameRate: rate).shortText
        if asset.isStill { return "fotka · \(length)" }
        return String(format: "zdroj %.0f fps · %@", asset.measuredFrameRate, length)
    }

    // MARK: - Tělo

    @ViewBuilder
    private var content: some View {
        if model.railSection == .settings {
            ScrollView { LegacySettingsPanel(model: model) }
        } else if model.railSection == .speech {
            // Přepis řeči má vlastní panel se dvěma stavy (F18/M11) —
            // není to inspektor klipu, takže nejde do záložek.
            TranscriptPanel(model: model, timeline: timeline,
                            transcription: model.transcription)
        } else if let titleID = timeline.selectedTitle,
                  let title = timeline.project.timeline.titleClip(titleID) {
            scrolled {
                TitleInspector(timeline: timeline, titleID: titleID, title: title)
            }
        } else if let speech = timeline.selectedSpeech,
                  let text = speechText(speech) {
            scrolled {
                SpeechInspector(timeline: timeline, selection: speech, currentText: text)
            }
        } else if let clip = selectedClip, timeline.project.asset(clip.assetID)?.isStill == true {
            // Fotka: rampa je na ní zakázaná (freeze frame se dělá fotkou),
            // takže místo záložky Rychlost jde Ken Burns.
            scrolled {
                VStack(alignment: .leading, spacing: 12) {
                    PhotoInspector(timeline: timeline, clipID: clip.id)
                    ColorTab(timeline: timeline, clipID: clip.id)
                }
            }
        } else if let clip = selectedClip {
            VStack(spacing: 0) {
                tabs
                scrolled { tabBody(clipID: clip.id) }
            }
        } else {
            placeholder
        }
    }

    private var tabs: some View {
        HStack(spacing: 14) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    model.panelTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Text(tab.label)
                            .font(.system(size: 11,
                                          weight: model.panelTab == tab ? .semibold : .regular))
                            .foregroundStyle(model.panelTab == tab
                                             ? KrasaUI.textPrimary : KrasaUI.textSecondary)
                        // Podtržení 2 px u aktivní záložky (zadání návrhu).
                        Rectangle()
                            .fill(model.panelTab == tab ? KrasaUI.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func tabBody(clipID: ClipID) -> some View {
        switch model.panelTab {
        case .speed:
            SpeedTab(timeline: timeline, model: model, clipID: clipID)
        case .color:
            ColorTab(timeline: timeline, clipID: clipID)
        case .audio:
            AudioTab(timeline: timeline, model: model, clipID: clipID)
        case .info:
            InfoTab(timeline: timeline, model: model, clipID: clipID)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Vyber klip na ose")
                .font(KrasaUI.Font.control)
                .foregroundStyle(KrasaUI.textTertiary)
            Text("Rychlost, barva a zvuk platí pro vybraný klip.")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textDisabled)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// ⚠️ `min-height: 0` a scroll (zadání): rozpočet výšky panelu je ~360
    /// bodů a obsah se do něj musí vejít, ne ho roztlačit. Bez scrollu by
    /// dlouhá záložka vytlačila osu z okna.
    private func scrolled<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Výběr

    /// Jediný vybraný klip. U víc vybraných panel neukazuje nic konkrétního —
    /// hromadné operace jedou z kontextového menu a z lišty, ne odsud.
    private var selectedClip: Clip? {
        guard timeline.selection.count == 1, let id = timeline.selection.first else { return nil }
        return timeline.project.timeline.clip(id)
    }

    private func speechText(_ selection: TimelineController.SpeechSelection) -> String? {
        guard let transcript = timeline.project.asset(selection.assetID)?.transcript,
              selection.segmentIndex < transcript.count else { return nil }
        return transcript[selection.segmentIndex].text
    }
}
