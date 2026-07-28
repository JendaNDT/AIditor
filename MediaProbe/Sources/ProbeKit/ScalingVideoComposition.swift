//
//  ScalingVideoComposition.swift
//  Projekt Krása / ProbeKit
//
//  Fáze 9, modul 1: škálovací video kompozice DVAKRÁT, za jedním
//  rozhraním — přesně podle plánu (sekce fáze 9).
//
//  - macOS 26+: `AVVideoComposition.Configuration` — nové API. Ověřeno
//    proti swiftinterface SDK 26.5 (má `frameDuration`, `renderSize`
//    i async `init(for:)` s vlastnostmi assetu).
//    <https://developer.apple.com/documentation/avfoundation/avvideocomposition/configuration>
//  - macOS 14–25: `AVMutableVideoComposition.videoComposition(withPropertiesOf:)`
//    — od macOS 26 deprecated, ale na starších systémech JEDINÁ možnost.
//    Warning se při deployment targetu 14 nehlásí (deprecation platí až
//    od 26); až se target jednou zvedne, smí zmizet tahle větev, ne dřív.
//    <https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition/videocomposition(withpropertiesof:)>
//
//  Obě větve dělají totéž: kompozice s vlastnostmi assetu (aplikuje
//  `preferredTransform`), cílový rozměr a KADENCE = cílová mřížka,
//  aby výstup čtečky byl už CFR a zero-order hold resampleru jím
//  prošel 1:1. Časování se tu žádné nemění — `Configuration` žádné
//  neumí a speed ramping řeší segmentace, ne kompozice.
//

import AVFoundation
import CoreMedia
import Foundation

enum ScalingVideoComposition {

    /// Kompozice pro čtení přes `AVAssetReaderVideoCompositionOutput`:
    /// vzpřímený obraz v `renderSize`, snímky na mřížce `frameDuration`.
    static func make(for asset: AVAsset,
                     renderSize: CGSize,
                     frameDuration: CMTime) async throws -> AVVideoComposition {
        if #available(macOS 26.0, *) {
            var configuration = try await AVVideoComposition.Configuration(for: asset)
            configuration.renderSize = renderSize
            configuration.frameDuration = frameDuration
            return AVVideoComposition(configuration: configuration)
        } else {
            let scaling = try await AVMutableVideoComposition
                .videoComposition(withPropertiesOf: asset)
            scaling.renderSize = renderSize
            scaling.frameDuration = frameDuration
            return scaling
        }
    }
}
