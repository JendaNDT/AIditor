//
//  Main.swift
//  Projekt Krása / Ramp
//
//      swift run Ramp <soubor.mov> [--fps 30] [--slow 0.25] [--segments 8,4,2,1]
//
//  Bez argumentů si vezme zploštěný slow-mo klip z kroku 3 spiku a projede
//  všechny čtyři jemnosti segmentace za sebou.
//

import AVFoundation
import Foundation
import ProbeKit
import SpeedRampEngine

@main
struct RampTool {

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            printUsage()
            return
        }

        let source = arguments.first.map { URL(fileURLWithPath: $0) } ?? defaultSource()
        let fps = doubleOption("--fps", in: arguments) ?? 30
        let slow = doubleOption("--slow", in: arguments) ?? 0.25
        let steps = listOption("--segments", in: arguments) ?? [8, 4, 2, 1]
        let pitch = pitchOption(in: arguments)

        guard FileManager.default.fileExists(atPath: source.path) else {
            fail("Soubor \(source.path) neexistuje. Nejdřív ho zploštit: swift run Flatten")
        }

        print("▸ Zdroj: \(source.lastPathComponent)")
        await printSourceInfo(source)
        print("  Ramp:  1,0 → \(fmt(slow, 2))× → 1,0, výstup \(fmt(fps, 0)) fps")
        print("  Běhy:  framesPerSegment \(steps.map(String.init).joined(separator: ", "))")
        print("  Zvuk:  korekce výšky \(shortPitch(pitch))\n")

        var results: [RampResult] = []
        for framesPerSegment in steps {
            print("── framesPerSegment \(framesPerSegment) ──")
            let output = defaultOutput(for: source, framesPerSegment: framesPerSegment, pitch: pitch)
            do {
                let result = try await Ramper.run(source: source,
                                                  to: output,
                                                  outputFrameRate: fps,
                                                  framesPerSegment: framesPerSegment,
                                                  slowSpeed: slow,
                                                  pitchAlgorithm: pitch)
                printResult(result)
                results.append(result)
            } catch {
                print("  ✗ selhalo: \(error.localizedDescription)")
            }
            print("")
        }

        printComparison(results)
    }

    // MARK: - Výpis

    static func printSourceInfo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return }
        let ramp = try? SpeedRamp.classicSlowMotion(sourceDuration: duration.seconds, slowSpeed: 0.25)
        print("  Délka: \(fmt(duration.seconds, 3)) s"
            + (ramp.map { " → ramp spotřebuje \(fmt($0.sourceConsumed, 3)) s,"
                         + " výstup \(fmt($0.outputDuration, 4)) s" } ?? ""))
    }

    static func printResult(_ r: RampResult) {
        let render = r.render
        let measured = render.outputDuration.seconds
        let delta = (measured - r.expectedOutputDuration) * 1000

        print("  Segmentů   \(r.segmentCount)"
            + "  ·  rychlost \(fmt(r.slowestSpeed, 4))× až \(fmt(r.fastestSpeed, 4))×")
        print("  Skok       největší rozdíl rychlosti mezi sousedy \(fmt(r.largestSpeedStep, 4))×")
        print("  Délka      čekáno \(fmt(r.expectedOutputDuration, 4)) s"
            + " · kompozice \(fmt(r.compositionDuration.seconds, 4)) s"
            + " · výstup \(fmt(measured, 4)) s"
            + "  (rozdíl \(signed(delta)) ms)")
        print("  Snímků     \(render.writtenFrameCount), z toho \(render.heldFrames) podržených")
        if let algorithm = render.pitchAlgorithm {
            print("  Zvuk       korekce výšky: \(algorithm.replacingOccurrences(of: "AVAudioTimePitchAlgorithm", with: ""))")
        }
        if let size = r.fileSizeBytes {
            print("  Soubor     \(fmt(Double(size) / 1_048_576, 1)) MB · \(r.outputURL.lastPathComponent)")
        }
        print("  Trvalo     \(fmt(render.elapsedSeconds, 1)) s")
    }

    static func printComparison(_ results: [RampResult]) {
        guard !results.isEmpty else { return }
        print("═══ POROVNÁNÍ ═══\n")

        let header = ["fr/seg", "segmentů", "délka", "snímků", "podrž.", "skok rychl.", "velikost"]
        var rows: [[String]] = []
        for r in results {
            rows.append([
                String(r.framesPerSegment),
                String(r.segmentCount),
                "\(fmt(r.render.outputDuration.seconds, 3)) s",
                String(r.render.writtenFrameCount),
                String(r.render.heldFrames),
                "\(fmt(r.largestSpeedStep, 4))×",
                r.fileSizeBytes.map { "\(fmt(Double($0) / 1_048_576, 1)) MB" } ?? "—",
            ])
        }

        let widths = header.indices.map { column in
            max(header[column].count, rows.map { $0[column].count }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            cells.indices.map { pad(cells[$0], widths[$0]) }.joined(separator: "  ")
        }
        print("  " + line(header))
        print("  " + widths.map { String(repeating: "─", count: $0) }.joined(separator: "  "))
        for row in rows { print("  " + line(row)) }

        print("\n  Menší framesPerSegment = jemnější křivka, ale víc hranic mezi úseky.")
        print("  Každá hranice je místo, kde se skokem mění rychlost zvuku — a tedy")
        print("  kandidát na lupnutí. Poslechni si je a řekni, kde to začne vadit.")
        print("  To číslo je jediný výstup, kvůli kterému tenhle experiment běží.")
    }

    // MARK: - Argumenty a cesty

    static func doubleOption(_ name: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1].replacingOccurrences(of: ",", with: "."))
    }

    static func listOption(_ name: String, in arguments: [String]) -> [Int]? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        let values = arguments[index + 1].split(separator: ",").compactMap { Int($0) }
        return values.isEmpty ? nil : values
    }

    static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func defaultSource() -> URL {
        packageRoot()
            .deletingLastPathComponent()
            .appendingPathComponent("TestClips/flattened/20260725_203813_cfr.mov")
    }

    /// Algoritmus se do názvu dostane jen když není výchozí — ať se A/B
    /// nesloučí do jednoho souboru a nepřepíše se dosavadní měření.
    static func defaultOutput(for source: URL,
                              framesPerSegment: Int,
                              pitch: AVAudioTimePitchAlgorithm) -> URL {
        let suffix = pitch == .spectral ? "" : "_" + shortPitch(pitch)
        return source.deletingLastPathComponent()
            .appendingPathComponent("ramped")
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent
                                    + "_ramp_seg\(framesPerSegment)\(suffix).mov")
    }

    static func pitchOption(in arguments: [String]) -> AVAudioTimePitchAlgorithm {
        guard let index = arguments.firstIndex(of: "--pitch"), index + 1 < arguments.count else {
            return .spectral
        }
        switch arguments[index + 1].lowercased() {
        case "timedomain": return .timeDomain
        case "varispeed":  return .varispeed
        case "spectral":   return .spectral
        default:
            fail("Neznámý algoritmus. Na macOS jsou: spectral, timeDomain, varispeed.")
        }
    }

    static func shortPitch(_ pitch: AVAudioTimePitchAlgorithm) -> String {
        pitch.rawValue.replacingOccurrences(of: "AVAudioTimePitchAlgorithm", with: "")
    }

    // MARK: - Drobnosti

    static func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + fmt(value, 1)
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    static func printUsage() {
        print("""
        Ramp — plynulá rychlostní křivka segmentací na mikro-úseky.

          swift run Ramp [soubor.mov] [--fps 30] [--slow 0.25] [--segments 8,4,2,1]

        Bez argumentů si vezme TestClips/flattened/20260725_203813_cfr.mov
        a projede framesPerSegment 8, 4, 2 a 1 za sebou.

        Křivku počítá SpeedRampEngine (31 testů). scaleTimeRange se aplikuje
        pozpátku, časy se převádějí kumulativně v celých tickách. Výstup je
        ProRes 422 Proxy na pevné mřížce, zvuk LPCM s korekcí výšky Spectral.
        """)
    }
}
