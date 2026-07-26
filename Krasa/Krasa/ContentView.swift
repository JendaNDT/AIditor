//
//  ContentView.swift
//  Projekt Krása
//
//  Minimální UI fáze 1: otevřít klip, přehrát, krokovat, změřit.
//  Žádná timeline, žádné panely — to je fáze 2.
//

import AVFoundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "Vyber klip nebo složku s klipy."
    @Published var clips: [ClipTiming] = []
    @Published var selected: ClipTiming?
    @Published var isMeasuring = false
    @Published var reportLines: [String] = []

    let importer = MediaImporter()
    let controller = PlaybackController()
    private(set) var hostView: PlayerHostView?

    func attach(_ view: PlayerHostView) { hostView = view }

    // MARK: Import

    func openFiles(directories: Bool) async {
        let urls = importer.promptForAccess(directories: directories)
        guard !urls.isEmpty else { return }
        await ingest(urls: urls)
    }

    func restoreAndScan() async {
        let urls = importer.restoreRememberedAccess()
        guard !urls.isEmpty else { return }
        await ingest(urls: urls)
    }

    private func ingest(urls: [URL]) async {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                files.append(contentsOf: importer.videoFiles(in: url))
            } else {
                files.append(url)
            }
        }

        status = "Měřím časování \(files.count) klipů…"
        var found: [ClipTiming] = []
        for file in files {
            switch await VFRDetector.inspect(url: file) {
            case .success(let timing): found.append(timing)
            case .failure(let error):
                status = "\(file.lastPathComponent): \(error.localizedDescription)"
            }
        }
        clips = found.sorted { $0.name < $1.name }
        status = "\(clips.count) klipů. Vyber jeden a přehraj, nebo spusť měření."
        if selected == nil, let first = clips.first { await select(first) }
    }

    func select(_ clip: ClipTiming) async {
        selected = clip
        try? await controller.load(url: clip.url, measuredFrameRate: clip.measuredFrameRate)
    }

    // MARK: Měření

    /// Čeká, až bude přehrávač v okně. Display link se rozjede až tam,
    /// takže dřív by se měřilo do prázdna.
    private func waitForPlayerWindow(timeout: TimeInterval = 10) async -> PlayerHostView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let view = hostView, view.window != nil { return view }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    /// Změří konkrétní soubory. Prázdný seznam = všechny načtené klipy.
    /// Cesty musí ležet uvnitř složky, na kterou máme bookmark.
    func runBenchmark(only paths: [String] = []) async {
        guard let hostView = await waitForPlayerWindow() else {
            status = "Přehrávač se nedostal do okna, měření by měřilo prázdno."
            return
        }

        var targets: [ClipTiming] = clips
        if !paths.isEmpty {
            targets = []
            for path in paths {
                let url = URL(fileURLWithPath: path)
                switch await VFRDetector.inspect(url: url) {
                case .success(let timing): targets.append(timing)
                case .failure(let error):
                    status = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
        guard !targets.isEmpty else {
            status = "Není co měřit."
            return
        }

        isMeasuring = true
        reportLines = []
        defer { isMeasuring = false }

        var lines: [String] = ["═══ MĚŘENÍ NÁHLEDU ═══", ""]
        for clip in targets {
            status = "Měřím \(clip.name)…"
            let benchmark = PlaybackBenchmark()
            var result = await benchmark.run(url: clip.url, timing: clip,
                                             controller: controller, hostView: hostView)
            result = result.withCodec(describeCodec(clip))
            lines.append(contentsOf: result.report)
            lines.append("")

            // Mezi běhy pauza, ať se stroj vrátí blíž k výchozí teplotě.
            // Bez toho druhý běh měří teplejší Air, ne pomalejší kodek.
            if clip.url != targets.last?.url {
                status = "Chladnu mezi běhy…"
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        reportLines = lines
        status = "Hotovo."
        writeReport(lines)
        for line in lines { print(line) }
    }

    private func describeCodec(_ clip: ClipTiming) -> String {
        clip.isVariable ? "VFR zdroj" : "CFR zdroj"
    }

    private func writeReport(_ lines: [String]) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first
        guard let url = directory?.appendingPathComponent("KrasaBenchmark.txt") else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("Report zapsán do \(url.path)")
    }
}

extension BenchmarkResult {
    func withCodec(_ codec: String) -> BenchmarkResult {
        BenchmarkResult(url: url, codec: codec,
                        measuredSourceFrameRate: measuredSourceFrameRate,
                        displayRefreshRate: displayRefreshRate,
                        backingScale: backingScale,
                        windowPointSize: windowPointSize,
                        deliveredPerSecond: deliveredPerSecond,
                        measuredSeconds: measuredSeconds,
                        droppedFramesFromAccessLog: droppedFramesFromAccessLog,
                        seekLatencies: seekLatencies,
                        coalescedSeeks: coalescedSeeks,
                        conditionsBefore: conditionsBefore,
                        conditionsAfter: conditionsAfter)
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300)
            playerPane
                .frame(minWidth: 640)
        }
        .frame(minWidth: 1000, minHeight: 640)
        .task {
            await model.restoreAndScan()
            // Bez GUI: `--benchmark [cesty…]` spustí měření samo a skončí.
            // Sandbox drží, přístup se obnovuje z uloženého bookmarku.
            let arguments = CommandLine.arguments.dropFirst()
            if arguments.contains("--benchmark") {
                let explicit = arguments.filter { !$0.hasPrefix("--") }
                await model.runBenchmark(only: Array(explicit))
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Otevřít soubor") { Task { await model.openFiles(directories: false) } }
                Button("Otevřít složku") { Task { await model.openFiles(directories: true) } }
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(model.clips, id: \.url) { clip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.name).font(.system(.body, design: .monospaced))
                    Text("\(clip.verdict.shortLabel) · \(String(format: "%.2f", clip.measuredFrameRate)) fps"
                         + (clip.droppedFrames > 0 ? " · \(clip.droppedFrames) zahozených" : ""))
                        .font(.caption)
                        .foregroundStyle(clip.isVariable ? .orange : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.select(clip) } }
            }

            Button(model.isMeasuring ? "Měřím…" : "Změřit náhled") {
                Task { await model.runBenchmark() }
            }
            .disabled(model.isMeasuring || model.clips.isEmpty)

            if !model.reportLines.isEmpty {
                ScrollView {
                    Text(model.reportLines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160)
            }
        }
        .padding(12)
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            PlayerView(player: model.controller.player) { view in
                model.attach(view)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 16) {
                Button(model.controller.isPlaying ? "Pauza" : "Přehrát") {
                    model.controller.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("◀︎ snímek") { model.controller.step(frames: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("snímek ▶︎") { model.controller.step(frames: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                Spacer()
                Text(timecode(model.controller.currentTime))
                    .font(.system(.body, design: .monospaced))
            }
            .padding(10)
        }
    }

    private func timecode(_ time: CMTime) -> String {
        guard time.isValid, time.seconds.isFinite else { return "—" }
        let total = time.seconds
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, seconds)
    }
}
