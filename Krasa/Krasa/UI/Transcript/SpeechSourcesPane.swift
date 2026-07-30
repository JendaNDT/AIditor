//
//  SpeechSourcesPane.swift
//  Projekt Krása — UI/Transcript
//
//  Zdroje řeči (fáze 18, modul 11). Stojí v horním pásu na místě knihovny,
//  když je rail na `Řeč` — rail podle zadání určuje, co je vpravo.
//
//  Odpovídá na jednu otázku, na kterou dosud nešlo odpovědět jinak než
//  proklikáním klipů: **co už je přepsané a co ne.**
//

import SwiftUI
import TimelineModel

struct SpeechSourcesPane: View {
    @ObservedObject var model: AppModel
    /// ⚠️ Vnořený `ObservableObject` se musí odebírat zvlášť — jinak pás
    /// nepozná, že se přepis změnil (táž past jako u `TranscriptPanel`).
    @ObservedObject var timeline: TimelineController
    @ObservedObject var transcription: TranscriptionService

    var body: some View {
        VStack(spacing: 0) {
            header
            KrasaUI.border.frame(height: 1)
            list
            KrasaUI.border.frame(height: 1)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(KrasaUI.surfaceRail)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Zdroje řeči")
                .font(KrasaUI.Font.controlStrong.weight(.semibold))
                .foregroundStyle(KrasaUI.textPrimary)
            Text("\(transcribed.count) z \(sources.count) přepsaných")
                .font(KrasaUI.Font.status)
                .foregroundStyle(KrasaUI.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sources, id: \.id) { asset in
                    row(for: asset)
                }
                if sources.isEmpty {
                    Text("Na ose není žádný zvukový klip.")
                        .font(KrasaUI.Font.status)
                        .foregroundStyle(KrasaUI.textTertiary)
                        .padding(.top, 12)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(for asset: Asset) -> some View {
        let segments = asset.transcript ?? []
        return Button {
            model.revealAssetOnTimeline(asset.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.originalURL.deletingPathExtension().lastPathComponent)
                    .font(KrasaUI.Font.control)
                    .foregroundStyle(KrasaUI.textPrimary)
                    .lineLimit(1)
                if segments.isEmpty {
                    Text("bez přepisu · ⌘5 spustí")
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.textTertiary)
                } else {
                    Text("\(segments.count) úseků · "
                         + TranscriptPanel.speechLength(of: segments))
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.ok)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(KrasaUI.surfaceRow))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(KrasaUI.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(modelText)
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textSecondary)
                .lineLimit(1)
            Text("Přepis běží ve stroji — nic se nikam neposílá.")
                .font(KrasaUI.Font.chip)
                .foregroundStyle(KrasaUI.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelText: String {
        guard let bytes = transcription.modelSizeBytes else {
            return "model se stáhne při prvním přepisu (~1,5 GB)"
        }
        return "large-v3 · "
            + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Zdroje se berou z KLIPŮ na zvukových stopách, ne ze všech assetů:
    /// řeč se přepisuje z toho, co je na ose (a `subtitleCues` bere taky jen
    /// zvukové stopy). Každý zdroj jednou, i když je položený dvakrát.
    private var sources: [Asset] {
        var seen: Set<AssetID> = []
        var out: [Asset] = []
        for track in timeline.project.timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard !seen.contains(clip.assetID),
                      let asset = timeline.project.asset(clip.assetID),
                      asset.hasAudio else { continue }
                seen.insert(clip.assetID)
                out.append(asset)
            }
        }
        return out
    }

    private var transcribed: [Asset] { sources.filter { $0.transcript?.isEmpty == false } }
}
