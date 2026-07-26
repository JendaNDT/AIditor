//
//  MediaImporter.swift
//  Projekt Krása
//
//  Otevření souboru přes NSOpenPanel a Security-Scoped Bookmarks.
//
//  Bookmark je jediný způsob, jak si sandboxovaná appka udrží přístup
//  k souboru přes restart. Bez něj by uživatel musel klikat po každém
//  spuštění — a měření by se nedalo pustit automaticky.
//
//  Párování startAccessing/stopAccessing je povinné. Nepárované volání
//  drží deskriptor a po pár stovkách souborů appka přestane otvírat cokoli.
//

import AppKit
import Foundation

@MainActor
final class MediaImporter {

    private static let bookmarksKey = "cz.projektkrasa.bookmarks"

    /// Aktuálně otevřené security-scoped přístupy, ať se dají poctivě zavřít.
    private var accessing: [URL] = []

    deinit {
        // deinit není na MainActoru, takže se kopie zpracuje mimo self.
        let urls = accessing
        for url in urls { url.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Výběr uživatelem

    /// Nechá uživatele vybrat soubory nebo složku a uloží bookmarky.
    func promptForAccess(directories: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = true
        panel.message = directories
            ? "Vyber složku s testovacími klipy. Přístup si appka zapamatuje."
            : "Vyber videosoubor."

        guard panel.runModal() == .OK else { return [] }
        let urls = panel.urls
        for url in urls { store(url) }
        return urls.compactMap { beginAccess($0) }
    }

    // MARK: - Bookmarky

    private func store(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        all[url.path] = data
        UserDefaults.standard.set(all, forKey: Self.bookmarksKey)
    }

    /// Obnoví přístup ke všem zapamatovaným cestám.
    @discardableResult
    func restoreRememberedAccess() -> [URL] {
        let all = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        var restored: [URL] = []

        for (path, data) in all {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale) else {
                FileHandle.standardError.write(Data("Bookmark pro \(path) se nepodařilo rozbalit.\n".utf8))
                continue
            }
            if stale {
                // Zastaralý bookmark ještě funguje, ale je potřeba ho přepsat,
                // jinak časem přestane. Tichý reset je horší než hlášení.
                FileHandle.standardError.write(Data("Bookmark pro \(path) je zastaralý, obnovuji.\n".utf8))
                store(url)
            }
            if let opened = beginAccess(url) { restored.append(opened) }
        }
        return restored
    }

    var hasRememberedAccess: Bool {
        let all = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        return !all.isEmpty
    }

    func forgetAll() {
        releaseAll()
        UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)
    }

    // MARK: - Přístup

    private func beginAccess(_ url: URL) -> URL? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessing.append(url)
        return url
    }

    func releaseAll() {
        for url in accessing { url.stopAccessingSecurityScopedResource() }
        accessing.removeAll()
    }

    // MARK: - Hledání klipů

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts"]

    /// Najde videosoubory ve složce (nerekurzivně).
    func videoFiles(in folder: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
