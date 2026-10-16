//
//  LLMService.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import SwiftUI
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

//Here is were the model is choosed
private let modelConfiguration = LLMRegistry.qwen3_4b_4bit

//Here the accuracy and creativness of the model is chosen
//More the temperature is high, more creative it will be
//maxTokens stops an answer that never ends. 13 fields copied as strings need about 180 tokens, so
//the limit is 384 (it was 256 for the 7 numbers of v1.1.0).
enum GenerationSettings {
    static let temperature: Float = 0.2
    static let maxTokens = 384
}

private let generateParameters = GenerateParameters(
    maxTokens: GenerationSettings.maxTokens,
    temperature: GenerationSettings.temperature
)

enum LLMServiceError: LocalizedError {
    case modelNotLoaded
    case unsupportedOnSimulator

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Model has not been loaded."
        case .unsupportedOnSimulator: "MLX needs a physical device: the simulator has no GPU that MLX can use. Run the app on an iPhone."
        }
    }
}

@MainActor @Observable
final class LLMService {
    
    enum State {
        case idle
        case loading(Task<ModelContainer, Error>)
        case loaded(ModelContainer)
    }
    
    static let modelName = modelConfiguration.name
    
    public var progress = 0.0
    public var isLoaded: Bool {
        switch state {
        case .idle, .loading: false
        case .loaded: true
        }
    }
    
    /// Seconds the last successful load took. It includes the download the first time.
    private(set) var loadDuration: TimeInterval?
    
    private var state = State.idle

    func loadModel() async throws {
        #if targetEnvironment(simulator)
        throw LLMServiceError.unsupportedOnSimulator
        #else
        switch self.state {
        case.idle:
            let started = ContinuousClock.now
            let task = Task {
                try await #huggingFaceLoadModelContainer(configuration: modelConfiguration) {
                    value in
                    Task {
                        @MainActor in
                        self.progress = value.fractionCompleted
                        
                    }
                }
            }
            
            self.state = .loading(task)
            do {
                let model = try await task.value
                self.loadDuration = seconds(since: started)
                self.state = .loaded(model)
            } catch {
                // Back to idle, otherwise Retry would await the same failed task forever.
                self.state = .idle
                self.progress = 0
                throw error
            }

        case .loading(let task):
             _ = try await task.value

        case .loaded:
            return
            
        }
        #endif
    }

    /// Runs one extraction. Every call uses a new session, because a `ChatSession` remembers
    /// the conversation and the statements must not influence each other.
    func generate(statement: String, seed: UInt64? = nil) async throws -> GenerationResult {
        guard case .loaded(let model) = state else {
            throw LLMServiceError.modelNotLoaded
        }

        var parameters = generateParameters
        parameters.seed = seed

        let session = ChatSession(
            model,
            instructions: ExtractionPrompt.system,
            generateParameters: parameters,
            // Qwen3 can write its reasoning before the answer. Extraction needs only the JSON.
            additionalContext: ["enable_thinking": false]
        )

        let started = ContinuousClock.now
        var text = ""
        var info: GenerateCompletionInfo?
        for try await item in session.streamDetails(to: ExtractionPrompt.userPrompt(for: statement)) {
            switch item {
            case .chunk(let chunk): text += chunk
            case .info(let completion): info = completion
            default: break
            }
        }
        let totalTime = seconds(since: started)
        let memory = Memory.snapshot()
        let tokensPerSecond = info?.tokensPerSecond ?? 0

        return GenerationResult(
            text: text,
            promptTokens: info?.promptTokenCount ?? 0,
            generatedTokens: info?.generationTokenCount ?? 0,
            promptTime: info?.promptTime ?? 0,
            generateTime: info?.generateTime ?? 0,
            totalTime: totalTime,
            tokensPerSecond: tokensPerSecond.isFinite ? tokensPerSecond : 0,
            activeMemory: memory.activeMemory,
            peakMemory: memory.peakMemory
        )
    }

    private func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}
