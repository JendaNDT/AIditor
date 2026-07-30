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

    /// Soubory, které přišly PŘETAŽENÍM na okno (fáze 18, modul 12).
    ///
    /// ⚠️ **Pojmenované riziko modulu.** Drop dává přístup k souboru jen na
    /// dobu operace a `startAccessingSecurityScopedResource()` na takové URL
    /// vrací `false` — není to security-scoped URL, je to obyčejná cesta
    /// s dočasně přidělenou výjimkou. Trvalý přístup (a tedy projekt, který
    /// přežije restart) dá jedině bookmark, a ten se musí vyrobit HNED, dokud
    /// výjimka platí; proto se čerstvý bookmark rovnou rozbalí zpátky.
    ///
    /// Když se bookmark nevyrobí, vrací se původní URL: import tím proběhne
    /// (v tomhle běhu přístup je), ale po restartu bude asset offline — a to
    /// projekt už umí přiznat. Tiše soubor zahodit by bylo horší.
    func adopt(dropped urls: [URL]) -> [URL] {
        urls.map { url in
            store(url)
            return beginAccessFromStoredBookmark(url) ?? url
        }
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

    /// Má appka pro tuhle cestu uložený bookmark? Odpověď na otázku „přežije
    /// import restart" — a tedy měřitelná podoba rizika modulu 12.
    func remembers(_ url: URL) -> Bool {
        let all = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        return all[url.path] != nil
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

    /// Otevře přístup přes bookmark, který se pro tu cestu právě uložil.
    private func beginAccessFromStoredBookmark(_ url: URL) -> URL? {
        let all = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        guard let data = all[url.path] else { return nil }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else { return nil }
        return beginAccess(resolved)
    }

    func releaseAll() {
        for url in accessing { url.stopAccessingSecurityScopedResource() }
        accessing.removeAll()
    }

    // MARK: - Hledání klipů

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts"]
    /// Fotky (fáze 12) a hudba (fáze 14) — přípony podle toho, co pouštějí
    /// panely `addPhotos` (`.heic`, `.jpeg`, `.png`) a `addMusic` (`.audio`).
    /// Rozhodují o tom, kam přetažený soubor půjde; jediné místo, kde se to
    /// z přípony pozná.
    static let stillExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff"]
    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf", "flac"]

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
