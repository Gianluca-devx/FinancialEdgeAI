//
//  ChatViewModel.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 05/10/2026.
//
import SwiftUI

@MainActor @Observable
class ChatViewModel {
    var progress: Double = 0
    var modelLoaded: Bool = false
    var response: String = ""
    var errorMessage: String? = nil
    private let service: LLMService
    
    init(service: LLMService) {
        self.service = service
    }
    
    func loadModel() async {
        
    }
    
    func sendMessage(to message: String) async {
        
    }
    
}
