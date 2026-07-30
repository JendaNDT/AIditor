//
//  AIditorToolbar.swift
//  Projekt AIditor — UI/Shell
//
//  Fáze 18, modul 1. Horní lišta: identita dokumentu vlevo, akce uprostřed,
//  dodávka vpravo. Nahrazuje horní část dosavadního sidebaru a `ProjectStatusRow`.
//
//  Čip běžících analýz (vpravo, před `Rampa ⌘4`) patří modulu 2 — tady je
//  po něm jen místo, ne zástupka.
//

import SwiftUI
import TimelineModel

struct AIditorToolbar: View {
    @ObservedObject var model: AppModel
    let mode: ShellMode

    var body: some View {
        HStack(spacing: 10) {
            ProjectTitleBlock(store: model.projectStore, timeline: model.timeline,
                              isEmptyStart: model.showsEmptyStart)

            verticalDivider

            // Bez materiálu nemá smysl nabízet titulek ani zmrazení snímku —
            // jsou to operace nad klipem, který neexistuje. Místo nich
            // dvojice, kterou návrh v prázdném stavu ukazuje (obrazovka 2).
            if model.showsEmptyStart {
                emptyStartActions
            } else {
                actions
            }

            Spacer(minLength: 12)

            // Čip běžících analýz (M2). Kreslí se jen když něco běží.
            AnalysisChip(analysis: model.analysis)

            if !model.showsEmptyStart {
                ChromeButton(title: "Rampa ⌘4",
                             style: model.panelVisible ? .active : .normal) {
                    model.panelVisible.toggle()
                }
                .keyboardShortcut("4", modifiers: .command)

                ChromeButton(title: "Exportovat…", style: .primary) {
                    model.openExportSheet()
                }
                .disabled(model.clips.isEmpty || model.isMeasuring)
            }

            if mode == .fullscreenApp {
                verticalDivider
                ChromeButton(title: "Zpět do okna ⌃⌘F", style: .normal) {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
        }
        .padding(.leading, mode.toolbarLeading)
        .padding(.trailing, 16)
        .frame(height: mode.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(AIditorUI.surfaceChrome)
    }

    /// Prázdný start: otevřít hotový projekt, nebo založit nový výběrem
    /// materiálu. **Projekt v AIditoru vzniká z materiálu** — prázdná osa se
    /// neukládá, takže „Nový projekt" znamená „vyber, z čeho".
    private var emptyStartActions: some View {
        HStack(spacing: 6) {
            ChromeButton(title: "Otevřít projekt… ⌘O") {
                model.openProjectViaPanel()
            }
            ChromeButton(title: "Nový projekt ⌘N", style: .primary) {
                Task { await model.openFiles(directories: false) }
            }
            .disabled(model.isMeasuring)
            .help("Projekt vznikne z vybraného materiálu — prázdná osa se neukládá.")
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ChromeButton(title: "Přidat média…") {
                Task { await model.openFiles(directories: false) }
            }
            .disabled(model.isMeasuring)

            ChromeButton(title: "Titulek") { model.addTitleAtPlayhead() }
                .disabled(!model.canAddTitle)

            ChromeButton(title: "Hudba") { model.addMusic() }
                .disabled(model.isMeasuring)

            ChromeButton(title: "Zmrazit snímek") { model.freezeSelectedClip() }
                .disabled(!model.canFreezeFrame)
        }
    }

    private var verticalDivider: some View {
        AIditorUI.border.frame(width: 1, height: 22)
    }
}

/// Jméno projektu a jeho meta. Vlastní view kvůli vnořeným
/// `ObservableObject`ům — `ContentView` by změnu v `ProjectStore` neviděl
/// (past pojmenovaná u `TransportBar` už ve fázi 1).
private struct ProjectTitleBlock: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var timeline: TimelineController
    var isEmptyStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(isEmptyStart ? "AIditor" : store.displayName)
                .font(AIditorUI.Font.projectName)
                .foregroundStyle(AIditorUI.textPrimary)
                .lineLimit(1)
            Text(isEmptyStart ? "bez projektu" : meta)
                .font(AIditorUI.Font.projectMeta)
                .foregroundStyle(AIditorUI.textTertiary)
                .lineLimit(1)
        }
        .help(store.fileURL?.path ?? "Projekt zatím není uložený — ⌘S ho uloží.")
    }

    private var meta: String {
        var parts: [String] = [saveState]
        let t = timeline.project.timeline
        parts.append("\(t.frameRate) fps")
        parts.append("\(t.canvasSize.width)×\(t.canvasSize.height)")
        if timeline.project.usesProxies { parts.append("proxy") }
        return parts.joined(separator: " · ")
    }

    private var saveState: String {
        if store.isDirty { return "neuloženo" }
        guard let saved = store.lastSavedAt else { return "⌘S uloží" }
        return "uloženo " + saved.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Tlačítko chrome

/// Tlačítko v liště. Tři podoby podle zadání: běžné (`surfaceControl`),
/// aktivní (`surfaceControlActive`) a primární (výplň `accent`).
///
/// Vlastní styl, ne systémový `.bordered` — systémové tlačítko si na
/// macOS kreslí vlastní pozadí i obrys a paleta zadání by se přes něj
/// neprosadila.
struct ChromeButton: View {
    enum Style { case normal, active, primary }

    let title: String
    var style: Style = .normal
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style == .primary ? AIditorUI.Font.controlStrong : AIditorUI.Font.control)
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: AIditorUI.Metric.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                        .strokeBorder(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var foreground: Color {
        guard isEnabled else { return AIditorUI.textDisabled }
        return style == .primary ? AIditorUI.accentText : AIditorUI.textPrimary
    }

    private var background: Color {
        switch style {
        case .normal: return AIditorUI.surfaceControl
        case .active: return AIditorUI.surfaceControlActive
        case .primary: return AIditorUI.accent
        }
    }

    private var border: Color {
        switch style {
        case .normal: return AIditorUI.borderStrong
        case .active: return AIditorUI.borderActive
        case .primary: return .clear
        }
    }
}
