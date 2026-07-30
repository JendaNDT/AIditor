//
//  TimelineScrollBenchmark.swift
//  Projekt AIditor
//
//  Výkonový test fáze 2: scroll přes celou osu s tisíci klipy, žádný
//  vypadlý tik.
//
//  Co se měří a proč zrovna tohle: `CADisplayLink` je vázaný na vsync
//  displeje a jeho obsluha běží na hlavním vlákně. Vypadlý tik tedy znamená
//  ZASEKNUTÉ HLAVNÍ VLÁKNO naší aplikace — recyklace vrstev, layout nebo
//  kreslení pravítka trvaly déle než jeden snímek displeje. Není to metrika
//  kompozice ani GPU (vsync proběhne, i když WindowServer nestíhá) — viz
//  rizika v PROJECT_STATUS.md.
//
//  Scroll se řídí ČASEM, ne krokem na tik: kdyby se krokovalo po ticích,
//  vypadlý tik by zpomalil jízdu a schoval sám sebe. Takhle po zádrhelu
//  osa skočí tam, kde měla být, a zádrhel zůstane v číslech.
//
//  <https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)>
//

import AppKit
import Foundation

struct TimelineScrollResult {
    let clipCount: Int
    let documentWidth: Double
    let traversedPoints: Double
    let measuredSeconds: Double
    let ticks: Int
    /// Z mediánu intervalů display linku — skutečná obnovovací frekvence.
    let nominalIntervalMs: Double
    /// Kolik tiků vsyncu hlavní vlákno prošvihlo (součet přes všechny mezery).
    let droppedTicks: Int
    let longestGapMs: Double
    /// Práce scrollovacího kroku (scroll + synchronní recyklace vrstev).
    let medianWorkMs: Double
    let maxWorkMs: Double
    let windowWasVisible: Bool

    var report: [String] {
        let rate = nominalIntervalMs > 0 ? 1000 / nominalIntervalMs : 0
        var lines = [
            "═══ VÝKONOVÝ TEST OSY: SCROLL PŘES CELOU OSU ═══",
            "",
            String(format: "klipů na ose: %d, dokument %.0f bodů, ujeto %.0f bodů (tam a zpět)",
                   clipCount, documentWidth, traversedPoints),
            String(format: "trvání %.1f s, %d tiků, displej %.1f Hz (medián intervalu %.2f ms)",
                   measuredSeconds, ticks, rate, nominalIntervalMs),
            String(format: "vypadlé tiky: %d, nejdelší mezera %.1f ms",
                   droppedTicks, longestGapMs),
            String(format: "práce na tik: medián %.2f ms, maximum %.2f ms",
                   medianWorkMs, maxWorkMs),
        ]
        if !windowWasVisible {
            lines.append("⚠️ Okno nebylo po celou dobu viditelné — běh je NEPLATNÝ.")
        } else if droppedTicks == 0 {
            lines.append("✅ Žádný vypadlý tik — kritérium fáze 2 splněno.")
        } else {
            lines.append("❌ Hlavní vlákno prošvihlo \(droppedTicks) tiků.")
        }
        return lines
    }
}

/// Jede scroll přes celou šířku dokumentu tam a zpět a počítá tiky.
@MainActor
final class TimelineScrollBenchmark: NSObject {

    private let pane: TimelinePane
    private let secondsPerPass: CFTimeInterval
    private let clipCount: Int

    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private var startTime: CFTimeInterval = 0
    private var endTime: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval?
    private var intervals: [Double] = []
    private var workDurations: [Double] = []
    private var ticks = 0
    private var maxX: CGFloat = 0
    private var windowWasVisible = true

    init(pane: TimelinePane, clipCount: Int, secondsPerPass: CFTimeInterval = 10) {
        self.pane = pane
        self.clipCount = clipCount
        self.secondsPerPass = secondsPerPass
    }

    func run() async -> TimelineScrollResult {
        let clipView = pane.scrollView.contentView
        maxX = max(0, pane.documentView.frame.width - clipView.bounds.width)

        let created = pane.scrollView.displayLink(target: self,
                                                 selector: #selector(tick(_:)))
        created.add(to: .main, forMode: .common)
        link = created
        // startTime se nastaví až v PRVNÍM tiku: display link se při
        // zakrytém okně pozastaví, a kdyby hodiny běžely od téhle chvíle,
        // odloženy start by ukrojil z měřené dráhy.

        await withCheckedContinuation { continuation = $0 }

        let sortedIntervals = intervals.sorted()
        let nominal = sortedIntervals.isEmpty ? 0 : sortedIntervals[sortedIntervals.count / 2]
        // Vypadlé tiky: mezera dvou intervalů = jeden prošvihnutý vsync.
        let dropped = nominal > 0
            ? intervals.reduce(0) { $0 + max(0, Int((($1 / nominal).rounded())) - 1) }
            : 0
        let sortedWork = workDurations.sorted()

        return TimelineScrollResult(
            clipCount: clipCount,
            documentWidth: Double(pane.documentView.frame.width),
            traversedPoints: Double(maxX) * 2,
            measuredSeconds: endTime - startTime,
            ticks: ticks,
            nominalIntervalMs: nominal * 1000,
            droppedTicks: dropped,
            longestGapMs: (intervals.max() ?? 0) * 1000,
            medianWorkMs: sortedWork.isEmpty ? 0 : sortedWork[sortedWork.count / 2],
            maxWorkMs: sortedWork.max() ?? 0,
            windowWasVisible: windowWasVisible)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if startTime == 0 { startTime = now }
        ticks += 1
        if let last = lastTimestamp {
            intervals.append(now - last)
        }
        lastTimestamp = now

        if pane.window?.occlusionState.contains(.visible) != true {
            windowWasVisible = false
        }

        let elapsed = now - startTime
        guard elapsed < secondsPerPass * 2 else {
            endTime = now
            link.invalidate()
            self.link = nil
            continuation?.resume()
            continuation = nil
            return
        }

        // Trojúhelník 0 → maxX → 0, poloha z ČASU (viz hlavička souboru).
        let phase = elapsed / secondsPerPass
        let progress = phase <= 1 ? phase : 2 - phase

        let workStart = CACurrentMediaTime()
        let clipView = pane.scrollView.contentView
        clipView.scroll(to: NSPoint(x: maxX * CGFloat(progress),
                                    y: clipView.bounds.origin.y))
        pane.scrollView.reflectScrolledClipView(clipView)
        workDurations.append((CACurrentMediaTime() - workStart) * 1000)
    }
}
