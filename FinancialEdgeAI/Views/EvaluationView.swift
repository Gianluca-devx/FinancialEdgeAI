//
//  EvaluationView.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import SwiftUI

struct EvaluationView: View {
    let viewModel: EvaluationViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Work in progress")
                                .font(.headline)
                            Text("A development tool to measure the model on the device. It will not be part of the final app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text(viewModel.modelName)
                    Text("30 test statements, 3 runs each")
                        .foregroundStyle(.secondary)

                    if viewModel.isRunning {
                        ProgressView(value: Double(viewModel.completed), total: Double(max(viewModel.total, 1)))
                        Text("\(viewModel.completed) of \(viewModel.total) answers")
                            .monospacedDigit()
                        Button("Cancel", role: .destructive) {
                            viewModel.cancel()
                        }
                    } else if viewModel.modelLoaded {
                        Button("Start evaluation") {
                            viewModel.start()
                        }
                    } else {
                        Text("Waiting for the model to load...")
                            .foregroundStyle(.secondary)
                    }

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("The screen stays on while it runs. Keep the phone plugged in.")
                }

                if !viewModel.summaryRows.isEmpty {
                    Section("Results") {
                        ForEach(viewModel.summaryRows) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                    }
                    Section("Mistakes, counted per field") {
                        ForEach(viewModel.mistakeRows) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                    }
                }

                if let url = viewModel.exportURL {
                    Section("Export") {
                        ShareLink(item: url) {
                            Label("Share the full report (JSON)", systemImage: "square.and.arrow.up")
                        }
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Evaluation")
        }
    }
}

#Preview {
    EvaluationView(viewModel: EvaluationViewModel(service: LLMService()))
}
