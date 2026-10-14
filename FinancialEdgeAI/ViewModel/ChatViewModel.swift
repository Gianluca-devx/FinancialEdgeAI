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
            result = try await service.generate(statement: statement)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
}
