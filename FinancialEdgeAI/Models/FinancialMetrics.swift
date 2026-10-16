//
//  FinancialMetrics.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import Foundation

/// What the model returned for one statement, keyed by the field keys of the schema.
///
/// The model copies each value from the text as a string (`texts`); code reads the number from it
/// (`values`). A field the model answered with null has neither. A text the parser cannot read has a
/// text and no value: it is flagged, never guessed.
nonisolated struct FinancialMetrics: Codable, Equatable, Sendable {
    /// The string the model copied, by key. A null answer is absent.
    let texts: [String: String]
    /// The number read from each text, by key. A text that cannot be read is absent.
    let values: [String: Double]

    /// From what the model returned: `ValueParser` reads each number, with the sign rule of its field.
    init(texts: [String: String], schema: Schema) {
        var values: [String: Double] = [:]
        for (key, text) in texts {
            guard let field = schema.field(key), let value = ValueParser.parse(text, field: field) else { continue }
            values[key] = value
        }
        self.texts = texts
        self.values = values
    }

    /// From known values, as in the labels of the dataset: nothing is parsed.
    init(texts: [String: String], values: [String: Double]) {
        self.texts = texts
        self.values = values
    }

    func text(forKey key: String) -> String? { texts[key] }

    func value(forKey key: String) -> Double? { values[key] }

    /// Keys, in schema order, whose text is there but could not be read as a number.
    func unreadableKeys(in schema: Schema) -> [String] {
        schema.fields.map(\.key).filter { texts[$0] != nil && values[$0] == nil }
    }

    /// The extracted numbers together with what code adds: growths the text did not print, and the
    /// derived values.
    func resolved(in schema: Schema) -> ResolvedMetrics {
        ResolvedMetrics(
            filled: Derivations.filledFields(in: schema, extracted: values),
            derived: Derivations.values(in: schema, extracted: values))
    }
}

/// What code calculated from the extracted numbers. The model never writes these.
nonisolated struct ResolvedMetrics: Equatable, Sendable {
    /// Growth fields the text did not print, filled in by code, by field key.
    let filled: [String: Double]
    /// Every derived value that could be calculated, by derived key.
    let derived: [String: Double]
}
