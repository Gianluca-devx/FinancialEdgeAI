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
    case labelCountMismatch(statements: Int, labels: Int)
    case unsupportedTier(set: String, tier: String)
    case missingExternalSet(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "The bundled file \(name) is missing."
        case .invalidTemplate: "The prompt template must contain \(PromptTemplate.placeholder) exactly once."
        case .malformedLine(let line, let reason): "Line \(line) of the dataset is malformed: \(reason)"
        case .labelCountMismatch(let statements, let labels):
            "The split has \(statements) statements but \(labels) label lines."
        case .unsupportedTier(let set, let tier): "The set \(set) has no \(tier) call."
        case .missingExternalSet(let path): "The evaluation set was not found: \(path)"
        }
    }
}

/// Reads a dataset split (`test.jsonl`), its sidecar (`test.labels.jsonl`) and its `index.csv`
/// into examples.
///
/// The expected values come from the sidecar: they are the true numbers written by the generator,
/// not the result of parsing a text. That is what lets the tests check the parser.
enum DatasetLoader {

    /// The bytes of a set's three files: what is parsed, and what the report's hash is made of.
    struct SetData: Sendable {
        let chat: Data
        let labels: Data
        let index: Data

        /// The statements with their labels, as hashed in a report.
        var hashed: Data { chat + labels }
    }

    /// Reads an external set from `directory` (`<name>.jsonl`, `<name>.labels.jsonl`, `index.csv`). Pure: no bundle.
    static func externalSetData(named name: String, in directory: URL) throws -> SetData {
        let files = EvaluationSet.externalFiles(named: name)
        func read(_ file: String) throws -> Data {
            let url = directory.appending(path: file)
            guard let data = try? Data(contentsOf: url) else { throw DatasetError.missingExternalSet(url.path) }
            return data
        }
        return SetData(chat: try read(files.chat), labels: try read(files.labels), index: try read(files.index))
    }

    /// Parses a set's files with the core prompt, for the keys of `tier` (an external set is core only).
    static func parse(
        _ data: SetData, template: PromptTemplate, schema: Schema, split: String, tier: FieldTier = .core
    ) throws -> [ExtractionExample] {
        try parse(
            jsonl: String(decoding: data.chat, as: UTF8.self),
            labelsJSONL: String(decoding: data.labels, as: UTF8.self),
            indexCSV: String(decoding: data.index, as: UTF8.self),
            template: template, schema: schema, split: split, tier: tier)
    }

    /// Pure and testable: no bundle access.
    /// `tier` says which call the chat file belongs to (`test.jsonl` or `test.extended.jsonl`, with the
    /// matching `template`): the expected values are those of the keys of that tier.
    static func parse(
        jsonl: String, labelsJSONL: String, indexCSV: String,
        template: PromptTemplate, schema: Schema, split: String, tier: FieldTier = .core
    ) throws -> [ExtractionExample] {
        let index = parseIndex(indexCSV, split: split)
        let lines = jsonl.split(whereSeparator: \.isNewline)
        let labelLines = labelsJSONL.split(whereSeparator: \.isNewline)
        guard lines.count == labelLines.count else {
            throw DatasetError.labelCountMismatch(statements: lines.count, labels: labelLines.count)
        }
        var examples: [ExtractionExample] = []

        for (offset, line) in lines.enumerated() {
            let number = offset + 1
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)) else {
                throw DatasetError.malformedLine(number, "not a chat record")
            }
            guard let user = record.messages.first(where: { $0.role == "user" })?.content else {
                throw DatasetError.malformedLine(number, "missing the user message")
            }
            guard let statement = template.statement(in: user) else {
                throw DatasetError.malformedLine(number, "the user message does not match the prompt template")
            }
            guard let labels = try? JSONDecoder().decode(Labels.self, from: Data(labelLines[offset].utf8)),
                  labels.line == number
            else {
                throw DatasetError.malformedLine(number, "the label line is not valid or has another number")
            }

            var texts: [String: String] = [:]
            var values: [String: Double] = [:]
            for key in schema.keys(for: tier) {
                if let entry = labels.fields[key] ?? nil {
                    texts[key] = entry.text
                    values[key] = entry.value
                }
            }
            let meta = index[number]
            examples.append(ExtractionExample(
                id: number, statement: statement,
                expected: FinancialMetrics(texts: texts, values: values),
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

    /// One line of a sidecar: all 18 fields, each null or the printed text with its true value.
    private struct Labels: Decodable {
        struct Entry: Decodable {
            let text: String
            let value: Double
        }
        let line: Int
        let fields: [String: Entry?]
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
