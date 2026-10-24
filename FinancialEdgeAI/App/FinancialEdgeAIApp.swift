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
        // MLX aborts the app as soon as it starts on the simulator (no usable GPU), so it is
        // not touched there. LLMService.loadModel() explains this to the user.
        #if !targetEnvironment(simulator)
        Memory.cacheLimit = 20 * 1024 * 1024
        #endif
        
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
                .badge("WIP")
            }
            // iOS does not allow GPU work in the background, and MLX stops the app with a fatal
            // error if it is attempted. A locked screen sends the app to the background, so the
            // screen must stay on while the evaluation runs. This lives here, not in a tab,
            // because a tab only exists while it is on screen.
            .onChange(of: evaluationViewModel.isRunning) { _, isRunning in
                UIApplication.shared.isIdleTimerDisabled = isRunning
            }
            // Development only: launched with `-autoRunEvaluation YES` (a launch argument, so
            // `xcrun devicectl device process launch ... -autoRunEvaluation YES`), the app starts the
            // evaluation by itself once the model is loaded. Without the argument nothing happens.
            .task {
                guard UserDefaults.standard.bool(forKey: "autoRunEvaluation") else { return }
                while !chatViewModel.modelLoaded {
                    try? await Task.sleep(for: .seconds(1))
                }
                // `-evaluationTier extended` evaluates the balance sheet call instead of the core call.
                if UserDefaults.standard.string(forKey: "evaluationTier") == FieldTier.extended.rawValue {
                    evaluationViewModel.tier = .extended
                }
                // `-evaluationSet test2|test3` (or the name of a set copied to Documents/EvalSets) chooses the statements.
                if let name = UserDefaults.standard.string(forKey: "evaluationSet") {
                    evaluationViewModel.evaluationSet = EvaluationSet(name: name)
                }
                evaluationViewModel.start()
            }
        }
    }
}
