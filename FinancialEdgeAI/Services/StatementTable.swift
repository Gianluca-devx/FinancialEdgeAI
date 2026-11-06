//
//  StatementTable.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import CoreGraphics
import Foundation

/// A line of text on a PDF page and where it is, in page space (72 dpi, origin at the lower left, y going up).
nonisolated struct TextLine: Equatable, Sendable {
    let text: String
    let bounds: CGRect
}

/// One row of a financial statement table as printed: the words of its label, and the number cells to their right.
nonisolated struct TableRow: Equatable, Sendable {
    /// The words before the number cells ("Total net sales"); the whole row when it has no number cell.
    let label: String
    /// The number cells from left to right, as printed but without the dollar sign: "416,161", "(321)", "7.46", "2025",
    /// or "—" for a dash.
    let cells: [String]
}

/// Phase 2g (`Specs/phase-2g-table-reader.md`, T2): the rows of a statement page, rebuilt from where its lines are.
///
/// `PDFPage.string` can put a row's label and its numbers on different lines; their positions keep them together. Pure:
/// the lines come from `PDFStatementLines` (PDFKit) or from a test.
nonisolated enum StatementTable {

    /// The rows of a page. Two lines are in the same row when they overlap vertically by more than half the height of the
    /// smaller one; rows run top to bottom and the lines of a row left to right. A label that wraps is joined: a row of
    /// words only, followed by a row whose label starts with a lowercase letter (the label goes on) or by a row of numbers
    /// with no label that is not a header of years.
    static func rows(from lines: [TextLine]) -> [TableRow] {
        var groups: [[TextLine]] = []
        for line in lines.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let first = groups.last?.first, sameRow(first.bounds, line.bounds) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        let rows = groups.map { group in
            row(from: group.sorted(by: { $0.bounds.minX < $1.bounds.minX }).map(\.text).joined(separator: " "))
        }
        return joinWrappedLabels(rows)
    }

    /// One row from its text: the number cells are read from the right end, and the rest is the label.
    static func row(from text: String) -> TableRow {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var cells: [String] = []
        while let last = words.last {
            if last == "$" {
                words.removeLast()
            } else if let value = cell(last) {
                cells.insert(value, at: 0)
                words.removeLast()
            } else {
                break
            }
        }
        return TableRow(label: words.joined(separator: " "), cells: cells)
    }

    /// A number cell as printed without "$" ("$(1,360)" gives "(1,360)"), "—" for a dash, or nil for a word.
    static func cell(_ word: String) -> String? {
        if dashes.contains(word) { return "—" }
        var body = word
        if body.hasPrefix("$") { body.removeFirst() }
        if body.hasPrefix("($") { body = "(" + body.dropFirst(2) }
        let range = NSRange(body.startIndex..., in: body)
        return number.firstMatch(in: body, range: range) != nil ? body : nil
    }

    private static let dashes: Set<String> = ["—", "–", "-", "−"]

    /// A number as statements print it: thousands separated by commas, an optional decimal part, an optional pair of
    /// parentheses for a negative value.
    private static let number = try! NSRegularExpression(
        pattern: #"^\(?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\)?$"#)

    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    private static func joinWrappedLabels(_ rows: [TableRow]) -> [TableRow] {
        var joined: [TableRow] = []
        var index = 0
        while index < rows.count {
            let current = rows[index]
            if current.cells.isEmpty, !current.label.isEmpty, index + 1 < rows.count {
                let next = rows[index + 1]
                let continues = next.label.first?.isLowercase == true
                let years = next.cells.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isNumber) }
                let numbersOnly = next.label.isEmpty && !next.cells.isEmpty && !years
                if continues || numbersOnly {
                    let label = numbersOnly ? current.label : current.label + " " + next.label
                    joined.append(TableRow(label: label, cells: next.cells))
                    index += 2
                    continue
                }
            }
            joined.append(current)
            index += 1
        }
        return joined
    }
}
