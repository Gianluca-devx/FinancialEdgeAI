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

    /// Which call is evaluated: the core fields or the balance sheet fields. Fixed while a run is on.
    var tier: FieldTier = .core

    /// Which statements are run: the frozen test split by default (`-evaluationSet test2|test3` or another name chooses).
    var evaluationSet: EvaluationSet = .test

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var report: EvaluationReport?
    private(set) var exportURL: URL?
    private(set) var errorMessage: String?

    var modelLoaded: Bool { service.isLoaded }
    var modelName: String { LLMService.modelName }

    /// Which adapter is on the model: the screen says it, because a result belongs to the exact weights.
    var adapterDescription: String {
        service.adapter.map { "Adapter: \($0.summary)" } ?? "Adapter: none (the base model)"
    }

    /// Which statements are on, next to the adapter: a result belongs to the exact set it was measured on.
    var setDescription: String { "Set: \(evaluationSet.name)" }

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
            let tier = self.tier
            let set = self.evaluationSet
            let (examples, setData) = try DatasetLoader.loadSet(set, tier: tier)
            let seeds = EvaluationRunner.seeds
            total = examples.count * seeds.count

            let runner = EvaluationRunner(service: service)
            print("[evaluation] started: \(total) answers, tier \(tier.rawValue), set \(set.name)")
            let records = await runner.run(examples: examples, seeds: seeds, tier: tier) { [weak self] done, total in
                self?.completed = done
                self?.total = total
                if done % 10 == 0 || done == total { print("[evaluation] \(done) of \(total) answers") }
            }
            guard !records.isEmpty else { return }

            let report = try EvaluationRunner.makeReport(
                records: records, examples: examples, seeds: seeds,
                modelLoadSeconds: service.loadDuration, tier: tier, adapter: service.adapter,
                set: set, setData: setData)
            self.report = report
            let url = try write(report, tier: tier, set: set)
            exportURL = url
            print("[evaluation] finished, report: \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
            print("[evaluation] failed: \(error.localizedDescription)")
        }
    }

    /// Saves the report in the app's Documents folder, from where it can be shared.
    private func write(_ report: EvaluationReport, tier: FieldTier, set: EvaluationSet) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateSeparator(.omitted))
        let model = LLMService.modelName.split(separator: "/").last.map(String.init) ?? "model"
        let prefix = (["baseline"] + (tier == .core ? [] : [tier.rawValue]) + (set == .test ? [] : [set.name]))
            .joined(separator: "-")
        let url = URL.documentsDirectory.appending(path: "\(prefix)-\(model)-\(stamp).json")
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
        let fieldCount = report?.metadata.keys.count ?? Schema.bundled.keys(for: tier).count
        return [
            MetricRow(label: "Answers", value: "\(summary.records)"),
            MetricRow(label: "Valid JSON", value: share(summary.validJSON)),
            MetricRow(label: "Right keys and types", value: share(summary.schemaValid)),
            MetricRow(label: "All \(fieldCount) fields correct", value: share(summary.fullyCorrect)),
            MetricRow(label: "Fields correct", value: summary.fieldAccuracy.formatted(.percent.precision(.fractionLength(1)))),
            MetricRow(
                label: "Strings copied exactly",
                value: "\(summary.exactCopies) / \(summary.exactCopiesComparable)"),
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
        let kinds: [FieldOutcome] = [.hallucinated, .missed, .wrongValue, .signError, .unitError, .unreadable, .unparsed]
        return kinds.compactMap { kind in
            let count = summary.fieldOutcomes.values.reduce(0) { $0 + ($1[kind.rawValue] ?? 0) }
            return count == 0 ? nil : MetricRow(label: kind.rawValue, value: "\(count)")
        }
    }
}
