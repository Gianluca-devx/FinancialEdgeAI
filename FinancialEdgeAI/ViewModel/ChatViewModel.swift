//
//  ChatViewModel.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 05/10/2026.
//
import SwiftUI

/// One line of the decoded result, ready to show.
struct MetricRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

@MainActor @Observable
class ChatViewModel {
    private let service: LLMService

    var textInput: String = ""
    var progress: Double { service.progress }
    var modelLoaded: Bool { service.isLoaded }
    var result: GenerationResult? = nil
    var outcome: ParseOutcome? = nil
    var response: String { result?.text ?? "" }
    var isResponding: Bool = false
    var errorMessage: String? = nil
    var hasError: Bool {
        get { errorMessage != nil }
        set { if newValue == false { errorMessage = nil }}
    }
    
    /// Which model is running and how long it took to load.
    var modelInfo: String {
        guard let seconds = service.loadDuration else { return LLMService.modelName }
        return "\(LLMService.modelName) - loaded in \(seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }
    
    /// What the last answer cost: tokens, speed, time to first token, total time, memory.
    var performanceSummary: String? {
        guard let result else { return nil }
        let speed = result.tokensPerSecond.formatted(.number.precision(.fractionLength(1)))
        let firstToken = result.promptTime.formatted(.number.precision(.fractionLength(2)))
        let total = result.totalTime.formatted(.number.precision(.fractionLength(1)))
        let peak = Int64(result.peakMemory).formatted(.byteCount(style: .memory))
        return "\(result.generatedTokens) tokens - \(speed) tokens/s - first token \(firstToken) s - total \(total) s - peak memory \(peak)"
    }
    
    /// Whether the answer could be read, and what had to be skipped to read it.
    var parseStatus: String? {
        guard let outcome else { return nil }
        switch outcome.failure {
        case nil:
            let skipped = [outcome.hadThinking ? "a reasoning block" : nil,
                           outcome.hadFence ? "a code fence" : nil].compactMap { $0 }
            return skipped.isEmpty ? "Decoded" : "Decoded, after skipping \(skipped.joined(separator: " and "))"
        case .noJSON:
            return "No JSON found in the answer"
        case .invalidJSON:
            return "The answer is not valid JSON"
        case .wrongSchema(let problem):
            return "Valid JSON, wrong schema: \(problem)"
        }
    }
    
    /// The seven decoded values. A missing value is shown as null, not hidden.
    var metricRows: [MetricRow] {
        guard let metrics = outcome?.metrics else { return [] }
        func show(_ value: Double?) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? "null"
        }
        return [
            MetricRow(label: "Revenue", value: show(metrics.revenue)),
            MetricRow(label: "Revenue growth", value: show(metrics.revenueGrowth)),
            MetricRow(label: "Operating income", value: show(metrics.operatingIncome)),
            MetricRow(label: "Operating income growth", value: show(metrics.operatingIncomeGrowth)),
            MetricRow(label: "Net income", value: show(metrics.netIncome)),
            MetricRow(label: "Net income growth", value: show(metrics.netIncomeGrowth)),
            MetricRow(label: "Previous-year net income", value: show(metrics.previousYearNetIncome)),
        ]
    }
    
    init(service: LLMService) {
        self.service = service
    }
    
    func loadModel() async {
        errorMessage = nil
        do {
            try await service.loadModel()
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
    func useSampleStatement() {
        textInput = ExtractionPrompt.sampleStatement
    }
    
    func sendMessage(to statement: String) async {
        guard isResponding == false && modelLoaded == true else { return }
        isResponding = true
        errorMessage = nil
        textInput = ""
        defer { isResponding = false }

        do {
            let generated = try await service.generate(statement: statement)
            result = generated
            outcome = MetricsParser.parse(generated.text)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
}
