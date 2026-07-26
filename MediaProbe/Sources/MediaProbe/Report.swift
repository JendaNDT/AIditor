//
//  Report.swift
//  Projekt Krása / MediaProbe
//
//  Formátování výsledků do konzole a do RESULTS.md. Žádné měření tady
//  neprobíhá — jen se tiskne, co Inspect a SampleTimingReader naměřily.
//

import AVFoundation
import CoreMedia
import Foundation
import ProbeKit

enum Report {

    // MARK: - Souhrnná tabulka

    static let summaryHeader = [
        "Soubor", "Obraz", "Kodek", "fps nom.", "fps měř.",
        "Edit V/A", "Délka", "Zvuk", "Kolísání", "Okraje", "Zahozeno", "Verdikt",
    ]

    static func summaryRow(_ clip: ClipReport) -> [String] {
        guard clip.failure == nil else {
            return [clip.name, "—", "—", "—", "—", "—", "—", "—", "—", "—", "—", "CHYBA"]
        }

        let video = clip.video
        let audio = clip.audio
        let timing = video?.timing

        let picture: String = {
            guard let v = video else { return "—" }
            let size = "\(Int(v.displaySize.width))×\(Int(v.displaySize.height))"
            return v.rotationDegrees == 0 ? size : "\(size) ↻\(v.rotationDegrees)°"
        }()

        // Edit list se hlásí za obraz i za zvuk zvlášť. Zvuková stopa bývá
        // netriviální i tam, kde je obraz 1:1 — a právě to rozjíždí synchron.
        func editMark(_ list: EditListInfo?) -> String {
            guard let list else { return "—" }
            if list.isIdentity { return "1:1" }
            if let rate = list.overallRate, abs(rate - 1.0) > 1e-6 { return "\(fmt(rate, 2))×" }
            return "⚠"
        }
        let editList = "\(editMark(video?.editList))/\(editMark(audio?.editList))"

        let audioText: String = {
            guard let a = audio else { return "—" }
            return "\(a.codec) \(a.channels)ch \(fmt(a.sampleRate / 1000, 1))k"
        }()

        // Kolísání je jen zevnitř stopy — bez zahozených snímků a bez okrajů.
        // Obojí by ho nafouklo o řád a zakrylo, že časování je jinak klidné.
        // Nic se ale nezahazuje potichu: okraje i zahozené mají vlastní sloupec.
        let jitter: String = timing.map { "\(fmt($0.interiorJitterPercent, 1)) %" } ?? "—"
        let edges: String = timing.map { t in
            let odd = t.anomalousEdges
            guard !odd.isEmpty else { return "ok" }
            return odd.map { "\(fmt($0.ratioToMode, 2))× \($0.shortPosition)" }
                .joined(separator: " ")
        } ?? "—"
        let dropped: String = timing.map { t in
            t.droppedFrames == 0 ? "—" : "\(t.droppedFrames) v \(t.droppedEvents)×"
        } ?? "—"

        return [
            clip.name,
            picture,
            video.map { "\($0.codec)" } ?? "—",
            video.map { fmt(Double($0.nominalFrameRate), 2) } ?? "—",
            timing.map { fmt($0.measuredFrameRate, 2) } ?? "—",
            editList,
            timeString(clip.duration),
            audioText,
            jitter,
            edges,
            dropped,
            timing?.verdict.shortLabel ?? "—",
        ]
    }

    // MARK: - Detailní blok

    static func detail(_ clip: ClipReport) -> [String] {
        var lines: [String] = []
        let size = clip.fileSize.map { " · \(fmt(Double($0) / 1_048_576, 1)) MB" } ?? ""
        lines.append("▸ \(clip.name)  (\(clip.formatName)\(size))")
        lines.append("  Obsah      \(clip.note ?? "⚠ nevyplněno — doplň do MediaProbe/CLIPS.txt")")

        if let failure = clip.failure {
            lines.append("  ✗ Soubor se nepodařilo přečíst: \(failure)")
            return lines
        }

        if let v = clip.video {
            lines.append(contentsOf: videoLines(v))
        } else {
            lines.append("  Obraz      žádná video stopa")
        }

        if let a = clip.audio {
            lines.append(contentsOf: audioLines(a))
        } else {
            lines.append("  Zvuk       žádná zvuková stopa")
        }

        lines.append("  Délka      \(timeString(clip.duration)) (asset)")
        return lines
    }

    private static func videoLines(_ v: VideoTrackInfo) -> [String] {
        var lines: [String] = []
        let orientation = v.isPortrait ? "na výšku" : "na šířku"
        lines.append("  Obraz      \(Int(v.naturalSize.width))×\(Int(v.naturalSize.height)) nativně"
                   + ", transform ↻\(v.rotationDegrees)°"
                   + " → zobrazeno \(Int(v.displaySize.width))×\(Int(v.displaySize.height)) (\(orientation))")
        if v.encodedSize != .zero && v.encodedSize != v.naturalSize {
            lines.append("             kódované rozměry \(Int(v.encodedSize.width))×\(Int(v.encodedSize.height))"
                       + " — liší se od nativních, kodek zarovnává na bloky")
        }
        lines.append("             kodek \(v.codec) (\(v.codecFourCC))"
                   + ", datový tok \(fmt(Double(v.estimatedDataRate) / 1_000_000, 1)) Mbit/s")

        let minFD = v.minFrameDuration
        let minFDText = minFD.isValid && minFD.value > 0
            ? "\(minFD.value)/\(minFD.timescale) (\(fmt(minFD.seconds * 1000, 3)) ms)"
            : "neuvedeno"
        lines.append("  Deklarace  nominální fps \(fmt(Double(v.nominalFrameRate), 3))"
                   + ", minFrameDuration \(minFDText)")
        lines.append("             timescale stopy \(v.naturalTimeScale)"
                   + ", timeRange \(timeString(v.timeRange.duration))")

        lines.append(contentsOf: editListLines(v.editList, label: "Edit list"))

        if let t = v.timing {
            lines.append(contentsOf: timingLines(t))
            if let effective = v.effectiveFrameRate,
               abs(effective - t.measuredFrameRate) > 0.01 {
                lines.append("  ⚠ Pozor    vzorky mají \(fmt(t.measuredFrameRate, 2)) fps, ale edit list je"
                           + " zpomaluje na \(fmt(effective, 2)) fps při přehrávání.")
                lines.append("             Syrová data tedy NEjsou to, co divák uvidí.")
            }
            lines.append("  Verdikt    \(t.verdict.explanation)")
        } else {
            lines.append("  Vzorky     ✗ nepodařilo se přečíst")
        }
        if let note = v.timingError {
            lines.append("  Poznámka   \(note)")
        }
        return lines
    }

    private static func timingLines(_ t: TimingStats) -> [String] {
        var lines: [String] = []
        lines.append("  Vzorky     \(t.sampleCount) přečteno přes \(t.source.rawValue)"
                   + ", \(t.distinctCount) různá délka/délky"
                   + (t.rescaled ? " (po převodu timescale)" : ""))

        let top = t.histogram.prefix(6).map { entry in
            "\(entry.tick) t = \(fmt(t.milliseconds(entry.tick), 3)) ms ×\(entry.count)"
        }.joined(separator: ", ")
        let more = t.histogram.count > 6 ? " … a další \(t.histogram.count - 6)" : ""
        lines.append("             histogram: \(top)\(more)")

        lines.append("             min \(t.minTick) t (\(fmt(t.milliseconds(t.minTick), 3)) ms)"
                   + ", max \(t.maxTick) t (\(fmt(t.milliseconds(t.maxTick), 3)) ms)"
                   + ", modus \(t.mode) t (\(fmt(t.milliseconds(t.mode), 3)) ms)")
        lines.append("             směrodatná odchylka \(fmt(t.stdDevTicks, 4)) ticku"
                   + " = \(fmt(t.stdDevTicks * t.msPerTick, 4)) ms")
        lines.append("             měřená fps z modu \(fmt(t.measuredFrameRate, 4))")

        lines.append("  Rozbor     \(t.normalCount)× přesně na modu"
                   + " · \(t.roundingCount)× zaokrouhlení (±1 tick)"
                   + " · \(t.droppedEvents)× násobek modu"
                   + " · \(t.irregularCount)× nepravidelné")

        if t.droppedFrames > 0 {
            lines.append("  Zahozeno   \(t.droppedFrames) snímek/snímků ve \(t.droppedEvents) místě/místech"
                       + " — vzorek je celočíselným násobkem délky snímku.")
            lines.append("             Opraví se doplněním duplikátů, ne přepočtem časování.")
        }

        lines.append("  Kolísání   \(t.interiorDeviationTicks) t"
                   + " = \(fmt(Double(t.interiorDeviationTicks) * t.msPerTick, 3)) ms"
                   + " = \(fmt(t.interiorJitterPercent, 2)) %")
        lines.append("             uvnitř stopy, z \(t.interiorSampleCount) vzorků"
                   + " — bez okrajů a bez zahozených snímků")
        lines.append("             se vším dohromady by vyšlo \(t.maxDeviationTicks) t"
                   + " = \(fmt(t.maxDeviationPercent, 2)) %")

        // Okraje se z kolísání vyjímají, ale nesmí zmizet — tady je jejich řádek.
        if t.edges.isEmpty {
            lines.append("  Okraje     stopa je kratší než 3 vzorky, okraje se nevyjímaly")
        } else {
            let parts = t.edges.map { edge -> String in
                let detail = "\(edge.tick) t = \(fmt(t.milliseconds(edge.tick), 3)) ms"
                            + ", \(fmt(edge.ratioToMode, 3))× modu"
                return edge.isAnomalous
                    ? "\(edge.position) vzorek [\(edge.index)] \(detail) ⚠"
                    : "\(edge.position) vzorek [\(edge.index)] přesně na modu"
            }
            lines.append("  Okraje     \(parts[0])")
            for part in parts.dropFirst() {
                lines.append("             \(part)")
            }
            if !t.anomalousEdges.isEmpty {
                lines.append("             Vyjmuté z kolísání výše, ne zahozené — krajní vzorek bývá")
                lines.append("             useknutý a nafoukl by číslo o řád.")
            }
        }

        if !t.irregularIndices.isEmpty {
            lines.append("             nepravidelné vzorky na indexech: \(indexList(t.irregularIndices))")
        }
        return lines
    }

    private static func audioLines(_ a: AudioTrackInfo) -> [String] {
        var lines: [String] = []
        lines.append("  Zvuk       \(a.codec) (\(a.codecFourCC))"
                   + ", \(a.channels) kanál(ů)"
                   + ", \(fmt(a.sampleRate, 0)) Hz")
        lines.append(contentsOf: editListLines(a.editList, label: "Edit list z"))
        return lines
    }

    private static func editListLines(_ list: EditListInfo, label: String) -> [String] {
        var lines: [String] = []
        let padded = label.padding(toLength: max(label.count, 10), withPad: " ", startingAt: 0)

        if list.isIdentity {
            lines.append("  \(padded) 1 segment, mapování 1:1 bez posunu — nic nepřeškálovává")
            return lines
        }
        if list.segments.isEmpty {
            lines.append("  \(padded) ⚠ stopa nehlásí žádný segment")
            return lines
        }

        lines.append("  \(padded) ⚠ \(list.segments.count) segment(ů), mapování NENÍ triviální:")
        for seg in list.segments {
            if seg.isEmpty {
                lines.append("             [\(seg.index)] prázdný segment (edit bez média)"
                           + " target \(timeString(seg.mapping.target.start))"
                           + " + \(timeString(seg.mapping.target.duration))")
                continue
            }
            let rate = seg.rate.map { fmt($0, 4) } ?? "?"
            lines.append("             [\(seg.index)] source \(timeString(seg.mapping.source.start))"
                       + " + \(timeString(seg.mapping.source.duration))"
                       + "  →  target \(timeString(seg.mapping.target.start))"
                       + " + \(timeString(seg.mapping.target.duration))"
                       + "  rate \(rate)×")
        }
        if let rate = list.overallRate, abs(rate - 1.0) > 1e-6 {
            let direction = rate > 1 ? "zpomaluje" : "zrychluje"
            lines.append("             → edit list \(direction) obraz \(fmt(rate, 4))×."
                       + " Tohle je přesně ten CMTimeMapping, na kterém stojí speed ramping.")
        }
        return lines
    }

    // MARK: - Závěr

    /// Souhrn přes celou dávku. Sdílený konzolí i RESULTS.md, ať se nerozejdou.
    static func conclusion(_ reports: [ClipReport]) -> [String] {
        var lines: [String] = []
        lines.append("Souborů celkem: \(reports.count)")

        let vfr = reports.filter {
            if case .variable = $0.video?.timing?.verdict { return true }
            return false
        }
        lines.append("Skutečně proměnlivé časování (VFR): \(vfr.count) z \(reports.count)"
                   + (vfr.isEmpty ? "" : " — \(vfr.map(\.name).joined(separator: ", "))"))

        // Klipy, kde je časování pod zahozenými snímky konstantní. Ty se opraví levně.
        let recoverable = reports.filter { report in
            guard let verdict = report.video?.timing?.verdict else { return false }
            guard verdict.isConstantUnderneath else { return false }
            return (report.video?.timing?.droppedFrames ?? 0) > 0
        }
        if !recoverable.isEmpty {
            lines.append("Konstantní se zahozenými snímky: \(recoverable.count)"
                       + " — \(recoverable.map(\.name).joined(separator: ", "))")
            lines.append("  Tyhle stačí doplnit duplikáty, časování se přepočítávat nemusí.")
        }

        let totalDropped = reports.compactMap { $0.video?.timing?.droppedFrames }.reduce(0, +)
        lines.append("Zahozených snímků celkem: \(totalDropped)")

        let editedVideo = reports.filter { $0.video.map { !$0.editList.isIdentity } ?? false }
        let editedAudio = reports.filter { $0.audio.map { !$0.editList.isIdentity } ?? false }
        lines.append("Netriviální edit list na obraze: \(editedVideo.count)"
                   + (editedVideo.isEmpty ? "" : " — \(editedVideo.map(\.name).joined(separator: ", "))"))
        lines.append("Netriviální edit list na zvuku: \(editedAudio.count)"
                   + (editedAudio.isEmpty ? "" : " — \(editedAudio.map(\.name).joined(separator: ", "))"))

        // Retiming (slow-mo zapsané jako edit list) je jiná kategorie než pouhý posun.
        let retimed = reports.filter { report in
            guard let rate = report.video?.editList.overallRate else { return false }
            return abs(rate - 1.0) > 1e-6
        }
        if retimed.isEmpty {
            lines.append("Přeškálování rychlosti edit listem: 0 — žádný klip nenese slow-mo"
                       + " zapsané jako edit list nad vysokorychlostní stopou.")
        } else {
            for report in retimed {
                let rate = report.video?.editList.overallRate ?? 1
                lines.append("⚠ \(report.name): edit list mění rychlost \(fmt(rate, 4))×."
                           + " Syrové délky vzorků NEodpovídají tomu, co divák uvidí.")
            }
        }

        // Posun začátku zvuku proti obrazu — klasický zdroj rozjetého synchronu.
        var offsets: [String] = []
        for report in reports {
            guard let audio = report.audio else { continue }
            let source = audio.editList.sourceStartOffset
            let target = audio.editList.targetStartOffset
            var parts: [String] = []
            if let source, source.isValid, source.seconds > 0 {
                parts.append("prvních \(fmt(source.seconds * 1000, 1)) ms zdroje se zahazuje")
            }
            if let target, target.isValid, target.seconds > 0 {
                parts.append("zvuk začíná až v \(fmt(target.seconds * 1000, 1)) ms stopy")
            }
            if !parts.isEmpty {
                offsets.append("\(report.name): \(parts.joined(separator: ", "))")
            }
        }
        if !offsets.isEmpty {
            lines.append("")
            lines.append("Posun zvuku podle edit listu (\(offsets.count) z \(reports.count) klipů):")
            for offset in offsets { lines.append("  · \(offset)") }
            lines.append("Tohle je priming AAC kodéru. Kdo edit list ignoruje a čte syrové vzorky,")
            lines.append("dostane zvuk posunutý o tenhle offset — a bude ho hledat jinde.")
        }

        return lines
    }

    // MARK: - Pomocné formátování

    /// Desetinná čárka, ne tečka. Deterministické, bez závislosti na locale stroje.
    static func fmt(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func timeString(_ time: CMTime) -> String {
        guard time.isValid, !time.isIndefinite, time.seconds.isFinite else { return "—" }
        let total = time.seconds
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return "\(minutes):" + String(format: "%06.3f", seconds).replacingOccurrences(of: ".", with: ",")
    }

    /// Zkrácený výpis indexů, ať se dlouhý seznam nerozteče přes celý terminál.
    static func indexList(_ indices: [Int]) -> String {
        let shown = indices.prefix(8).map(String.init).joined(separator: ", ")
        return indices.count > 8 ? "\(shown), … +\(indices.count - 8)" : shown
    }

    // MARK: - Vykreslení tabulky

    static func asciiTable(header: [String], rows: [[String]]) -> [String] {
        guard !rows.isEmpty else { return ["(žádné soubory)"] }
        let widths = header.indices.map { column in
            max(header[column].count, rows.map { $0[column].count }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            cells.indices
                .map { pad(cells[$0], widths[$0]) }
                .joined(separator: "  ")
        }
        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ")
        return [line(header), separator] + rows.map(line)
    }

    static func markdownTable(header: [String], rows: [[String]]) -> [String] {
        guard !rows.isEmpty else { return ["_(žádné soubory)_"] }
        var out = ["| " + header.joined(separator: " | ") + " |"]
        out.append("|" + String(repeating: "---|", count: header.count))
        for row in rows {
            out.append("| " + row.joined(separator: " | ") + " |")
        }
        return out
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
