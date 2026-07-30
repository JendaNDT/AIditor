//
//  ExportSheet.swift
//  Projekt Krása — UI/Export
//
//  List exportu (fáze 18, modul 10). Tři stavy: nastavení → průběh → hotovo.
//  Zdroj zadání: `design_handoff_krasa_ui/README.md`, obrazovka 3.
//
//  ⚠️ List NEZAKLÁDÁ druhou exportní cestu. Tlačítko volá `AppModel.export(to:)`,
//  tedy tutéž funkci, kterou používají všechny CLI kontroly — jinak by se
//  „co vyexportuje uživatel" a „co měří `--export-check`" rozešlo a nikdo by
//  si toho nevšiml.
//
//  ⚠️ Varovný blok o duplikaci snímků počítá podíl MODELEM
//  (`Project.duplicatedFrameShare`), ne konstantou v UI — pojmenované riziko
//  modulu v plánu. Číslo se musí měnit s materiálem: 30fps zdroj s rampou na
//  0,25× dá 37,5 %, 120fps zdroj nulu.
//
//  ⚠️ Odhad času se ukazuje JEN po prvním exportu, ze skutečně naměřené
//  rychlosti. Vymyšlené „~1 min" v listu, který má být kontrolní, je horší
//  než přiznané „ukáže se po prvním exportu".
//

import AudioEngine
import SwiftUI
import TimelineModel

struct ExportSheet: View {
    @ObservedObject var model: AppModel

    private static let width: CGFloat = 660

    var body: some View {
        ZStack {
            // Ztmavení okna pod listem. Klik mimo list ho NEZAVÍRÁ: během
            // exportu by to vypadalo jako zrušení a v nastavení by se ztratila
            // rozdělaná volba.
            Color(krasaHex: 0x060708, opacity: 0.62)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                KrasaUI.border.frame(height: 1)
                content
            }
            .frame(width: Self.width)
            .background(Color(krasaHex: 0x191B1F))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(KrasaUI.borderActive, lineWidth: 1))
            .shadow(color: .black.opacity(0.65), radius: 35, y: 30)
            .padding(.top, 56)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exportovat film")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KrasaUI.textPrimary)
                Text("vždy z originálů, proxy se nepoužije")
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Timecode(Frames(model.exportSheetFrameCount),
                              frameRate: model.timeline.project.timeline.frameRate).text)
                    .font(KrasaUI.Font.timecode)
                    .foregroundStyle(KrasaUI.textPrimary)
                Text(estimateText)
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var estimateText: String {
        let frames = model.exportSheetFrameCount
        guard let fps = model.exportMeasuredFPS, fps > 0 else {
            return "\(frames) snímků · odhad času po prvním exportu"
        }
        let seconds = Double(frames) / fps
        let minutes = Int(seconds) / 60
        let text = minutes > 0
            ? "\(minutes) min \(Int(seconds) % 60) s"
            : "\(Int(seconds.rounded())) s"
        return String(format: "%d snímků · odhad %@ (naposled %.0f fps)", frames, text, fps)
    }

    @ViewBuilder
    private var content: some View {
        switch model.exportSheet {
        case .progress: progressBody
        case .done: doneBody
        default: settingsBody
        }
    }

    // MARK: - Nastavení

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ Bez `ScrollView`. Obsah je ohraničený (šest sekcí a nejvýš
            // jeden varovný blok), ale scroll view si vezme celou nabídnutou
            // výšku — v listu pak zůstala třetina prázdna. Chytil snímek listu.
            VStack(alignment: .leading, spacing: 16) {
                rangeSection
                imageSection
                loudnessSection
                titleSection
                destinationSection
                duplicationWarning
            }
            .padding(20)
            KrasaUI.border.frame(height: 1)
            HStack(spacing: 10) {
                Text(footerEstimate)
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textTertiary)
                    .lineLimit(1)
                Spacer()
                SheetButton(title: "Zrušit") { model.exportSheet = nil }
                SheetButton(title: "Exportovat", isPrimary: true,
                            isEnabled: model.exportDestination != nil
                                && model.exportSheetFrameCount > 0) {
                    model.runExportFromSheet()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    /// Patička nese ODHAD, ne cestu — ta je v sekci „Uložit jako" o dva
    /// řádky výš a dvakrát totéž je jen šum.
    private var footerEstimate: String {
        guard let fps = model.exportMeasuredFPS, fps > 0 else {
            return "Hardwarový kodér HEVC · odhad času až po prvním exportu"
        }
        let seconds = Double(model.exportSheetFrameCount) / fps
        return "Odhad \(AppModel.decimal(seconds, places: 0)) s · hardwarový kodér "
            + "(~\(AppModel.decimal(fps, places: 0)) fps)"
    }

    private var rangeSection: some View {
        section("Rozsah") {
            HStack(spacing: 10) {
                RangeCard(title: "Celý projekt",
                          detail: rangeDetail(for: false),
                          isOn: !model.exportsRangeEffectively) { model.exportUsesRange = false }
                RangeCard(title: "Jen výřez I—O",
                          detail: model.timeline.hasExportRange
                              ? rangeDetail(for: true)
                              : "výřez není nastavený",
                          isOn: model.exportsRangeEffectively,
                          isEnabled: model.timeline.hasExportRange) {
                    model.exportUsesRange = true
                }
            }
        }
    }

    private func rangeDetail(for usesRange: Bool) -> String {
        let project = model.timeline.project
        let rate = project.timeline.frameRate
        let range = usesRange
            ? model.timeline.exportRange
            : project.exportRange(inPoint: nil, outPoint: nil)
        let frames = max(0, range.upperBound.count - range.lowerBound.count)
        if usesRange {
            return "\(Timecode(range.lowerBound, frameRate: rate).text)"
                + " → \(Timecode(range.upperBound, frameRate: rate).text) · \(frames) snímků"
        }
        return "\(Timecode(range.upperBound, frameRate: rate).text) · \(frames) snímků"
    }

    private var imageSection: some View {
        section("Obraz") {
            HStack(spacing: 8) {
                let canvas = model.timeline.project.timeline.canvasSize
                Text("HEVC · \(canvas.width)×\(canvas.height) · "
                     + "\(model.timeline.project.timeline.frameRate) fps")
                    .font(KrasaUI.Font.control)
                    .foregroundStyle(KrasaUI.textSecondary)
                Chip(text: "CFR", color: KrasaUI.ok)
                Text("pevná mřížka snímků, `mediaTimeScale` podle základny")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
        }
    }

    private var loudnessSection: some View {
        section("Hlasitost") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(LoudnessChoice.allCases) { choice in
                        Radio(title: choice.label, isOn: choice.profile == model.loudnessProfile) {
                            model.loudnessProfile = choice.profile
                        }
                    }
                }
                Text("Změří se celý mix, strop −1 dBTP. Když zesílení narazí "
                     + "na špičky, řekne se to.")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
        }
    }

    private var titleSection: some View {
        section("Titulky") {
            VStack(alignment: .leading, spacing: 6) {
                Checkbox(title: "Vypálit grafické titulky (T1)",
                         detail: titleCountText,
                         isOn: model.exportBurnsTitles) { model.exportBurnsTitles.toggle() }
                Checkbox(title: "Uložit řeč jako .srt vedle filmu",
                         detail: subtitleCountText,
                         isOn: model.exportWritesSRT,
                         isEnabled: !model.timeline.project.subtitleCues().isEmpty) {
                    model.exportWritesSRT.toggle()
                }
            }
        }
    }

    private var titleCountText: String {
        let count = model.timeline.project.titleCues().count
        return count == 0 ? "žádné titulky na T1" : "\(count) titulků"
    }

    private var subtitleCountText: String {
        let count = model.timeline.project.subtitleCues().count
        return count == 0 ? "není co uložit — řeč není přepsaná" : "\(count) úseků z přepisu"
    }

    private var destinationSection: some View {
        section("Uložit jako") {
            HStack(spacing: 10) {
                Text(model.exportDestination?.path ?? "—")
                    .font(KrasaUI.Font.monoSmall)
                    .foregroundStyle(KrasaUI.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                SheetButton(title: "Změnit…") { model.chooseExportDestination() }
            }
        }
    }

    /// Varovný blok o duplikaci snímků. Kreslí se JEN když opravdu bude —
    /// prázdný varovný rámeček učí uživatele varování ignorovat.
    @ViewBuilder
    private var duplicationWarning: some View {
        let warnings = model.exportDuplicationWarnings
        if let worst = warnings.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(KrasaUI.warn)
                    Text(warnings.count == 1
                         ? "Jeden klip zpomaluje pod možnosti zdroje"
                         : "\(warnings.count) klipů zpomaluje pod možnosti zdroje")
                        .font(KrasaUI.Font.controlStrong)
                        .foregroundStyle(KrasaUI.textPrimary)
                }
                Text(warningText(worst))
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Zobrazit klip na ose") {
                    model.timeline.selectClips([worst.id])
                    if let clip = model.timeline.project.timeline.clip(worst.id) {
                        model.timeline.setPlayheadFromUser(clip.timelineStart)
                    }
                    model.exportSheet = nil
                }
                .buttonStyle(.plain)
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.accent)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(KrasaUI.warn.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(KrasaUI.warn.opacity(0.45), lineWidth: 1))
        }
    }

    private func warningText(_ warning: AppModel.DuplicationWarning) -> String {
        String(format: "%@ utáhne čistě jen %@ a rampa jde na %@ — ve zpomalené části "
               + "se snímky zduplikují (%.1f %%) a bude to trhat. "
               + "Export projde, jen to nebude plynulé.",
               warning.name, Self.speed(warning.limit), Self.speed(warning.lowestSpeed),
               warning.share * 100)
    }

    private static func speed(_ value: Double) -> String {
        String(format: "%.3g×", value).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Průběh

    private var progressBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(Int(((model.exportProgress ?? 0) * 100).rounded())) %")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KrasaUI.textPrimary)
                Text(progressDetail)
                    .font(KrasaUI.Font.controlStrong)
                    .foregroundStyle(KrasaUI.textSecondary)
                Spacer()
                if let fps = model.exportMeasuredFPS {
                    Text(String(format: "%.0f fps", fps))
                        .font(KrasaUI.Font.monoSmall)
                        .foregroundStyle(KrasaUI.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(KrasaUI.surfaceControl)
                    RoundedRectangle(cornerRadius: 3).fill(KrasaUI.accent)
                        .frame(width: proxy.size.width * (model.exportProgress ?? 0))
                }
            }
            .frame(height: 6)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.exportStages, id: \.title) { stage in
                    StageRow(stage: stage)
                }
            }

            Text("Můžeš dál stříhat — export si drží vlastní kopii projektu. "
                 + "Zavření okna ho zruší.")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)

            HStack {
                Spacer()
                SheetButton(title: "Skrýt na pozadí") { model.exportSheet = nil }
            }
        }
        .padding(20)
    }

    private var progressDetail: String {
        let total = model.exportSheetFrameCount
        let done = Int((model.exportProgress ?? 0) * Double(total))
        var text = "\(done) z \(total) snímků"
        if let fps = model.exportMeasuredFPS, fps > 0, total > done {
            text += String(format: " · zbývá asi %.0f s", Double(total - done) / fps)
        }
        return text
    }

    // MARK: - Hotovo

    @ViewBuilder
    private var doneBody: some View {
        if let outcome = model.exportOutcome {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    poster(for: outcome)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Film je hotový")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KrasaUI.textPrimary)
                        Text("\(outcome.url.lastPathComponent) · "
                             + ByteCountFormatter.string(fromByteCount: outcome.fileBytes,
                                                         countStyle: .file))
                            .font(KrasaUI.Font.monoSmall)
                            .foregroundStyle(KrasaUI.textSecondary)
                        Text(doneSummary(outcome))
                            .font(KrasaUI.Font.chip)
                            .foregroundStyle(KrasaUI.textTertiary)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    CheckRow(title: "Časování",
                             detail: String(format: "%d fps · zapsáno %d snímků, čekáno %d",
                                            model.timeline.project.timeline.frameRate,
                                            outcome.writtenFrames, outcome.expectedFrames),
                             isGood: outcome.framesMatch)
                    if let line = outcome.loudnessLine {
                        CheckRow(title: "Hlasitost", detail: line,
                                 isGood: !outcome.loudnessCapped)
                    } else {
                        CheckRow(title: "Hlasitost", detail: "bez normalizace", isGood: true)
                    }
                    CheckRow(title: "Titulky", detail: titleResult(outcome), isGood: true)
                }

                HStack(spacing: 10) {
                    Spacer()
                    SheetButton(title: "Ukázat ve Finderu") {
                        NSWorkspace.shared.activateFileViewerSelecting([outcome.url])
                    }
                    SheetButton(title: "Exportovat znovu…") { model.exportSheet = .settings }
                    SheetButton(title: "Zavřít", isPrimary: true) { model.exportSheet = nil }
                }
            }
            .padding(20)
        }
    }

    private func doneSummary(_ outcome: AppModel.ExportOutcome) -> String {
        let rate = model.timeline.project.timeline.frameRate
        var text = String(format: "%.0f s · %@", outcome.elapsedSeconds,
                          outcome.rangeText.map { "výřez " + $0 }
                          ?? "celý projekt " + Timecode(Frames(outcome.expectedFrames),
                                                        frameRate: rate).text)
        if outcome.framesPerSecond > 0 {
            text += String(format: " · %.0f fps", outcome.framesPerSecond)
        }
        return text
    }

    private func titleResult(_ outcome: AppModel.ExportOutcome) -> String {
        var parts: [String] = []
        if outcome.burnedTitles > 0 {
            parts.append("\(outcome.burnedTitles) vypálené")
        } else if model.timeline.project.titleCues().isEmpty {
            parts.append("na T1 nic nebylo")
        } else {
            parts.append("nevypalovaly se (vypnuto)")
        }
        if let srt = outcome.srtURL {
            parts.append("\(srt.lastPathComponent) uložen")
        }
        return parts.joined(separator: " · ")
    }

    /// Miniatura hotového filmu — ze `ThumbnailStore`, tedy z TOHO souboru,
    /// co se právě zapsal. Náhled z osy by ukazoval, co jsme chtěli, ne co
    /// vyšlo.
    @ViewBuilder
    private func poster(for outcome: AppModel.ExportOutcome) -> some View {
        let image = model.timeline.thumbnails.tile(url: outcome.url, rung: 1, index: 0,
                                                  side: 63, scale: 2)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(KrasaUI.surfaceWindow)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Drobnosti

    private func section<Content: View>(_ title: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(KrasaUI.Font.sectionTitle)
                .foregroundStyle(KrasaUI.textTertiary)
            content()
        }
    }
}

// MARK: - Volba hlasitosti

/// Tři možnosti profilu jako výčet, ať se pořadí a názvy nepíšou dvakrát.
enum LoudnessChoice: String, CaseIterable, Identifiable {
    case none, web, broadcast

    var id: String { rawValue }

    var profile: LoudnessProfile? {
        switch self {
        case .none: return nil
        case .web: return .web
        case .broadcast: return .broadcast
        }
    }

    var label: String {
        switch self {
        case .none: return "Bez normalizace"
        case .web: return "Web / sociální sítě (−14 LUFS)"
        case .broadcast: return "Vysílání (−23 LUFS)"
        }
    }
}

// MARK: - Prvky listu

private struct RangeCard: View {
    let title: String
    let detail: String
    let isOn: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(KrasaUI.Font.controlStrong)
                    .foregroundStyle(isEnabled ? KrasaUI.textPrimary : KrasaUI.textDisabled)
                Text(detail)
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(isEnabled ? KrasaUI.textTertiary : KrasaUI.textDisabled)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(KrasaUI.surfaceRow))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isOn ? KrasaUI.accent : KrasaUI.border,
                              lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct Radio: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .strokeBorder(isOn ? KrasaUI.accent : KrasaUI.borderStrong, lineWidth: 1.5)
                    .background(Circle().fill(isOn ? KrasaUI.accent.opacity(0.35) : .clear))
                    .frame(width: 11, height: 11)
                Text(title)
                    .font(KrasaUI.Font.control)
                    .foregroundStyle(isOn ? KrasaUI.textPrimary : KrasaUI.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Checkbox: View {
    let title: String
    let detail: String
    let isOn: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn && isEnabled ? KrasaUI.accent : KrasaUI.surfaceControl)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(KrasaUI.borderStrong, lineWidth: 1))
                    .frame(width: 13, height: 13)
                    .overlay {
                        if isOn && isEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(KrasaUI.accentText)
                        }
                    }
                Text(title)
                    .font(KrasaUI.Font.control)
                    .foregroundStyle(isEnabled ? KrasaUI.textPrimary : KrasaUI.textDisabled)
                Text(detail)
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(isEnabled ? KrasaUI.textTertiary : KrasaUI.textDisabled)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                .fill(color.opacity(0.16)))
    }
}

private struct StageRow: View {
    let stage: AppModel.ExportStageState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(stage.isDone ? KrasaUI.ok
                                  : (stage.isRunning ? KrasaUI.accent : KrasaUI.borderActive),
                                  lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                if stage.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(KrasaUI.ok)
                }
            }
            Text(stage.title)
                .font(KrasaUI.Font.control)
                .foregroundStyle(stage.isRunning || stage.isDone
                                 ? KrasaUI.textPrimary : KrasaUI.textTertiary)
            if let detail = stage.detail {
                Text(detail)
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
            Spacer()
        }
    }
}

private struct CheckRow: View {
    let title: String
    let detail: String
    let isGood: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isGood ? KrasaUI.ok : KrasaUI.warn)
            Text(title)
                .font(KrasaUI.Font.controlStrong)
                .foregroundStyle(KrasaUI.textPrimary)
                .frame(width: 70, alignment: .leading)
            Text(detail)
                .font(KrasaUI.Font.status)
                .foregroundStyle(isGood ? KrasaUI.textSecondary : KrasaUI.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

private struct SheetButton: View {
    let title: String
    var isPrimary = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KrasaUI.Font.control)
                .foregroundStyle(isPrimary ? KrasaUI.accentText
                                 : (isEnabled ? KrasaUI.textSecondary : KrasaUI.textDisabled))
                .padding(.horizontal, 12)
                .frame(height: KrasaUI.Metric.controlHeight)
                .background(RoundedRectangle(cornerRadius: KrasaUI.Metric.controlRadius)
                    .fill(isPrimary ? KrasaUI.accent : KrasaUI.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: KrasaUI.Metric.controlRadius)
                    .strokeBorder(isPrimary ? .clear : KrasaUI.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
