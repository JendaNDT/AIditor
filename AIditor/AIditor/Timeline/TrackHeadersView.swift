//
//  TrackHeadersView.swift
//  Projekt AIditor
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

    /// Šířka podle návrhu (fáze 18, modul 4) — dřív 96. Osm bodů navíc
    /// nese meta řádek („obraz · 5 klipů") pod jménem stopy.
    static let width: CGFloat = 104

    private let controller: TimelineController

    /// Ovládání zvukové stopy. Klíčem je TrackID — sada stop je zatím
    /// pevná (V1+A1+A2), ale slovník přežije i budoucí přidávání stop.
    private struct AudioControls {
        let mute: NSButton
        let slider: NSSlider
        /// Hlasitost v decibelech. Lineární 0–1 nikomu nic neřekne;
        /// „−4,0 dB" je údaj, se kterým se dá pracovat.
        let readout: NSTextField
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

    private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let metaFont = NSFont.systemFont(ofSize: 9)

    /// Co stopa nese. Počet klipů se BERE z projektu, nedomýšlí — u obrazu
    /// je to nejužitečnější údaj v hlavičce, protože po hromadných operacích
    /// je hned vidět, jestli se stalo, co mělo.
    private static func metaText(for track: Track) -> String {
        switch track.kind {
        case .video:
            return "obraz · \(track.clips.count) \(clipWord(track.clips.count))"
        case .audio:
            // A1 nese řeč (svázaný zvuk klipů), A2 hudbu — pořadí je
            // konvence projektu od fáze 2, ne vlastnost modelu, takže se
            // odvozuje z JMÉNA, ne z indexu.
            return track.name.hasSuffix("2") ? "hudba" : "řeč"
        case .title:
            return "titulky"
        }
    }

    /// „1 klip / 2 klipy / 5 klipů" — česky se to bez toho nedá napsat.
    private static func clipWord(_ count: Int) -> String {
        switch count {
        case 1: return "klip"
        case 2, 3, 4: return "klipy"
        default: return "klipů"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        TimelinePalette.chrome.setFill()
        bounds.fill()

        let geometry = controller.geometry
        let timeline = controller.project.timeline

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: TimelinePalette.text,
        ]
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.metaFont,
            .foregroundColor: TimelinePalette.headerMeta,
        ]

        for (index, track) in timeline.tracks.enumerated() {
            let y = geometry.y(ofTrackAt: index, in: timeline) - scrollY
            let height = geometry.height(of: track.kind)
            let rect = NSRect(x: 0, y: y, width: Double(bounds.width), height: height)

            guard rect.intersects(bounds) else { continue }

            // Řádek je KARTA se zaoblením jen vpravo (návrh: radius 0 7 7 0) —
            // vlevo přiléhá k hraně okna, tam by zaoblení dělalo jen díru.
            // Barva `surfaceRow`, ne barva pruhu: hlavička je ovládání,
            // pruh je obsah. Že spolu svisle sedí, se pozná z toho, že
            // jméno stojí vedle svých klipů — na to nemusí být stejné.
            TimelinePalette.headerRow.setFill()
            let card = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            card.appendRect(NSRect(x: rect.minX, y: rect.minY,
                                   width: 7, height: rect.height))
            card.fill()

            let label = NSAttributedString(string: track.name, attributes: attributes)
            // Jméno vždy nahoře, meta pod ním. Dřív bylo u obrazu na středu
            // a u zvuku nahoře — se stopou vysokou 136 bodů by jméno V1
            // plavalo v prázdnu doprostřed a nebylo by u čeho.
            label.draw(at: NSPoint(x: 9, y: y + 5))

            let meta = NSAttributedString(string: Self.metaText(for: track),
                                          attributes: metaAttributes)
            meta.draw(at: NSPoint(x: 9, y: y + 5 + Double(label.size().height) + 1))
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
            controls.readout.removeFromSuperview()
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
            controls.readout.stringValue = audio.isMuted
                ? "ztlumeno"
                : Self.decibels(audio.volume)
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

        let readout = NSTextField(labelWithString: "")
        readout.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        readout.textColor = TimelinePalette.headerMeta
        readout.alignment = .right
        addSubview(readout)

        return AudioControls(mute: mute, slider: slider, readout: readout)
    }

    private func layoutControls() {
        let geometry = controller.geometry
        let timeline = controller.project.timeline
        for (index, track) in timeline.tracks.enumerated() {
            guard let controls = audioControls[track.id] else { continue }
            let y = geometry.y(ofTrackAt: index, in: timeline) - scrollY
            let height = geometry.height(of: track.kind)
            let rowBottom = y + height
            controls.mute.frame = NSRect(x: 6, y: rowBottom - 24, width: 22, height: 16)
            controls.slider.frame = NSRect(x: 32, y: rowBottom - 24,
                                           width: Double(bounds.width) - 42, height: 16)
            controls.readout.frame = NSRect(x: 6, y: rowBottom - 42,
                                           width: Double(bounds.width) - 12, height: 12)
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

    /// Lineární hlasitost v decibelech. Nula je `−∞`, ne „0 dB" — to by
    /// znamenalo plnou hlasitost a plete se to i lidem, kteří to vědí.
    private static func decibels(_ volume: Double) -> String {
        guard volume > 0.0001 else { return "−∞ dB" }
        return String(format: "%+.1f dB", 20 * log10(volume))
            .replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: "-", with: "−")
    }

    private func trackID(of match: (AudioControls) -> Bool) -> TrackID? {
        audioControls.first(where: { match($0.value) })?.key
    }
}
