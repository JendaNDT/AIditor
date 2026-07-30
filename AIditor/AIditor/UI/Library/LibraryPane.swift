//
//  LibraryPane.swift
//  Projekt AIditor — UI/Library
//
//  Knihovna médií (fáze 18, modul 9). Pás 330 bodů vpravo v horním pásu:
//  hlavička, filtry, mřížka karet, patička s proxy.
//  Zdroj zadání: `design_handoff_aiditor_ui/README.md`, sekce 1.3 „Knihovna".
//
//  Zavírá potíž #6 ze zadání („chyběla knihovna médií / prohlížeč záběrů").
//  Dosud šlo materiál vidět jen jako klipy na ose — kdo chtěl vědět, co má
//  k dispozici, musel se dívat do Finderu.
//
//  ⚠️ Řadí se CHRONOLOGICKY, ne podle jména. U jedné kamery je název časové
//  razítko, u telefonu hosta ne (pravidlo z F17, modul 3). Assety bez času
//  jdou dozadu.
//
//  ⚠️ Karty mají PEVNOU výšku (`LibraryCard.height`) — past pojmenovaná
//  v zadání: mřížka by je jinak zmáčkla.
//

import SwiftUI
import TimelineModel

/// Filtr knihovny. Pořadí i názvy podle zadání.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, video, stills, music

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Vše"
        case .video: return "Video"
        case .stills: return "Fotky"
        case .music: return "Hudba"
        }
    }

    func matches(_ asset: Asset) -> Bool {
        switch self {
        case .all: return true
        case .video: return asset.hasVideo && !asset.isStill
        case .stills: return asset.isStill
        case .music: return asset.hasAudio && !asset.hasVideo && !asset.isStill
        }
    }
}

struct LibraryPane: View {
    @ObservedObject var model: AppModel
    @State private var filter: LibraryFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            header
            AIditorUI.border.frame(height: 1)
            filters
            grid
            AIditorUI.border.frame(height: 1)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(AIditorUI.surfaceRail)
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: 8) {
            Text("Knihovna")
                .font(AIditorUI.Font.controlStrong.weight(.semibold))
                .foregroundStyle(AIditorUI.textPrimary)
            Text("\(assets.count) · chronologicky")
                .font(AIditorUI.Font.status)
                .foregroundStyle(AIditorUI.textTertiary)
            Spacer()
            Button {
                Task { await model.openFiles(directories: false) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AIditorUI.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isMeasuring)
            .help("Přidat média…")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    // MARK: - Filtry

    private var filters: some View {
        HStack(spacing: 5) {
            ForEach(LibraryFilter.allCases) { item in
                FilterPill(title: item.label, count: count(of: item),
                           isOn: filter == item) { filter = item }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func count(of item: LibraryFilter) -> Int {
        model.timeline.project.assets.filter { item.matches($0) }.count
    }

    // MARK: - Mřížka

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(assets) { asset in
                    LibraryCard(asset: asset,
                                timing: timing(for: asset),
                                isOnTimeline: isOnTimeline(asset),
                                softRuns: softRuns(for: asset),
                                isSelected: model.librarySelection == asset.id,
                                thumbnails: model.timeline.thumbnails,
                                usesProxies: model.timeline.project.usesProxies,
                                onSelect: { model.librarySelection = asset.id },
                                onReveal: { model.revealAssetOnTimeline(asset.id) })
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
        // Prázdná knihovna to řekne — mřížka bez karet vypadá jako chyba
        // kreslení. (Prázdný start jako obrazovka je M12.)
        .overlay {
            if assets.isEmpty {
                Text(model.timeline.project.assets.isEmpty
                     ? "Zatím žádná média.\nPřidej je tlačítkem ＋."
                     : "V tomhle filtru nic není.")
                    .font(AIditorUI.Font.status)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AIditorUI.textTertiary)
            }
        }
    }

    /// Assety podle filtru, chronologicky; bez času natočení dozadu.
    private var assets: [Asset] {
        model.timeline.project.assets
            .filter { filter.matches($0) }
            .sorted { a, b in
                switch (a.creationDate, b.creationDate) {
                case let (x?, y?): return x == y ? name(a) < name(b) : x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return name(a) < name(b)
                }
            }
    }

    private func name(_ asset: Asset) -> String {
        asset.originalURL.lastPathComponent
    }

    private func timing(for asset: Asset) -> ClipTiming? {
        model.clips.first { $0.url == asset.originalURL }
    }

    private func isOnTimeline(_ asset: Asset) -> Bool {
        model.timeline.project.timeline.tracks.contains { track in
            track.clips.contains { $0.assetID == asset.id }
        }
    }

    /// Problémové úseky ostrosti z JEDNÉ tabulky prahů — té, kterou počítá
    /// model pro osu. Karta si vlastní klasifikaci nevymýšlí.
    private func softRuns(for asset: Asset) -> Int {
        guard !model.timeline.sharpnessSamples.isEmpty else { return 0 }
        let marks = model.timeline.project.qualityMarks(
            samples: model.timeline.sharpnessSamples,
            sensitivity: model.timeline.qualitySensitivity)
        var count = 0
        for track in model.timeline.project.timeline.tracks where track.kind == .video {
            for clip in track.clips where clip.assetID == asset.id {
                count += marks[clip.id]?.count ?? 0
            }
        }
        return count
    }

    // MARK: - Patička

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Uspořádat na V1 chronologicky") {
                guard let v1 = model.timeline.project.timeline.tracks
                    .first(where: { $0.kind == .video })?.id else { return }
                model.timeline.arrangeChronologically(trackID: v1)
            }
            .buttonStyle(.plain)
            .font(AIditorUI.Font.control)
            .foregroundStyle(AIditorUI.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                .fill(AIditorUI.surfaceControl))
            .overlay(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                .strokeBorder(AIditorUI.borderStrong, lineWidth: 1))
            .disabled(!canArrange)
            .help(canArrange
                  ? "Seřadí klipy na V1 podle času natočení a zavře mezery."
                  : "Žádný klip na V1 nemá čas natočení.")

            ProxyFooterLine(proxies: model.proxies, timeline: model.timeline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var canArrange: Bool {
        guard let v1 = model.timeline.project.timeline.tracks
            .first(where: { $0.kind == .video }) else { return false }
        return v1.clips.contains { clip in
            model.timeline.project.asset(clip.assetID)?.creationDate != nil
        }
    }
}

// MARK: - Pilulka filtru

private struct FilterPill: View {
    let title: String
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(count > 0 ? "\(title) \(count)" : title)
                .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? AIditorUI.textPrimary : AIditorUI.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? AIditorUI.surfaceRailActive : AIditorUI.surfaceRow))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isOn ? AIditorUI.borderActive : AIditorUI.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Řádek proxy v patičce

/// Stav proxy. Text je týž jako ve stavovém řádku (M2) — vlastní formátování
/// by se s ním rozešlo, jen tady je i tečka a odkaz na nastavení.
private struct ProxyFooterLine: View {
    @ObservedObject var proxies: ProxyStore
    @ObservedObject var timeline: TimelineController

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(proxies.progressText != nil ? AIditorUI.warn : AIditorUI.ok)
                .frame(width: 7, height: 7)
            Text(text)
                .font(AIditorUI.Font.status)
                .foregroundStyle(AIditorUI.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .help("Úložiště: \(proxies.directoryDisplayName)")
    }

    private var text: String {
        if let progress = proxies.progressText { return progress }
        guard proxies.finished.count > 0 else { return "Proxy se nedělají" }
        return "Proxy \(proxies.finished.count)/\(videoAssetCount) · "
            + ByteCountFormatter.string(fromByteCount: proxies.cacheSizeBytes, countStyle: .file)
    }

    private var videoAssetCount: Int {
        timeline.project.assets.filter { $0.hasVideo && !$0.isStill }.count
    }
}
