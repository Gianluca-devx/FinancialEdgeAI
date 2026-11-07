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
    /// A loss row (or a loss-per-share row) printed without parentheses: its sign cannot be read from the number (Phase 2h, R3).
    case unsignedLoss
    /// The page's unit names another currency than the dollar, which the app cannot read (Phase 2h, R5).
    case currency
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
/// Phase 2h (`Specs/phase-2h-table-reader-round2.md`) adds, from the misses Phase 2g named: loss rows (a number in parentheses
/// is negative; without them the field is null, R3), a combined "basic and diluted" EPS row, "consolidated" ignored at the start
/// of a row label, more operating cash flow and capex forms (the broader capex lines only when no strict one is printed), the
/// cash flow title in either word order, note references kept out of the cells, capex read only inside the investing section
/// (R4), and a currency guard: a unit in another currency makes every field of the page null (R5).
///
/// The synonym table was written on the five reports of the PDF pilot (Phase 2g) and the 17 labelled reports (Phase 2h), the
/// development sets.
nonisolated enum StatementTableReader {

    /// The keys the reader fills, in the order of the schema.
    static let keys = ["revenue", "operatingIncome", "netIncome", "eps", "interestExpense", "operatingCashFlow", "capex",
                       "previousYearRevenue", "previousYearNetIncome", "previousYearEps"]

    // MARK: - A report

    /// The amounts of a report, from the rows of its income statement page and its cash flow statement page (either may
    /// be missing: its fields are then null, `noPage`).
    static func read(income: [TableRow]?, cashFlow: [TableRow]?) -> StatementReading {
        var reading = StatementReading()
        let incomeForeign = income.map(foreignCurrency(in:)) ?? false
        let cashFlowForeign = cashFlow.map(foreignCurrency(in:)) ?? false
        let incomeUnit = incomeForeign ? nil : income.flatMap(unit(in:))
        let cashFlowUnit = cashFlowForeign ? nil : cashFlow.flatMap(unit(in:))
        for field in fields {
            let rows = field.statement == .income ? income : cashFlow
            let foreign = field.statement == .income ? incomeForeign : cashFlowForeign
            let pageUnit = field.statement == .income ? (incomeUnit ?? cashFlowUnit) : (cashFlowUnit ?? incomeUnit)
            var outputs = [(field.current, false)]
            if let previous = field.previous { outputs.append((previous, true)) }
            for (key, previousYear) in outputs {
                if foreign, rows != nil {
                    reading.abstained[key] = .currency
                    continue
                }
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

    /// Whether the page's amounts are in another currency than the dollar (R5). Read in the header, the rows above the first
    /// amount, where a statement declares its currency: a currency symbol other than "$"; a unit phrase followed by "of" and
    /// anything but dollars or shares ("in millions of euros", "of Canadian dollars"); or a currency word or code in a row that
    /// names a unit ("€ in millions", "(EUR millions)"). Below the header, only a foreign symbol printed right before a row's
    /// numbers counts, so a line such as "Repayment of €750 million notes" does not make a dollar statement foreign.
    static func foreignCurrency(in rows: [TableRow]) -> Bool {
        let symbols: [Character] = ["€", "£", "¥", "₹", "₩", "₣"]
        if rows.contains(where: { row in !row.cells.isEmpty && row.label.last.map(symbols.contains) == true }) { return true }
        let header = rows.prefix { row in row.cells.allSatisfy { year($0) != nil } }
        for row in header {
            let text = (row.label + " " + row.cells.joined(separator: " ")).lowercased()
            if symbols.contains(where: { text.contains($0) }) { return true }
            let range = NSRange(text.startIndex..., in: text)
            for match in unitPattern.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text) else { continue }
                let after = text[whole.upperBound...].trimmingCharacters(in: .whitespaces)
                guard after.hasPrefix("of ") else { continue }
                let next = after.dropFirst(3).split(whereSeparator: { " ,;)".contains($0) }).first.map(String.init) ?? ""
                if !["dollars", "u.s.", "us", "usd", "us$", "$", "shares", "share"].contains(next) { return true }
            }
            let namesUnit = ["thousand", "million", "billion"].contains { text.contains($0) }
            if namesUnit, currencyWordPattern.firstMatch(in: text, range: range) != nil { return true }
        }
        return false
    }

    /// A row label made comparable: lowercase, without "$", footnote markers, note references ("(Note 12)"), "(loss)" and
    /// "(used in)" asides, a leading "consolidated", extra spaces or a final colon, comma or period.
    static func normalized(_ label: String) -> String {
        var text = label.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        for aside in ["(loss)", "(losses)", "(used in)", "(used for)", "(used by)", "$"] {
            text = text.replacingOccurrences(of: aside, with: " ")
        }
        for pattern in [notePattern, footnotePattern] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.hasPrefix("consolidated ") { text.removeFirst("consolidated ".count) }
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
        let named = ["net income attributable to ", "net earnings attributable to ", "net loss attributable to "]
            .contains { label.hasPrefix($0) }
        let others = ["noncontrolling", "non-controlling", "minority", "redeemable"].contains { label.contains($0) }
        return named && !others && !StatementTableReader.perShareWords(label)
    }

    /// A row that names a loss: its number must be in parentheses to be read (R3). A per-share row counts when its section
    /// names a loss per share ("Net loss per share:").
    private static func namesLoss(_ candidate: Candidate, perShare: Bool) -> Bool {
        let label = candidate.label
        if label.hasPrefix("operating loss") || label.hasPrefix("net loss") || label == "loss from operations" { return true }
        return perShare && (candidate.section.contains("loss per") || label.contains("loss per"))
    }

    private static let dilutedNamed: Matcher = { candidate in
        let label = candidate.label
        let diluted = label.contains("diluted") || label.contains("assuming dilution")
        return diluted && StatementTableReader.perShareWords(label) && !StatementTableReader.shareCountWords(label)
    }

    private static let dilutedInSection: Matcher = { candidate in
        ["diluted", "basic and diluted"].contains(candidate.label) && StatementTableReader.perShareWords(candidate.section)
            && !StatementTableReader.shareCountWords(candidate.section)
    }

    private static let revenueLevels = exact(
        "total net sales and revenues", "total net sales and revenue", "total net revenues", "total net revenue",
        "total revenues", "total revenue", "total net sales", "total sales", "net sales and revenues", "net revenues",
        "net revenue", "revenues", "revenue", "net sales", "sales")
    private static let operatingIncomeLevels = exact(
        "operating income", "income from operations", "operating profit", "total operating income", "operating earnings",
        "earnings from operations", "operating loss", "loss from operations")
    private static let netIncomeLevels = [attributableToCompany] + exact("net income", "net earnings", "net loss")
    private static let epsLevels = [dilutedNamed, dilutedInSection]
    private static let interestExpenseLevels = exact("interest expense")
    private static let operatingCashFlowLevels = exact(
        "net cash provided by operating activities", "net cash from operating activities",
        "net cash generated by operating activities", "net cash generated from operating activities",
        "cash generated by operating activities", "cash provided by operating activities",
        "net cash provided by operations", "net cash used in operating activities", "net cash from operations",
        "cash provided by operations", "net cash flows from operating activities", "net cash flow from operating activities",
        "cash generated from operations", "net cash generated from operations")
    /// The strict capex lines first, then the broader ones (with intangible assets, or net of sales), used only when the
    /// statement prints no strict line: the labelling choice the user agreed in Phase 2g.
    private static let capexLevels = prefix(
        "purchases of property and equipment", "purchases of property, plant and equipment",
        "purchase of property and equipment", "purchase of property, plant and equipment",
        "payments for acquisition of property, plant and equipment", "payments for property, plant and equipment",
        "payments for property and equipment",
        "additions to property and equipment", "additions to property, plant and equipment",
        "acquisitions of property and equipment", "acquisition of property and equipment", "capital expenditures",
        "investment in property, plant, equipment", "investment in property, plant and equipment",
        "investment in property and equipment", "purchases related to property and equipment")

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
        let scope = field.current == "capex" ? (investingSection(of: rows) ?? rows) : rows
        let found = candidates(scope)
        guard let level = field.levels.first(where: { matcher in found.contains { matcher($0.key) } }) else {
            return .failure(.noRow)
        }
        let usable = found.filter { level($0.key) }.compactMap { candidate in
            usableCells(candidate.row.cells, count: years.count, perShare: field.perShare).map { (candidate, $0) }
        }
        guard let first = usable.first else { return .failure(.cellCount) }
        guard Set(usable.map { $0.1[column] }).count == 1 else { return .failure(.ambiguous) }
        let (candidate, cells) = first
        let row = candidate.row
        let printed = cells[column]
        guard printed != "—" else { return .failure(.dash) }
        if namesLoss(candidate.key, perShare: field.perShare), !printed.hasPrefix("(") { return .failure(.unsignedLoss) }
        if field.perShare { return .success(StatementAmount(text: printed, row: row.label, year: year)) }
        guard let unit else { return .failure(.noUnit) }
        return .success(StatementAmount(text: printed + " " + unit.rawValue, row: row.label, year: year))
    }

    /// The rows of the investing section (R4): from its header (a row of words naming investing activities, or just
    /// "Investing") to its total ("Net cash ... investing ..."), both included; nil when either is missing.
    static func investingSection(of rows: [TableRow]) -> [TableRow]? {
        guard let start = rows.firstIndex(where: { row in
            let label = normalized(row.label)
            return row.cells.isEmpty && (label == "investing" || label.contains("investing activities"))
        }) else { return nil }
        guard let end = rows[start...].firstIndex(where: { row in
            let label = normalized(row.label)
            return !row.cells.isEmpty && label.hasPrefix("net cash") && label.contains("investing")
        }) else { return nil }
        return Array(rows[start...end])
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
                      "statement of cash flow", "cash flows statements", "cash flows statement", "cash flow statements",
                      "cash flow statement"]
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
    private static let notePattern = try! NSRegularExpression(pattern: #"\((?:see )?notes? [^)]*\)"#)
    private static let currencyWordPattern = try! NSRegularExpression(
        pattern: #"\b(?:euros?|pounds?|sterling|yen|francs?|kron(?:a|or|e|er)|yuan|renminbi|rupees?|pesos?|reais|rand|won|"#
            + #"eur|gbp|jpy|chf|cad|aud|nzd|hkd|sgd|cny|rmb|inr|krw|sek|nok|dkk|brl|mxn|zar)\b"#)
}
