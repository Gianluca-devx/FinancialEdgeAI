//
//  ContentView.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ChatViewModel
    
    var body: some View {
        VStack {
            if viewModel.modelLoaded == false {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .padding()
                Text("Loading...")
            } else {
                Text(viewModel.response)
                HStack {
                    TextField("Enter your prompt", text: $viewModel.textInput)
                    Button("Send") {
                        Task { await viewModel.sendMessage(to: viewModel.textInput) }
                    }
                    .disabled(viewModel.isResponding)
                }
            }
        }
        .task {
            await viewModel.loadModel()
        }
        .alert("Fail to load model", isPresented: $viewModel.hasError) {
            Button("Retry") {
                Task { await viewModel.loadModel() }
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .padding()
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel(service: LLMService()))
}
