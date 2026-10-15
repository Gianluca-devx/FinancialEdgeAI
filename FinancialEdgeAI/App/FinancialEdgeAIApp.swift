//
//  FinancialEdgeAIApp.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import SwiftUI
import UIKit
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
            // iOS does not allow GPU work in the background, and MLX stops the app with a fatal
            // error if it is attempted. A locked screen sends the app to the background, so the
            // screen must stay on while the evaluation runs. This lives here, not in a tab,
            // because a tab only exists while it is on screen.
            .onChange(of: evaluationViewModel.isRunning) { _, isRunning in
                UIApplication.shared.isIdleTimerDisabled = isRunning
            }
        }
    }
}
