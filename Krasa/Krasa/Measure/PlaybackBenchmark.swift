//
//  PlaybackBenchmark.swift
//  Projekt Krása
//
//  Utáhne AVPlayer náhled 4K? Otázka, kterou Spike 0 zdědil fázi 1.
//
//  ⚠️ CO TENHLE NÁSTROJ UMÍ A CO NE
//
//  Umí: změřit, kolik odlišných snímků se dostalo z dekodéru ven, jak dlouho
//  trvá seek se zero tolerance, a jestli se nezasekává hlavní vlákno.
//
//  NEUMÍ: změřit, kolik stojí skládání a škálování obrazu. Doručené snímky
//  chodí z `AVPlayerItemVideoOutput` v rozlišení ZDROJE bez ohledu na to, jak
//  je okno velké, a víc než jeden na tik displeje se jich nezapočítá — takže
//  na 60Hz panelu je výsledek nasycený na 60 a velikostí plochy s ním
//  nepohneš. Kadence display linku je slepá taky: vsync proběhne, i když
//  GPU nestíhá. Cenu kompozice ukáže jen `powermetrics` puštěný vedle,
//  případně vlastní Metal cesta — viz `powermetricsHint`.
//
//  Prahy jsou napsané DOPŘEDU, než se uvidí čísla. Bez toho se výsledek
//  vždycky nějak vyloží.
//

import AVFoundation
import AppKit
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

    /// Podíl skutečných tiků hlavního vlákna k obnovovací frekvenci displeje.
    /// ⚠️ Metrika odezvy NAŠÍ aplikace, ne propustnosti kompozice.
    static let tickRateGood: Double = 0.99     // ≥ → runloop stíhá každý vsync
    static let tickRateUsable: Double = 0.95   // ≥ → ojedinělé zádrhely
                                               // < → hlavní vlákno se zasekává
    /// Nad tímhle je v účtování chyba — víc tiků než obnovení displeje být nemůže.
    static let tickRateImpossible: Double = 1.02
}

/// Jedno měřicí okno. Nese svou SKUTEČNOU délku, ne domnělou sekundu:
/// okno se uzavírá na prvním tiku za hranicí, takže je vždycky o kousek
/// delší. Dřívější verze ten přeběh zahazovala a vydávala počet za „fps" —
/// odtud pochází 60,3 fps naměřených na displeji, který zvládne 60,0.
struct MeasurementWindow {
    let delivered: Int
    let ticks: Int
    let duration: CFTimeInterval
}

struct BenchmarkResult {
    let url: URL
    var codec: String
    let measuredSourceFrameRate: Double

    // MARK: Displej
    let screenName: String
    /// `NSScreen.maximumFramesPerSecond` — maximum, ne aktuální hodnota.
    let screenRefreshRate: Double
    /// Dopočteno z mediánu `CADisplayLink.duration`. Tohle je skutečnost.
    let measuredRefreshRate: Double
    let backingScale: CGFloat
    let screenBackingPixelSize: CGSize

    // MARK: Plocha
    let isFullScreen: Bool
    /// Plocha PŘEHRÁVAČE, ne okna — okno je větší o sidebar a transport.
    let playerPointSize: CGSize
    let layerBackingPixelSize: CGSize
    let videoBackingPixelSize: CGSize
    /// Rozlišení pixel bufferu, který doopravdy přišel z dekodéru.
    /// Důkaz, že se velikostí okna nemění — ne domněnka.
    let deliveredPixelSize: CGSize

    // MARK: Viditelnost
    /// Podíl tiků, ve kterých bylo okno aspoň zčásti vidět.
    let visibleTickRatio: Double
    /// Podíl tiků, ve kterých byla aplikace aktivní.
    let appActiveTickRatio: Double
    /// Kolik z obrazu leželo uvnitř obsahu okna (měřeno na konci běhu).
    let videoVisibleFraction: Double

    // MARK: Měření
    let windows: [MeasurementWindow]
    let longTickGaps: Int
    /// Skutečně uplynulý čas měření, ne zamýšlená délka spánku.
    let measuredSeconds: Double
    let startedAt: Date
    let endedAt: Date
    let droppedFramesFromAccessLog: Int
    let seekLatencies: [TimeInterval]
    let coalescedSeeks: Int

    let conditionsBefore: SystemConditions
    let conditionsAfter: SystemConditions

    var name: String { url.lastPathComponent }
    var placeLabel: String { isFullScreen ? "celá obrazovka" : "okno" }

    // MARK: Odvozené — snímky

    /// Ustálený stav: bez prvního okna (rozjezd) a bez posledního
    /// (nekompletní). Podle tohohle se rozhoduje verdikt.
    var steadyWindows: [MeasurementWindow] {
        guard windows.count > 2 else { return windows }
        return Array(windows.dropFirst().dropLast())
    }

    private func rate(_ count: (MeasurementWindow) -> Int, over windows: [MeasurementWindow]) -> Double {
        let time = windows.reduce(0.0) { $0 + $1.duration }
        guard time > 0 else { return 0 }
        return Double(windows.reduce(0) { $0 + count($1) }) / time
    }

    /// Snímky za sekundu = počet děleno SKUTEČNÝM časem. Ne počet na kbelík.
    var steadyStateFPS: Double { rate({ $0.delivered }, over: steadyWindows) }
    var meanDeliveredFPS: Double { rate({ $0.delivered }, over: windows) }
    var steadyStateTickRate: Double { rate({ $0.ticks }, over: steadyWindows) }

    var deliveredPerSecond: [Int] { windows.map(\.delivered) }
    var ticksPerSecond: [Int] { windows.map(\.ticks) }
    var minDeliveredFPS: Double { Double(deliveredPerSecond.min() ?? 0) }

    /// Podíl skutečné kadence hlavního vlákna k obnovovací frekvenci.
    var tickRateRatio: Double {
        guard measuredRefreshRate > 0 else { return 0 }
        return steadyStateTickRate / measuredRefreshRate
    }

    /// Rovnoměrnost doručování. Vysoký rozptyl znamená škubání i při
    /// slušném průměru — 60 a 20 střídavě dá průměr 40, ale kouká se to blbě.
    var deliveredStdDev: Double {
        let counts = deliveredPerSecond
        guard counts.count > 1 else { return 0 }
        let mean = Double(counts.reduce(0, +)) / Double(counts.count)
        let variance = counts.reduce(0.0) { acc, value in
            let d = Double(value) - mean
            return acc + d * d
        } / Double(counts.count)
        return variance.squareRoot()
    }

    // MARK: Odvozené — scrubování

    private func percentile(_ p: Double) -> TimeInterval {
        let sorted = seekLatencies.sorted()
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }

    /// U sudého počtu vzorků průměr dvou prostředních, ne horní z nich.
    var medianSeekLatency: TimeInterval { percentile(0.5) }
    /// Interpolovaný 95. percentil. Dřívější verze tady vracela maximum:
    /// při 20 vzorcích je `Int(20 × 0,95)` rovno 19, tedy poslednímu prvku.
    var p95SeekLatency: TimeInterval { percentile(0.95) }
    var maxSeekLatency: TimeInterval { seekLatencies.max() ?? 0 }

    // MARK: Odvozené — plocha

    var videoBackingPixelCount: Double {
        Double(videoBackingPixelSize.width * videoBackingPixelSize.height)
    }

    var screenPixelCount: Double {
        Double(screenBackingPixelSize.width * screenBackingPixelSize.height)
    }

    /// Kolik z displeje zabírá samotný obraz. Bez tohohle čísla se nedá
    /// poznat, jestli „fullscreen" znamenal celou obrazovku, nebo dvě
    /// třetiny obrazovky vedle sidebaru.
    var displayCoverage: Double {
        guard screenPixelCount > 0 else { return 0 }
        return videoBackingPixelCount / screenPixelCount
    }

    /// Doručení nemůže překročit obnovovací frekvenci displeje ani frekvenci
    /// zdroje. Zároveň je to strop METODY: počítá se nejvýš jeden snímek
    /// na tik, takže nad refresh rate se metrika nasytí a nemá kam růst.
    var deliveryCeiling: Double {
        Swift.min(measuredRefreshRate > 0 ? measuredRefreshRate : screenRefreshRate,
                  measuredSourceFrameRate)
    }

    // MARK: Verdikty

    var playbackVerdict: String {
        let fps = steadyStateFPS
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

    /// Bylo na co koukat? Bez tohohle je celý běh k ničemu a nesmí se
    /// vydávat za výsledek. Zavedeno poté, co fullscreen běh 27. 07. 2026
    /// vrátil spokojených 60,0 fps při nulové zátěži GPU.
    var visibilityProblem: String? {
        if visibleTickRatio < 0.99 {
            return "okno bylo vidět jen \(pct(visibleTickRatio)) doby běhu"
                 + " — WindowServer ho zbytek času neskládal"
        }
        if videoVisibleFraction < 0.99 {
            return "z obrazu leželo uvnitř okna jen \(pct(videoVisibleFraction))"
        }
        if appActiveTickRatio < 0.99 {
            return "aplikace byla aktivní jen \(pct(appActiveTickRatio)) doby běhu"
        }
        return nil
    }

    var visibilityVerdict: String {
        if let problem = visibilityProblem {
            return "🔴 MĚŘENÍ NEPLATNÉ — \(problem)"
        }
        return "✅ OKNO BYLO CELOU DOBU VIDĚT"
    }

    var mainThreadVerdict: String {
        let ratio = tickRateRatio
        if steadyStateTickRate == 0 {
            return "⚠️ ŽÁDNÉ TIKY — display link neběžel, celé měření je neplatné"
        } else if ratio > BenchmarkThresholds.tickRateImpossible {
            return "⚠️ VÍC TIKŮ NEŽ OBNOVENÍ DISPLEJE — chyba v účtování času, čísla neber"
        } else if ratio >= BenchmarkThresholds.tickRateGood {
            return "✅ HLAVNÍ VLÁKNO STÍHÁ každý vsync"
        } else if ratio >= BenchmarkThresholds.tickRateUsable {
            return "🟡 OJEDINĚLÉ ZÁDRHELY hlavního vlákna"
        } else {
            return "🔴 HLAVNÍ VLÁKNO SE ZASEKÁVÁ"
        }
    }

    /// Návod, jak k tomuhle běhu dohledat cenu kompozice.
    var powermetricsHint: String {
        "sudo powermetrics --samplers gpu_power,cpu_power -i 1000"
            + " · úsek \(clock(startedAt))–\(clock(endedAt))"
    }

    var report: [String] {
        var lines: [String] = []
        lines.append("▸ \(name)  [\(placeLabel)]  \(clock(startedAt))–\(clock(endedAt))")
        lines.append("  Zdroj      \(codec), naměřeno \(fmt(measuredSourceFrameRate, 3)) fps")
        lines.append("  Displej    \(screenName) · \(fmt(measuredRefreshRate, 1)) Hz naměřeno"
                   + " (hlášené maximum \(fmt(screenRefreshRate, 0)))"
                   + " · backing scale \(fmt(Double(backingScale), 1))×"
                   + " · \(px(screenBackingPixelSize)) px")
        lines.append("  Přehrávač  \(Int(playerPointSize.width))×\(Int(playerPointSize.height)) bodů"
                   + " · vrstva \(px(layerBackingPixelSize)) px")
        lines.append("  OBRAZ      \(px(videoBackingPixelSize)) px"
                   + " = \(fmt(displayCoverage * 100, 1)) % plochy displeje"
                   + " · uvnitř okna \(pct(videoVisibleFraction))")
        lines.append("  VIDITELNOST okno vidět \(pct(visibleTickRatio)) tiků"
                   + " · appka aktivní \(pct(appActiveTickRatio)) tiků")
        lines.append("  → \(visibilityVerdict)")
        lines.append("  Z dekodéru \(px(deliveredPixelSize)) px"
                   + "  — na velikosti okna nezávisí, roste jen škálování")
        lines.append("  Strop      \(fmt(deliveryCeiling, 1)) fps — strop METODY, ne stroje"
                   + " (nejvýš jeden snímek na tik)")
        lines.append("")
        lines.append("  DORUČENO   ustálený stav \(fmt(steadyStateFPS, 1)) fps"
                   + "  (průměr včetně rozjezdu \(fmt(meanDeliveredFPS, 1)))")
        lines.append("             minimum \(fmt(minDeliveredFPS, 0)) za okno"
                   + " · odchylka \(fmt(deliveredStdDev, 1))"
                   + " · měřeno \(fmt(measuredSeconds, 2)) s")
        lines.append("             po oknech: \(deliveredPerSecond.map(String.init).joined(separator: " "))")
        lines.append("             zahozeno podle access logu: \(droppedFramesFromAccessLog)"
                   + (droppedFramesFromAccessLog == 0 ? "  (u lokálních souborů bývá 0 i při problémech — neber jako důkaz)" : ""))
        lines.append("  → \(playbackVerdict)")
        lines.append("")
        lines.append("  HLAVNÍ VLÁKNO \(fmt(steadyStateTickRate, 1)) tiků/s"
                   + " z \(fmt(measuredRefreshRate, 1)) Hz = \(fmt(tickRateRatio * 100, 1)) %")
        lines.append("             po oknech: \(ticksPerSecond.map(String.init).joined(separator: " "))")
        lines.append("             dlouhé mezery mezi tiky: \(longTickGaps)")
        lines.append("  → \(mainThreadVerdict)")
        lines.append("     (NEMĚŘÍ kompozici — vsync proběhne, i když GPU nestíhá)")
        lines.append("")
        lines.append("  SCRUBOVÁNÍ medián \(fmt(medianSeekLatency * 1000, 1)) ms"
                   + " · p95 \(fmt(p95SeekLatency * 1000, 1)) ms"
                   + " · max \(fmt(maxSeekLatency * 1000, 1)) ms"
                   + " · \(seekLatencies.count) seeků, \(coalescedSeeks) sloučeno")
        lines.append("  → \(scrubVerdict)")
        lines.append("")
        lines.append("  Podmínky   start: \(conditionsBefore.summary)")
        lines.append("             konec: \(conditionsAfter.summary)")
        if let drift = SystemConditions.drift(from: conditionsBefore, to: conditionsAfter) {
            lines.append("  \(drift)")
        }
        lines.append("  Cena kompozice: \(powermetricsHint)")
        return lines
    }

    private func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func px(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    private func pct(_ value: Double) -> String {
        fmt(value * 100, 1) + " %"
    }

    /// Pevný 24hodinový tvar. Locale se musí připnout: `amPM: .omitted` jen
    /// schová „PM", hodinový cyklus nechá podle systému — na anglicky
    /// nastaveném Macu by z 14:23 vyšlo 02:23 a spárovat to s výpisem
    /// `powermetrics` by nešlo vůbec.
    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()
            .locale(Locale(identifier: "en_GB")))
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
    private var windows: [MeasurementWindow] = []
    private var deliveredInCurrentWindow = 0
    private var ticksInCurrentWindow = 0
    private var tickDurations: [CFTimeInterval] = []
    private var longTickGaps = 0
    private var visibleTicks = 0
    private var appActiveTicks = 0
    private var totalTicks = 0
    private var lastTickTimestamp: CFTimeInterval = 0
    private var deliveredPixelSize: CGSize = .zero
    private var windowStart: CFTimeInterval = 0
    private var measurementStart: CFTimeInterval = 0
    /// Hodiny se pouští až na PRVNÍM doručeném snímku. Dokud `AVPlayerItem`
    /// nemá timebase, `itemTime(forHostTime:)` vrací neplatný čas — a kdyby
    /// se okna vyklápěla už tehdy, rozjezd by kontaminoval dvě okna místo
    /// jednoho a `steadyState` by zahodil jen to první.
    private var running = false

    func run(url: URL,
             timing: ClipTiming?,
             controller: PlaybackController,
             hostView: PlayerHostView) async -> BenchmarkResult {

        let before = SystemConditions.snapshot()
        let startedAt = Date()

        try? await controller.load(url: url, measuredFrameRate: timing?.measuredFrameRate)
        guard let item = controller.player.currentItem else {
            return emptyResult(url: url, timing: timing, hostView: hostView,
                               conditions: before, startedAt: startedAt)
        }

        // Výstup v nativním formátu — nechceme měřit konverzi pixelů.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        item.add(output)
        videoOutput = output

        windows = []
        deliveredInCurrentWindow = 0
        ticksInCurrentWindow = 0
        tickDurations = []
        longTickGaps = 0
        visibleTicks = 0
        appActiveTicks = 0
        totalTicks = 0
        lastTickTimestamp = 0
        deliveredPixelSize = .zero
        running = false

        hostView.onDisplayTick = { [weak self, weak hostView] tick in
            self?.pollFrame(output: output, tick: tick, hostView: hostView)
        }

        controller.seek(to: .zero)
        controller.play()

        // Nikdy neměřit déle, než klip trvá — jinak se do průměru započítají
        // nuly za koncem videa a vyjde z toho zdánlivé zadrhávání.
        let clipSeconds = controller.duration.seconds
        let requestedSeconds = clipSeconds.isFinite && clipSeconds > 0
            ? max(3.0, min(Double(Self.playbackSeconds), clipSeconds - 0.5))
            : Double(Self.playbackSeconds)
        try? await Task.sleep(nanoseconds: UInt64(requestedSeconds * 1_000_000_000))

        controller.pause()
        hostView.onDisplayTick = nil

        // Skutečná délka měření, ne zamýšlená. `Task.sleep` přetahuje a hodiny
        // se navíc pouštěly až prvním doručeným snímkem.
        let elapsed = running ? CACurrentMediaTime() - measurementStart : 0
        let endedAt = Date()

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
            codec: "",
            measuredSourceFrameRate: timing?.measuredFrameRate ?? 0,
            screenName: hostView.screenName,
            screenRefreshRate: hostView.displayRefreshRate,
            measuredRefreshRate: measuredRefreshRate(fallback: hostView.displayRefreshRate),
            backingScale: hostView.backingScale,
            screenBackingPixelSize: hostView.screenBackingPixelSize,
            isFullScreen: Self.isOnFullScreen(hostView),
            playerPointSize: hostView.bounds.size,
            layerBackingPixelSize: hostView.layerBackingPixelSize,
            videoBackingPixelSize: hostView.videoBackingPixelSize,
            deliveredPixelSize: deliveredPixelSize,
            visibleTickRatio: ratio(visibleTicks),
            appActiveTickRatio: ratio(appActiveTicks),
            videoVisibleFraction: hostView.videoVisibleFraction,
            windows: windows,
            longTickGaps: longTickGaps,
            measuredSeconds: elapsed,
            startedAt: startedAt,
            endedAt: endedAt,
            droppedFramesFromAccessLog: dropped,
            seekLatencies: latencies,
            coalescedSeeks: controller.coalescedSeekCount,
            conditionsBefore: before,
            conditionsAfter: after)
    }

    /// Podíl z celkového počtu tiků. Bez tiků je to 0, ne 1 — „neměřilo se"
    /// se nesmí tvářit jako „bylo to v pořádku".
    private func ratio(_ count: Int) -> Double {
        totalTicks > 0 ? Double(count) / Double(totalTicks) : 0
    }

    /// Skutečná obnovovací frekvence z mediánu délek tiků.
    /// `NSScreen.maximumFramesPerSecond` je maximum — na adaptivním displeji
    /// by z něj vyšel falešný propadák.
    private func measuredRefreshRate(fallback: Double) -> Double {
        let valid = tickDurations.filter { $0 > 0 }.sorted()
        guard !valid.isEmpty else { return fallback }
        let median = valid[valid.count / 2]
        return median > 0 ? 1.0 / median : fallback
    }

    /// Při každém tiku displeje: přišel nový snímek? Kopie je nutná —
    /// bez ní `hasNewPixelBuffer` zůstane true a počítalo by se pořád dokola.
    private func pollFrame(output: AVPlayerItemVideoOutput, tick: DisplayTick,
                           hostView: PlayerHostView?) {
        let hostTime = CACurrentMediaTime()

        let itemTime = output.itemTime(forHostTime: hostTime)
        var gotFrame = false
        if itemTime.isValid, output.hasNewPixelBuffer(forItemTime: itemTime) {
            let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            if deliveredPixelSize == .zero, let buffer {
                deliveredPixelSize = CGSize(width: CVPixelBufferGetWidth(buffer),
                                            height: CVPixelBufferGetHeight(buffer))
            }
            gotFrame = true
        }

        // Hodiny se pouští prvním doručeným snímkem, ne dřív.
        if !running {
            guard gotFrame else { return }
            running = true
            measurementStart = hostTime
            windowStart = hostTime
            lastTickTimestamp = tick.timestamp
        }

        // Viditelnost se vzorkuje na každém tiku, ne jednou na konci — okno
        // může zmizet uprostřed běhu a průměr to musí zachytit.
        totalTicks += 1
        if hostView?.isWindowVisible == true { visibleTicks += 1 }
        if NSApp.isActive { appActiveTicks += 1 }

        if tick.duration > 0 { tickDurations.append(tick.duration) }
        ticksInCurrentWindow += 1
        if lastTickTimestamp > 0, tick.duration > 0,
           tick.timestamp - lastTickTimestamp > tick.duration * 1.5 {
            longTickGaps += 1
        }
        lastTickTimestamp = tick.timestamp
        if gotFrame { deliveredInCurrentWindow += 1 }

        // Okno se uzavírá na prvním tiku ZA hranicí, takže je o kousek delší
        // než sekunda. Ta délka se zaznamená a fps se počítá z ní — přeběh
        // se nezahazuje. Kdyby se zahazoval, vyjde na 60Hz displeji 60,5 fps.
        let elapsed = hostTime - windowStart
        if elapsed >= 1.0 {
            windows.append(MeasurementWindow(delivered: deliveredInCurrentWindow,
                                             ticks: ticksInCurrentWindow,
                                             duration: elapsed))
            deliveredInCurrentWindow = 0
            ticksInCurrentWindow = 0
            windowStart = hostTime
        }
    }

    /// Je hostitelské okno na celé obrazovce? Bez okna se měří v okně z definice.
    private static func isOnFullScreen(_ hostView: PlayerHostView) -> Bool {
        guard let window = hostView.window else { return false }
        return FullScreenSwitch.isFullScreen(window)
    }

    private func emptyResult(url: URL, timing: ClipTiming?,
                             hostView: PlayerHostView,
                             conditions: SystemConditions,
                             startedAt: Date) -> BenchmarkResult {
        BenchmarkResult(url: url, codec: "—",
                        measuredSourceFrameRate: timing?.measuredFrameRate ?? 0,
                        screenName: hostView.screenName,
                        screenRefreshRate: hostView.displayRefreshRate,
                        measuredRefreshRate: hostView.displayRefreshRate,
                        backingScale: hostView.backingScale,
                        screenBackingPixelSize: hostView.screenBackingPixelSize,
                        isFullScreen: Self.isOnFullScreen(hostView),
                        playerPointSize: hostView.bounds.size,
                        layerBackingPixelSize: hostView.layerBackingPixelSize,
                        videoBackingPixelSize: hostView.videoBackingPixelSize,
                        deliveredPixelSize: .zero,
                        visibleTickRatio: 0, appActiveTickRatio: 0,
                        videoVisibleFraction: 0,
                        windows: [], longTickGaps: 0, measuredSeconds: 0,
                        startedAt: startedAt, endedAt: Date(),
                        droppedFramesFromAccessLog: 0,
                        seekLatencies: [], coalescedSeeks: 0,
                        conditionsBefore: conditions, conditionsAfter: conditions)
    }
}

// MARK: - Srovnání okno vs celá obrazovka

enum ComparisonThresholds {
    /// Relativní pokles doručených snímků na fullscreenu.
    static let fpsNegligible = 0.02
    /// 3 % je na 60fps sestavě necelé dva snímky za sekundu. Deset procent,
    /// jak to bylo napsané dřív, je každý desátý snímek zopakovaný — tedy
    /// přesně to trhání při panorámování, kvůli kterému se zavrhla základna
    /// 24 fps. „Náhled drží" se o tom říct nedá.
    static let fpsAcceptable = 0.03

    /// Zhoršení scrubování. Relativní práh sám o sobě nestačí: u ProResu se
    /// 6,2 → 9,4 ms vejde do +50 %, a nikdo to nepozná. Proto se relativní
    /// test pouští, až když je absolutní rozdíl nad podlahou.
    static let scrubFloor: TimeInterval = 0.010
    static let scrubNegligible = 0.15
    static let scrubAcceptable = 0.50

    /// Pod tímhle poměrem ploch se neporovnává fullscreen s oknem,
    /// ale dvě skoro stejná okna. Takové měření nemá vypovídací hodnotu.
    static let minimumPixelRatio = 1.3
}

/// Jedno kolo: tentýž klip v okně a na celé obrazovce.
struct ComparisonRound {
    let windowed: BenchmarkResult
    let fullScreen: BenchmarkResult
    /// Které se měřilo první. Kvůli teplotě to není detail.
    let windowedFirst: Bool
}

/// Srovnání pro jeden klip.
///
/// Kola jsou dvě a v zrcadlovém pořadí (okno→fullscreen, pak fullscreen→okno).
/// Air je bezventilátorový a při jediném pořadí by druhý stav vždycky měřil
/// teplejší stroj. ABBA ruší lineární tepelný drift přesně; zakřivení křivky
/// nezruší, proto se před prvním kolem pouští zahřívací běh, který se zahazuje.
///
/// ⚠️ Tohle srovnání odpovídá jen na otázku „změnilo se doručování snímků".
/// Na otázku „kolik stojí skládání většího obrazu" neodpovídá a odpovědět
/// nemůže — na to je `powermetrics`, jehož úsek si každý běh tiskne sám.
struct FullScreenComparison {
    let clipName: String
    let rounds: [ComparisonRound]

    private var windowedResults: [BenchmarkResult] { rounds.map(\.windowed) }
    private var fullScreenResults: [BenchmarkResult] { rounds.map(\.fullScreen) }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var windowedFPS: Double { Self.average(windowedResults.map(\.steadyStateFPS)) }
    var fullScreenFPS: Double { Self.average(fullScreenResults.map(\.steadyStateFPS)) }
    var windowedScrub: Double { Self.average(windowedResults.map(\.medianSeekLatency)) }
    var fullScreenScrub: Double { Self.average(fullScreenResults.map(\.medianSeekLatency)) }
    var windowedPixels: Double { Self.average(windowedResults.map(\.videoBackingPixelCount)) }
    var fullScreenPixels: Double { Self.average(fullScreenResults.map(\.videoBackingPixelCount)) }
    var windowedCoverage: Double { Self.average(windowedResults.map(\.displayCoverage)) }
    var fullScreenCoverage: Double { Self.average(fullScreenResults.map(\.displayCoverage)) }

    /// Kolikrát větší plochu obrazu skládá GPU na fullscreenu.
    var pixelRatio: Double {
        guard windowedPixels > 0 else { return 0 }
        return fullScreenPixels / windowedPixels
    }

    /// Relativní pokles fps. `nil` = data chybí. Nikdy nemapovat na nulu:
    /// „nevím" a „žádný rozdíl" nejsou totéž a záměna vyrobí zelený verdikt
    /// z prázdného měření.
    var fpsDrop: Double? {
        guard windowedFPS > 0, fullScreenFPS > 0 else { return nil }
        return (windowedFPS - fullScreenFPS) / windowedFPS
    }

    var scrubIncrease: Double? {
        guard windowedScrub > 0, fullScreenScrub > 0 else { return nil }
        return (fullScreenScrub - windowedScrub) / windowedScrub
    }

    /// Rozptyl mezi koly. Když je velký, průměr nic neznamená.
    var roundSpread: Double? {
        let values = fullScreenResults.map(\.steadyStateFPS) + windowedResults.map(\.steadyStateFPS)
        guard let low = values.min(), let high = values.max(), high > 0, values.count > 2 else { return nil }
        return (high - low) / high
    }

    /// Důvod, proč se z tohohle běhu nedá nic vyvodit. `nil` = dá.
    var blockingProblem: String? {
        if rounds.count < 2 {
            return "proběhlo jen \(rounds.count) kolo ze 2 — ABBA se nestihlo uzavřít"
        }
        if fpsDrop == nil {
            return "některý běh neodevzdal ani jeden snímek"
        }
        if (windowedResults + fullScreenResults).contains(where: { $0.steadyStateTickRate == 0 }) {
            return "v některém běhu neběžel display link — nejspíš se ztratil odkaz na přehrávač"
        }
        // Nejdůležitější pojistka. Snímky z dekodéru chodí, i když se nic
        // nekreslí — takže bez tohohle testu vypadá neviditelné okno jako
        // dokonalý výsledek.
        for result in windowedResults + fullScreenResults {
            if let problem = result.visibilityProblem {
                return "\(result.placeLabel): \(problem)."
                     + " Nech appku celou dobu v popředí a nepřepínej Spaces."
            }
        }
        if pixelRatio < ComparisonThresholds.minimumPixelRatio {
            return "plocha obrazu narostla jen \(fmt(pixelRatio, 2))× — to není fullscreen proti oknu,"
                 + " ale dvě podobně velká okna. Zmenši okno před spuštěním."
        }
        return nil
    }

    var verdict: String {
        if let problem = blockingProblem {
            return "⚠️ NEPRŮKAZNÉ — \(problem)"
        }
        guard let drop = fpsDrop else { return "⚠️ NEPRŮKAZNÉ — chybí data" }
        if drop < ComparisonThresholds.fpsNegligible {
            return "✅ DORUČOVÁNÍ SNÍMKŮ SE NEZMĚNILO"
                 + " — pozor, tahle metrika je na plochu málo citlivá, cenu skládání ukáže powermetrics"
        } else if drop < ComparisonThresholds.fpsAcceptable {
            return "🟡 MĚŘITELNÝ POKLES na hraně viditelnosti"
        } else {
            return "🔴 FULLSCREEN BOLÍ — a to i na metrice, která je na plochu málo citlivá"
        }
    }

    var scrubVerdict: String {
        guard blockingProblem == nil, let increase = scrubIncrease else {
            return "⚠️ scrubování nevyhodnoceno"
        }
        // Absolutní podlaha první: pár milisekund nikdo nepozná, ať je to
        // v procentech kolik chce.
        if abs(fullScreenScrub - windowedScrub) < ComparisonThresholds.scrubFloor {
            return "✅ scrubování se nezhoršilo (rozdíl pod \(fmt(ComparisonThresholds.scrubFloor * 1000, 0)) ms)"
        }
        if increase < ComparisonThresholds.scrubNegligible {
            return "✅ scrubování se nezhoršilo"
        } else if increase < ComparisonThresholds.scrubAcceptable {
            return "🟡 scrubování je znatelně pomalejší"
        } else {
            return "🔴 scrubování se na fullscreenu rozpadá"
        }
    }

    var report: [String] {
        var lines: [String] = []
        lines.append("╔═ SROVNÁNÍ OKNO vs CELÁ OBRAZOVKA ═ \(clipName)")
        lines.append("║")
        lines.append("║  plocha obrazu   okno \(mpx(windowedPixels))"
                   + " (\(fmt(windowedCoverage * 100, 0)) % displeje)"
                   + " → fullscreen \(mpx(fullScreenPixels))"
                   + " (\(fmt(fullScreenCoverage * 100, 0)) % displeje)")
        lines.append("║                  poměr \(fmt(pixelRatio, 2))×")
        lines.append("║")
        lines.append("║  DORUČENO        okno \(fmt(windowedFPS, 1)) fps"
                   + " → fullscreen \(fmt(fullScreenFPS, 1)) fps"
                   + "  (\(percent(fpsDrop.map { -$0 })))")
        lines.append("║  SCRUBOVÁNÍ      okno \(fmt(windowedScrub * 1000, 1)) ms"
                   + " → fullscreen \(fmt(fullScreenScrub * 1000, 1)) ms"
                   + "  (\(percent(scrubIncrease)))")
        lines.append("║")
        lines.append("║  → \(verdict)")
        lines.append("║  → \(scrubVerdict)")
        if let spread = roundSpread, spread > 0.05 {
            lines.append("║  ⚠️ Běhy se mezi sebou liší o \(fmt(spread * 100, 1)) %."
                       + " Průměr je pak měkký — zopakuj na ustáleném stroji.")
        }
        lines.append("║")
        lines.append("║  Cenu skládání tenhle nástroj nezměří. Pusť vedle:")
        lines.append("║    sudo powermetrics --samplers gpu_power,cpu_power -i 1000 > ~/krasa_gpu.txt")
        lines.append("║  a spáruj podle časů u jednotlivých běhů níž.")
        lines.append("╚═ jednotlivá kola níž")
        lines.append("")
        for (index, round) in rounds.enumerated() {
            let order = round.windowedFirst ? "okno → fullscreen" : "fullscreen → okno"
            lines.append("── kolo \(index + 1) (\(order)) ──")
            lines.append(contentsOf: round.windowed.report)
            lines.append("")
            lines.append(contentsOf: round.fullScreen.report)
            lines.append("")
        }
        return lines
    }

    private func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "bez dat" }
        return String(format: "%+.1f", value * 100).replacingOccurrences(of: ".", with: ",") + " %"
    }

    private func mpx(_ pixels: Double) -> String {
        fmt(pixels / 1_000_000, 2) + " Mpx"
    }
}
