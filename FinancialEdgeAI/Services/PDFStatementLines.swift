//
//  PDFStatementLines.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import CoreGraphics
import Foundation
import PDFKit

/// Phase 2g (`Specs/phase-2g-table-reader.md`, T2): the lines of text of a PDF page with their bounds, for
/// `StatementTable.rows(from:)`. The only part of the table reader that needs PDFKit; it builds for iOS and macOS alike, so
/// the Mac driver (`Scripts/table_reader.sh`) runs the same code as the app.
nonisolated enum PDFStatementLines {

    /// Every line of text on the page (`selectionsByLine()` of the selection that covers the media box), with its bounds in
    /// page space. Empty lines are dropped.
    static func lines(of page: PDFPage) -> [TextLine] {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return TextLine(text: text, bounds: line.bounds(for: page))
        }
    }

    /// The rows of page `number` (from 1) of a document, or nil when it has no such page.
    static func rows(of document: PDFDocument, page number: Int) -> [TableRow]? {
        guard number >= 1, let page = document.page(at: number - 1) else { return nil }
        return StatementTable.rows(from: lines(of: page))
    }
}
