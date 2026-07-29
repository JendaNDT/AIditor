//
//  AnalysisProgress.swift
//  Projekt Krása — UI/Shell
//
//  Fáze 18, modul 2. Stav běžících analýz kvality (ostrost, hluchá místa).
//
//  ⚠️ Proč to nežije v `SharpnessStore` a `EmptinessStore`.
//  Ty jsou actory nad JEDNÍM souborem — o tom, že se zpracovává třetí asset
//  z pěti, nevědí a vědět nemají. „3/5" je stav SMYČKY, kterou drží
//  `AppModel`, takže postup patří sem, vedle ní. Do storů by se musel
//  protlačit shora, aby ho mohly hlásit zpátky dolů.
//
//  Do `Project` (a tedy do projektového souboru) nepatří nic z toho — je to
//  stav sezení.
//

import SwiftUI

@MainActor
final class AnalysisProgress: ObservableObject {

    enum Kind {
        case sharpness
        case emptiness

        /// Do stavového řádku (název dimenze).
        var label: String {
            switch self {
            case .sharpness: return "Ostrost"
            case .emptiness: return "Hluchá místa"
            }
        }

        /// Do čipu v toolbaru (co se zrovna dělá).
        var verb: String {
            switch self {
            case .sharpness: return "Analyzuju ostrost"
            case .emptiness: return "Analyzuju hluchá místa"
            }
        }
    }

    @Published private(set) var total = 0
    @Published private(set) var sharpnessDone = 0
    @Published private(set) var emptinessDone = 0
    /// Co běží PRÁVĚ TEĎ. `nil` = nic — a to je jediný stav, ve kterém smí
    /// čip z toolbaru zmizet.
    @Published private(set) var running: Kind?
    /// Jméno souboru, na kterém se pracuje. Do tooltipu.
    @Published private(set) var currentName: String?

    /// Záznam přechodů pro `--status-check`. Vypnutý ve výchozím stavu —
    /// běžný provoz ho nepotřebuje a v paměti by rostl donekonečna.
    var logsTransitions = false
    private(set) var log: [String] = []

    var isRunning: Bool { running != nil }
    /// Analýza doběhla a je co ukázat. Rozlišuje se od „nikdy neběžela",
    /// aby stavový řádek u čerstvě spuštěné aplikace nehlásil „0/0 hotovo".
    var hasFinished: Bool { total > 0 && running == nil }

    /// Text čipu v toolbaru. `nil` = nic neběží, čip se nekreslí vůbec.
    ///
    /// Číslo je „kolikátý se zpracovává", ne „kolik je hotových" — proto
    /// `done + 1`. Uživatel čte „3/5" jako „je na třetím z pěti".
    var chipText: String? {
        guard let running else { return nil }
        let done = running == .sharpness ? sharpnessDone : emptinessDone
        return "\(running.verb) · \(min(done + 1, total))/\(total)"
    }

    /// Text do stavového řádku. `nil` = analýza nikdy neběžela.
    var statusText: String? {
        if let running {
            let done = running == .sharpness ? sharpnessDone : emptinessDone
            return "\(running.label) \(min(done + 1, total))/\(total)"
        }
        guard hasFinished else { return nil }
        return "Kvalita \(sharpnessDone)/\(total)"
    }

    // MARK: - Průběh

    func begin(total: Int) {
        self.total = total
        sharpnessDone = 0
        emptinessDone = 0
        running = nil
        currentName = nil
        record("begin total=\(total)")
    }

    func started(_ kind: Kind, name: String) {
        running = kind
        currentName = name
        record("start \(kind.label) \(name)")
    }

    func finished(_ kind: Kind) {
        switch kind {
        case .sharpness: sharpnessDone += 1
        case .emptiness: emptinessDone += 1
        }
        record("done \(kind.label) \(sharpnessDone)/\(emptinessDone) z \(total)")
    }

    /// ⚠️ **Musí se zavolat i když smyčka spadne nebo se zruší** — jinak
    /// čip v toolbaru zůstane viset a tvrdí, že se pracuje, když se nepracuje.
    /// Volající to zajišťuje `defer`em.
    func finish() {
        running = nil
        currentName = nil
        record("finish")
    }

    private func record(_ line: String) {
        guard logsTransitions else { return }
        log.append(line)
    }
}

// MARK: - Čip v toolbaru

/// Čip běžících analýz. Kreslí se JEN když něco běží — trvale přítomný
/// čip s textem „nic neběží" by zabíral místo a nic neříkal.
struct AnalysisChip: View {
    @ObservedObject var analysis: AnalysisProgress

    var body: some View {
        if let text = analysis.chipText {
            HStack(spacing: 6) {
                Circle()
                    .fill(KrasaUI.warn)
                    .frame(width: 7, height: 7)
                Text(text)
                    .font(KrasaUI.Font.control)
                    .foregroundStyle(KrasaUI.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: KrasaUI.Metric.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: KrasaUI.Metric.controlRadius)
                    .fill(KrasaUI.warn.opacity(0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KrasaUI.Metric.controlRadius)
                    .strokeBorder(KrasaUI.warn.opacity(0.32), lineWidth: 1)
            )
            .help(analysis.currentName.map { "Zpracovává se \($0)" }
                  ?? "Analýzy běží na pozadí, střihat můžeš dál.")
        }
    }
}
