//
//  Derivations.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation

/// The formulas of the derived values in `Dataset/schema.json`. The model never writes these.
///
/// The schema says which fields each derived value reads; the formula lives here, so a formula
/// is plain code that a unit test covers. A value is `nil` if an input is missing, a divisor is
/// zero, or the result is not a finite number.
nonisolated enum Derivations {

    /// Formula per derived key. The inputs arrive in the order of `DerivedSpec.inputs`.
    private static let formulas: [String: @Sendable ([Double]) -> Double?] = [
        "revenueGrowthDerived": percentChange,
        "netIncomeGrowthDerived": percentChange,
        "epsGrowthDerived": percentChange,
        "operatingMargin": percentOf,
        "netMargin": percentOf,
        "freeCashFlow": difference,
        "interestCoverage": ratio,
        "roe": percentOf,
        "debtToEquity": ratio,
        "currentRatio": ratio,
        "netDebt": difference,
    ]

    /// The derived keys that have a formula. A test checks it is the list of the schema.
    static var formulaKeys: Set<String> { Set(formulas.keys) }

    /// One derived value, from the numbers extracted so far (a missing key is a missing value).
    static func value(for spec: DerivedSpec, extracted: [String: Double]) -> Double? {
        let inputs = spec.inputs.compactMap { extracted[$0] }
        guard inputs.count == spec.inputs.count, let formula = formulas[spec.key],
              let result = formula(inputs), result.isFinite
        else { return nil }
        return result
    }

    /// Every derived value that can be calculated, by derived key.
    static func values(in schema: Schema, extracted: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for spec in schema.derived {
            if let value = value(for: spec, extracted: extracted) { result[spec.key] = value }
        }
        return result
    }

    /// The extracted fields the text did not print, filled in by code: the printed value always wins.
    static func filledFields(in schema: Schema, extracted: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for spec in schema.derived {
            guard let target = spec.fills, extracted[target] == nil,
                  let value = value(for: spec, extracted: extracted)
            else { continue }
            result[target] = value
        }
        return result
    }

    // MARK: - Formulas

    /// (current - previous) / |previous| x 100. Inputs: current, previous.
    private static func percentChange(_ values: [Double]) -> Double? {
        values[1] == 0 ? nil : (values[0] - values[1]) / abs(values[1]) * 100
    }

    /// a / b x 100. Inputs: a, b.
    private static func percentOf(_ values: [Double]) -> Double? {
        values[1] == 0 ? nil : values[0] / values[1] * 100
    }

    /// a / b. Inputs: a, b.
    private static func ratio(_ values: [Double]) -> Double? {
        values[1] == 0 ? nil : values[0] / values[1]
    }

    /// a - b. Inputs: a, b.
    private static func difference(_ values: [Double]) -> Double? {
        values[0] - values[1]
    }
}
