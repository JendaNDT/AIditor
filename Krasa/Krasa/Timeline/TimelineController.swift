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

    /// Výběr. Totéž — stav UI, ne dokumentu.
    @Published var selection: Set<ClipID> = []

    // `waveforms: WaveformStore` přibude až s krokem 10 (vlnové průběhy).

    init(project: Project = .empty(), geometry: TimelineGeometry = TimelineGeometry()) {
        self.project = project
        self.interaction = TimelineInteraction(geometry: geometry)
    }

    /// Jediné úložiště, žádná synchronizace.
    var geometry: TimelineGeometry {
        get { interaction.geometry }
        set { interaction.geometry = newValue }
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
