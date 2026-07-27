//
//  UndoStack.swift
//  TimelineModel — Projekt Krása
//
//  Snapshot stack, ne command pattern. `Project` je hodnotový typ, takže
//  snapshot je prostě jeho kopie a nemá vlastní kód, který by mohl mít chybu.
//  Command pattern by dával smysl u dat, která se nedají levně kopírovat;
//  tady by jen přidal místo, kde se dá udělat chyba.
//
//  ⚠️ Snímkuje se CELÝ projekt, ne jen timeline. Jinak: naimportuješ klip
//  a vložíš ho (přibude asset i klip), undo smaže klip a asset zůstane;
//  po redo se vrátí klip odkazující na asset, který se mezitím odstranil —
//  porušený invariant cestou, kterou žádná operace nehlídá.
//

import Foundation

public struct UndoStack: Sendable {
    private var past: [Project] = []
    private var future: [Project] = []
    /// Stav před začátkem interakce (tažení trimu nebo rollu).
    private var interactionBase: Project?

    public var limit: Int

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }
    public var isInteracting: Bool { interactionBase != nil }

    /// Zapíše stav PŘED chystanou změnou.
    public mutating func record(_ project: Project) {
        guard interactionBase == nil else { return }   // uvnitř interakce se nezapisuje
        past.append(project)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    public mutating func undo(current: Project) -> Project? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: Project) -> Project? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    // MARK: Interakce

    /// Začátek tažení trimu nebo rollu, kde jsou mezistavy legální a chodí
    /// desítky za sekundu. Zapíše se jeden snapshot na začátku.
    ///
    /// Pro přetahování klipu se tohle NEPOUŽÍVÁ — tam drží náhled UI ve
    /// vlastním stavu a do modelu se zapíše až výsledek, protože každý
    /// mezistav přes souseda by byl překryv, tedy chyba.
    public mutating func beginInteraction(_ project: Project) {
        guard interactionBase == nil else { return }   // nespárované volání nesmí rozbít zásobník
        interactionBase = project
    }

    /// Konec tažení. **Když se nic nezměnilo, undo krok nevznikne** — jinak
    /// by Cmd+Z dvakrát nic neudělalo a vypadalo by to jako zamrznutí.
    public mutating func endInteraction(_ project: Project) {
        guard let base = interactionBase else { return }
        interactionBase = nil
        guard base != project else { return }
        past.append(base)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    /// Zrušené tažení — vrací stav před jeho začátkem.
    public mutating func cancelInteraction() -> Project? {
        defer { interactionBase = nil }
        return interactionBase
    }
}
