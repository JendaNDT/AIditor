//
//  StatusBar.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, moduly 1 a 2. Stavový řádek 26 px: vlevo tečky běhů na pozadí,
//  vpravo poslední akce. Sem míří hook `onStatus` z osy — hlášky schránky
//  a hromadných operací, které dosud končily v sidebaru.
//
//  ⚠️ Řádek ukazuje JEN to, co opravdu existuje. Prázdné místo je lepší než
//  tečka „Proxy 0/0" u projektu bez klipů: uživatel se naučí, že tečka
//  znamená běh, a přestane ji číst, když svítí pořád.
//

import SwiftUI

struct ShellStatusBar: View {
    @ObservedObject var model: AppModel
    let mode: ShellMode

    var body: some View {
        HStack(spacing: 14) {
            AnalysisStatusDot(analysis: model.analysis)
            ProxyStatusDot(proxies: model.proxies, timeline: model.timeline)
            WhisperStatusDot(transcription: model.transcription)

            Spacer(minLength: 12)

            Text(trailingText)
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .frame(height: KrasaUI.Metric.statusBarHeight)
        .frame(maxWidth: .infinity)
        .background(KrasaUI.surfaceChrome)
    }

    private var trailingText: String {
        mode == .fullscreenApp
            ? model.status + " · menu vyjede u horní hrany"
            : model.status
    }
}

// MARK: - Tečka

/// Tečka se stavem jednoho běhu. Oranžová = pracuje se, zelená = hotovo.
private struct StatusDot: View {
    let text: String
    let isRunning: Bool
    var help: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isRunning ? KrasaUI.warn : KrasaUI.ok)
                .frame(width: 6, height: 6)
            Text(text)
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textSecondary)
                .lineLimit(1)
        }
        .help(help ?? text)
    }
}

/// Analýzy kvality (fáze 15). Do M2 běžely úplně bez UI — `startSharpnessAnalysis()`
/// se rozjelo po importu a uživatel se o něm dozvěděl tak, že se na klipech
/// samy od sebe objevily proužky.
private struct AnalysisStatusDot: View {
    @ObservedObject var analysis: AnalysisProgress

    var body: some View {
        if let text = analysis.statusText {
            StatusDot(text: text, isRunning: analysis.isRunning,
                      help: analysis.currentName.map { "Zpracovává se \($0)" })
        }
    }
}

/// Proxy (fáze 4). Během generování nese `ProxyStore` vlastní text
/// s pořadím, po dokončení se ukazuje počet a velikost cache.
private struct ProxyStatusDot: View {
    @ObservedObject var proxies: ProxyStore
    @ObservedObject var timeline: TimelineController

    var body: some View {
        if let progress = proxies.progressText {
            StatusDot(text: progress, isRunning: true)
        } else if proxies.finished.count > 0 {
            StatusDot(text: "Proxy \(proxies.finished.count)/\(videoAssetCount) · "
                      + ByteCountFormatter.string(fromByteCount: proxies.cacheSizeBytes,
                                                  countStyle: .file),
                      isRunning: false,
                      help: "Úložiště: \(proxies.directoryDisplayName)")
        }
    }

    /// Jmenovatel je počet assetů, ze kterých se proxy VYRÁBÍ — fotky
    /// a zvukové soubory mezi ně nepatří, jinak by se hlásilo 5/8 u projektu,
    /// kde je všech pět hotových.
    private var videoAssetCount: Int {
        timeline.project.assets.filter { $0.hasVideo && !$0.isStill }.count
    }
}

/// Model přepisu (fáze 8, správa z fáze 16). Nestažený model se neukazuje —
/// dokud uživatel titulky z řeči nepoužil, není co hlásit.
private struct WhisperStatusDot: View {
    @ObservedObject var transcription: TranscriptionService

    var body: some View {
        if let status = transcription.statusText {
            StatusDot(text: status, isRunning: true)
        } else if let size = transcription.modelSizeBytes {
            StatusDot(text: "Model přepisu "
                      + ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                      isRunning: false,
                      help: "Umístění: \(transcription.modelLocationName)")
        }
    }
}
