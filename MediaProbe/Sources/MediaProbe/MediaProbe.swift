//
//  MediaProbe.swift
//  Projekt Krása / MediaProbe
//
//  Sonda na testovací klipy. Nic nerenderuje, nic nedekóduje, nic nezapisuje
//  do zdrojových souborů — jen čte metadata a délky vzorků.
//
//      swift run MediaProbe [složka] [--results cesta/RESULTS.md]
//
//  Bez argumentů projde ../TestClips relativně k balíčku a zapíše RESULTS.md
//  vedle sebe.
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
        let folder = folderArgument.map { URL(fileURLWithPath: $0) }
            ?? packageRoot.deletingLastPathComponent().appendingPathComponent("TestClips")
        let resultsURL = resultsArgument.map { URL(fileURLWithPath: $0) }
            ?? packageRoot.appendingPathComponent("RESULTS.md")

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

        var reports: [ClipReport] = []
        for (index, file) in files.enumerated() {
            FileHandle.standardError.write(
                Data("  [\(index + 1)/\(files.count)] \(file.lastPathComponent)…\n".utf8))
            reports.append(await ClipInspector.inspect(url: file))
        }

        printConsole(reports: reports)
        writeResults(reports: reports, to: resultsURL, folder: folder)
    }

    // MARK: - Vstup

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
        print("  Kolísání: největší odchylka od nejčastější délky, BEZ zahozených snímků")
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

    static func writeResults(reports: [ClipReport], to url: URL, folder: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []

        lines.append("# MediaProbe — naměřené vlastnosti testovacích klipů")
        lines.append("")
        lines.append("*Vygenerováno \(stamp) nástrojem `MediaProbe`.*")
        lines.append("")
        lines.append("Klipy samotné jsou v `.gitignore` (jsou to gigabajty videa), takže tenhle")
        lines.append("soubor je jediný záznam o tom, na čem se měřilo. Negeneruj ho ručně —")
        lines.append("spusť `swift run MediaProbe` a commitni výsledek.")
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
        lines.append("Sloupec `Kolísání` je bez zahozených snímků — ty mají vlastní sloupec,")
        lines.append("aby jeden dvojnásobný vzorek nezakryl, že časování je jinak klidné.")
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
          --results  kam zapsat markdown (výchozí: MediaProbe/RESULTS.md)

        Čte rozlišení, orientaci, kodeky, snímkovou frekvenci, edit list a
        skutečné délky vzorků. Nic nedekóduje ani nemění.
        """)
    }
}
