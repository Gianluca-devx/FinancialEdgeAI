//
//  StatementTableReaderTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 02/11/2026.
//
import Foundation
import Testing

/// Phase 2g, T3 to T6: the rules of `StatementTableReader` on made-up statements, each with a tamper case that must fail
/// the rule's way. Every company and number is made up.
struct StatementTableReaderTests {

    /// Rows from lines of text, one row per line (positions are tested in `StatementTableTests`).
    private func rows(_ text: String) -> [TableRow] {
        text.split(separator: "\n").map { StatementTable.row(from: String($0)) }
    }

    private let income = """
        Made-up Corp.
        CONSOLIDATED STATEMENTS OF OPERATIONS
        (In millions, except number of shares, which are reflected in thousands, and per-share amounts)
        Years ended
        2025 2024 2023
        Net sales:
        Products $ 1,000 $ 900 $ 800
        Services 234 200 150
        Total net sales 1,234 1,100 950
        Operating income 300 250 200
        Interest expense (12) (10) (8)
        Net income $ 210 $ 190 $ 170
        Earnings per share:
        Basic $ 2.20 $ 1.99 $ 1.80
        Diluted $ 2.15 $ 1.95 $ 1.77
        Shares used in computing earnings per share:
        Basic 95,000 96,000 97,000
        Diluted 97,600 98,000 99,000
        """

    private let cashFlow = """
        CONSOLIDATED STATEMENTS OF CASH FLOWS
        (In millions)
        Years ended
        2025 2024 2023
        Net income $ 210 $ 190 $ 170
        Net cash provided by operating activities 400 350 300
        Purchases of property and equipment (90) (80) (70)
        Net cash used in investing activities (150) (120) (100)
        Net cash used in financing activities (200) (180) (160)
        """

    private func read(_ income: String?, _ cashFlow: String?) -> StatementReading {
        StatementTableReader.read(income: income.map(rows), cashFlow: cashFlow.map(rows))
    }

    private func texts(_ reading: StatementReading) -> [String: String] {
        reading.amounts.mapValues(\.text)
    }

    // MARK: - The whole report

    @Test func readsTheTenAmountsOfAMadeUpReport() {
        let reading = read(income, cashFlow)
        #expect(texts(reading) == [
            "revenue": "1,234 million", "operatingIncome": "300 million", "netIncome": "210 million", "eps": "2.15",
            "interestExpense": "(12) million", "operatingCashFlow": "400 million", "capex": "(90) million",
            "previousYearRevenue": "1,100 million", "previousYearNetIncome": "190 million", "previousYearEps": "1.95",
        ])
        #expect(reading.abstained.isEmpty)
        #expect(reading.amounts["revenue"]?.year == 2025 && reading.amounts["previousYearRevenue"]?.year == 2024)
    }

    @Test func everyTextIsReadByTheAppsParser() throws {
        let reading = read(income, cashFlow)
        let value = { (key: String, kind: FieldKind) in reading.amounts[key].flatMap { ValueParser.parse($0.text, kind: kind) } }
        let close = { (found: Double?, expected: Double) in found.map { abs($0 - expected) < 1e-9 } == true }
        #expect(close(value("revenue", .amount), 1.234))
        #expect(close(value("capex", .amount), -0.09))
        #expect(close(value("eps", .perShare), 2.15))
        let thousands = read(income.replacingOccurrences(of: "In millions", with: "In thousands"), cashFlow)
        #expect(close(thousands.amounts["revenue"].flatMap { ValueParser.parse($0.text, kind: .amount) }, 0.001234))
    }

    @Test func theReaderFillsOnlyCoreKeysOfTheSchema() throws {
        let schema = try DatasetFiles.schema()
        #expect(Set(StatementTableReader.keys).isSubset(of: Set(schema.coreKeys)))
        #expect(Set(read(income, cashFlow).amounts.keys) == Set(StatementTableReader.keys))
    }

    // MARK: - T3: columns by their year

    @Test func yearsPrintedOldestFirstAreReadByYearNotPosition() {
        let reversed = """
            CONSOLIDATED STATEMENTS OF INCOME
            (In millions)
            2023 2024 2025
            Total revenues 950 1,100 1,234
            Net income 170 190 210
            Diluted earnings per share 1.77 1.95 2.15
            """
        let reading = read(reversed, nil)
        #expect(reading.amounts["revenue"]?.text == "1,234 million")
        #expect(reading.amounts["previousYearRevenue"]?.text == "1,100 million")
        #expect(reading.amounts["previousYearEps"]?.text == "1.95")
    }

    @Test func thePreviousYearIsNeverTheOldestColumn() {
        let reading = read(income, cashFlow)
        #expect(reading.amounts["previousYearNetIncome"]?.text == "190 million")   // not the 170 of 2023
    }

    @Test func tamperWithoutAYearHeaderEveryIncomeFieldIsNull() {
        let reading = read(income.replacingOccurrences(of: "2025 2024 2023\n", with: ""), nil)
        #expect(reading.amounts.isEmpty)
        #expect(reading.abstained["revenue"] == .noYears && reading.abstained["capex"] == .noPage)
    }

    @Test func aHeaderWithTwoDatesOnOneLineGivesItsYears() {
        let table = rows("""
            CONSOLIDATED STATEMENTS OF OPERATIONS
            December 31, 2025 December 31, 2024
            Total revenues 1,234 1,100
            """)
        #expect(StatementTableReader.years(in: table) == [2025, 2024])
    }

    // MARK: - T5: units

    @Test(arguments: [
        ("(In millions, except number of shares, which are reflected in thousands, and per-share amounts)", StatementUnit.million),
        ("(In thousands, except per share data)", .thousand),
        ("(Dollars in millions)", .million),
        ("(In millions of dollars and shares, except per share amounts)", .million),
        ("Amounts in billions of U.S. dollars", .billion),
    ])
    func theHeaderGivesTheUnit(header: String, unit: StatementUnit) {
        #expect(StatementTableReader.unit(in: rows(header)) == unit)
    }

    @Test func tamperAUnitOfSharesOrAnAmountInTheTextIsNoUnit() {
        #expect(StatementTableReader.unit(in: rows("(in millions of shares)")) == nil)
        #expect(StatementTableReader.unit(in: rows("Proceeds from the issue of $500 million of notes 500 —")) == nil)
    }

    @Test func aPageWithoutAUnitTakesTheOtherStatementsUnit() {
        let reading = read(income, cashFlow.replacingOccurrences(of: "(In millions)\n", with: ""))
        #expect(reading.amounts["operatingCashFlow"]?.text == "400 million")
    }

    @Test func tamperWithNoUnitAnywhereAmountsAreNullButPerShareValuesAreRead() {
        let noUnit = income.replacingOccurrences(
            of: "(In millions, except number of shares, which are reflected in thousands, and per-share amounts)\n", with: "")
        let reading = read(noUnit, cashFlow.replacingOccurrences(of: "(In millions)\n", with: ""))
        #expect(reading.abstained["revenue"] == .noUnit && reading.abstained["capex"] == .noUnit)
        #expect(reading.amounts["eps"]?.text == "2.15")
    }

    // MARK: - T4: rows and the schema's choices

    @Test func tamperWithoutTheDilutedRowBasicIsNotTaken() {
        let reading = read(income.replacingOccurrences(of: "Diluted $ 2.15 $ 1.95 $ 1.77\n", with: ""), nil)
        #expect(reading.abstained["eps"] == .noRow)   // neither the basic 2.20 nor the diluted share count 97,600
    }

    @Test func netIncomeAttributableToTheCompanyIsPreferred() {
        let table = """
            CONSOLIDATED STATEMENTS OF OPERATIONS
            (in millions)
            2025 2024 2023
            Net income 3,855 7,153 15,001
            Net income (loss) attributable to noncontrolling interests 61 62 (4)
            Net income attributable to common stockholders $ 3,794 $ 7,091 $ 15,005
            """
        let reading = read(table, nil)
        #expect(reading.amounts["netIncome"]?.text == "3,794 million")
        #expect(reading.amounts["previousYearNetIncome"]?.text == "7,091 million")
    }

    @Test func tamperOnlyTheNoncontrollingRowIsNotTheCompanysNetIncome() {
        let table = """
            CONSOLIDATED STATEMENTS OF OPERATIONS
            (in millions)
            2025 2024
            Net income attributable to noncontrolling interests 61 62
            """
        #expect(read(table, nil).abstained["netIncome"] == .noRow)
    }

    @Test func aTotalTakesTheNameOfItsSection() {
        let table = """
            STATEMENT OF CONSOLIDATED INCOME
            (In millions of dollars)
            2025 2024
            Net Sales and Revenues
            Net sales $ 38,000 $ 44,000
            Finance and interest income 5,000 5,500
            Other income 2,684 2,216
            Total 45,684 51,716
            Costs and Expenses
            Cost of sales 30,000 31,000
            Total 39,427 42,510
            Income before income taxes 6,257 9,206
            """
        let reading = read(table, nil)
        #expect(reading.amounts["revenue"]?.text == "45,684 million")   // the total, not the net sales line
        #expect(reading.abstained["operatingIncome"] == .noRow)           // neither the costs total nor pre-tax income
    }

    @Test func capexWithALongLabelKeepsItsParentheses() {
        let table = cashFlow.replacingOccurrences(
            of: "Purchases of property and equipment (90) (80) (70)",
            with: "Purchases of property and equipment excluding finance leases, net of sales (90) (80) (70)")
        let reading = read(income, table)
        #expect(reading.amounts["capex"]?.text == "(90) million")
        let parsed = reading.amounts["capex"].flatMap { ValueParser.parse($0.text, kind: .amount) }
        #expect(parsed.map { abs($0 + 0.09) < 1e-9 } == true)
    }

    @Test func labelsAreNormalized() {
        #expect(StatementTableReader.normalized("Operating income (loss)") == "operating income")
        #expect(StatementTableReader.normalized("Net cash provided by (used in) operating activities")
                == "net cash provided by operating activities")
        #expect(StatementTableReader.normalized("Net income (1):") == "net income")
        #expect(StatementTableReader.normalized("Total revenues,") == "total revenues")
    }

    // MARK: - T6: abstain rather than guess

    @Test func aDashIsNull() {
        let reading = read(income.replacingOccurrences(of: "Interest expense (12) (10) (8)", with: "Interest expense — (10) (8)"), nil)
        #expect(reading.abstained["interestExpense"] == .dash)
    }

    @Test func twoMatchingRowsWithDifferentValuesAreNull() {
        let twice = income.replacingOccurrences(of: "Operating income 300 250 200",
                                                with: "Operating income 300 250 200\nOperating income 310 250 200")
        #expect(read(twice, nil).abstained["operatingIncome"] == .ambiguous)
        let same = income.replacingOccurrences(of: "Operating income 300 250 200",
                                               with: "Operating income 300 250 200\nOperating income 300 250 200")
        #expect(read(same, nil).amounts["operatingIncome"]?.text == "300 million")   // tamper: equal values are read
    }

    @Test func aFootnoteMarkerIsDroppedButAMissingCellIsNull() {
        let footnote = income.replacingOccurrences(of: "Net income $ 210 $ 190 $ 170", with: "Net income (1) $ 210 $ 190 $ 170")
        #expect(read(footnote, nil).amounts["netIncome"]?.text == "210 million")
        let missing = income.replacingOccurrences(of: "Net income $ 210 $ 190 $ 170", with: "Net income $ 210 $ 190")
        #expect(read(missing, nil).abstained["netIncome"] == .cellCount)
    }

    @Test func aMissingPageMakesItsFieldsNull() {
        let reading = read(nil, cashFlow)
        #expect(reading.abstained["revenue"] == .noPage && reading.abstained["eps"] == .noPage)
        #expect(reading.amounts["operatingCashFlow"]?.text == "400 million")
    }

    // MARK: - Phase 2h: losses (R3)

    private let lossYear = """
        CONSOLIDATED STATEMENTS OF OPERATIONS
        (In millions, except share and per share amounts)
        2025 2024 2023
        Total revenues 4,848.9 4,637.2 4,812.6
        Operating loss (17.4) (79.3) (74.3)
        Loss before income taxes (627.9) (350.5) (393.2)
        Net loss $ (632.4) $ (352.6) $ (396.6)
        Net loss per share:
        Basic and diluted $ (1.34) $ (1.06) $ (2.37)
        Weighted average shares outstanding:
        Basic and diluted (in thousands) 472,899 332,920 167,644
        """

    @Test func lossRowsInParenthesesAreNegativeAmounts() {
        let reading = read(lossYear, nil)
        #expect(reading.amounts["operatingIncome"]?.text == "(17.4) million")
        #expect(reading.amounts["netIncome"]?.text == "(632.4) million")
        #expect(reading.amounts["previousYearNetIncome"]?.text == "(352.6) million")
        #expect(reading.amounts["eps"]?.text == "(1.34)")             // the combined row, not the share count below
        #expect(reading.amounts["previousYearEps"]?.text == "(1.06)")
        #expect(StatementTableReader.recognises(.income, rows: rows(lossYear)))
        let value = reading.amounts["netIncome"].flatMap { ValueParser.parse($0.text, kind: .amount) }
        #expect(value.map { abs($0 + 0.6324) < 1e-9 } == true)
    }

    @Test func tamperALossPrintedWithoutParenthesesIsNull() {
        let unsigned = lossYear.replacingOccurrences(of: "Net loss $ (632.4) $ (352.6) $ (396.6)",
                                                     with: "Net loss $ 632.4 $ 352.6 $ 396.6")
            .replacingOccurrences(of: "Basic and diluted $ (1.34) $ (1.06) $ (2.37)", with: "Basic and diluted $ 1.34 $ 1.06 $ 2.37")
        let reading = read(unsigned, nil)
        #expect(reading.abstained["netIncome"] == .unsignedLoss && reading.abstained["previousYearNetIncome"] == .unsignedLoss)
        #expect(reading.abstained["eps"] == .unsignedLoss)
        #expect(reading.amounts["operatingIncome"]?.text == "(17.4) million")   // still in parentheses, still read
    }

    // MARK: - Phase 2h: row names

    @Test func consolidatedNetIncomeAttributableToTheCompanyIsRead() {
        let table = """
            Consolidated Statements of Income
            (Amounts in millions, except per share data) 2026 2025 2024
            Total revenues 713,163 680,985 648,125
            Consolidated net income 22,270 20,157 16,270
            Consolidated net income attributable to noncontrolling interest (377) (721) (759)
            Consolidated net income attributable to the company $ 21,893 $ 19,436 $ 15,511
            """
        let reading = read(table, nil)
        #expect(reading.amounts["netIncome"]?.text == "21,893 million")   // not the 22,270 including noncontrolling interest
        #expect(reading.amounts["previousYearNetIncome"]?.text == "19,436 million")
    }

    @Test func netCashFromOperationsIsTheOperatingCashFlow() {
        let table = cashFlow.replacingOccurrences(of: "Net cash provided by operating activities 400 350 300",
                                                  with: "Net cash from operations 400 350 300")
        #expect(read(income, table).amounts["operatingCashFlow"]?.text == "400 million")
    }

    @Test func aBroaderCapexLineIsReadOnlyWhenNoStrictLineIsPrinted() {
        let broader = cashFlow.replacingOccurrences(
            of: "Purchases of property and equipment (90) (80) (70)",
            with: "Purchases related to property and equipment and intangible assets (95) (85) (75)")
        #expect(read(income, broader).amounts["capex"]?.text == "(95) million")
        let both = cashFlow.replacingOccurrences(
            of: "Purchases of property and equipment (90) (80) (70)",
            with: "Purchases of property and equipment (90) (80) (70)\nInvestment in property and equipment, net (88) (79) (69)")
        #expect(read(income, both).amounts["capex"]?.text == "(90) million")   // tamper: the strict line wins
    }

    @Test func aNoteReferenceInALabelDoesNotHideTheRow() {
        let table = income.replacingOccurrences(of: "Diluted $ 2.15 $ 1.95 $ 1.77",
                                                with: "Diluted net income per share (Note 12) $ 2.15 $ 1.95 $ 1.77")
        #expect(read(table, nil).amounts["eps"]?.text == "2.15")
    }

    // MARK: - Phase 2h: capex inside the investing section (R4)

    private func cashFlowWithSecondCapexLine(_ second: String) -> String {
        """
        CONSOLIDATED STATEMENTS OF CASH FLOWS
        (In millions)
        2025 2024
        Net income 210 190
        Net cash provided by operating activities 400 350
        Cash flows from investing activities:
        Purchases of property and equipment (90) (80)
        Net cash used in investing activities (150) (120)
        \(second)
        """
    }

    @Test(arguments: [
        "Cash flows from investing activities of discontinued operations:\nPurchases of property and equipment (38) —",
        "Cash flows from financing activities:\nAdditions to property, plant and equipment (30) (11)",
        "Supplemental disclosures:\nPurchases of property and equipment included in accrued liabilities 12 9",
    ])
    func capexIsReadInsideTheInvestingSectionOnly(second: String) {
        #expect(read(income, cashFlowWithSecondCapexLine(second)).amounts["capex"]?.text == "(90) million")
    }

    @Test func tamperWithoutAnInvestingSectionTwoCapexLinesStayNull() {
        let flat = """
            CONSOLIDATED STATEMENTS OF CASH FLOWS
            (In millions)
            2025 2024
            Net cash provided by operating activities 400 350
            Purchases of property and equipment (90) (80)
            Purchases of property and equipment (38) —
            """
        #expect(read(income, flat).abstained["capex"] == .ambiguous)
    }

    // MARK: - Phase 2h: titles in either word order

    @Test(arguments: ["CONSOLIDATED CASH FLOWS STATEMENTS", "CASH FLOWS STATEMENTS", "Cash Flow Statements"])
    func theCashFlowTitleIsRecognisedInEitherWordOrder(title: String) {
        let table = cashFlow.replacingOccurrences(of: "CONSOLIDATED STATEMENTS OF CASH FLOWS", with: title)
        #expect(StatementTableReader.recognises(.cashFlow, rows: rows(table)))
    }

    // MARK: - Phase 2h: the currency guard (R5)

    @Test(arguments: [
        "(In millions of euros, except per share amounts)", "(In thousands of Canadian dollars)", "€ in millions",
        "(EUR millions, except per share data)", "(In millions of Swiss francs)",
    ])
    func aStatementInAnotherCurrencyGivesNoAmount(header: String) {
        let foreign = income.replacingOccurrences(
            of: "(In millions, except number of shares, which are reflected in thousands, and per-share amounts)", with: header)
        let reading = read(foreign, nil)
        #expect(reading.amounts.isEmpty)
        #expect(reading.abstained["revenue"] == .currency && reading.abstained["eps"] == .currency)
    }

    @Test(arguments: [
        "(In millions of U.S. dollars, except per share amounts)", "(In thousands of US dollars)",
        "(In millions of dollars and shares, except per share amounts)", "(Dollars in millions, except per share data)",
    ])
    func tamperADollarHeaderIsStillRead(header: String) {
        let dollars = income.replacingOccurrences(
            of: "(In millions, except number of shares, which are reflected in thousands, and per-share amounts)", with: header)
        #expect(read(dollars, nil).amounts["revenue"] != nil)
        #expect(!StatementTableReader.foreignCurrency(in: rows(dollars)))
    }

    @Test func aForeignNoteBelowTheHeaderDoesNotMakeADollarStatementForeign() {
        let table = cashFlow.replacingOccurrences(
            of: "Net cash used in financing activities (200) (180) (160)",
            with: "Repayment of €750 million senior notes (812) — —\nNet cash used in financing activities (200) (180) (160)")
        #expect(!StatementTableReader.foreignCurrency(in: rows(table)))
        #expect(read(income, table).amounts["capex"]?.text == "(90) million")
    }

    // MARK: - Recognising a statement

    @Test func statementsAreRecognisedByTitleYearsAndKnownRows() {
        #expect(StatementTableReader.recognises(.income, rows: rows(income)))
        #expect(!StatementTableReader.recognises(.cashFlow, rows: rows(income)))
        #expect(StatementTableReader.recognises(.cashFlow, rows: rows(cashFlow)))
        #expect(!StatementTableReader.recognises(.income, rows: rows(cashFlow)))
    }

    @Test func aTitleWithConsolidatedInTheMiddleIsRecognised() {
        let title = cashFlow.replacingOccurrences(of: "CONSOLIDATED STATEMENTS OF CASH FLOWS",
                                                  with: "STATEMENTS OF CONSOLIDATED CASH FLOWS")
        #expect(StatementTableReader.recognises(.cashFlow, rows: rows(title)))
    }

    @Test func tamperAHeaderThatRepeatsTheYearsIsNotAStatement() {
        let consolidating = """
            SUPPLEMENTAL CONSOLIDATING DATA (continued)
            STATEMENTS OF CASH FLOWS
            (In millions)
            2025 2024 2025 2024
            Net income 210 190 200 180
            Net cash provided by operating activities 400 350 300 250
            Purchases of property and equipment (90) (80) (60) (50)
            Net cash used in investing activities (150) (120) (100) (90)
            """
        #expect(StatementTableReader.years(in: rows(consolidating)) == nil)
        #expect(!StatementTableReader.recognises(.cashFlow, rows: rows(consolidating)))
        #expect(read(income, consolidating).abstained["capex"] == .noYears)   // not the first group's (90)
    }

    @Test func tamperAComprehensiveIncomePageOrAnIndexIsNotTheIncomeStatement() {
        let comprehensive = income.replacingOccurrences(of: "CONSOLIDATED STATEMENTS OF OPERATIONS",
                                                        with: "CONSOLIDATED STATEMENTS OF COMPREHENSIVE INCOME")
        #expect(!StatementTableReader.recognises(.income, rows: rows(comprehensive)))
        let both = income.replacingOccurrences(of: "CONSOLIDATED STATEMENTS OF OPERATIONS",
                                               with: "CONSOLIDATED STATEMENTS OF OPERATIONS AND COMPREHENSIVE INCOME")
        #expect(StatementTableReader.recognises(.income, rows: rows(both)))
        let index = rows("""
            Index to Consolidated Financial Statements
            Consolidated Statements of Operations 29
            Consolidated Statements of Cash Flows 33
            """)
        #expect(!StatementTableReader.recognises(.income, rows: index))
    }
}
