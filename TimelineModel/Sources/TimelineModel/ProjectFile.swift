//
//  ProjectFile.swift
//  TimelineModel — Projekt Krása
//
//  Obálka souboru `.projektkrasa` (fáze 5). Obsah je JSON: verze formátu,
//  metadata a projekt v jeho VLASTNÍ Codable podobě — celé ticky a snímky,
//  ne sekundy s plovoucí čárkou, a uzly rychlostních křivek kotvené ve
//  zdrojovém čase. Specifikace 6.2 kreslí schéma se sekundami; tam, kde se
//  rozchází s pozdějšími rozhodnutími (přesnost časů, kotvení uzlů), platí
//  rozhodnutí — spec je starší než plán.
//
//  Zápis je deterministický (`sortedKeys`): stejný projekt = stejné bajty.
//  Bez toho by se nedalo poznat, jestli se soubor opravdu změnil, a diff
//  dvou verzí projektu by byl šum.
//

import Foundation

public enum ProjectFileError: Error, Equatable, CustomStringConvertible {
    /// Soubor je z novější verze aplikace. Nečíst — tichá ztráta dat
    /// z neznámých polí je horší než odmítnutí.
    case unsupportedVersion(found: Int, supported: Int)
    case corrupted(String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let found, let supported):
            return "Soubor je z novější verze aplikace (formát \(found), tahle umí \(supported))."
        case .corrupted(let detail):
            return "Soubor se nepodařilo přečíst: \(detail)"
        }
    }
}

/// Obsah souboru `.projektkrasa`.
public struct ProjectFile: Codable, Equatable, Sendable {

    /// Zvyšovat při každé změně formátu, která starší aplikaci znemožní
    /// soubor přečíst. Doplnění volitelného pole verzi nezvedá.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var project: Project

    public init(project: Project,
                name: String,
                createdAt: Date = Date(),
                modifiedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.project = project
    }

    // MARK: Zápis a čtení

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProjectFile {
        // Nejdřív jen verze — celý soubor se čte až po jejím schválení,
        // jinak by novější formát spadl na nesrozumitelné dekódovací chybě
        // místo jasného „soubor je z novější verze".
        struct VersionProbe: Codable { let formatVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).formatVersion
        } catch {
            throw ProjectFileError.corrupted("chybí verze formátu (\(error.localizedDescription))")
        }
        guard version <= currentFormatVersion else {
            throw ProjectFileError.unsupportedVersion(found: version,
                                                      supported: currentFormatVersion)
        }

        do {
            return try decoder.decode(ProjectFile.self, from: data)
        } catch {
            throw ProjectFileError.corrupted(String(describing: error))
        }
    }
}
