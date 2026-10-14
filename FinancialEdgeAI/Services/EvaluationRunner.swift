//
//  EvaluationRunner.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import CryptoKit
import Foundation

/// Runs the test split through the model on the device and judges every answer.
@MainActor
final class EvaluationRunner {
    /// One run per seed. Fixed seeds make a run reproducible.
    static let seeds: [UInt64] = [1, 2, 3]

    private let service: LLMService

    init(service: LLMService) {
        self.service = service
    }

    /// Runs every example once per seed. Run 1 covers all the examples before run 2 starts,
    /// so a cancelled evaluation still has complete runs. `progress` receives (done, total).
    func run(
        examples: [ExtractionExample],
        seeds: [UInt64] = EvaluationRunner.seeds,
        progress: (Int, Int) -> Void
    ) async -> [EvaluationRecord] {
        var records: [EvaluationRecord] = []
        let total = examples.count * seeds.count

        for (index, seed) in seeds.enumerated() {
            for example in examples {
                if Task.isCancelled { return records }
                await coolDownIfNeeded()

                let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
                var generation: GenerationResult?
                var generationError: String?
                do {
                    generation = try await service.generate(statement: example.statement, seed: seed)
                } catch {
                    generationError = error.localizedDescription
                }
                let thermalAfter = ProcessInfo.processInfo.thermalState.rawValue

                records.append(EvaluationMetrics.makeRecord(
                    example: example, run: index + 1, seed: seed,
                    generation: generation, generationError: generationError,
                    thermalBefore: thermalBefore, thermalAfter: thermalAfter))
                progress(records.count, total)
            }
        }
        return records
    }

    /// A hot phone slows down and the speed numbers stop meaning anything. Wait while it is
    /// "serious" or worse, for at most two minutes.
    private func coolDownIfNeeded() async {
        var waited = 0
        while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue,
              waited < 120, !Task.isCancelled
        {
            try? await Task.sleep(for: .seconds(10))
            waited += 10
        }
    }

    // MARK: - Report

    static func makeReport(
        records: [EvaluationRecord],
        examples: [ExtractionExample],
        seeds: [UInt64],
        modelLoadSeconds: Double?
    ) throws -> EvaluationReport {
        let prompts = try DatasetLoader.bundledData("system_prompt", "txt")
            + DatasetLoader.bundledData("prompt_template", "txt")
        let testSet = try DatasetLoader.bundledData("test", "jsonl")

        let metadata = EvaluationReport.Metadata(
            date: ISO8601DateFormatter().string(from: .now),
            model: LLMService.modelName,
            device: deviceIdentifier,
            system: "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            temperature: Double(GenerationSettings.temperature),
            maxTokens: GenerationSettings.maxTokens,
            runs: seeds.count,
            seeds: seeds,
            examples: examples.count,
            promptHash: sha256(prompts),
            testSetHash: sha256(testSet),
            modelLoadSeconds: modelLoadSeconds)

        return EvaluationReport(
            metadata: metadata,
            summary: EvaluationMetrics.summarize(records),
            byScenario: EvaluationMetrics.summarize(records, groupedBy: \.scenario),
            byPool: EvaluationMetrics.summarize(records, groupedBy: \.pool),
            records: records)
    }

    /// The model identifier of the hardware, for example "iPhone17,3".
    static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
