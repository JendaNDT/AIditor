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
//  Fáze 7, modul 2: zvukové stopy mají mute a posuvník hlasitosti.
//  Ovládání jsou normální AppKit subviews (žádné vlastní kreslení stavů),
//  pozicované ručně podle geometrie a scrollY — auto layout tu nemá co
//  synchronizovat s CALayer pruhy osy.
//

import AppKit
import TimelineModel

final class TrackHeadersView: NSView {

    static let width: CGFloat = 96

    private let controller: TimelineController

    /// Ovládání zvukové stopy. Klíčem je TrackID — sada stop je zatím
    /// pevná (V1+A1+A2), ale slovník přežije i budoucí přidávání stop.
    private struct AudioControls {
        let mute: NSButton
        let slider: NSSlider
    }
    private var audioControls: [TrackID: AudioControls] = [:]
    /// Probíhá tažení posuvníku — nepřepisovat mu hodnotu z modelu,
    /// poskakoval by pod myší.
    private var isDraggingVolume = false

    /// Svislý posun plochy osy. Píše ho `TimelinePane` z notifikace.
    var scrollY: Double = 0 {
        didSet {
            if scrollY != oldValue {
                needsDisplay = true
                layoutControls()
            }
        }
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
            // Zvuková stopa: jméno nahoře, pod ním ovládání mixu.
            let labelY = track.kind == .audio
                ? y + 3
                : y + (height - Double(size.height)) / 2
            label.draw(at: NSPoint(x: 10, y: labelY))
        }

        // Předěl proti ploše osy.
        TimelinePalette.separator.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    // MARK: - Ovládání mixu (fáze 7, modul 2)

    /// Srovná sadu ovládacích prvků s projektem a promítne hodnoty
    /// z modelu. Volá `TimelinePane.reload()` — tedy po každé změně
    /// projektu včetně undo.
    func reloadControls() {
        let audioTracks = controller.project.timeline.tracks.filter { $0.kind == .audio }

        for (trackID, controls) in audioControls
        where !audioTracks.contains(where: { $0.id == trackID }) {
            controls.mute.removeFromSuperview()
            controls.slider.removeFromSuperview()
            audioControls[trackID] = nil
        }

        for track in audioTracks {
            let controls = audioControls[track.id] ?? makeControls()
            audioControls[track.id] = controls
            let audio = track.audio ?? AudioSettings()
            controls.mute.state = audio.isMuted ? .on : .off
            if !isDraggingVolume {
                controls.slider.doubleValue = audio.volume
            }
            controls.slider.toolTip = "Hlasitost \(track.name): \(Int(audio.volume * 100)) %"
        }
        layoutControls()
    }

    private func makeControls() -> AudioControls {
        let mute = NSButton(title: "M", target: self, action: #selector(muteToggled(_:)))
        mute.setButtonType(.pushOnPushOff)
        mute.bezelStyle = .accessoryBar   // zapnuto = ztmavené, hotový vzhled
        mute.controlSize = .mini
        mute.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        mute.toolTip = "Ztlumit stopu"
        addSubview(mute)

        let slider = NSSlider(value: 1.0,
                              minValue: Project.trackVolumeRange.lowerBound,
                              maxValue: Project.trackVolumeRange.upperBound,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .mini
        addSubview(slider)

        return AudioControls(mute: mute, slider: slider)
    }

    private func layoutControls() {
        let geometry = controller.geometry
        let timeline = controller.project.timeline
        for (index, track) in timeline.tracks.enumerated() {
            guard let controls = audioControls[track.id] else { continue }
            let y = geometry.y(ofTrackAt: index, in: timeline) - scrollY
            let height = geometry.height(of: track.kind)
            let rowBottom = y + height
            controls.mute.frame = NSRect(x: 6, y: rowBottom - 21, width: 24, height: 16)
            controls.slider.frame = NSRect(x: 34, y: rowBottom - 21,
                                           width: Double(bounds.width) - 44, height: 16)
        }
    }

    override func layout() {
        super.layout()
        layoutControls()
    }

    @objc private func muteToggled(_ sender: NSButton) {
        guard let trackID = trackID(of: { $0.mute === sender }) else { return }
        controller.setTrackMuted(trackID, muted: sender.state == .on)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        guard let trackID = trackID(of: { $0.slider === sender }) else { return }
        // Tažení myší = jedna interakce (jeden undo krok); změna klávesnicí
        // přijde jako osamocená událost a zabalí se do interakce hned.
        let eventType = NSApp.currentEvent?.type
        if !isDraggingVolume {
            isDraggingVolume = true
            controller.volumeDragBegan()
        }
        controller.volumeDragChanged(trackID, volume: sender.doubleValue)
        if eventType != .leftMouseDown && eventType != .leftMouseDragged {
            isDraggingVolume = false
            controller.volumeDragEnded()
        }
    }

    private func trackID(of match: (AudioControls) -> Bool) -> TrackID? {
        audioControls.first(where: { match($0.value) })?.key
    }
}
