//
//  KeyRepair.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 19/10/2026.
//
import Foundation

/// Reads a garbled key of a model answer as the key the schema asks for, when there is no doubt about which one.
///
/// An adapted model sometimes writes a valid JSON object in which one key is garbled (`previous6YearEps`,
/// `previous5000`) at the place where `previousYearEps` belongs. The answer is then unusable, though every value is
/// right. The rule is by **position**, not by similarity (`previous5000` is nowhere near `previousYearEps`):
///
/// - the object has exactly as many keys as the schema asks for,
/// - **exactly one** key differs from the schema's key at its position (all the others are where they should be),
/// - and that key is not itself a key of the schema, of either call (so it is not a swap, a duplicate, or a key that
///   belongs to the other call).
///
/// Anything else is not repaired and stays a failure: two keys wrong, a missing or an extra key, another order,
/// a duplicate. The values are not looked at here (the parser still demands a string or null for each).
///
/// The app uses it and says so on the screen; an evaluation does not (it stays strict, so that "decodable" keeps its
/// meaning in every report).
nonisolated enum KeyRepair {

    /// A key that was read as another: `found` is what the model wrote, `expected` the schema's key at that position.
    struct Rename: Equatable, Sendable {
        let found: String
        let expected: String
        /// 1-based position in the answer.
        let position: Int
    }

    /// The rename that makes the keys of `json` (a JSON object as text) those of `expected`, or `nil`.
    /// `alsoKnown` are the keys of the schema that this call does not ask for (the other call's): a key found at
    /// the wrong place that is one of them is not a garbled key.
    static func rename(inJSON json: String, expected: [String], alsoKnown: [String] = []) -> Rename? {
        guard let found = topLevelKeys(of: json), found.count == expected.count else { return nil }
        let known = Set(expected + alsoKnown)
        let differing = found.indices.filter { found[$0] != expected[$0] }
        guard differing.count == 1, let index = differing.first, !known.contains(found[index]) else { return nil }
        return Rename(found: found[index], expected: expected[index], position: index + 1)
    }

    /// The keys of the top-level object of `json`, in the order they are written (a dictionary would lose it).
    /// `nil` if the text is not one JSON object. Values are skipped, whatever they are.
    static func topLevelKeys(of json: String) -> [String]? {
        var scanner = KeyScanner(json)
        return scanner.keys()
    }

    private struct KeyScanner {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) { characters = Array(text) }

        private var current: Character? { index < characters.count ? characters[index] : nil }

        private mutating func skipWhitespace() {
            while let c = current, c.isWhitespace { index += 1 }
        }

        mutating func keys() -> [String]? {
            skipWhitespace()
            guard current == "{" else { return nil }
            index += 1
            var keys: [String] = []
            skipWhitespace()
            if current == "}" { return trailingIsEmpty(after: 1) ? keys : nil }
            while true {
                skipWhitespace()
                guard let key = string() else { return nil }
                keys.append(key)
                skipWhitespace()
                guard current == ":" else { return nil }
                index += 1
                skipWhitespace()
                guard skipValue() else { return nil }
                skipWhitespace()
                switch current {
                case ",": index += 1
                case "}":
                    index += 1
                    return trailingIsEmpty(after: 0) ? keys : nil
                default: return nil
                }
            }
        }

        private mutating func trailingIsEmpty(after skip: Int) -> Bool {
            index += skip
            skipWhitespace()
            return current == nil
        }

        /// A JSON string literal at the current position, decoded.
        private mutating func string() -> String? {
            guard current == "\"" else { return nil }
            let start = index
            index += 1
            while let c = current {
                if c == "\\" { index += 2; continue }
                index += 1
                if c == "\"" {
                    let literal = String(characters[start..<index])
                    return try? JSONDecoder().decode(String.self, from: Data(literal.utf8))
                }
            }
            return nil
        }

        /// Moves past one value: a string, an object or array (to its closing bracket), or a literal.
        private mutating func skipValue() -> Bool {
            guard let c = current else { return false }
            if c == "\"" { return string() != nil }
            if c == "{" || c == "[" {
                var depth = 0
                while let d = current {
                    if d == "\"" {
                        guard string() != nil else { return false }
                        continue
                    }
                    index += 1
                    if d == "{" || d == "[" { depth += 1 }
                    if d == "}" || d == "]" {
                        depth -= 1
                        if depth == 0 { return true }
                    }
                }
                return false
            }
            let start = index
            while let d = current, d != ",", d != "}", d != "]", !d.isWhitespace { index += 1 }
            return index > start
        }
    }
}
