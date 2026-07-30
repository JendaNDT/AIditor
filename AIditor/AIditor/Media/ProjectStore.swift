//
//  ProjectStore.swift
//  Projekt AIditor
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
import CryptoKit
import Foundation
import TimelineModel
import UniformTypeIdentifiers

/// Řádek v „Poslední projekty" na prázdném startu (fáze 18, modul 12).
///
/// ⚠️ Čísla (počet záběrů, délka) jsou ULOŽENÁ, ne dopočítaná ze souboru.
/// Projekt na odpojeném disku se otevřít nedá, takže by se u něj počítat
/// nedaly — a řádek, který u poloviny projektů mlčí, je horší než řádek
/// s číslem z doby, kdy se projekt naposled ukládal.
struct RecentProject: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let modifiedAt: Date
    let shotCount: Int
    let durationSeconds: Double
    /// Bookmark se nerozbalil nebo soubor na cestě není — disk bývá odpojený.
    let isOffline: Bool
}

@MainActor
final class ProjectStore: ObservableObject {

    /// Kam je projekt uložený. `nil` = zatím neuložený (obraz skenu).
    @Published private(set) var fileURL: URL?
    @Published private(set) var lastSavedAt: Date?
    /// Poslední projekty pro prázdný start. Plní `refreshRecentProjects()` —
    /// ne getter, protože zjišťování offline stavu rozbaluje bookmarky
    /// a to se nesmí dělat při každém překreslení.
    @Published private(set) var recentProjects: [RecentProject] = []
    /// Projekt se liší od baseline (poslední uložený/otevřený stav; u
    /// čerstvého skenu sken samotný — jinak by „neuloženo" svítilo pořád).
    @Published private(set) var isDirty = false

    /// `nil` = ještě není co chránit (před prvním skenem/otevřením).
    /// Pozor: porovnávat s `Project.empty()` nejde — razí náhodná ID stop.
    private var baseline: Project?

    /// Datum vzniku se čte ze souboru a při ukládání vrací — jinak by ho
    /// každé uložení přepsalo dneškem.
    private var createdAt = Date()

    /// Security scope držené po dobu běhu: soubor projektu a assety.
    /// Nepárované stopAccessing tu není omylem — přístup má žít, dokud
    /// žije aplikace.
    private var heldScopes: [URL] = []

    private static let lastProjectKey = "cz.projektkrasa.lastProject"
    private static let recentProjectsKey = "cz.projektkrasa.recentProjects"
    /// Kolik projektů si seznam pamatuje. Návrh ukazuje tři řádky, pás jich
    /// unese pět — víc už je archiv, ne „poslední".
    private static let recentProjectsLimit = 8

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
        // „Uložit jako" z neuloženého projektu: záloha starého slotu už
        // nemá co chránit — smazat PŘED přepnutím fileURL, pak ještě
        // zálohu nového slotu (stav je teď v souboru).
        discardAutosave()
        fileURL = url
        discardAutosave()
        lastSavedAt = Date()
        markCurrent(project)
        rememberLastProject(url)
        rememberRecent(project: project, at: url, modifiedAt: file.modifiedAt)
    }

    func load(from url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        let file = try ProjectFile.decode(data)
        createdAt = file.createdAt
        fileURL = url
        lastSavedAt = file.modifiedAt
        rememberLastProject(url)
        rememberRecent(project: file.project, at: url, modifiedAt: file.modifiedAt)
        return file.project
    }

    /// Nový neuložený projekt (import klipů zahodil ten starý obraz).
    func detachFromFile() {
        fileURL = nil
        lastSavedAt = nil
        createdAt = Date()
    }

    // MARK: Baseline a špinavost

    /// Nový výchozí stav: po uložení, otevření nebo skenu. Od něj se měří
    /// „neuloženo" a jen proti němu se píše autosave.
    func markCurrent(_ project: Project) {
        baseline = project
        isDirty = false
    }

    func updateDirty(_ project: Project) {
        // Bez baseline NENÍ špinavo: čerstvě spuštěná aplikace s prázdným
        // projektem by se jinak hned hlásila jako „neuloženo" a za 5 s by
        // se prázdný projekt zbytečně zazálohoval (nalezeno CLI ověřením).
        let dirty = baseline.map { $0 != project } ?? false
        if isDirty != dirty { isDirty = dirty }
    }

    /// Po obnově neuloženého projektu ze zálohy: baseline je prázdný projekt
    /// (od obnoveného se VŽDY liší — i prázdná osa má jiná ID stop), takže
    /// obnovená práce zůstává „neuložená" a autosave ji dál chrání.
    func markRestoredUnsaved() {
        baseline = Project.empty()
        isDirty = true
    }

    // MARK: Autosave

    /// Zálohy žijí v Application Support, NE vedle projektu — přežijí
    /// i přesun či smazání souboru a nešpiní uživateli složku.
    private static var autosaveDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Autosaves", isDirectory: true)
    }

    /// Slot zálohy: otisk cesty projektu, pro neuložený projekt pevné jméno.
    private var autosaveSlotURL: URL? {
        guard let directory = Self.autosaveDirectory else { return nil }
        let name: String
        if let fileURL {
            let digest = SHA256.hash(data: Data(fileURL.path.utf8))
            name = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            name = "neulozeny-projekt"
        }
        return directory.appendingPathComponent(name + ".projektkrasa")
    }

    /// Zapíše zálohu, když je co zálohovat. Volá se debounced po změnách
    /// projektu a při ukončování aplikace.
    func autosaveIfDirty(_ project: Project) {
        guard isDirty, let url = autosaveSlotURL else { return }
        let file = ProjectFile(project: project, name: displayName,
                               createdAt: createdAt, modifiedAt: Date())
        guard let data = try? file.encoded() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Soubor zálohy aktuálního slotu. **Jen pro `--empty-start-check`**,
    /// který si obsah slotu odloží a po sobě ho vrátí — kontrola nesmí přepsat
    /// zálohu skutečné neuložené práce uživatele (běží v témže kontejneru).
    var autosaveFileURL: URL? { autosaveSlotURL }

    /// Záloha aktuálního slotu, pokud existuje a dá se přečíst.
    func pendingAutosave() -> ProjectFile? {
        guard let url = autosaveSlotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ProjectFile.decode(data)
    }

    func discardAutosave() {
        guard let url = autosaveSlotURL else { return }
        try? FileManager.default.removeItem(at: url)
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

    // MARK: Poslední projekty (prázdný start, fáze 18, modul 12)

    /// Uložený řádek. Bookmark je tu ze stejného důvodu jako u posledního
    /// projektu: bez něj by sandbox po restartu na soubor nesměl a každý
    /// projekt by se hlásil jako offline.
    private struct StoredRecent: Codable {
        var path: String
        var name: String
        var modifiedAt: Date
        var shotCount: Int
        var durationSeconds: Double
        var bookmark: Data?
    }

    /// Zapíše (nebo přepíše) řádek po uložení i po otevření projektu.
    /// Čísla se berou z projektu, který se právě prošel — počítat je později
    /// by znamenalo otevřít každý soubor v seznamu.
    private func rememberRecent(project: Project, at url: URL, modifiedAt: Date) {
        let timeline = project.timeline
        let shots = timeline.tracks.filter { $0.kind == .video }
            .reduce(0) { $0 + $1.clips.count }
        let entry = StoredRecent(
            path: url.path,
            name: url.deletingPathExtension().lastPathComponent,
            modifiedAt: modifiedAt,
            shotCount: shots,
            // `duration` je O(klipů) — tady se volá jednou při uložení nebo
            // otevření, ne v kreslicí cestě (poučení z modulu 6).
            durationSeconds: Double(project.duration.count) / Double(timeline.frameRate),
            bookmark: try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil))
        var all = Self.loadStoredRecents().filter { $0.path != url.path }
        all.insert(entry, at: 0)
        Self.saveStoredRecents(Array(all.prefix(Self.recentProjectsLimit)))
        refreshRecentProjects()
    }

    /// Přepočítá seznam včetně dostupnosti souborů. Volá se při startu,
    /// po uložení a po otevření — ne při kreslení.
    func refreshRecentProjects() {
        recentProjects = Self.loadStoredRecents().map { stored in
            RecentProject(path: stored.path,
                          name: stored.name,
                          modifiedAt: stored.modifiedAt,
                          shotCount: stored.shotCount,
                          durationSeconds: stored.durationSeconds,
                          isOffline: !Self.isReachable(stored))
        }
    }

    /// URL projektu ze seznamu, s otevřeným security scope. `nil` = nedostupný
    /// (odpojený disk, smazaný soubor) — volající to má říct, ne mlčet.
    func resolveRecent(_ recent: RecentProject) -> URL? {
        guard let stored = Self.loadStoredRecents().first(where: { $0.path == recent.path })
        else { return nil }
        if let data = stored.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                heldScopes.append(url)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url
            }
        }
        let url = URL(fileURLWithPath: stored.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// ⚠️ Přístup se otevírá a HNED zavírá. V sandboxu vrátí `fileExists`
    /// pro cestu bez oprávnění `false`, takže se bez scope nedá odlišit
    /// „soubor není" od „nesmíme se podívat" — a všechny projekty by se
    /// hlásily jako offline. Držet scope kvůli pouhé kontrole existence by
    /// naopak znamenalo osm nepárovaných přístupů při každém startu.
    private static func isReachable(_ stored: StoredRecent) -> Bool {
        if let data = stored.bookmark {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale) else { return false }
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                return FileManager.default.fileExists(atPath: url.path)
            }
            return FileManager.default.fileExists(atPath: url.path)
        }
        return FileManager.default.fileExists(atPath: stored.path)
    }

    /// Odložený stav evidence. **Jen pro `--empty-start-check`**: kontrola si
    /// do seznamu uloží dočasný projekt, aby ověřila offline řádek, a musí
    /// po sobě uklidit — jinak by uživateli v „Poslední projekty" zůstal
    /// mrtvý řádek a přepsaný „poslední projekt" ze startu aplikace.
    struct RecentsSnapshot {
        let recents: Data?
        let last: Data?
    }

    func snapshotRecents() -> RecentsSnapshot {
        RecentsSnapshot(recents: UserDefaults.standard.data(forKey: Self.recentProjectsKey),
                        last: UserDefaults.standard.data(forKey: Self.lastProjectKey))
    }

    func restoreRecents(_ snapshot: RecentsSnapshot) {
        let defaults = UserDefaults.standard
        if let recents = snapshot.recents { defaults.set(recents, forKey: Self.recentProjectsKey) }
        else { defaults.removeObject(forKey: Self.recentProjectsKey) }
        if let last = snapshot.last { defaults.set(last, forKey: Self.lastProjectKey) }
        else { defaults.removeObject(forKey: Self.lastProjectKey) }
        refreshRecentProjects()
    }

    private static func loadStoredRecents() -> [StoredRecent] {
        guard let data = UserDefaults.standard.data(forKey: recentProjectsKey),
              let all = try? JSONDecoder().decode([StoredRecent].self, from: data)
        else { return [] }
        return all
    }

    private static func saveStoredRecents(_ all: [StoredRecent]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: recentProjectsKey)
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
