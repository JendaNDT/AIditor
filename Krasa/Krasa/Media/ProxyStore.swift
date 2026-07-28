//
//  ProxyStore.swift
//  Projekt Krása
//
//  Fáze 4: generování a evidence proxy souborů.
//
//  ⚠️ Proxy NENÍ kvůli přehrávání, ale kvůli SCRUBOVÁNÍ. AVPlayer utáhne
//  4K HEVC na stropu displeje; rozdíl je odezva seeku se zero tolerance —
//  6,2 ms u ProRes proti 41–95 ms u HEVC (naměřeno ve fázi 1). ProRes je
//  intra-only, HEVC musí dekódovat od klíčového snímku.
//
//  Rozhodnutí, která tu platí (plán, fáze 4):
//  - ProRes 422 Proxy v POLOVIČNÍM rozlišení — plné 4K proxy není úspora.
//  - Při generování se VFR zploští na CFR: mřížka z modu délek vzorků
//    (nominalFrameRate lže), čte se přes AVComposition (edit list — zvuk
//    by jinak ujel o 44 ms).
//  - Zvuk LPCM, ne AAC — AAC by přidal vlastní priming delay.
//  - Render dělá sdílený `CFRRenderer` z ProbeKitu, tentýž kód jako
//    ověřený nástroj Flatten; tady je jen orchestrace a cache.
//
//  Cache: Application Support/Proxies/<sha256(cesta|velikost|mtime)>.mov —
//  stejný otisk jako u vln. Zapisuje se vedle a přejmenuje až po úspěchu,
//  jinak by nedopsaný soubor po pádu vypadal jako hotová proxy.
//

import AVFoundation
import CryptoKit
import Foundation
import ProbeKit

@MainActor
final class ProxyStore: ObservableObject {

    /// Text pro sidebar: „Proxy 2/5: jméno…", `nil` = nic neběží.
    @Published private(set) var progressText: String?
    /// Originál → hotová proxy. Zdroj pravdy pro opakované přišití k projektu
    /// (undo vrací snapshoty z doby, kdy proxy ještě nebyla).
    @Published private(set) var finished: [URL: URL] = [:]
    /// Součet velikostí souborů v aktuálním úložišti — ProRes je velký
    /// a uživatel má vidět, kolik proxy stojí.
    @Published private(set) var cacheSizeBytes: Int64 = 0
    /// Pro sidebar: kam se ukládá.
    @Published private(set) var directoryDisplayName = "výchozí složka aplikace"

    private var isGenerating = false

    // MARK: Umístění

    /// Kritérium fáze 4: „proxy jde vygenerovat na externí disk". Zvolená
    /// složka se drží security-scoped bookmarkem (sandbox) — stejný vzorec
    /// jako `MediaImporter` u zdrojů. `nil` = výchozí Application Support.
    private static let directoryBookmarkKey = "cz.projektkrasa.proxyDirectory"
    private var customRoot: URL?

    private static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Proxies", isDirectory: true)
    }

    /// Aktuální úložiště. Ve zvolené složce se dělá podsložka, aby se
    /// hashované .mov soubory nesypaly uživateli do kořene disku.
    private var directory: URL? {
        customRoot?.appendingPathComponent("Krása Proxy", isDirectory: true)
            ?? Self.defaultDirectory
    }

    init() {
        restoreCustomDirectory()
        refreshCacheSize()
    }

    /// Nastaví (a bookmarkem si zapamatuje) složku pro proxy. Evidence se
    /// vyprázdní — volající pak spustí generování znovu, do nového umístění.
    func chooseDirectory(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.directoryBookmarkKey)
        _ = url.startAccessingSecurityScopedResource()
        customRoot = url
        directoryDisplayName = url.path
        finished = [:]
        refreshCacheSize()
    }

    private func restoreCustomDirectory() {
        guard let data = UserDefaults.standard.data(forKey: Self.directoryBookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            // Odpojený externí disk: potichu spadnout na výchozí složku —
            // klipy pojedou z originálů, nic nespadne.
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.directoryBookmarkKey)
        }
        customRoot = url
        directoryDisplayName = url.path
    }

    // MARK: Cache

    /// Cesta proxy pro daný zdroj — otisk cesty, velikosti a času změny.
    /// Přejmenovaný nebo přepsaný originál dostane novou proxy sám od sebe.
    func cacheURL(for source: URL) -> URL? {
        guard let directory,
              let attributes = try? FileManager.default.attributesOfItem(atPath: source.path),
              let size = attributes[.size] as? Int64,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let fingerprint = "\(source.path)|\(size)|\(modified.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".mov")
    }

    /// Smaže obsah aktuálního úložiště a vyprázdní evidenci. Volající musí
    /// NEJDŘÍV odšít proxy z projektu — jinak by kompozice chvíli ukazovala
    /// na smazané soubory.
    func deleteAll() {
        guard !isGenerating, let directory else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in contents where ["mov", "partial"].contains(item.pathExtension) {
            try? FileManager.default.removeItem(at: item)
        }
        finished = [:]
        refreshCacheSize()
    }

    private func refreshCacheSize() {
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            cacheSizeBytes = 0
            return
        }
        cacheSizeBytes = contents.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Zajistí proxy pro všechny klipy, postupně (ProRes engine je jeden).
    /// Za každou hotovou (i nalezenou v cache) zavolá `onReady` — volající
    /// ji přišije k projektu.
    func ensureProxies(for timings: [ClipTiming],
                       onReady: @MainActor (URL, URL) -> Void) async {
        guard !isGenerating else { return }
        isGenerating = true
        defer {
            isGenerating = false
            progressText = nil
        }

        var pending: [(ClipTiming, URL)] = []
        for timing in timings {
            guard let cache = cacheURL(for: timing.url) else { continue }
            if FileManager.default.fileExists(atPath: cache.path) {
                finished[timing.url] = cache
                onReady(timing.url, cache)
            } else {
                pending.append((timing, cache))
            }
        }

        for (index, (timing, cache)) in pending.enumerated() {
            progressText = "Proxy \(index + 1)/\(pending.count): \(timing.name)…"
            do {
                try await Self.generate(source: timing.url, to: cache)
                finished[timing.url] = cache
                onReady(timing.url, cache)
            } catch {
                // Klip bez proxy dál jede z originálu — url(usingProxies:)
                // má fallback. Zaznamenat a jet dál, ne spadnout.
                print("Proxy pro \(timing.name) selhala: \(error)")
            }
            refreshCacheSize()
        }
    }

    /// Jedno proxy: stejná orchestrace jako ověřený Flattener, jen
    /// s polovičním rozlišením a zápisem přes dočasný soubor.
    private static func generate(source: URL, to cache: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.message("Soubor nemá video stopu.")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (range, naturalScale) = try await video.load(.timeRange, .naturalTimeScale)

        // Mřížka z modu délek vzorků — měření, ne metadata.
        let timing = await SampleTimingReader.read(track: video, asset: asset,
                                                   naturalTimeScale: naturalScale)
        guard let stats = timing.stats else {
            throw ProbeError.message("Nepodařilo se změřit časování: \(timing.note ?? "?")")
        }

        // Kompozice aplikuje edit list — u zvuku povinné (priming 44 ms).
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProbeError.message("Nepodařilo se založit stopu kompozice.")
        }
        try compVideo.insertTimeRange(range, of: video, at: .zero)
        var compAudio: AVMutableCompositionTrack?
        if let audio {
            let audioRange = try await audio.load(.timeRange)
            compAudio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compAudio?.insertTimeRange(audioRange, of: audio, at: .zero)
        }

        let partial = cache.appendingPathExtension("partial")
        _ = try await CFRRenderer.render(asset: composition,
                                         videoTrack: compVideo,
                                         audioTrack: compAudio,
                                         frameDuration: stats.frameDuration,
                                         outputScale: 0.5,
                                         to: partial)
        try? FileManager.default.removeItem(at: cache)
        try FileManager.default.moveItem(at: partial, to: cache)
    }
}
