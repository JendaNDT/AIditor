//
//  ProjectStore.swift
//  Projekt Krása
//
//  Fáze 5: soubor `.projektkrasa` — uložit, otevřít, znovu otevřít po
//  startu. Formát dělá `ProjectFile` v TimelineModelu; tady je jen disk,
//  sandbox a bookmarky.
//
//  Odchylka od specifikace 6.1: projekt je JEDEN soubor, ne balíček se
//  složkami Proxies/ a Autosaves/. Proxy jsou centrální cache s vlastním
//  umístěním (fáze 4 — a spec 6.3 sama doporučuje proxy oddělit od
//  projektu), autosavy patří do Application Support, aby přežily i přesun
//  souboru (přijdou v dalším modulu). Jeden soubor se navíc dá poslat
//  mailem a nezmate Finder bez deklarace balíčkového UTI.
//

import AppKit
import Foundation
import TimelineModel
import UniformTypeIdentifiers

@MainActor
final class ProjectStore: ObservableObject {

    /// Kam je projekt uložený. `nil` = zatím neuložený (obraz skenu).
    @Published private(set) var fileURL: URL?
    @Published private(set) var lastSavedAt: Date?

    /// Datum vzniku se čte ze souboru a při ukládání vrací — jinak by ho
    /// každé uložení přepsalo dneškem.
    private var createdAt = Date()

    /// Security scope držené po dobu běhu: soubor projektu a assety.
    /// Nepárované stopAccessing tu není omylem — přístup má žít, dokud
    /// žije aplikace.
    private var heldScopes: [URL] = []

    private static let lastProjectKey = "cz.projektkrasa.lastProject"

    static let fileType = UTType(filenameExtension: "projektkrasa",
                                 conformingTo: .json) ?? .json

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Neuložený projekt"
    }

    // MARK: Uložit / otevřít

    func save(project: Project, to url: URL) throws {
        let file = ProjectFile(project: project,
                               name: url.deletingPathExtension().lastPathComponent,
                               createdAt: createdAt,
                               modifiedAt: Date())
        try file.encoded().write(to: url, options: .atomic)
        fileURL = url
        lastSavedAt = Date()
        rememberLastProject(url)
    }

    func load(from url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        let file = try ProjectFile.decode(data)
        createdAt = file.createdAt
        fileURL = url
        lastSavedAt = file.modifiedAt
        rememberLastProject(url)
        return file.project
    }

    /// Nový neuložený projekt (import klipů zahodil ten starý obraz).
    func detachFromFile() {
        fileURL = nil
        lastSavedAt = nil
        createdAt = Date()
    }

    // MARK: Poslední projekt (start aplikace)

    private func rememberLastProject(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.lastProjectKey)
    }

    /// URL posledního projektu, s už otevřeným security scope. `nil` =
    /// není co otevírat (smazaný soubor, první spuštění).
    func restoreLastProjectURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastProjectKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        heldScopes.append(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.lastProjectKey)
        }
        return url
    }

    // MARK: Bookmarky assetů

    /// Bookmark pro asset — ukládá se do projektu, aby se soubory našly
    /// i po restartu, kdy oprávnění sandboxu z tohohle běhu už neplatí.
    static func assetBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope,
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    /// Projde assety otevřeného projektu: vyřeší bookmarky (a otevře jim
    /// security scope), opraví přesunuté cesty, označí nedostupné jako
    /// offline a zahodí proxy, jejichž soubor mezitím zmizel. Klipy
    /// offline assetů ZŮSTÁVAJÍ — smazat cizí práci kvůli přejmenované
    /// složce je horší chyba než prázdné místo v náhledu.
    func resolveAssets(in project: Project) -> Project {
        var resolved = project
        for var asset in resolved.assets {
            if let data = asset.bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale),
                   url.startAccessingSecurityScopedResource() {
                    heldScopes.append(url)
                    if url != asset.originalURL { asset.originalURL = url }
                    if stale, let fresh = Self.assetBookmark(for: url) {
                        asset.bookmark = fresh
                    }
                    asset.isOffline = !FileManager.default.fileExists(atPath: url.path)
                } else {
                    asset.isOffline = !FileManager.default.fileExists(atPath: asset.originalURL.path)
                }
            } else {
                asset.isOffline = !FileManager.default.fileExists(atPath: asset.originalURL.path)
            }

            // Proxy z minulého běhu, jejíž soubor už neexistuje, by v kompozici
            // udělala tichou díru — čerstvou přišije ProxyStore po přeskenu.
            if let proxy = asset.proxyURL, !FileManager.default.fileExists(atPath: proxy.path) {
                asset.proxyURL = nil
            }
            resolved.addAsset(asset)
        }
        return resolved
    }
}
