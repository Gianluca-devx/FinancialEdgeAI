//
//  ValueParser.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation

/// Turns a value copied from the text ("$726 million", "(1.2) billion", "-4%") into a number.
///
/// The model only copies; this is where units, signs and symbols are resolved, by rules that
/// a unit test can cover. A string it cannot read gives `nil` and is never guessed.
///
/// What a value becomes depends on the kind of the field:
/// - `amount`: billions of USD. An amount with no unit word is read as plain dollars (what is printed).
/// - `percent`: the percentage number, without the "%": "23.5%" is 23.5.
/// - `perShare`: USD per share. No unit word is accepted.
///
/// Only the dollar is understood. Another currency is unreadable on purpose: no conversion is done.
nonisolated enum ValueParser {

    /// The value of a field, with the sign rule of the field (a magnitude is always positive).
    static func parse(_ text: String, field: FieldSpec) -> Double? {
        guard let value = parse(text, kind: field.kind) else { return nil }
        return field.isMagnitude ? abs(value) : value
    }

    /// `nil` if the text is not a value of that kind.
    static func parse(_ text: String, kind: FieldKind) -> Double? {
        guard kind != .ratio, var body = cleaned(text) else { return nil }

        // Parentheses mean negative: "(1.2) billion" or "($1.2 billion)". One pair, in order.
        var negative = false
        let opening = body.filter { $0 == "(" }.count
        let closing = body.filter { $0 == ")" }.count
        if opening > 0 || closing > 0 {
            guard opening == 1, closing == 1,
                  let open = body.firstIndex(of: "("), let close = body.firstIndex(of: ")"), open < close
            else { return nil }
            body.remove(at: close)
            body.remove(at: open)
            negative = true
        }

        let range = NSRange(body.startIndex..., in: body)
        guard let match = pattern.firstMatch(in: body, range: range) else { return nil }
        func group(_ name: String) -> String? {
            let found = match.range(withName: name)
            guard found.location != NSNotFound, let swiftRange = Range(found, in: body) else { return nil }
            return String(body[swiftRange]).lowercased()
        }

        // A sign before and after the currency symbol, or a sign inside parentheses, is ambiguous.
        let signs = [group("signBefore"), group("signAfter")].compactMap { $0 }
        guard signs.count <= 1 else { return nil }
        if signs.first == "-" {
            guard !negative else { return nil }
            negative = true
        }

        let hasCurrency = group("currencyBefore") != nil || group("currencyAfter") != nil
        if group("currencyBefore") != nil && group("currencyAfter") != nil { return nil }
        let unit = group("unit")

        guard let number = group("number"),
              let digits = Decimal(string: number.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }

        var value: Decimal
        switch kind {
        case .amount:
            if let unit, percentWords.contains(unit) { return nil }
            guard let factor = billionsPerUnit(of: unit) else { return nil }
            value = digits * factor
        case .percent:
            guard !hasCurrency else { return nil }
            if let unit, !percentWords.contains(unit) { return nil }
            value = digits
        case .perShare:
            guard unit == nil else { return nil }
            value = digits
        case .ratio:
            return nil
        }
        if negative { value = -value }
        return NSDecimalNumber(decimal: value).doubleValue
    }

    // MARK: - Details

    private static let percentWords: Set<String> = ["%", "percent", "per cent"]

    /// How many billions one unit of the written scale is. No scale word: one plain dollar.
    private static func billionsPerUnit(of unit: String?) -> Decimal? {
        guard let unit else { return Decimal(string: "0.000000001") }
        switch unit {
        case "thousand", "k": return Decimal(string: "0.000001")
        case "million", "mn", "mm", "m": return Decimal(string: "0.001")
        case "billion", "bn", "b": return 1
        case "trillion", "tn", "t": return 1000
        default: return nil
        }
    }

    /// Trims spaces and quotes, normalises the minus signs, drops the punctuation after the value.
    private static func cleaned(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = body.last, ".,;:".contains(last) { body.removeLast() }
        body = body.replacingOccurrences(of: "\u{2212}", with: "-")   // minus sign
            .replacingOccurrences(of: "\u{2013}", with: "-")          // en dash
            .replacingOccurrences(of: "\u{2014}", with: "-")          // em dash
        return body.isEmpty ? nil : body
    }

    private static let pattern: NSRegularExpression = {
        let number = #"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+"#
        let unit = #"thousand|million|billion|trillion|bn|mn|mm|tn|k|m|b|t|%|percent|per cent"#
        let source = #"^(?<signBefore>[-+])?\s*(?<currencyBefore>us\$|usd|\$)?\s*(?<signAfter>[-+])?\s*"#
            + #"(?<number>"# + number + #")\s*(?<unit>"# + unit + #")?\s*(?<currencyAfter>dollars?|usd)?$"#
        // The pattern is a constant: a failure here is a programming error.
        return try! NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }()
}
