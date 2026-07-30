//
//  FrameExport.swift
//  Projekt AIditor / Flatten
//
//  Vytažení několika snímků do PNG. `MediaProbe` čte metadata, ne pixely —
//  soubor může mít dokonalé časování a přitom být rozsypaná duha.
//  Tohle je jediný způsob, jak se na výsledek podívat.
//
//  `appliesPreferredTrackTransform = true` schválně: chceme vidět obraz tak,
//  jak ho uvidí divák, včetně otočení.
//

import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FrameExport {

    /// Vytáhne `count` snímků rovnoměrně rozložených po stopě.
    static func export(from url: URL, to folder: URL, count: Int) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isValid, duration.seconds > 0 else {
            throw ProbeErrorLocal.message("Soubor nemá použitelnou délku.")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Nulová tolerance — chceme přesně ten snímek, ne nejbližší klíčový.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var written: [URL] = []
        let base = url.deletingPathExtension().lastPathComponent

        for index in 0..<count {
            // Rovnoměrně, ale ne úplně na krajích — první a poslední snímek
            // bývají netypické a o kvalitě obrazu neřeknou nic.
            let fraction = (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: duration.seconds * fraction, preferredTimescale: 600)

            let (image, actualTime) = try await generator.image(at: time)
            let seconds = String(format: "%07.3f", actualTime.seconds)
            let target = folder.appendingPathComponent("\(base)_\(seconds)s.png")

            guard let destination = CGImageDestinationCreateWithURL(
                target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ProbeErrorLocal.message("Nepodařilo se založit PNG \(target.lastPathComponent).")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ProbeErrorLocal.message("Nepodařilo se zapsat \(target.lastPathComponent).")
            }
            written.append(target)
        }
        return written
    }
}

/// Vlastní chyba, ať se nemíchá s ProbeError z knihovny.
enum ProbeErrorLocal: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
