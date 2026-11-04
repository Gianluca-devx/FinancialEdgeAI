//
//  StatementTableReader.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import Foundation

/// The two statements the reader knows.
nonisolated enum StatementKind: String, CaseIterable, Sendable {
    case income
    case cashFlow
}

/// The unit of a statement's amounts, as its header prints it. The raw value is the word the app's `ValueParser` reads.
nonisolated enum StatementUnit: String, Sendable {
    case thousand
    case million
    case billion
}

/// An amount the reader found: the text for the app ("416,161 million", "(8,527) million", "7.46"), the label of the row
/// it came from, and its year.
nonisolated struct StatementAmount: Equatable, Sendable {
    let text: String
    let row: String
    let year: Int
}

/// Why the reader left a field null (T6: abstain rather than guess).
nonisolated enum Abstention: String, Error, CaseIterable, Sendable {
    /// No page was given for the field's statement.
    case noPage
    /// The page has no year header, or not the year the field needs.
    case noYears
    /// No row of the page matches the field.
    case noRow
    /// The matching row has a different number of cells than the header has years.
    case cellCount
    /// Rows that match equally well give different values.
    case ambiguous
    /// A dash where the value should be.
    case dash
    /// Neither statement page prints the unit of its amounts.
    case noUnit
}

/// What the reader found in one report: an amount or the reason for a null, for each of its keys.
nonisolated struct StatementReading: Equatable, Sendable {
    var amounts: [String: StatementAmount] = [:]
    var abstained: [String: Abstention] = [:]
}

/// Phase 2g (`Specs/phase-2g-table-reader.md`): reads the 10 statement amounts of the schema from the rows of an income
/// statement and a cash flow statement, by fixed rules.
///
/// - Columns by their year (T3): the latest year of the header is the current year, the year before it the previous year;
///   an older column is never used.
/// - Rows by a synonym table with the schema's choices (T4): diluted over basic, attributable to the company over net
///   income including noncontrolling interests, the total of revenues over a partial line, operating income and interest
///   expense only from rows that name them. Levels are tried in order; the first level with a matching row decides.
/// - The unit from the page header (T5), skipping a unit that qualifies shares and everything after "except"; if the page
///   prints none, the unit of the other statement. The text keeps the cell as printed and adds the unit word.
/// - A null with its reason whenever a rule cannot decide (T6).
///
/// The synonym table was written on the five reports of the PDF pilot only (the development set).
nonisolated enum StatementTableReader {

    /// The keys the reader fills, in the order of the schema.
    static let keys = ["revenue", "operatingIncome", "netIncome", "eps", "interestExpense", "operatingCashFlow", "capex",
                       "previousYearRevenue", "previousYearNetIncome", "previousYearEps"]

    // MARK: - A report

    /// The amounts of a report, from the rows of its income statement page and its cash flow statement page (either may
    /// be missing: its fields are then null, `noPage`).
    static func read(income: [TableRow]?, cashFlow: [TableRow]?) -> StatementReading {
        var reading = StatementReading()
        let incomeUnit = income.flatMap(unit(in:))
        let cashFlowUnit = cashFlow.flatMap(unit(in:))
        for field in fields {
            let rows = field.statement == .income ? income : cashFlow
            let pageUnit = field.statement == .income ? (incomeUnit ?? cashFlowUnit) : (cashFlowUnit ?? incomeUnit)
            var outputs = [(field.current, false)]
            if let previous = field.previous { outputs.append((previous, true)) }
            for (key, previousYear) in outputs {
                switch value(of: field, previousYear: previousYear, in: rows, unit: pageUnit) {
                case .success(let amount): reading.amounts[key] = amount
                case .failure(let reason): reading.abstained[key] = reason
                }
            }
        }
        return reading
    }

    /// Whether the rows are a statement of that kind: its title in the first rows, a year header, and at least three rows
    /// the reader knows. Used to pick a page among the ones a search found.
    static func recognises(_ kind: StatementKind, rows: [TableRow]) -> Bool {
        guard hasTitle(kind, rows), years(in: rows) != nil else { return false }
        let found = candidates(rows)
        let known = recognitionGroups(kind).filter { group in
            group.contains { matcher in found.contains { matcher($0.key) } }
        }
        return known.count >= 3
    }

    // MARK: - Years, unit, labels

    /// The years of the table's header, left to right: the first row whose cells are all years (at least two); failing
    /// that, the first row above any amount whose text holds at least two years ("December 31, 2025 December 31, 2024").
    /// A header that repeats a year belongs to a table with groups of columns (segments, consolidating data), not to a
    /// statement: it gives no years.
    static func years(in rows: [TableRow]) -> [Int]? {
        for row in rows where row.cells.count >= 2 {
            let found = row.cells.compactMap(year)
            if found.count == row.cells.count { return Set(found).count == found.count ? found : nil }
        }
        for row in rows {
            if row.cells.contains(where: { year($0) == nil }) { break }
            let text = row.label + " " + row.cells.joined(separator: " ")
            let range = NSRange(text.startIndex..., in: text)
            let found = yearPattern.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).flatMap { Int(text[$0]) }
            }
            if found.count >= 2, Set(found).count == found.count { return found }
        }
        return nil
    }

    /// The unit of the page's amounts: the first "in millions" (thousands, billions) or "millions of dollars" of the page,
    /// reading each row only up to "except", and skipping a unit followed by "of shares".
    static func unit(in rows: [TableRow]) -> StatementUnit? {
        for row in rows {
            var text = (row.label + " " + row.cells.joined(separator: " ")).lowercased()
            if let except = text.range(of: "except") { text = String(text[..<except.lowerBound]) }
            let range = NSRange(text.startIndex..., in: text)
            for match in unitPattern.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text) else { continue }
                let after = text[whole.upperBound...].trimmingCharacters(in: .whitespaces)
                if after.hasPrefix("of share") { continue }
                let word = text[whole]
                if word.contains("thousand") { return .thousand }
                if word.contains("million") { return .million }
                if word.contains("billion") { return .billion }
            }
        }
        return nil
    }

    /// A row label made comparable: lowercase, without "$", footnote markers, "(loss)" and "(used in)" asides, extra
    /// spaces or a final colon, comma or period.
    static func normalized(_ label: String) -> String {
        var text = label.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        for aside in ["(loss)", "(losses)", "(used in)", "(used for)", "(used by)", "$"] {
            text = text.replacingOccurrences(of: aside, with: " ")
        }
        let range = NSRange(text.startIndex..., in: text)
        text = footnotePattern.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = text.last, ":,. ".contains(last) { text.removeLast() }
        return text
    }

    /// The rows that carry cells, with their normalized label and the label of the section they are in (the last row of
    /// words only above them). A row labelled just "Total" takes its section's name: "total net sales and revenues".
    static func candidates(_ rows: [TableRow]) -> [(row: TableRow, key: Candidate)] {
        var section = ""
        var result: [(row: TableRow, key: Candidate)] = []
        for row in rows {
            if row.cells.isEmpty {
                if !row.label.isEmpty { section = normalized(row.label) }
                continue
            }
            var label = normalized(row.label)
            if label == "total" { label = "total " + section }
            result.append((row, Candidate(label: label, section: section)))
        }
        return result
    }

    /// A row as the matchers see it.
    struct Candidate: Equatable, Sendable {
        let label: String
        let section: String
    }

    // MARK: - Fields

    typealias Matcher = @Sendable (Candidate) -> Bool

    private struct Field: Sendable {
        let statement: StatementKind
        let perShare: Bool
        let current: String
        let previous: String?
        /// In priority order: the first level with a matching row decides.
        let levels: [Matcher]
    }

    private static func exact(_ labels: String...) -> [Matcher] {
        labels.map { label in { $0.label == label } }
    }

    private static func prefix(_ labels: String...) -> [Matcher] {
        labels.map { label in { $0.label.hasPrefix(label) } }
    }

    private static func perShareWords(_ text: String) -> Bool {
        ["per share", "per common share", "per diluted share", "earnings per", "income per"].contains { text.contains($0) }
    }

    private static func shareCountWords(_ text: String) -> Bool {
        ["shares used", "weighted", "average", "number of shares", "shares outstanding"].contains { text.contains($0) }
    }

    private static let attributableToCompany: Matcher = { candidate in
        let label = candidate.label
        let named = label.hasPrefix("net income attributable to ") || label.hasPrefix("net earnings attributable to ")
        let others = ["noncontrolling", "non-controlling", "minority", "redeemable"].contains { label.contains($0) }
        return named && !others && !StatementTableReader.perShareWords(label)
    }

    private static let dilutedNamed: Matcher = { candidate in
        let label = candidate.label
        let diluted = label.contains("diluted") || label.contains("assuming dilution")
        return diluted && StatementTableReader.perShareWords(label) && !StatementTableReader.shareCountWords(label)
    }

    private static let dilutedInSection: Matcher = { candidate in
        candidate.label == "diluted" && StatementTableReader.perShareWords(candidate.section)
            && !StatementTableReader.shareCountWords(candidate.section)
    }

    private static let revenueLevels = exact(
        "total net sales and revenues", "total net sales and revenue", "total net revenues", "total net revenue",
        "total revenues", "total revenue", "total net sales", "total sales", "net sales and revenues", "net revenues",
        "net revenue", "revenues", "revenue", "net sales", "sales")
    private static let operatingIncomeLevels = exact(
        "operating income", "income from operations", "operating profit", "total operating income", "operating earnings",
        "earnings from operations")
    private static let netIncomeLevels = [attributableToCompany] + exact("net income", "net earnings")
    private static let epsLevels = [dilutedNamed, dilutedInSection]
    private static let interestExpenseLevels = exact("interest expense")
    private static let operatingCashFlowLevels = exact(
        "net cash provided by operating activities", "net cash from operating activities",
        "net cash generated by operating activities", "net cash generated from operating activities",
        "cash generated by operating activities", "cash provided by operating activities",
        "net cash provided by operations", "net cash used in operating activities")
    private static let capexLevels = prefix(
        "purchases of property and equipment", "purchases of property, plant and equipment",
        "purchase of property and equipment", "purchase of property, plant and equipment",
        "payments for acquisition of property, plant and equipment", "payments for property, plant and equipment",
        "additions to property and equipment", "additions to property, plant and equipment",
        "acquisitions of property and equipment", "acquisition of property and equipment", "capital expenditures")

    private static let fields: [Field] = [
        Field(statement: .income, perShare: false, current: "revenue", previous: "previousYearRevenue",
              levels: revenueLevels),
        Field(statement: .income, perShare: false, current: "operatingIncome", previous: nil,
              levels: operatingIncomeLevels),
        Field(statement: .income, perShare: false, current: "netIncome", previous: "previousYearNetIncome",
              levels: netIncomeLevels),
        Field(statement: .income, perShare: true, current: "eps", previous: "previousYearEps", levels: epsLevels),
        Field(statement: .income, perShare: false, current: "interestExpense", previous: nil,
              levels: interestExpenseLevels),
        Field(statement: .cashFlow, perShare: false, current: "operatingCashFlow", previous: nil,
              levels: operatingCashFlowLevels),
        Field(statement: .cashFlow, perShare: false, current: "capex", previous: nil, levels: capexLevels),
    ]

    private static func recognitionGroups(_ kind: StatementKind) -> [[Matcher]] {
        let taxes: Matcher = { $0.label.contains("income taxes") }
        let investing: Matcher = { $0.label.hasPrefix("net cash") && $0.label.contains("investing activities") }
        let financing: Matcher = { $0.label.hasPrefix("net cash") && $0.label.contains("financing activities") }
        switch kind {
        case .income:
            return [revenueLevels, operatingIncomeLevels, netIncomeLevels, epsLevels, interestExpenseLevels, [taxes]]
        case .cashFlow:
            return [operatingCashFlowLevels, capexLevels, netIncomeLevels, [investing], [financing]]
        }
    }

    // MARK: - One value

    private static func value(of field: Field, previousYear: Bool, in rows: [TableRow]?,
                              unit: StatementUnit?) -> Result<StatementAmount, Abstention> {
        guard let rows else { return .failure(.noPage) }
        guard let years = years(in: rows), let latest = years.max() else { return .failure(.noYears) }
        let year = previousYear ? latest - 1 : latest
        guard let column = years.firstIndex(of: year) else { return .failure(.noYears) }
        let found = candidates(rows)
        guard let level = field.levels.first(where: { matcher in found.contains { matcher($0.key) } }) else {
            return .failure(.noRow)
        }
        let usable = found.filter { level($0.key) }.compactMap { candidate in
            usableCells(candidate.row.cells, count: years.count, perShare: field.perShare).map { (candidate.row, $0) }
        }
        guard let first = usable.first else { return .failure(.cellCount) }
        guard Set(usable.map { $0.1[column] }).count == 1 else { return .failure(.ambiguous) }
        let (row, cells) = first
        let printed = cells[column]
        guard printed != "—" else { return .failure(.dash) }
        if field.perShare { return .success(StatementAmount(text: printed, row: row.label, year: year)) }
        guard let unit else { return .failure(.noUnit) }
        return .success(StatementAmount(text: printed + " " + unit.rawValue, row: row.label, year: year))
    }

    /// The cells of a row when they line up with the header's years: a leading footnote marker ("(1)") is dropped; a
    /// per-share row must print decimals (share counts do not).
    private static func usableCells(_ cells: [String], count: Int, perShare: Bool) -> [String]? {
        var cells = cells
        if cells.count == count + 1, let first = cells.first, isFootnote(first) { cells.removeFirst() }
        guard cells.count == count else { return nil }
        if perShare, !cells.allSatisfy({ $0 == "—" || $0.contains(".") }) { return nil }
        return cells
    }

    private static func isFootnote(_ cell: String) -> Bool {
        cell.count == 3 && cell.first == "(" && cell.last == ")" && cell.dropFirst().first?.isNumber == true
    }

    private static func year(_ cell: String) -> Int? {
        guard cell.count == 4, cell.allSatisfy(\.isNumber), let value = Int(cell), (1990...2100).contains(value) else {
            return nil
        }
        return value
    }

    private static func hasTitle(_ kind: StatementKind, _ rows: [TableRow]) -> Bool {
        let titles: [String]
        switch kind {
        case .income:
            titles = ["statements of operations", "statement of operations", "statements of income", "statement of income",
                      "statements of earnings", "statement of earnings", "income statements", "income statement"]
        case .cashFlow:
            titles = ["statements of cash flows", "statement of cash flows", "statements of cash flow",
                      "statement of cash flow"]
        }
        for row in rows.prefix(12) {
            var text = row.label.lowercased().replacingOccurrences(of: "consolidated ", with: "")
            for joined in ["and comprehensive income (loss)", "and comprehensive income", "and comprehensive loss"] {
                text = text.replacingOccurrences(of: joined, with: "")
            }
            if text.contains("comprehensive") { continue }
            if titles.contains(where: { text.contains($0) }) { return true }
        }
        return false
    }

    private static let yearPattern = try! NSRegularExpression(pattern: #"\b(?:19|20)\d{2}\b"#)
    private static let unitPattern = try! NSRegularExpression(
        pattern: #"\bin (?:thousands|millions|billions)\b|\b(?:thousands|millions|billions) of (?:u\.s\. )?dollars\b"#)
    private static let footnotePattern = try! NSRegularExpression(pattern: #"\(\d{1,2}\)|\([a-z]\)"#)
}
