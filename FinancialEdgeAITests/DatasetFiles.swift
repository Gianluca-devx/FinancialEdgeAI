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

    static func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    static func schema() throws -> Schema {
        try Schema(data: Data(contentsOf: url("Dataset/schema.json")))
    }

    /// The prompt of the core call or of the extended call.
    static func promptTemplate(tier: FieldTier = .core) throws -> PromptTemplate {
        let file = tier == .core ? "prompt_template.txt" : "prompt_template_extended.txt"
        let text = try text("Dataset/\(file)").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = PromptTemplate(text: text) else { throw DatasetError.invalidTemplate }
        return template
    }

    /// The chat file of a split for a tier: `test.jsonl` or `test.extended.jsonl`.
    static func chatFile(_ split: String, tier: FieldTier) -> String {
        tier == .core ? "Dataset/\(split).jsonl" : "Dataset/\(split).extended.jsonl"
    }

    /// A whole split with its labels: `train`, `valid` or `test`, for the core call or the extended call.
    static func split(_ name: String, tier: FieldTier = .core) throws -> [ExtractionExample] {
        try DatasetLoader.parse(
            jsonl: text(chatFile(name, tier: tier)),
            labelsJSONL: text("Dataset/\(name).labels.jsonl"),
            indexCSV: text("Dataset/index.csv"),
            template: promptTemplate(tier: tier),
            schema: schema(),
            split: name,
            tier: tier)
    }

    static func testSplit(tier: FieldTier = .core) throws -> [ExtractionExample] {
        try split("test", tier: tier)
    }

    /// The raw JSON of every assistant message of a split, one per line of the file.
    static func assistantMessages(of split: String, tier: FieldTier = .core) throws -> [String] {
        struct Line: Decodable {
            struct Message: Decodable {
                let role: String
                let content: String
            }
            let messages: [Message]
        }
        return try text(chatFile(split, tier: tier)).split(separator: "\n").map { line in
            let decoded = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
            return decoded.messages.first { $0.role == "assistant" }?.content ?? ""
        }
    }

    /// One line of a sidecar: all 18 fields, each null or the printed text with its true value.
    struct LabelLine: Decodable {
        struct Entry: Decodable {
            let text: String
            let value: Double
        }
        let line: Int
        let fields: [String: Entry?]
    }

    static func labelLines(of split: String) throws -> [LabelLine] {
        try text("Dataset/\(split).labels.jsonl").split(separator: "\n").map {
            try JSONDecoder().decode(LabelLine.self, from: Data($0.utf8))
        }
    }
}
