//
//  OracleTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation
import Testing

/// If the dataset's own correct answers do not score 100%, the evaluation itself is wrong.
///
/// The labels carry the true value of every printed string, written by the generator without the
/// parser. So `ValueParser(text) == value` is a check of the parser against ground truth, for every
/// field of every statement of every split.
struct OracleTests {

    private static let splits = ["train", "valid", "test"]

    @Test(arguments: OracleTests.splits)
    func everyPrintedStringParsesToItsTrueValue(split: String) throws {
        let schema = try DatasetFiles.schema()
        var failures: [String] = []
        var checked = 0
        for line in try DatasetFiles.labelLines(of: split) {
            for field in schema.fields {
                guard let entry = line.fields[field.key] ?? nil else { continue }
                checked += 1
                guard let parsed = ValueParser.parse(entry.text, field: field) else {
                    failures.append("\(split):\(line.line) \(field.key) \"\(entry.text)\" was not read")
                    continue
                }
                if abs(parsed - entry.value) > 1e-9 * max(1, abs(entry.value)) {
                    failures.append("\(split):\(line.line) \(field.key) \"\(entry.text)\" gave \(parsed), expected \(entry.value)")
                }
            }
        }
        #expect(checked > 0)
        #expect(failures.isEmpty, "\(failures.count) of \(checked): \(failures.prefix(8))")
    }

    @Test(arguments: OracleTests.splits)
    func theDatasetsOwnAnswersScoreEverythingCorrect(split: String) throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.split(split)
        let answers = try DatasetFiles.assistantMessages(of: split)
        #expect(answers.count == examples.count)

        let records = zip(examples, answers).map { example, answer in
            EvaluationMetrics.makeRecord(
                example: example, run: 1, seed: 1, generation: Self.generation(text: answer),
                generationError: nil, thermalBefore: 0, thermalAfter: 0, schema: schema)
        }
        let summary = EvaluationMetrics.summarize(records, schema: schema)
        #expect(summary.validJSON == examples.count)
        #expect(summary.schemaValid == examples.count)
        #expect(summary.fullyCorrect == examples.count)
        #expect(summary.fieldAccuracy == 1)
        #expect(summary.fenced == 0)
        #expect(summary.exactCopies == summary.exactCopiesComparable)
        #expect(summary.exactCopiesComparable > 0)
    }

    @Test(arguments: OracleTests.splits)
    func theAssistantMessageIsTheCoreOfTheSidecar(split: String) throws {
        let schema = try DatasetFiles.schema()
        let answers = try DatasetFiles.assistantMessages(of: split)
        let labels = try DatasetFiles.labelLines(of: split)
        #expect(answers.count == labels.count)
        for (answer, label) in zip(answers, labels) {
            let outcome = MetricsParser.parse(answer, schema: schema)
            let metrics = try #require(outcome.metrics, "line \(label.line)")
            for key in schema.coreKeys {
                #expect(metrics.text(forKey: key) == (label.fields[key] ?? nil)?.text, "line \(label.line) \(key)")
            }
        }
    }

    @Test func everyCoreFieldIsInEveryTestSplitAtLeastThreeTimes() throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.testSplit()
        for key in schema.coreKeys {
            let count = examples.filter { $0.expected.text(forKey: key) != nil }.count
            #expect(count >= 3, "\(key) is in only \(count) test statements")
        }
    }

    @Test func magnitudeFieldsAreLabelledPositive() throws {
        let schema = try DatasetFiles.schema()
        let magnitudes = schema.fields.filter(\.isMagnitude).map(\.key)
        for split in Self.splits {
            for line in try DatasetFiles.labelLines(of: split) {
                for key in magnitudes {
                    if let value = (line.fields[key] ?? nil)?.value { #expect(value > 0) }
                }
            }
        }
    }

    private static func generation(text: String) -> GenerationResult {
        GenerationResult(
            text: text, promptTokens: 300, generatedTokens: 70, promptTime: 1.5, generateTime: 3.2,
            totalTime: 4.7, tokensPerSecond: 21.8, activeMemory: 2_000_000_000, peakMemory: 2_500_000_000)
    }
}
