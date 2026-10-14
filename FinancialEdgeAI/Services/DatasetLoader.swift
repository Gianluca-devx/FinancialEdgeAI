//
//  DatasetLoader.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

enum DatasetError: LocalizedError, Equatable {
    case missingResource(String)
    case invalidTemplate
    case malformedLine(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "The bundled file \(name) is missing."
        case .invalidTemplate: "The prompt template must contain \(PromptTemplate.placeholder) exactly once."
        case .malformedLine(let line, let reason): "Line \(line) of the dataset is malformed: \(reason)"
        }
    }
}

/// Reads a dataset split (`test.jsonl`) and its `index.csv` into examples.
enum DatasetLoader {

    /// Pure and testable: no bundle access.
    static func parse(jsonl: String, indexCSV: String, template: PromptTemplate, split: String) throws
        -> [ExtractionExample]
    {
        let index = parseIndex(indexCSV, split: split)
        var examples: [ExtractionExample] = []

        let lines = jsonl.split(whereSeparator: \.isNewline)
        for (offset, line) in lines.enumerated() {
            let number = offset + 1
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)) else {
                throw DatasetError.malformedLine(number, "not a chat record")
            }
            guard let user = record.messages.first(where: { $0.role == "user" })?.content,
                  let assistant = record.messages.first(where: { $0.role == "assistant" })?.content
            else {
                throw DatasetError.malformedLine(number, "missing the user or the assistant message")
            }
            guard let statement = template.statement(in: user) else {
                throw DatasetError.malformedLine(number, "the user message does not match the prompt template")
            }
            guard let expected = try? JSONDecoder().decode(FinancialMetrics.self, from: Data(assistant.utf8)) else {
                throw DatasetError.malformedLine(number, "the label is not a FinancialMetrics JSON")
            }
            let meta = index[number]
            examples.append(ExtractionExample(
                id: number, statement: statement, expected: expected,
                source: meta?.source ?? "unknown",
                scenario: meta?.scenario ?? "unknown",
                pool: meta?.pool ?? "unknown"))
        }
        return examples
    }

    private struct Record: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let messages: [Message]
    }

    private struct IndexRow {
        let source: String
        let scenario: String
        let pool: String
    }

    /// Columns: split,line,source,scenario,pool,unit,distractors. No field is quoted.
    private static func parseIndex(_ csv: String, split: String) -> [Int: IndexRow] {
        var rows: [Int: IndexRow] = [:]
        // Python writes "\r\n", which Swift reads as one character that is not "\n".
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, fields[0] == split, let number = Int(fields[1]) else { continue }
            rows[number] = IndexRow(source: fields[2], scenario: fields[3], pool: fields[4])
        }
        return rows
    }
}
