//
//  TimelineBarState.swift
//  Projekt AIditor — UI/Shell
//
//  Úzké zrcadlo `TimelineController` pro lištu nad osou (fáze 18, modul 3;
//  oprava 30. 07. 2026).
//
//  ⚠️ Past projektu POTŘETÍ: `TimelineController` je VNOŘENÝ `ObservableObject`
//  uvnitř `AppModelu`, takže view, které pozoruje jen model, jeho
//  `objectWillChange` NEDOSTANE. `TimelineLayerBar` čte a mění stav
//  controlleru (vrstvy, přichytávání, citlivost, zoom, výřez), ale pozorovala
//  jen `AppModel` — pilulky proto měnily vzhled až při nejbližším překreslení
//  z jiného důvodu (typicky změna `status`). Kreslení na ose správně bylo:
//  AppKit se na controller odebírá sám. Rozjíždělo se jen ovládání.
//  (F11 `selectedTitle`, F18/M11 `selectedSpeech`, teď lišta.)
//
//  ⚠️ A pozor na obvyklé „řešení": prosté `@ObservedObject var timeline` v liště
//  znamená překreslení při KAŽDÉ změně controlleru — tedy 30×/s během
//  přehrávání (`playhead` je `@Published` na témže objektu) a při každém pohybu
//  myší během tažení (`interaction`). Odběry jsou proto CÍLENÉ, přesně jako
//  v `TimelinePane`: lišta se překreslí, jen když se změní to, co doopravdy
//  ukazuje. Změřeno v `--layers-check`, části C.
//
//  Vlastní malý `ObservableObject`, ne `@Published` pole na `AppModelu`:
//  kdyby stav lišty visel na modelu, tažení posuvníku zoomu by 60×/s
//  překreslovalo CELOU skořápku (toolbar, rail, panely). Takhle jen lištu.
//

import Combine
import Foundation
import TimelineModel

@MainActor
final class TimelineBarState: ObservableObject {

    /// Co osa kreslí (pilulky vlevo).
    @Published private(set) var layers = TimelineLayers()
    /// Magnet zapnutý globálně.
    @Published private(set) var snappingEnabled = true
    /// Citlivost klasifikace ostrosti a hluchých míst, 0–1.
    @Published private(set) var qualitySensitivity = 0.5
    /// Zoom osy v bodech na snímek — z něj se počítá poloha posuvníku.
    @Published private(set) var pointsPerFrame = 1.0
    /// Popisek výřezu, nebo `nil`, když výřez není nastavený. Hotový TEXT,
    /// ne body: viz `refreshExportRangeText()`.
    @Published private(set) var exportRangeText: String?

    private let timeline: TimelineController
    private var subscriptions: [AnyCancellable] = []

    init(timeline: TimelineController) {
        self.timeline = timeline
        // Výchozí stav ze skutečných hodnot — `@Published` sice pošle
        // současnou hodnotu hned při odběru, ale citlivost se čte
        // z `UserDefaults` a zoom z geometrie, takže ať to sedí i před
        // prvním doručením.
        layers = timeline.layers
        snappingEnabled = timeline.snappingEnabled
        qualitySensitivity = timeline.qualitySensitivity
        pointsPerFrame = timeline.geometry.pointsPerFrame

        subscriptions = [
            // Hodnota se bere Z PUBLISHERU, ne zpětným dotazem na controller:
            // `@Published` posílá novou hodnotu ve `willSet`, kdy má vlastnost
            // ještě starou (týž důvod, proč má `TimelinePane` všude
            // `receive(on:)`). Tady je proto odběr SYNCHRONNÍ — posuvník
            // citlivosti a zoomu by s odloženým doručením při tažení
            // zadrhával, protože by si četl vlastní hodnotu o krok pozadu.
            timeline.$layers
                .removeDuplicates()
                .sink { [weak self] in self?.layers = $0 },
            timeline.$snappingEnabled
                .removeDuplicates()
                .sink { [weak self] in self?.snappingEnabled = $0 },
            timeline.$qualitySensitivity
                .removeDuplicates()
                .sink { [weak self] in self?.qualitySensitivity = $0 },
            // Geometrie žije uvnitř `interaction` (jediné úložiště zoomu).
            // `interaction` se mění při každém pohybu myší během tažení,
            // takže `removeDuplicates` na jednom Doublu je tu to podstatné —
            // bez něj by lišta překreslovala celé tažení klipu.
            timeline.$interaction
                .map(\.geometry.pointsPerFrame)
                .removeDuplicates()
                .sink { [weak self] in self?.pointsPerFrame = $0 },
            // Výřez: text se počítá jen při změně bodů nebo projektu, ne při
            // každém vyhodnocení těla lišty. Projekt je přes `debounce`,
            // protože `Project.duration` je O(klipů) (past z M6) a při tažení
            // trimu chodí změny projektu po každém pohybu myší.
            // `receive(on:)` je tu nutný: `refreshExportRangeText` si hodnoty
            // ČTE z controlleru, a ve `willSet` by ještě četl staré.
            Publishers.Merge3(
                timeline.$inPoint.map { _ in () },
                timeline.$outPoint.map { _ in () },
                timeline.$project
                    .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
                    .map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.refreshExportRangeText() },
        ]
    }

    /// Popisek výřezu. Vzorec `TimelineRulerView.drawExportRange`: nejdřív
    /// laciný odskok na bodech, teprve pak `exportRange` a `duration`.
    ///
    /// ⚠️ `Project.duration` prochází všechny klipy a alokuje přitom dvě pole
    /// (~1,5 ms na 2000 klipech, CLAUDE.md). Proto se tady čte NEJVÝŠ dvakrát
    /// a jen na změnu — ne v každém průchodu `body`, kde to bylo dosud.
    private func refreshExportRangeText() {
        guard timeline.inPoint != nil || timeline.outPoint != nil else {
            set(nil); return
        }
        let range = timeline.exportRange
        // Ruční ekvivalent `hasExportRange` — ta vlastnost by spočítala
        // `exportRange` (a v ní `duration`) ještě jednou navíc.
        guard range.lowerBound.count > 0 || range.upperBound < timeline.project.duration
        else { set(nil); return }

        let rate = timeline.project.timeline.frameRate
        set("výřez \(Timecode(range.lowerBound, frameRate: rate).shortText)"
            + "–\(Timecode(range.upperBound, frameRate: rate).shortText)")
    }

    private func set(_ text: String?) {
        if exportRangeText != text { exportRangeText = text }
    }
}
