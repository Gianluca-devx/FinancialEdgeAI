//
//  StatementTableTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import CoreGraphics
import Foundation
import Testing

/// Phase 2g, T2: rows rebuilt from the positions of the lines of a page (`StatementTable`). Every number is made up.
struct StatementTableTests {

    private func line(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 10) -> TextLine {
        TextLine(text: text, bounds: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: height))
    }

    // MARK: - One row from its text

    @Test func aRowIsItsLabelAndTheNumberCellsOnItsRight() {
        let row = StatementTable.row(from: "Total net sales $ 416,161 $ 391,035 $ 383,285")
        #expect(row == TableRow(label: "Total net sales", cells: ["416,161", "391,035", "383,285"]))
    }

    @Test func parenthesesDashesAndAttachedDollarSignsAreCells() {
        #expect(StatementTable.row(from: "Other income/(expense), net (321) 269 —")
                == TableRow(label: "Other income/(expense), net", cells: ["(321)", "269", "—"]))
        #expect(StatementTable.row(from: "Purchases of equipment $(1,360) $1,200")
                == TableRow(label: "Purchases of equipment", cells: ["(1,360)", "1,200"]))
        #expect(StatementTable.row(from: "Diluted $ 7.46 $ 6.08")
                == TableRow(label: "Diluted", cells: ["7.46", "6.08"]))
    }

    @Test func wordsWithDigitsStayInTheLabel() {
        #expect(StatementTable.row(from: "September 27, September 28,") == TableRow(label: "September 27, September 28,", cells: []))
        #expect(StatementTable.row(from: "Year Ended December 31, 2025 2024")
                == TableRow(label: "Year Ended December 31,", cells: ["2025", "2024"]))
        #expect(StatementTable.row(from: "Per-share data") == TableRow(label: "Per-share data", cells: []))
    }

    // MARK: - Rows from positions

    @Test func linesThatOverlapVerticallyAreOneRowReadLeftToRight() {
        let lines = [
            line("416,161 391,035", x: 360, y: 700),
            line("Total net sales", x: 72, y: 701.5),
        ]
        #expect(StatementTable.rows(from: lines) == [TableRow(label: "Total net sales", cells: ["416,161", "391,035"])])
    }

    @Test func rowsRunTopToBottom() {
        let lines = [
            line("Net income 210 190", x: 72, y: 600),
            line("Total net sales 1,234 1,100", x: 72, y: 700),
            line("2025 2024", x: 360, y: 760),
        ]
        #expect(StatementTable.rows(from: lines).map(\.label) == ["", "Total net sales", "Net income"])
    }

    @Test func aLabelThatWrapsOntoALowercaseLineIsJoined() {
        let lines = [
            line("Net income (loss) attributable to noncontrolling interests and redeemable noncontrolling", x: 72, y: 700),
            line("interests in subsidiaries 61 62 (23)", x: 82, y: 688),
        ]
        #expect(StatementTable.rows(from: lines) == [TableRow(
            label: "Net income (loss) attributable to noncontrolling interests and redeemable noncontrolling interests in subsidiaries",
            cells: ["61", "62", "(23)"])])
    }

    @Test func aLabelAboveARowOfNumbersOnlyIsJoined() {
        let lines = [line("Total net sales", x: 72, y: 700), line("416,161 391,035", x: 360, y: 688)]
        #expect(StatementTable.rows(from: lines) == [TableRow(label: "Total net sales", cells: ["416,161", "391,035"])])
    }

    @Test func tamperAHeaderAboveTheYearsIsNotJoinedToThem() {
        let lines = [line("(In millions, except per-share amounts)", x: 72, y: 700), line("2025 2024", x: 380, y: 688)]
        #expect(StatementTable.rows(from: lines) == [
            TableRow(label: "(In millions, except per-share amounts)", cells: []),
            TableRow(label: "", cells: ["2025", "2024"]),
        ])
    }

    @Test func tamperASectionHeaderAboveACapitalisedRowIsNotJoined() {
        let lines = [line("Earnings per share:", x: 72, y: 700), line("Basic 2.20 1.99", x: 82, y: 688)]
        #expect(StatementTable.rows(from: lines) == [
            TableRow(label: "Earnings per share:", cells: []),
            TableRow(label: "Basic", cells: ["2.20", "1.99"]),
        ])
    }

    @Test func tamperLinesThatDoNotOverlapEnoughAreTwoRows() {
        let lines = [line("Total net sales", x: 72, y: 700), line("416,161", x: 360, y: 694)]  // 4 of 10 points overlap
        #expect(StatementTable.rows(from: lines).count == 1)   // the second joins only as a numbers-only row
        let apart = [line("Total net sales 1", x: 72, y: 700), line("416,161", x: 360, y: 694)]
        #expect(StatementTable.rows(from: apart).count == 2)
    }
}
