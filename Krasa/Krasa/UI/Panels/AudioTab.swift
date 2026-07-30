//
//  AudioTab.swift
//  Projekt Krása — UI/Panels
//
//  Fáze 18, modul 8. Záložka Zvuk připnutého panelu.
//
//  Fade se dosud daly nastavit JEN tažením úchytu na klipu (fáze 16) — kdo
//  chtěl přesnou délku, neměl kde ji napsat. Tady jsou posuvníky s hodnotou
//  ve snímcích I v sekundách, protože jedna otázka je „kolik snímků" a druhá
//  „jak dlouho to slyším", a obě se ptají v jiné situaci.
//

import SwiftUI
import TimelineModel

struct AudioTab: View {
    @ObservedObject var timeline: TimelineController
    @ObservedObject var model: AppModel
    let clipID: ClipID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            metaRow
            fadeSection
            trackSection
            loudnessSection
        }
    }

    private var clip: Clip? { timeline.project.timeline.clip(clipID) }

    /// Stopa, na které klip leží — kvůli mute a hlasitosti.
    private var track: Track? {
        timeline.project.timeline.tracks.first { $0.clips.contains { $0.id == clipID } }
    }

    /// Zvuk klipu: buď je klip sám na zvukové stopě, nebo má svázané dvojče.
    private var audioClip: Clip? {
        guard let clip else { return nil }
        if track?.kind == .audio { return clip }
        guard let linkID = clip.linkID else { return nil }
        for candidate in timeline.project.timeline.tracks where candidate.kind == .audio {
            if let twin = candidate.clips.first(where: { $0.linkID == linkID && $0.id != clip.id }) {
                return twin
            }
        }
        return nil
    }

    private var audioTrack: Track? {
        guard let audioClip else { return nil }
        return timeline.project.timeline.tracks.first {
            $0.clips.contains { $0.id == audioClip.id }
        }
    }

    // MARK: - Meta

    private var metaRow: some View {
        Text(metaText)
            .font(KrasaUI.Font.chip)
            .foregroundStyle(KrasaUI.textTertiary)
    }

    private var metaText: String {
        guard let audioClip, let audioTrack else {
            return "Tenhle klip nemá zvuk — fade ani hlasitost tu nejsou k čemu."
        }
        let name = audioTrack.name
        return audioTrack.id == track?.id
            ? "zvuková stopa \(name)"
            : "svázaný zvuk na \(name)"
    }

    // MARK: - Fade

    /// ⚠️ Délky se čtou přes `effectiveAudioFades`, ne z `clip.audioFades`.
    /// Trim smí klip zkrátit pod součet fade a model to schválně NEZAŘEZÁVÁ
    /// (jinak by se přepisovalo šest trim operací) — zařezává až tohle jediné
    /// místo, ze kterého čte i kompozice. Panel musí ukazovat totéž, co je
    /// slyšet.
    private var fadeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Fade")

            if let audioClip {
                let effective = timeline.project.effectiveAudioFades(of: audioClip)
                fadeSlider(title: "Nájezd",
                           frames: effective?.fadeIn ?? .zero,
                           maximum: audioClip.duration) { newValue in
                    timeline.setAudioFades(audioClip.id, AudioFades(
                        fadeIn: newValue,
                        fadeOut: effective?.fadeOut ?? .zero))
                }
                fadeSlider(title: "Dojezd",
                           frames: effective?.fadeOut ?? .zero,
                           maximum: audioClip.duration) { newValue in
                    timeline.setAudioFades(audioClip.id, AudioFades(
                        fadeIn: effective?.fadeIn ?? .zero,
                        fadeOut: newValue))
                }
                Text("Hrana pod crossfadem fade nedostane — přechod tam rampuje sám "
                     + "a dvě rampy přes sebe mix dostat nesmí.")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Není co rozeznívat.")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textDisabled)
            }
        }
    }

    private func fadeSlider(title: String, frames: Frames, maximum: Frames,
                            set: @escaping (Frames) -> Void) -> some View {
        let rate = Double(timeline.project.timeline.frameRate)
        // Strop je polovina klipu: druhou půlku si bere protější fade
        // a součet přes délku by model odmítl.
        let cap = max(1.0, Double(maximum.count) / 2)
        return HStack(spacing: 8) {
            Text(title)
                .font(KrasaUI.Font.control)
                .foregroundStyle(KrasaUI.textSecondary)
                .frame(width: 52, alignment: .leading)
            Slider(value: Binding(
                get: { min(Double(frames.count), cap) },
                set: { set(Frames(Int($0.rounded()))) }), in: 0...cap)
                .controlSize(.small)
                .tint(KrasaUI.ok)
            // Snímky I sekundy: „18 sn" odpoví na otázku o přesnosti,
            // „0,6 s" na otázku, jak dlouho to bude slyšet.
            Text(String(format: "%d sn · %.1f s", frames.count, Double(frames.count) / rate)
                    .replacingOccurrences(of: ".", with: ","))
                .font(KrasaUI.Font.monoSmall)
                .foregroundStyle(KrasaUI.textSecondary)
                .frame(width: 82, alignment: .trailing)
        }
    }

    // MARK: - Stopa

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let audioTrack {
                sectionTitle("Stopa \(audioTrack.name)")
                HStack(spacing: 8) {
                    Button {
                        timeline.setTrackMuted(audioTrack.id,
                                               muted: !(audioTrack.audio?.isMuted ?? false))
                    } label: {
                        Text("M")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle((audioTrack.audio?.isMuted ?? false)
                                             ? KrasaUI.accentText : KrasaUI.textSecondary)
                            .frame(width: 22, height: 18)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill((audioTrack.audio?.isMuted ?? false) ? KrasaUI.warn : KrasaUI.surfaceControl))
                    }
                    .buttonStyle(.plain)
                    .help((audioTrack.audio?.isMuted ?? false) ? "Stopa je ztlumená" : "Ztlumit stopu")

                    Slider(value: Binding(
                        get: { audioTrack.audio?.volume ?? 1.0 },
                        set: { timeline.volumeDragChanged(audioTrack.id, volume: $0) }),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing { timeline.volumeDragBegan() }
                            else { timeline.volumeDragEnded() }
                        })
                        .controlSize(.small)
                    Text(Self.decibels(audioTrack.audio?.volume ?? 1.0))
                        .font(KrasaUI.Font.monoSmall)
                        .foregroundStyle(KrasaUI.textSecondary)
                        .frame(width: 58, alignment: .trailing)
                }
                // ⚠️ Rozsah `AVAudioMix.volume` je dokumentovaně 0,0–1,0.
                // Zesilovat přes něj se NESMÍ — normalizační gain se násobí
                // do vzorků v rendereru.
                Text("Posuvník jen ztišuje. Zesílení dělá normalizace v exportu, "
                     + "se stropem −1 dBTP.")
                    .font(KrasaUI.Font.chip)
                    .foregroundStyle(KrasaUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Hlasitost dodávky

    /// ⚠️ Ukazuje POSLEDNÍ NAMĚŘENOU hodnotu z exportu, a říká to.
    /// Hlasitost se nikde jinde neměří (scan trvá a jede přes celou osu), a
    /// měřidlo, které si čísla domyslí, je horší než měřidlo s pomlčkami.
    private var loudnessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Hlasitost dodávky")
            HStack(spacing: 6) {
                if let readout = model.lastLoudness {
                    chip(String(format: "%.1f LUFS", readout.lufs)
                            .replacingOccurrences(of: ".", with: ","),
                         color: KrasaUI.ok)
                    chip(String(format: "%.1f dBTP", readout.truePeakDB)
                            .replacingOccurrences(of: ".", with: ","),
                         color: KrasaUI.warn)
                    Text("naměřeno při posledním exportu")
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.textTertiary)
                } else {
                    Text("Změří se při exportu — dokud se nevyváželo, není co ukázat.")
                        .font(KrasaUI.Font.chip)
                        .foregroundStyle(KrasaUI.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Drobnosti

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(KrasaUI.Font.sectionTitle)
            .tracking(0.7)
            .foregroundStyle(KrasaUI.textTertiary)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(KrasaUI.Font.chip)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: KrasaUI.Metric.chipRadius)
                .fill(color.opacity(0.12)))
    }

    /// Hlasitost stopy je lineární 0–1; v decibelech je to čitelnější.
    private static func decibels(_ volume: Double) -> String {
        guard volume > 0.0001 else { return "−∞ dB" }
        let db = 20 * log10(volume)
        return String(format: "%+.1f dB", db)
            .replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: "-", with: "−")
    }
}
