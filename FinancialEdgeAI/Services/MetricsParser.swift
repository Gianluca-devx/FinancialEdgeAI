//
//  MetricsParser.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

nonisolated enum ParseFailure: Error, Equatable, Sendable {
    /// There is no `{ ... }` in the answer.
    case noJSON
    /// There is a `{ ... }` but it is not valid JSON.
    case invalidJSON
    /// Valid JSON, but not exactly the core keys with a string or null each.
    case wrongSchema(String)
}

/// What came out of one model answer, with the formatting habits that were needed to read it.
nonisolated struct ParseOutcome: Equatable, Sendable {
    let metrics: FinancialMetrics?
    let failure: ParseFailure?
    /// The answer was wrapped in a Markdown code fence.
    let hadFence: Bool
    /// The answer started with a `<think>...</think>` block.
    let hadThinking: Bool
    /// Keys whose string the parser could not read as a number. They are flagged, not guessed.
    let unreadableKeys: [String]

    /// The text contained a JSON object that parsed, even if its schema was wrong.
    var isValidJSON: Bool {
        switch failure {
        case nil, .wrongSchema: true
        case .noJSON, .invalidJSON: false
        }
    }

    /// Valid JSON with exactly the core keys, each a string or null.
    var isSchemaValid: Bool { metrics != nil }
}

/// Turns the raw text of a model answer into `FinancialMetrics`.
///
/// It is tolerant about what surrounds the JSON (a reasoning block, a Markdown fence, a sentence)
/// and strict about the JSON itself: exactly the core keys of the schema, each a string or null.
/// It records the tolerance it needed, so that "how often does the model break the format" can be
/// measured. The strings are turned into numbers by `ValueParser` (see `FinancialMetrics`).
nonisolated enum MetricsParser {

    /// `tier` says which call the answer belongs to, and so which keys are demanded: the core
    /// answer has exactly the core keys, the extended answer exactly the extended ones.
    static func parse(_ raw: String, schema: Schema, tier: FieldTier = .core) -> ParseOutcome {
        var text = raw

        var hadThinking = false
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
            hadThinking = true
        }
        let hadFence = text.contains("```")

        func outcome(_ metrics: FinancialMetrics?, _ failure: ParseFailure?) -> ParseOutcome {
            ParseOutcome(
                metrics: metrics, failure: failure, hadFence: hadFence, hadThinking: hadThinking,
                unreadableKeys: metrics?.unreadableKeys(in: schema) ?? [])
        }

        guard let open = text.firstIndex(of: "{"),
              let close = text.lastIndex(of: "}"),
              open < close
        else {
            return outcome(nil, .noJSON)
        }
        let json = Data(text[open...close].utf8)

        // JSONDecoder is strict (a trailing comma is an error). JSONSerialization is not.
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: json) else {
            return outcome(nil, .invalidJSON)
        }

        if let problem = schemaProblem(in: object, keys: schema.keys(for: tier)) {
            return outcome(nil, .wrongSchema(problem))
        }
        var texts: [String: String] = [:]
        for (key, value) in object {
            if case .string(let string) = value { texts[key] = string }
        }
        return outcome(FinancialMetrics(texts: texts, schema: schema), nil)
    }

    /// Swift turns a missing optional key into nil, so the keys are checked here.
    private static func schemaProblem(in object: [String: JSONValue], keys: [String]) -> String? {
        let expected = Set(keys)
        let actual = Set(object.keys)
        let missing = expected.subtracting(actual).sorted()
        let extra = actual.subtracting(expected).sorted()
        if !missing.isEmpty || !extra.isEmpty {
            var parts: [String] = []
            if !missing.isEmpty { parts.append("missing \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { parts.append("unexpected \(extra.joined(separator: ", "))") }
            return parts.joined(separator: "; ")
        }
        for key in keys {
            switch object[key] {
            case .null?, .string?: continue
            default: return "\(key) is not a string or null"
            }
        }
        return nil
    }
}

/// Any JSON value. It exists only to check the syntax and the types before the real decoding.
private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}
