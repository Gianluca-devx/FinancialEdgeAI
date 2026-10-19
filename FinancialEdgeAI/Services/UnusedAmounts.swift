//
//  UnusedAmounts.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 19/10/2026.
//
import Foundation

/// The amounts in a statement that no extracted field used: a hint that the model may have left a value out.
///
/// A model that answers `null` for a value the text states fails silently: the screen shows an empty field,
/// which looks like a statement that does not give the value. This finds, in the statement, every amount written with a
/// unit word (`$46.9 billion`, `USD 11.6 billion`, `11.6 billion dollars`, `$25.6bn`, `$924 million`, `$1,817M`),
/// reads it with the same rules as `ValueParser`, and keeps those whose value is **not equal to any amount that was
/// extracted** (core fields and, when the balance sheet call was made, its fields too).
///
/// It never changes a value. It is a hint, and it is noisy on purpose: an amount that is not a field of the schema (total
/// assets, free cash flow, guidance) is also "unused". What it cannot see: a missed percentage (growth) or per-share
/// value, because only amounts with a unit word are looked for; bare numbers and `$85.90` are not amounts here.
nonisolated enum UnusedAmounts {

    /// An amount as printed in the statement, and its value in billions of USD.
    struct Amount: Equatable, Sendable {
        let text: String
        let billions: Double
    }

    /// The amounts of the statement that are not equal to the value of any amount field of `metrics`.
    /// Each distinct value is listed once, in the order of the text.
    static func unused(in statement: String, metrics: [FinancialMetrics], schema: Schema) -> [Amount] {
        var used: [Double] = []
        for metric in metrics {
            for field in schema.fields where field.kind == .amount {
                if let value = metric.value(forKey: field.key) { used.append(value) }
            }
        }
        var seen: [Double] = []
        var result: [Amount] = []
        for amount in amounts(in: statement) {
            guard !used.contains(where: { matches($0, amount.billions) }),
                  !seen.contains(where: { matches($0, amount.billions) })
            else { continue }
            seen.append(amount.billions)
            result.append(amount)
        }
        return result
    }

    /// Every amount with a unit word in the statement, in the order of the text.
    static func amounts(in statement: String) -> [Amount] {
        let whole = NSRange(statement.startIndex..., in: statement)
        return pattern.matches(in: statement, range: whole).compactMap { match in
            guard let range = Range(match.range, in: statement) else { return nil }
            let text = String(statement[range])
            guard let value = ValueParser.parse(text, kind: .amount) else { return nil }
            return Amount(text: text, billions: value)
        }
    }

    private static func matches(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(1, abs(a))
    }

    /// `$ 46.9 billion`, `USD41 billion`, `US$11.3 billion`, `$25.6bn`, `$1,817M`, or `46.9 billion` / `11.3 billion USD` /
    /// `11.6 billion dollars` (no currency sign in front, so the unit word must be spelled out).
    private static let pattern: NSRegularExpression = {
        let number = #"\d[\d,]*(?:\.\d+)?"#
        let source = #"(?:US\$|USD|\$)\s?"# + number + #"\s?(?:billion|million|thousand|bn|mn|b|m)\b"#
            + #"|"# + number + #"\s?(?:billion|million)\b(?:\s?(?:USD|dollars))?"#
        // The pattern is a constant: a failure here is a programming error.
        return try! NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }()
}
