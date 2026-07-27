//
//  TimelineDocumentView.swift
//  Projekt Krása
//
//  Plocha časové osy uvnitř `NSScrollView`. Krok 2 z `FAZE_2_VIEW.md`, sekce 7.
//
//  Zatím jen pruhy stop. Klipy jsou krok 5, pravítko a hlavičky krok 3.
//  Do view patří kreslení a předávání událostí, nic víc — všechno, co má
//  návratovou hodnotu porovnatelnou s očekáváním, umí `TimelineModel`.
//

import AppKit
import TimelineModel

/// Barvy časové osy.
///
/// ⚠️ **Sémantické systémové barvy se sem nehodí.** První verze kroku 2 brala
/// pruhy z `controlBackgroundColor` a pozadí z `underPageBackgroundColor` —
/// v tmavém režimu jsou obě skoro černé, takže osa vyšla jako jeden slitý
/// tmavý blok a tři pruhy v ní nebyly poznat. Ty barvy mají svůj smysl
/// (obsah okna, plocha pod dokumentem), ale nejsou navržené na to, aby se
/// odlišily od sebe navzájem.
///
/// Proto vlastní paleta. `NSColor(name:dynamicProvider:)` drží obě větve
/// v jedné hodnotě, takže i tady stačí barvu přeložit při změně vzhledu
/// a nikde není druhá sada konstant.
/// <https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)>
enum TimelinePalette {

    private static func adaptive(_ name: String,
                                 dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        }
    }

    /// Plocha pod stopami a za koncem projektu.
    static let background = adaptive("timelineBackground", dark: 0.09, light: 0.78)
    /// Pruh obrazové stopy. Nejsvětlejší — obraz je hlavní.
    static let videoLane = adaptive("timelineVideoLane", dark: 0.24, light: 0.95)
    /// Pruh zvukové stopy.
    static let audioLane = adaptive("timelineAudioLane", dark: 0.17, light: 0.88)

    static func lane(for kind: TrackKind) -> NSColor {
        kind == .video ? videoLane : audioLane
    }
}

final class TimelineDocumentView: NSView {

    /// Vlastník stavu. Silná reference je v pořádku, protože controller
    /// zpátky na views neukazuje. Až ukazovat bude, ať je ta cesta `weak`.
    private let controller: TimelineController

    /// Pruhy stop pod klipy. Jeden `CALayer` na STOPU — stop jsou jednotky,
    /// takže se recyklovat nemusí. Recyklace se řeší u klipů (krok 5).
    private let backgroundLayer = CALayer()
    private var laneLayers: [CALayer] = []

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(backgroundLayer)
        rebuildLanes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    // MARK: - ⚠️ Svislá osa

    /// ⚠️ **Bez tohohle je celá svislá osa vzhůru nohama.**
    ///
    /// `TimelineGeometry.y(ofTrackAt:)` sčítá výšky stop odshora dolů, takže
    /// stopa 0 má `y = 0`. AppKit má ale ve výchozím stavu počátek vlevo dole.
    /// Nespadne to a nevyhodí to warning — jen `trackIndex(atY:)` vrátí při
    /// kliknutí na V1 poslední zvukovou stopu a klipy se nakreslí obráceně.
    ///
    /// <https://developer.apple.com/documentation/appkit/nsview/isflipped>
    override var isFlipped: Bool { true }

    // MARK: - Stopy

    /// Přepočítá POČET vrstev podle stop. Volá se při změně sady stop,
    /// ne při každém layoutu — ten jen přepisuje rámce.
    func rebuildLanes() {
        let count = controller.project.timeline.tracks.count

        while laneLayers.count > count {
            laneLayers.removeLast().removeFromSuperlayer()
        }
        while laneLayers.count < count {
            let lane = CALayer()
            backgroundLayer.addSublayer(lane)
            laneLayers.append(lane)
        }

        applyColors()
        applyContentsScale()
        needsLayout = true
    }

    override func layout() {
        super.layout()

        // ⚠️ `CALayer` animuje změnu `frame` 0,25 s. Při scrollování by pruhy
        // „plavaly" za obsahem. `PlayerView.layout()` řešil v projektu tenhle
        // problém už jednou, stejným způsobem.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        backgroundLayer.frame = bounds

        // ⚠️ Souřadnice vrstev jsou tu shodné se souřadnicemi view, tedy
        // počátek vlevo NAHOŘE. AppKit u převráceného layer-backed view sám
        // nastavuje `layer.isGeometryFlipped = true` (ověřeno měřením
        // 27. 07. 2026) a SDK k té vlastnosti říká „geometry of the layer
        // AND ITS SUBLAYERS is flipped vertically". Proto jde `y(ofTrackAt:)`
        // vrstvě předat rovnou a nic se nepřepočítává.
        //
        // Pozor při ověřování: `CALayer.render(in:)` převrácení IGNORUJE,
        // takže cokoli změřeného přes něj tvrdí opak. Poznat je to okem —
        // V1 je vysoká 64 bodů proti 44 u zvuku, takže při špatném převrácení
        // leží vysoký pruh dole.
        let geometry = controller.geometry
        let timeline = controller.project.timeline

        for (index, track) in timeline.tracks.enumerated() where index < laneLayers.count {
            laneLayers[index].frame = CGRect(x: 0,
                                             y: geometry.y(ofTrackAt: index, in: timeline),
                                             width: bounds.width,
                                             height: geometry.height(of: track.kind))
        }
    }

    // MARK: - Barvy

    /// ⚠️ **`NSColor.cgColor` se vyhodnotí pro appearance platnou v okamžiku
    /// volání, ne pro tu, ve které vrstva leží.** Systémová barva uložená do
    /// `CALayer.backgroundColor` tedy při přepnutí do tmavého režimu zamrzne
    /// na staré hodnotě. Proto se barvy překládají uvnitř
    /// `performAsCurrentDrawingAppearance` a znovu při každé změně vzhledu.
    ///
    /// <https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)>
    private func applyColors() {
        let tracks = controller.project.timeline.tracks

        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            layer?.backgroundColor = TimelinePalette.background.cgColor

            for (index, lane) in laneLayers.enumerated() where index < tracks.count {
                lane.backgroundColor = TimelinePalette.lane(for: tracks[index].kind).cgColor
            }

            CATransaction.commit()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    // MARK: - Retina

    /// ⚠️ **Ručně vytvořené vrstvy `contentsScale` nedostanou.** Výchozí
    /// hodnota je 1,0; vrstva připojená k view ji zdědí od view, ale ta,
    /// kterou si vyrobíme sami, ne. U jednobarevných pruhů to ještě nevadí,
    /// u textu a vlny (kroky 5 a 10) je z toho rozmazaná Retina.
    ///
    /// <https://developer.apple.com/documentation/quartzcore/calayer/contentsscale>
    private func applyContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        backgroundLayer.contentsScale = scale
        for lane in laneLayers { lane.contentsScale = scale }
    }

    /// Volá se i při přesunu okna na displej s jiným rozlišením, ne jen na začátku.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyContentsScale()
    }
}
