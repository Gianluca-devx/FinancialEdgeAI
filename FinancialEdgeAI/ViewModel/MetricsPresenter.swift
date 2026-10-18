//
//  MetricsPresenter.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation

/// One line of the decoded result, ready to show.
nonisolated struct MetricRow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    /// A line under the value: what the model printed, or why the value is flagged.
    let note: String?
    /// The value could not be read. The row shows the raw text instead of a number.
    let isWarning: Bool

    init(id: String? = nil, label: String, value: String, note: String? = nil, isWarning: Bool = false) {
        self.id = id ?? label
        self.label = label
        self.value = value
        self.note = note
        self.isWarning = isWarning
    }
}

/// One line of the "Check" group of the Extract tab: something to know about the answer that is not a field.
nonisolated struct CheckRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// An amount in the text that no field used: the model may have left a value out. A hint.
        case possibleMiss
        /// A garbled key of the answer was read as the schema's key. A caution.
        case keyRepaired
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String

    /// What a screen reader says: the same as the text, in one phrase.
    var accessibilityLabel: String { "\(title). \(detail)" }
}

/// Turns the decoded metrics into the rows of the Extract tab. Pure, so it is covered by unit tests.
///
/// A missing value is shown as "null", not hidden. A value that code calculated is marked as
/// derived. A string that cannot be read is shown as it is, with a warning, and the other rows
/// still appear.
nonisolated enum MetricsPresenter {

    // MARK: - Rows

    /// One row per core field, in the order of the schema.
    static func coreRows(_ metrics: FinancialMetrics, schema: Schema, locale: Locale = .current) -> [MetricRow] {
        rows(for: schema.coreFields, metrics, schema: schema, locale: locale)
    }

    /// One row per extended field (the balance sheet), in the order of the schema.
    static func extendedRows(_ metrics: FinancialMetrics, schema: Schema, locale: Locale = .current) -> [MetricRow] {
        rows(for: schema.extendedFields, metrics, schema: schema, locale: locale)
    }

    private static func rows(
        for fields: [FieldSpec], _ metrics: FinancialMetrics, schema: Schema, locale: Locale
    ) -> [MetricRow] {
        let resolved = metrics.resolved(in: schema)
        return fields.map { field in
            let text = metrics.text(forKey: field.key)
            if let text, let value = metrics.value(forKey: field.key) {
                return MetricRow(
                    id: field.key, label: field.label,
                    value: display(value, kind: field.kind, locale: locale), note: "printed: \(text)")
            }
            if let text {
                return MetricRow(
                    id: field.key, label: field.label, value: text,
                    note: "could not read this value", isWarning: true)
            }
            if let filled = resolved.filled[field.key] {
                return MetricRow(
                    id: field.key, label: field.label,
                    value: display(filled, kind: field.kind, locale: locale),
                    note: "derived from the two amounts, not printed in the text")
            }
            return MetricRow(id: field.key, label: field.label, value: "null")
        }
    }

    /// The derived values whose inputs are all core fields. Those that need the extended tier
    /// (return on equity, debt to equity, current ratio, net debt) wait until the extended call was
    /// made: with `includeExtended` they are listed too (null if an input is missing).
    /// A growth that fills a core field is shown in that field's row, not here.
    static func derivedRows(
        _ metrics: FinancialMetrics, schema: Schema, includeExtended: Bool = false, locale: Locale = .current
    ) -> [MetricRow] {
        let resolved = metrics.resolved(in: schema)
        return schema.derived
            .filter {
                $0.fills == nil
                    && (includeExtended || $0.inputs.allSatisfy { schema.field($0)?.tier == .core })
            }
            .map { spec in
                guard let value = resolved.derived[spec.key] else {
                    return MetricRow(id: spec.key, label: spec.label, value: "null")
                }
                return MetricRow(
                    id: spec.key, label: spec.label,
                    value: display(value, kind: spec.kind, locale: locale), note: "derived")
            }
    }

    // MARK: - Check

    /// What to say about an answer besides its fields (empty when there is nothing to say):
    /// a key that was repaired, and the amounts of the statement that no field used.
    /// `statement` is the text the answer is about; the balance sheet fields count as used once that call was made.
    static func checkRows(
        statement: String?, core: ParseOutcome?, extended: ParseOutcome?, schema: Schema, maxListed: Int = 4
    ) -> [CheckRow] {
        var rows: [CheckRow] = []
        for (name, outcome) in [("core", core), ("extended", extended)] {
            if let repair = outcome?.repair {
                rows.append(CheckRow(
                    id: "key-repaired-\(name)", kind: .keyRepaired, title: "A key was repaired",
                    detail: "The model wrote \(repair.found) where \(repair.expected) belongs (key \(repair.position)); "
                        + "it was read as \(repair.expected)."))
            }
        }
        if let statement, let coreMetrics = core?.metrics {
            let metrics = [coreMetrics] + (extended?.metrics.map { [$0] } ?? [])
            let unused = UnusedAmounts.unused(in: statement, metrics: metrics, schema: schema)
            if !unused.isEmpty {
                let listed = unused.prefix(maxListed).map(\.text).joined(separator: ", ")
                let more = unused.count > maxListed ? " and \(unused.count - maxListed) more" : ""
                let detail = unused.count == 1
                    ? "\(listed) is in the text but in no field."
                    : "\(unused.count) amounts are in the text but in no field: \(listed)\(more)."
                rows.append(CheckRow(id: "possible-miss", kind: .possibleMiss, title: "Possible miss", detail: detail))
            }
        }
        return rows
    }

    // MARK: - Formatting

    static func display(_ value: Double, kind: FieldKind, locale: Locale = .current) -> String {
        switch kind {
        case .amount:
            return "$" + value.formatted(.number.precision(.significantDigits(1...6)).locale(locale)) + " bn"
        case .percent:
            return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "%"
        case .perShare:
            return "$" + value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        case .ratio:
            return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        }
    }

    // MARK: - Status

    /// Whether the answer could be read, and what had to be skipped or flagged to read it.
    static func status(for outcome: ParseOutcome) -> String {
        switch outcome.failure {
        case nil:
            let skipped = [outcome.hadThinking ? "a reasoning block" : nil,
                           outcome.hadFence ? "a code fence" : nil].compactMap { $0 }
            var text = skipped.isEmpty ? "Decoded" : "Decoded, after skipping \(skipped.joined(separator: " and "))"
            if let repair = outcome.repair {
                text += "; key \(repair.found) read as \(repair.expected)"
            }
            let unreadable = outcome.unreadableKeys.count
            if unreadable > 0 {
                text += "; \(unreadable) \(unreadable == 1 ? "value" : "values") could not be read"
            }
            return text
        case .noJSON:
            return "No JSON found in the answer"
        case .invalidJSON:
            return "The answer is not valid JSON"
        case .wrongSchema(let problem):
            return "Valid JSON, wrong schema: \(problem)"
        }
    }
}
