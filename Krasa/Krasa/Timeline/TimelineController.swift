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
        selection = [clip.id]
        return true
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
