//
//  SafeguardMeasurementTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 19/10/2026.
//
import Foundation
import Testing

/// The criteria of `Specs/phase-2c-app-safeguards.md`, measured with the real implementation (`KeyRepair`,
/// `MetricsParser`, `UnusedAmounts`) on every saved evaluation report, not on a copy of the rules.
///
/// The raw answers are in the reports, so nothing runs on the phone. The reports of the real-style sets are private
/// (`RealSet/reports/`, never committed): their part runs only where that folder is present, and prints counts only,
/// never a statement. Numbers are printed with the prefix `[safeguard]`.
struct SafeguardMeasurementTests {

    // MARK: - What a saved report holds (only what is needed; older formats are skipped)

    private struct Saved: Decodable {
        struct Metadata: Decodable {
            struct Adapter: Decodable { let name: String }
            let tier: String?
            let keys: [String]?
            let coreKeys: [String]?
            let evaluationSet: String?
            let adapter: Adapter?
        }
        struct Record: Decodable {
            struct Generation: Decodable { let text: String }
            let exampleID: Int
            let run: Int
            let isValidJSON: Bool
            let isSchemaValid: Bool
            let fields: [String: String]
            let generation: Generation?
        }
        let metadata: Metadata
        let records: [Record]

        var isCoreCall: Bool {
            (metadata.tier ?? "core") == "core" && (metadata.keys?.count == 13 || metadata.coreKeys?.count == 13)
        }
        var setName: String { metadata.evaluationSet ?? "test" }
        var adapterName: String? { metadata.adapter?.name }
    }

    private struct Loaded {
        let name: String
        let report: Saved
        let examples: [Int: ExtractionExample]
        let isPrivate: Bool
    }

    private static let schema = try! DatasetFiles.schema()

    /// Prints a measured number and, if the environment variable `SAFEGUARD_OUT` names a file (pass it to the test run as
    /// `TEST_RUNNER_SAFEGUARD_OUT=<file>`), appends it there, so the numbers can be read from a run.
    private static func report(_ line: String) {
        let text = "[safeguard] " + line
        print(text)
        guard let path = ProcessInfo.processInfo.environment["SAFEGUARD_OUT"],
              let handle = FileHandle(forWritingAtPath: path) ?? {
                  FileManager.default.createFile(atPath: path, contents: nil)
                  return FileHandle(forWritingAtPath: path)
              }()
        else { return }
        handle.seekToEndOfFile()
        handle.write(Data((text + "\n").utf8))
        try? handle.close()
    }

    private static func statements(for set: String) -> [Int: ExtractionExample]? {
        let examples: [ExtractionExample]?
        switch set {
        case "test": examples = try? DatasetFiles.testSplit()
        case "test2": examples = try? DatasetFiles.split("test2", directory: "Dataset/v2")
        default:
            // A real-style set: private, present only on the machine that built it.
            let folder = DatasetFiles.url("RealSet/\(set)")
            guard let data = try? DatasetLoader.externalSetData(named: set, in: folder),
                  let template = try? DatasetFiles.promptTemplate()
            else { return nil }
            examples = try? DatasetLoader.parse(data, template: template, schema: schema, split: set)
        }
        return examples.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) }) }
    }

    private static func reports(in folder: String, isPrivate: Bool) -> [Loaded] {
        let url = DatasetFiles.url(folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let report = try? JSONDecoder().decode(Saved.self, from: data), report.isCoreCall,
                  let examples = statements(for: report.setName)
            else { return nil }
            return Loaded(name: file.lastPathComponent, report: report, examples: examples, isPrivate: isPrivate)
        }
    }

    private static let committed = reports(in: "Results", isPrivate: false)
    private static let privateReports = reports(in: "RealSet/reports", isPrivate: true)
    private static var hasPrivateReports: Bool { !privateReports.isEmpty }
    private static var all: [Loaded] { committed + privateReports }

    private static func outcome(_ text: String, repair: Bool) -> ParseOutcome {
        MetricsParser.parse(text, schema: schema, repairKeys: repair)
    }

    private static func generation(_ text: String) -> GenerationResult {
        GenerationResult(
            text: text, promptTokens: 300, generatedTokens: 70, promptTime: 1.5, generateTime: 3.2,
            totalTime: 4.7, tokensPerSecond: 21.8, activeMemory: 2_000_000_000, peakMemory: 2_500_000_000)
    }

    // MARK: - A. The key repair

    @Test func theCommittedReportsAreFound() {
        // 8 committed reports of the core call hold the answers of the criteria: on the old test the baseline, lora-v1, its
        // two checkpoints and lora-v2; on test 2 the unmodified model, lora-v1 and lora-v2.
        #expect(Self.committed.count == 8, "found \(Self.committed.map(\.name))")
        Self.report("reports of the core call: \(Self.committed.count) committed, \(Self.privateReports.count) private; "
            + "answers \(Self.all.reduce(0) { $0 + $1.report.records.count })")
    }

    /// Criterion 1: the answers with exactly one garbled key become decodable, and fully correct.
    @Test(.enabled(if: SafeguardMeasurementTests.hasPrivateReports))
    func theGarbledKeyAnswersBecomeDecodableAndFullyCorrect() {
        var undecodable = 0, repairable = 0, fullyCorrect = 0, stillUndecodable = 0
        for loaded in Self.all {
            for record in loaded.report.records where !record.isSchemaValid {
                undecodable += 1
                guard let text = record.generation?.text, let example = loaded.examples[record.exampleID] else { continue }
                let repaired = Self.outcome(text, repair: true)
                guard repaired.metrics != nil, let rename = repaired.repair else { stillUndecodable += 1; continue }
                repairable += 1
                // Judged by the evaluation code itself, on the answer with the key renamed.
                let fixed = text.replacingOccurrences(of: "\"\(rename.found)\"", with: "\"\(rename.expected)\"")
                let judged = EvaluationMetrics.makeRecord(
                    example: example, run: record.run, seed: 1, generation: Self.generation(fixed),
                    generationError: nil, thermalBefore: 0, thermalAfter: 0, schema: Self.schema)
                if judged.isFullyCorrect { fullyCorrect += 1 }
            }
        }
        Self.report("A1: undecodable answers \(undecodable); repairable by the position rule \(repairable); "
            + "fully correct after the repair \(fullyCorrect); not repaired \(stillUndecodable)")
        #expect(undecodable == 14)
        #expect(repairable == 12)
        #expect(fullyCorrect == 12)
        #expect(stillUndecodable == 2)           // the two answers that are not JSON stay undecodable: no guessing
    }

    /// Criterion 2: no answer that is already decodable changes.
    @Test func noDecodableAnswerChangesWithTheRepair() {
        var checked = 0, different = 0
        for loaded in Self.all {
            for record in loaded.report.records where record.isSchemaValid {
                guard let text = record.generation?.text else { continue }
                checked += 1
                let strict = Self.outcome(text, repair: false)
                let repairing = Self.outcome(text, repair: true)
                if strict != repairing || repairing.repair != nil { different += 1 }
            }
        }
        Self.report("A2: decodable answers checked \(checked); changed by the repair \(different)")
        #expect(checked > 700)
        #expect(different == 0)
    }

    // MARK: - B. The possible-miss hint

    private struct Tally {
        var answers = 0
        var withMissedAmount = 0, withMissedAmountWarned = 0
        var fullyCorrect = 0, fullyCorrectWarned = 0
        var warned = 0
        var missedByKind: [FieldKind: Int] = [:]
    }

    private static func tally(_ reports: [Loaded]) -> Tally {
        var t = Tally()
        for loaded in reports {
            for record in loaded.report.records {
                guard let text = record.generation?.text, let example = loaded.examples[record.exampleID],
                      let metrics = outcome(text, repair: true).metrics
                else { continue }
                t.answers += 1
                let warned = !UnusedAmounts.unused(in: example.statement, metrics: [metrics], schema: schema).isEmpty
                if warned { t.warned += 1 }
                let missed = record.fields.filter { $0.value == "missed" }.keys
                for key in missed { if let kind = schema.field(key)?.kind { t.missedByKind[kind, default: 0] += 1 } }
                if missed.contains(where: { schema.field($0)?.kind == .amount }) {
                    t.withMissedAmount += 1
                    if warned { t.withMissedAmountWarned += 1 }
                }
                if record.fields.values.allSatisfy({ $0 == "correct" }) {
                    t.fullyCorrect += 1
                    if warned { t.fullyCorrectWarned += 1 }
                }
            }
        }
        return t
    }

    /// The answers of the criteria: the adapters (`lora-v1`, its two checkpoints, `lora-v2`) on the old test and on test 2.
    private static var adapterReports: [Loaded] {
        committed.filter { $0.report.adapterName != nil && ["test", "test2"].contains($0.report.setName) }
    }

    /// Criteria 4 and 5: recall and noise.
    @Test func theHintCatchesMostMissedAmountsAndStaysQuietOnMostGoodAnswers() {
        let reports = Self.adapterReports
        #expect(reports.count == 6, "found \(reports.map(\.name))")
        for loaded in reports {
            let t = Self.tally([loaded])
            Self.report("B \(loaded.report.adapterName ?? "-") on \(loaded.report.setName): answers \(t.answers); "
                + "missed amount \(t.withMissedAmountWarned)/\(t.withMissedAmount); "
                + "fully correct warned \(t.fullyCorrectWarned)/\(t.fullyCorrect)")
        }
        let total = Self.tally(reports)
        let recall = Double(total.withMissedAmountWarned) / Double(max(total.withMissedAmount, 1))
        let noise = Double(total.fullyCorrectWarned) / Double(max(total.fullyCorrect, 1))
        Self.report("B4 recall: \(total.withMissedAmountWarned) of \(total.withMissedAmount) answers with a missed amount "
            + "are warned (\(Int((recall * 100).rounded()))%)")
        Self.report("B5 noise: \(total.fullyCorrectWarned) of \(total.fullyCorrect) fully correct answers are warned "
            + "(\(Int((noise * 100).rounded()))%)")
        #expect(total.withMissedAmount > 50)
        #expect(recall >= 0.85)
        #expect(noise <= 0.40)
    }

    /// Criterion 6: what the hint cannot see, with numbers.
    @Test func theLimitOfTheHintIsCounted() {
        let total = Self.tally(Self.adapterReports)
        let amount = total.missedByKind[.amount, default: 0]
        let percent = total.missedByKind[.percent, default: 0]
        let perShare = total.missedByKind[.perShare, default: 0]
        let all = amount + percent + perShare
        Self.report("B6 missed fields in those answers: \(all); amounts (visible to the hint) \(amount); "
            + "percentages \(percent) and per-share values \(perShare) (invisible to it)")
        #expect(all > 0)
        #expect(amount + percent + perShare == total.missedByKind.values.reduce(0, +))
    }

    /// Criterion 7: on the real sets, how often the hint is shown (counts only, no criterion).
    @Test(.enabled(if: SafeguardMeasurementTests.hasPrivateReports))
    func theHintOnRealText() {
        for loaded in Self.privateReports {
            let t = Self.tally([loaded])
            Self.report("B7 \(loaded.report.adapterName ?? "unmodified") on \(loaded.report.setName): "
                + "answers \(t.answers); hint shown on \(t.warned)")
        }
        #expect(!Self.privateReports.isEmpty)
    }
}
