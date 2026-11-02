//
//  PDFStatementLinesTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

/// Phase 2g, T2: a made-up statement page drawn with CoreText (one text run per cell, as statements are typeset), read back
/// through PDFKit and rebuilt into rows. Every number is made up.
struct PDFStatementLinesTests {

    /// A one-page PDF; each row is a list of (text, x) cells drawn on one baseline, rows 18 points apart.
    private func madeUpPDF(_ rows: [[(String, CGFloat)]]) throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        for (index, cells) in rows.enumerated() {
            for (text, x) in cells {
                let attributed = NSAttributedString(
                    string: text, attributes: [NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: x, y: 740 - CGFloat(index) * 18)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    private let statement: [[(String, CGFloat)]] = [
        [("CONSOLIDATED STATEMENTS OF OPERATIONS", 72)],
        [("(In millions, except per-share amounts)", 72)],
        [("2025", 380), ("2024", 460), ("2023", 540)],
        [("Total net sales", 72), ("$ 1,234", 370), ("$ 1,100", 450), ("$ 950", 530)],
        [("Operating income", 72), ("300", 380), ("250", 460), ("200", 540)],
        [("Net income", 72), ("$ 210", 375), ("$ 190", 455), ("$ 170", 535)],
        [("Earnings per share:", 72)],
        [("Diluted", 82), ("$ 2.15", 375), ("$ 1.95", 455), ("$ 1.77", 535)],
    ]

    @Test func aDrawnStatementReadsBackIntoItsRows() throws {
        let document = try madeUpPDF(statement)
        let rows = try #require(PDFStatementLines.rows(of: document, page: 1))
        #expect(rows.contains(TableRow(label: "", cells: ["2025", "2024", "2023"])))
        #expect(rows.contains(TableRow(label: "Total net sales", cells: ["1,234", "1,100", "950"])))
        #expect(rows.contains(TableRow(label: "Diluted", cells: ["2.15", "1.95", "1.77"])))
        #expect(StatementTableReader.recognises(.income, rows: rows))
        let reading = StatementTableReader.read(income: rows, cashFlow: nil)
        #expect(reading.amounts["revenue"]?.text == "1,234 million")
        #expect(reading.amounts["previousYearEps"]?.text == "1.95")
    }

    @Test func tamperAPageThatDoesNotExistGivesNoRows() throws {
        let document = try madeUpPDF(statement)
        #expect(PDFStatementLines.rows(of: document, page: 2) == nil)
        #expect(PDFStatementLines.rows(of: document, page: 0) == nil)
    }
}
