//
//  EvaluationViewModel.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import SwiftUI

@MainActor @Observable
final class EvaluationViewModel {
    private let service: LLMService
    private var task: Task<Void, Never>?

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var report: EvaluationReport?
    private(set) var exportURL: URL?
    private(set) var errorMessage: String?

    var modelLoaded: Bool { service.isLoaded }
    var modelName: String { LLMService.modelName }

    init(service: LLMService) {
        self.service = service
    }

    func start() {
        guard !isRunning, modelLoaded else { return }
        isRunning = true
        report = nil
        exportURL = nil
        errorMessage = nil
        completed = 0
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
    }

    private func run() async {
        defer {
            isRunning = false
            task = nil
        }
        do {
            let examples = try DatasetLoader.loadTestSplit()
            let seeds = EvaluationRunner.seeds
            total = examples.count * seeds.count

            let runner = EvaluationRunner(service: service)
            let records = await runner.run(examples: examples, seeds: seeds) { [weak self] done, total in
                self?.completed = done
                self?.total = total
            }
            guard !records.isEmpty else { return }

            let report = try EvaluationRunner.makeReport(
                records: records, examples: examples, seeds: seeds,
                modelLoadSeconds: service.loadDuration)
            self.report = report
            exportURL = try write(report)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the report in the app's Documents folder, from where it can be shared.
    private func write(_ report: EvaluationReport) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateSeparator(.omitted))
        let model = LLMService.modelName.split(separator: "/").last.map(String.init) ?? "model"
        let url = URL.documentsDirectory.appending(path: "baseline-\(model)-\(stamp).json")
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }

    // MARK: - What the screen shows

    /// The headline numbers of the finished evaluation.
    var summaryRows: [MetricRow] {
        guard let summary = report?.summary else { return [] }
        func share(_ count: Int) -> String {
            "\(count) / \(summary.records)  (\(summary.rate(count).formatted(.percent.precision(.fractionLength(0)))))"
        }
        let seconds = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        return [
            MetricRow(label: "Answers", value: "\(summary.records)"),
            MetricRow(label: "Valid JSON", value: share(summary.validJSON)),
            MetricRow(label: "Right 7 keys and types", value: share(summary.schemaValid)),
            MetricRow(label: "All 7 fields correct", value: share(summary.fullyCorrect)),
            MetricRow(label: "Fields correct", value: summary.fieldAccuracy.formatted(.percent.precision(.fractionLength(1)))),
            MetricRow(label: "Needed a code fence", value: share(summary.fenced)),
            MetricRow(label: "Median time per statement", value: "\(summary.medianTotalTime.formatted(seconds)) s"),
            MetricRow(label: "Median tokens per second", value: summary.medianTokensPerSecond.formatted(seconds)),
            MetricRow(label: "Peak memory", value: Int64(summary.peakMemory).formatted(.byteCount(style: .memory))),
            MetricRow(label: "Highest thermal state", value: "\(summary.maxThermalState)  (0 nominal, 3 critical)"),
        ]
    }

    /// How the mistakes are spread: what the model did wrong, over all fields of all answers.
    var mistakeRows: [MetricRow] {
        guard let summary = report?.summary else { return [] }
        let kinds: [FieldOutcome] = [.hallucinated, .missed, .wrongValue, .signError, .unitError, .unparsed]
        return kinds.compactMap { kind in
            let count = summary.fieldOutcomes.values.reduce(0) { $0 + ($1[kind.rawValue] ?? 0) }
            return count == 0 ? nil : MetricRow(label: kind.rawValue, value: "\(count)")
        }
    }
}
