//
//  UnusedAmountsTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 19/10/2026.
//
import Foundation
import Testing

/// The possible-miss hint (`UnusedAmounts`) and the rows of the "Check" group (`MetricsPresenter.checkRows`).
struct UnusedAmountsTests {

    private let schema = try! DatasetFiles.schema()

    private func metrics(_ values: [String: Double]) -> FinancialMetrics {
        FinancialMetrics(texts: [:], values: values)
    }

    // MARK: - Finding amounts

    @Test(arguments: [
        ("Revenue was $46.9 billion.", 46.9), ("Net income was USD 11.6 billion.", 11.6),
        ("Net income was 11.6 billion dollars.", 11.6), ("Capex was $25.6bn.", 25.6),
        ("Debt was $924 million.", 0.924), ("Sales were $1,817M.", 1.817),
        ("Revenue was US$11.3 billion.", 11.3), ("Revenue was 11.3 billion USD.", 11.3),
        ("Operating income was USD41 billion.", 41), ("Revenue was $ 4.2 billion.", 4.2),
        ("Cost was $7.5 thousand.", 0.0000075),
    ])
    func everyFormWithAUnitWordIsFound(statement: String, billions: Double) throws {
        let found = UnusedAmounts.amounts(in: statement)
        let amount = try #require(found.first, "\(statement)")
        #expect(found.count == 1)
        #expect(abs(amount.billions - billions) <= 1e-9 * max(1, billions))
    }

    @Test(arguments: [
        "Shares closed the year at $85.90.", "Operating margin was 12.5%.", "The company employed 162,000 people.",
        "It opened 14 new stores.", "A dividend of $0.56 per share was declared.", "EPS was $2.35.",
        "Growth of 14% year over year.", "Revenue was 46.9 in the table.",
    ])
    func whatIsNotAnAmountWithAUnitWordIsNotFound(statement: String) {
        #expect(UnusedAmounts.amounts(in: statement).isEmpty, "\(statement)")
    }

    @Test func theAmountsComeInTheOrderOfTheText() {
        let found = UnusedAmounts.amounts(in: "A was $3 billion, B was USD 1 billion and C was 2 billion dollars.")
        #expect(found.map(\.billions) == [3, 1, 2])
        #expect(found.map(\.text) == ["$3 billion", "USD 1 billion", "2 billion dollars"])
    }

    // MARK: - Used and unused

    @Test func anAmountThatAFieldUsedIsNotListed() {
        let statement = "Revenue was $46.9 billion and net income was 11.6 billion dollars."
        let unused = UnusedAmounts.unused(
            in: statement, metrics: [metrics(["revenue": 46.9, "netIncome": 11.6])], schema: schema)
        #expect(unused.isEmpty)
    }

    @Test func anAmountThatNoFieldUsedIsListedWithItsText() {
        let statement = "Revenue was $46.9 billion and net income was 11.6 billion dollars."
        let unused = UnusedAmounts.unused(in: statement, metrics: [metrics(["revenue": 46.9])], schema: schema)
        #expect(unused.map(\.text) == ["11.6 billion dollars"])
    }

    @Test func theSameAmountTwiceIsListedOnce() {
        let unused = UnusedAmounts.unused(
            in: "Total assets were $9.2 billion. Free cash flow was $9.2 billion.", metrics: [metrics([:])], schema: schema)
        #expect(unused.count == 1)
    }

    @Test func aValueThatIsNotAnAmountFieldDoesNotUseAnAmount() {
        // eps and growth are not amounts: a 5.0 there must not hide a "$5 billion" in the text.
        let unused = UnusedAmounts.unused(
            in: "Revenue was $5 billion.", metrics: [metrics(["eps": 5, "revenueGrowth": 5])], schema: schema)
        #expect(unused.map(\.billions) == [5])
    }

    @Test func theBalanceSheetFieldsCountAsUsedOnceTheSecondCallWasMade() {
        let statement = "Net income was $2 billion. Total debt was $12.5 billion."
        let core = metrics(["netIncome": 2])
        let extended = metrics(["totalDebt": 12.5])
        #expect(UnusedAmounts.unused(in: statement, metrics: [core], schema: schema).map(\.text) == ["$12.5 billion"])
        #expect(UnusedAmounts.unused(in: statement, metrics: [core, extended], schema: schema).isEmpty)
    }

    @Test func aStatementWithNoAmountHasNothingUnused() {
        #expect(UnusedAmounts.unused(in: "Customer demand stayed steady.", metrics: [metrics([:])], schema: schema).isEmpty)
    }

    @Test func aMissedPercentageIsNotSeen() {
        // The limit of the hint, written down: only amounts with a unit word are looked for.
        #expect(UnusedAmounts.unused(in: "Net income grew 14%.", metrics: [metrics([:])], schema: schema).isEmpty)
    }

    // MARK: - The rows of the Check group

    private func outcome(_ keys: [String], tier: FieldTier = .core, repair: Bool = true) -> ParseOutcome {
        let body = keys.map { "\"\($0)\": null" }.joined(separator: ", ")
        return MetricsParser.parse("{\(body)}", schema: schema, tier: tier, repairKeys: repair)
    }

    private var core: [String] { schema.keys(for: .core) }

    @Test func nothingIsShownWhenThereIsNothingToSay() {
        let rows = MetricsPresenter.checkRows(
            statement: "Customer demand stayed steady.", core: outcome(core), extended: nil, schema: schema)
        #expect(rows.isEmpty)
    }

    @Test func oneUnusedAmountGivesTheHintWithTheAmount() throws {
        let rows = MetricsPresenter.checkRows(
            statement: "Net earnings stood at 11.6 billion dollars.", core: outcome(core), extended: nil, schema: schema)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.kind == .possibleMiss)
        #expect(row.title == "Possible miss")
        #expect(row.detail == "11.6 billion dollars is in the text but in no field.")
        #expect(row.accessibilityLabel == "Possible miss. 11.6 billion dollars is in the text but in no field.")
    }

    @Test func severalUnusedAmountsAreCountedAndTheListIsCut() throws {
        let statement = "A $1 billion, B $2 billion, C $3 billion, D $4 billion, E $5 billion, F $6 billion."
        let row = try #require(MetricsPresenter.checkRows(
            statement: statement, core: outcome(core), extended: nil, schema: schema).first)
        #expect(row.detail == "6 amounts are in the text but in no field: $1 billion, $2 billion, $3 billion, $4 billion and 2 more.")
    }

    @Test func aRepairedKeyGivesACautionRowBeforeTheHint() throws {
        var keys = core
        keys[9] = "previous6YearEps"
        let rows = MetricsPresenter.checkRows(
            statement: "Revenue was $5 billion.", core: outcome(keys), extended: nil, schema: schema)
        #expect(rows.map(\.kind) == [.keyRepaired, .possibleMiss])
        #expect(rows[0].id == "key-repaired-core")
        #expect(rows[0].detail == "The model wrote previous6YearEps where previousYearEps belongs (key 10); it was read as previousYearEps.")
    }

    @Test func theExtendedCallsRepairIsNamedForTheExtendedCall() throws {
        var keys = schema.keys(for: .extended)
        keys[1] = "shareholdersEquityy"
        let rows = MetricsPresenter.checkRows(
            statement: "Nothing here.", core: outcome(core), extended: outcome(keys, tier: .extended), schema: schema)
        #expect(rows.map(\.id) == ["key-repaired-extended"])
    }

    @Test func noHintWhenTheCoreAnswerCouldNotBeRead() {
        let failed = MetricsParser.parse("I cannot answer.", schema: schema, repairKeys: true)
        #expect(MetricsPresenter.checkRows(
            statement: "Revenue was $5 billion.", core: failed, extended: nil, schema: schema).isEmpty)
        #expect(MetricsPresenter.checkRows(
            statement: nil, core: outcome(core), extended: nil, schema: schema).isEmpty)
    }

    @Test func theStatusSaysThatAKeyWasRepaired() {
        var keys = core
        keys[9] = "previous5000"
        let status = MetricsPresenter.status(for: outcome(keys))
        #expect(status == "Decoded; key previous5000 read as previousYearEps")
        #expect(MetricsPresenter.status(for: outcome(core)) == "Decoded")
    }
}
