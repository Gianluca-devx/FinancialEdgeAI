//
//  EvaluationMetrics.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// How a model answer is judged. Pure functions, so every rule is covered by a unit test and the
/// same rules apply to the baseline and to any later model.
///
/// The fields are judged on the numbers: the number read from the model's string against the true
/// number of the label. Whether the string was copied exactly is recorded as a diagnostic.
enum EvaluationMetrics {

    /// Two numbers closer than this are the same value.
    static let tolerance = 0.001

    // MARK: - One value

    static func compare(expected: Double?, actual: Double?) -> FieldOutcome {
        switch (expected, actual) {
        case (nil, nil):
            return .correct
        case (nil, _?):
            return .hallucinated
        case (_?, nil):
            return .missed
        case let (expected?, actual?):
            if abs(actual - expected) <= tolerance { return .correct }
            if abs(actual + expected) <= tolerance { return .signError }
            if isScaled(actual, from: expected) { return .unitError }
            return .wrongValue
        }
    }

    /// The same number written in millions instead of billions, or the other way round.
    private static func isScaled(_ actual: Double, from expected: Double) -> Bool {
        guard expected != 0 else { return false }
        return [1000.0, 0.001].contains { factor in
            let target = expected * factor
            return abs(actual - target) <= max(tolerance, abs(target) * 1e-6)
        }
    }

    // MARK: - One answer

    /// Outcome per core key. Without a readable answer every key is `unparsed`. A string the parser
    /// cannot read is `unreadable`, whatever was expected.
    static func compare(expected: FinancialMetrics, actual: FinancialMetrics?, schema: Schema)
        -> [String: FieldOutcome]
    {
        var outcomes: [String: FieldOutcome] = [:]
        for key in schema.coreKeys {
            guard let actual else {
                outcomes[key] = .unparsed
                continue
            }
            if actual.text(forKey: key) != nil, actual.value(forKey: key) == nil {
                outcomes[key] = .unreadable
            } else {
                outcomes[key] = compare(expected: expected.value(forKey: key), actual: actual.value(forKey: key))
            }
        }
        return outcomes
    }

    /// For the keys where the model and the label both have a string: was it copied exactly?
    static func exactCopies(expected: FinancialMetrics, actual: FinancialMetrics?, schema: Schema) -> [String: Bool] {
        guard let actual else { return [:] }
        var copies: [String: Bool] = [:]
        for key in schema.coreKeys {
            if let given = actual.text(forKey: key), let wanted = expected.text(forKey: key) {
                copies[key] = given == wanted
            }
        }
        return copies
    }

    /// Judges one model answer (or one failed generation).
    static func makeRecord(
        example: ExtractionExample,
        run: Int,
        seed: UInt64,
        generation: GenerationResult?,
        generationError: String?,
        thermalBefore: Int,
        thermalAfter: Int,
        schema: Schema
    ) -> EvaluationRecord {
        let outcome = generation.map { MetricsParser.parse($0.text, schema: schema) }
        return EvaluationRecord(
            exampleID: example.id,
            scenario: example.scenario,
            pool: example.pool,
            run: run,
            seed: seed,
            generation: generation,
            generationError: generationError,
            isValidJSON: outcome?.isValidJSON ?? false,
            isSchemaValid: outcome?.isSchemaValid ?? false,
            hadFence: outcome?.hadFence ?? false,
            hadThinking: outcome?.hadThinking ?? false,
            parseFailure: outcome?.failure.map(describe),
            extracted: outcome?.metrics,
            expected: example.expected,
            fields: compare(expected: example.expected, actual: outcome?.metrics, schema: schema),
            exactCopies: exactCopies(expected: example.expected, actual: outcome?.metrics, schema: schema),
            thermalBefore: thermalBefore,
            thermalAfter: thermalAfter
        )
    }

    private nonisolated static func describe(_ failure: ParseFailure) -> String {
        switch failure {
        case .noJSON: "noJSON"
        case .invalidJSON: "invalidJSON"
        case .wrongSchema(let problem): "wrongSchema: \(problem)"
        }
    }

    // MARK: - Many answers

    static func summarize(_ records: [EvaluationRecord], schema: Schema) -> EvaluationSummary {
        var outcomes: [String: [String: Int]] = [:]
        for key in schema.coreKeys {
            outcomes[key] = Dictionary(uniqueKeysWithValues: FieldOutcome.allCases.map { ($0.rawValue, 0) })
        }
        for record in records {
            for (key, outcome) in record.fields {
                outcomes[key, default: [:]][outcome.rawValue, default: 0] += 1
            }
        }
        let correctFields = outcomes.values.reduce(0) { $0 + ($1[FieldOutcome.correct.rawValue] ?? 0) }
        let totalFields = records.count * schema.coreKeys.count
        let generations = records.compactMap(\.generation)
        let copies = records.flatMap { $0.exactCopies.values }

        return EvaluationSummary(
            records: records.count,
            generationFailures: records.filter { $0.generation == nil }.count,
            validJSON: records.filter(\.isValidJSON).count,
            schemaValid: records.filter(\.isSchemaValid).count,
            fenced: records.filter(\.hadFence).count,
            thinking: records.filter(\.hadThinking).count,
            fullyCorrect: records.filter(\.isFullyCorrect).count,
            fieldOutcomes: outcomes,
            fieldAccuracy: totalFields == 0 ? 0 : Double(correctFields) / Double(totalFields),
            exactCopies: copies.filter { $0 }.count,
            exactCopiesComparable: copies.count,
            medianTotalTime: median(generations.map(\.totalTime)),
            medianFirstTokenTime: median(generations.map(\.promptTime)),
            medianTokensPerSecond: median(generations.map(\.tokensPerSecond)),
            peakMemory: generations.map(\.peakMemory).max() ?? 0,
            maxThermalState: records.flatMap { [$0.thermalBefore, $0.thermalAfter] }.max() ?? 0
        )
    }

    static func summarize(
        _ records: [EvaluationRecord], schema: Schema, groupedBy key: (EvaluationRecord) -> String
    ) -> [String: EvaluationSummary] {
        Dictionary(grouping: records, by: key).mapValues { summarize($0, schema: schema) }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
