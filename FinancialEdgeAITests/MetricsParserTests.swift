//
//  MetricsParserTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation
import Testing

struct MetricsParserTests {

    /// The answer the model should give for `ExtractionPrompt.sampleStatement`.
    private static let sample = FinancialMetrics(
        revenue: 94, revenueGrowth: 12,
        operatingIncome: 25, operatingIncomeGrowth: 8,
        netIncome: 21, netIncomeGrowth: -4,
        previousYearNetIncome: 21.9
    )

    private static let sampleJSON = """
    {
    "revenue": 94,
    "revenueGrowth": 12,
    "operatingIncome": 25,
    "operatingIncomeGrowth": 8,
    "netIncome": 21,
    "netIncomeGrowth": -4,
    "previousYearNetIncome": 21.9
    }
    """

    // MARK: - Readable answers

    @Test func cleanJSON() {
        let outcome = MetricsParser.parse(Self.sampleJSON)
        #expect(outcome.metrics == Self.sample)
        #expect(outcome.failure == nil)
        #expect(outcome.isValidJSON)
        #expect(outcome.isSchemaValid)
        #expect(!outcome.hadFence)
        #expect(!outcome.hadThinking)
    }

    /// What the model really answered on the iPhone: a fence with the `json` label and
    /// `previousYearNetIncome` left null.
    @Test func fencedAnswerFromTheDevice() {
        let raw = """
        ```json
        {
        "revenue": 94,
        "revenueGrowth": 12,
        "operatingIncome": 25,
        "operatingIncomeGrowth": 8,
        "netIncome": 21,
        "netIncomeGrowth": -4,
        "previousYearNetIncome": null
        }
        """
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.hadFence)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics?.revenue == 94)
        #expect(outcome.metrics?.netIncomeGrowth == -4)
        #expect(outcome.metrics?.previousYearNetIncome == nil)
    }

    @Test func fenceWithClosingMarker() {
        let outcome = MetricsParser.parse("```json\n\(Self.sampleJSON)\n```")
        #expect(outcome.hadFence)
        #expect(outcome.metrics == Self.sample)
    }

    @Test func reasoningBlockBeforeTheAnswer() {
        let raw = "<think>\nThe revenue is 94 and { it grows } 12 percent.\n</think>\n\n\(Self.sampleJSON)"
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.hadThinking)
        #expect(outcome.metrics == Self.sample)
    }

    @Test func sentencesAroundTheJSON() {
        let raw = "Here is the extracted data:\n\(Self.sampleJSON)\nLet me know if you need more."
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.metrics == Self.sample)
        #expect(!outcome.hadFence)
    }

    @Test func allNullsIsAValidAnswer() {
        let raw = """
        {"revenue": null, "revenueGrowth": null, "operatingIncome": null,
         "operatingIncomeGrowth": null, "netIncome": null, "netIncomeGrowth": null,
         "previousYearNetIncome": null}
        """
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics == FinancialMetrics(
            revenue: nil, revenueGrowth: nil, operatingIncome: nil, operatingIncomeGrowth: nil,
            netIncome: nil, netIncomeGrowth: nil, previousYearNetIncome: nil))
    }

    @Test func numbersKeepTheirValueAndSign() {
        let outcome = MetricsParser.parse(Self.sampleJSON)
        #expect(outcome.metrics?.previousYearNetIncome == 21.9)
        #expect(outcome.metrics?.netIncomeGrowth == -4)
    }

    // MARK: - Answers that cannot be used

    @Test func noJSONAtAll() {
        let outcome = MetricsParser.parse("I am sorry, I cannot extract this information.")
        #expect(outcome.failure == .noJSON)
        #expect(!outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
    }

    @Test func emptyAnswer() {
        #expect(MetricsParser.parse("").failure == .noJSON)
    }

    @Test func answerCutOffBeforeTheClosingBrace() {
        let outcome = MetricsParser.parse("{\n\"revenue\": 94,\n\"revenueGrowth\": ")
        #expect(outcome.failure == .noJSON)
    }

    @Test func invalidJSON() {
        let outcome = MetricsParser.parse("{ revenue: 94 }")
        #expect(outcome.failure == .invalidJSON)
        #expect(!outcome.isValidJSON)
    }

    /// Foundation's JSON parsers (JSONDecoder and JSONSerialization) accept a trailing comma.
    /// "Valid JSON" in this project means "the app's own decoder can read it", so this counts
    /// as valid JSON. The schema check still fails here. Keep this in mind when reporting results.
    @Test func trailingCommaIsToleratedByFoundation() {
        let outcome = MetricsParser.parse("{\"revenue\": 94,}")
        #expect(outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
    }

    // MARK: - Valid JSON with the wrong schema

    @Test func missingKeyIsNotSilentlyNil() {
        // Swift would decode this as revenue = nil; the parser must reject it.
        let raw = """
        {"revenue": 94, "revenueGrowth": 12, "operatingIncome": 25, "operatingIncomeGrowth": 8,
         "netIncome": 21, "netIncomeGrowth": -4}
        """
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.contains("missing previousYearNetIncome"))
    }

    @Test func unexpectedKey() {
        let raw = Self.sampleJSON.replacingOccurrences(of: "}", with: ", \"currency\": \"USD\"}")
        let outcome = MetricsParser.parse(raw)
        #expect(outcome.isValidJSON)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.contains("unexpected currency"))
    }

    @Test func numberWrittenAsText() {
        let raw = Self.sampleJSON.replacingOccurrences(of: "\"revenue\": 94", with: "\"revenue\": \"94\"")
        let outcome = MetricsParser.parse(raw)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.contains("revenue"))
    }

    @Test func booleanInsteadOfNumber() {
        let raw = Self.sampleJSON.replacingOccurrences(of: "\"netIncome\": 21", with: "\"netIncome\": true")
        let outcome = MetricsParser.parse(raw)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.contains("netIncome"))
    }
}
