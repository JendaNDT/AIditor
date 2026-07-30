//
//  TimelineRulerView.swift
//  Projekt Krása
//
//  Pravítko s timecode. Krok 3 z `FAZE_2_VIEW.md`, sekce 7 a 2.5.
//
//  ⚠️ **Není to `NSRulerView`.** Ta registruje jednotky globálně metodou
//  `registerUnit(withName:abbreviation:unitToPointsConversionFactor:…)`
//  a ten převodní faktor je konstanta — náš `pointsPerFrame` se mění při
//  každém zoomu, takže bychom při každém pinchi přeregistrovávali jednotku
//  sdílenou se všemi pravítky v aplikaci. Navíc popisky nejsou čísla
//  s jednotkou, ale `00:01:23:14`.
//
//  ⚠️ **Pravítko neskroluje, překresluje se.** Není uvnitř `NSScrollView`,
//  jen dostává `contentView.bounds.origin.x` a odečítá ho od pozic. Kdyby
//  bylo uvnitř, scrollovalo by i svisle a odjelo by se stopami pryč.
//

import AppKit
import TimelineModel

final class TimelineRulerView: NSView {

    static let height: CGFloat = 26

    private let controller: TimelineController

    /// Vodorovný posun plochy osy. Píše ho `TimelinePane` z notifikace.
    var scrollX: Double = 0 {
        didSet { if scrollX != oldValue { needsDisplay = true } }
    }

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    /// Stejně jako u plochy osy — počátek vlevo nahoře, ať se souřadnice
    /// nemusí v půlce souboru obracet.
    override var isFlipped: Bool { true }

    /// Popisek se musí vejít i s mezerou: `00:00:00:00` monospaced desítkou
    /// plus vzduch na obou stranách.
    ///
    /// ⚠️ Na pravítku je **plný čtyřskupinový timecode**, ne zkrácený
    /// `MM:SS:FF`. Zkrácený se vejde do menší šířky, ale tři skupiny si
    /// každý přečte jako `HH:MM:SS` — `00:04:00` pak vypadá na čtyři minuty
    /// a znamená čtyři sekundy. Číslo, které nelže a přitom mate, je pořád
    /// špatné číslo. Čtyři skupiny používá každý NLE právě proto.
    private static let minimumLabelSpacing: Double = 100

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        // ⚠️ Barvy se tu berou jako `NSColor` při každém kreslení, ne jako
        // `CGColor` uložený do vrstvy — proto tady problém se zamrznutím
        // v tmavém režimu vůbec nevzniká.
        TimelinePalette.chrome.setFill()
        bounds.fill()

        let geometry = controller.geometry
        let frameRate = controller.project.timeline.frameRate
        let interval = geometry.rulerInterval(frameRate: frameRate,
                                              minimumSpacing: Self.minimumLabelSpacing)

        // Přesah, aby popisek napůl za hranou okna nezmizel celý.
        let range = geometry.visibleFrameRange(scrollX: scrollX,
                                               width: Double(bounds.width),
                                               overscanPoints: Self.minimumLabelSpacing)

        drawExportRange(geometry: geometry)
        drawMinorTicks(geometry: geometry, range: range, interval: interval)
        drawBeatMarks(geometry: geometry, range: range)
        drawLabels(geometry: geometry, range: range, interval: interval, frameRate: frameRate)

        // Předěl proti ploše osy.
        TimelinePalette.separator.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// Ryska bez popisku uprostřed mezi popisky.
    ///
    /// Půlka, ne pětina — půlka vždycky padne na celý snímek a vždycky se
    /// trefí pod popisek. Rozteče z žebříku na sebe totiž nenavazují
    /// jednotným poměrem (15 → 30 je dvojnásobek, 30 → 60 taky, ale
    /// 60 → 150 je dva a půl), takže pevná pětina by u některých zoomů
    /// kreslila rysky mimo popisky.
    private func drawMinorTicks(geometry: TimelineGeometry,
                                range: Range<Frames>,
                                interval: Frames) {
        guard interval.count % 2 == 0 else { return }
        let half = Frames(interval.count / 2)

        TimelinePalette.tick.withAlphaComponent(0.45).setFill()
        for frame in geometry.rulerFrames(in: range, interval: half) {
            guard frame.count % interval.count != 0 else { continue }   // pod popiskem už ryska je
            let x = (geometry.x(for: frame) - scrollX).rounded()
            NSRect(x: x, y: bounds.height - 5, width: 1, height: 4).fill()
        }
    }

    /// Výřez k exportu (fáze 17, modul 3): světlý pruh mezi in a out
    /// a plné zarážky na obou koncích.
    ///
    /// Kreslí se, JEN když je výřez opravdu výřez — zvýrazňovat celý film
    /// by znamenalo, že „nic nevybráno" a „vybráno vše" vypadá stejně,
    /// a uživatel by pak nevěděl, jestli mu export ukrojí konec.
    private func drawExportRange(geometry: TimelineGeometry) {
        // ⚠️ Bez in/out bodů se rovnou vrací, a je to VÝKONOVÁ věc, ne úklid.
        // `hasExportRange` i `exportRange` počítají `Project.duration`, a ta
        // prochází všechny klipy a alokuje přitom dvě pole — na 2000 klipech
        // ~0,8 ms na jedno kreslení. Pravítko se překresluje při každém tiku
        // scrollu, takže se to platilo za informaci „výřez není nastavený".
        // Kreslení pravítka spadlo z 0,88 na 0,08 ms (změřeno M6, `--thumb-check`
        // část E). Výsledek je stejný, jen bez počítání.
        //
        // ⚠️ **A pozor na to, co udělá `--timeline-bench`: medián práce na tik
        // STOUPNE z 0,97 na 1,95 ms.** Není to regrese — A/B na tomhle jednom
        // řádku (třikrát každá varianta, rozptyl 0,02 ms) ukazuje pořád
        // stejnou věc: ten údaj měří `scroll(to:)` na hlavním vlákně, a když
        // vlákno mezi tiky nemá co dělat, platí se za probuzení (rampa
        // frekvence, studená cache). Součet práce na snímek se nezměnil
        // (~2 ms z 16,67) a vypadlé tiky zůstávají 0–1. Nevracet to „zpátky"
        // podle benchmarku — je to práce, která zmizela.
        guard controller.inPoint != nil || controller.outPoint != nil else { return }
        guard controller.hasExportRange else { return }
        let range = controller.exportRange
        let startX = geometry.x(for: range.lowerBound) - scrollX
        let endX = geometry.x(for: range.upperBound) - scrollX
        guard endX > 0, startX < Double(bounds.width) else { return }

        TimelinePalette.clipSelectedStroke.withAlphaComponent(0.18).setFill()
        NSRect(x: startX, y: 0, width: endX - startX, height: bounds.height).fill()

        TimelinePalette.clipSelectedStroke.setFill()
        for x in [startX, endX - 2] {
            NSRect(x: x.rounded(), y: 0, width: 2, height: bounds.height).fill()
        }
    }

    /// Doby hudby (fáze 14): jantarové rysky při spodní hraně, „raz"
    /// taktu vyšší a plný. Počítá se při každém kreslení — bez hudby
    /// s mřížkou je `beatMarks()` okamžitý early-out přes assety a
    /// s hudbou jsou to stovky značek, ne tisíce (scroll benchmark
    /// fáze 2 zůstává nedotčený).
    private func drawBeatMarks(geometry: TimelineGeometry, range: Range<Frames>) {
        guard controller.layers.beats else { return }   // vypnutá vrstva (F18/M3)
        let marks = controller.project.beatMarks()
        guard !marks.isEmpty else { return }
        for mark in marks {
            guard mark.frame >= range.lowerBound, mark.frame < range.upperBound else { continue }
            let x = (geometry.x(for: mark.frame) - scrollX).rounded()
            let height: CGFloat = mark.isDownbeat ? 8 : 4
            (mark.isDownbeat
                ? TimelinePalette.beat
                : TimelinePalette.beat.withAlphaComponent(0.55)).setFill()
            NSRect(x: x, y: bounds.height - 1 - height,
                   width: mark.isDownbeat ? 2 : 1, height: height).fill()
        }
    }

    // MARK: - Myš → přehrávací hlava (krok 6)

    /// Klik i tažení v pravítku posouvá hlavu. Souřadnice se převádí přes
    /// `scrollX` do soustavy dokumentu a přes geometrii na snímek — stejná
    /// cesta, jakou jde kreslení, jen pozpátku. Meze hlídá controller.
    override func mouseDown(with event: NSEvent) {
        controller.isUserScrubbing = true
        moveHead(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        moveHead(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        controller.isUserScrubbing = false
    }

    private func moveHead(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x + scrollX
        controller.setPlayheadFromUser(controller.geometry.frame(atX: x))
    }

    private func drawLabels(geometry: TimelineGeometry,
                            range: Range<Frames>,
                            interval: Frames,
                            frameRate: Int) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: TimelinePalette.text,
        ]

        for frame in geometry.rulerFrames(in: range, interval: interval) {
            // Na celý bod, jinak je svislá ryska rozmazaná přes dva pixely.
            let x = (geometry.x(for: frame) - scrollX).rounded()

            TimelinePalette.tick.setFill()
            NSRect(x: x, y: bounds.height - 9, width: 1, height: 8).fill()

            let label = frame.timecode(frameRate: frameRate).text
            let string = NSAttributedString(string: label, attributes: attributes)
            // Dva body vpravo od rysky, ať popisek nesedí na čáře.
            string.draw(at: NSPoint(x: x + 3, y: 3))
        }
    }
}
