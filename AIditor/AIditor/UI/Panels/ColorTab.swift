//
//  ColorTab.swift
//  Projekt AIditor — UI/Panels
//
//  Fáze 18, modul 8. Záložka Barva připnutého panelu.
//
//  Proti dosavadnímu `ColorGradePanel` (rozbalovátko + posuvník na 260 bodů)
//  přidává to, co zadání žádá: **náhled před a po ze SKUTEČNÉHO snímku klipu**,
//  pět řádků presetů s barevným vzorkem místo rozbalovátka a přiznání, na
//  kolik klipů volba dopadne.
//
//  ⚠️ Vzhled presetů drží dál JEN `ColorPresetFilter` — tady se jím jen
//  renderuje náhled. Kdyby si panel míchal barvy sám, rozešel by se s tím,
//  co vyleze z exportu, a nikdo by nepoznal, které z těch dvou lže.
//

import AVFoundation
import CoreImage
import SwiftUI
import TimelineModel

struct ColorTab: View {
    @ObservedObject var timeline: TimelineController
    let clipID: ClipID

    @State private var before: NSImage?
    @State private var after: NSImage?
    /// Zdrojový snímek se drží dekódovaný — přebarvení pro jinou intenzitu
    /// je pak jen render CoreImage, ne nové čtení souboru.
    @State private var sourceFrame: CIImage?
    @State private var loadedFrameKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewRow
            presetRows
            strengthRow
            selectionRow
            actionRow
        }
        .task(id: frameKey) { await loadFrameIfNeeded() }
        .task(id: gradeKey) { renderAfter() }
    }

    private var clip: Clip? { timeline.project.timeline.clip(clipID) }
    private var grade: ColorGrade? { clip?.colorGrade }

    // MARK: - Náhled před / po

    private var previewRow: some View {
        HStack(spacing: 8) {
            tile(image: before, label: "originál", highlighted: false)
            tile(image: after, label: gradeLabel, highlighted: grade != nil)
        }
    }

    private func tile(image: NSImage?, label: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(AIditorUI.surfaceWindow)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(height: 52)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(highlighted ? AIditorUI.accent : AIditorUI.border, lineWidth: 1))
            Text(label)
                .font(AIditorUI.Font.chip)
                .foregroundStyle(AIditorUI.textTertiary)
                .lineLimit(1)
        }
    }

    private var gradeLabel: String {
        guard let grade else { return "bez úpravy" }
        return "\(grade.preset.displayName) \(Int((grade.intensity * 100).rounded())) %"
    }

    // MARK: - Presety

    /// Pět řádků: „Bez úpravy" a čtyři presety v pořadí `ColorPreset`.
    /// Vzorek je vyrobený TÍMŽ filtrem jako náhled — barevný čtvereček
    /// namíchaný ručně by se s presetem rozešel.
    private var presetRows: some View {
        VStack(spacing: 4) {
            presetRow(nil)
            ForEach(ColorPreset.allCases, id: \.self) { presetRow($0) }
        }
    }

    private func presetRow(_ preset: ColorPreset?) -> some View {
        let isSelected = grade?.preset == preset
        return Button {
            if let preset {
                timeline.setColorGradeOnSelection(
                    ColorGrade(preset: preset, intensity: grade?.intensity ?? 1.0))
            } else {
                timeline.setColorGradeOnSelection(nil)
            }
        } label: {
            HStack(spacing: 8) {
                swatch(preset)
                Text(preset?.displayName ?? "Bez úpravy")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AIditorUI.accent : AIditorUI.textPrimary)
                Spacer(minLength: 0)
                if isSelected {
                    Text("vybráno")
                        .font(AIditorUI.Font.chip)
                        .foregroundStyle(AIditorUI.accent)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(aiditorHex: 0x3A3320) : AIditorUI.surfaceRow))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? AIditorUI.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ preset: ColorPreset?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(AIditorUI.surfaceWindow)
            if let image = swatchImage(preset) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(width: 34, height: 18)
    }

    private func swatchImage(_ preset: ColorPreset?) -> NSImage? {
        guard let sourceFrame else { return nil }
        guard let preset else { return Self.render(sourceFrame) }
        return Self.render(ColorPresetFilter.apply(
            ColorGrade(preset: preset, intensity: 1.0), to: sourceFrame))
    }

    // MARK: - Síla

    private var strengthRow: some View {
        HStack(spacing: 8) {
            Text("Síla")
                .font(AIditorUI.Font.control)
                .foregroundStyle(AIditorUI.textSecondary)
            Slider(value: Binding(
                get: { (grade?.intensity ?? 1.0) * 100 },
                set: { percent in
                    guard let preset = grade?.preset else { return }
                    timeline.colorGradeDragChangedOnSelection(
                        ColorGrade(preset: preset, intensity: percent / 100))
                }), in: 0...100,
                onEditingChanged: { editing in
                    // Undo se skládá kolem tažení (vzorec hlasitosti a zoomu):
                    // jeden krok za celé tažení, ne za každý pixel.
                    if editing { timeline.colorGradeDragBegan() }
                    else { timeline.colorGradeDragEnded() }
                })
                .controlSize(.small)
                .tint(AIditorUI.accent)
                .disabled(grade == nil)
            Text("\(Int(((grade?.intensity ?? 0) * 100).rounded())) %")
                .font(AIditorUI.Font.monoSmall)
                .foregroundStyle(AIditorUI.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Na co to platí

    /// Kolik obrazových klipů volba zasáhne. Přiznat to je podstatné:
    /// od F17 jedou presety na CELÝ výběr a „proč se přebarvilo pět klipů"
    /// je otázka, kterou si uživatel nemá klást.
    private var selectedVideoCount: Int {
        timeline.project.timeline.tracks
            .filter { $0.kind == .video }
            .reduce(0) { $0 + $1.clips.filter { timeline.selection.contains($0.id) }.count }
    }

    private var selectionRow: some View {
        HStack(spacing: 8) {
            Text(selectedVideoCount > 1
                 ? "platí pro výběr · \(selectedVideoCount) klipů"
                 : "platí pro tenhle klip")
                .font(AIditorUI.Font.chip)
                .foregroundStyle(selectedVideoCount > 1 ? AIditorUI.accent : AIditorUI.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.chipRadius)
                    .fill(selectedVideoCount > 1
                          ? AIditorUI.accent.opacity(0.12) : Color.clear))
            Text("jeden krok ⌘Z")
                .font(AIditorUI.Font.chip)
                .foregroundStyle(AIditorUI.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            ChromeButton(title: "Zrušit preset") {
                timeline.setColorGradeOnSelection(nil)
            }
            .disabled(grade == nil)
            Spacer(minLength: 0)
        }
        .help("Vlastní kompozitor se staví jen s presetem — bez něj jde náhled "
              + "přímou cestou. Se presety je skok GPU medián ~24 % (změřeno --color-gpu).")
    }

    // MARK: - Render náhledu

    /// Klíč zdrojového snímku: klip a čas ve zdroji. Změna intenzity ho
    /// nemění, takže se soubor nečte znovu.
    private var frameKey: String {
        guard let clip else { return "" }
        let offset = timeline.playhead - clip.timelineStart
        let source = timeline.project.sourceOffset(in: clip, atFrame: offset)
        return "\(clipID)|\(source.seconds.rounded())"
    }

    private var gradeKey: String {
        guard let grade else { return "\(loadedFrameKey)|none" }
        return "\(loadedFrameKey)|\(grade.preset.rawValue)|\(grade.intensity)"
    }

    private func loadFrameIfNeeded() async {
        guard !frameKey.isEmpty, frameKey != loadedFrameKey else { return }
        guard let clip, let asset = timeline.project.asset(clip.assetID) else { return }
        let offset = timeline.playhead - clip.timelineStart
        let source = timeline.project.sourceOffset(in: clip, atFrame: offset)

        // Malý náhled — dekodér ho zmenší sám a 4K snímek by tu byl plýtvání.
        // Nulová tolerance jako všude jinde v projektu.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.originalURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        let time = CMTime(value: source.value, timescale: source.timescale)
        guard let cgImage = try? await generator.image(at: time).image else { return }

        sourceFrame = CIImage(cgImage: cgImage)
        loadedFrameKey = frameKey
        before = Self.render(sourceFrame!)
        renderAfter()
    }

    private func renderAfter() {
        guard let sourceFrame else { return }
        guard let grade, grade.isUsable else {
            after = before
            return
        }
        after = Self.render(ColorPresetFilter.apply(grade, to: sourceFrame))
    }

    /// CoreImage → `NSImage`. Kontext se vyrábí jednou: `CIContext` je drahý
    /// objekt a zakládat ho na každý render by bylo znát na posuvníku síly.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private static func render(_ image: CIImage) -> NSImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: image.extent.size)
    }
}
