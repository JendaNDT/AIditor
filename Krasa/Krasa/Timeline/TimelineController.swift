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
}
