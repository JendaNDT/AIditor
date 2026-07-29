//
//  StatusBar.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 1. Stavový řádek 26 px. Sem míří hook `onStatus` z osy —
//  hlášky schránky a hromadných operací, které dosud končily v sidebaru.
//
//  Tři stavové tečky (běžící analýzy, proxy, model přepisu) přidá modul 2;
//  levá strana je do té doby schválně prázdná.
//

import SwiftUI

struct ShellStatusBar: View {
    @ObservedObject var model: AppModel
    let mode: ShellMode

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

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
