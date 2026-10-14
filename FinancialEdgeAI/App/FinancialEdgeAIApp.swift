//
//  FinancialEdgeAIApp.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import SwiftUI
import MLX

@main
struct FinancialEdgeAIApp: App {
    
    @State private var chatViewModel: ChatViewModel
    @State private var evaluationViewModel: EvaluationViewModel
    
    init() {
        Memory.cacheLimit = 20 * 1024 * 1024
        
        // One service, so the model is in memory once and both screens use it.
        let service = LLMService()
        _chatViewModel = State(initialValue: ChatViewModel(service: service))
        _evaluationViewModel = State(initialValue: EvaluationViewModel(service: service))
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Extract", systemImage: "text.magnifyingglass") {
                    ContentView(viewModel: chatViewModel)
                }
                Tab("Evaluate", systemImage: "chart.bar") {
                    EvaluationView(viewModel: evaluationViewModel)
                }
            }
        }
    }
}
