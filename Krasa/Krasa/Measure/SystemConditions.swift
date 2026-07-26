//
//  SystemConditions.swift
//  Projekt Krása
//
//  Stav stroje v okamžiku měření. Bez tohohle nejsou čísla mezi běhy
//  porovnatelná a anomálie vypadají jako záhada.
//
//  Air je bezventilátorový: když se pustí HEVC test a hned po něm ProRes,
//  druhý běží na teplejším stroji a vyjde hůř, než jaký doopravdy je.
//  Na baterce navíc macOS škrtí.
//

import Foundation
import IOKit.ps

struct SystemConditions {
    let thermalState: ProcessInfo.ThermalState
    let powerSource: String
    let lowPowerMode: Bool
    let activeProcessorCount: Int

    static func snapshot() -> SystemConditions {
        SystemConditions(thermalState: ProcessInfo.processInfo.thermalState,
                         powerSource: currentPowerSource(),
                         lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                         activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount)
    }

    /// `IOPSGetProvidingPowerSourceType` je „Get" funkce — vrací nepřevzatou
    /// referenci, takže `takeUnretainedValue`.
    private static func currentPowerSource() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return "neznámé"
        }
        guard let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return "neznámé"
        }
        switch type as String {
        case kIOPSACPowerValue: return "síť"
        case kIOPSBatteryPowerValue: return "baterie"
        case kIOPSOffLineValue: return "odpojeno"
        default: return type as String
        }
    }

    var summary: String {
        var parts = ["teplota \(SystemConditions.label(thermalState))", "napájení \(powerSource)"]
        if lowPowerMode { parts.append("⚠️ úsporný režim ZAPNUTÝ") }
        return parts.joined(separator: " · ")
    }

    static func label(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious ⚠️"
        case .critical: return "critical ⚠️"
        @unknown default: return "neznámý"
        }
    }

    /// Varování, když se podmínky mezi začátkem a koncem běhu změnily.
    /// Pak není co srovnávat a číslo platí jen s hvězdičkou.
    static func drift(from before: SystemConditions, to after: SystemConditions) -> String? {
        var changes: [String] = []
        if before.thermalState != after.thermalState {
            changes.append("teplota \(label(before.thermalState)) → \(label(after.thermalState))")
        }
        if before.powerSource != after.powerSource {
            changes.append("napájení \(before.powerSource) → \(after.powerSource)")
        }
        if before.lowPowerMode != after.lowPowerMode {
            changes.append("úsporný režim \(before.lowPowerMode) → \(after.lowPowerMode)")
        }
        guard !changes.isEmpty else { return nil }
        return "⚠️ Podmínky se během běhu změnily: " + changes.joined(separator: ", ")
            + ". Výsledek není přímo porovnatelný s ostatními běhy."
    }
}
