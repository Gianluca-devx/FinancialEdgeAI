//
//  Schema.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation

nonisolated enum FieldTier: String, Codable, Sendable {
    /// Returned in every answer.
    case core
    /// Returned only when the user asks for it (a second call).
    case extended
}

nonisolated enum FieldKind: String, Codable, Sendable {
    /// Money, in billions of USD once parsed.
    case amount
    /// A percentage, without the "%".
    case percent
    /// USD per share.
    case perShare
    /// A plain ratio. Only derived values use it.
    case ratio
}

/// One value the model must copy from the text.
nonisolated struct FieldSpec: Codable, Equatable, Sendable, Identifiable {
    let key: String
    let tier: FieldTier
    let kind: FieldKind
    /// If true the value is stored as a positive magnitude, whatever sign is printed
    /// (an expense is written as a negative number in some reports).
    let magnitude: Bool?
    let label: String
    /// The words of the prompt that define the field.
    let description: String

    var id: String { key }
    var isMagnitude: Bool { magnitude ?? false }
}

/// One value that code calculates from extracted fields. The model never writes it.
nonisolated struct DerivedSpec: Codable, Equatable, Sendable, Identifiable {
    let key: String
    let kind: FieldKind
    let label: String
    /// Keys of the extracted fields the formula reads.
    let inputs: [String]
    /// If set, this value fills in that extracted field when the text did not print it.
    let fills: String?

    var id: String { key }
}

nonisolated enum SchemaError: Error, Equatable, LocalizedError {
    case malformed(String)
    case unsupportedVersion(Int)
    case noCoreFields
    case duplicateKey(String)
    case unknownInput(derived: String, input: String)
    case badFill(derived: String, target: String)

    var errorDescription: String? {
        switch self {
        case .malformed(let reason): "The schema is not readable: \(reason)"
        case .unsupportedVersion(let version): "The schema version \(version) is not supported."
        case .noCoreFields: "The schema has no core field."
        case .duplicateKey(let key): "The key \(key) is used twice in the schema."
        case .unknownInput(let derived, let input): "\(derived) reads \(input), which is not an extracted field."
        case .badFill(let derived, let target): "\(derived) cannot fill \(target): it must be an extracted field of the same kind."
        }
    }
}

/// The only list of fields. The prompt, the parser, the evaluation and the UI read it, so a field
/// can be added in `Dataset/schema.json` without touching the code that loops over the fields.
/// The app bundles a copy and `Scripts/validate_dataset.py` fails if the copy differs.
nonisolated struct Schema: Equatable, Sendable {
    static let supportedVersion = 1

    let fields: [FieldSpec]
    let derived: [DerivedSpec]

    /// Pure and testable: no bundle access.
    init(data: Data) throws {
        struct Raw: Decodable {
            let version: Int
            let fields: [FieldSpec]
            let derived: [DerivedSpec]
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw SchemaError.malformed(error.localizedDescription)
        }
        guard raw.version == Schema.supportedVersion else { throw SchemaError.unsupportedVersion(raw.version) }
        guard raw.fields.contains(where: { $0.tier == .core }) else { throw SchemaError.noCoreFields }

        var seen = Set<String>()
        for key in raw.fields.map(\.key) + raw.derived.map(\.key) {
            guard seen.insert(key).inserted else { throw SchemaError.duplicateKey(key) }
        }
        let byKey = Dictionary(uniqueKeysWithValues: raw.fields.map { ($0.key, $0) })
        for item in raw.derived {
            for input in item.inputs where byKey[input] == nil {
                throw SchemaError.unknownInput(derived: item.key, input: input)
            }
            if let target = item.fills, byKey[target]?.kind != item.kind {
                throw SchemaError.badFill(derived: item.key, target: target)
            }
        }
        fields = raw.fields
        derived = raw.derived
    }

    var coreFields: [FieldSpec] { fields.filter { $0.tier == .core } }
    var extendedFields: [FieldSpec] { fields.filter { $0.tier == .extended } }
    var coreKeys: [String] { coreFields.map(\.key) }
    var extendedKeys: [String] { extendedFields.map(\.key) }

    func field(_ key: String) -> FieldSpec? {
        fields.first { $0.key == key }
    }
}
