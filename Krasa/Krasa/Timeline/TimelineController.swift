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
//  To všechno umí `TimelineModel` a je to otestované (143 testů).
//

import Foundation
import TimelineModel

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

    /// Hlavu právě táhne uživatel. Po tu dobu se ignorují aktualizace
    /// z přehrávače — obousměrná vazba se nikdy nesmí zapnout naráz
    /// (`FAZE_2_VIEW.md`, sekce 5). Schválně ne `@Published`: je to příznak
    /// pro logiku, ne stav ke kreslení.
    var isUserScrubbing = false

    /// Výběr. Totéž — stav UI, ne dokumentu.
    @Published var selection: Set<ClipID> = []

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

    /// Testovací rampa (fáze 3, modul 2): klasické zpomalení 1× → 0,25× → 1×
    /// přes klip, dokud nemá `SpeedRampEditor` vlastní UI (modul 3). Když už
    /// klip křivku má, akce ji smaže. Dvojče řeší model (`setSpeedRamp` je
    /// link-aware), undo jeden krok.
    func toggleTestRamp(_ clipID: ClipID) {
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
    func loadScannedClips(_ timings: [ClipTiming]) {
        var built = Project.empty()

        guard let videoTrack = built.timeline.tracks.first(where: { $0.kind == .video })?.id,
              let audioTrack = built.timeline.tracks.first(where: { $0.kind == .audio })?.id
        else { return }

        for timing in timings {
            guard timing.measuredFrameRate > 0, timing.sampleCount > 0 else { continue }
            let seconds = Double(timing.sampleCount) / timing.measuredFrameRate

            let asset = Asset(originalURL: timing.url,
                              duration: SourceTime(seconds: seconds),
                              measuredFrameRate: timing.measuredFrameRate,
                              hasVideo: true,
                              // Nepřímý, ale jediný dostupný signál: offset
                              // zvukové stopy sonda vyplní, jen když zvuková
                              // stopa existuje.
                              hasAudio: timing.audioSourceOffset != nil)
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
}
