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
    var response: String = ""
    var isResponding: Bool = false
    var errorMessage: String? = nil
    var hasError: Bool {
        get { errorMessage != nil }
        set { if newValue == false { errorMessage = nil }}
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
    
    func sendMessage(to message: String) async {
        guard isResponding == false && modelLoaded == true else { return }
        isResponding = true
        errorMessage = nil
        textInput = ""
        defer { isResponding = false }

        do {
            response = try await service.respond(to: message)
        } catch {
            errorMessage = "An Error Occurred: \(error.localizedDescription)"
        }
    }
    
}
