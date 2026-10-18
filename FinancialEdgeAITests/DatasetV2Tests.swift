//
//  DatasetV2Tests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 17/10/2026.
//
import Foundation
import Testing

/// The Phase 2b files (`Dataset/v2`): the same oracle checks as the first dataset, for the core call.
/// The parser must read every printed string to the true value of the sidecar, and the dataset's own answers
/// must score 100%, or the evaluation (and the training data) would be wrong.
struct DatasetV2Tests {

    private static let splits = ["train", "valid", "test2"]
    private static let directory = "Dataset/v2"

    @Test(arguments: DatasetV2Tests.splits)
    func everyPrintedStringParsesToItsTrueValue(split: String) throws {
        let schema = try DatasetFiles.schema()
        var failures: [String] = []
        var checked = 0
        for line in try DatasetFiles.labelLines(of: split, directory: Self.directory) {
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

    @Test(arguments: DatasetV2Tests.splits)
    func theDatasetsOwnAnswersScoreEverythingCorrect(split: String) throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.split(split, directory: Self.directory)
        let answers = try DatasetFiles.assistantMessages(of: split, directory: Self.directory)
        #expect(answers.count == examples.count)
        #expect(!examples.isEmpty)

        let records = zip(examples, answers).map { example, answer in
            EvaluationMetrics.makeRecord(
                example: example, run: 1, seed: 1, generation: Self.generation(text: answer),
                generationError: nil, thermalBefore: 0, thermalAfter: 0, schema: schema, tier: .core)
        }
        let summary = EvaluationMetrics.summarize(records, schema: schema, tier: .core)
        #expect(summary.validJSON == examples.count)
        #expect(summary.schemaValid == examples.count)
        #expect(summary.fullyCorrect == examples.count)
        #expect(summary.fieldAccuracy == 1)
        #expect(summary.exactCopies == summary.exactCopiesComparable)
    }

    @Test(arguments: DatasetV2Tests.splits)
    func theAssistantMessageIsTheCoreOfTheSidecar(split: String) throws {
        let schema = try DatasetFiles.schema()
        let answers = try DatasetFiles.assistantMessages(of: split, directory: Self.directory)
        let labels = try DatasetFiles.labelLines(of: split, directory: Self.directory)
        #expect(answers.count == labels.count)
        for (answer, label) in zip(answers, labels) {
            let outcome = MetricsParser.parse(answer, schema: schema, tier: .core)
            let metrics = try #require(outcome.metrics, "line \(label.line)")
            for key in schema.keys(for: .core) {
                #expect(metrics.text(forKey: key) == (label.fields[key] ?? nil)?.text, "line \(label.line) \(key)")
            }
        }
    }

    /// The coverage promised by the spec: every core field is stated in at least a quarter of the training statements.
    @Test func everyCoreFieldIsStatedInAQuarterOfTheTrainingStatements() throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.split("train", directory: Self.directory)
        for key in schema.keys(for: .core) {
            let count = examples.filter { $0.expected.text(forKey: key) != nil }.count
            #expect(Double(count) / Double(examples.count) >= 0.25, "\(key) is stated in \(count) of \(examples.count)")
        }
    }

    @Test func test2HasEveryCoreFieldAtLeastThreeTimes() throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.split("test2", directory: Self.directory)
        #expect(examples.count == 30)
        for key in schema.keys(for: .core) {
            let count = examples.filter { $0.expected.text(forKey: key) != nil }.count
            #expect(count >= 3, "\(key) is in only \(count) statements of test 2")
        }
    }

    /// The app bundles test 2; the copy must be the file of the dataset, byte for byte.
    @Test func theBundledCopiesOfTest2AreTheDatasetFiles() throws {
        for (published, source) in [("test2.jsonl", "test2.jsonl"), ("test2.labels.jsonl", "test2.labels.jsonl"),
                                    ("index.v2.csv", "index.csv")] {
            let bundled = try DatasetFiles.text("FinancialEdgeAI/Resources/\(published)")
            #expect(bundled == (try DatasetFiles.text("Dataset/v2/\(source)")), "\(published) differs")
        }
    }

    /// The frozen test of every earlier experiment must not appear in the new training data.
    @Test func noTrainingStatementIsInTheOldTestOrInTest2() throws {
        let train = Set(try DatasetFiles.split("train", directory: Self.directory).map(\.statement))
        let valid = Set(try DatasetFiles.split("valid", directory: Self.directory).map(\.statement))
        let old = Set(try DatasetFiles.testSplit().map(\.statement))
        let test2 = Set(try DatasetFiles.split("test2", directory: Self.directory).map(\.statement))
        #expect(train.isDisjoint(with: old))
        #expect(train.isDisjoint(with: test2))
        #expect(valid.isDisjoint(with: old.union(test2).union(train)))
        #expect(test2.isDisjoint(with: old))
    }

    private static func generation(text: String) -> GenerationResult {
        GenerationResult(
            text: text, promptTokens: 300, generatedTokens: 70, promptTime: 1.5, generateTime: 3.2,
            totalTime: 4.7, tokensPerSecond: 21.8, activeMemory: 2_000_000_000, peakMemory: 2_500_000_000)
    }
}
