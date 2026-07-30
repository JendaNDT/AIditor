//
//  TranscriptPanel.swift
//  Projekt AIditor — UI/Transcript
//
//  Panel přepisu řeči (fáze 18, modul 11). Dva stavy: průběh a editace.
//  Zdroj zadání: `design_handoff_aiditor_ui/README.md`, obrazovka 4.
//
//  ⚠️ Editace úseku je operace nad ASSETEM, ne nad klipem: `setTranscriptText`
//  přepíše text v přepisu zdroje, takže se změna projeví na VŠECH klipech
//  z toho souboru. Panel to musí říct nahlas — jinak to vypadá jako chyba,
//  když se titulek změní i „někde jinde".
//
//  ⚠️ Prázdný text úsek MAŽE (pravidlo modelu z fáze 11). Panel proto
//  u pole píše „prázdné smaže" a mazání nemá vlastní cestu do modelu.
//
//  Průběžné úseky jsou NÁHLED, ne data — jejich časy jsou při VAD chunkingu
//  relativní ke kusu nahrávky (viz `TranscriptionService.LiveSegment`).
//  Uložené úseky přijdou až z návratové hodnoty přepisu.
//

import SwiftUI
import TimelineModel

struct TranscriptPanel: View {
    @ObservedObject var model: AppModel
    /// ⚠️ **Controller se musí odebírat ZVLÁŠŤ.** `TimelineController` je
    /// vnořený `ObservableObject` uvnitř `AppModelu`, a view, které pozoruje
    /// jen model, jeho změny NEVIDÍ. Panel proto po nastavení
    /// `selectedSpeech` nepřekreslil vybraný úsek na kartu s polem —
    /// zvýraznění na ose se objevilo (to kreslí AppKit z odběru), ale panel
    /// zůstal stát. Známá past tohohle projektu; chytil ji snímek panelu.
    @ObservedObject var timeline: TimelineController
    /// A přepis taky — průběžné úseky přitékají do `TranscriptionService`.
    @ObservedObject var transcription: TranscriptionService
    @State private var search = ""
    @State private var onlyUnderPlayhead = false
    @State private var draft = ""
    @State private var cursor = 0
    /// Pro který výběr je `draft` naplněný. ⚠️ **Bez tohohle je v panelu mina:**
    /// výběr úseku umí nastavit i osa (klik do pásku řeči, F11/M3), a tehdy
    /// `select(_:)` v panelu neproběhne. Pole pak zůstalo PRÁZDNÉ — a protože
    /// prázdný text úsek MAŽE, ⏎ by ho zahodilo. Chytil to snímek panelu.
    @State private var loadedSelection: TimelineController.SpeechSelection?

    var body: some View {
        VStack(spacing: 0) {
            if transcription.statusText != nil {
                progressBody
            } else {
                editingBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIditorUI.surfacePanel)
        .onAppear { syncDraft() }
        .onChange(of: timeline.selectedSpeech) { _, _ in syncDraft() }
    }

    /// Natáhne text vybraného úseku do pole. Jediné místo, odkud se `draft`
    /// plní — ať přišel výběr z panelu, z osy nebo odjinud.
    private func syncDraft() {
        guard let selection = timeline.selectedSpeech,
              let text = timeline.project.asset(selection.assetID)?
                .transcript?[safe: selection.segmentIndex]?.text else {
            loadedSelection = nil
            draft = ""
            cursor = 0
            return
        }
        guard loadedSelection != selection else { return }
        loadedSelection = selection
        draft = text
        cursor = text.count
    }

    // MARK: - Průběh

    private var progressBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let fraction = transcription.progressFraction {
                    Text("\(Int((fraction * 100).rounded())) %")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AIditorUI.textPrimary)
                } else {
                    Text("začínám…")
                        .font(AIditorUI.Font.controlStrong)
                        .foregroundStyle(AIditorUI.textSecondary)
                }
                Text(progressDetail)
                    .font(AIditorUI.Font.status)
                    .foregroundStyle(AIditorUI.textSecondary)
                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(AIditorUI.surfaceControl)
                    RoundedRectangle(cornerRadius: 3).fill(AIditorUI.accent)
                        .frame(width: proxy.size.width
                               * (transcription.progressFraction ?? 0))
                }
            }
            .frame(height: 5)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(stages, id: \.title) { stage in
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .strokeBorder(stage.isDone ? AIditorUI.ok
                                              : (stage.isRunning ? AIditorUI.accent
                                                 : AIditorUI.borderActive), lineWidth: 1.5)
                                .frame(width: 13, height: 13)
                            if stage.isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(AIditorUI.ok)
                            }
                        }
                        Text(stage.title)
                            .font(AIditorUI.Font.control)
                            .foregroundStyle(stage.isDone || stage.isRunning
                                             ? AIditorUI.textPrimary : AIditorUI.textTertiary)
                        Spacer()
                    }
                }
            }

            // Úseky přitékají průběžně; poslední je vybledlý, protože se
            // ještě může změnit (dekodér ho může přepsat lepší variantou).
            if !transcription.liveSegments.isEmpty {
                Text("Přitéká")
                    .font(AIditorUI.Font.sectionTitle)
                    .foregroundStyle(AIditorUI.textTertiary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let live = transcription.liveSegments
                        ForEach(Array(live.enumerated()), id: \.element.id) { index, segment in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.clock(segment.position))
                                    .font(AIditorUI.Font.monoSmall)
                                    .foregroundStyle(AIditorUI.textTertiary)
                                Text(segment.text)
                                    .font(AIditorUI.Font.control)
                                    .foregroundStyle(AIditorUI.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .opacity(index == live.count - 1 ? 0.6 : 1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Přepis běží ve stroji — nic se nikam neposílá.")
                .font(AIditorUI.Font.chip)
                .foregroundStyle(AIditorUI.textTertiary)
        }
        .padding(14)
    }

    private var progressDetail: String {
        let count = transcription.liveSegments.count
        guard let total = transcription.totalSeconds else {
            return "\(count) úseků"
        }
        let done = (transcription.progressFraction ?? 0) * total
        return "\(Self.clock(done)) z \(Self.clock(total)) · \(count) úseků"
    }

    private struct StageRowState {
        let title: String
        let isDone: Bool
        let isRunning: Bool
    }

    private var stages: [StageRowState] {
        let stage = transcription.stage
        let order: [TranscriptionService.Stage] = [.model, .reading, .transcribing, .projecting]
        let current = order.firstIndex(of: stage) ?? 0
        return [
            StageRowState(title: "Model načten", isDone: current >= 1, isRunning: current == 0),
            StageRowState(title: "Rozpoznávám řeč", isDone: current >= 3,
                          isRunning: current == 1 || current == 2),
            StageRowState(title: "Promítnutí na T1", isDone: false, isRunning: current == 3),
        ]
    }

    // MARK: - Editace

    private var editingBody: some View {
        VStack(spacing: 0) {
            searchRow
            AIditorUI.border.frame(height: 1)
            if visibleSegments.isEmpty {
                emptyNote
            } else {
                segmentList
            }
            AIditorUI.border.frame(height: 1)
            footer
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(AIditorUI.textTertiary)
            TextField("Hledat v přepisu", text: $search)
                .textFieldStyle(.plain)
                .font(AIditorUI.Font.control)
                .foregroundStyle(AIditorUI.textPrimary)
            BarPill(title: "jen pod hlavou", isOn: onlyUnderPlayhead,
                    help: "Ukáže jen úsek, který právě leží pod přehrávací hlavou.") {
                onlyUnderPlayhead.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyNote: some View {
        VStack(spacing: 6) {
            Text(transcriptAsset == nil
                 ? "Vyber zvukový klip s řečí."
                 : (search.isEmpty ? "Tenhle zdroj ještě není přepsaný."
                    : "Nic, co by odpovídalo hledání."))
                .font(AIditorUI.Font.status)
                .foregroundStyle(AIditorUI.textTertiary)
                .multilineTextAlignment(.center)
            if let asset = transcriptAsset, asset.transcript == nil {
                Text("⌘5 spustí přepis")
                    .font(AIditorUI.Font.chip)
                    .foregroundStyle(AIditorUI.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var segmentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleSegments, id: \.index) { item in
                    if isSelected(item.index) {
                        selectedCard(item)
                    } else {
                        Button {
                            select(item.index)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.clock(item.segment.start.seconds))
                                    .font(AIditorUI.Font.monoSmall)
                                    .foregroundStyle(AIditorUI.textTertiary)
                                Text(item.segment.text)
                                    .font(AIditorUI.Font.control)
                                    .foregroundStyle(AIditorUI.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private func selectedCard(_ item: SegmentItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(Self.clock(item.segment.start.seconds)) → "
                     + Self.clock(item.segment.end.seconds))
                    .font(AIditorUI.Font.monoSmall)
                    .foregroundStyle(AIditorUI.accent)
                Spacer()
                Text("⏎ potvrdí · prázdné smaže")
                    .font(AIditorUI.Font.chip)
                    .foregroundStyle(AIditorUI.textTertiary)
            }

            TextEditorCompat(text: $draft, cursor: $cursor) {
                commit(item)
            }
            .frame(height: 44)

            HStack(spacing: 8) {
                PanelSmallButton(title: "Rozdělit v kurzoru") { split(item) }
                PanelSmallButton(title: "Smazat úsek") { delete(item) }
                Spacer()
            }

            Text("Platí pro všechny klipy ze zdroje — text je v přepisu souboru, "
                 + "ne na klipu.")
                .font(AIditorUI.Font.chip)
                .foregroundStyle(AIditorUI.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(AIditorUI.surfaceControl))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(AIditorUI.accent, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(allSegments.count) úseků")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AIditorUI.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.chipRadius)
                        .fill(AIditorUI.surfaceControlActive))
                Text(speechMinutesText)
                    .font(AIditorUI.Font.status)
                    .foregroundStyle(AIditorUI.textTertiary)
                Spacer()
            }
            HStack(spacing: 8) {
                PanelSmallButton(title: "Přepsat znovu") {
                    model.transcribeSelectedSpeech()
                }
                PanelSmallButton(title: "Uložit .srt…") { model.exportSubtitles() }
                Spacer()
            }
        }
        .padding(12)
    }

    private var speechMinutesText: String {
        Self.speechLength(of: allSegments.map(\.segment))
    }

    /// „12,3 min řeči" u dlouhé nahrávky, ale „4 s řeči" u krátké —
    /// „0,1 min" je technicky správně a přitom nečitelné.
    static func speechLength(of segments: [TranscriptSegment]) -> String {
        let seconds = segments.reduce(0.0) { $0 + ($1.end.seconds - $1.start.seconds) }
        guard seconds > 0 else { return "bez řeči" }
        if seconds < 60 { return "\(Int(seconds.rounded())) s řeči" }
        return String(format: "%.1f min řeči", seconds / 60)
            .replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Data

    struct SegmentItem {
        let index: Int
        let segment: TranscriptSegment
    }

    /// Zdroj, jehož přepis se edituje: pod hlavou, jinak z vybraného klipu,
    /// jinak první přepsaný. Kdyby se bral „nějaký", panel by po každém kliknutí
    /// ukazoval něco jiného.
    private var transcriptAsset: Asset? {
        let project = timeline.project
        if let ref = project.speechCueRef(at: timeline.playhead) {
            return project.asset(ref.assetID)
        }
        if let clipID = timeline.selection.first,
           let clip = project.timeline.clip(clipID),
           let asset = project.asset(clip.assetID), asset.transcript != nil {
            return asset
        }
        if let selected = timeline.selectedSpeech {
            return project.asset(selected.assetID)
        }
        return project.assets.first { $0.transcript != nil }
    }

    private var allSegments: [SegmentItem] {
        guard let transcript = transcriptAsset?.transcript else { return [] }
        return transcript.enumerated().map { SegmentItem(index: $0.offset, segment: $0.element) }
    }

    private var visibleSegments: [SegmentItem] {
        var items = allSegments
        if !search.isEmpty {
            items = items.filter {
                $0.segment.text.range(of: search, options: .caseInsensitive) != nil
            }
        }
        if onlyUnderPlayhead {
            let ref = timeline.project.speechCueRef(at: timeline.playhead)
            items = items.filter { $0.index == ref?.segmentIndex }
        }
        return items
    }

    private func isSelected(_ index: Int) -> Bool {
        timeline.selectedSpeech?.assetID == transcriptAsset?.id
            && timeline.selectedSpeech?.segmentIndex == index
    }

    // MARK: - Operace

    private func select(_ index: Int) {
        guard let asset = transcriptAsset else { return }
        timeline.selectedSpeech = TimelineController.SpeechSelection(assetID: asset.id,
                                                                    segmentIndex: index)
        syncDraft()
        // Hlavu na začátek úseku, ať je vidět, o čem se mluví.
        if let range = timeline.project.speechCueRanges(assetID: asset.id,
                                                        segmentIndex: index).first {
            timeline.setPlayheadFromUser(range.lowerBound)
        }
    }

    private func commit(_ item: SegmentItem) {
        guard let asset = transcriptAsset else { return }
        // Pojistka proti smazání nedopatřením: prázdný text úsek maže, ale jen
        // když ho uživatel opravdu vyprázdnil — ne když se pole nestihlo
        // naplnit (viz `loadedSelection`).
        let selection = TimelineController.SpeechSelection(assetID: asset.id,
                                                          segmentIndex: item.index)
        guard loadedSelection == selection else {
            syncDraft()
            return
        }
        model.setSpeechText(assetID: asset.id, segmentIndex: item.index, text: draft)
    }

    private func delete(_ item: SegmentItem) {
        guard let asset = transcriptAsset else { return }
        // Mazání jde TOUTÉŽ cestou jako oprava textu — prázdný text úsek maže
        // (pravidlo modelu). Dvě cesty by znamenaly dvě místa, kde se to dá
        // rozbít.
        model.setSpeechText(assetID: asset.id, segmentIndex: item.index, text: "")
        timeline.selectedSpeech = nil
    }

    private func split(_ item: SegmentItem) {
        guard let asset = transcriptAsset else { return }
        model.splitSpeechSegment(assetID: asset.id, segmentIndex: item.index,
                                 atCharacter: cursor)
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Editovatelné pole s kurzorem

/// `TextEditor` neumí říct, kde je kurzor, a modul ho potřebuje pro
/// „Rozdělit v kurzoru". Vlastní `NSTextView` v `NSViewRepresentable` ho
/// vydá — a zároveň umí ⏎ jako potvrzení místo nového řádku.
struct TextEditorCompat: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursor: Int
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 11)
        view.textColor = .labelColor
        view.drawsBackground = false
        view.isRichText = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: TextEditorCompat

        init(_ parent: TextEditorCompat) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.cursor = view.selectedRange().location
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.cursor = view.selectedRange().location
        }

        /// ⏎ potvrzuje, ne odřádkovává — titulek je jedna věta a nový řádek
        /// by se v něm zobrazil jako mezera, takže by uživatel nevěděl, co
        /// vlastně napsal.
        func textView(_ textView: NSTextView,
                      doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

// MARK: - Drobné tlačítko panelu

struct PanelSmallButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AIditorUI.Font.control)
                .foregroundStyle(AIditorUI.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.chipRadius)
                    .fill(AIditorUI.surfaceRow))
                .overlay(RoundedRectangle(cornerRadius: AIditorUI.Metric.chipRadius)
                    .strokeBorder(AIditorUI.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bezpečný index

extension Array {
    /// Sáhnutí, které nespadne na prázdném přepisu. Panel čte podle indexu
    /// z výběru, a ten může být o krok pozadu (úsek se právě smazal).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
