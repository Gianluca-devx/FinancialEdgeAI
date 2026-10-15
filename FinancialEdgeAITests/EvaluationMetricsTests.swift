//
//  EvaluationMetricsTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation
import Testing

struct EvaluationMetricsTests {

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
        let record = Self.record(answer: "I cannot do that.")
        #expect(!record.isValidJSON)
        #expect(!record.isSchemaValid)
        #expect(record.fields.count == FinancialMetrics.keys.count)
        #expect(record.fields.values.allSatisfy { $0 == .unparsed })
        #expect(!record.isFullyCorrect)
    }

    @Test func failedGenerationIsRecordedAsUnparsed() {
        let record = EvaluationMetrics.makeRecord(
            example: Self.example, run: 1, seed: 1, generation: nil,
            generationError: "out of memory", thermalBefore: 0, thermalAfter: 0)
        #expect(record.generationError == "out of memory")
        #expect(record.fields.values.allSatisfy { $0 == .unparsed })
    }

    @Test func eachMistakeIsNamedOnItsField() {
        // Expected: netIncomeGrowth is null and previousYearNetIncome is 21.9. The model got one
        // number wrong, flipped a sign, gave millions instead of billions, calculated a growth
        // that is not in the text, and left the previous year out.
        let expected = FinancialMetrics(
            revenue: 94, revenueGrowth: 12, operatingIncome: 25, operatingIncomeGrowth: 8,
            netIncome: 21, netIncomeGrowth: nil, previousYearNetIncome: 21.9)
        let answer = """
        {"revenue": 93, "revenueGrowth": -12, "operatingIncome": 25000, "operatingIncomeGrowth": 8,
         "netIncome": 21, "netIncomeGrowth": -0.5, "previousYearNetIncome": null}
        """
        let record = Self.record(answer: answer, expected: expected)
        #expect(record.fields["revenue"] == .wrongValue)
        #expect(record.fields["revenueGrowth"] == .signError)
        #expect(record.fields["operatingIncome"] == .unitError)
        #expect(record.fields["operatingIncomeGrowth"] == .correct)
        #expect(record.fields["netIncome"] == .correct)
        #expect(record.fields["netIncomeGrowth"] == .hallucinated)
        #expect(record.fields["previousYearNetIncome"] == .missed)
        #expect(record.isSchemaValid)
        #expect(!record.isFullyCorrect)
    }

    // MARK: - Many answers

    @Test func summaryCountsTheOutcomes() {
        let perfect = Self.record(answer: Self.expectedJSON)
        let flawed = Self.record(answer: Self.expectedJSON.replacingOccurrences(
            of: "\"netIncomeGrowth\": null", with: "\"netIncomeGrowth\": -0.5"))
        let unreadable = Self.record(answer: "no JSON here")
        let summary = EvaluationMetrics.summarize([perfect, flawed, unreadable])

        #expect(summary.records == 3)
        #expect(summary.validJSON == 2)
        #expect(summary.schemaValid == 2)
        #expect(summary.fullyCorrect == 1)
        #expect(summary.fieldOutcomes["netIncomeGrowth"]?["hallucinated"] == 1)
        #expect(summary.fieldOutcomes["netIncomeGrowth"]?["unparsed"] == 1)
        // 7 + 6 correct fields out of 21
        #expect(abs(summary.fieldAccuracy - 13.0 / 21.0) < 1e-9)
        #expect(summary.rate(summary.validJSON) == 2.0 / 3.0)
    }

    @Test func groupsAreSummarisedSeparately() {
        let a = Self.record(answer: Self.expectedJSON, scenario: "full")
        let b = Self.record(answer: "no JSON here", scenario: "none")
        let groups = EvaluationMetrics.summarize([a, b], groupedBy: \.scenario)
        #expect(groups["full"]?.fullyCorrect == 1)
        #expect(groups["none"]?.fullyCorrect == 0)
    }

    @Test func medianOfOddAndEvenCounts() {
        #expect(EvaluationMetrics.median([3, 1, 2]) == 2)
        #expect(EvaluationMetrics.median([4, 1, 3, 2]) == 2.5)
        #expect(EvaluationMetrics.median([]) == 0)
    }

    // MARK: - The oracle

    /// If the dataset's own correct answers do not score 100%, the evaluation itself is wrong.
    @Test func theDatasetsOwnAnswersScoreEverythingCorrect() throws {
        let text = try String(contentsOf: DatasetFiles.url("Dataset/test.jsonl"), encoding: .utf8)
        let examples = try DatasetFiles.testSplit()
        let answers = try DatasetFiles.assistantMessages(in: text)
        #expect(examples.count == 30)
        #expect(answers.count == examples.count)

        let records = zip(examples, answers).map { example, answer in
            EvaluationMetrics.makeRecord(
                example: example, run: 1, seed: 1, generation: Self.generation(text: answer),
                generationError: nil, thermalBefore: 0, thermalAfter: 0)
        }
        let summary = EvaluationMetrics.summarize(records)
        #expect(summary.validJSON == 30)
        #expect(summary.schemaValid == 30)
        #expect(summary.fullyCorrect == 30)
        #expect(summary.fieldAccuracy == 1)
        #expect(summary.fenced == 0)
    }

    // MARK: - Helpers

    private static let expected = FinancialMetrics(
        revenue: 93, revenueGrowth: 12, operatingIncome: 25, operatingIncomeGrowth: 8,
        netIncome: 21, netIncomeGrowth: nil, previousYearNetIncome: nil)

    private static let expectedJSON = """
    {"revenue": 93, "revenueGrowth": 12, "operatingIncome": 25, "operatingIncomeGrowth": 8,
     "netIncome": 21, "netIncomeGrowth": null, "previousYearNetIncome": null}
    """

    private static let example = ExtractionExample(
        id: 1, statement: "statement", expected: expected, source: "generated", scenario: "full", pool: "A")

    private static func generation(text: String) -> GenerationResult {
        GenerationResult(
            text: text, promptTokens: 300, generatedTokens: 70, promptTime: 1.5, generateTime: 3.2,
            totalTime: 4.7, tokensPerSecond: 21.8, activeMemory: 2_000_000_000, peakMemory: 2_500_000_000)
    }

    private static func record(
        answer: String, scenario: String = "full", expected: FinancialMetrics = expected
    ) -> EvaluationRecord {
        let example = ExtractionExample(
            id: 1, statement: "statement", expected: expected, source: "generated",
            scenario: scenario, pool: "A")
        return EvaluationMetrics.makeRecord(
            example: example, run: 1, seed: 1, generation: generation(text: answer),
            generationError: nil, thermalBefore: 0, thermalAfter: 0)
    }
}
