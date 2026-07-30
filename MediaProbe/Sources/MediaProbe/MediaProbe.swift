//
//  MediaProbe.swift
//  Projekt AIditor / MediaProbe
//
//  Sonda na testovací klipy. Nic nerenderuje, nic nedekóduje, nic nezapisuje
//  do zdrojových souborů — jen čte metadata a délky vzorků.
//
//      swift run MediaProbe [složka] [--results cesta/RESULTS.md]
//
//  Bez argumentů projde ../TestClips relativně k balíčku a zapíše RESULTS.md
//  vedle sebe. Při měření JINÉ složky se bez --results žádný soubor nezapisuje
//  — RESULTS.md je kanonický záznam o TestClips a nesmí ho přepsat cizí běh.
//

import AVFoundation
import Foundation

@main
struct MediaProbe {

    static let mediaExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mts", "m2ts", "mxf", "hevc", "3gp",
    ]

    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        var folderArgument: String?
        var resultsArgument: String?

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--results":
                resultsArgument = iterator.next()
            case "-h", "--help":
                printUsage()
                return
            default:
                folderArgument = argument
            }
        }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MediaProbe
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // balíček
        let testClipsFolder = packageRoot.deletingLastPathComponent()
            .appendingPathComponent("TestClips")
        let folder = folderArgument.map { URL(fileURLWithPath: $0) } ?? testClipsFolder

        // RESULTS.md je kanonický záznam o TestClips — klipy samotné jsou
        // v .gitignore, takže přepsat ho výsledkem cizí složky znamená ten
        // záznam ZTRATIT (stalo se ve fázi 5, všimlo si to až ve fázi 10).
        // Bez --results se proto zapisuje jen při měření právě TestClips;
        // u jiné složky zůstane výsledek v konzoli.
        let resultsURL: URL?
        if let resultsArgument {
            resultsURL = URL(fileURLWithPath: resultsArgument)
        } else if canonicalPath(folder) == canonicalPath(testClipsFolder) {
            resultsURL = packageRoot.appendingPathComponent("RESULTS.md")
        } else {
            resultsURL = nil
        }

        guard let files = mediaFiles(in: folder) else {
            FileHandle.standardError.write(
                Data("Složka \(folder.path) neexistuje nebo ji nejde přečíst.\n".utf8))
            exit(1)
        }
        guard !files.isEmpty else {
            print("Ve složce \(folder.path) nejsou žádné mediální soubory.")
            return
        }

        print("MediaProbe — \(files.count) soubor(ů) ve složce \(folder.path)")
        print("Čtou se skutečné délky vzorků, u velkých klipů to chvíli trvá.\n")

        // Poznámky, co se na kterém klipu točilo. RESULTS.md je generovaný,
        // takže ručně psaný obsah musí přijít odjinud.
        let notes = ClipNotes.load(from: packageRoot.appendingPathComponent("CLIPS.txt"))
        if notes.isEmpty {
            FileHandle.standardError.write(
                Data("  (CLIPS.txt nenalezen nebo prázdný — poznámky ke klipům budou chybět)\n".utf8))
        }

        var reports: [ClipReport] = []
        for (index, file) in files.enumerated() {
            FileHandle.standardError.write(
                Data("  [\(index + 1)/\(files.count)] \(file.lastPathComponent)…\n".utf8))
            reports.append(await ClipInspector.inspect(url: file, note: notes[file.lastPathComponent]))
        }

        printConsole(reports: reports)
        if let resultsURL {
            writeResults(reports: reports, to: resultsURL, folder: folder,
                         canonical: canonicalPath(folder) == canonicalPath(testClipsFolder))
        } else {
            print("""

              Markdown se nezapsal: měřila se jiná složka než TestClips a RESULTS.md
              je kanonický záznam právě o TestClips. Chceš-li výsledek do souboru,
              přidej --results cesta/k/souboru.md.
            """)
        }
    }

    // MARK: - Vstup

    /// Táž složka se dá zadat mnoha zápisy (relativně, s `..`, přes symlink).
    /// Porovnávat se proto musí až vyžehlená absolutní cesta.
    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func mediaFiles(in folder: URL) -> [URL]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        return contents
            .filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Výstup do konzole

    static func printConsole(reports: [ClipReport]) {
        let rows = reports.map(Report.summaryRow)
        print("═══ SOUHRN ═══\n")
        for line in Report.asciiTable(header: Report.summaryHeader, rows: rows) {
            print(line)
        }

        print("\n  Verdikt:  CFR = všechny vzorky stejné · CFR≈ = rozdíl do 1 ticku (zaokrouhlení)")
        print("            CFR↓n = konstantní, ale s n zahozenými snímky · CFR± = odchylka jen na okraji")
        print("            VFR = skutečně proměnlivé časování, nevysvětlí ho ani jedno z výše uvedeného")
        print("  Kolísání: největší odchylka od nejčastější délky UVNITŘ stopy")
        print("            (bez okrajových vzorků a bez zahozených snímků — mají vlastní sloupce)")
        print("  Okraje:   první/poslední vzorek, když nesedí na modu; „ok\" = sedí")
        print("  Zahozeno: chybějící snímky (vzorek je celočíselným násobkem délky snímku)\n")

        print("═══ DETAIL ═══\n")
        for report in reports {
            for line in Report.detail(report) { print(line) }
            print("")
        }

        print("═══ ZÁVĚR ═══\n")
        for line in Report.conclusion(reports) {
            print(line.isEmpty ? "" : "  \(line)")
        }
    }

    // MARK: - Zápis RESULTS.md

    static func writeResults(reports: [ClipReport], to url: URL, folder: URL, canonical: Bool) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []

        lines.append("# MediaProbe — naměřené vlastnosti testovacích klipů")
        lines.append("")
        lines.append("*Vygenerováno \(stamp) nástrojem `MediaProbe`.*")
        lines.append("")
        if canonical {
            lines.append("Klipy samotné jsou v `.gitignore` (jsou to gigabajty videa), takže tenhle")
            lines.append("soubor je jediný záznam o tom, na čem se měřilo. Negeneruj ho ručně —")
            lines.append("spusť `swift run MediaProbe` a commitni výsledek.")
        } else {
            lines.append("⚠ Jednorázové měření jiné složky než `TestClips` (vyžádané přes")
            lines.append("`--results`). Kanonický záznam o testovacích klipech je")
            lines.append("`MediaProbe/RESULTS.md` — tenhle soubor ho nenahrazuje.")
        }
        lines.append("")
        lines.append("- **Zdrojová složka:** `\(folder.path)`")
        lines.append("- **Souborů:** \(reports.count)")
        lines.append("")
        lines.append("## Jak se to měří")
        lines.append("")
        lines.append("Apple nemá API, které řekne „tenhle soubor je VFR\". Délky jednotlivých")
        lines.append("vzorků se čtou přes `AVSampleCursor` (tabulka vzorků v kontejneru, bez")
        lines.append("dekódování), a když stopa kurzory neumí, přes `AVAssetReader` s")
        lines.append("`outputSettings: nil`. Porovnávají se **celá čísla v tickách timescale**,")
        lines.append("ne sekundy — plovoucí aritmetika by vyrobila rozptyl, který v souboru není.")
        lines.append("")
        lines.append("Každá délka se klasifikuje vůči nejčastější hodnotě (modu):")
        lines.append("")
        lines.append("| Kategorie | Podmínka | Co s tím |")
        lines.append("|---|---|---|")
        lines.append("| zaokrouhlení | odchylka ≤ 1 tick | nic, je to artefakt časové základny |")
        lines.append("| zahozený snímek | celočíselný násobek modu (±10 %) | doplnit duplikát |")
        lines.append("| nepravidelné | cokoli jiného | přepočítat časování |")
        lines.append("")
        lines.append("Verdikty: `CFR` všechny vzorky identické · `CFR≈` jen zaokrouhlení ·")
        lines.append("`CFR↓n` konstantní časování s n zahozenými snímky · `CFR±` nepravidelný")
        lines.append("jen krajní vzorek · `VFR` skutečně proměnlivé časování.")
        lines.append("")
        lines.append("Sloupec `Edit V/A` hlásí edit list zvlášť pro obraz a pro zvuk.")
        lines.append("")
        lines.append("`Kolísání` je odchylka **uvnitř** stopy — bez prvního a posledního vzorku")
        lines.append("a bez zahozených snímků. Obojí by číslo nafouklo o řád a zakrylo, že")
        lines.append("časování je jinak klidné. Nic se ale nezahazuje potichu: okraje mají")
        lines.append("sloupec `Okraje` a vlastní řádek v detailu, zahozené snímky sloupec")
        lines.append("`Zahozeno`. Detail navíc vždy uvádí i číslo se vším dohromady.")
        lines.append("")
        lines.append("## Co je na klipech")
        lines.append("")
        lines.append("Ručně udržované v `MediaProbe/CLIPS.txt` — názvy souborů jsou časová")
        lines.append("razítka a obsah záběru z metadat vyčíst nejde.")
        lines.append("")
        lines.append("| Soubor | Co se točilo |")
        lines.append("|---|---|")
        for report in reports {
            lines.append("| \(report.name) | \(report.note ?? "⚠ nevyplněno") |")
        }
        lines.append("")
        lines.append("## Souhrn")
        lines.append("")
        lines.append(contentsOf: Report.markdownTable(header: Report.summaryHeader,
                                                      rows: reports.map(Report.summaryRow)))
        lines.append("")
        lines.append("## Závěr")
        lines.append("")
        lines.append("```")
        lines.append(contentsOf: Report.conclusion(reports))
        lines.append("```")
        lines.append("")
        lines.append("## Detail")
        lines.append("")
        for report in reports {
            lines.append("### \(report.name)")
            lines.append("")
            lines.append("```")
            lines.append(contentsOf: Report.detail(report))
            lines.append("```")
            lines.append("")
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            print("\n  Zapsáno do \(url.path)")
        } catch {
            FileHandle.standardError.write(
                Data("Nepodařilo se zapsat \(url.path): \(error.localizedDescription)\n".utf8))
        }
    }

    static func printUsage() {
        print("""
        MediaProbe — sonda na vlastnosti mediálních souborů.

          swift run MediaProbe [složka] [--results cesta/RESULTS.md]

          složka     kde hledat klipy (výchozí: ../TestClips vedle balíčku)
          --results  kam zapsat markdown

        Bez --results se markdown zapíše do MediaProbe/RESULTS.md, ale JEN
        při měření složky TestClips — RESULTS.md je kanonický záznam právě
        o ní. U jiné složky zůstane výsledek v konzoli, dokud neřekneš
        --results.

        Čte rozlišení, orientaci, kodeky, snímkovou frekvenci, edit list a
        skutečné délky vzorků. Nic nedekóduje ani nemění.
        """)
    }
}
