//
//  IconRail.swift
//  Projekt AIditor — UI/Shell
//
//  Fáze 18, modul 1. Ikonový rail vlevo, šířka 60. Určuje, co je v panelu
//  vpravo — nahrazuje vývojářský sidebar, ve kterém se mísil dokument,
//  nastavení, dodávka i měření.
//
//  V M1 přepíná rail jen mezi inspektorem a nastavením; obsah sekcí Text,
//  Barva, Zvuk a Řeč dodají moduly 7, 8 a 11. Položky proto nejsou
//  vypnuté — sekce existují, jen jejich panel zatím ukazuje kontextový
//  inspektor. Vypnout je by bylo lež opačným směrem.
//

import SwiftUI

struct IconRail: View {
    @ObservedObject var model: AppModel

    /// Nastavení sedí dole, oddělené od pracovních sekcí.
    private static let workSections: [RailSection] =
        [.media, .text, .color, .audio, .speech]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.workSections) { section in
                item(section)
            }
            Spacer(minLength: 0)
            item(.settings)
        }
        .padding(.vertical, 8)
        .frame(width: AIditorUI.Metric.railWidth)
        .frame(maxHeight: .infinity)
        .background(AIditorUI.surfaceRail)
    }

    /// Na prázdném startu jsou pracovní sekce kromě Médií ztlumené na 0,35
    /// (zadání, obrazovka 2) **a vypnuté** — bez klipu není co inspektovat.
    /// Nastavení ztlumené NENÍ, i když ho návrh takhle kreslí: na projektu
    /// nezávisí a je to jediná cesta ke správě proxy a modelu přepisu.
    /// Ztlumené tlačítko, které funguje, je lež stejně jako svítící, které
    /// nedělá nic (pravidlo z modulu 1).
    private func isDimmed(_ section: RailSection) -> Bool {
        model.showsEmptyStart && section != .media && section != .settings
    }

    private func item(_ section: RailSection) -> some View {
        let isActive = model.railSection == section
        let dimmed = isDimmed(section)
        return Button {
            model.railSection = section
            // Sáhnutí do railu má panel ukázat — jinak by kliknutí na
            // „Barva" při skrytém panelu (⌘4) nedělalo viditelně nic.
            model.panelVisible = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isActive ? AIditorUI.textPrimary : AIditorUI.textSecondary)
                Text(section.label)
                    .font(AIditorUI.Font.railLabel)
                    .foregroundStyle(isActive ? AIditorUI.textSecondary : AIditorUI.textTertiary)
            }
            .frame(width: AIditorUI.Metric.railItemSize,
                   height: AIditorUI.Metric.railItemSize)
            .background(
                RoundedRectangle(cornerRadius: AIditorUI.Metric.railItemRadius)
                    .fill(isActive ? AIditorUI.surfaceRailActive : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AIditorUI.Metric.railItemRadius)
                    .strokeBorder(isActive ? AIditorUI.borderActive : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.35 : 1)
        .disabled(dimmed)
        .help(dimmed ? "\(section.label) — až bude na ose materiál." : section.label)
    }
}
