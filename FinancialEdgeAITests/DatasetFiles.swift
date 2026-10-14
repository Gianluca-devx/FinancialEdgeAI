//
//  DatasetFiles.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// Reads the real dataset files from the repository. The tests run in the simulator,
/// which can read the files of the Mac.
enum DatasetFiles {

    /// The repository root: this file is in `FinancialEdgeAITests/`, one level below it.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    static func promptTemplate() throws -> PromptTemplate {
        let text = try String(contentsOf: url("Dataset/prompt_template.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = PromptTemplate(text: text) else { throw DatasetError.invalidTemplate }
        return template
    }

    static func testSplit() throws -> [ExtractionExample] {
        try DatasetLoader.parse(
            jsonl: String(contentsOf: url("Dataset/test.jsonl"), encoding: .utf8),
            indexCSV: String(contentsOf: url("Dataset/index.csv"), encoding: .utf8),
            template: promptTemplate(),
            split: "test")
    }

    /// The raw JSON of every assistant message, one per line of the file.
    static func assistantMessages(in jsonl: String) throws -> [String] {
        struct Line: Decodable {
            struct Message: Decodable {
                let role: String
                let content: String
            }
            let messages: [Message]
        }
        return try jsonl.split(separator: "\n").map { line in
            let decoded = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
            return decoded.messages.first { $0.role == "assistant" }?.content ?? ""
        }
    }
}
