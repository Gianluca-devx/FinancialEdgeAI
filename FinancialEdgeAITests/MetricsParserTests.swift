//
//  MetricsParserTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation
import Testing

struct MetricsParserTests {

    private let schema: Schema

    init() throws {
        schema = try DatasetFiles.schema()
    }

    /// An answer with every core key. Keys not in `literals` are null; a literal is written as is,
    /// so `"\"$94 billion\""` is a string and `94` is a number.
    private func answer(_ literals: [String: String] = [:], extra: String = "") -> String {
        let lines = schema.coreKeys.map { "\"\($0)\": \(literals[$0] ?? "null")" }
        return "{\n" + lines.joined(separator: ",\n") + extra + "\n}"
    }

    private func string(_ text: String) -> String { "\"\(text)\"" }

    /// The answer the model should give for `ExtractionPrompt.sampleStatement`.
    private var sampleJSON: String {
        answer([
            "revenue": string("$94 billion"), "operatingIncome": string("$25 billion"),
            "netIncome": string("$21 billion"), "previousYearNetIncome": string("$21.9 billion"),
            "revenueGrowth": string("12%"), "netIncomeGrowth": string("-4%"),
        ])
    }

    // MARK: - Readable answers

    @Test func cleanJSON() {
        let outcome = MetricsParser.parse(sampleJSON, schema: schema)
        #expect(outcome.failure == nil)
        #expect(outcome.isValidJSON)
        #expect(outcome.isSchemaValid)
        #expect(!outcome.hadFence)
        #expect(!outcome.hadThinking)
        #expect(outcome.unreadableKeys.isEmpty)
        #expect(outcome.metrics?.texts["revenue"] == "$94 billion")
        #expect(outcome.metrics?.value(forKey: "revenue") == 94)
        #expect(outcome.metrics?.value(forKey: "operatingIncome") == 25)
        #expect(outcome.metrics?.value(forKey: "previousYearNetIncome") == 21.9)
        #expect(outcome.metrics?.value(forKey: "revenueGrowth") == 12)
        #expect(outcome.metrics?.value(forKey: "netIncomeGrowth") == -4)
        #expect(outcome.metrics?.value(forKey: "eps") == nil)
        #expect(outcome.metrics?.texts["eps"] == nil)
    }

    @Test func fencedAnswerFromTheDevice() {
        let outcome = MetricsParser.parse("```json\n\(sampleJSON)\n", schema: schema)
        #expect(outcome.hadFence)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics?.value(forKey: "revenue") == 94)
    }

    @Test func fenceWithClosingMarker() {
        let outcome = MetricsParser.parse("```json\n\(sampleJSON)\n```", schema: schema)
        #expect(outcome.hadFence)
        #expect(outcome.metrics?.value(forKey: "netIncomeGrowth") == -4)
    }

    @Test func reasoningBlockBeforeTheAnswer() {
        let raw = "<think>\nThe revenue is 94 and { it grows } 12 percent.\n</think>\n\n\(sampleJSON)"
        let outcome = MetricsParser.parse(raw, schema: schema)
        #expect(outcome.hadThinking)
        #expect(outcome.metrics?.value(forKey: "revenue") == 94)
    }

    @Test func sentencesAroundTheJSON() {
        let raw = "Here is the extracted data:\n\(sampleJSON)\nLet me know if you need more."
        let outcome = MetricsParser.parse(raw, schema: schema)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics?.value(forKey: "revenue") == 94)
        #expect(!outcome.hadFence)
    }

    @Test func allNullsIsAValidAnswer() {
        let outcome = MetricsParser.parse(answer(), schema: schema)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics == FinancialMetrics(texts: [:], values: [:]))
        #expect(outcome.unreadableKeys.isEmpty)
    }

    // MARK: - The strings are read by the ValueParser

    @Test func theUnitIsResolvedByCodeNotByTheModel() {
        let outcome = MetricsParser.parse(
            answer(["revenue": string("726 million"), "operatingIncome": string("$6.9bn"),
                    "netIncome": string("2,772 million")]),
            schema: schema)
        #expect(outcome.metrics?.value(forKey: "revenue") == 0.726)
        #expect(outcome.metrics?.value(forKey: "operatingIncome") == 6.9)
        #expect(outcome.metrics?.value(forKey: "netIncome") == 2.772)
    }

    @Test func aMagnitudeFieldIsStoredPositive() {
        let outcome = MetricsParser.parse(
            answer(["interestExpense": string("(1.2) billion"), "netIncome": string("(1.2) billion")]),
            schema: schema)
        #expect(outcome.metrics?.value(forKey: "interestExpense") == 1.2)
        #expect(outcome.metrics?.value(forKey: "netIncome") == -1.2)
    }

    @Test func aStringThatCannotBeReadIsFlaggedNotGuessed() {
        let outcome = MetricsParser.parse(
            answer(["revenue": string("about 5 billion"), "netIncome": string("$21 billion")]), schema: schema)
        #expect(outcome.isSchemaValid)
        #expect(outcome.unreadableKeys == ["revenue"])
        #expect(outcome.metrics?.texts["revenue"] == "about 5 billion")
        #expect(outcome.metrics?.value(forKey: "revenue") == nil)
        #expect(outcome.metrics?.value(forKey: "netIncome") == 21)
    }

    // MARK: - The extended call

    /// An answer of the extended call: every extended key, null unless a literal is given.
    private func extendedAnswer(_ literals: [String: String] = [:], extra: String = "") -> String {
        let lines = schema.extendedKeys.map { "\"\($0)\": \(literals[$0] ?? "null")" }
        return "{\n" + lines.joined(separator: ",\n") + extra + "\n}"
    }

    @Test func theExtendedAnswerHasTheExtendedKeys() {
        let outcome = MetricsParser.parse(
            extendedAnswer(["totalDebt": string("$12.5 billion"), "shareholdersEquity": string("30 billion dollars"),
                            "cash": string("$4,200 million")]),
            schema: schema, tier: .extended)
        #expect(outcome.isSchemaValid)
        #expect(outcome.metrics?.value(forKey: "totalDebt") == 12.5)
        #expect(outcome.metrics?.value(forKey: "shareholdersEquity") == 30)
        #expect(outcome.metrics?.value(forKey: "cash") == 4.2)
        #expect(outcome.metrics?.value(forKey: "currentAssets") == nil)
        #expect(outcome.unreadableKeys.isEmpty)
    }

    @Test func aCoreAnswerIsNotAnExtendedAnswer() {
        let outcome = MetricsParser.parse(sampleJSON, schema: schema, tier: .extended)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        // The message lists the missing keys, then the unexpected ones, each sorted.
        #expect(message.contains("missing cash, currentAssets, currentLiabilities, shareholdersEquity, totalDebt"))
        #expect(message.contains("unexpected capex, eps,"))
        #expect(message.contains("revenue"))
    }

    @Test func anExtendedAnswerIsNotACoreAnswer() {
        let outcome = MetricsParser.parse(extendedAnswer(), schema: schema, tier: .core)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.contains("unexpected cash, currentAssets, currentLiabilities, shareholdersEquity, totalDebt"))
    }

    @Test func anUnreadableExtendedStringIsFlagged() {
        let outcome = MetricsParser.parse(
            extendedAnswer(["cash": string("a lot"), "currentAssets": string("$9.8 billion")]),
            schema: schema, tier: .extended)
        #expect(outcome.unreadableKeys == ["cash"])
        #expect(outcome.metrics?.value(forKey: "currentAssets") == 9.8)
    }

    @Test func theAnswersOfTheTwoCallsCanBeMerged() throws {
        let core = try #require(MetricsParser.parse(sampleJSON, schema: schema).metrics)
        let extended = try #require(MetricsParser.parse(
            extendedAnswer(["totalDebt": string("$12.5 billion")]), schema: schema, tier: .extended).metrics)
        let both = core.merged(with: extended)
        #expect(both.value(forKey: "revenue") == 94)
        #expect(both.value(forKey: "totalDebt") == 12.5)
        #expect(both.texts.count == core.texts.count + extended.texts.count)
        #expect(both.values.count == core.values.count + extended.values.count)
    }

    // MARK: - Answers that cannot be used

    @Test func noJSONAtAll() {
        let outcome = MetricsParser.parse("I am sorry, I cannot extract this information.", schema: schema)
        #expect(outcome.failure == .noJSON)
        #expect(!outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
        #expect(outcome.unreadableKeys.isEmpty)
    }

    @Test func emptyAnswer() {
        #expect(MetricsParser.parse("", schema: schema).failure == .noJSON)
    }

    @Test func answerCutOffBeforeTheClosingBrace() {
        let outcome = MetricsParser.parse("{\n\"revenue\": \"$94 billion\",\n\"operatingIncome\": ", schema: schema)
        #expect(outcome.failure == .noJSON)
    }

    @Test func invalidJSON() {
        let outcome = MetricsParser.parse("{ revenue: 94 }", schema: schema)
        #expect(outcome.failure == .invalidJSON)
        #expect(!outcome.isValidJSON)
    }

    /// Foundation's JSON parsers (JSONDecoder and JSONSerialization) accept a trailing comma.
    /// "Valid JSON" in this project means "the app's own decoder can read it", so this counts
    /// as valid JSON. The schema check still fails here. Keep this in mind when reporting results.
    @Test func trailingCommaIsToleratedByFoundation() {
        let outcome = MetricsParser.parse("{\"revenue\": \"$94 billion\",}", schema: schema)
        #expect(outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
    }

    // MARK: - Valid JSON with the wrong schema

    private func wrongSchemaMessage(_ raw: String) -> String? {
        let outcome = MetricsParser.parse(raw, schema: schema)
        guard case .wrongSchema(let message) = outcome.failure else {
            Issue.record("expected wrongSchema, got \(String(describing: outcome.failure))")
            return nil
        }
        #expect(outcome.isValidJSON)
        #expect(!outcome.isSchemaValid)
        return message
    }

    @Test func missingKeyIsNotSilentlyNull() {
        // A missing key must not read as null: the parser must reject it.
        let raw = sampleJSON.replacingOccurrences(of: ",\n\"epsGrowth\": null", with: "")
        #expect(wrongSchemaMessage(raw)?.contains("missing epsGrowth") == true)
    }

    @Test func unexpectedKey() {
        let raw = answer(extra: ",\n\"currency\": \"USD\"")
        #expect(wrongSchemaMessage(raw)?.contains("unexpected currency") == true)
    }

    @Test func anExtendedFieldIsUnexpectedInTheCoreAnswer() {
        let raw = answer(extra: ",\n\"totalDebt\": \"$5 billion\"")
        #expect(wrongSchemaMessage(raw)?.contains("unexpected totalDebt") == true)
    }

    @Test func aNumberInsteadOfAString() {
        let raw = answer(["revenue": "94"])
        #expect(wrongSchemaMessage(raw)?.contains("revenue is not a string or null") == true)
    }

    @Test func aBooleanInsteadOfAString() {
        let raw = answer(["netIncome": "true"])
        #expect(wrongSchemaMessage(raw)?.contains("netIncome is not a string or null") == true)
    }

    @Test func anObjectInsteadOfAString() {
        let raw = answer(["eps": "{\"value\": 1}"])
        #expect(wrongSchemaMessage(raw)?.contains("eps is not a string or null") == true)
    }
}
