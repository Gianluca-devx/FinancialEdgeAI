//
//  MetricsPresenterTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation
import Testing

struct MetricsPresenterTests {

    private let schema: Schema
    private let english = Locale(identifier: "en_US")

    init() throws {
        schema = try DatasetFiles.schema()
    }

    private func metrics(_ texts: [String: String]) -> FinancialMetrics {
        FinancialMetrics(texts: texts, schema: schema)
    }

    private func outcome(_ metrics: FinancialMetrics?, failure: ParseFailure? = nil, fence: Bool = false,
                         thinking: Bool = false, unreadable: [String] = []) -> ParseOutcome {
        ParseOutcome(metrics: metrics, failure: failure, hadFence: fence, hadThinking: thinking, unreadableKeys: unreadable)
    }

    // MARK: - Rows

    @Test func everyCoreKeyHasARowInTheOrderOfTheSchema() {
        let rows = MetricsPresenter.coreRows(metrics([:]), schema: schema, locale: english)
        #expect(rows.map(\.id) == schema.coreKeys)
        #expect(rows.map(\.label) == schema.coreFields.map(\.label))
        // A missing value is shown as null, not hidden.
        #expect(rows.allSatisfy { $0.value == "null" && $0.note == nil && !$0.isWarning })
    }

    @Test func aRowShowsTheNumberAndWhatWasPrinted() {
        let rows = MetricsPresenter.coreRows(
            metrics(["revenue": "$94 billion", "netIncomeGrowth": "-4%", "eps": "USD 2.1",
                     "revenueGrowth": "12 percent"]),
            schema: schema, locale: english)
        func row(_ key: String) -> MetricRow? { rows.first { $0.id == key } }
        #expect(row("revenue")?.value == "$94 bn")
        #expect(row("revenue")?.note == "printed: $94 billion")
        #expect(row("netIncomeGrowth")?.value == "-4%")
        #expect(row("revenueGrowth")?.value == "12%")
        #expect(row("eps")?.value == "$2.10")
        #expect(row("capex")?.value == "null")
    }

    @Test func aStringThatCannotBeReadIsShownWithAWarningAndTheOtherRowsStay() {
        let rows = MetricsPresenter.coreRows(
            metrics(["revenue": "about 5 billion", "netIncome": "$21 billion"]), schema: schema, locale: english)
        let revenue = rows.first { $0.id == "revenue" }
        #expect(revenue?.value == "about 5 billion")
        #expect(revenue?.isWarning == true)
        #expect(revenue?.note == "could not read this value")
        #expect(rows.first { $0.id == "netIncome" }?.value == "$21 bn")
        #expect(rows.count == schema.coreKeys.count)
    }

    @Test func aGrowthTheTextDidNotPrintIsFilledInAndMarkedDerived() {
        let rows = MetricsPresenter.coreRows(
            metrics(["revenue": "$120 billion", "previousYearRevenue": "$100 billion"]),
            schema: schema, locale: english)
        let growth = rows.first { $0.id == "revenueGrowth" }
        #expect(growth?.value == "20%")
        #expect(growth?.note?.contains("derived") == true)
    }

    @Test func aPrintedGrowthIsNotReplacedByTheDerivedOne() {
        let rows = MetricsPresenter.coreRows(
            metrics(["revenue": "$120 billion", "previousYearRevenue": "$100 billion", "revenueGrowth": "21%"]),
            schema: schema, locale: english)
        let growth = rows.first { $0.id == "revenueGrowth" }
        #expect(growth?.value == "21%")
        #expect(growth?.note == "printed: 21%")
    }

    @Test func derivedRowsAreTheOnesWhoseInputsAreCore() {
        let rows = MetricsPresenter.derivedRows(
            metrics(["revenue": "$100 billion", "operatingIncome": "$20 billion", "netIncome": "$10 billion",
                     "operatingCashFlow": "$15 billion", "capex": "$5 billion"]),
            schema: schema, locale: english)
        // Return on equity, debt to equity, current ratio and net debt need the extended tier.
        #expect(rows.map(\.id) == ["operatingMargin", "netMargin", "freeCashFlow", "interestCoverage"])
        func row(_ id: String) -> MetricRow? { rows.first { $0.id == id } }
        #expect(row("operatingMargin")?.value == "20%")
        #expect(row("netMargin")?.value == "10%")
        #expect(row("freeCashFlow")?.value == "$10 bn")
        #expect(row("freeCashFlow")?.note == "derived")
        #expect(row("interestCoverage")?.value == "null")
    }

    // MARK: - The balance sheet (extended call)

    @Test func everyExtendedKeyHasARowInTheOrderOfTheSchema() {
        let rows = MetricsPresenter.extendedRows(metrics([:]), schema: schema, locale: english)
        #expect(rows.map(\.id) == schema.extendedKeys)
        #expect(rows.map(\.label) == schema.extendedFields.map(\.label))
        #expect(rows.allSatisfy { $0.value == "null" && $0.note == nil && !$0.isWarning })
    }

    @Test func anExtendedRowShowsTheNumberAndWhatWasPrinted() {
        let rows = MetricsPresenter.extendedRows(
            metrics(["totalDebt": "$12.5 billion", "cash": "4,200 million dollars"]), schema: schema, locale: english)
        #expect(rows.first { $0.id == "totalDebt" }?.value == "$12.5 bn")
        #expect(rows.first { $0.id == "totalDebt" }?.note == "printed: $12.5 billion")
        #expect(rows.first { $0.id == "cash" }?.value == "$4.2 bn")
        #expect(rows.first { $0.id == "currentAssets" }?.value == "null")
    }

    @Test func anUnreadableExtendedStringIsShownWithAWarning() {
        let rows = MetricsPresenter.extendedRows(
            metrics(["cash": "a lot", "shareholdersEquity": "$30 billion"]), schema: schema, locale: english)
        let cash = rows.first { $0.id == "cash" }
        #expect(cash?.value == "a lot")
        #expect(cash?.isWarning == true)
        #expect(rows.first { $0.id == "shareholdersEquity" }?.value == "$30 bn")
        #expect(rows.count == schema.extendedKeys.count)
    }

    @Test func theRatiosThatNeedTheBalanceSheetAppearWhenTheExtendedCallWasMade() throws {
        let both = metrics(["netIncome": "$5 billion", "totalDebt": "$30 billion", "shareholdersEquity": "$40 billion",
                            "currentAssets": "$15 billion", "currentLiabilities": "$10 billion", "cash": "$12 billion"])
        let rows = MetricsPresenter.derivedRows(both, schema: schema, includeExtended: true, locale: english)
        func row(_ id: String) -> MetricRow? { rows.first { $0.id == id } }
        for id in ["roe", "debtToEquity", "currentRatio", "netDebt"] {
            #expect(row(id) != nil, "\(id) must be listed")
        }
        #expect(row("roe")?.value == "12.5%")
        #expect(row("debtToEquity")?.value == "0.75")
        #expect(row("currentRatio")?.value == "1.5")
        #expect(row("netDebt")?.value == "$18 bn")
        #expect(row("netDebt")?.note == "derived")
        // Without the flag the same metrics still hide them.
        let without = MetricsPresenter.derivedRows(both, schema: schema, locale: english)
        #expect(without.map(\.id).contains("roe") == false)
    }

    @Test func aRatioWithAMissingInputIsNullNotHiddenOnceTheBalanceSheetWasAsked() {
        let onlyDebt = metrics(["totalDebt": "$30 billion"])
        let rows = MetricsPresenter.derivedRows(onlyDebt, schema: schema, includeExtended: true, locale: english)
        #expect(rows.first { $0.id == "debtToEquity" }?.value == "null")
        #expect(rows.first { $0.id == "netDebt" }?.value == "null")
    }

    // MARK: - Formatting

    @Test func valuesAreFormattedByTheirKind() {
        #expect(MetricsPresenter.display(94, kind: .amount, locale: english) == "$94 bn")
        #expect(MetricsPresenter.display(0.726, kind: .amount, locale: english) == "$0.726 bn")
        #expect(MetricsPresenter.display(1750, kind: .amount, locale: english) == "$1,750 bn")
        #expect(MetricsPresenter.display(23.469387, kind: .percent, locale: english) == "23.47%")
        #expect(MetricsPresenter.display(-4, kind: .percent, locale: english) == "-4%")
        #expect(MetricsPresenter.display(2.1, kind: .perShare, locale: english) == "$2.10")
        #expect(MetricsPresenter.display(4, kind: .ratio, locale: english) == "4")
        #expect(MetricsPresenter.display(0.75, kind: .ratio, locale: english) == "0.75")
    }

    @Test func theLocaleOfTheUserIsRespected() {
        let italian = Locale(identifier: "it_IT")
        #expect(MetricsPresenter.display(0.726, kind: .amount, locale: italian) == "$0,726 bn")
    }

    // MARK: - Status

    @Test func theStatusSaysWhatHadToBeSkipped() {
        #expect(MetricsPresenter.status(for: outcome(metrics([:]))) == "Decoded")
        #expect(MetricsPresenter.status(for: outcome(metrics([:]), fence: true))
                == "Decoded, after skipping a code fence")
        #expect(MetricsPresenter.status(for: outcome(metrics([:]), fence: true, thinking: true))
                == "Decoded, after skipping a reasoning block and a code fence")
    }

    @Test func theStatusCountsTheValuesThatCouldNotBeRead() {
        #expect(MetricsPresenter.status(for: outcome(metrics([:]), unreadable: ["revenue"]))
                == "Decoded; 1 value could not be read")
        #expect(MetricsPresenter.status(for: outcome(metrics([:]), unreadable: ["revenue", "eps"]))
                == "Decoded; 2 values could not be read")
    }

    @Test func theStatusNamesEachFailure() {
        #expect(MetricsPresenter.status(for: outcome(nil, failure: .noJSON)) == "No JSON found in the answer")
        #expect(MetricsPresenter.status(for: outcome(nil, failure: .invalidJSON)) == "The answer is not valid JSON")
        #expect(MetricsPresenter.status(for: outcome(nil, failure: .wrongSchema("missing eps")))
                == "Valid JSON, wrong schema: missing eps")
    }

    // MARK: - The schema, the parser and the screen agree

    @Test func everyCoreKeyHasAParserPathAndARow() {
        let skeleton = "{" + schema.coreKeys.map { "\"\($0)\": null" }.joined(separator: ",") + "}"
        let parsed = MetricsParser.parse(skeleton, schema: schema)
        #expect(parsed.isSchemaValid)
        let rows = MetricsPresenter.coreRows(parsed.metrics ?? metrics([:]), schema: schema, locale: english)
        #expect(Set(rows.map(\.id)) == Set(schema.coreKeys))
    }
}
