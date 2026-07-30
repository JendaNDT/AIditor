//
//  EmptyState.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 12. Prázdný start: okno bez materiálu.
//  Zdroj zadání: `design_handoff_krasa_ui/README.md`, obrazovka 2 (varianta 3a).
//
//  ⚠️ Prázdný stav NENÍ jiná obrazovka, jen jiný obsah téhož rámu. Toolbar,
//  rail, lišta osy, osa i stavový řádek zůstávají na svých místech a mění se
//  jen to, co v nich je — jinak by se po importu přestavovala celá hierarchie
//  a `PlayerView` by se přetvořil (pravidlo „jeden strom, podmíněná
//  sourozenci" z modulu 1).
//
//  ⚠️ **Cíl přetažení je AppKit `NSView`, ne SwiftUI `.onDrop`, a obsah zóny
//  visí UVNITŘ něj.** Dva důvody:
//    · AppKit hledá cíl přetažení hit testem od nejhlubšího pohledu pod
//      kurzorem NAHORU po hierarchii. Kdyby obsah zóny ležel v ZStacku NAD
//      registrovaným pohledem, hit test by skončil na hostitelském pohledu
//      SwiftUI, který registrovaný není — a nad textem a tlačítky by drop
//      přestal fungovat. Vnořený `NSHostingView` je potomek terče, takže
//      hit test skončí vždy uvnitř něj. Hlídá to `--empty-start-check`.
//    · `--empty-start-check` tím jde SKUTEČNOU cestou protokolu
//      (`registerForDraggedTypes` → pasteboard → `draggingEntered` →
//      `performDragOperation`), ne zkratkou do vnitřní funkce modelu.
//      SwiftUI drop se bez skutečné myši nasimulovat nedá.
//

import AppKit
import SwiftUI
import TimelineModel

// MARK: - Zóna přetažení

/// Zóna přetažení na místě přehrávače. Přijímá soubory na CELÉ ploše náhledu,
/// ne jen v přerušovaném rámečku — ten je návod, ne terč.
struct EmptyStartDropZone: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> FileDropView {
        let view = FileDropView()
        view.onDropURLs = { urls in
            Task { await model.importDropped(urls: urls) }
        }
        view.setContent(DropZoneContent(
            isTargeted: false,
            chooseFiles: { Task { await model.openFiles(directories: false) } },
            chooseFolder: { Task { await model.openFiles(directories: true) } }))
        model.attachDropZone(view)
        return view
    }

    func updateNSView(_ nsView: FileDropView, context: Context) {}
}

/// Terč přetažení souborů z Finderu.
///
/// <https://developer.apple.com/documentation/appkit/nsview/registerfordraggedtypes(_:)>
/// <https://developer.apple.com/documentation/appkit/nspasteboard/readobjects(forclasses:options:)>
/// <https://developer.apple.com/documentation/swiftui/nshostingview>
final class FileDropView: NSView {

    var onDropURLs: (([URL]) -> Void)?

    private var hosting: NSHostingView<DropZoneContent>?
    private var content: DropZoneContent?

    /// Kurzor s platnými soubory je nad zónou — rámeček se rozsvítí.
    private var isTargeted = false {
        didSet {
            guard isTargeted != oldValue, var content else { return }
            content.isTargeted = isTargeted
            setContent(content)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // ⚠️ Bez registrace typu nikdo metody `NSDraggingDestination` nezavolá
        // a nic to nenahlásí — táž past, kterou popisuje osa u dropu z knihovny.
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    func setContent(_ newContent: DropZoneContent) {
        content = newContent
        if let hosting {
            hosting.rootView = newContent
            return
        }
        let view = NSHostingView(rootView: newContent)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosting = view
    }

    // MARK: Protokol přetažení

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let urls = Self.fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = !Self.fileURLs(from: sender).isEmpty
        isTargeted = accepts
        return accepts ? .copy : []
    }

    /// Soubory z pasteboardu. `urlReadingFileURLsOnly` odfiltruje odkazy
    /// z prohlížeče — ty by se do importu neměly dostat vůbec.
    static func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: options)
        return (objects as? [URL]) ?? []
    }
}

/// Obsah zóny: dlaždice, nadpis, odstavec, dvě tlačítka a řádek formátů.
struct DropZoneContent: View {
    var isTargeted: Bool
    let chooseFiles: () -> Void
    let chooseFolder: () -> Void

    var body: some View {
        ZStack {
            KrasaUI.surfaceViewer
            box
                .frame(maxWidth: 680)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var box: some View {
        VStack(spacing: 14) {
            tiles
            Text("Přetáhni sem záběry, fotky nebo hudbu")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(KrasaUI.textPrimary)
            Text("Krása si u každého souboru změří skutečné časování (VFR poznáš "
                 + "v knihovně) a na pozadí připraví proxy. Osa se plní ručně — "
                 + "nic se nepoloží samo.")
                .font(.system(size: 12))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(KrasaUI.textSecondary)
                .frame(maxWidth: 460)
            HStack(spacing: 8) {
                zoneButton("Vybrat soubory…", isPrimary: true, action: chooseFiles)
                zoneButton("Vybrat složku…", isPrimary: false, action: chooseFolder)
            }
            .padding(.top, 2)
            Text("MOV, MP4 · HEIC, JPEG, PNG · M4A, MP3, WAV")
                .font(.system(size: 10))
                .foregroundStyle(KrasaUI.textTertiary)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? KrasaUI.accent.opacity(0.06) : Color.white.opacity(0.014))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isTargeted ? KrasaUI.accent : Color(krasaHex: 0x33373E),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    /// Tři dlaždice: dvě obrazové a jedna zvuková. Jsou to ATRAPY — kreslí se
    /// gradientem, ne miniaturou: na prázdném startu žádný materiál není,
    /// odkud by se snímek vzal.
    private var tiles: some View {
        HStack(alignment: .bottom, spacing: 6) {
            tile(width: 44, height: 30,
                 colors: [Color(krasaHex: 0x3A4250), Color(krasaHex: 0x1A1D22)],
                 border: Color(krasaHex: 0x33373E))
            tile(width: 56, height: 38,
                 colors: [Color(krasaHex: 0x465060), Color(krasaHex: 0x1C2129)],
                 border: KrasaUI.borderActive)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(krasaHex: 0x1E2C26))
                waveHint
            }
            .frame(width: 44, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(krasaHex: 0x33373E), lineWidth: 1))
        }
    }

    private func tile(width: CGFloat, height: CGFloat,
                      colors: [Color], border: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: width, height: height)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
    }

    private var waveHint: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { _ in
                Color(krasaHex: 0x78DCAA, opacity: 0.55).frame(width: 1)
            }
        }
        .frame(height: 10)
    }

    private func zoneButton(_ title: String, isPrimary: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                .foregroundStyle(isPrimary ? KrasaUI.textPrimary : Color(krasaHex: 0xC9CCD1))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? KrasaUI.surfaceControlActive : KrasaUI.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPrimary ? KrasaUI.borderActive : KrasaUI.borderStrong,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Poslední projekty

/// Pás 330 bodů vpravo místo knihovny médií. Táž šířka i pozadí — knihovna
/// se do něj po importu jen vymění.
struct RecentProjectsPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            header
            KrasaUI.border.frame(height: 1)
            rows
            KrasaUI.border.frame(height: 1)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(KrasaUI.surfaceRail)
    }

    private var header: some View {
        HStack {
            Text("Poslední projekty")
                .font(KrasaUI.Font.controlStrong.weight(.semibold))
                .foregroundStyle(KrasaUI.textPrimary)
            Spacer()
            Button { model.openProjectViaPanel() } label: {
                Text("Otevřít…")
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Otevřít projekt ze souboru (⌘O)")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var rows: some View {
        ScrollView {
            // ⚠️ `maxWidth: .infinity` na obsahu, ne jen na `ScrollView`u.
            // Prázdný seznam nemá co roztáhnout, takže se scroll view smrskl
            // na nulovou šířku a text v `overlay` se vysázel PO PÍSMENKÁCH
            // pod sebe (chytil snímek okna — čísla to vidět nemohla).
            VStack(spacing: 6) {
                ForEach(store.recentProjects) { recent in
                    RecentProjectRow(recent: recent) { model.openRecent(recent) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if store.recentProjects.isEmpty {
                Text("Zatím žádný uložený projekt.\nZaložíš ho materiálem a ⌘S.")
                    .font(KrasaUI.Font.status)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KrasaUI.textTertiary)
            }
        }
    }

    /// Patička přiznává, co appka na disku drží a co ještě NEmá — nestažený
    /// model přepisu se má vědět hned, ne až při prvním spuštění přepisu.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                dot(KrasaUI.ok)
                Text("Proxy cache " + ByteCountFormatter.string(
                    fromByteCount: model.proxies.cacheSizeBytes, countStyle: .file))
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textTertiary)
                Spacer(minLength: 4)
                Button { model.changeProxyDirectory() } label: {
                    Text("Spravovat…")
                        .font(KrasaUI.Font.status)
                        .foregroundStyle(KrasaUI.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Vybrat složku pro proxy — třeba na externím disku.")
            }
            HStack(spacing: 8) {
                dot(model.transcription.modelSizeBytes == nil
                    ? KrasaUI.textDisabled : KrasaUI.ok)
                Text(whisperText)
                    .font(KrasaUI.Font.status)
                    .foregroundStyle(KrasaUI.textTertiary)
                Spacer(minLength: 4)
                if model.transcription.modelSizeBytes == nil {
                    Text("1,5 GB při prvním použití")
                        .font(KrasaUI.Font.status)
                        .foregroundStyle(KrasaUI.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var whisperText: String {
        guard let size = model.transcription.modelSizeBytes else {
            return "Model přepisu nestažený"
        }
        return "Model přepisu "
            + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

/// Jeden řádek seznamu. Offline projekt se NESKRÝVÁ a nemlčí: jméno zšedne,
/// meta řádek oranžově řekne proč. Nabídnout ho k otevření a pak selhat by
/// bylo horší; zamlčet ho taky (uživatel by hledal, kam se mu projekt poděl).
private struct RecentProjectRow: View {
    let recent: RecentProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                thumb
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(recent.isOffline
                                         ? KrasaUI.textSecondary : KrasaUI.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(recent.isOffline ? "disk není připojený" : meta)
                        .font(.system(size: 9))
                        .foregroundStyle(recent.isOffline
                                         ? KrasaUI.warn : KrasaUI.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(recent.isOffline ? Color.clear : KrasaUI.surfaceControlActive))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(recent.isOffline ? Color.clear : Color(krasaHex: 0x33373E),
                              lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(recent.isOffline)
        .help(recent.isOffline
              ? "Soubor projektu není dostupný: \(recent.path)"
              : recent.path)
    }

    /// ⚠️ Miniatura je NEUTRÁLNÍ dlaždice, ne snímek z filmu. Skutečný by
    /// znamenal otevřít každý projekt v seznamu a rozbalit bookmark jeho
    /// prvního assetu — a projekt na odpojeném disku by ho stejně neměl.
    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(recent.isOffline
                      ? LinearGradient(colors: [Color(krasaHex: 0x1C1F24),
                                                Color(krasaHex: 0x1C1F24)],
                                       startPoint: .top, endPoint: .bottom)
                      : LinearGradient(colors: [Color(krasaHex: 0x463F38),
                                                Color(krasaHex: 0x1A1D22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            if recent.isOffline {
                Text("offline")
                    .font(.system(size: 8))
                    .foregroundStyle(KrasaUI.textDisabled)
            }
        }
        .frame(width: 56, height: 32)
    }

    private var meta: String {
        var parts = [Self.dateText(recent.modifiedAt)]
        parts.append(recent.shotCount == 1 ? "1 záběr" : "\(recent.shotCount) záběrů")
        parts.append(Self.durationText(recent.durationSeconds))
        return parts.joined(separator: " · ")
    }

    /// „včera 21:04" u čerstvého, datum u staršího. Relativní čas u projektu
    /// z loňska („před 8 měsíci") by se hledal v hlavě dýl než datum.
    static func dateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "dnes " + time.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "včera " + time.string(from: date)
        }
        return day.string(from: date)
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. M. yyyy"
        return formatter
    }()
}

// MARK: - Pruh obnovy zálohy

/// Nabídka obnovy neuložené práce. **Pruh, ne dialog** (zadání, obrazovka 2):
/// dialog při startu nutí rozhodnout dřív, než je vidět o čem, a „Zahodit"
/// je nevratné. Pruh jde ignorovat a záloha zůstane ležet.
struct RecoveryBar: View {
    @ObservedObject var model: AppModel
    let offer: AppModel.RecoveryOffer

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(KrasaUI.warn).frame(width: 7, height: 7)
            (Text("Aplikace minule neskončila uložením. Záloha neuloženého projektu je z ")
                .foregroundStyle(Color(krasaHex: 0xFFD7A0))
             + Text(Self.stamp.string(from: offer.modifiedAt))
                .foregroundStyle(.white)
             + Text(" · " + clipText).foregroundStyle(Color(krasaHex: 0xFFD7A0)))
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Task { await model.restoreRecoveryOffer() }
            } label: {
                Text("Obnovit zálohu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(krasaHex: 0xFFD7A0))
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(KrasaUI.warn.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(KrasaUI.warn.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.dismissRecoveryOffer() }
            } label: {
                Text("Zahodit")
                    .font(.system(size: 11))
                    .foregroundStyle(KrasaUI.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(KrasaUI.surfaceControl))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(KrasaUI.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Zálohu smaže a naskenuje zapamatované složky s klipy.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(KrasaUI.warn.opacity(0.10))
        .overlay(alignment: .bottom) {
            KrasaUI.warn.opacity(0.30).frame(height: 1)
        }
    }

    /// Kolik klipů v záloze je: údaj, který dialog neříkal. „Záloha z 23:41"
    /// se dá rozhodnout snáz, když je vidět, že v ní je čtrnáct klipů.
    private var clipText: String {
        switch offer.clipCount {
        case 0: return "prázdná osa"
        case 1: return "1 klip"
        case 2...4: return "\(offer.clipCount) klipy"
        default: return "\(offer.clipCount) klipů"
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. M. yyyy H:mm"
        return formatter
    }()
}
