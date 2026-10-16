//
//  DerivationsTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation
import Testing

struct DerivationsTests {

    private static func realSchema() throws -> Schema {
        try Schema(data: Data(contentsOf: DatasetFiles.url("Dataset/schema.json")))
    }

    private func derive(_ key: String, _ extracted: [String: Double]) throws -> Double? {
        let schema = try Self.realSchema()
        let spec = try #require(schema.derived.first { $0.key == key })
        return Derivations.value(for: spec, extracted: extracted)
    }

    private func expectClose(_ actual: Double?, _ expected: Double, _ name: String) {
        guard let actual else {
            Issue.record("\(name) is nil, expected \(expected)")
            return
        }
        #expect(abs(actual - expected) < 1e-9, "\(name) gave \(actual), expected \(expected)")
    }

    // MARK: - The schema and the formulas agree

    @Test func everyDerivedValueOfTheSchemaHasAFormulaAndNothingElse() throws {
        let schema = try Self.realSchema()
        #expect(Derivations.formulaKeys == Set(schema.derived.map(\.key)))
    }

    // MARK: - Formulas

    @Test func growthIsTheChangeOverThePreviousValue() throws {
        // "10 against 9.7" is +3.1%, not 0.3: the baseline's calculation error.
        expectClose(try derive("netIncomeGrowthDerived", ["netIncome": 10, "previousYearNetIncome": 9.7]),
                    (10 - 9.7) / 9.7 * 100, "net income growth")
        expectClose(try derive("revenueGrowthDerived", ["revenue": 0.726, "previousYearRevenue": 0.588]),
                    23.469387755102, "revenue growth")
        expectClose(try derive("epsGrowthDerived", ["eps": 0.41, "previousYearEps": 0.58]),
                    -29.310344827586, "EPS growth")
    }

    @Test func growthFromANegativePreviousValueUsesItsSize() throws {
        // From a loss of 2 to a profit of 1 is +150%, not -150%.
        expectClose(try derive("netIncomeGrowthDerived", ["netIncome": 1, "previousYearNetIncome": -2]), 150, "growth")
        expectClose(try derive("netIncomeGrowthDerived", ["netIncome": -1, "previousYearNetIncome": 2]), -150, "growth")
    }

    @Test func marginsAreShareOfRevenue() throws {
        expectClose(try derive("operatingMargin", ["operatingIncome": 0.128, "revenue": 0.726]), 17.630853994490, "operating margin")
        expectClose(try derive("netMargin", ["netIncome": 21, "revenue": 94]), 22.340425531915, "net margin")
    }

    @Test func freeCashFlowIsOperatingCashFlowMinusCapex() throws {
        expectClose(try derive("freeCashFlow", ["operatingCashFlow": 10, "capex": 3]), 7, "free cash flow")
        expectClose(try derive("freeCashFlow", ["operatingCashFlow": 2, "capex": 3]), -1, "negative free cash flow")
    }

    @Test func ratiosAndReturns() throws {
        expectClose(try derive("interestCoverage", ["operatingIncome": 12, "interestExpense": 3]), 4, "interest coverage")
        expectClose(try derive("roe", ["netIncome": 5, "shareholdersEquity": 40]), 12.5, "ROE")
        expectClose(try derive("debtToEquity", ["totalDebt": 30, "shareholdersEquity": 40]), 0.75, "debt to equity")
        expectClose(try derive("currentRatio", ["currentAssets": 15, "currentLiabilities": 10]), 1.5, "current ratio")
        expectClose(try derive("netDebt", ["totalDebt": 30, "cash": 12]), 18, "net debt")
        expectClose(try derive("netDebt", ["totalDebt": 5, "cash": 12]), -7, "net cash")
    }

    // MARK: - Missing inputs and zero divisors

    @Test func aMissingInputGivesNil() throws {
        #expect(try derive("operatingMargin", ["operatingIncome": 1]) == nil)
        #expect(try derive("operatingMargin", ["revenue": 1]) == nil)
        #expect(try derive("freeCashFlow", [:]) == nil)
        #expect(try derive("netIncomeGrowthDerived", ["netIncome": 10]) == nil)
    }

    @Test func aZeroDivisorGivesNil() throws {
        #expect(try derive("operatingMargin", ["operatingIncome": 1, "revenue": 0]) == nil)
        #expect(try derive("interestCoverage", ["operatingIncome": 1, "interestExpense": 0]) == nil)
        #expect(try derive("debtToEquity", ["totalDebt": 1, "shareholdersEquity": 0]) == nil)
        #expect(try derive("currentRatio", ["currentAssets": 1, "currentLiabilities": 0]) == nil)
        #expect(try derive("netIncomeGrowthDerived", ["netIncome": 1, "previousYearNetIncome": 0]) == nil)
    }

    @Test func aZeroNumeratorIsAValue() throws {
        expectClose(try derive("operatingMargin", ["operatingIncome": 0, "revenue": 5]), 0, "zero margin")
    }

    // MARK: - Over the whole schema

    @Test func valuesReturnsOnlyWhatCanBeCalculated() throws {
        let schema = try Self.realSchema()
        let values = Derivations.values(in: schema, extracted: [
            "revenue": 100, "operatingIncome": 20, "netIncome": 10,
            "operatingCashFlow": 15, "capex": 5,
        ])
        #expect(Set(values.keys) == ["operatingMargin", "netMargin", "freeCashFlow"])
        expectClose(values["operatingMargin"], 20, "operating margin")
        expectClose(values["netMargin"], 10, "net margin")
        expectClose(values["freeCashFlow"], 10, "free cash flow")
    }

    @Test func aPrintedGrowthIsNeverReplaced() throws {
        let schema = try Self.realSchema()
        let filled = Derivations.filledFields(in: schema, extracted: [
            "netIncome": 10, "previousYearNetIncome": 9.7, "netIncomeGrowth": 3,
            "revenue": 726, "previousYearRevenue": 588,
        ])
        // netIncomeGrowth was printed (3), so only revenueGrowth is filled in.
        #expect(Set(filled.keys) == ["revenueGrowth"])
        expectClose(filled["revenueGrowth"], (726 - 588) / 588.0 * 100, "revenue growth")
    }

    @Test func aGrowthWithoutBothAmountsIsNotFilled() throws {
        let schema = try Self.realSchema()
        let filled = Derivations.filledFields(in: schema, extracted: ["netIncome": 10, "revenue": 5])
        #expect(filled.isEmpty)
    }
}
