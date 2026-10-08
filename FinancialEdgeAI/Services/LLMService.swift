//
//  LLMService.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import SwiftUI
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

//Here is were the model is choosed
private let modelConfiguration = LLMRegistry.gemma3_1B_qat_4bit

//Here the basic prompt to the LLM
private let instruction =
"""
You are a financial expert that is able to retrive JSON from unstructed text
"""

//Here the accuracy and creativness of the model is chosen
//More the temperature is high, more creative it will be
private let generateParameters = GenerateParameters(temperature: 0.2)

@MainActor @Observable
final class LLMService {
    
    enum State {
        case idle
        case loading(Task<ModelContainer, Error>)
        case loaded(ModelContainer)
    }
    
    public var progress = 0.0
    public var isLoaded: Bool {
        switch state {
        case .idle, .loading: false
        case .loaded: true
        }
    }
    
    private var state = State.idle
    
    private var session: ChatSession?
    
    private func sessionHelper(for model: ModelContainer) {
        self.session = ChatSession(
            model,
            instructions: instruction,
            generateParameters: generateParameters
        )
    }

    func loadModel() async throws {
        switch self.state {
        case.idle:
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
            let model = try await task.value
            sessionHelper(for: model)
            self.state = .loaded(model)

        case .loading(let task):
             _ = try await task.value

        case .loaded:
            return
            
        }
    }

    func respond(to prompt: String) async throws -> String {
        guard let session else {
            throw NSError(
                domain: "LLMService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Model has not been loaded."
                ]
            )
        }

        return try await session.respond(to: prompt)
    }
}
