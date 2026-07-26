//
//  PlaybackBenchmark.swift
//  Projekt Krása
//
//  Utáhne AVPlayer náhled 4K/60? Otázka, kterou Spike 0 zdědil fázi 1.
//
//  Měří se tři věci:
//
//  1. DORUČENÉ SNÍMKY. Přes `AVPlayerItemVideoOutput` + display link se
//     počítá, kolik ODLIŠNÝCH snímků se skutečně dostalo ven. Ne kolikrát
//     se překreslilo okno — to by měřilo displej, ne dekodér.
//  2. ZAHOZENÉ SNÍMKY z access logu, jako křížová kontrola.
//  3. ODEZVA SCRUBOVÁNÍ. Série seeků se zero tolerance.
//
//  Prahy jsou napsané DOPŘEDU, než se uvidí čísla. Bez toho se výsledek
//  vždycky nějak vyloží.
//

import AVFoundation
import Foundation
import ProbeKit

enum BenchmarkThresholds {
    /// Doručené fps na 60p zdroji.
    static let fpsGood: Double = 55        // ≥ → náhled stačí, proxy kvůli přehrávání netřeba
    static let fpsUsable: Double = 25      // ≥ → použitelné, ale proxy znatelně pomůže
                                           // < → proxy je podmínka použitelnosti, ne optimalizace

    /// Medián odezvy scrubování.
    static let scrubFast: TimeInterval = 0.100      // < → svižné
    static let scrubTolerable: TimeInterval = 0.300 // < → znatelné, ale snesitelné
                                                    // ≥ → rozbité
}

struct BenchmarkResult {
    let url: URL
    let codec: String
    let measuredSourceFrameRate: Double
    let displayRefreshRate: Double
    let backingScale: CGFloat
    let windowPointSize: CGSize

    /// Doručené snímky po jednosekundových oknech.
    let deliveredPerSecond: [Int]
    let droppedFramesFromAccessLog: Int
    let seekLatencies: [TimeInterval]
    let coalescedSeeks: Int

    let conditionsBefore: SystemConditions
    let conditionsAfter: SystemConditions

    var name: String { url.lastPathComponent }

    var meanDeliveredFPS: Double {
        guard !deliveredPerSecond.isEmpty else { return 0 }
        return Double(deliveredPerSecond.reduce(0, +)) / Double(deliveredPerSecond.count)
    }

    var minDeliveredFPS: Double { Double(deliveredPerSecond.min() ?? 0) }

    /// Rovnoměrnost doručování. Vysoký rozptyl znamená škubání i při
    /// slušném průměru — 60 a 20 střídavě dá průměr 40, ale kouká se to blbě.
    var deliveredStdDev: Double {
        guard deliveredPerSecond.count > 1 else { return 0 }
        let mean = meanDeliveredFPS
        let variance = deliveredPerSecond.reduce(0.0) { acc, value in
            let d = Double(value) - mean
            return acc + d * d
        } / Double(deliveredPerSecond.count)
        return variance.squareRoot()
    }

    var medianSeekLatency: TimeInterval {
        guard !seekLatencies.isEmpty else { return 0 }
        let sorted = seekLatencies.sorted()
        return sorted[sorted.count / 2]
    }

    var p95SeekLatency: TimeInterval {
        guard !seekLatencies.isEmpty else { return 0 }
        let sorted = seekLatencies.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }

    // MARK: Verdikty

    var playbackVerdict: String {
        let fps = meanDeliveredFPS
        if fps >= BenchmarkThresholds.fpsGood {
            return "✅ NÁHLED STAČÍ — proxy kvůli přehrávání není potřeba"
        } else if fps >= BenchmarkThresholds.fpsUsable {
            return "🟡 POUŽITELNÉ — ale proxy to znatelně zlepší"
        } else {
            return "🔴 PROXY JE PODMÍNKA použitelnosti timeline, ne optimalizace"
        }
    }

    var scrubVerdict: String {
        let median = medianSeekLatency
        if median < BenchmarkThresholds.scrubFast {
            return "✅ SVIŽNÉ"
        } else if median < BenchmarkThresholds.scrubTolerable {
            return "🟡 ZNATELNÉ, ale snesitelné"
        } else {
            return "🔴 ROZBITÉ"
        }
    }

    /// Doručení nemůže překročit obnovovací frekvenci displeje ani frekvenci
    /// zdroje. Bez tohohle stropu číslo nedává smysl.
    var deliveryCeiling: Double {
        min(displayRefreshRate, measuredSourceFrameRate)
    }

    var report: [String] {
        var lines: [String] = []
        lines.append("▸ \(name)")
        lines.append("  Zdroj      \(codec), naměřeno \(fmt(measuredSourceFrameRate, 3)) fps")
        lines.append("  Displej    \(fmt(displayRefreshRate, 0)) Hz, backing scale \(fmt(Double(backingScale), 1))×"
                   + ", okno \(Int(windowPointSize.width))×\(Int(windowPointSize.height)) bodů")
        lines.append("  Strop      \(fmt(deliveryCeiling, 1)) fps — víc se doručit nedá")
        lines.append("")
        lines.append("  DORUČENO   průměr \(fmt(meanDeliveredFPS, 1)) fps"
                   + " · minimum \(fmt(minDeliveredFPS, 0)) fps"
                   + " · odchylka \(fmt(deliveredStdDev, 1))")
        lines.append("             po sekundách: \(deliveredPerSecond.map(String.init).joined(separator: " "))")
        lines.append("             zahozeno podle access logu: \(droppedFramesFromAccessLog)"
                   + (droppedFramesFromAccessLog == 0 ? "  (u lokálních souborů bývá 0 i při problémech — neber jako důkaz)" : ""))
        lines.append("  → \(playbackVerdict)")
        lines.append("")
        lines.append("  SCRUBOVÁNÍ medián \(fmt(medianSeekLatency * 1000, 1)) ms"
                   + " · p95 \(fmt(p95SeekLatency * 1000, 1)) ms"
                   + " · \(seekLatencies.count) seeků, \(coalescedSeeks) sloučeno")
        lines.append("  → \(scrubVerdict)")
        lines.append("")
        lines.append("  Podmínky   start: \(conditionsBefore.summary)")
        lines.append("             konec: \(conditionsAfter.summary)")
        if let drift = SystemConditions.drift(from: conditionsBefore, to: conditionsAfter) {
            lines.append("  \(drift)")
        }
        return lines
    }

    private func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Běh měření

@MainActor
final class PlaybackBenchmark {

    /// Jak dlouho se přehrává. Kratší běh nestačí na ustálení, delší zahřeje stroj.
    static let playbackSeconds = 15
    /// Kolik seeků na test scrubování.
    static let seekCount = 20

    private var videoOutput: AVPlayerItemVideoOutput?
    private var deliveredInCurrentSecond = 0
    private var deliveredPerSecond: [Int] = []
    private var windowStart: CFTimeInterval = 0

    func run(url: URL,
             timing: ClipTiming?,
             controller: PlaybackController,
             hostView: PlayerHostView) async -> BenchmarkResult {

        let before = SystemConditions.snapshot()

        try? await controller.load(url: url, measuredFrameRate: timing?.measuredFrameRate)
        guard let item = controller.player.currentItem else {
            return emptyResult(url: url, timing: timing, hostView: hostView, conditions: before)
        }

        // Výstup v nativním formátu — nechceme měřit konverzi pixelů.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        item.add(output)
        videoOutput = output

        deliveredPerSecond = []
        deliveredInCurrentSecond = 0
        windowStart = CACurrentMediaTime()

        hostView.onDisplayTick = { [weak self] _ in
            self?.pollFrame(output: output)
        }

        controller.seek(to: .zero)
        controller.play()

        try? await Task.sleep(nanoseconds: UInt64(Self.playbackSeconds) * 1_000_000_000)

        controller.pause()
        hostView.onDisplayTick = nil
        if deliveredInCurrentSecond > 0 { deliveredPerSecond.append(deliveredInCurrentSecond) }

        let dropped = item.accessLog()?.events.reduce(0) { $0 + max(0, $1.numberOfDroppedVideoFrames) } ?? 0

        // Scrubování: rovnoměrně rozházené skoky přes celou délku.
        var latencies: [TimeInterval] = []
        let duration = controller.duration.seconds
        for index in 0..<Self.seekCount {
            let fraction = Double((index * 7) % Self.seekCount) / Double(Self.seekCount)
            let target = CMTime(seconds: duration * fraction, preferredTimescale: 90000)
            latencies.append(await controller.measuredSeek(to: target))
        }

        item.remove(output)
        videoOutput = nil
        let after = SystemConditions.snapshot()

        return BenchmarkResult(
            url: url,
            codec: timing.map { _ in "" } ?? "",
            measuredSourceFrameRate: timing?.measuredFrameRate ?? 0,
            displayRefreshRate: hostView.displayRefreshRate,
            backingScale: hostView.backingScale,
            windowPointSize: hostView.bounds.size,
            deliveredPerSecond: deliveredPerSecond,
            droppedFramesFromAccessLog: dropped,
            seekLatencies: latencies,
            coalescedSeeks: controller.coalescedSeekCount,
            conditionsBefore: before,
            conditionsAfter: after)
    }

    /// Při každém tiku displeje: přišel nový snímek? Kopie je nutná —
    /// bez ní `hasNewPixelBuffer` zůstane true a počítalo by se pořád dokola.
    private func pollFrame(output: AVPlayerItemVideoOutput) {
        let hostTime = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: hostTime)
        guard itemTime.isValid else { return }

        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            _ = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            deliveredInCurrentSecond += 1
        }

        if hostTime - windowStart >= 1.0 {
            deliveredPerSecond.append(deliveredInCurrentSecond)
            deliveredInCurrentSecond = 0
            windowStart = hostTime
        }
    }

    private func emptyResult(url: URL, timing: ClipTiming?,
                             hostView: PlayerHostView,
                             conditions: SystemConditions) -> BenchmarkResult {
        BenchmarkResult(url: url, codec: "—",
                        measuredSourceFrameRate: timing?.measuredFrameRate ?? 0,
                        displayRefreshRate: hostView.displayRefreshRate,
                        backingScale: hostView.backingScale,
                        windowPointSize: hostView.bounds.size,
                        deliveredPerSecond: [], droppedFramesFromAccessLog: 0,
                        seekLatencies: [], coalescedSeeks: 0,
                        conditionsBefore: conditions, conditionsAfter: conditions)
    }
}
