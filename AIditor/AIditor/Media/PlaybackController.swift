//
//  PlaybackController.swift
//  Projekt AIditor
//
//  AVPlayer se seekem podle Apple QA1820.
//
//  https://developer.apple.com/library/archive/qa/qa1820/_index.html
//
//  Dvě věci, které se dají udělat špatně:
//
//  1. TOLERANCE. Bez `toleranceBefore/After: .zero` skočí přehrávač na
//     nejbližší klíčový snímek, což u HEVC může být o sekundu vedle.
//     V editoru je to nepoužitelné.
//
//  2. COALESCING. Při tažení scrubberem přijdou desítky požadavků za
//     sekundu. Vystřelit je všechny znamená frontu, která dobíhá dlouho
//     po tom, co uživatel pustil myš. Správně se drží jen POSLEDNÍ
//     požadovaný čas a po dokončení běžícího seeku se skočí rovnou na něj.
//

import AVFoundation
import Combine
import Foundation
import TimelineModel

@MainActor
final class PlaybackController: ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: CMTime = .zero
    @Published private(set) var duration: CMTime = .zero
    @Published private(set) var frameDuration: CMTime = CMTime(value: 1, timescale: 30)

    let player = AVPlayer()

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    // MARK: Coalescing podle QA1820
    private var chaseTime: CMTime = .invalid
    private var isSeekInProgress = false

    /// Kolik seeků se sloučilo — diagnostika, ne kosmetika.
    private(set) var coalescedSeekCount = 0

    init() {
        player.actionAtItemEnd = .pause
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time }
        }
        // Přehrávač si rychlost srazí sám — na konci osy (`actionAtItemEnd`)
        // i při výpadku bufferu. Bez tohohle by JKL indikátor tvrdil „4×",
        // zatímco obraz stojí. `rate` je KVO-observable.
        // <https://developer.apple.com/documentation/avfoundation/avplayer/rate>
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let rate = Double(player.rate)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.isSteppingFallback else { return }
                    self.shuttleRate = rate
                    self.isPlaying = rate != 0
                }
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        shuttleTimer?.invalidate()
    }

    // MARK: - Načtení

    func load(url: URL, measuredFrameRate: Double?) async throws {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)

        duration = try await asset.load(.duration)

        // Krok po snímku se řídí MĚŘENOU frekvencí, ne nominalFrameRate.
        // Ta na slow-mo klipu hlásí 119,369 místo skutečných 120,000.
        if let measuredFrameRate, measuredFrameRate > 0 {
            frameDuration = CMTime(seconds: 1.0 / measuredFrameRate, preferredTimescale: 90000)
        } else if let track = try await asset.loadTracks(withMediaType: .video).first {
            let nominal = try await track.load(.nominalFrameRate)
            frameDuration = nominal > 0
                ? CMTime(seconds: 1.0 / Double(nominal), preferredTimescale: 90000)
                : CMTime(value: 1, timescale: 30)
        }
        currentTime = .zero
    }

    // MARK: - Načtení timeline (fáze 3)

    /// Nahraje kompozici celé osy. Krok po snímku jde po snímcích ZÁKLADNY
    /// projektu — kompozice žádnou vlastní frekvenci nemá.
    func loadComposition(_ composition: AVComposition, frameRate: Int,
                         audioMix: AVAudioMix? = nil,
                         videoComposition: AVVideoComposition? = nil,
                         pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain) {
        pause()
        let item = AVPlayerItem(asset: composition)
        // Korekce výšky pro škálované zvukové úseky rampy. `.timeDomain`
        // zachovává transienty (rozhodnutí ze Spiku 0 — `.spectral` je
        // rozmazává do plechovosti); na úsecích 1× nedělá nic.
        // <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiotimepitchalgorithm-swift.property>
        // Od fáze 18 volitelné (panel Rychlost) — výchozí zůstává
        // `.timeDomain`, protože zachovává transienty.
        item.audioTimePitchAlgorithm = pitchAlgorithm
        // Per-track hlasitost a mute (fáze 7, modul 2).
        // <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix>
        item.audioMix = audioMix
        // Přechody (fáze 10): instrukce s opacity rampami. `nil` = přímá
        // cesta bez skládání — GPU baseline z fáze 1 zůstává v platnosti.
        // <https://developer.apple.com/documentation/avfoundation/avplayeritem/videocomposition>
        item.videoComposition = videoComposition
        player.replaceCurrentItem(with: item)
        duration = composition.duration
        frameDuration = CMTime(value: CMTimeValue(Int64(SourceTime.projectTimescale) / Int64(frameRate)),
                               timescale: SourceTime.projectTimescale)
        currentTime = .zero
    }

    /// Vymění mix na BĚŽÍCÍM itemu — změna hlasitosti stopy nesmí zastavit
    /// přehrávání, uživatel míchá poslechem. Kompozice se nesahá.
    func applyAudioMix(_ audioMix: AVAudioMix?) {
        player.currentItem?.audioMix = audioMix
    }

    // MARK: - Přehrávání

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        stopShuttleStepping()
        shuttleRate = 1
        player.play()
        isPlaying = true
    }

    func pause() {
        stopShuttleStepping()
        shuttleRate = 0
        player.pause()
        isPlaying = false
    }

    // MARK: - JKL (fáze 17)

    /// Žebřík rychlostí. L posouvá doprava, J doleva, K sráží na nulu —
    /// konvence z NLE: ze 4× vpřed se stiskem J jede 2× vpřed, ne rovnou
    /// pozpátku. Nula uprostřed je pauza.
    static let shuttleLadder: [Double] = [-8, -4, -2, -1, 0, 1, 2, 4, 8]

    /// Kam se má přehrávat. Vlastní stav, protože `player.rate` může být
    /// nula i v režimu krokovacího fallbacku (kde přehrávač stojí a čas
    /// posouvá časovač).
    @Published private(set) var shuttleRate: Double = 0

    /// Přehrává se pozpátku krokováním, protože to přehrávač jinak neumí.
    /// Přiznaná mez — status to říká uživateli.
    @Published private(set) var isSteppingFallback = false

    enum ShuttleStep { case backward, pause, forward }

    /// J / K / L. Vrací popis pro status, ať uživatel VIDÍ, co drží —
    /// „−2× (krokováním)" je jiná informace než „−2×".
    @discardableResult
    func shuttle(_ step: ShuttleStep) -> String {
        let ladder = Self.shuttleLadder
        let current = ladder.enumerated().min { abs($0.element - shuttleRate) < abs($1.element - shuttleRate) }?.offset
            ?? ladder.firstIndex(of: 0)!
        let next: Int
        switch step {
        case .forward: next = min(current + 1, ladder.count - 1)
        case .backward: next = max(current - 1, 0)
        case .pause: next = ladder.firstIndex(of: 0)!
        }
        return setShuttleRate(ladder[next])
    }

    @discardableResult
    func setShuttleRate(_ rate: Double) -> String {
        stopShuttleStepping()
        shuttleRate = rate

        guard rate != 0 else {
            player.pause()
            isPlaying = false
            return "Pauza"
        }

        if playerSupports(rate: rate) {
            player.rate = Float(rate)
            isPlaying = true
            return String(format: "%.0f×", rate)
        }

        // Přehrávač tuhle rychlost neumí (typicky zpětný chod). Fallback
        // podle plánu: krokování po snímcích. Zvuk nehraje a u 4K HEVC bez
        // proxy to bude trhat — ProRes proxy je intra-only a zvládne to.
        startShuttleStepping(rate: rate)
        isPlaying = true
        return String(format: "%.0f× (krokováním)", rate)
    }

    /// ⚠️ Zeptat se, ne předpokládat.
    ///
    /// Od macOS 10.9 jde KAŽDÝ hotový item přehrát mezi 1,0 a 2,0 i když
    /// `canPlayFastForward` hlásí `false` — ta vlastnost od té doby značí
    /// rychlosti NAD 2,0. Dokumentováno v hlavičce `AVPlayerItem`.
    ///
    /// <https://developer.apple.com/documentation/avfoundation/avplayeritem/canplayfastforward>
    /// <https://developer.apple.com/documentation/avfoundation/avplayeritem/canplayreverse>
    /// <https://developer.apple.com/documentation/avfoundation/avplayeritem/canplayfastreverse>
    /// Vynutí krokovací fallback i tam, kde přehrávač zpětný chod umí.
    /// Jen pro měření (`--jkl-check`): na naší kompozici vychází
    /// `canPlayReverse == true`, takže by se ta větev nikdy nespustila —
    /// a nespouštěná cesta tiše shnije.
    var forcesSteppingFallback = false

    func playerSupports(rate: Double) -> Bool {
        if forcesSteppingFallback, rate < 0 { return false }
        guard let item = player.currentItem, item.status == .readyToPlay else { return false }
        if rate > 2 { return item.canPlayFastForward }
        if rate > 0 { return true }
        if rate == -1 { return item.canPlayReverse }
        return item.canPlayFastReverse
    }

    /// Popis stavu transportu pro status a pro CLI kontrolu.
    var shuttleDescription: String {
        guard shuttleRate != 0 else { return "Pauza" }
        return String(format: "%.0f×", shuttleRate) + (isSteppingFallback ? " (krokováním)" : "")
    }

    // MARK: Krokovací fallback

    private var shuttleTimer: Timer?
    /// Kam už se doskákalo. Vlastní kurzor, protože seek se slučuje —
    /// `player.currentTime()` po sloučení odpovídá poslednímu DOKONČENÉMU
    /// skoku a krok by se o něj zasekl.
    private var shuttleCursor: CMTime = .zero

    private func startShuttleStepping(rate: Double) {
        let framesPerTick = max(1, Int(abs(rate).rounded()))
        let direction = rate < 0 ? -1 : 1
        player.pause()
        shuttleCursor = player.currentTime()
        isSteppingFallback = true

        // Tik na základně projektu: |rate| snímků za tik dá |rate|× rychlost.
        shuttleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let delta = CMTimeMultiply(self.frameDuration, multiplier: Int32(direction * framesPerTick))
                let next = self.clamp(CMTimeAdd(self.shuttleCursor, delta))
                // Doraz na začátek nebo konec osy shuttle zastaví — jinak by
                // časovač tepal donekonečna na jednom místě.
                if next == self.shuttleCursor {
                    self.setShuttleRate(0)
                    return
                }
                self.shuttleCursor = next
                self.seek(to: next)
            }
        }
    }

    private func stopShuttleStepping() {
        shuttleTimer?.invalidate()
        shuttleTimer = nil
        isSteppingFallback = false
    }

    // MARK: - Krokování

    func step(frames count: Int) {
        pause()
        guard frameDuration.isValid, frameDuration.value > 0 else { return }
        let delta = CMTimeMultiply(frameDuration, multiplier: Int32(count))
        let target = CMTimeAdd(player.currentTime(), delta)
        seek(to: clamp(target))
    }

    private func clamp(_ time: CMTime) -> CMTime {
        guard duration.isValid, duration > .zero else { return CMTimeMaximum(time, .zero) }
        return CMTimeMinimum(CMTimeMaximum(time, .zero), duration)
    }

    // MARK: - Seek s coalescingem

    /// Požadavek na skok. Volat klidně desetkrát za sekundu — sloučí se.
    func seek(to time: CMTime, completion: (@Sendable @MainActor (TimeInterval) -> Void)? = nil) {
        let requested = clamp(time)
        // Krokovací fallback si vede vlastní kurzor. Když mezitím skočí
        // uživatel (klik do pravítka), kurzor se srovná na jeho čas — jinak
        // by se krokování rvalo s ním a hlava by cukala mezi dvěma místy.
        shuttleCursor = requested
        guard requested != chaseTime || !isSeekInProgress else {
            chaseTime = requested
            return
        }
        chaseTime = requested
        guard !isSeekInProgress else {
            coalescedSeekCount += 1
            return
        }
        performSeek(startedAt: CACurrentMediaTime(), completion: completion)
    }

    private func performSeek(startedAt started: CFTimeInterval,
                             completion: (@Sendable @MainActor (TimeInterval) -> Void)?) {
        guard chaseTime.isValid else { isSeekInProgress = false; return }
        let target = chaseTime
        isSeekInProgress = true

        // Nulová tolerance na obě strany — jinak přehrávač skočí na klíčový snímek.
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = target
                if self.chaseTime == target {
                    // Nic nového nepřišlo — hotovo.
                    self.isSeekInProgress = false
                    completion?(CACurrentMediaTime() - started)
                } else {
                    // Mezitím dorazil novější požadavek. Skáče se rovnou na něj,
                    // mezilehlé se přeskočí — o to celé jde.
                    self.performSeek(startedAt: started, completion: completion)
                }
            }
        }
    }

    /// Seek bez coalescingu, pro měření jednotlivé odezvy.
    func measuredSeek(to time: CMTime) async -> TimeInterval {
        let target = clamp(time)
        let started = CACurrentMediaTime()
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        return CACurrentMediaTime() - started
    }
}
