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
                    VStack(alignment: .leading, spacing: 8) {
                        if let status = viewModel.parseStatus {
                            Text(status)
                                .font(.headline)
                        }
                        ForEach(viewModel.metricRows) { row in
                            MetricRowView(row: row)
                        }
                        if viewModel.checkRows.isEmpty == false {
                            Text("Check")
                                .font(.headline)
                                .padding(.top, 8)
                            ForEach(viewModel.checkRows) { row in
                                CheckRowView(row: row)
                            }
                        }
                        if viewModel.extendedOutcome != nil {
                            Text("Balance sheet (second call)")
                                .font(.headline)
                                .padding(.top, 8)
                            if let status = viewModel.extendedStatus {
                                Text(status)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(viewModel.extendedRows) { row in
                                MetricRowView(row: row)
                            }
                        }
                        if viewModel.derivedRows.isEmpty == false {
                            Text("Derived by code")
                                .font(.headline)
                                .padding(.top, 8)
                            ForEach(viewModel.derivedRows) { row in
                                MetricRowView(row: row)
                            }
                        }
                        if viewModel.response.isEmpty == false {
                            DisclosureGroup("Raw answer") {
                                Text(viewModel.response)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        if viewModel.extendedResponse.isEmpty == false {
                            DisclosureGroup("Raw answer, balance sheet") {
                                Text(viewModel.extendedResponse)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let summary = viewModel.performanceSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let summary = viewModel.extendedPerformanceSummary {
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
                    // The second call: debt, equity, current assets and liabilities, cash of the last statement.
                    Button {
                        Task { await viewModel.askExtended() }
                    } label: {
                        Label("Balance sheet", systemImage: "building.columns")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!viewModel.canAskExtended)
                    .accessibilityHint("Asks for debt, equity, current assets, current liabilities and cash of the last statement")
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

/// One label with its value, and the line under it (what was printed, or why it is flagged).
private struct MetricRowView: View {
    let row: MetricRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.label)
                Spacer()
                Text(row.value)
                    .monospacedDigit()
                    .foregroundStyle(row.isWarning ? .orange : .primary)
            }
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(row.isWarning ? .orange : .secondary)
            }
        }
    }
}

/// A line of the "Check" group: an info icon for a hint, a caution icon for a repair. Read as one phrase by VoiceOver.
private struct CheckRowView: View {
    let row: CheckRow
    @ScaledMetric private var iconWidth = 24.0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.kind == .keyRepaired ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(row.kind == .keyRepaired ? .orange : .secondary)
                .frame(width: iconWidth)   // the two icons differ in width: keep the texts aligned
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

#Preview {
    ContentView(viewModel: ChatViewModel(service: LLMService()))
}

#Preview("Check rows") {
    // The rows the presenter builds for an answer with a garbled key and an amount that no field used.
    let schema = Schema.bundled
    var keys = schema.keys(for: .core)
    keys[9] = "previous6YearEps"
    let body = keys.map { "\"\($0)\": null" }.joined(separator: ", ")
    let outcome = MetricsParser.parse("{\(body)}", schema: schema, repairKeys: true)
    let rows = MetricsPresenter.checkRows(
        statement: "Net earnings stood at 11.6 billion dollars; capital spending was $25.6bn.",
        core: outcome, extended: nil, schema: schema)
    return VStack(alignment: .leading, spacing: 8) {
        Text("Check").font(.headline)
        ForEach(rows) { CheckRowView(row: $0) }
    }
    .padding()
}
