//
//  StillMovieStore.swift
//  Projekt Krása
//
//  Mezisoubor fotky pro kompozici (fáze 12, modul 2).
//
//  Fotka nemá video stopu, do `AVComposition` se vkládat nedá. Tady se z ní
//  JEDNOU vyrobí film o JEDNOM snímku: ProRes 422 Proxy v rozměru plátna,
//  s vpáleným aspect-fitem (černé pruhy) a EXIF orientací narovnanou už při
//  čtení. `CompositionBuilder` ten snímek vloží a roztáhne `scaleTimeRange`
//  přes celou délku klipu — zero-order hold v přehrávači i exportu pak drží
//  tentýž obraz, což je u fotky přesně to, co má dělat.
//
//  Vpálený aspect-fit je schválně: mezisoubor má rozměr plátna, takže se
//  chová jako každé jiné video 1:1 a BEZ přechodů nevzniká video kompozice
//  — GPU baseline z fáze 1 platí dál i s fotkami na ose.
//
//  Cache: Application Support/StillMovies/<sha256(cesta|velikost|mtime|plátno)>.mov
//  — otisk jako u vln a proxy. Actor: kompozice se přestavuje často a dvě
//  souběžné stavby nesmí generovat týž soubor naráz.
//
//  <https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>
//

import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import TimelineModel

actor StillMovieStore {

    static let shared = StillMovieStore()

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("StillMovies", isDirectory: true)
    }

    /// Vrátí (a případně nejdřív vyrobí) film jednoho snímku pro fotku.
    func movieURL(forPhoto url: URL, canvas: CGSize) async throws -> URL {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? Int64) ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fingerprint = "\(url.path)|\(size)|\(modified)|\(Int(canvas.width))x\(Int(canvas.height))"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".mov"
        let destination = directory.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)

        guard let pixels = renderPhoto(url: url, canvas: canvas) else {
            throw ProbeErrorLike("Fotku \(url.lastPathComponent) se nepodařilo přečíst.")
        }
        // Zápis vedle a přejmenování až po úspěchu — vzorec proxy: půlka
        // souboru po pádu nesmí vypadat jako hotová cache.
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".mov")
        try await writeSingleFrameMovie(pixels: pixels, canvas: canvas, to: temporary)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    struct ProbeErrorLike: Error, CustomStringConvertible {
        let description: String
        init(_ text: String) { description = text }
    }

    // MARK: - Fotka → pixel buffer plátna

    /// Přečte fotku (HEIC/JPEG/PNG — ImageIO), narovná EXIF orientaci
    /// a nakreslí ji aspect-fit na černé plátno. Čte se přes thumbnail API
    /// s mezí velikosti plátna — 48Mpx fotka z foťáku se rovnou podvzorkuje,
    /// místo aby se celá tahala do paměti.
    private func renderPhoto(url: URL, canvas: CGSize) -> CVPixelBuffer? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  // Bez tohohle by fotka na výšku ležela na boku — EXIF
                  // orientace se jinak ignoruje.
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: Int(max(canvas.width, canvas.height)),
              ] as CFDictionary) else { return nil }

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(canvas.width), Int(canvas.height),
                            kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                            &buffer)
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))

        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (canvas.width - fitted.width) / 2,
                                       y: (canvas.height - fitted.height) / 2,
                                       width: fitted.width, height: fitted.height))
        return buffer
    }

    // MARK: - Jeden snímek do .mov

    /// Zapíše jediný ProRes snímek délky 1/30 s (délka je jen nominální —
    /// builder vložený rozsah stejně roztahuje `scaleTimeRange`). Platí
    /// ⚠️ pravidlo projektu: `mediaTimeScale` na video vstupu, jinak si
    /// zapisovač zvolí 600.
    private func writeSingleFrameMovie(pixels: CVPixelBuffer, canvas: CGSize,
                                       to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
            AVVideoWidthKey: Int(canvas.width),
            AVVideoHeightKey: Int(canvas.height),
        ])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = SourceTime.projectTimescale
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
        guard writer.canAdd(input) else {
            throw ProbeErrorLike("Zapisovač nepřijal video vstup fotky.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? ProbeErrorLike("Zápis fotky se nepodařilo spustit.")
        }
        writer.startSession(atSourceTime: .zero)
        guard adaptor.append(pixels, withPresentationTime: .zero) else {
            writer.cancelWriting()
            throw writer.error ?? ProbeErrorLike("Snímek fotky se nepodařilo zapsat.")
        }
        input.markAsFinished()
        let frameDuration = CMTime(
            value: Int64(SourceTime.projectTimescale) / 30,
            timescale: SourceTime.projectTimescale)
        writer.endSession(atSourceTime: frameDuration)

        // Přes continuation, ne semafor — blokující wait v async kontextu
        // zabírá kooperativní vlákno (táž past jako v `CFRRendereru`).
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status == .failed {
            throw writer.error ?? ProbeErrorLike("Zápis fotky selhal.")
        }
    }
}
