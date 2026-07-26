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

/// NSView s AVPlayerLayer a display linkem svázaným s displejem okna.
final class PlayerHostView: NSView {

    let playerLayer = AVPlayerLayer()

    /// Volá se při každém obnovení displeje. Sem se věší měření.
    var onDisplayTick: ((CFTimeInterval) -> Void)?

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
        playerLayer.frame = bounds
        CATransaction.commit()
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
        onDisplayTick?(sender.targetTimestamp)
    }

    /// Kolikrát za sekundu se obnovuje displej. Strop pro doručené snímky —
    /// na 60Hz panelu se víc než 60 fps doručit nedá, ať je zdroj jakýkoli.
    var displayRefreshRate: Double {
        guard let screen = window?.screen else { return 60 }
        let maximum = screen.maximumFramesPerSecond
        return maximum > 0 ? Double(maximum) : 60
    }

    var backingScale: CGFloat {
        window?.backingScaleFactor ?? 1
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
    }
}
