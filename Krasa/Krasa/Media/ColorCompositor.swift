//
//  ColorCompositor.swift
//  Projekt Krása
//
//  Barevné presety v kompozici (fáze 13, modul 2).
//
//  Proč vlastní compositor: `init(asset:applyingCIFiltersWithHandler:)`
//  filtruje jen PRVNÍ zapnutou video stopu assetu — naše kompozice má od
//  fáze 10 víc drah (A/B rozklad prolínaček), staví si vlastní instrukce
//  (zahodila by naše rampy i aspect-fit) a `frameDuration` si bere
//  z `nominalFrameRate`, o kterém máme změřeno, že lže. Vlastní compositor
//  naopak dostává instrukce kompozice a per snímek snímky VŠECH stop.
//  <https://developer.apple.com/documentation/avfoundation/avvideocompositing>
//  <https://developer.apple.com/documentation/avfoundation/avasynchronousvideocompositionrequest>
//
//  Instrukce je VLASTNÍ objekt (`AVVideoCompositionInstructionProtocol`),
//  ne podtřída `AVMutableVideoCompositionInstruction` — player item si
//  video kompozici KOPÍRUJE a u podtřídy by kopie prošla přes NSCopying
//  rodiče, který o přidaných polích nic neví. Protokolové instrukce se
//  držejí referencí (kopírovat je AVFoundation neumí), data přežijí.
//  <https://developer.apple.com/documentation/avfoundation/avvideocompositioninstructionprotocol>
//
//  Data instrukce počítá `CompositionBuilder.computeSpans` — TÁŽ funkce,
//  ze které se bez presetů emitují standardní instrukce. Sémantika obou
//  cest má jediný zdroj; tenhle soubor ji jen přehrává v CoreImage.
//

import AVFoundation
import CoreImage
import TimelineModel

// MARK: - Instrukce

/// Jeden úsek osy: vrstvy odpředu dozadu, s krajními hodnotami transformace
/// a průhlednosti (uvnitř úseku se interpolují lineárně — stejně, jako to
/// dělá vestavěný kompozitor s rampami standardních instrukcí).
final class ColorCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {

    struct Layer {
        let trackID: CMPersistentTrackID
        let transformStart: CGAffineTransform
        let transformEnd: CGAffineTransform
        let opacityStart: Float
        let opacityEnd: Float
        let grade: ColorGrade?
    }

    let timeRange: CMTimeRange
    /// Odpředu dozadu (první překrývá ostatní) — pořadí z `computeSpans`.
    let layers: [Layer]
    /// Barva pozadí zatmívačky; `nil` = černá.
    let background: CGColor?

    var enablePostProcessing: Bool { false }
    var containsTweening: Bool { true }
    var requiredSourceTrackIDs: [NSValue]? { layers.map { NSNumber(value: $0.trackID) } }
    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    init(timeRange: CMTimeRange, layers: [Layer], background: CGColor?) {
        self.timeRange = timeRange
        self.layers = layers
        self.background = background
    }
}

// MARK: - Compositor

/// Vykreslí `ColorCompositionInstruction` přes CoreImage. Jedna instance
/// na player item / čtečku (vyrábí ji AVFoundation z třídy nastavené
/// v `customVideoCompositorClass`); volání chodí z front AVFoundation,
/// proto zámek kolem render contextu. `CIContext` je podle dokumentace
/// thread-safe a immutable.
/// <https://developer.apple.com/documentation/coreimage/cicontext>
final class ColorVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    private let lock = NSLock()
    private var renderContext: AVVideoCompositionRenderContext?
    /// Kontext s pracovním prostorem podle barevných atributů zdroje —
    /// mezipaměť na dvojici (prostor, kontext), zdroje v jedné kompozici
    /// tagy prakticky nestřídají.
    private var cachedSpace: CGColorSpace?
    private var cachedContext: CIContext?

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_32BGRA,
        ]]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock()
        renderContext = newRenderContext
        lock.unlock()
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Renderuje se synchronně uvnitř `startRequest` — není co rušit.
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock()
        let context = renderContext
        lock.unlock()

        guard let instruction = request.videoCompositionInstruction
                as? ColorCompositionInstruction else {
            request.finish(with: CompositorError.wrongInstruction)
            return
        }
        guard let context, let output = context.newPixelBuffer() else {
            request.finish(with: CompositorError.noBuffer)
            return
        }

        let canvas = context.size
        // Zlomek času uvnitř instrukce — krajní hodnoty vrstev se lineárně
        // interpolují, přesně jako rampy vestavěného kompozitoru.
        let range = instruction.timeRange
        let f: Double = range.duration.seconds > 0
            ? (request.compositionTime - range.start).seconds / range.duration.seconds
            : 0

        let backgroundColor = instruction.background.flatMap { CIColor(cgColor: $0) }
            ?? CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        var image = CIImage(color: backgroundColor)
            .cropped(to: CGRect(origin: .zero, size: canvas))

        // Skládá se odzadu dopředu (`composited(over:)` klade NAD podklad).
        var attachmentsSource: CVPixelBuffer?
        for layer in instruction.layers.reversed() {
            guard let frame = request.sourceFrame(byTrackID: layer.trackID) else { continue }
            if attachmentsSource == nil { attachmentsSource = frame }

            var ci = CIImage(cvPixelBuffer: frame)
            // Preset PŘED transformací — na plném neprůhledném snímku.
            // Po transformaci by filtr sahal i na průhledné okolí a jasové
            // členy (brightness) by kolem klipu vyráběly svatozář.
            if let grade = layer.grade {
                ci = ColorPresetFilter.apply(grade, to: ci)
            }
            let transform = Self.lerp(layer.transformStart, layer.transformEnd, f)
            ci = ci.transformed(by: Self.ciTransform(
                transform, sourceHeight: ci.extent.height, canvasHeight: canvas.height))

            let opacity = layer.opacityStart
                + (layer.opacityEnd - layer.opacityStart) * Float(f)
            if opacity < 1 {
                // Škáluje se JEN alfa. `CIColorMatrix` počítá na
                // NEpremultiplikovaných hodnotách — kdyby se škálovaly
                // i barevné složky, po zpětné premultiplikaci by se barva
                // násobila průhledností DVAKRÁT (změřeno: směs prolínačky
                // vyšla o², poměr 0,26 místo 0,5). Source-over pak dává
                // o·vrstva + (1−o)·podklad — touž lineární směs kódovaných
                // hodnot jako opacity rampa vestavěného kompozitoru.
                let o = CGFloat(max(0, opacity))
                ci = ci.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: o),
                ])
            }
            image = ci.composited(over: image)
        }

        // Barevné atributy (matice, primárky) z prvního zdroje — jinak by
        // zapisovač u složených snímků předpokládal výchozí a graded úseky
        // by barevně uskočily (vzorec `TitleExportRenderer.makeBuffer`).
        let attachments = attachmentsSource
            .flatMap { CVBufferCopyAttachments($0, .shouldPropagate) }
        if let attachments {
            CVBufferSetAttachments(output, attachments, .shouldPropagate)
        }

        // ⚠️ Dekódování a enkódování MUSÍ být symetrické: pracovní prostor
        // CoreImage i cíl renderu je TENTÝŽ prostor, kterým jsou snímky
        // tagované — round trip nefiltrovaného pixelu je pak identita.
        // S výchozím (lineárním) pracovním prostorem a natvrdo daným cílem
        // se středy posouvaly o ~15 jasu a směsi vycházely lineárně,
        // zatímco vestavěný kompozitor míchá KÓDOVANÉ hodnoty (změřeno
        // ve fázi 10: směs na střihu = průměr kódovaných stran).
        // <https://developer.apple.com/documentation/corevideo/cvimagebuffercreatecolorspacefromattachments(_:)>
        let space = attachments
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.itur_709)
            ?? CGColorSpaceCreateDeviceRGB()
        ciContext(for: space).render(image, to: output,
                                     bounds: CGRect(origin: .zero, size: canvas),
                                     colorSpace: space)
        request.finish(withComposedVideoFrame: output)
    }

    private func ciContext(for space: CGColorSpace) -> CIContext {
        lock.lock()
        defer { lock.unlock() }
        if let cachedContext, cachedSpace == space { return cachedContext }
        let context = CIContext(options: [
            .workingColorSpace: space,
            .cacheIntermediates: false,
        ])
        cachedSpace = space
        cachedContext = context
        return context
    }

    enum CompositorError: Error {
        case wrongInstruction
        case noBuffer
    }

    // MARK: Geometrie

    /// Transformace instrukcí video kompozice pracují v soustavě s počátkem
    /// vlevo NAHOŘE (y roste dolů); CoreImage má počátek vlevo DOLE.
    /// Sendvič: převrátit zdroj do horní soustavy, aplikovat T, převrátit
    /// výsledek zpět do CI soustavy plátna.
    static func ciTransform(_ t: CGAffineTransform,
                            sourceHeight: CGFloat,
                            canvasHeight: CGFloat) -> CGAffineTransform {
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let flipCanvas = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight)
        return flipSource.concatenating(t).concatenating(flipCanvas)
    }

    /// Interpolace po složkách — táž definice jako u `setTransformRamp`
    /// (a `CompositionBuilder.lerp`, který krájí Ken Burns na úseky).
    static func lerp(_ a: CGAffineTransform, _ b: CGAffineTransform,
                     _ f: Double) -> CGAffineTransform {
        let t = CGFloat(min(max(f, 0), 1))
        return CGAffineTransform(a: a.a + (b.a - a.a) * t,
                                 b: a.b + (b.b - a.b) * t,
                                 c: a.c + (b.c - a.c) * t,
                                 d: a.d + (b.d - a.d) * t,
                                 tx: a.tx + (b.tx - a.tx) * t,
                                 ty: a.ty + (b.ty - a.ty) * t)
    }
}

// MARK: - Filtry presetů

/// Optická podoba presetů. Model (`ColorPreset`) nese jen volbu — TADY je
/// jediné místo, kde se z volby stávají CIFiltry, a ladí se bez zásahu do
/// formátu souboru. Vestavěné CIFiltry z referenční dokumentace:
/// <https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/>
enum ColorPresetFilter {

    /// Aplikuje preset s intenzitou: 0 = originál, 1 = plný efekt, mezi tím
    /// lineární směs (`CIDissolveTransition` — prolnutí dvou obrazů časem,
    /// tady „časem" je intenzita).
    static func apply(_ grade: ColorGrade, to image: CIImage) -> CIImage {
        let intensity = min(max(grade.intensity, 0), 1)
        guard intensity > 0 else { return image }
        let filtered = filteredImage(grade.preset, image)
        guard intensity < 1 else { return filtered }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: filtered,
            kCIInputTimeKey: intensity,
        ])
    }

    private static func filteredImage(_ preset: ColorPreset, _ image: CIImage) -> CIImage {
        switch preset {
        case .softWedding:
            // Jemný svatební: vybledlé barvy foto-efektu Fade + lehké
            // prosvětlení a měkčí kontrast.
            return image
                .applyingFilter("CIPhotoEffectFade")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.02,
                    kCIInputContrastKey: 0.98,
                ])
        case .warmFilm:
            // Teplý film: foto-efekt Transfer („warm, reminiscent of film").
            return image.applyingFilter("CIPhotoEffectTransfer")
        case .cleanSkin:
            // Čistá pleť: potlačit saturaci (zarudnutí), lehce prosvětlit.
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.9,
                kCIInputBrightnessKey: 0.015,
                kCIInputContrastKey: 0.97,
            ])
        case .blackAndWhite:
            return image.applyingFilter("CIPhotoEffectMono")
        }
    }
}
