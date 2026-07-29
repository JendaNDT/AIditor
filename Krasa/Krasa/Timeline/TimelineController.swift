//
//  TimelineController.swift
//  Projekt Krása
//
//  Vlastník veškerého stavu časové osy. Návrh: `FAZE_2_VIEW.md`, sekce 2.1.
//
//  ⚠️ GEOMETRIE MÁ JEDINÉ ÚLOŽIŠTĚ, a je jím `interaction.geometry`.
//  `TimelineGeometry` je struktura, tedy hodnota — kdyby si ji view drželo
//  taky, vznikly by dvě kopie a při zoomu by se rozešly: hit testing by
//  počítal s jedním měřítkem a přichytávání během tažení s druhým. Taková
//  chyba nespadne. Jen se klip trefuje vedle a hledá se týdny.
//
//  Proto se geometrie vystavuje jen průchodem a view si ji NIKDY neuloží
//  do vlastnosti — vždycky si o ni řekne v okamžiku použití.
//
//  Do controlleru nepatří střihové operace, meze tažení ani přichytávání.
//  To všechno umí `TimelineModel` a je to otestované (351 testů balíčku).
//

import AudioEngine
import Foundation
import TimelineModel

/// Které informační vrstvy osa kreslí (fáze 18, modul 3).
///
/// ⚠️ Vypnutá vrstva znamená, že se **nepočítá**. Kdyby se jen skrývala,
/// přepínač by nic neušetřil — a jediný důvod, proč existuje, je ubrat
/// práci na dvacetiminutové ose. Rozhodnutí patří do `rebuildClipInfo`
/// a `applyWaveform`, ne do neprůhlednosti vrstvy.
struct TimelineLayers: Equatable {
    /// Miniatury na klipech. Přijdou v modulu 5 — přepínač už existuje,
    /// protože je to POJISTKA pro ně: kdyby srazily scroll benchmark, musí
    /// jít vypnout, a vypínač nemá vznikat až ve chvíli, kdy je zle.
    var thumbnails = true
    var waveforms = true
    var beats = true
    var qualityMarks = true
}

@MainActor
final class TimelineController: ObservableObject {

    /// Dokument.
    @Published var project: Project

    /// Historie. Snímkuje celý projekt, ne jen timeline.
    @Published var undo = UndoStack()

    /// Stavový automat tažení — a v něm jediná kopie geometrie.
    @Published var interaction: TimelineInteraction

    /// Přehrávací hlava. V modelu není a nemá tam být: je to stav UI.
    @Published var playhead: Frames = .zero

    /// Volá se, když hlavu posune UŽIVATEL (klik nebo tažení v pravítku).
    /// `AppModel` sem věší překlad na seek přehrávače. Aktualizace hlavy
    /// z přehrávače tudy NEchodí — jinak by vznikla smyčka seek → hlava → seek.
    var onUserSeek: ((Frames) -> Void)?

    /// Transport z klávesnice (fáze 17): J / K / L. Osa přehrávač nezná —
    /// jen řekne, co uživatel stiskl, a `AppModel` to přeloží na rychlost.
    /// Vlastní enum schválně: `TimelineController` je bez AVFoundation.
    enum ShuttleKey { case backward, pause, forward }
    var onShuttle: ((ShuttleKey) -> Void)?

    /// ⇧Z — celá osa do okna (F18/M3). Zoom umí spočítat jen `TimelinePane`:
    /// šířku výřezu zná scroll view, ne controller.
    var onFitRequest: (() -> Void)?

    /// Hlavu právě táhne uživatel. Po tu dobu se ignorují aktualizace
    /// z přehrávače — obousměrná vazba se nikdy nesmí zapnout naráz
    /// (`FAZE_2_VIEW.md`, sekce 5). Schválně ne `@Published`: je to příznak
    /// pro logiku, ne stav ke kreslení.
    var isUserScrubbing = false

    /// Výběr. Totéž — stav UI, ne dokumentu.
    @Published var selection: Set<ClipID> = []

    // MARK: - Rozsah exportu (fáze 17, modul 3)

    /// In a out bod na ose. Stav UI jako hlava — do projektového souboru
    /// nepatří a undo se jich netýká.
    @Published var inPoint: Frames?
    @Published var outPoint: Frames?

    /// Co se bude exportovat. Bez bodů (nebo s obrácenými) celý projekt —
    /// export nikdy nesmí tiše vyrobit prázdný soubor.
    var exportRange: Range<Frames> { project.exportRange(inPoint: inPoint, outPoint: outPoint) }

    /// Je to opravdu výřez, nebo celý film?
    var hasExportRange: Bool {
        let range = exportRange
        return range.lowerBound.count > 0 || range.upperBound < project.duration
    }

    func setInPoint(_ frame: Frames?) {
        inPoint = frame
        // Obrácené body se nedrží — druhý ustoupí, ať je stav vždycky
        // smysluplný a nemusí se to dohánět až v exportu.
        if let inPoint, let out = outPoint, out <= inPoint { outPoint = nil }
    }

    func setOutPoint(_ frame: Frames?) {
        outPoint = frame
        if let outPoint, let inp = inPoint, outPoint <= inp { inPoint = nil }
    }

    func clearExportRange() {
        inPoint = nil
        outPoint = nil
    }

    /// Uspořádat klipy stopy podle času natočení (fáze 17, modul 3).
    func arrangeChronologically(trackID: TrackID) {
        var updated = project
        do {
            let undated = try updated.arrangeChronologically(trackID: trackID)
            guard updated != project else {
                onStatus?("Klipy už jsou v chronologickém pořadí.")
                return
            }
            undo.record(project)
            project = updated
            onStatus?(undated > 0
                      ? "Uspořádáno chronologicky; \(undated) klipů bez času natočení je na konci."
                      : "Uspořádáno chronologicky podle času natočení.")
        } catch {
            onStatus?("Uspořádat nešlo: na sousední stopě leží něco, co by se překrylo.")
        }
    }

    /// Vybraný titulek na T1 (fáze 11, modul 3). Výběry se navzájem
    /// vylučují — inspektor pod přehrávačem ukazuje právě jednu věc.
    @Published var selectedTitle: TitleClipID?

    /// Vybraný úsek titulků z řeči (adresa v přepisu assetu). Text se
    /// v inspektoru čte vždy čerstvý z projektu — adresa po editaci platí,
    /// dokud úsek existuje.
    @Published var selectedSpeech: SpeechSelection?

    struct SpeechSelection: Hashable {
        let assetID: AssetID
        let segmentIndex: Int
    }

    /// Mezipaměť vlnových průběhů (krok 10). Mezipaměť, ne dokument —
    /// špičky i dlaždice se dají kdykoli zahodit a spočítat znovu.
    let waveforms = WaveformStore()

    init(project: Project = .empty(), geometry: TimelineGeometry = TimelineGeometry()) {
        self.project = project
        self.interaction = TimelineInteraction(geometry: geometry)
    }

    /// Jediné úložiště, žádná synchronizace.
    var geometry: TimelineGeometry {
        get { interaction.geometry }
        set { interaction.geometry = newValue }
    }

    // MARK: - Vrstvy osy a citlivost analýz (fáze 18, modul 3)

    /// Co se na ose kreslí. Vypnutá vrstva se **nepočítá**, ne jen neukazuje —
    /// smysl přepínače je ušetřit práci při scrollu, ne ji udělat a schovat.
    /// Stav sezení: do `Project` (a tedy do souboru) nepatří.
    @Published var layers = TimelineLayers()

    /// Přichytávání zapnuté globálně (F18/M3). Shift ho vypne pro JEDNO
    /// tažení — dosud existovala jen ta shiftová cesta, takže kdo chtěl
    /// hodinu stříhat bez magnetu, musel hodinu držet shift.
    @Published var snappingEnabled = true

    /// Citlivost klasifikace ostrosti a hluchých míst, 0–1 (fáze 15 měla
    /// model, UI ne). Přepočítává ZNAČKY z hotových vzorků — **nové
    /// vzorkování nespouští**, takže posuvník reaguje okamžitě.
    ///
    /// Přežívá restart (`UserDefaults`), ale ne projekt: je to nastavení
    /// oka, ne vlastnost filmu.
    @Published var qualitySensitivity: Double = TimelineController.storedSensitivity() {
        didSet {
            guard qualitySensitivity != oldValue else { return }
            UserDefaults.standard.set(qualitySensitivity, forKey: Self.sensitivityKey)
        }
    }

    private static let sensitivityKey = "cz.projektkrasa.qualitySensitivity"

    private static func storedSensitivity() -> Double {
        guard UserDefaults.standard.object(forKey: sensitivityKey) != nil else { return 0.5 }
        let value = UserDefaults.standard.double(forKey: sensitivityKey)
        return min(max(value, 0), 1)
    }

    // MARK: - Přehrávací hlava (krok 6)

    /// Posun hlavy uživatelem. Ořeže na rozsah projektu a ohlásí seek.
    func setPlayheadFromUser(_ frame: Frames) {
        let clamped = Frames(min(max(0, frame.count), project.duration.count))
        if playhead != clamped { playhead = clamped }
        onUserSeek?(clamped)
    }

    /// Posun hlavy podle času přehrávače. Během tažení uživatelem se zahazuje.
    func setPlayheadFromPlayback(_ frame: Frames) {
        guard !isUserScrubbing else { return }
        let clamped = Frames(min(max(0, frame.count), project.duration.count))
        if playhead != clamped { playhead = clamped }
    }

    // MARK: - Střihové operace z menu a zkratek (krok 9)

    /// Rozřízne klip v hlavě. Svázané dvojče řeže model sám (a přepojuje
    /// vazby) — tady se jen hlídá, že řez vede vnitřkem klipu, a píše undo.
    func splitAtPlayhead(_ clipID: ClipID) {
        guard let clip = project.timeline.clip(clipID),
              clip.timelineStart < playhead, playhead < clip.timelineEnd else { return }
        var updated = project
        guard (try? updated.split(clipID: clipID, at: playhead)) != nil else { return }
        undo.record(project)
        project = updated
    }

    /// Smaže klipy i jejich svázaná dvojčata. Jeden undo krok pro celou dávku.
    func deleteClips(_ ids: Set<ClipID>) {
        var toRemove = ids
        for id in ids {
            for partner in project.linkedPartners(of: id) { toRemove.insert(partner.id) }
        }
        let existing = toRemove.filter { project.timeline.clip($0) != nil }
        guard !existing.isEmpty else { return }

        var updated = project
        for id in existing { try? updated.remove(clipID: id) }
        undo.record(project)
        project = updated
        selection.subtract(toRemove)
    }

    /// Smaže s dosunutím. Dvojčata a dosah přes stopy řeší model
    /// (`rippleRemove` — hudební podkres na A2 se neposouvá).
    func rippleDelete(_ clipID: ClipID) {
        var updated = project
        guard (try? updated.rippleRemove(clipID: clipID)) != nil else { return }
        undo.record(project)
        project = updated
        selection.remove(clipID)
    }

    // MARK: - Editor rychlostní křivky (fáze 3, modul 3)

    /// Přidá uzel na křivku klipu (dvojklik v editoru). Vrací index nového
    /// uzlu, `nil` když operace neprošla — třeba uzel moc blízko souseda.
    @discardableResult
    func addRampNode(clipID: ClipID, atOutputFrame frame: Double) -> Int? {
        var updated = project
        guard let index = try? updated.addRampNode(clipID: clipID, atOutputFrame: frame)
        else { return nil }
        undo.record(project)
        project = updated
        return index
    }

    func removeRampNode(clipID: ClipID, nodeIndex: Int) {
        var updated = project
        guard (try? updated.removeRampNode(clipID: clipID, nodeIndex: nodeIndex)) != nil
        else { return }
        undo.record(project)
        project = updated
    }

    /// Tažení uzlu editoru — stejný vzorec jako trim: mezistavy jsou legální,
    /// zapisují se průběžně a `beginInteraction`/`endInteraction` z nich
    /// složí jeden undo krok.
    func rampDragBegan() { undo.beginInteraction(project) }

    func rampDragChanged(_ ramp: SpeedRamp, clipID: ClipID) {
        var updated = project
        guard (try? updated.setSpeedRamp(clipID: clipID, ramp: ramp)) != nil else { return }
        project = updated
    }

    func rampDragEnded() { undo.endInteraction(project) }

    func rampDragCancelled() {
        if let base = undo.cancelInteraction() { project = base }
    }

    /// Preset: klasické zpomalení 1× → 0,25× → 1× přes klip. Vznikl jako
    /// testovací rampa modulu 2 a zůstává — nakreslit tenhle tvar ručně
    /// znamená tři uzly a tři tahy, tohle je jeden klik. Když už klip
    /// křivku má, akce ji smaže. Dvojče řeší model (`setSpeedRamp` je
    /// link-aware), undo jeden krok.
    /// Rychlý preset zpomalení (fáze 18/M7): `nil` rampu zruší.
    ///
    /// Rozpětí se kotví tak, aby VÝSTUP zůstal dlouhý jako klip. Průměrná
    /// rychlost easeInOut rampy je `(1 + slow) / 2` — táž symetrie, ze které
    /// vychází referenční hodnota Spiku 0 (1× → 0,25× → 1× přes 5 s spotřebuje
    /// 3,125 s). Pro 0,25× vyjde 0,625, tedy přesně číslo, se kterým počítal
    /// `toggleClassicRamp` před zobecněním.
    func setClassicRamp(_ clipID: ClipID, slowSpeed: Double?) {
        guard let clip = project.timeline.clip(clipID) else { return }
        var updated = project
        if let slowSpeed {
            let consumption = project.sourceConsumption(of: clip)
            let span = SourceTime(seconds: consumption.seconds * (1 + slowSpeed) / 2)
            let ramp = SpeedRamp.classicSlowMotion(from: clip.sourceStart,
                                                   spanning: span,
                                                   slowSpeed: slowSpeed)
            guard (try? updated.setSpeedRamp(clipID: clipID, ramp: ramp)) != nil else { return }
        } else {
            guard (try? updated.setSpeedRamp(clipID: clipID, ramp: nil)) != nil else { return }
        }
        undo.record(project)
        project = updated
    }

    func toggleClassicRamp(_ clipID: ClipID) {
        guard let clip = project.timeline.clip(clipID) else { return }
        var updated = project
        if clip.speedRamp != nil {
            guard (try? updated.setSpeedRamp(clipID: clipID, ramp: nil)) != nil else { return }
        } else {
            // Křivka natažená tak, aby výstup zůstal dlouhý jako klip:
            // easeInOut ramp na 0,25× má průměrnou rychlost 0,625, takže se
            // kotví přes 62,5 % dosavadní spotřeby. Klip se neprodlužuje,
            // sousedi zůstávají na místě — jen konec záběru zůstane nevyužitý.
            let consumption = project.sourceConsumption(of: clip)
            let span = SourceTime(seconds: consumption.seconds * 0.625)
            let ramp = SpeedRamp.classicSlowMotion(from: clip.sourceStart,
                                                   spanning: span,
                                                   slowSpeed: 0.25)
            guard (try? updated.setSpeedRamp(clipID: clipID, ramp: ramp)) != nil else { return }
        }
        undo.record(project)
        project = updated
    }

    // MARK: - Přechody (fáze 10, modul 3)

    /// Výchozí délka nového přechodu: 1 sekunda základny, zaražená o to,
    /// co střih unese. Jemné doladění je na tažení okraje lichoběžníku.
    func addTransition(_ kind: TransitionKind,
                       betweenLeft leftID: ClipID, andRight rightID: ClipID) {
        let maxD = project.maxTransitionDuration(kind: kind,
                                                 betweenLeft: leftID, andRight: rightID)
        guard maxD.count >= 1 else { return }
        let duration = Frames(min(project.timeline.frameRate, maxD.count))
        var updated = project
        guard (try? updated.setTransition(kind, duration: duration,
                                          betweenLeft: leftID, andRight: rightID)) != nil
        else { return }
        undo.record(project)
        project = updated
    }

    func removeTransition(_ id: TransitionID) {
        var updated = project
        guard (try? updated.removeTransition(id: id)) != nil else { return }
        undo.record(project)
        project = updated
        if selectedTransition == id { selectedTransition = nil }
    }

    /// Puštění tažení okraje: mezistavy se během tažení do modelu nepsaly
    /// (duch), takže jeden `record()` před zápisem — vzorec `move`.
    func resizeTransition(_ id: TransitionID, to duration: Frames) {
        guard let current = project.transition(id: id),
              current.duration != duration else { return }
        var updated = project
        guard (try? updated.setTransitionDuration(id: id, to: duration)) != nil else { return }
        undo.record(project)
        project = updated
    }

    // MARK: - Titulkové klipy (fáze 11, modul 3)

    /// Přidá titulek z kontextového menu: výchozí délka zaražená o mezeru
    /// do dalšího titulku. Nový titulek se rovnou vybere — inspektor se
    /// otevře na něm a uživatel hned píše.
    func addTitle(template: TitleTemplate, at frame: Frames, onTrack trackID: TrackID) {
        let room = project.maxNewTitleDuration(at: frame, onTrack: trackID)
        guard room.count >= 1 else { return }
        let duration = Frames(min(project.defaultTitleDuration.count, room.count))
        var updated = project
        guard let title = try? updated.makeTitle(text: defaultText(for: template),
                                                 template: template,
                                                 at: frame, duration: duration),
              (try? updated.addTitle(title, onTrack: trackID)) != nil else { return }
        undo.record(project)
        project = updated
        selectTitle(title.id)
    }

    /// Výchozí text nového titulku — něco k přepsání, ne prázdno, které
    /// by na ose nebylo vidět.
    private func defaultText(for template: TitleTemplate) -> String {
        switch template {
        case .plain: return "Text"
        case .names: return "Jména novomanželů"
        case .dateAndPlace: return "Datum a místo"
        case .chapter: return "Kapitola"
        case .thanks: return "Poděkování"
        }
    }

    func deleteTitle(_ id: TitleClipID) {
        var updated = project
        guard (try? updated.removeTitle(id: id)) != nil else { return }
        undo.record(project)
        project = updated
        if selectedTitle == id { selectedTitle = nil }
    }

    /// Puštění tažení titulku — mezistavy se do modelu nepsaly (duch),
    /// takže jeden `record()` před zápisem, vzorec `move`/`resizeTransition`.
    func commitTitleMove(_ id: TitleClipID, to start: Frames) {
        guard let title = project.timeline.titleClip(id),
              title.timelineStart != start else { return }
        var updated = project
        guard (try? updated.moveTitle(id: id, start: start)) != nil else { return }
        undo.record(project)
        project = updated
    }

    func commitTitleTrim(_ id: TitleClipID, start: Frames, duration: Frames) {
        guard let title = project.timeline.titleClip(id),
              title.timelineStart != start || title.duration != duration else { return }
        var updated = project
        if title.timelineStart != start {
            guard (try? updated.trimTitleStart(id: id, to: start)) != nil else { return }
        } else {
            guard (try? updated.trimTitleEnd(id: id, to: start + duration)) != nil else { return }
        }
        undo.record(project)
        project = updated
    }

    // MARK: Inspektor titulku

    /// Psaní textu — vzorec posuvníku hlasitosti: mezistavy jsou legální,
    /// zapisují se průběžně (uživatel vidí titulek v náhledu při psaní)
    /// a begin/end kolem fokusu z nich složí jeden undo krok.
    func titleEditingBegan() { undo.beginInteraction(project) }

    func titleEditingChanged(_ id: TitleClipID, text: String) {
        guard project.timeline.titleClip(id)?.text != text else { return }
        var updated = project
        guard (try? updated.setTitleText(id: id, text)) != nil else { return }
        project = updated
    }

    func titleEditingEnded() { undo.endInteraction(project) }

    func setTitleTemplate(_ id: TitleClipID, template: TitleTemplate) {
        guard let title = project.timeline.titleClip(id), title.template != template
        else { return }
        var updated = project
        guard (try? updated.setTitleTemplate(id: id, template)) != nil else { return }
        undo.record(project)
        project = updated
    }

    func setTitleAlignment(_ id: TitleClipID, alignment: TitleAlignment) {
        guard let title = project.timeline.titleClip(id), title.alignment != alignment
        else { return }
        var updated = project
        guard (try? updated.setTitleAlignment(id: id, alignment)) != nil else { return }
        undo.record(project)
        project = updated
    }

    /// Editace textu titulku z řeči (splátka fáze 8). Prázdný text úsek
    /// maže — výběr pak zaniká s ním.
    func setSpeechText(assetID: AssetID, segmentIndex: Int, text: String) {
        var updated = project
        guard (try? updated.setTranscriptText(assetID: assetID,
                                              segmentIndex: segmentIndex,
                                              text: text)) != nil else { return }
        undo.record(project)
        project = updated
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedSpeech = nil
        }
    }

    // MARK: Vzájemné vylučování výběrů

    /// Inspektor ukazuje jednu věc — kdo vybírá, ruší ostatní druhy výběru.
    func selectTitle(_ id: TitleClipID?) {
        if selectedTitle != id { selectedTitle = id }
        if id != nil {
            if !selection.isEmpty { selection = [] }
            if selectedSpeech != nil { selectedSpeech = nil }
        }
    }

    func selectSpeech(_ speech: SpeechSelection?) {
        if selectedSpeech != speech { selectedSpeech = speech }
        if speech != nil {
            if !selection.isEmpty { selection = [] }
            if selectedTitle != nil { selectedTitle = nil }
        }
    }

    func selectClips(_ ids: Set<ClipID>) {
        if selection != ids { selection = ids }
        if !ids.isEmpty {
            selectionAnchor = ids.count == 1 ? ids.first : selectionAnchor
            if selectedTitle != nil { selectedTitle = nil }
            if selectedSpeech != nil { selectedSpeech = nil }
            if selectedTransition != nil { selectedTransition = nil }
        }
    }

    // MARK: - Multi-výběr (fáze 17, modul 2)

    /// Poslední klip, na který se kliklo bez modifikátoru. Od něj měří
    /// shift-klik rozsah — bez kotvy by „rozšířit" nemělo od čeho.
    private(set) var selectionAnchor: ClipID?

    /// ⌘-klik: přidat nebo odebrat jeden klip.
    func toggleSelection(_ id: ClipID) {
        var ids = selection
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
            selectionAnchor = id
        }
        selectClips(ids)
        if ids.isEmpty { selectionAnchor = nil }
    }

    /// Shift-klik: rozsah od kotvy k cíli (na téže stopě), přidaný k výběru.
    /// Bez kotvy se chová jako prostý klik.
    func extendSelection(to id: ClipID) {
        guard let anchor = selectionAnchor, anchor != id else {
            selectClips([id])
            selectionAnchor = id
            return
        }
        selectClips(selection.union(project.clipRange(from: anchor, to: id)))
    }

    /// Rámečkový výběr. `adding` = tažení se shiftem nebo ⌘ přidává
    /// k dosavadnímu výběru místo aby ho nahradilo.
    func selectClips(in rect: TimelineRect, adding: Bool) {
        let hits = Set(geometry.clips(in: rect, in: project.timeline))
        selectClips(adding ? selection.union(hits) : hits)
        selectionAnchor = hits.count == 1 ? hits.first : selectionAnchor
    }

    /// ⌘A — všechny klipy osy (titulky ne, ty mají výhradní výběr).
    func selectAllClips() {
        let all = project.timeline.tracks.flatMap { $0.clips.map(\.id) }
        guard !all.isEmpty else { return }
        selectClips(Set(all))
    }

    // MARK: - Schránka (fáze 17, modul 2)

    /// Stav sezení, ne dokumentu — do projektového souboru nepatří a undo
    /// se jí netýká. Svázané dvojice a čerstvé `LinkID` řeší model.
    @Published private(set) var clipboard = Clipboard()

    /// Hlášky pro stavový řádek (vložení, které se nevejde, hromadná
    /// operace, která část výběru přeskočila). `AppModel` to napojí na
    /// `status`; osa sama žádný stavový řádek nemá.
    var onStatus: ((String) -> Void)?

    func copySelection() {
        let board = project.clipboard(copying: selection)
        guard !board.isEmpty else { return }
        clipboard = board
        onStatus?(board.count == 1 ? "Zkopírován 1 klip."
                                   : "Zkopírováno \(board.count) klipů.")
    }

    func cutSelection() {
        guard !selection.isEmpty else { return }
        var updated = project
        guard let board = try? updated.cut(selection), !board.isEmpty else { return }
        undo.record(project)
        project = updated
        clipboard = board
        selection = []
        selectionAnchor = nil
        onStatus?(board.count == 1 ? "Vyjmut 1 klip." : "Vyjmuto \(board.count) klipů.")
    }

    /// Vloží na hlavu. Buď celý obsah, nebo nic — model je atomický.
    /// Vložené klipy se rovnou vyberou, ať je vidět, s čím se dál pracuje.
    func pasteAtPlayhead() {
        guard !clipboard.isEmpty else { return }
        var updated = project
        do {
            let inserted = try updated.paste(clipboard, at: playhead)
            undo.record(project)
            project = updated
            selectClips(inserted)
            onStatus?(inserted.count == 1 ? "Vložen 1 klip." : "Vloženo \(inserted.count) klipů.")
        } catch {
            // Poctivá hláška místo tichého nic: uživatel jinak zkouší
            // ⌘V třikrát a myslí si, že je appka rozbitá.
            onStatus?("Na hlavě není místo — vlož jinam nebo udělej díru.")
        }
    }

    /// Vybraný přechod (fáze 16, modul 3 — drobnost z koukanců F10:
    /// „přechod nejde vybrat klikem do těla"). Výběr dává lichoběžníku
    /// rámeček a pouští na něj Delete.
    @Published var selectedTransition: TransitionID?

    func selectTransition(_ id: TransitionID?) {
        if selectedTransition != id { selectedTransition = id }
        if id != nil {
            if !selection.isEmpty { selection = [] }
            if selectedTitle != nil { selectedTitle = nil }
            if selectedSpeech != nil { selectedSpeech = nil }
        }
    }

    // MARK: - Fotky a Ken Burns (fáze 12, modul 3)

    /// Kontextové menu žádá zmrazit snímek — obslouží `AppModel` (čtení
    /// snímku z videa není práce osy).
    var onFreezeFrameRequest: ((ClipID) -> Void)?

    /// Přepnutí pohybu z pickeru — jeden undo krok.
    func setKenBurns(_ clipID: ClipID, _ kenBurns: KenBurns?) {
        guard project.timeline.clip(clipID)?.kenBurns != kenBurns else { return }
        var updated = project
        guard (try? updated.setKenBurns(clipID: clipID, kenBurns)) != nil else { return }
        undo.record(project)
        project = updated
    }

    /// Posuvník zoomu — vzorec hlasitosti: mezistavy legální, zapisují se
    /// průběžně a begin/end z nich složí jeden undo krok.
    func kenBurnsDragBegan() { undo.beginInteraction(project) }

    func kenBurnsDragChanged(_ clipID: ClipID, _ kenBurns: KenBurns?) {
        var updated = project
        guard (try? updated.setKenBurns(clipID: clipID, kenBurns)) != nil else { return }
        project = updated
    }

    func kenBurnsDragEnded() { undo.endInteraction(project) }

    // MARK: - Barevné presety (fáze 13, modul 3)

    /// Výběr presetu z pickeru — jeden undo krok.
    func setColorGrade(_ clipID: ClipID, _ grade: ColorGrade?) {
        guard project.timeline.clip(clipID)?.colorGrade != grade else { return }
        var updated = project
        guard (try? updated.setColorGrade(clipID: clipID, grade)) != nil else { return }
        undo.record(project)
        project = updated
    }

    // MARK: - Hromadné operace nad výběrem (fáze 17, modul 2)
    //
    // Vlastní odměna modulu: preset na deset klipů je jedno kliknutí.
    // Společné pravidlo — klipy, kde operace nedává smysl (zvuk u presetu,
    // fotka u rampy), se PŘESKOČÍ a řekne se to; celá dávka je jeden
    // undo krok.

    /// Klipy výběru, na které operace daného druhu sedí.
    private func selectedClips(onKind kind: TrackKind) -> [ClipID] {
        var out: [ClipID] = []
        for track in project.timeline.tracks where track.kind == kind {
            for clip in track.clips where selection.contains(clip.id) { out.append(clip.id) }
        }
        return out
    }

    /// Barevný preset na celý výběr.
    func setColorGradeOnSelection(_ grade: ColorGrade?) {
        let targets = selectedClips(onKind: .video)
        guard !targets.isEmpty else { return }
        var updated = project
        var changed = 0
        for id in targets where updated.timeline.clip(id)?.colorGrade != grade {
            if (try? updated.setColorGrade(clipID: id, grade)) != nil { changed += 1 }
        }
        guard changed > 0 else { return }
        undo.record(project)
        project = updated
        if targets.count > 1 { onStatus?("Preset nastaven na \(changed) klipech.") }
    }

    /// Táhne se posuvník síly nad víc klipy — vzorec hlasitosti: mezistavy
    /// legální, `beginInteraction`/`endInteraction` z nich složí jeden krok.
    func colorGradeDragChangedOnSelection(_ grade: ColorGrade?) {
        var updated = project
        for id in selectedClips(onKind: .video) {
            _ = try? updated.setColorGrade(clipID: id, grade)
        }
        project = updated
    }

    /// Fade na celý výběr. Délky se každému klipu zařežou zvlášť — krátký
    /// klip dostane, co unese, místo aby operace na něm selhala.
    func setAudioFadesOnSelection(_ fades: AudioFades?) {
        let targets = selectedClips(onKind: .audio)
        guard targets.count > 1 else { return }
        var updated = project
        var changed = 0
        for id in targets {
            guard let clip = updated.timeline.clip(id) else { continue }
            let capped = fades.map { f -> AudioFades in
                let limit = clip.duration
                var fadeIn = Frames(min(f.fadeIn.count, limit.count))
                let fadeOut = Frames(min(f.fadeOut.count, limit.count))
                if fadeIn + fadeOut > limit { fadeIn = limit - fadeOut }
                return AudioFades(fadeIn: fadeIn, fadeOut: fadeOut)
            }
            if (try? updated.setAudioFades(clipID: id, capped)) != nil { changed += 1 }
        }
        guard changed > 0 else { return }
        undo.record(project)
        project = updated
        onStatus?("Fade nastaven na \(changed) klipech.")
    }

    /// Klasické zpomalení na celý výběr. Rampa se každému klipu počítá
    /// z JEHO spotřeby — kopírovat uzly z cizího klipu nejde, jsou kotvené
    /// ve zdrojovém čase konkrétního záběru.
    func toggleClassicRampOnSelection() {
        let targets = selectedClips(onKind: .video)
        guard !targets.isEmpty else { return }
        // Když je bez rampy aspoň jeden, dávka rampu PŘIDÁVÁ; jinak maže.
        // Jinak by se u smíšeného výběru půlka zapnula a půlka vypnula.
        let adding = targets.contains { project.timeline.clip($0)?.speedRamp == nil }

        var updated = project
        var changed = 0
        var skipped = 0
        for id in targets {
            guard let clip = updated.timeline.clip(id) else { continue }
            if adding {
                guard clip.speedRamp == nil else { continue }
                let consumption = updated.sourceConsumption(of: clip)
                let ramp = SpeedRamp.classicSlowMotion(from: clip.sourceStart,
                                                       spanning: SourceTime(seconds: consumption.seconds * 0.625),
                                                       slowSpeed: 0.25)
                if (try? updated.setSpeedRamp(clipID: id, ramp: ramp)) != nil { changed += 1 }
                else { skipped += 1 }        // fotka, přechod na střihu, málo zdroje
            } else {
                if (try? updated.setSpeedRamp(clipID: id, ramp: nil)) != nil { changed += 1 }
            }
        }
        guard changed > 0 else {
            onStatus?("Zpomalení nešlo použít ani na jeden klip výběru.")
            return
        }
        undo.record(project)
        project = updated
        if targets.count > 1 {
            onStatus?(skipped > 0
                      ? "Zpomalení na \(changed) klipech, \(skipped) přeskočeno."
                      : "Zpomalení na \(changed) klipech.")
        }
    }

    /// Posuvník síly — vzorec hlasitosti a zoomu: mezistavy legální,
    /// zapisují se průběžně a begin/end z nich složí jeden undo krok.
    func colorGradeDragBegan() { undo.beginInteraction(project) }

    func colorGradeDragChanged(_ clipID: ClipID, _ grade: ColorGrade?) {
        var updated = project
        guard (try? updated.setColorGrade(clipID: clipID, grade)) != nil else { return }
        project = updated
    }

    func colorGradeDragEnded() { undo.endInteraction(project) }

    // MARK: - Hudba a doby (fáze 14, modul 2)

    /// Uloží mřížku dob k assetu hudby — jeden undo krok (výsledek
    /// analýzy i budoucí ruční korekce jdou touhle cestou).
    func setBeatGrid(assetID: AssetID, _ grid: BeatGrid?) {
        guard project.asset(assetID)?.beatGrid != grid else { return }
        var updated = project
        guard (try? updated.setBeatGrid(assetID: assetID, grid)) != nil else { return }
        undo.record(project)
        project = updated
    }

    /// Kontextové menu: zarovnat konec klipu na dobu (modul 3). Meze hlídá
    /// model; menu položku zapíná zkušební běh, takže selhání sem nedojde.
    func fitClipEndToBeat(_ clipID: ClipID) {
        var updated = project
        guard (try? updated.fitClipEndToBeat(clipID: clipID)) != nil else { return }
        undo.record(project)
        project = updated
    }

    /// Kontextové menu: rampa na úder — zpomalení dosedne na dobu nejblíž
    /// HLAVĚ (uživatel si úder naskrubuje).
    func rampClipToBeat(_ clipID: ClipID) {
        var updated = project
        guard (try? updated.rampClipToBeat(clipID: clipID, near: playhead)) != nil else { return }
        undo.record(project)
        project = updated
    }

    // MARK: - Zvukové fade (fáze 16)

    /// Puštění úchytu fade — jeden undo krok (vzorec přechodů: mezistavy
    /// kreslil jen náhled, model se sahá až tady).
    func setAudioFades(_ clipID: ClipID, _ fades: AudioFades?) {
        guard project.timeline.clip(clipID)?.audioFades != fades else { return }
        var updated = project
        guard (try? updated.setAudioFades(clipID: clipID, fades)) != nil else { return }
        undo.record(project)
        project = updated
    }

    // MARK: - Analýzy kvality (fáze 15)

    /// Vzorky ostrosti per asset — plní je `AppModel` z diskové cache
    /// (`SharpnessStore`), do projektového souboru se NEUKLÁDAJÍ.
    /// Promítnutí na klipy dělá model (`qualityMarks`) při reloadu osy.
    @Published var sharpnessSamples: [AssetID: [SharpnessSample]] = [:]

    /// Vzorky hluchosti (fáze 15, modul 2) — týž vzorec.
    @Published var emptinessSamples: [AssetID: [EmptinessSample]] = [:]

    // MARK: - Synchronizace externího zvuku (fáze 7, modul 5)

    /// Kontextové menu klipu žádá synchronizaci — obslouží `AppModel`
    /// (soubor, čtení zvuku, korelace jsou jeho práce, ne osy).
    var onSyncAudioRequest: ((ClipID) -> Void)?

    /// Položí synchronizovaný zvuk: přidá asset a vloží klip na POSLEDNÍ
    /// zvukovou stopu (A2 — A1 patří zvuku kamery). Vrací `false`, když
    /// vložení neprojde (typicky překryv s něčím, co na A2 už leží).
    func placeSyncedAudio(asset: Asset, timelineStart: Frames,
                          duration: Frames, sourceStart: SourceTime) -> Bool {
        guard duration > .zero,
              let a2 = project.timeline.tracks.last(where: { $0.kind == .audio })
        else { return false }
        var updated = project
        updated.addAsset(asset)
        let clip = Clip(assetID: asset.id, timelineStart: timelineStart,
                        duration: duration, sourceStart: sourceStart)
        guard (try? updated.insert(clip, onTrack: a2.id)) != nil else { return false }
        undo.record(project)
        project = updated
        selectClips([clip.id])
        return true
    }

    // MARK: - Titulky (fáze 8)

    /// Kontextové menu žádá přepis klipu — obslouží `AppModel` (Whisper
    /// není práce osy).
    var onTranscribeRequest: ((ClipID) -> Void)?

    func setTranscript(assetID: AssetID, segments: [TranscriptSegment]) {
        var updated = project
        guard (try? updated.setTranscript(assetID: assetID, segments: segments)) != nil
        else { return }
        undo.record(project)
        project = updated
    }

    // MARK: - Hlasitost stop (fáze 7, modul 2)

    func setTrackMuted(_ trackID: TrackID, muted: Bool) {
        var updated = project
        guard (try? updated.setTrackMuted(trackID: trackID, isMuted: muted)) != nil
        else { return }
        undo.record(project)
        project = updated
    }

    /// Tažení posuvníku hlasitosti — vzorec trimu: mezistavy jsou legální,
    /// zapisují se průběžně a `beginInteraction`/`endInteraction` z nich
    /// složí jeden undo krok.
    func volumeDragBegan() { undo.beginInteraction(project) }

    func volumeDragChanged(_ trackID: TrackID, volume: Double) {
        var updated = project
        guard (try? updated.setTrackVolume(trackID: trackID, volume: volume)) != nil
        else { return }
        project = updated
    }

    func volumeDragEnded() { undo.endInteraction(project) }

    // MARK: - Undo (krok 7)

    func undoStep() {
        guard let previous = undo.undo(current: project) else { return }
        project = previous
    }

    func redoStep() {
        guard let next = undo.redo(current: project) else { return }
        project = next
    }

    // MARK: - Import naskenovaných klipů (krok 5)

    /// Postaví projekt znovu z naskenovaných klipů: každý za konec
    /// předchozího, obraz na V1 a zvuk svázaně na A1.
    ///
    /// Znovu, ne přírůstkově: sken se pouští při každém startu i při každém
    /// „Otevřít složku" a vrací vždy CELÝ seznam — přidávat by znamenalo
    /// duplikovat. Až bude skutečný projektový soubor (fáze 5), tohle celé
    /// zmizí; do té doby je timeline obraz posledního skenu.
    ///
    /// Délka assetu = počet vzorků / naměřená frekvence. `ClipTiming` nenese
    /// délku v sekundách a `nominalFrameRate` lže — počet vzorků je měření.
    /// Nahraje projekt ze souboru (fáze 5). Čistý stav: žádný výběr,
    /// hlava na nule, prázdná historie — undo nesmí umět „odotevřít" soubor.
    func loadProject(_ project: Project) {
        self.project = project
        selection = []
        playhead = .zero
        undo = UndoStack()
    }

    func loadScannedClips(_ timings: [ClipTiming], bookmarks: [URL: Data] = [:]) {
        var built = Project.empty()

        guard let videoTrack = built.timeline.tracks.first(where: { $0.kind == .video })?.id,
              let audioTrack = built.timeline.tracks.first(where: { $0.kind == .audio })?.id
        else { return }

        for timing in timings {
            guard timing.measuredFrameRate > 0, timing.sampleCount > 0 else { continue }
            let seconds = Double(timing.sampleCount) / timing.measuredFrameRate

            let asset = Asset(originalURL: timing.url,
                              // Bookmark do projektového souboru — po restartu
                              // oprávnění sandboxu z tohohle běhu neplatí.
                              bookmark: bookmarks[timing.url],
                              duration: SourceTime(seconds: seconds),
                              measuredFrameRate: timing.measuredFrameRate,
                              hasVideo: true,
                              // Nepřímý, ale jediný dostupný signál: offset
                              // zvukové stopy sonda vyplní, jen když zvuková
                              // stopa existuje.
                              hasAudio: timing.audioSourceOffset != nil,
                              // Čas natočení (fáze 17) — sonda ho přečetla
                              // spolu s časováním, tady se jen předává dál.
                              creationDate: timing.creationDate,
                              creationDateSource: timing.creationDateSource)
            built.addAsset(asset)

            let start = built.duration
            do {
                if asset.hasAudio {
                    let pair = try built.makeLinkedClips(assetID: asset.id, at: start)
                    try built.insertLinked(video: pair.video, onVideoTrack: videoTrack,
                                           audio: pair.audio, onAudioTrack: audioTrack)
                } else {
                    let clip = try built.makeClip(assetID: asset.id, at: start)
                    try built.insert(clip, onTrack: videoTrack)
                }
            } catch {
                // Klip kratší než snímek základny apod. — přeskočit, ne spadnout.
                continue
            }
        }

        project = built
        selection = []
        playhead = .zero
        undo = UndoStack()
    }

    // MARK: - Proxy (fáze 4)

    /// Přišije proxy k assetu. BEZ undo kroku — dostupnost proxy není
    /// střihové rozhodnutí a ⌘Z ji nemá vracet. Undo snapshoty z doby před
    /// dokončením proxy ji neznají, proto se po každé změně projektu
    /// přišívá znovu (`AppModel.reapplyKnownProxies`).
    func setProxy(_ url: URL, forAssetWithOriginal original: URL) {
        guard let asset = project.assets.first(where: { $0.originalURL == original }),
              asset.proxyURL != url else { return }
        var updated = asset
        updated.proxyURL = url
        var next = project
        next.addAsset(updated)   // nahrazuje podle ID, klipy zůstávají
        project = next
    }

    /// Volba „stříhat z proxy" je per projekt, ne per klip (rozhodnutí
    /// z fáze 2). Také bez undo — je to režim práce, ne střih.
    func setUsesProxies(_ value: Bool) {
        guard project.usesProxies != value else { return }
        var next = project
        next.usesProxies = value
        project = next
    }

    /// Odšije všechny proxy z projektu — před smazáním cache nebo změnou
    /// umístění. Jeden zápis, ne N; kompozice se přestaví na originály.
    func clearAssetProxies() {
        guard project.usesProxies || project.assets.contains(where: { $0.proxyURL != nil })
        else { return }
        var next = project
        for asset in next.assets where asset.proxyURL != nil {
            var updated = asset
            updated.proxyURL = nil
            next.addAsset(updated)
        }
        next.usesProxies = false
        project = next
    }

    // MARK: - Zátěžový projekt (výkonový test fáze 2)

    /// Postaví syntetickou osu pro výkonový test: `pairs` dvojic obraz+zvuk
    /// (tedy 2×`pairs` klipů) nastříhaných dokola z naskenovaných assetů.
    /// Délky klipů cyklují 45–150 snímků a zdrojový začátek se posouvá,
    /// ať recyklované vrstvy a dlaždice vln nedostávají identickou práci.
    func loadStressProject(from timings: [ClipTiming], pairs: Int) {
        var built = Project.empty()
        guard let videoTrack = built.timeline.tracks.first(where: { $0.kind == .video })?.id,
              let audioTrack = built.timeline.tracks.first(where: { $0.kind == .audio })?.id
        else { return }

        var usable: [Asset] = []
        for timing in timings
        where timing.measuredFrameRate > 0 && timing.sampleCount > 0
            && timing.audioSourceOffset != nil {
            let seconds = Double(timing.sampleCount) / timing.measuredFrameRate
            let asset = Asset(originalURL: timing.url,
                              duration: SourceTime(seconds: seconds),
                              measuredFrameRate: timing.measuredFrameRate)
            built.addAsset(asset)
            usable.append(asset)
        }
        guard !usable.isEmpty else { return }

        let durations = [45, 90, 150, 60, 120]
        var cursor = Frames.zero
        for index in 0..<pairs {
            let asset = usable[index % usable.count]
            let available = built.timeline.availableFrames(from: asset.duration)
            let length = Frames(min(durations[index % durations.count], available.count))
            guard length.count > 0 else { continue }
            let slack = max(1, available.count - length.count + 1)
            let sourceStart = built.timeline.sourceTime(Frames((index * 30) % slack))

            let link = LinkID()
            let video = Clip(assetID: asset.id, linkID: link,
                             timelineStart: cursor, duration: length,
                             sourceStart: sourceStart)
            let audio = Clip(assetID: asset.id, linkID: link,
                             timelineStart: cursor, duration: length,
                             sourceStart: sourceStart)
            do {
                try built.insert(video, onTrack: videoTrack)
                try built.insert(audio, onTrack: audioTrack)
            } catch {
                continue
            }
            cursor += length
        }

        project = built
        selection = []
        playhead = .zero
        undo = UndoStack()
    }
}
