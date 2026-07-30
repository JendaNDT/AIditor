//
//  ThumbnailStore.swift
//  Projekt Krása
//
//  Miniatury na klipech — fáze 18, modul 5. Vzorec `WaveformStore`:
//  mezipaměť v paměti + na disku, líné dopočítávání na pozadí, `version`
//  jako jediný signál „přišlo něco nového".
//
//  ⚠️ DLAŽDICE JSOU KOTVENÉ VE ZDROJOVÉM ČASE, ne v klipu.
//  Návrh dělí pás miniatur na 2–4 rovnoměrné dlaždice přes šířku klipu.
//  Vypadá to stejně, ale znamenalo by to, že po každém trimu a slipu se
//  změní čas VŠECH dlaždic klipu a celá sada se zahodí — a to při tažení
//  úchytu šedesátkrát za sekundu. Kotvení ve zdroji drží miniatury na místě
//  (týž důvod, proč jsou ve zdroji kotvené uzly rychlostní křivky), takže
//  trim jen posune výřez. Cenou je, že se dlaždice na hranách klipu
//  ZAŘEZÁVAJÍ — přesně jak to dělá Premiere i Final Cut.
//  Hustota je z návrhu: jedna dlaždice na 96 bodů, což na jeho čtyřech
//  ukázkových šířkách (150 / 172 / 250 / 130) vyjde na 2 / 2 / 3 / 1
//  dlaždici, tedy přesně na to, co je na screenshotu.
//
//  ⚠️ JEDEN PRACOVNÍK, DÁVKOVĚ. Dekódování snímku je řádově dražší než
//  dlaždice vlny a běží na CPU. Kdyby se pouštěla úloha na dlaždici, měl by
//  scroll přes dvacet klipů dvacet souběžných dekodérů a hlavní vlákno by
//  o výpočetní čas soutěžilo s nimi — to je riziko R1 plánu. Proto sériový
//  pracovník, který si bere dávku po `batchLimit` snímcích jednoho souboru
//  a nechá je vygenerovat JEDNÍM průchodem `AVAssetImageGenerator.images(for:)`.
//  <https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/images(for:)>
//  (ověřeno v SDK, pravidlo 6: existuje a přeloží se i s deployment targetem
//  macOS 14; vrací `AsyncSequence` s případy `.success(requestedTime:image:
//  actualTime:)` a `.failure(requestedTime:error:)`.)
//
//  ⚠️ ZÁSOBNÍK, NE FRONTA. Vyzvedává se POSLEDNÍ požadavek: ten odpovídá
//  tomu, co je na obrazovce teď. Fronta by po projetí dvaceti obrazovek
//  dogenerovávala miniatury k místům, odkud už uživatel dávno odscrolloval.
//
//  Generuje se Z PROXY, když projekt s proxy pracuje (ProRes 422 Proxy je
//  intra-only, takže seek stojí 6 ms proti 41–95 ms u 4K HEVC — naměřeno
//  27. 07. 2026). Bez proxy se čte z originálu a je to prostě pomalejší;
//  na pozadí to nikoho nebolí, protože pás se doplňuje po dlaždicích.
//
//  Tolerance seeku je NULA. Miniatura má ukazovat snímek z toho místa, kam
//  ukazuje — s tolerancí půl dlaždice by si sousední dlaždice u HEVC sáhly
//  na týž klíčový snímek a pás by vypadal, že se v něm nic nehýbe.
//

import AVFoundation
import AppKit
import CoreMedia
import CryptoKit
import Foundation
import ImageIO
import TimelineModel
import UniformTypeIdentifiers

/// Klíč dlaždice. Souborem, ne `AssetID` — po zapnutí proxy se čte jiný
/// soubor a miniatury z originálu se použít nesmí (proxy má poloviční
/// rozlišení, ale hlavně může být zploštěná z VFR, takže na témže čase
/// leží obecně jiný snímek).
///
/// `rung` je mocnina dvou jako u vln: cachovat podle spojitého zoomu by
/// znamenalo zahazovat mezipaměť při každém kroku pinche.
struct ThumbTileKey: Hashable {
    let url: URL
    /// Úroveň zoomu (mocnina dvou). Nula = fotka: ta má jednu dlaždici
    /// na celý pás a se zoomem se nemění.
    let rung: Double
    let index: Int
    /// Hrana dlaždice v bodech (výška pásu).
    let side: Double
    let scale: CGFloat
}

@MainActor
final class ThumbnailStore: ObservableObject {

    /// Roste s každou dopočítanou dlaždicí. Odběr v `TimelinePane` je
    /// throttlovaný — vzorec vln.
    @Published private(set) var version = 0

    /// Hrana dlaždice v bodech = výška pásu miniatur podle návrhu.
    /// Zároveň ROZTEČ mřížky: jedna miniatura na 96 bodů osy.
    nonisolated static let tileSidePoints: Double = 96

    /// Poměr renderované dlaždice (šířka ku výšce).
    ///
    /// ⚠️ **Ne čtverec, a chytil to až screenshot.** Slot na obrazovce je
    /// široký `hrana × zoom/úroveň`, tedy mezi 0,71 a 1,41 hrany — u čtvercové
    /// dlaždice se tedy obraz při běžném zoomu DOTAHOVAL (1,25×) a pás byl
    /// vidět rozmazaný. S poměrem 1,5 se dlaždice ve slotu vždycky zmenšuje,
    /// ne zvětšuje. Cena je paměť: 1,5násobek bajtů na dlaždici.
    nonisolated static let tileAspect: Double = 1.5

    /// Časová základna projektu. Táž konstanta jako ve `WaveformStore`:
    /// osové body se na sekundy převádějí JÍ, nikdy frekvencí assetu.
    private nonisolated static let timelineFrameRate: Double = 30

    /// Kolik snímků si pracovník vezme v jedné dávce. Šest je kompromis:
    /// míň znamená častější rozjezd generátoru, víc znamená delší dobu,
    /// po kterou pracovník nevidí, že se výřez posunul.
    private static let batchLimit = 6
    /// Strop čekajících požadavků. Co se nevejde, spadne pod stůl —
    /// při scrollu přes tisíce klipů se o ně nikdo za chvíli nezajímá.
    private static let pendingLimit = 64
    /// Strop dlaždic v paměti. Vzorec `WaveformStore`: dlaždice jsou levné
    /// na dopočet a drahé na držení, takže se při přetečení začne znovu.
    private static let memoryLimit = 240

    private var tiles: [ThumbTileKey: CGImage] = [:]
    /// Čekající požadavky. Zdrojový čas se v nich nedrží — plyne z klíče
    /// (`index × secondsPerTile`), takže není kde se rozejít.
    private var pending: Set<ThumbTileKey> = []
    private var stack: [ThumbTileKey] = []
    private var isWorking = false
    /// Co se nepovedlo. Bez tohohle by se každý neúspěch zkoušel znovu při
    /// každém tiku scrollu — a když soubor chybí, nepovede se to nikdy.
    private var failed: Set<ThumbTileKey> = []

    // MARK: - Měřicí okno pro `--thumb-check`

    struct Stats {
        var generated = 0
        var fromDisk = 0
        var failed = 0
        var generateMs: Double = 0
        var diskMs: Double = 0

        var msPerGenerated: Double { generated > 0 ? generateMs / Double(generated) : 0 }
        var msPerDisk: Double { fromDisk > 0 ? diskMs / Double(fromDisk) : 0 }
    }
    private(set) var stats = Stats()
    func resetStats() { stats = Stats() }

    var pendingCount: Int { pending.count }
    var memoryCount: Int { tiles.count }
    var isBusy: Bool { isWorking || !pending.isEmpty }

    /// Vypnutelný odklad — pro měření v `--thumb-check`. Cesta bez odkladu
    /// se v aplikaci nikdy nespustí, takže by tiše shnila; kontrola ji
    /// vynucuje a měří, o kolik je horší (vzorec `forcesSteppingFallback`
    /// z `--jkl-check`).
    var deferralEnabled = true

    /// Zahodí paměťovou mezipaměť (disková zůstane) — pro měření „druhé
    /// generování z cache".
    func dropMemory() {
        tiles.removeAll()
        failed.removeAll()
    }

    // MARK: - Mřížka

    /// Nejbližší mocnina dvou k aktuálnímu zoomu. Táž funkce jako u vln,
    /// aby se obě vrstvy při pinchi přepínaly ve stejném okamžiku.
    static func rung(for pointsPerFrame: Double) -> Double {
        WaveformStore.rung(for: pointsPerFrame)
    }

    /// Kolik sekund zdroje připadá na jednu dlaždici při dané úrovni zoomu.
    nonisolated static func secondsPerTile(rung: Double, side: Double) -> Double {
        side / (timelineFrameRate * rung)
    }

    // MARK: - Čtení

    /// Dlaždice videa, nebo `nil` a zadaný požadavek na pozadí.
    func tile(url: URL, rung: Double, index: Int,
              side: Double = ThumbnailStore.tileSidePoints, scale: CGFloat) -> CGImage? {
        let key = ThumbTileKey(url: url, rung: rung, index: index, side: side, scale: scale)
        if let image = tiles[key] { return image }
        guard !failed.contains(key) else { return nil }
        enqueue(key)
        return nil
    }

    /// Dlaždice fotky: jedna na celý pás (fotka se v čase nemění, takže
    /// filmový pás by u ní byl třikrát týž obrázek — návrh ji taky kreslí
    /// jako jednu plochu).
    func stillTile(url: URL, side: Double = ThumbnailStore.tileSidePoints,
                   scale: CGFloat) -> CGImage? {
        let key = ThumbTileKey(url: url, rung: 0, index: 0, side: side, scale: scale)
        if let image = tiles[key] { return image }
        guard !failed.contains(key) else { return nil }
        enqueue(key)
        return nil
    }

    private func enqueue(_ key: ThumbTileKey) {
        if pending.insert(key).inserted {
            stack.append(key)
            // Přeteklý zásobník se zkracuje ZEZDOLU: nejstarší požadavky
            // jsou ty, od kterých uživatel odscrolloval.
            while stack.count > Self.pendingLimit {
                pending.remove(stack.removeFirst())
            }
        } else if let position = stack.lastIndex(of: key), position != stack.count - 1 {
            // Znovu vyžádaná dlaždice jde na konec zásobníku: pořadí má
            // odpovídat tomu, na co se uživatel právě kouká.
            stack.remove(at: position)
            stack.append(key)
        }
        pump()
    }

    // MARK: - Odklad, dokud se osa hýbe

    /// Do kdy se má mlčet. `nil` = pracuje se.
    private var quietDeadline: Date?
    private var watchdogRunning = false

    /// Osa posunula výřez. Generování se odloží, dokud nebude `seconds`
    /// klidu.
    ///
    /// ⚠️ **Bez tohohle nedrží brána R1.** Změřeno 30. 07. 2026: scroll přes
    /// 2000 klipů se studenou cache vygeneroval 199 snímků za jízdy a stály
    /// **dva vypadlé tiky** — ne kvůli práci na hlavním vlákně (0,40 ms
    /// z rozpočtu 16,67), ale protože dekodéry na pozadí soutěží o výpočetní
    /// čas s hlavním vláknem. S odkladem se za jízdy negeneruje nic a pás se
    /// doplní, jakmile osa stojí. Takhle se chová každý NLE a je to i
    /// správná odpověď na otázku „co uživatel chce": při scrollování hledá
    /// místo, ne kouká na miniatury.
    ///
    /// Požadavky se během odkladu DÁL SBÍRAJÍ a přeteklé padají zezdola,
    /// takže po zastavení se generuje to, na co se uživatel kouká teď.
    func deferGeneration(quiet seconds: Double = 0.2) {
        guard deferralEnabled else { return }
        quietDeadline = Date().addingTimeInterval(seconds)
        guard !watchdogRunning else { return }
        watchdogRunning = true
        Task { @MainActor in
            while let deadline = self.quietDeadline, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            self.quietDeadline = nil
            self.watchdogRunning = false
            self.pump()
        }
    }

    // MARK: - Pracovník

    private func pump() {
        guard quietDeadline == nil else { return }
        guard !isWorking, !stack.isEmpty else { return }

        // Dávka: poslední požadavek a k němu další ze STEJNÉHO souboru
        // a stejné úrovně — jeden generátor umí naráz jen jeden asset.
        let head = stack.removeLast()
        pending.remove(head)

        var batch: [ThumbTileKey] = [head]
        var index = stack.count - 1
        while index >= 0, batch.count < Self.batchLimit {
            let candidate = stack[index]
            if candidate.url == head.url, candidate.rung == head.rung,
               candidate.side == head.side, candidate.scale == head.scale {
                batch.append(candidate)
                pending.remove(candidate)
                stack.remove(at: index)
            }
            index -= 1
        }

        isWorking = true
        let request = BatchRequest(url: head.url, side: head.side,
                                   scale: head.scale, keys: batch)

        Task.detached(priority: .utility) {
            let outcome = await Self.render(request)
            await MainActor.run {
                self.isWorking = false
                if self.tiles.count > Self.memoryLimit { self.tiles.removeAll() }
                for (key, image) in outcome.images {
                    if let image { self.tiles[key] = image } else { self.failed.insert(key) }
                }
                self.stats.generated += outcome.stats.generated
                self.stats.fromDisk += outcome.stats.fromDisk
                self.stats.failed += outcome.stats.failed
                self.stats.generateMs += outcome.stats.generateMs
                self.stats.diskMs += outcome.stats.diskMs
                if !outcome.images.isEmpty { self.version += 1 }
                self.pump()
            }
        }
    }

    // MARK: - Render (mimo hlavní vlákno)

    private struct BatchRequest {
        let url: URL
        let side: Double
        let scale: CGFloat
        let keys: [ThumbTileKey]
    }

    private struct BatchOutcome {
        var images: [(key: ThumbTileKey, image: CGImage?)] = []
        var stats = Stats()
    }

    private nonisolated static func render(_ request: BatchRequest) async -> BatchOutcome {
        var outcome = BatchOutcome()
        let pixelSide = Int((request.side * Double(request.scale)).rounded())
        let pixelWidth = Int((request.side * tileAspect * Double(request.scale)).rounded())
        guard pixelSide > 0, pixelWidth > 0 else { return outcome }

        // 1) Z disku, co tam je.
        var toGenerate: [ThumbTileKey] = []
        for key in request.keys {
            let started = CACurrentMediaTime()
            if let cacheURL = cacheURL(for: key), let image = loadJPEG(from: cacheURL) {
                outcome.stats.diskMs += (CACurrentMediaTime() - started) * 1000
                outcome.stats.fromDisk += 1
                outcome.images.append((key, image))
            } else {
                toGenerate.append(key)
            }
        }
        guard !toGenerate.isEmpty else { return outcome }

        // 2) Fotka (`rung == 0`): jeden obrázek přes ImageIO, žádný `AVAsset`.
        if let still = toGenerate.first(where: { $0.rung == 0 }) {
            let started = CACurrentMediaTime()
            let image = renderStill(url: request.url, pixelSide: pixelWidth)
            outcome.stats.generateMs += (CACurrentMediaTime() - started) * 1000
            if let image {
                outcome.stats.generated += 1
                if let cacheURL = cacheURL(for: still) { saveJPEG(image, to: cacheURL) }
            } else {
                outcome.stats.failed += 1
            }
            outcome.images.append((still, image))
            return outcome
        }

        // 3) Video: jeden generátor, všechny časy naráz.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: request.url))
        generator.appliesPreferredTrackTransform = true
        // Nulová tolerance — viz hlavička souboru.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Čtvercová mez, ne 16:9: `maximumSize` je aspect FIT, takže box
        // 342×342 pokryje výškou i 16:9 (342×192) i portrét z telefonu
        // (192×342). Kdyby box byl 342×192, portrét by vyšel 108 px široký
        // a do dlaždice by se upscaloval do rozmazání.
        let box = Double(max(pixelSide, pixelWidth)) * 16.0 / 9.0
        generator.maximumSize = CGSize(width: box, height: box)

        // Časy ve pevné časové základně, ať se `requestedTime` z odpovědi
        // dá spárovat zpátky na dlaždici bez porovnávání zlomků.
        let timescale: CMTimeScale = 30_000
        var byValue: [Int64: ThumbTileKey] = [:]
        var times: [CMTime] = []
        for key in toGenerate {
            let seconds = Double(key.index) * secondsPerTile(rung: key.rung, side: key.side)
            let time = CMTime(value: CMTimeValue((seconds * Double(timescale)).rounded()),
                              timescale: timescale)
            byValue[time.value] = key
            times.append(time)
        }
        guard !times.isEmpty else { return outcome }

        let started = CACurrentMediaTime()
        for await result in generator.images(for: times.sorted { $0.value < $1.value }) {
            switch result {
            case .success(requestedTime: let requested, image: let image, actualTime: _):
                guard let key = byValue[requested.value] else { continue }
                let tile = crop(image, pixelWidth: pixelWidth, pixelHeight: pixelSide)
                if let tile {
                    outcome.stats.generated += 1
                    if let cacheURL = cacheURL(for: key) { saveJPEG(tile, to: cacheURL) }
                } else {
                    outcome.stats.failed += 1
                }
                outcome.images.append((key, tile))
            case .failure(requestedTime: let requested, error: _):
                guard let key = byValue[requested.value] else { continue }
                outcome.stats.failed += 1
                outcome.images.append((key, nil))
            @unknown default:
                break
            }
        }
        outcome.stats.generateMs += (CACurrentMediaTime() - started) * 1000
        return outcome
    }

    /// Snímek → dlaždice středovým výřezem (aspect fill). Výřez, ne
    /// zmenšenina celého snímku: dlaždice je v pásu užší než 16:9, a obraz
    /// se má ZAŘEZAT, ne zúžit.
    private nonisolated static func crop(_ image: CGImage,
                                         pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let scale = max(Double(pixelWidth) / Double(image.width),
                        Double(pixelHeight) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: (Double(pixelWidth) - width) / 2,
                                       y: (Double(pixelHeight) - height) / 2,
                                       width: width, height: height))
        return context.makeImage()
    }

    /// Fotka: ImageIO s `kCGImageSourceCreateThumbnailWithTransform`, takže
    /// se srovná EXIF orientace. Bez toho by portrétová fotka z telefonu
    /// ležela v pásu na boku (týž důvod jako u still movie mezisouboru).
    /// <https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform>
    private nonisolated static func renderStill(url: URL, pixelSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Dvojnásobek: pás fotky je JEDNA dlaždice přes celou šířku
            // klipu, takže se obrázek roztahuje na víc než jeden slot.
            kCGImageSourceThumbnailMaxPixelSize: pixelSide * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else { return nil }
        return image
    }

    // MARK: - Disková mezipaměť

    /// Klíč z cesty, velikosti, času změny a rozměru dlaždice — vzorec
    /// `WaveformStore` a `SharpnessStore`. Verze je součástí otisku, takže
    /// po změně renderu se staré soubory přestanou trefovat.
    private nonisolated static func cacheURL(for key: ThumbTileKey) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attributes = try? FileManager.default.attributesOfItem(atPath: key.url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        // ⚠️ Verze je součástí otisku, a v2 je tu proto, že v1 renderovala
        // dlaždici jako ČTVEREC. Bez zvednuté verze by se po změně poměru
        // tahaly z disku staré čtverce a pás by zůstal rozmazaný.
        let fingerprint = "v2|\(key.url.path)|\(size)|\(modified)"
            + "|\(key.side)|\(key.scale)|\(key.rung)|\(key.index)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".jpg")
    }

    /// JPEG, ne PNG: dlaždice je fotografický obsah, kde je PNG dvakrát
    /// větší a nic tím nezískáme. Kvalita 0,8 — na 96 bodech není artefakt
    /// vidět a soubor má jednotky kilobajtů.
    private nonisolated static func saveJPEG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private nonisolated static func loadJPEG(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
