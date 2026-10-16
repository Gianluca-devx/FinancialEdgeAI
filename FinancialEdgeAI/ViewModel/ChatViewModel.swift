//
//  ChatViewModel.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 05/10/2026.
//
import SwiftUI

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
    
    /// Whether the answer could be read, and what had to be skipped or flagged to read it.
    var parseStatus: String? {
        outcome.map(MetricsPresenter.status(for:))
    }
    
    /// The core fields. A missing value is shown as null, not hidden; a string that cannot be read
    /// is shown as it is, with a warning.
    var metricRows: [MetricRow] {
        guard let metrics = outcome?.metrics else { return [] }
        return MetricsPresenter.coreRows(metrics, schema: Schema.bundled)
    }

    /// What code calculated from the core fields. The model never writes these.
    var derivedRows: [MetricRow] {
        guard let metrics = outcome?.metrics else { return [] }
        return MetricsPresenter.derivedRows(metrics, schema: Schema.bundled)
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
            outcome = MetricsParser.parse(generated.text, schema: Schema.bundled)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
}
