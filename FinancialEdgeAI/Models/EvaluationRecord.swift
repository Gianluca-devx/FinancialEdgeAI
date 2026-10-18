//
//  EvaluationRecord.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// How one returned value compares with the expected one.
enum FieldOutcome: String, Codable, Sendable, CaseIterable {
    /// Same value (within the tolerance), or both null.
    case correct
    /// A value was expected to be null, and the model invented one.
    case hallucinated
    /// A value was expected, and the model returned null.
    case missed
    /// Same size, opposite sign.
    case signError
    /// Off by a factor of 1000 (millions against billions).
    case unitError
    /// Any other wrong number.
    case wrongValue
    /// The model returned a string that the parser cannot read as a number.
    case unreadable
    /// The answer could not be read, so there is no value to compare.
    case unparsed
}

/// Everything recorded about one statement in one run.
struct EvaluationRecord: Codable, Sendable {
    let exampleID: Int
    let scenario: String
    let pool: String
    /// 1, 2, 3...
    let run: Int
    let seed: UInt64

    /// Nil if the generation itself failed.
    let generation: GenerationResult?
    let generationError: String?

    let isValidJSON: Bool
    let isSchemaValid: Bool
    let hadFence: Bool
    let hadThinking: Bool
    /// Why the answer could not be read, if it could not.
    let parseFailure: String?
    /// What the model returned (the strings) and the numbers read from them.
    let extracted: FinancialMetrics?
    /// The labels of the dataset: the printed strings and the true numbers.
    let expected: FinancialMetrics

    /// Outcome per core key of the schema.
    let fields: [String: FieldOutcome]
    /// For the keys where the model and the label both have a string: whether the model copied the
    /// label's string exactly. A diagnostic: the fields are judged on the numbers.
    let exactCopies: [String: Bool]

    /// `ProcessInfo.ThermalState` raw values: 0 nominal, 1 fair, 2 serious, 3 critical.
    let thermalBefore: Int
    let thermalAfter: Int

    var isFullyCorrect: Bool {
        !fields.isEmpty && fields.values.allSatisfy { $0 == .correct }
    }
}

/// Counts and rates over a set of records.
struct EvaluationSummary: Codable, Sendable {
    let records: Int
    let generationFailures: Int
    let validJSON: Int
    let schemaValid: Int
    let fenced: Int
    let thinking: Int
    /// Records where every core field is correct.
    let fullyCorrect: Int
    /// Outcome counts per key.
    let fieldOutcomes: [String: [String: Int]]
    /// Share of correct fields over all core keys and all records.
    let fieldAccuracy: Double
    /// Strings copied exactly like the label, and how many strings could be compared.
    let exactCopies: Int
    let exactCopiesComparable: Int

    let medianTotalTime: Double
    let medianFirstTokenTime: Double
    let medianTokensPerSecond: Double
    /// Highest MLX peak memory seen, in bytes.
    let peakMemory: Int
    let maxThermalState: Int

    func rate(_ count: Int) -> Double {
        records == 0 ? 0 : Double(count) / Double(records)
    }
}

/// A whole evaluation: what was run, on what, and what came out.
struct EvaluationReport: Codable, Sendable {
    struct Metadata: Codable, Sendable {
        let date: String
        let model: String
        let device: String
        let system: String
        let temperature: Double
        let maxTokens: Int
        let runs: Int
        let seeds: [UInt64]
        let examples: Int
        /// SHA-256 of the system prompt and the prompt template, of the test split with its labels,
        /// and of the schema.
        let promptHash: String
        let testSetHash: String
        let schemaHash: String
        /// "core" or "extended": which call was evaluated. (Reports of v2.0.0 have `coreKeys` instead.)
        let tier: String
        /// The keys that were asked and judged, in order.
        let keys: [String]
        /// The LoRA adapter that was on the model during the run, with the hashes of its files; nil for the
        /// base model (the key is then absent from the report).
        let adapter: AdapterInfo?
        /// Seconds the model took to load (the first load includes the download).
        let modelLoadSeconds: Double?
        /// Which statements were run: "test" (the frozen test split), "test2" or the name of an external set.
        /// Reports written before Phase 2b do not have it: they are the test split.
        var evaluationSet: String? = nil
    }

    let metadata: Metadata
    let summary: EvaluationSummary
    let byScenario: [String: EvaluationSummary]
    let byPool: [String: EvaluationSummary]
    let records: [EvaluationRecord]
}
