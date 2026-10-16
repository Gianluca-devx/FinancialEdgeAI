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
    /// The last statement sent. The extended call (the balance sheet) runs on it, because the
    /// text field is cleared after Send.
    private(set) var lastStatement: String? = nil
    var extendedResult: GenerationResult? = nil
    var extendedOutcome: ParseOutcome? = nil
    var extendedResponse: String { extendedResult?.text ?? "" }
    var errorMessage: String? = nil
    var hasError: Bool {
        get { errorMessage != nil }
        set { if newValue == false { errorMessage = nil }}
    }
    
    /// Which model is running and how long it took to load.
    var modelInfo: String {
        let model = service.adapter.map { "\(LLMService.modelName) + adapter \($0.summary)" } ?? LLMService.modelName
        guard let seconds = service.loadDuration else { return model }
        return "\(model) - loaded in \(seconds.formatted(.number.precision(.fractionLength(1)))) s"
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

    /// The balance sheet fields of the extended call, once it was made.
    var extendedRows: [MetricRow] {
        guard let metrics = extendedOutcome?.metrics else { return [] }
        return MetricsPresenter.extendedRows(metrics, schema: Schema.bundled)
    }

    var extendedStatus: String? {
        extendedOutcome.map(MetricsPresenter.status(for:))
    }

    /// What the extended call cost.
    var extendedPerformanceSummary: String? {
        guard let extendedResult else { return nil }
        let total = extendedResult.totalTime.formatted(.number.precision(.fractionLength(1)))
        return "Balance sheet: \(extendedResult.generatedTokens) tokens - total \(total) s"
    }

    /// What code calculated from the fields. The model never writes these. The ratios that need the
    /// balance sheet appear once the extended call was made.
    var derivedRows: [MetricRow] {
        let core = outcome?.metrics
        let extended = extendedOutcome?.metrics
        guard core != nil || extended != nil else { return [] }
        let empty = FinancialMetrics(texts: [:], values: [:])
        let metrics = (core ?? empty).merged(with: extended ?? empty)
        return MetricsPresenter.derivedRows(metrics, schema: Schema.bundled, includeExtended: extended != nil)
    }

    /// The balance sheet button: after a first Send, once, when nothing else is running.
    var canAskExtended: Bool {
        modelLoaded && !isResponding && lastStatement != nil && extendedOutcome == nil
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
        lastStatement = statement
        // A new statement: the balance sheet of the previous one no longer applies.
        extendedResult = nil
        extendedOutcome = nil
        defer { isResponding = false }

        do {
            let generated = try await service.generate(statement: statement)
            result = generated
            outcome = MetricsParser.parse(generated.text, schema: Schema.bundled)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }

    /// The extended call: the balance sheet fields of the last statement, with its own prompt.
    /// It does not depend on the answer of the core call.
    func askExtended() async {
        guard canAskExtended, let statement = lastStatement else { return }
        isResponding = true
        errorMessage = nil
        defer { isResponding = false }

        do {
            let generated = try await service.generate(statement: statement, tier: .extended)
            extendedResult = generated
            extendedOutcome = MetricsParser.parse(generated.text, schema: Schema.bundled, tier: .extended)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
}
