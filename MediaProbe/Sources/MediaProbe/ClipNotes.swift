//
//  ClipNotes.swift
//  Projekt Krása / MediaProbe
//
//  Načtení ručně psaných poznámek z CLIPS.txt. Názvy klipů jsou časová
//  razítka, ze kterých po týdnu nikdo nepozná, co na nich je — a obsah
//  záběru z metadat vyčíst nejde.
//
//  RESULTS.md je generovaný, takže poznámky musí přijít odjinud, jinak
//  je příští běh přepíše.
//

import Foundation

struct ClipNotes {
    private let notes: [String: String]

    static let empty = ClipNotes(notes: [:])

    subscript(fileName: String) -> String? {
        notes[fileName]
    }

    var isEmpty: Bool { notes.isEmpty }

    /// Načte `nazev = poznámka` řádky. Prázdné řádky a `#` komentáře ignoruje.
    static func load(from url: URL) -> ClipNotes {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .empty }

        var notes: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }

            let name = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            let note = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !note.isEmpty else { continue }
            notes[name] = note
        }
        return ClipNotes(notes: notes)
    }
}
