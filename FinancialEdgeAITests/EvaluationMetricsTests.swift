//
//  EvaluationMetricsTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation
import Testing

struct EvaluationMetricsTests {

    private let schema: Schema

    init() throws {
        schema = try DatasetFiles.schema()
    }

    // MARK: - One value

    @Test func bothNullIsCorrect() {
        #expect(EvaluationMetrics.compare(expected: nil, actual: nil) == .correct)
    }

    @Test func inventedValueIsHallucinated() {
        #expect(EvaluationMetrics.compare(expected: nil, actual: -0.5) == .hallucinated)
    }

    @Test func nullInsteadOfAValueIsMissed() {
        #expect(EvaluationMetrics.compare(expected: 21.9, actual: nil) == .missed)
    }

    @Test func sameValueWithinTheToleranceIsCorrect() {
        #expect(EvaluationMetrics.compare(expected: 21.9, actual: 21.9) == .correct)
        #expect(EvaluationMetrics.compare(expected: 21.9, actual: 21.9004) == .correct)
        #expect(EvaluationMetrics.compare(expected: 21.9, actual: 21.95) == .wrongValue)
    }

    @Test func oppositeSignIsASignError() {
        #expect(EvaluationMetrics.compare(expected: -4, actual: 4) == .signError)
        #expect(EvaluationMetrics.compare(expected: 12.5, actual: -12.5) == .signError)
    }

    @Test func millionsAgainstBillionsIsAUnitError() {
        #expect(EvaluationMetrics.compare(expected: 0.41, actual: 410) == .unitError)
        #expect(EvaluationMetrics.compare(expected: 410, actual: 0.41) == .unitError)
    }

    @Test func anyOtherNumberIsWrong() {
        #expect(EvaluationMetrics.compare(expected: 94, actual: 93) == .wrongValue)
        #expect(EvaluationMetrics.compare(expected: -8.2, actual: -0.5) == .wrongValue)
    }

    // MARK: - One answer

    @Test func answerWithoutJSONLeavesEveryFieldUnparsed() {
        let record = record(answer: "I cannot do that.")
        #expect(!record.isValidJSON)
        #expect(!record.isSchemaValid)
        #expect(record.fields.count == schema.coreKeys.count)
        #expect(record.fields.values.allSatisfy { $0 == .unparsed })
        #expect(!record.isFullyCorrect)
        #expect(record.exactCopies.isEmpty)
    }

    @Test func failedGenerationIsRecordedAsUnparsed() {
        let record = EvaluationMetrics.makeRecord(
            example: example(), run: 1, seed: 1, generation: nil,
            generationError: "out of memory", thermalBefore: 0, thermalAfter: 0, schema: schema)
        #expect(record.generationError == "out of memory")
        #expect(record.fields.values.allSatisfy { $0 == .unparsed })
    }

    @Test func theUnitIsJudgedAfterTheParserSoMillionsWrittenAsMillionsAreCorrect() {
        // The label is 94 billion. The model copied "94,000 million": the same amount, so it is correct.
        let record = record(answer: answerJSON(["revenue": "94,000 million"]))
        #expect(record.fields["revenue"] == .correct)
        #expect(record.exactCopies["revenue"] == false)
    }

    @Test func eachMistakeIsNamedOnItsField() {
        // The label has netIncomeGrowth null, previousYearNetIncome 21.9 and EPS null. The model got one
        // number wrong, flipped a sign, wrote millions where billions were expected, calculated a
        // growth that is not in the text, left the previous year out, and wrote a string that is no value.
        let answer = answerJSON([
            "revenue": "$93 billion", "revenueGrowth": "-12%", "operatingIncome": "$25 million",
            "netIncome": "$21 billion", "netIncomeGrowth": "-0.5%", "capex": "five",
        ], without: ["previousYearNetIncome"])
        let record = record(answer: answer)
        #expect(record.fields["revenue"] == .wrongValue)
        #expect(record.fields["revenueGrowth"] == .signError)
        #expect(record.fields["operatingIncome"] == .unitError)
        #expect(record.fields["netIncome"] == .correct)
        #expect(record.fields["netIncomeGrowth"] == .hallucinated)
        #expect(record.fields["previousYearNetIncome"] == .missed)
        #expect(record.fields["capex"] == .unreadable)
        #expect(record.fields["eps"] == .correct)
        #expect(record.isSchemaValid)
        #expect(!record.isFullyCorrect)
    }

    @Test func exactCopiesAreRecordedForTheStringsBothSidesHave() {
        let record = record(answer: answerJSON([
            "revenue": "$94 billion", "revenueGrowth": "12 percent", "netIncomeGrowth": "-0.5%",
        ]))
        // revenue: same string. revenueGrowth: same number, another string. netIncomeGrowth: the label has none.
        #expect(record.exactCopies["revenue"] == true)
        #expect(record.exactCopies["revenueGrowth"] == false)
        #expect(record.exactCopies["netIncomeGrowth"] == nil)
        #expect(record.fields["revenueGrowth"] == .correct)
    }

    // MARK: - The extended call

    private var expectedExtended: FinancialMetrics {
        FinancialMetrics(
            texts: ["totalDebt": "$12.5 billion", "shareholdersEquity": "$30 billion", "cash": "4,200 million dollars"],
            values: ["totalDebt": 12.5, "shareholdersEquity": 30, "cash": 4.2])
    }

    private func extendedRecord(_ overrides: [String: String?] = [:], rawAnswer: String? = nil) -> EvaluationRecord {
        var texts = expectedExtended.texts as [String: String?]
        for (key, text) in overrides { texts[key] = text }
        let lines = schema.extendedKeys.map { key in
            "\"\(key)\": " + ((texts[key] ?? nil).map { "\"\($0)\"" } ?? "null")
        }
        let answer = rawAnswer ?? "{\n" + lines.joined(separator: ",\n") + "\n}"
        let example = ExtractionExample(
            id: 1, statement: "statement", expected: expectedExtended, source: "generated", scenario: "balance_sheet", pool: "A")
        return EvaluationMetrics.makeRecord(
            example: example, run: 1, seed: 1, generation: generation(text: answer),
            generationError: nil, thermalBefore: 0, thermalAfter: 0, schema: schema, tier: .extended)
    }

    @Test func anExtendedAnswerIsJudgedOnTheExtendedKeysOnly() {
        let record = extendedRecord()
        #expect(Set(record.fields.keys) == Set(schema.extendedKeys))
        #expect(record.fields.values.allSatisfy { $0 == .correct })
        #expect(record.isFullyCorrect)
        #expect(record.isSchemaValid)
    }

    @Test func theExtendedMistakesAreNamedOnTheirFields() {
        // Wrong equity, an invented current assets value, cash left out, a string that is no value.
        let record = extendedRecord([
            "shareholdersEquity": "$31 billion", "currentAssets": "$9.8 billion", "cash": nil,
            "currentLiabilities": "plenty",
        ])
        #expect(record.fields["totalDebt"] == .correct)
        #expect(record.fields["shareholdersEquity"] == .wrongValue)
        #expect(record.fields["currentAssets"] == .hallucinated)
        #expect(record.fields["cash"] == .missed)
        #expect(record.fields["currentLiabilities"] == .unreadable)
        #expect(!record.isFullyCorrect)
    }

    @Test func aCoreAnswerGivenToTheExtendedCallIsUnparsed() {
        let core = answerJSON([:])
        let record = extendedRecord(rawAnswer: core)
        #expect(!record.isSchemaValid)
        #expect(record.fields.count == schema.extendedKeys.count)
        #expect(record.fields.values.allSatisfy { $0 == .unparsed })
    }

    @Test func theSummaryOfAnExtendedRunCountsTheExtendedFields() {
        let summary = EvaluationMetrics.summarize([extendedRecord(), extendedRecord(["cash": nil])], schema: schema, tier: .extended)
        #expect(summary.records == 2)
        #expect(summary.fullyCorrect == 1)
        #expect(Set(summary.fieldOutcomes.keys) == Set(schema.extendedKeys))
        // 5 fields in 2 answers; one field is missed once.
        #expect(abs(summary.fieldAccuracy - 9.0 / 10.0) < 1e-9)
    }

    // MARK: - Many answers

    @Test func summaryCountsTheOutcomes() {
        let perfect = record(answer: answerJSON([:]))
        let flawed = record(answer: answerJSON(["netIncomeGrowth": "-0.5%"]))
        let unreadable = record(answer: "no JSON here")
        let summary = EvaluationMetrics.summarize([perfect, flawed, unreadable], schema: schema)
        let fieldCount = schema.coreKeys.count

        #expect(summary.records == 3)
        #expect(summary.validJSON == 2)
        #expect(summary.schemaValid == 2)
        #expect(summary.fullyCorrect == 1)
        #expect(summary.fieldOutcomes["netIncomeGrowth"]?["hallucinated"] == 1)
        #expect(summary.fieldOutcomes["netIncomeGrowth"]?["unparsed"] == 1)
        // The perfect answer has every field correct, the flawed one all but one, the unreadable one none.
        #expect(abs(summary.fieldAccuracy - Double(2 * fieldCount - 1) / Double(3 * fieldCount)) < 1e-9)
        #expect(summary.rate(summary.validJSON) == 2.0 / 3.0)
        // The label has 5 strings; both readable answers copied all of them.
        #expect(summary.exactCopiesComparable == 2 * 5)
        #expect(summary.exactCopies == 2 * 5)
    }

    @Test func groupsAreSummarisedSeparately() {
        let a = record(answer: answerJSON([:]), scenario: "full")
        let b = record(answer: "no JSON here", scenario: "none")
        let groups = EvaluationMetrics.summarize([a, b], schema: schema, groupedBy: \.scenario)
        #expect(groups["full"]?.fullyCorrect == 1)
        #expect(groups["none"]?.fullyCorrect == 0)
    }

    @Test func medianOfOddAndEvenCounts() {
        #expect(EvaluationMetrics.median([3, 1, 2]) == 2)
        #expect(EvaluationMetrics.median([4, 1, 3, 2]) == 2.5)
        #expect(EvaluationMetrics.median([]) == 0)
    }

    // MARK: - Helpers

    /// The label of an invented statement: six fields, the others null.
    private var expected: FinancialMetrics {
        FinancialMetrics(
            texts: ["revenue": "$94 billion", "revenueGrowth": "12%", "operatingIncome": "$25 billion",
                    "netIncome": "$21 billion", "previousYearNetIncome": "$21.9 billion"],
            values: ["revenue": 94, "revenueGrowth": 12, "operatingIncome": 25,
                     "netIncome": 21, "previousYearNetIncome": 21.9])
    }

    /// The answer that matches the label, with some keys replaced by the strings given.
    private func answerJSON(_ overrides: [String: String], without: [String] = []) -> String {
        var texts = expected.texts
        for (key, text) in overrides { texts[key] = text }
        for key in without { texts[key] = nil }
        let lines = schema.coreKeys.map { key in
            "\"\(key)\": " + (texts[key].map { "\"\($0)\"" } ?? "null")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n}"
    }

    private func example(scenario: String = "full") -> ExtractionExample {
        ExtractionExample(
            id: 1, statement: "statement", expected: expected, source: "generated", scenario: scenario, pool: "A")
    }

    private func generation(text: String) -> GenerationResult {
        GenerationResult(
            text: text, promptTokens: 300, generatedTokens: 70, promptTime: 1.5, generateTime: 3.2,
            totalTime: 4.7, tokensPerSecond: 21.8, activeMemory: 2_000_000_000, peakMemory: 2_500_000_000)
    }

    private func record(answer: String, scenario: String = "full") -> EvaluationRecord {
        EvaluationMetrics.makeRecord(
            example: example(scenario: scenario), run: 1, seed: 1, generation: generation(text: answer),
            generationError: nil, thermalBefore: 0, thermalAfter: 0, schema: schema)
    }
}
