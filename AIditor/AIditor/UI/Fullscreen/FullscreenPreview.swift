//
//  FullscreenPreview.swift
//  Projekt AIditor — UI/Fullscreen
//
//  Fáze 18, modul 13. Fullscreen náhled: obraz přes celou obrazovku a tři
//  stavy overlaye (`čistý / ovládání / osa`).
//  Zdroj zadání: `design_handoff_aiditor_ui/README.md`, obrazovka 6.
//
//  ⚠️ TÁŽ hierarchie, jen bez chrome. Náhled není druhé okno ani druhý
//  přehrávač — `AppShell` z sebe odebere toolbar, rail, lišty i osu a
//  `ViewerPane` dostane celou plochu. Vzorec `chromeHidden` z modulu 1:
//  kdyby se přepínala celá větev, SwiftUI by `PlayerView` přetvořil a vznikl
//  by nový `PlayerHostView` — přesně to, kvůli čemu má `PlayerView` dodnes
//  `onHostView` i v `updateNSView`.
//
//  ⚠️ Co tepe 30×/s, má VLASTNÍ view. Timecode, scrub lišta a transport se
//  hýbou s každým snímkem přehrávání; kdyby seděly v těle celého overlaye,
//  překresloval by se s nimi i horní pruh, čipy a mini osa (vzorec
//  `TransportPill` z modulu 1).
//

import AppKit
import SwiftUI
import TimelineModel

struct FullscreenPreviewOverlay: View {
    @ObservedObject var model: AppModel

    private var overlay: AppModel.FullscreenOverlay { model.fullscreenOverlay }

    var body: some View {
        ZStack {
            // Sledovač myši leží pod vším a nic nechytá — jen hlásí pohyb.
            FullscreenMouseWatcher(model: model)

            if overlay == .clean {
                cleanCapsule
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 22)
                    .padding(.top, 58)
            }

            if overlay == .controls {
                topBand
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                FullscreenControls(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if overlay == .timeline {
                MiniTimelineBand(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            shortcuts
        }
        // 150 ms ease-out podle zadání. Animuje se jen průhlednost stavů,
        // ne rozměry — layout se ve fullscreenu nesmí hýbat pod myší.
        .animation(.easeOut(duration: 0.15), value: model.fullscreenOverlay)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Čistý stav

    private var cleanCapsule: some View {
        HStack(spacing: 8) {
            FullscreenTimecode(controller: model.controller,
                               frameRate: model.timeline.project.timeline.frameRate,
                               size: 12)
            Color.white.opacity(0.25).frame(width: 1, height: 12)
            Text("⎋ zpět do editoru")
                .font(.system(size: 10))
                .foregroundStyle(Color(aiditorHex: 0xC9CCD1))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .opacity(0.5)
    }

    // MARK: - Horní pruh

    private var topBand: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.projectStore.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AIditorUI.textPrimary)
                Text(clipLine)
                    .font(.system(size: 11))
                    .foregroundStyle(AIditorUI.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                if model.timeline.project.usesProxies {
                    chip("Proxy 1/2", color: Color(aiditorHex: 0xC9CCD1))
                }
                if let grade = gradeText {
                    chip(grade, color: Color(aiditorHex: 0xFFD88A))
                }
                if let loudness = model.lastLoudness {
                    chip(AppModel.decimal(loudness.lufs) + " LUFS",
                         color: AIditorUI.textSecondary, mono: true)
                }
                Text("⎋ zpět")
                    .font(.system(size: 10))
                    .foregroundStyle(AIditorUI.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.10)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .frame(height: 112, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.72), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func chip(_ text: String, color: Color, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? AIditorUI.Font.monoSmall : .system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
    }

    /// Co je pod hlavou — ne co je vybrané. V náhledu se člověk dívá na obraz,
    /// takže popisek musí mluvit o tom, co vidí; vybraný klip může být jinde.
    private var clipUnderPlayhead: (clip: Clip, track: Track)? {
        let timeline = model.timeline.project.timeline
        let frame = model.timeline.playhead
        for track in timeline.tracks where track.kind == .video {
            if let clip = track.clips.first(where: { $0.contains(frame: frame) }) {
                return (clip, track)
            }
        }
        return nil
    }

    private var clipLine: String {
        guard let found = clipUnderPlayhead else { return "mezera na ose" }
        var parts: [String] = []
        if let asset = model.timeline.project.asset(found.clip.assetID) {
            parts.append(asset.originalURL.lastPathComponent)
        }
        parts.append(found.track.name)
        if let ramp = found.clip.speedRamp, let slowest = ramp.nodes.map(\.speed).min() {
            parts.append("rampa 1× → " + AppModel.decimal(slowest, places: 2) + "×")
        }
        return parts.joined(separator: " · ")
    }

    private var gradeText: String? {
        guard let grade = clipUnderPlayhead?.clip.colorGrade else { return nil }
        return "\(grade.preset.displayName) \(Int((grade.intensity * 100).rounded())) %"
    }

    // MARK: - Klávesy

    /// Zkratky náhledu. Tlačítka bez plochy — v hierarchii jsou jen po dobu
    /// náhledu, takže ⎋ ani mezerník nikde jinde nic nepřebíjejí. (Osa své
    /// klávesy obsluhuje v `keyDown`, ale ta ve fullscreenu v hierarchii není.)
    private var shortcuts: some View {
        ZStack {
            Button("") { model.exitPreviewFullscreen() }
                .keyboardShortcut(.cancelAction)
            Button("") { model.toggleFullscreenTimeline() }
                .keyboardShortcut("t", modifiers: .shift)
            Button("") { model.controller.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { _ = model.controller.shuttle(.backward) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { _ = model.controller.shuttle(.pause) }
                .keyboardShortcut("k", modifiers: [])
            Button("") { _ = model.controller.shuttle(.forward) }
                .keyboardShortcut("l", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Sledovač myši

/// Hlásí pohyb myši a to, jestli je kurzor u spodní hrany. AppKit, protože
/// `NSTrackingArea` je jediná cesta, jak se o pohybu dozvědět bez klikání —
/// SwiftUI `onHover` říká jen „uvnitř / venku", ne kde.
///
/// ⚠️ `hitTest` vrací `nil`: sledovač leží přes celou plochu a nesmí brát
/// kliknutí tlačítkům overlaye. Sledovací oblasti se hit testem neřídí — jsou
/// registrované u okna a `mouseMoved` chodí vlastníkovi oblasti. Že to platí
/// i tady, ověřuje `--fullscreen-ui-check` (počet oblastí a jejich volby).
///
/// <https://developer.apple.com/documentation/appkit/nstrackingarea>
struct FullscreenMouseWatcher: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> MouseWatchView {
        let view = MouseWatchView()
        view.onMove = { [weak model] nearBottom in
            model?.noteFullscreenMouseActivity(nearBottom: nearBottom)
        }
        model.attachMouseWatcher(view)
        return view
    }

    func updateNSView(_ nsView: MouseWatchView, context: Context) {}
}

final class MouseWatchView: NSView {

    /// Pruh u spodní hrany, ve kterém návrh chce mini osu.
    static let bottomBandHeight: CGFloat = 60

    var onMove: ((Bool) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // `isFlipped` je false, takže počátek je vlevo DOLE: „u spodní hrany"
        // znamená malé `y`.
        onMove?(point.y <= Self.bottomBandHeight)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }
}

// MARK: - Timecode

/// Vlastní view, protože se mění 30×/s. Zbytek overlaye se s ním překreslovat
/// nesmí (vzorec `TransportPill`).
struct FullscreenTimecode: View {
    @ObservedObject var controller: PlaybackController
    let frameRate: Int
    var size: CGFloat = 22

    var body: some View {
        Text(text)
            .font(.system(size: size, design: .monospaced))
            .foregroundStyle(AIditorUI.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private var text: String {
        let time = controller.currentTime
        guard time.isValid, time.seconds.isFinite, time.seconds >= 0 else { return "—" }
        let frame = Frames(Int((time.seconds * Double(frameRate)).rounded()))
        return Timecode(frame, frameRate: frameRate).text
    }

    /// ⚠️ Návrh dává timecodu 132 bodů, jenže to je šířka z prototypu v HTML.
    /// SF Mono 22 potřebuje na `00:00:04:04` ~150 a zbytek si zalomí na druhý
    /// řádek — chytil to snímek okna, čísla o tom nic nevědí. Držíme tedy
    /// ČÍSLO Z NÁVRHU jako minimum a necháváme písmo rozhodnout o zbytku.
    static let width: CGFloat = 160
}

// MARK: - Dolní pruh ovládání

private struct FullscreenControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var timeline: TimelineController

    init(model: AppModel) {
        self.model = model
        self.timeline = model.timeline
    }

    private var frameRate: Int { timeline.project.timeline.frameRate }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                FullscreenTimecode(controller: model.controller, frameRate: frameRate)
                    .frame(width: FullscreenTimecode.width, alignment: .leading)
                FullscreenScrubBar(model: model)
                    .frame(height: 26)
                Text(remainingText)
                    .font(AIditorUI.Font.monoSmall)
                    .foregroundStyle(AIditorUI.textSecondary)
                    .frame(width: 96, alignment: .trailing)
            }

            HStack(spacing: 16) {
                rangeChips
                Spacer(minLength: 8)
                transport
                Spacer(minLength: 8)
                trailingButtons
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(height: 168, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: Výřez

    /// Body výřezu se ukazují, jen když existují — „nic nevybráno" a „vybráno
    /// vše" nesmí vypadat stejně (pravidlo fáze 17).
    private var rangeChips: some View {
        HStack(spacing: 10) {
            if let inPoint = timeline.inPoint {
                pill("I " + Self.shortTime(inPoint, frameRate: frameRate))
            }
            if let outPoint = timeline.outPoint {
                pill("O " + Self.shortTime(outPoint, frameRate: frameRate))
            }
            if timeline.inPoint == nil && timeline.outPoint == nil {
                Text("bez výřezu · I a O ho staví na ose")
                    .font(.system(size: 10))
                    .foregroundStyle(AIditorUI.textTertiary)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            glyph("J") { _ = model.controller.shuttle(.backward) }
            glyph("◀") { model.controller.step(frames: -1) }

            Button {
                model.controller.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Color(aiditorHex: 0xF2F3F5))
                    Image(systemName: model.controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(aiditorHex: 0x111315))
                }
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)

            glyph("▶") { model.controller.step(frames: 1) }
            glyph("L") { _ = model.controller.shuttle(.forward) }

            // Oranžová je vyhrazená krokovacímu fallbacku — přiznaná mez
            // zpětného přehrávání z fáze 17, ne ozdoba.
            if model.controller.shuttleRate != 0 {
                Text(model.controller.shuttleDescription)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.controller.isSteppingFallback
                                     ? AIditorUI.warn : AIditorUI.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(model.controller.isSteppingFallback
                              ? AIditorUI.warn.opacity(0.16) : Color.white.opacity(0.08)))
            }
        }
    }

    private var trailingButtons: some View {
        HStack(spacing: 10) {
            Button { model.previewSubtitles.toggle() } label: {
                pill("Titulky " + (model.previewSubtitles ? "✓" : "—"))
            }
            .buttonStyle(.plain)
            Button { model.toggleFullscreenTimeline() } label: {
                pill("Osa ⇧T")
            }
            .buttonStyle(.plain)
        }
    }

    private func glyph(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(aiditorHex: 0xC9CCD1))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(aiditorHex: 0xC9CCD1))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private var remainingText: String {
        let total = model.totalFrames
        let position = min(timeline.playhead, total)
        let left = Frames(max(0, total.count - position.count))
        return "−" + Timecode(left, frameRate: frameRate).text
    }

    static func shortTime(_ frame: Frames, frameRate: Int) -> String {
        let seconds = frame.count / max(frameRate, 1)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Scrub lišta

/// Lišta pod timecodem: přehraná část, výřez, doby a úchyt hlavy.
///
/// ⚠️ Délka filmu se bere z `model.totalFrames`, ne z `project.duration` —
/// ta je O(klipů) a tohle view se překresluje s každým snímkem přehrávání
/// (past z modulu 6).
private struct FullscreenScrubBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var timeline: TimelineController

    init(model: AppModel) {
        self.model = model
        self.timeline = model.timeline
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = Double(max(model.totalFrames.count, 1))
            let progress = Double(timeline.playhead.count) / total

            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.18)
                    .frame(height: 4)
                    .clipShape(Capsule())
                    .offset(y: 11)

                AIditorUI.playhead
                    .frame(width: max(0, width * progress), height: 4)
                    .clipShape(Capsule())
                    .offset(y: 11)

                if let range = rangeFraction {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AIditorUI.accent.opacity(0.28))
                        .frame(width: max(2, width * (range.upperBound - range.lowerBound)),
                               height: 10)
                        .overlay(HStack {
                            AIditorUI.accent.frame(width: 2)
                            Spacer(minLength: 0)
                            AIditorUI.accent.frame(width: 2)
                        })
                        .offset(x: width * range.lowerBound, y: 8)
                }

                // Doby hudby. Kreslí se jen když mřížka existuje — `beatMarks()`
                // je bez ní okamžitý early-out přes assety.
                BeatTicks(marks: beatFractions, width: width)
                    .offset(y: 19)

                RoundedRectangle(cornerRadius: 2)
                    .fill(AIditorUI.playhead)
                    .frame(width: 4, height: 18)
                    .shadow(color: AIditorUI.playhead.opacity(0.2), radius: 0)
                    .offset(x: max(0, width * progress - 2), y: 4)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                let frame = Frames(Int((fraction * total).rounded()))
                timeline.setPlayheadFromUser(frame)
                model.noteFullscreenMouseActivity(nearBottom: false)
            })
        }
    }

    private var rangeFraction: ClosedRange<Double>? {
        guard timeline.inPoint != nil || timeline.outPoint != nil else { return nil }
        let total = Double(max(model.totalFrames.count, 1))
        let range = timeline.exportRange
        let low = min(max(Double(range.lowerBound.count) / total, 0), 1)
        let high = min(max(Double(range.upperBound.count) / total, 0), 1)
        guard high > low else { return nil }
        return low...high
    }

    private var beatFractions: [Double] {
        guard timeline.layers.beats else { return [] }
        let total = Double(max(model.totalFrames.count, 1))
        return timeline.project.beatMarks().map { Double($0.frame.count) / total }
    }
}

/// Rysky dob. Vlastní `Canvas`, ne stovka `Rectangle`ů: na tříminutové skladbě
/// je dob přes čtyři sta a každá jako view by z lišty udělala nejdražší kus
/// overlaye.
private struct BeatTicks: View {
    let marks: [Double]
    let width: Double

    var body: some View {
        Canvas { context, size in
            for fraction in marks {
                let x = fraction * width
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                             with: .color(AIditorUI.warn.opacity(0.5)))
            }
        }
        .frame(height: 6)
        .allowsHitTesting(false)
    }
}
