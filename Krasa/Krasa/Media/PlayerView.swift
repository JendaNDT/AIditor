//
//  PlayerView.swift
//  Projekt Krása
//
//  AVPlayerLayer v NSView, obalené pro SwiftUI.
//
//  NSView, ne SwiftUI VideoPlayer: potřebujeme vlastní display link kvůli
//  měření a přímý přístup k vrstvě. `NSView.displayLink(target:selector:)`
//  je macOS 14.0+, tedy přesně naše minimum.
//  https://developer.apple.com/documentation/appkit/nsview/4200851-displaylink
//

import AVFoundation
import AppKit
import SwiftUI

/// Jeden tik display linku.
///
/// ⚠️ **Co tahle metrika NEMĚŘÍ.** Display link je vázaný na vsync displeje.
/// Ten proběhne šedesátkrát za sekundu, ať skládání obrazu stíhá nebo ne —
/// když WindowServer nestihne nový snímek, ukáže se starý a vsync je tam
/// pořád. Vypadlý tik tedy znamená zaseknuté hlavní vlákno NAŠÍ aplikace,
/// ne přetížené GPU. Je to užitečné (odhalí zatuhlé UI), ale jako důkaz, že
/// kompozice 4K na velké ploše stíhá, to použít NELZE. Na to je `powermetrics`
/// puštěný vedle — viz `BenchmarkResult.powermetricsHint`.
///
/// `duration` navíc slouží k dopočtu SKUTEČNÉ obnovovací frekvence.
/// `NSScreen.maximumFramesPerSecond` je maximum, ne aktuální hodnota, a na
/// adaptivním displeji by z něj vyšly nesmysly.
///
/// `CADisplayLink` je na macOS od 14.0; `timestamp`, `targetTimestamp`
/// i `duration` má na všech platformách.
/// https://developer.apple.com/documentation/quartzcore/cadisplaylink
struct DisplayTick {
    let timestamp: CFTimeInterval
    let targetTimestamp: CFTimeInterval
    let duration: CFTimeInterval
}

/// NSView s AVPlayerLayer a display linkem svázaným s displejem okna.
final class PlayerHostView: NSView {

    let playerLayer = AVPlayerLayer()

    /// Volá se při každém obnovení displeje. Sem se věší měření.
    var onDisplayTick: ((DisplayTick) -> Void)?

    private var link: CADisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nepoužívá se") }

    override func layout() {
        super.layout()
        // Vrstva se nesmí animovat při změně velikosti okna, jinak obraz „plave".
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = visibleBounds
        CATransaction.commit()
    }

    /// Průnik vlastní plochy s obsahem okna.
    ///
    /// SwiftUI umí view poslat rozměr větší, než je okno — stačí, aby si nějaký
    /// sourozenec vyžádal výšku, kterou nemá kam dát. Kdyby se vrstva roztáhla
    /// na takový `bounds`, `resizeAspect` by obraz vycentroval mimo obrazovku
    /// a WindowServer by ho neskládal: měření by pak hlásilo plných 60 fps
    /// z dekodéru, zatímco GPU by nedělalo nic. Přesně to se 27. 07. 2026 stalo.
    var visibleBounds: NSRect {
        guard let content = window?.contentView, content !== self else { return bounds }
        let visible = convert(content.bounds, from: content)
        let clipped = bounds.intersection(visible)
        return clipped.isNull || clipped.isEmpty ? bounds : clipped
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }

        let displayLink = self.displayLink(target: self, selector: #selector(displayTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    @objc private func displayTick(_ sender: CADisplayLink) {
        onDisplayTick?(DisplayTick(timestamp: sender.timestamp,
                                   targetTimestamp: sender.targetTimestamp,
                                   duration: sender.duration))
    }

    // MARK: Popis displeje

    /// Nejvyšší obnovovací frekvence displeje. POZOR: maximum, ne aktuální
    /// hodnota. Na adaptivním panelu se skutečná frekvence bere z tiků.
    var displayRefreshRate: Double {
        guard let screen = window?.screen else { return 60 }
        let maximum = screen.maximumFramesPerSecond
        return maximum > 0 ? Double(maximum) : 60
    }

    var screenName: String {
        window?.screen?.localizedName ?? "neznámý displej"
    }

    var backingScale: CGFloat {
        window?.backingScaleFactor ?? 1
    }

    /// Celý displej v backing pixelech — měřítko, proti kterému se pozná,
    /// jestli „fullscreen" opravdu znamenal celou obrazovku.
    var screenBackingPixelSize: CGSize {
        guard let frame = window?.screen?.frame else { return .zero }
        return CGSize(width: frame.width * backingScale, height: frame.height * backingScale)
    }

    // MARK: Plocha

    /// Plocha vrstvy v backing pixelech — tolik pixelů GPU doopravdy skládá.
    /// Body samy o sobě nestačí: na Retina panelu je jich čtyřikrát míň.
    /// Počítá se z `visibleBounds`, ne z `bounds` — vrstva má od zavedení
    /// ořezu právě tenhle rámec.
    var layerBackingPixelSize: CGSize {
        let rect = visibleBounds
        return CGSize(width: rect.width * backingScale, height: rect.height * backingScale)
    }

    /// Plocha samotného obrazu v backing pixelech. Při `resizeAspect` je menší
    /// než vrstva — u 16:9 videa na 16:10 panelu vždycky, a ve svisle
    /// protaženém okně výrazně. Srovnávat velikost okna místo tohohle by lhalo.
    /// https://developer.apple.com/documentation/avfoundation/avplayerlayer/videorect
    var videoBackingPixelSize: CGSize {
        let rect = playerLayer.videoRect
        return CGSize(width: rect.width * backingScale, height: rect.height * backingScale)
    }

    // MARK: Viditelnost — pojistky proti měření naslepo

    /// Je aspoň část okna vidět? Když ne, WindowServer okno neskládá a všechno,
    /// co měří kompozici, je nula — zatímco snímky z dekodéru chodí dál.
    /// Typicky nastane, když se okno přepne do fullscreenu na vlastní Space
    /// a uživatel zůstane na jiném.
    /// https://developer.apple.com/documentation/appkit/nswindow/occlusionstate
    var isWindowVisible: Bool {
        window?.occlusionState.contains(.visible) ?? false
    }

    /// Kolik z obrazu doopravdy leží uvnitř obsahu okna. 1,0 = celý.
    /// Druhá pojistka: okno může být „visible" a obraz přesto mimo.
    var videoVisibleFraction: Double {
        guard let content = window?.contentView, content !== self else { return 0 }
        // `videoRect` je v souřadnicích VRSTVY, `convert(_:to:)` čeká souřadnice
        // view. Dokud byl `playerLayer.frame == bounds`, obojí splývalo. Od
        // zavedení `visibleBounds` má vrstva nenulový počátek — a to přesně
        // v případě, kvůli kterému tahle pojistka vznikla. Bez posunu by tady
        // vyšel nesmysl zrovna tam, kde na výsledku záleží.
        let inSelf = playerLayer.videoRect.offsetBy(dx: playerLayer.frame.minX,
                                                    dy: playerLayer.frame.minY)
        let rect = convert(inSelf, to: content)
        let area = rect.width * rect.height
        guard area > 0 else { return 0 }
        let clipped = rect.intersection(content.bounds)
        guard !clipped.isEmpty else { return 0 }
        return Double((clipped.width * clipped.height) / area)
    }
}

// MARK: - Přepnutí okna na celou obrazovku

/// Přepínání okna do fullscreenu a zpět, s čekáním na dokončení přechodu.
///
/// `toggleFullScreen(_:)` (macOS 10.7+) se vrací hned. Systém přepne bit
/// `NSWindow.StyleMask.fullScreen` už na ZAČÁTKU přechodu, ne na konci —
/// čekání na hodnotu tedy skončí dřív, než doběhne animace. Proto se po něm
/// čeká ještě `settleSeconds` a volající si má sám ověřit, že se plocha
/// doopravdy změnila (`PlayerHostView.videoBackingPixelSize`).
///
/// https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:)
/// https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullscreen
/// https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenprimary
@MainActor
enum FullScreenSwitch {

    /// Nejdéle takhle dlouho se čeká, než se přepne bit ve `styleMask`.
    static let transitionTimeout: TimeInterval = 5

    /// Klid po přepnutí bitu: doběhne animace, vrstva se přelayoutuje
    /// a přehrávač se srovná s novou plochou.
    static let settleSeconds: TimeInterval = 2.5

    static func isFullScreen(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.fullScreen)
    }

    /// Přepne okno do požadovaného stavu a počká, až tam bude.
    /// Vrací `false`, když se přechod nestihl — pak se nemá co měřit.
    @discardableResult
    static func set(_ wanted: Bool, on window: NSWindow) async -> Bool {
        if isFullScreen(window) == wanted { return true }

        // Bez `.fullScreenPrimary` a bez `.resizable` toggleFullScreen mlčky
        // neudělá nic. U SwiftUI okna to obvykle nastavené je, ale spoléhat
        // se na to znamená měřit okno v domnění, že měříš fullscreen.
        window.collectionBehavior.insert(.fullScreenPrimary)

        // ⚠️ `styleMask` se smí přepisovat JEN mimo fullscreen. `insert` je
        // get-modify-set, takže by ve fullscreenu zapsal masku i s bitem
        // `.fullScreen` — a ten se nastavovat přímo nesmí, AppKit na to
        // odpovídá NSInternalInconsistencyException. Sem se dostaneme jen
        // když `isFullScreen != wanted`, takže `wanted == true` znamená
        // „teď jsme v okně" a zápis je bezpečný.
        if wanted, !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }

        window.toggleFullScreen(nil)

        let deadline = Date().addingTimeInterval(transitionTimeout)
        while Date() < deadline {
            if isFullScreen(window) == wanted {
                try? await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000))
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    var onHostView: ((PlayerHostView) -> Void)?

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView(frame: .zero)
        view.playerLayer.player = player
        onHostView?(view)
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        // Po přepnutí na fullscreen a zpět může SwiftUI view přetvořit.
        // Bez tohohle by měření drželo starý PlayerHostView bez okna,
        // naměřilo nula tiků a vydalo to za „fullscreen bolí".
        onHostView?(nsView)
    }
}
