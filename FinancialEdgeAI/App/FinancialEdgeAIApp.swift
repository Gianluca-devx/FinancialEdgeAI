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
    
    init() {
        Memory.cacheLimit = 20 * 1024 * 1024
    }
    
    @State var loader = LLMService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
