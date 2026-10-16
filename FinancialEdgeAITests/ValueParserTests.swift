//
//  ValueParserTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation
import Testing

struct ValueParserTests {

    private func expectClose(_ actual: Double?, _ expected: Double, _ text: String) {
        guard let actual else {
            Issue.record("\(text) was not read, expected \(expected)")
            return
        }
        #expect(abs(actual - expected) < 1e-9, "\(text) gave \(actual), expected \(expected)")
    }

    // MARK: - Amounts (billions of USD)

    @Test(arguments: [
        ("$726 million", 0.726),
        ("726 million", 0.726),
        ("USD 726 million", 0.726),
        ("US$ 5 bn", 5.0),
        ("$6.9bn", 6.9),
        ("$2.1 billion", 2.1),
        ("$12.4 Billion", 12.4),
        ("$41 billion", 41.0),
        ("2,772 million", 2.772),
        ("$1,750 million", 1.75),
        ("1,234.56 million", 1.23456),
        ("$410m", 0.41),
        ("726 million dollars", 0.726),
        ("2.1 billion dollars", 2.1),
        ("$3.5 trillion", 3500.0),
        ("$250 thousand", 0.00025),
        ("$250k", 0.00025),
        ("$ 726  Million", 0.726),
        ("$726\u{00A0}million", 0.726),
        ("$21 billion.", 21.0),
        ("\"$21 billion\"", 21.0),
        ("  $21 billion \n", 21.0),
    ])
    func amountsBecomeBillions(text: String, expected: Double) {
        expectClose(ValueParser.parse(text, kind: .amount), expected, text)
    }

    @Test func anAmountWithNoUnitWordIsPlainDollars() {
        expectClose(ValueParser.parse("$726", kind: .amount), 7.26e-7, "$726")
    }

    @Test(arguments: [
        ("-$1.2 billion", -1.2),
        ("$-1.2 billion", -1.2),
        ("-1.2 billion", -1.2),
        ("\u{2212}1.2 billion", -1.2),
        ("(1.2) billion", -1.2),
        ("($1.2 billion)", -1.2),
        ("(1,200) million", -1.2),
        ("+1.2 billion", 1.2),
    ])
    func negativeAmounts(text: String, expected: Double) {
        expectClose(ValueParser.parse(text, kind: .amount), expected, text)
    }

    // MARK: - Percentages

    @Test(arguments: [
        ("23.5%", 23.5),
        ("-4%", -4.0),
        ("+3.1%", 3.1),
        ("12 percent", 12.0),
        ("12 per cent", 12.0),
        ("0.5 %", 0.5),
        ("12", 12.0),
        ("(2.5%)", -2.5),
        ("\u{2212}7.1%", -7.1),
    ])
    func percentagesKeepTheirNumber(text: String, expected: Double) {
        expectClose(ValueParser.parse(text, kind: .percent), expected, text)
    }

    // MARK: - Per share

    @Test(arguments: [
        ("$0.41", 0.41),
        ("0.41", 0.41),
        ("USD 1.25", 1.25),
        ("$ 12", 12.0),
        ("(0.30)", -0.30),
        ("-$0.30", -0.30),
    ])
    func perShareValuesStayInDollars(text: String, expected: Double) {
        expectClose(ValueParser.parse(text, kind: .perShare), expected, text)
    }

    // MARK: - Never guessed

    @Test(arguments: [
        "", "   ", "n/a", "null", "twelve", "about 5 billion", "down 4%", "approximately $5 billion",
        "\u{20AC}5 billion", "5 billion euros", "\u{00A3}3 million",
        "1.2.3", "12,34 million", "5 billion billion", "--5", "5-", "$$5", "$5 $",
        "(-1.2) billion", "-(1.2) billion", "((1.2))", "(1.2", "1.2)", ")1.2(",
        "$5 billion dollars usd", "41 cents",
    ])
    func unreadableAmountsAreNil(text: String) {
        #expect(ValueParser.parse(text, kind: .amount) == nil, "\(text) must not be read")
    }

    @Test func eachKindRefusesTheUnitsOfTheOthers() {
        #expect(ValueParser.parse("5%", kind: .amount) == nil)
        #expect(ValueParser.parse("5 percent", kind: .amount) == nil)
        #expect(ValueParser.parse("$5 billion", kind: .percent) == nil)
        #expect(ValueParser.parse("$5%", kind: .percent) == nil)
        #expect(ValueParser.parse("5 million", kind: .percent) == nil)
        #expect(ValueParser.parse("5 million", kind: .perShare) == nil)
        #expect(ValueParser.parse("5%", kind: .perShare) == nil)
        #expect(ValueParser.parse("5", kind: .ratio) == nil)
    }

    // MARK: - Magnitudes

    private func field(_ key: String, kind: FieldKind, magnitude: Bool?) -> FieldSpec {
        FieldSpec(key: key, tier: .core, kind: kind, magnitude: magnitude, label: key, description: "d")
    }

    @Test func aMagnitudeFieldIsAlwaysPositive() {
        let expense = field("interestExpense", kind: .amount, magnitude: true)
        expectClose(ValueParser.parse("(1.2) billion", field: expense), 1.2, "(1.2) billion")
        expectClose(ValueParser.parse("-3 million", field: expense), 0.003, "-3 million")
        expectClose(ValueParser.parse("$3 million", field: expense), 0.003, "$3 million")
        #expect(ValueParser.parse("nope", field: expense) == nil)
    }

    @Test func otherFieldsKeepTheirSign() {
        let income = field("netIncome", kind: .amount, magnitude: nil)
        expectClose(ValueParser.parse("(1.2) billion", field: income), -1.2, "(1.2) billion")
        let explicitlyOff = field("netIncome", kind: .amount, magnitude: false)
        expectClose(ValueParser.parse("-1.2 billion", field: explicitlyOff), -1.2, "-1.2 billion")
    }

    // MARK: - The values the dataset prints

    @Test func theFormsTheGeneratorWritesAreAllRead() {
        // Pool A and pool B amount and percent forms of Scripts/generate_dataset.py.
        let amounts = ["$94 billion", "USD 94 billion", "$94bn", "94 billion dollars",
                       "$410 million", "USD 410 million", "$410m", "410 million dollars", "$1,750 million"]
        for text in amounts {
            #expect(ValueParser.parse(text, kind: .amount) != nil, "\(text)")
        }
        for text in ["12%", "6.5%", "12 percent", "6.5 percent"] {
            #expect(ValueParser.parse(text, kind: .percent) != nil, "\(text)")
        }
    }
}
