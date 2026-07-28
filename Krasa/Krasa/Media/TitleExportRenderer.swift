//
//  TitleExportRenderer.swift
//  Projekt Krása
//
//  Vypálení grafických titulků do exportu (fáze 11, modul 4).
//
//  ⚠️ Plán předepisoval `AVVideoCompositionCoreAnimationTool` — NEPOUŽÍVÁ SE,
//  a je to rozhodnutí, ne opomenutí. Ten nástroj je dokumentovaný pro
//  `AVAssetExportSession` („Export: add animation to a video with an export
//  session"), kterou tenhle projekt schválně nepoužívá (ignoruje
//  `frameDuration` — proto celý `CFRRenderer`). Jeho chování na cestě
//  `AVAssetReader` + `AVAssetWriter` dokumentace nepopisuje, a stavět export
//  na nedokumentovaném chování je přesně chyba z pravidla 6.
//  <https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool>
//
//  Místo toho: `CFRRenderer` dostal `frameDecorator` a tahle třída v něm
//  přimíchá předrenderovaný titulkový obraz nad snímky, kde titulek opravdu
//  leží. Snímky bez titulku projdou bajt po bajtu nedotčené — ověřená
//  exportní cesta (kolísání 0,0 %, CFR) se jich ani nedotkne.
//
//  Typografie MUSÍ zrcadlit `TitleOverlay` v náhledu (velikosti jako zlomky
//  výšky plátna, patková jména přes střed, prostý text v dolní třetině,
//  stín místo desky) — „co vidíš v náhledu, to dostaneš v souboru".
//

import AppKit
import CoreImage
import TimelineModel

/// Použití: jedna instance na jeden export; dekorátor běží sériově z fronty
/// zapisovače (`cfr.video`), proto `@unchecked Sendable` — stav (mezipaměť
/// overlay obrazu, pool bufferů) se dotýká jen z toho jednoho vlákna.
final class TitleExportRenderer: @unchecked Sendable {

    private let cues: [TitleCue]
    private let canvas: CGSize
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?

    /// Overlay se renderuje jednou na BĚH (úsek osy se stejnou množinou
    /// aktivních titulků), ne na snímek — titulky jsou statické.
    private var cachedActive: [TitleCue] = []
    private var cachedOverlay: CIImage?

    /// `nil`, když projekt žádné titulky nemá — volající pak dekorátor
    /// vůbec nezapojí a export je beze změny.
    init?(cues: [TitleCue], canvas: CGSize) {
        guard !cues.isEmpty, canvas.width > 0, canvas.height > 0 else { return nil }
        self.cues = cues
        self.canvas = canvas
    }

    /// Dekorátor pro `CFRRenderer.render(frameDecorator:)`.
    func decorator() -> @Sendable (CVPixelBuffer, Int) -> CVPixelBuffer {
        { [self] buffer, slot in decorate(buffer, slot: slot) }
    }

    // MARK: - Kompozice snímku

    private func decorate(_ buffer: CVPixelBuffer, slot: Int) -> CVPixelBuffer {
        let frame = Frames(slot)
        let active = cues.filter { $0.start <= frame && frame < $0.end }
        guard !active.isEmpty,
              let overlay = overlayImage(for: active),
              let output = makeBuffer(like: buffer) else { return buffer }

        let base = CIImage(cvPixelBuffer: buffer)
        context.render(overlay.composited(over: base), to: output,
                       bounds: CGRect(origin: .zero, size: canvas),
                       colorSpace: CGColorSpace(name: CGColorSpace.itur_709)
                           ?? CGColorSpaceCreateDeviceRGB())
        return output
    }

    /// Nový buffer stejného formátu jako vstup. Barevné atributy (matice,
    /// primárky) se PŘENÁŠEJÍ — zapisovač by jinak u dekorovaných snímků
    /// předpokládal výchozí a titulené úseky by barevně uskočily.
    private func makeBuffer(like buffer: CVPixelBuffer) -> CVPixelBuffer? {
        if pool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    CVPixelBufferGetPixelFormatType(buffer),
                kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(buffer),
                kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(buffer),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess,
              let out else { return nil }
        if let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) {
            CVBufferSetAttachments(out, attachments, .shouldPropagate)
        }
        return out
    }

    // MARK: - Rasterizace overlay obrazu

    private func overlayImage(for active: [TitleCue]) -> CIImage? {
        if active == cachedActive { return cachedOverlay }
        cachedActive = active
        cachedOverlay = rasterize(active).map { CIImage(cgImage: $0) }
        return cachedOverlay
    }

    /// Nakreslí aktivní titulky do průhledného obrazu velikosti plátna.
    /// Souřadnice jsou CG (počátek vlevo DOLE) — stejně je orientovaný
    /// `CIImage` z pixel bufferu, takže se nic nepřevrací.
    private func rasterize(_ active: [TitleCue]) -> CGImage? {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = previous }

        let h = canvas.height
        // Stín zrcadlí overlay náhledu (radius h*0,008, posun 1 bod) —
        // převedeno na plátno; posun dolů je v CG soustavě záporné y.
        ctx.setShadow(offset: CGSize(width: 0, height: -h * 0.0025),
                      blur: h * 0.016,
                      color: NSColor.black.withAlphaComponent(0.65).cgColor)

        let padding = canvas.width * 0.02
        let boxWidth = canvas.width - 2 * padding

        // Středové šablony pod sebou v pořadí cues (jména navrchu),
        // prostý text v dolní třetině — přesně jako `TitleOverlay`.
        let centered = active.filter { $0.template != .plain }
        let plain = active.filter { $0.template == .plain }

        func draw(_ group: [TitleCue], spacing: CGFloat, centerY: CGFloat?,
                  bottomY: CGFloat?) {
            guard !group.isEmpty else { return }
            let rendered: [(NSAttributedString, CGRect)] = group.map { cue in
                let text = attributed(cue)
                let bounds = text.boundingRect(
                    with: CGSize(width: boxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin])
                return (text, bounds)
            }
            let totalHeight = rendered.reduce(0) { $0 + $1.1.height }
                + spacing * CGFloat(rendered.count - 1)
            // `top` = horní hrana skupiny v CG souřadnicích (y roste nahoru).
            var top = centerY.map { $0 + totalHeight / 2 }
                ?? (bottomY! + totalHeight)
            for (text, bounds) in rendered {
                let rect = CGRect(x: padding, y: top - bounds.height,
                                  width: boxWidth, height: bounds.height)
                text.draw(with: rect, options: [.usesLineFragmentOrigin])
                top -= bounds.height + spacing
            }
        }

        draw(centered, spacing: h * 0.02, centerY: h / 2, bottomY: nil)
        draw(plain, spacing: h * 0.015, centerY: nil, bottomY: h * 0.18)

        return ctx.makeImage()
    }

    private func attributed(_ cue: TitleCue) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        switch cue.alignment {
        case .leading: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        }
        return NSAttributedString(string: cue.text, attributes: [
            .font: font(for: cue.template),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    /// Tytéž zlomky výšky a řezy jako `TitleOverlay` — jediný zdroj vzhledu
    /// šablon jsou tyhle dvě funkce a musí se měnit spolu.
    private func font(for template: TitleTemplate) -> NSFont {
        let h = canvas.height
        let size: CGFloat
        let weight: NSFont.Weight
        var serif = true
        switch template {
        case .names:        size = h * 0.105; weight = .semibold
        case .chapter:      size = h * 0.065; weight = .medium
        case .thanks:       size = h * 0.060; weight = .regular
        case .dateAndPlace: size = h * 0.045; weight = .regular
        case .plain:        size = h * 0.045; weight = .medium; serif = false
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard serif,
              let descriptor = base.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }
}
