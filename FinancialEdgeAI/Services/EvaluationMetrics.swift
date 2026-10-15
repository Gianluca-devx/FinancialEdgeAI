//
//  EvaluationMetrics.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// How a model answer is judged. Pure functions, so every rule is covered by a unit test and the
/// same rules apply to the baseline and to any later model.
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

    /// Outcome per key. Without a readable answer every key is `unparsed`.
    static func compare(expected: FinancialMetrics, actual: FinancialMetrics?) -> [String: FieldOutcome] {
        var outcomes: [String: FieldOutcome] = [:]
        for key in FinancialMetrics.keys {
            if let actual {
                outcomes[key] = compare(expected: expected.value(forKey: key), actual: actual.value(forKey: key))
            } else {
                outcomes[key] = .unparsed
            }
        }
        return outcomes
    }

    /// Judges one model answer (or one failed generation).
    static func makeRecord(
        example: ExtractionExample,
        run: Int,
        seed: UInt64,
        generation: GenerationResult?,
        generationError: String?,
        thermalBefore: Int,
        thermalAfter: Int
    ) -> EvaluationRecord {
        let outcome = generation.map { MetricsParser.parse($0.text) }
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
            fields: compare(expected: example.expected, actual: outcome?.metrics),
            thermalBefore: thermalBefore,
            thermalAfter: thermalAfter
        )
    }

    private static func describe(_ failure: ParseFailure) -> String {
        switch failure {
        case .noJSON: "noJSON"
        case .invalidJSON: "invalidJSON"
        case .wrongSchema(let problem): "wrongSchema: \(problem)"
        }
    }

    // MARK: - Many answers

    static func summarize(_ records: [EvaluationRecord]) -> EvaluationSummary {
        var outcomes: [String: [String: Int]] = [:]
        for key in FinancialMetrics.keys {
            outcomes[key] = Dictionary(uniqueKeysWithValues: FieldOutcome.allCases.map { ($0.rawValue, 0) })
        }
        for record in records {
            for (key, outcome) in record.fields {
                outcomes[key, default: [:]][outcome.rawValue, default: 0] += 1
            }
        }
        let correctFields = outcomes.values.reduce(0) { $0 + ($1[FieldOutcome.correct.rawValue] ?? 0) }
        let totalFields = records.count * FinancialMetrics.keys.count
        let generations = records.compactMap(\.generation)

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
            medianTotalTime: median(generations.map(\.totalTime)),
            medianFirstTokenTime: median(generations.map(\.promptTime)),
            medianTokensPerSecond: median(generations.map(\.tokensPerSecond)),
            peakMemory: generations.map(\.peakMemory).max() ?? 0,
            maxThermalState: records.flatMap { [$0.thermalBefore, $0.thermalAfter] }.max() ?? 0
        )
    }

    static func summarize(_ records: [EvaluationRecord], groupedBy key: (EvaluationRecord) -> String)
        -> [String: EvaluationSummary]
    {
        Dictionary(grouping: records, by: key).mapValues(summarize)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
