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
                if viewModel.progress > 0 && viewModel.progress < 1 {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .padding()
                    Text("Downloading model... \(Int(viewModel.progress * 100))%")
                } else {
                    ProgressView()
                        .padding()
                    Text(viewModel.progress >= 1 ? "Loading model into memory..." : "Connecting...")
                }
            } else {
                Text(viewModel.modelInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(viewModel.response)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if let summary = viewModel.performanceSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.isResponding {
                    ProgressView()
                }
                HStack {
                    TextField("Financial statement", text: $viewModel.textInput, axis: .vertical)
                        .lineLimit(1...4)
                    Button("Sample") {
                        viewModel.useSampleStatement()
                    }
                    Button("Send") {
                        Task { await viewModel.sendMessage(to: viewModel.textInput) }
                    }
                    .disabled(viewModel.isResponding || viewModel.textInput.isEmpty)
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
