//
//  TrackHeadersView.swift
//  Projekt Krása
//
//  Hlavičky stop vlevo od osy. Krok 3 z `FAZE_2_VIEW.md`, sekce 3 a 2.5.
//
//  Stejný princip jako pravítko, jen druhá osa: hlavičky nejsou uvnitř
//  `NSScrollView`, dostávají `contentView.bounds.origin.y` a odečítají ho.
//  Uvnitř by scrollovaly i vodorovně a odjely by pryč.
//
//  Mute/solo, přejmenování a přidávání stop sem přijdou později — model to
//  umí (`addTrack`, `removeTrack`, `AudioSettings`), ale fáze 2 má výchozí
//  V1 + A1 + A2 bez úprav, viz `FAZE_2_VIEW.md` sekce 8, bod 2.
//

import AppKit
import TimelineModel

final class TrackHeadersView: NSView {

    static let width: CGFloat = 96

    private let controller: TimelineController

    /// Svislý posun plochy osy. Píše ho `TimelinePane` z notifikace.
    var scrollY: Double = 0 {
        didSet { if scrollY != oldValue { needsDisplay = true } }
    }

    init(controller: TimelineController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    /// ⚠️ Musí souhlasit s plochou osy. `y(ofTrackAt:)` počítá odshora dolů,
    /// takže při nepřevrácené ose by hlavičky vyšly v opačném pořadí než
    /// pruhy — jméno „V1" by stálo vedle zvukové stopy.
    override var isFlipped: Bool { true }

    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    override func draw(_ dirtyRect: NSRect) {
        TimelinePalette.chrome.setFill()
        bounds.fill()

        let geometry = controller.geometry
        let timeline = controller.project.timeline

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: TimelinePalette.text,
        ]

        for (index, track) in timeline.tracks.enumerated() {
            let y = geometry.y(ofTrackAt: index, in: timeline) - scrollY
            let height = geometry.height(of: track.kind)
            let rect = NSRect(x: 0, y: y, width: Double(bounds.width), height: height)

            guard rect.intersects(bounds) else { continue }

            // Táž barva jako pruh stopy. Když hlavička nesedí s pruhem
            // svisle, je to na první pohled vidět — což je přesně to,
            // co se tímhle krokem ověřuje.
            TimelinePalette.lane(for: track.kind).setFill()
            rect.fill()

            let label = NSAttributedString(string: track.name, attributes: attributes)
            let size = label.size()
            label.draw(at: NSPoint(x: 10, y: y + (height - Double(size.height)) / 2))
        }

        // Předěl proti ploše osy.
        TimelinePalette.separator.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
