//
//  TimelineLayerBar.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 3. Lišta nad osou (32 px): co se kreslí, jak citlivé jsou
//  analýzy, přichytávání, výřez a zoom.
//
//  ⚠️ Vypnutá vrstva se NEPOČÍTÁ, ne jen neukazuje. Jediný důvod, proč
//  přepínače existují, je ubrat práci na dvacetiminutové ose — kdyby se
//  vrstva jen skryla, přepínač by nic neušetřil a byl by to podvod na
//  uživateli, který ho zmáčkl právě proto, že mu to jelo pomalu.
//  Rozhodnutí sedí v `rebuildClipInfo`, `applyWaveform` a `drawBeatMarks`.
//

import SwiftUI
import TimelineModel

struct TimelineLayerBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            Text("Na ose:")
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textTertiary)

            layerToggles

            divider

            sensitivity

            divider

            BarPill(title: "Přichytávání", isOn: model.timeline.snappingEnabled,
                    help: "Magnet na hrany klipů, doby hudby a mřížku snímků.") {
                model.timeline.snappingEnabled.toggle()
            }
            Text("Shift vypne")
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textTertiary)

            Spacer(minLength: 8)

            exportRange

            divider

            zoom
        }
        .padding(.horizontal, 12)
        .frame(height: KrasaUI.Metric.timelineToolbarHeight)
        .frame(maxWidth: .infinity)
        .background(KrasaUI.surfaceChrome)
    }

    // MARK: - Vrstvy

    private var layerToggles: some View {
        HStack(spacing: 6) {
            // Od modulu 5 zapojené naostro. Vypnutá vrstva se NEPOČÍTÁ:
            // early-out je v `applyThumbnails`, takže se nezadá ani jeden
            // požadavek na dekódování snímku.
            BarPill(title: "Miniatury", isOn: model.timeline.layers.thumbnails,
                    help: "Pás miniatur v dolní části obrazových klipů.") {
                model.timeline.layers.thumbnails.toggle()
            }

            BarPill(title: "Vlny", isOn: model.timeline.layers.waveforms,
                    help: "Vlnové průběhy na zvukových klipech.") {
                model.timeline.layers.waveforms.toggle()
            }
            BarPill(title: "Doby", isOn: model.timeline.layers.beats,
                    help: "Jantarové rysky dob hudby v pravítku.") {
                model.timeline.layers.beats.toggle()
            }
            BarPill(title: "Značky kvality", isOn: model.timeline.layers.qualityMarks,
                    help: "Proužky neostrosti u horní hrany klipu a hluchých míst u spodní.") {
                model.timeline.layers.qualityMarks.toggle()
            }
        }
    }

    // MARK: - Citlivost

    private var sensitivity: some View {
        HStack(spacing: 6) {
            Text("Citlivost")
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textTertiary)
            Slider(value: Binding(
                get: { model.timeline.qualitySensitivity },
                set: { model.timeline.qualitySensitivity = $0 }), in: 0...1)
                .controlSize(.mini)
                .tint(KrasaUI.warn)
                .frame(width: 80)
                .disabled(!model.timeline.layers.qualityMarks)
                .help("Přepočítá ZNAČKY z hotových vzorků — analýza se nespouští znovu, "
                      + "takže je to okamžité. Výš = hlásí se i mírnější propady ostrosti.")
            Text(Self.decimal(model.timeline.qualitySensitivity))
                .font(KrasaUI.Font.monoSmall)
                .foregroundStyle(KrasaUI.textSecondary)
                .frame(width: 26, alignment: .leading)
        }
    }

    // MARK: - Výřez

    private var exportRange: some View {
        HStack(spacing: 6) {
            // Kreslí se jen když je výřez opravdu výřez — jinak by „nic
            // nevybráno" a „vybráno vše" vypadalo stejně (pravidlo fáze 17).
            if let text = exportRangeText {
                Text(text)
                    .font(KrasaUI.Font.monoSmall)
                    .foregroundStyle(KrasaUI.textSecondary)
            }
            markButton("I", help: "In bod na hlavu (⌥I zruší)") {
                model.timeline.setInPoint(model.timeline.playhead)
            }
            markButton("O", help: "Out bod na hlavu (⌥O zruší)") {
                model.timeline.setOutPoint(model.timeline.playhead)
            }
        }
    }

    private var exportRangeText: String? {
        let timeline = model.timeline
        guard timeline.hasExportRange else { return nil }
        let range = timeline.exportRange
        let rate = timeline.project.timeline.frameRate
        return "výřez \(Timecode(range.lowerBound, frameRate: rate).shortText)"
            + "–\(Timecode(range.upperBound, frameRate: rate).shortText)"
    }

    private func markButton(_ title: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KrasaUI.Font.controlStrong)
                .foregroundStyle(KrasaUI.accent)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                        .fill(KrasaUI.surfaceRow))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Zoom

    private var zoom: some View {
        HStack(spacing: 6) {
            Text("zoom")
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textTertiary)
            Slider(value: Binding(get: { zoomSliderValue },
                                  set: { setZoomFromSlider($0) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: 96)
            BarPill(title: "Fit ⇧Z", isOn: false,
                    help: "Celá osa do okna.") {
                model.timelinePane?.zoomToFit()
            }
        }
    }

    /// Posuvník je LOGARITMICKÝ. Lineární by dal celou levou polovinu dráhy
    /// rozsahu 0,02–60 bodů na snímek, ve kterém se nedá pracovat, a celý
    /// použitelný střed by se vešel do posledních pár pixelů.
    private static let minZoom = 0.05
    private static let maxZoom = 60.0

    private var zoomSliderValue: Double {
        let value = model.timeline.geometry.pointsPerFrame
        let clamped = min(max(value, Self.minZoom), Self.maxZoom)
        return log(clamped / Self.minZoom) / log(Self.maxZoom / Self.minZoom)
    }

    private func setZoomFromSlider(_ position: Double) {
        var geometry = model.timeline.geometry
        geometry.setZoom(Self.minZoom * pow(Self.maxZoom / Self.minZoom, position))
        model.timeline.geometry = geometry
    }

    // MARK: - Drobnosti

    private var divider: some View {
        KrasaUI.border.frame(width: 1, height: 18)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Pilulka lišty

/// Přepínač v liště osy. Zapnutý `surfaceRailActive` + `borderActive`,
/// vypnutý `surfaceRow` + `border` — podle zadání návrhu.
struct BarPill: View {
    let title: String
    let isOn: Bool
    var isEnabled = true
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isEnabled
                                 ? (isOn ? KrasaUI.textPrimary : KrasaUI.textSecondary)
                                 : KrasaUI.textDisabled)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? KrasaUI.surfaceRailActive : KrasaUI.surfaceRow))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isOn ? KrasaUI.borderActive : KrasaUI.border,
                                      lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help ?? title)
    }
}
