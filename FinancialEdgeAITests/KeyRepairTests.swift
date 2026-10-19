//
//  KeyRepairTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 19/10/2026.
//
import Foundation
import Testing

/// The rule of `KeyRepair`: one garbled key, at the position where the schema's key belongs, and nothing else.
struct KeyRepairTests {

    private let schema = try! DatasetFiles.schema()
    private var core: [String] { schema.keys(for: .core) }
    private var extended: [String] { schema.keys(for: .extended) }

    /// A JSON object in the order of `keys`, one value per key: a string, or null for `nil`.
    private func answer(_ keys: [String], values: [String: String] = [:]) -> String {
        let lines = keys.map { key in
            let value = values[key].map { "\"\($0)\"" } ?? "null"
            return "  \"\(key)\": \(value)"
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n}"
    }

    private func replacing(_ keys: [String], at index: Int, with key: String) -> [String] {
        var copy = keys
        copy[index] = key
        return copy
    }

    // MARK: - Repaired

    @Test(arguments: ["previous6YearEps", "previous5000", "previous500", "prevYearEps", "x"])
    func oneGarbledKeyAtItsPositionIsRead(garbled: String) throws {
        let keys = replacing(core, at: 9, with: garbled)      // previousYearEps is the 10th key
        let raw = answer(keys, values: ["revenue": "$5 billion", garbled: "$2.35"])

        let strict = MetricsParser.parse(raw, schema: schema)
        #expect(strict.metrics == nil)                        // an evaluation stays strict
        #expect(strict.failure != nil && strict.isValidJSON)

        let repaired = MetricsParser.parse(raw, schema: schema, repairKeys: true)
        #expect(repaired.repair == .init(found: garbled, expected: "previousYearEps", position: 10))
        let metrics = try #require(repaired.metrics)
        #expect(metrics.text(forKey: "previousYearEps") == "$2.35")     // the value is kept
        #expect(metrics.text(forKey: "revenue") == "$5 billion")
        #expect(repaired.isSchemaValid)
    }

    @Test(arguments: [0, 6, 12])
    func theFirstTheMiddleAndTheLastPositionAreRepairedToo(index: Int) throws {
        let keys = replacing(core, at: index, with: "garbled_key")
        let outcome = MetricsParser.parse(answer(keys), schema: schema, repairKeys: true)
        #expect(outcome.repair == .init(found: "garbled_key", expected: core[index], position: index + 1))
        #expect(outcome.metrics != nil)
    }

    @Test func theExtendedCallIsRepairedWithItsOwnKeys() throws {
        let keys = replacing(extended, at: 2, with: "currentAssetz")
        let outcome = MetricsParser.parse(answer(keys), schema: schema, tier: .extended, repairKeys: true)
        #expect(outcome.repair == .init(found: "currentAssetz", expected: extended[2], position: 3))
        #expect(outcome.metrics != nil)
    }

    @Test func aFenceAndAThinkingBlockAroundTheAnswerDoNotPreventTheRepair() throws {
        let keys = replacing(core, at: 9, with: "previous6YearEps")
        let raw = "<think>\n\n</think>\n```json\n" + answer(keys) + "\n```"
        let outcome = MetricsParser.parse(raw, schema: schema, repairKeys: true)
        #expect(outcome.repair?.expected == "previousYearEps")
        #expect(outcome.hadFence && outcome.hadThinking)
    }

    // MARK: - Not repaired

    private func notRepaired(_ raw: String, tier: FieldTier = .core, sourceLocation: SourceLocation = #_sourceLocation) {
        let outcome = MetricsParser.parse(raw, schema: schema, tier: tier, repairKeys: true)
        #expect(outcome.metrics == nil, sourceLocation: sourceLocation)
        #expect(outcome.repair == nil, sourceLocation: sourceLocation)
    }

    @Test func twoGarbledKeysAreNotRepaired() {
        var keys = replacing(core, at: 9, with: "previous6YearEps")
        keys[3] = "eps_"
        notRepaired(answer(keys))
    }

    @Test func aMissingKeyWithNoExtraOneIsNotRepaired() {
        notRepaired(answer(Array(core.dropLast())))                       // 12 keys
    }

    @Test func anExtraKeyWithNoMissingOneIsNotRepaired() {
        notRepaired(answer(core + ["extra"]))                             // 14 keys
    }

    @Test func aGarbledKeyWithANumberAsItsValueIsNotRepaired() {
        let keys = replacing(core, at: 9, with: "previous6YearEps")
        let raw = answer(keys).replacingOccurrences(of: "\"previous6YearEps\": null", with: "\"previous6YearEps\": 2.35")
        notRepaired(raw)
    }

    @Test func aDuplicateKeyIsNotRepaired() {
        // The 10th key repeats the 9th: a schema key, so it is not a garbled one.
        notRepaired(answer(replacing(core, at: 9, with: core[8])))
    }

    @Test func aNestedValueIsNotRepaired() {
        let keys = replacing(core, at: 9, with: "previous6YearEps")
        let raw = answer(keys).replacingOccurrences(of: "\"previous6YearEps\": null", with: "\"previous6YearEps\": {\"a\": \"b\"}")
        notRepaired(raw)
    }

    @Test func aGarbledKeyThatIsAKeyOfTheOtherTierIsNotRepaired() {
        // `cash` is a key of the extended call: out of place in the core answer, not a garbled key.
        notRepaired(answer(replacing(core, at: 9, with: "cash")))
    }

    @Test func invalidJSONAndNoJSONKeepTheirFailure() {
        let broken = MetricsParser.parse("{\"revenue\": null,", schema: schema, repairKeys: true)
        #expect(broken.failure == .noJSON || broken.failure == .invalidJSON)
        #expect(broken.repair == nil)
        let none = MetricsParser.parse("I cannot answer.", schema: schema, repairKeys: true)
        #expect(none.failure == .noJSON)
    }

    @Test func withoutTheFlagNothingIsRepaired() {
        let raw = answer(replacing(core, at: 9, with: "previous6YearEps"))
        let outcome = MetricsParser.parse(raw, schema: schema)
        #expect(outcome.metrics == nil)
        #expect(outcome.repair == nil)
        if case .wrongSchema(let reason)? = outcome.failure {
            #expect(reason.contains("missing previousYearEps"))
            #expect(reason.contains("unexpected previous6YearEps"))
        } else {
            Issue.record("expected a wrong schema failure")
        }
    }

    // MARK: - Answers that are fine stay as they are

    @Test func aValidAnswerIsParsedTheSameWithAndWithoutTheFlag() {
        let raw = answer(core, values: ["revenue": "$5 billion", "eps": "$2.35"])
        let strict = MetricsParser.parse(raw, schema: schema)
        let repairing = MetricsParser.parse(raw, schema: schema, repairKeys: true)
        #expect(strict == repairing)
        #expect(repairing.repair == nil)
    }

    @Test func theSameKeysInAnotherOrderAreValidAndNotRepaired() {
        let raw = answer(core.reversed())
        let outcome = MetricsParser.parse(raw, schema: schema, repairKeys: true)
        #expect(outcome.metrics != nil)
        #expect(outcome.repair == nil)
    }

    // MARK: - The key scanner

    @Test func theKeysAreReadInTheOrderTheyAreWritten() {
        let json = "{ \"b\": \"x\", \"a\": null, \"c\": \"1,2\" }"
        #expect(KeyRepair.topLevelKeys(of: json) == ["b", "a", "c"])
    }

    @Test func valuesOfAnyKindAreSkippedAndEscapesAreRead() {
        let json = "{\"a\": {\"x\": [1, {\"y\": \"}\"}]}, \"b\\\"c\": \"v\\\\\", \"d\": 3.5, \"e\": true}"
        #expect(KeyRepair.topLevelKeys(of: json) == ["a", "b\"c", "d", "e"])
    }

    @Test(arguments: ["", "[]", "{", "{\"a\" 1}", "{\"a\": 1,}", "{\"a\": 1} trailing", "not json"])
    func textThatIsNotOneObjectGivesNoKeys(text: String) {
        #expect(KeyRepair.topLevelKeys(of: text) == nil)
    }

    @Test func anEmptyObjectHasNoKeys() {
        #expect(KeyRepair.topLevelKeys(of: "{ }") == [])
    }
}
