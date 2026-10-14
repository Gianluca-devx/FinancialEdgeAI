//
//  PromptTemplate.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// The user prompt with a hole where the statement goes.
///
/// It works in both directions: it builds the prompt for a statement, and it recovers the
/// statement from a prompt (the dataset stores the full prompt of every example).
struct PromptTemplate: Sendable, Equatable {
    static let placeholder = "<<STATEMENT>>"

    let prefix: String
    let suffix: String

    /// Returns nil unless the text contains the placeholder exactly once.
    init?(text: String) {
        let parts = text.components(separatedBy: Self.placeholder)
        guard parts.count == 2 else { return nil }
        prefix = parts[0]
        suffix = parts[1]
    }

    func render(_ statement: String) -> String {
        prefix + statement + suffix
    }

    /// The statement inside a prompt built from this template, or nil if the prompt does not match.
    func statement(in prompt: String) -> String? {
        guard prompt.hasPrefix(prefix), prompt.hasSuffix(suffix),
              prompt.count >= prefix.count + suffix.count
        else { return nil }
        return String(prompt.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
