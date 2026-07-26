//
//  Main.swift
//  Projekt Krása / Flatten
//
//      swift run Flatten <soubor.mp4> [--out cesta.mov]
//      swift run Flatten --all [složka]
//      swift run Flatten --sync <originál> <zploštěný>
//      swift run Flatten --transients [složka]
//
//  Výchozí výstup jde do TestClips/flattened/ — TestClips je ignorované
//  gitem, takže se gigabajty ProRes nemůžou omylem dostat do repozitáře.
//

import AVFoundation
import Foundation
import ProbeKit

@main
struct FlattenTool {

    static let mediaExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts"]

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else { printUsage(); return }

        switch arguments[0] {
        case "-h", "--help":
            printUsage()
        case "--sync":
            guard arguments.count >= 3 else {
                fail("--sync potřebuje dva soubory: originál a zploštěný.")
            }
            await runSync(original: URL(fileURLWithPath: arguments[1]),
                          flattened: URL(fileURLWithPath: arguments[2]))
        case "--transients":
            let folder = arguments.count > 1
                ? URL(fileURLWithPath: arguments[1])
                : defaultClipsFolder()
            await runTransients(folder: folder)
        case "--frames":
            guard arguments.count >= 2 else {
                fail("--frames potřebuje soubor.")
            }
            let count = arguments.count >= 3 ? (Int(arguments[2]) ?? 4) : 4
            await runFrames(url: URL(fileURLWithPath: arguments[1]), count: count)
        case "--all":
            let folder = arguments.count > 1
                ? URL(fileURLWithPath: arguments[1])
                : defaultClipsFolder()
            await runBatch(folder: folder)
        default:
            let source = URL(fileURLWithPath: arguments[0])
            var output: URL?
            if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
                output = URL(fileURLWithPath: arguments[index + 1])
            }
            await runFlatten(source: source, output: output ?? defaultOutput(for: source))
        }
    }

    // MARK: - Zploštění

    static func runFlatten(source: URL, output: URL) async {
        print("▸ \(source.lastPathComponent) → \(output.lastPathComponent)")
        do {
            let result = try await Flattener.flatten(source: source, to: output)
            printResult(result)
        } catch {
            fail("Zploštění selhalo: \(error.localizedDescription)")
        }
    }

    static func runBatch(folder: URL) async {
        guard let files = mediaFiles(in: folder), !files.isEmpty else {
            fail("Ve složce \(folder.path) nejsou žádné mediální soubory.")
        }
        print("Zplošťuje se \(files.count) soubor(ů). ProRes ve 4K je velký, počítej s minutami.\n")
        for file in files {
            await runFlatten(source: file, output: defaultOutput(for: file))
            print("")
        }
    }

    static func printResult(_ r: FlattenResult) {
        let fd = r.frameDuration
        print("  Zdroj      \(r.sourceVerdict.shortLabel) · \(r.sourceFrameCount) vzorků"
            + " · \(fmt(r.sourceDuration.seconds, 3)) s")
        print("  Mřížka     \(fd.value)/\(fd.timescale) = \(fmt(r.measuredFrameRate, 4)) fps"
            + "  (z modu, ne z nominalFrameRate)")
        print("  Zapsáno    \(r.writtenFrameCount) snímků, z toho \(r.heldFrames) podržených")
        print("  Obraz      ProRes 422 Proxy, plné rozlišení, pixely \(r.pixelFormat)"
            + ", \(r.bitDepth) bit\(r.bitDepthWasDetected ? "" : " (odhad — BitsPerComponent chybí)")")
        if r.audioSampleRate > 0 {
            print("  Zvuk       LPCM \(r.audioChannels) kanál(ů) \(fmt(r.audioSampleRate / 1000, 1)) kHz"
                + " — schválně ne AAC, ten by přidal vlastní priming")
        }
        print("  Délka      zdroj \(fmt(r.sourceDuration.seconds, 3)) s"
            + " → výstup \(fmt(r.outputDuration.seconds, 3)) s"
            + " (rozdíl \(fmt((r.outputDuration.seconds - r.sourceDuration.seconds) * 1000, 1)) ms)")
        print("  Trvalo     \(fmt(r.elapsedSeconds, 1)) s")
        print("  Soubor     \(r.outputURL.path)")
    }

    // MARK: - Snímky na oční kontrolu

    static func runFrames(url: URL, count: Int) async {
        let folder = url.deletingLastPathComponent().appendingPathComponent("frames")
        do {
            let written = try await FrameExport.export(from: url, to: folder, count: count)
            print("Vytaženo \(written.count) snímků z \(url.lastPathComponent):")
            for file in written { print("  \(file.path)") }
        } catch {
            fail("Export snímků selhal: \(error.localizedDescription)")
        }
    }

    // MARK: - Test synchronu

    static func runSync(original: URL, flattened: URL) async {
        do {
            let before = try await SyncProbe.analyze(url: original)
            let after = try await SyncProbe.analyze(url: flattened)

            print("═══ TEST SYNCHRONU ═══\n")
            print("  Originál:  \(before.name)")
            print("  Zploštěný: \(after.name)")
            print("  Oba čtené přes AVComposition, takže edit list je aplikovaný.\n")

            compare(label: "Tlesknutí na začátku", before: before.start, after: after.start)
            compare(label: "Tlesknutí na konci", before: before.end, after: after.end)

            print("\n  Pozn.: rozdíl v jednotkách ms je kvantizace na snímkovou mřížku.")
            print("         Rozdíl kolem 44 ms by znamenal, že některá cesta obešla edit list.")
        } catch {
            fail("Test synchronu selhal: \(error.localizedDescription)")
        }
    }

    static func compare(label: String, before: TransientWindow?, after: TransientWindow?) {
        guard let before, let after else {
            print("  \(label): nepodařilo se najít transient v jednom ze souborů")
            return
        }
        let onsetDelta = (after.onsetTime - before.onsetTime) * 1000
        let peakDelta = (after.peakTime - before.peakTime) * 1000
        print("  \(label)")
        print("    náběh   originál \(fmt(before.onsetTime, 4)) s → zploštěný \(fmt(after.onsetTime, 4)) s"
            + "   rozdíl \(signed(onsetDelta)) ms")
        print("    vrchol  originál \(fmt(before.peakTime, 4)) s → zploštěný \(fmt(after.peakTime, 4)) s"
            + "   rozdíl \(signed(peakDelta)) ms")
        print("    amplituda \(fmt(Double(before.peak), 3)) → \(fmt(Double(after.peak), 3))"
            + ", crest faktor \(fmt(before.crestFactor, 1))× → \(fmt(after.crestFactor, 1))×")
    }

    // MARK: - Křížová kontrola, kde je tlesknutí

    static func runTransients(folder: URL) async {
        guard let files = mediaFiles(in: folder), !files.isEmpty else {
            fail("Ve složce \(folder.path) nejsou žádné mediální soubory.")
        }

        print("═══ DETEKCE TRANSIENTŮ ═══\n")
        print("  Křížová kontrola k ručnímu označení v CLIPS.txt.")
        print("  Hledá se ostrý transient na začátku i na konci — podpis tlesknutí.\n")

        var analyses: [AudioAnalysis] = []
        for file in files {
            do {
                let analysis = try await SyncProbe.analyze(url: file)
                printAnalysis(analysis)
                analyses.append(analysis)
            } catch {
                print("  ✗ \(file.lastPathComponent): \(error.localizedDescription)\n")
            }
        }
        let candidates = analyses.filter(\.looksLikeClap)

        print("═══ ZÁVĚR ═══\n")
        print("  Pořadí podle toho, jak blízko ke krajům leží oba vrcholy:")
        for analysis in analyses.sorted(by: { $0.worstEdgeDistance < $1.worstEdgeDistance }) {
            print("    \(fmt(analysis.worstEdgeDistance, 2)) s   \(analysis.name)"
                + (analysis.looksLikeClap ? "  ← kandidát" : ""))
        }
        print("")
        if candidates.isEmpty {
            print("  Žádný klip nevypadá jako záměrná synchronizační značka.")
            print("  Buď mezi nimi referenční klip není, nebo se netleskalo dost u krajů.")
            print("  Rozhoduje tvoje označení, tohle je jen křížová kontrola.")
        } else {
            print("  Kandidát na referenční klip: "
                + candidates.map(\.name).joined(separator: ", "))
            print("  Porovnej s CLIPS.txt. Když se to rozchází, ověř si klip uchem —")
            print("  ani jedno z toho není důkaz.")
        }
        print("\n  ⚠ Samotný crest faktor NEROZLIŠUJE: na téhle sadě vyšel u všech pěti")
        print("    klipů mezi 12× a 30×, protože každý obsahuje nějaký hlasitý zvuk.")
        print("    Rozlišuje až poloha vrcholu vůči kraji — kdo tleská na synchron,")
        print("    tleská hned na začátku a těsně před koncem. Práh je 1,5 s.")
    }

    static func printAnalysis(_ a: AudioAnalysis) {
        print("▸ \(a.name)  (\(fmt(a.duration, 2)) s, \(a.channels) kanál(ů),"
            + " \(fmt(a.sampleRate / 1000, 1)) kHz)")
        print("  Celkové RMS \(fmt(a.overallRMS, 4))")
        for window in [a.start, a.end].compactMap({ $0 }) {
            print("  \(window.label.padding(toLength: 8, withPad: " ", startingAt: 0))"
                + " vrchol \(fmt(Double(window.peak), 3)) v \(fmt(window.peakTime, 3)) s"
                + ", crest \(fmt(window.crestFactor, 1))×")
            print("           od kraje \(fmt(window.distanceFromEdge, 3)) s"
                + ", náběh→vrchol \(fmt(window.onsetToPeak, 3)) s")
        }
        print("  → \(a.looksLikeClap ? "VYPADÁ jako tlesknutí na obou koncích" : "nevypadá jako záměrná značka")\n")
    }

    // MARK: - Cesty

    static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Flatten
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // balíček
    }

    static func defaultClipsFolder() -> URL {
        packageRoot().deletingLastPathComponent().appendingPathComponent("TestClips")
    }

    /// Výstup do TestClips/flattened/. Ta složka je ignorovaná gitem.
    static func defaultOutput(for source: URL) -> URL {
        defaultClipsFolder()
            .appendingPathComponent("flattened")
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent + "_cfr.mov")
    }

    static func mediaFiles(in folder: URL) -> [URL]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents
            .filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Drobnosti

    static func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + fmt(value, 2)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    static func printUsage() {
        print("""
        Flatten — přepis VFR souboru na pevnou snímkovou mřížku.

          swift run Flatten <soubor.mp4> [--out cesta.mov]
          swift run Flatten --all [složka]
          swift run Flatten --sync <originál> <zploštěný>
          swift run Flatten --transients [složka]

        Cílová frekvence se bere z MĚŘENÉHO modu délek vzorků, ne z
        nominalFrameRate. Zvuk se čte přes AVComposition, aby se respektoval
        edit list. Výstup je ProRes 422 Proxy v plném rozlišení, zvuk LPCM.

        Výchozí výstup: TestClips/flattened/<název>_cfr.mov
        """)
    }
}
