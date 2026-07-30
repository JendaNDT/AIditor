//
//  MiniTimeline.swift
//  Projekt AIditor — UI/Fullscreen
//
//  Fáze 18, modul 13. Mini osa u spodní hrany fullscreen náhledu (⇧T nebo
//  myš k dolní hraně) a plovoucí náhled snímku nad kurzorem.
//  Zdroj zadání: `design_handoff_aiditor_ui/README.md`, obrazovka 6, stav `osa`.
//
//  ⚠️ Vlastní mapování CELÉ osy na šířku pásu, ne `TimelineGeometry` — ta je
//  o zoomu a scrollu. Totéž rozhodnutí jako u přehledu osy v modulu 6.
//
//  ⚠️ Miniatury jdou z `ThumbnailStore` (modul 5), ale s VLASTNÍ hranou (40).
//  Klíč mezipaměti nese hranu i měřítko, takže si mini osa a pás na klipech
//  navzájem dlaždice nezahazují — vzorec knihovny médií (M9, hrana 104).
//

import AppKit
import SwiftUI
import TimelineModel

struct MiniTimelineBand: View {
    @ObservedObject var model: AppModel
    @ObservedObject var timeline: TimelineController
    /// Kde je kurzor nad pásem (v bodech od jeho levé hrany). `nil` = mimo.
    @State private var hoverX: Double?

    init(model: AppModel) {
        self.model = model
        self.timeline = model.timeline
    }

    /// Výška pásu osy podle zadání.
    static let stripHeight: CGFloat = 76
    /// Pás miniatur uvnitř.
    static let thumbHeight: CGFloat = 40
    static let audioHeight: CGFloat = 12
    static let beatsHeight: CGFloat = 5

    private var frameRate: Int { timeline.project.timeline.frameRate }

    var body: some View {
        VStack(spacing: 10) {
            header
            strip
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(height: 146, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0), location: 0),
                .init(color: Color.black.opacity(0.55), location: 0.3),
                .init(color: Color.black.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        // Náhled snímku leží NAD pásem, mimo jeho ořez.
        .overlay(alignment: .bottomLeading) {
            if let hoverX, let preview = previewFrame(atX: hoverX) {
                FloatingFramePreview(model: model, frame: preview)
                    .offset(x: max(24, min(hoverX, hoverWidth - 168)), y: -150)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FullscreenTimecode(controller: model.controller,
                               frameRate: frameRate, size: 18)
            Text("osa · ⇧T schová")
                .font(.system(size: 10))
                .foregroundStyle(Color(aiditorHex: 0xC9CCD1))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            Spacer(minLength: 8)
            Text("tažením scrubuješ · ⌥ krok po snímcích"
                 + (hasBeats ? " · klik do doby přiskočí na úder" : ""))
                .font(.system(size: 10))
                .foregroundStyle(AIditorUI.textSecondary)
        }
    }

    /// Šířka pásu se drží pro umístění náhledu snímku — `GeometryReader`
    /// uvnitř by ji ven nedostal.
    @State private var hoverWidth: Double = 0

    private var strip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                MiniThumbStrip(model: model, width: width)
                    .frame(height: Self.thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 6)
                    .padding(.top, 6)

                MiniAudioStrip(model: model, width: width)
                    .frame(height: Self.audioHeight)
                    .padding(.horizontal, 6)
                    .offset(y: 6 + Self.thumbHeight + 4)

                MiniBeats(model: model, width: width - 12)
                    .frame(height: Self.beatsHeight)
                    .padding(.horizontal, 6)
                    .offset(y: 6 + Self.thumbHeight + 4 + Self.audioHeight + 3)

                if let range = rangeFraction {
                    Rectangle()
                        .fill(AIditorUI.accent.opacity(0.18))
                        .frame(width: max(2, (width - 12) * (range.upperBound - range.lowerBound)),
                               height: Self.stripHeight - 12)
                        .overlay(HStack {
                            AIditorUI.accent.frame(width: 1.5)
                            Spacer(minLength: 0)
                            AIditorUI.accent.frame(width: 1.5)
                        })
                        .offset(x: 6 + (width - 12) * range.lowerBound, y: 6)
                        .allowsHitTesting(false)
                }

                AIditorUI.playhead
                    .frame(width: 2, height: Self.stripHeight - 8)
                    .offset(x: 6 + playheadFraction * (width - 12) - 1, y: 4)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: Self.stripHeight)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(aiditorHex: 0x0E0F11, opacity: 0.82)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                hoverWidth = width
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hoverWidth = width
                hoverX = value.location.x
                scrub(toX: value.location.x, width: width)
                model.noteFullscreenMouseActivity(nearBottom: true)
            })
        }
        .frame(height: Self.stripHeight)
    }

    // MARK: - Mapování

    private var total: Double { Double(max(model.totalFrames.count, 1)) }

    private var playheadFraction: Double {
        min(max(Double(timeline.playhead.count) / total, 0), 1)
    }

    private var rangeFraction: ClosedRange<Double>? {
        guard timeline.inPoint != nil || timeline.outPoint != nil else { return nil }
        let range = timeline.exportRange
        let low = min(max(Double(range.lowerBound.count) / total, 0), 1)
        let high = min(max(Double(range.upperBound.count) / total, 0), 1)
        return high > low ? low...high : nil
    }

    private var hasBeats: Bool {
        timeline.layers.beats && !timeline.project.beatMarks().isEmpty
    }

    private func frame(atX x: Double, width: Double) -> Frames {
        let inner = max(width - 12, 1)
        let fraction = min(max((x - 6) / inner, 0), 1)
        return Frames(Int((fraction * total).rounded()))
    }

    private func previewFrame(atX x: Double) -> Frames? {
        guard hoverWidth > 0 else { return nil }
        return frame(atX: x, width: hoverWidth)
    }

    /// Tažení posouvá hlavu. Bez ⌥ se klik přichytí na nejbližší dobu do
    /// šesti bodů — návrh to slibuje a `beatMarks()` na to má data. S ⌥ jde
    /// hlava přesně tam, kam se kliklo (krok po snímcích).
    private func scrub(toX x: Double, width: Double) {
        var target = frame(atX: x, width: width)
        if !NSEvent.modifierFlags.contains(.option), timeline.layers.beats {
            let inner = max(width - 12, 1)
            let tolerance = Frames(Int((6 / inner) * total))
            let marks = timeline.project.beatMarks()
            if let nearest = marks.min(by: {
                abs($0.frame.count - target.count) < abs($1.frame.count - target.count)
            }), abs(nearest.frame.count - target.count) <= tolerance.count {
                target = nearest.frame
            }
        }
        timeline.setPlayheadFromUser(target)
    }
}

// MARK: - Pás miniatur

/// Miniatury přes celou osu. Jedna dlaždice na `40 × 1,5` bodu, obsah se
/// dohledává přes klip pod tím místem — tedy TÝŽ převod, jaký dělá pás na
/// klipech, jen s jiným mapováním osy na body.
private struct MiniThumbStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var thumbnails: ThumbnailStore
    let width: Double

    init(model: AppModel, width: Double) {
        self.model = model
        self.thumbnails = model.timeline.thumbnails
        self.width = width
    }

    private static let side: Double = MiniTimelineBand.thumbHeight
    private var tileWidth: Double { Self.side * ThumbnailStore.tileAspect }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(Int((width - 12) / tileWidth), 1), id: \.self) { index in
                tile(index: index)
                    .frame(width: tileWidth, height: Self.side)
                    .clipped()
            }
            Spacer(minLength: 0)
        }
        .frame(width: max(width - 12, 1), alignment: .leading)
        .background(Color(aiditorHex: 0x101216))
        // Verze roste s každou dopočítanou dlaždicí — bez tohohle by pás
        // zůstal prázdný, dokud se view nepřekreslí z jiného důvodu.
        .id(thumbnails.version)
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        if let image = image(at: index) {
            Image(decorative: image, scale: 1)
                .resizable()
                // ⚠️ `.fill` by nahlásil větší velikost, než dostal (past z M9),
                // proto `.fit` do pevného rámce — dlaždice má poměr 1,5 a slot
                // taky, takže se nic neořezává.
                .aspectRatio(contentMode: .fit)
        } else {
            Color(aiditorHex: 0x1A1D22)
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5))
        }
    }

    private func image(at index: Int) -> CGImage? {
        let total = Double(max(model.totalFrames.count, 1))
        let inner = max(width - 12, 1)
        let center = (Double(index) + 0.5) * tileWidth
        let frame = Frames(Int((min(center / inner, 1) * total).rounded()))
        guard let found = clip(at: frame) else { return nil }
        guard let asset = model.timeline.project.asset(found.assetID) else { return nil }
        let url = asset.proxyURL ?? asset.originalURL
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        if asset.isStill {
            return thumbnails.stillTile(url: url, side: Self.side, scale: scale)
        }
        // ⚠️ `sourceOffset` je na PROJEKTU, ne na `Timeline` — počítá s rampou
        // i s tím, že fotka stojí, a na to potřebuje asset.
        let source = model.timeline.project.sourceOffset(
            in: found, atFrame: Frames(frame.count - found.timelineStart.count))
        // Úroveň se počítá ze zoomu mini osy — táž funkce jako u pásu na
        // klipech, takže se mřížka indexů chová stejně.
        let rung = ThumbnailStore.rung(for: inner / total)
        let seconds = ThumbnailStore.secondsPerTile(rung: rung, side: Self.side)
        let tileIndex = max(Int(source.seconds / max(seconds, 0.0001)), 0)
        return thumbnails.tile(url: url, rung: rung, index: tileIndex,
                               side: Self.side, scale: scale)
    }

    private func clip(at frame: Frames) -> Clip? {
        for track in model.timeline.project.timeline.tracks where track.kind == .video {
            if let clip = track.clips.first(where: { $0.contains(frame: frame) }) { return clip }
        }
        return nil
    }
}

// MARK: - Zvuk a doby

/// Zvukové klipy jako bloky. **Ne vlna:** dlaždice vln jsou klíčované zoomem
/// osy a v mini pásu by to byla další kapsa mezipaměti pro pár pixelů výšky.
/// Přehled osy (M6) kreslí zvuk stejně.
private struct MiniAudioStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var timeline: TimelineController
    let width: Double

    init(model: AppModel, width: Double) {
        self.model = model
        self.timeline = model.timeline
        self.width = width
    }

    var body: some View {
        Canvas { context, size in
            let total = Double(max(model.totalFrames.count, 1))
            for track in timeline.project.timeline.tracks where track.kind == .audio {
                for clip in track.clips {
                    let x = Double(clip.timelineStart.count) / total * size.width
                    let w = max(Double(clip.duration.count) / total * size.width, 1)
                    context.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w,
                                                          height: size.height),
                                      cornerRadius: 2),
                                 with: .color(Color(aiditorHex: 0x2A6950)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MiniBeats: View {
    @ObservedObject var model: AppModel
    @ObservedObject var timeline: TimelineController
    let width: Double

    init(model: AppModel, width: Double) {
        self.model = model
        self.timeline = model.timeline
        self.width = width
    }

    var body: some View {
        Canvas { context, size in
            guard timeline.layers.beats else { return }
            let total = Double(max(model.totalFrames.count, 1))
            for mark in timeline.project.beatMarks() {
                let x = Double(mark.frame.count) / total * size.width
                context.fill(Path(CGRect(x: x, y: mark.isDownbeat ? 0 : size.height * 0.35,
                                         width: 1,
                                         height: mark.isDownbeat ? size.height
                                                                 : size.height * 0.65)),
                             with: .color(AIditorUI.warn.opacity(mark.isDownbeat ? 0.9 : 0.5)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Plovoucí náhled snímku

/// Snímek 192×108 nad kurzorem s timecodem. Bere se z `ThumbnailStore`, tedy
/// z proxy, když je — a proto je okamžitý; dokud dlaždice nedorazí, je tam
/// prázdné místo, ne vymyšlený obrázek.
private struct FloatingFramePreview: View {
    @ObservedObject var model: AppModel
    @ObservedObject var thumbnails: ThumbnailStore
    let frame: Frames

    init(model: AppModel, frame: Frames) {
        self.model = model
        self.thumbnails = model.timeline.thumbnails
        self.frame = frame
    }

    private static let side: Double = 108

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(aiditorHex: 0x44525D),
                                                  Color(aiditorHex: 0x181C22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let image = image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 192, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.55), radius: 15, y: 14)

            Text(Timecode(frame, frameRate: model.timeline.project.timeline.frameRate).text)
                .font(AIditorUI.Font.monoSmall)
                .foregroundStyle(AIditorUI.textPrimary)
        }
        .id(thumbnails.version)
    }

    private var image: CGImage? {
        let timeline = model.timeline.project.timeline
        var found: Clip?
        for track in timeline.tracks where track.kind == .video {
            if let clip = track.clips.first(where: { $0.contains(frame: frame) }) {
                found = clip
                break
            }
        }
        guard let clip = found,
              let asset = model.timeline.project.asset(clip.assetID) else { return nil }
        let url = asset.proxyURL ?? asset.originalURL
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        if asset.isStill {
            return thumbnails.stillTile(url: url, side: Self.side, scale: scale)
        }
        let source = model.timeline.project.sourceOffset(
            in: clip, atFrame: Frames(frame.count - clip.timelineStart.count))
        // Nejjemnější mřížka, jakou store nabízí: náhled má ukázat snímek
        // z místa pod kurzorem, ne z okolí.
        let rung: Double = 8
        let seconds = ThumbnailStore.secondsPerTile(rung: rung, side: Self.side)
        let index = max(Int(source.seconds / max(seconds, 0.0001)), 0)
        return thumbnails.tile(url: url, rung: rung, index: index,
                               side: Self.side, scale: scale)
    }
}
