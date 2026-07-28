//
//  PlaybackController.swift
//  Projekt Krása
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
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObserver?.invalidate()
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
                         audioMix: AVAudioMix? = nil) {
        pause()
        let item = AVPlayerItem(asset: composition)
        // Korekce výšky pro škálované zvukové úseky rampy. `.timeDomain`
        // zachovává transienty (rozhodnutí ze Spiku 0 — `.spectral` je
        // rozmazává do plechovosti); na úsecích 1× nedělá nic.
        // <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiotimepitchalgorithm-swift.property>
        item.audioTimePitchAlgorithm = .timeDomain
        // Per-track hlasitost a mute (fáze 7, modul 2).
        // <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix>
        item.audioMix = audioMix
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
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
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
