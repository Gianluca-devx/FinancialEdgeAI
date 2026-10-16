//
//  SchemaTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation
import Testing

struct SchemaTests {

    private static func realSchema() throws -> Schema {
        try Schema(data: Data(contentsOf: DatasetFiles.url("Dataset/schema.json")))
    }

    private static func field(_ key: String, tier: String = "core", kind: String = "amount") -> String {
        #"{"key": "\#(key)", "tier": "\#(tier)", "kind": "\#(kind)", "label": "\#(key)", "description": "d"}"#
    }

    private static func derived(_ key: String, inputs: [String], kind: String = "amount", fills: String? = nil) -> String {
        let inputList = inputs.map { "\"\($0)\"" }.joined(separator: ",")
        let fill = fills.map { #", "fills": "\#($0)""# } ?? ""
        return #"{"key": "\#(key)", "kind": "\#(kind)", "label": "\#(key)", "inputs": [\#(inputList)]\#(fill)}"#
    }

    private static func json(version: Int = 1, fields: [String], derived: [String] = []) -> Data {
        Data(#"{"version": \#(version), "fields": [\#(fields.joined(separator: ","))], "derived": [\#(derived.joined(separator: ","))]}"#.utf8)
    }

    // MARK: - The real schema

    @Test func theRealSchemaHasThe13CoreFieldsInOrder() throws {
        let schema = try Self.realSchema()
        #expect(schema.coreKeys == [
            "revenue", "operatingIncome", "netIncome", "eps", "interestExpense",
            "operatingCashFlow", "capex", "previousYearRevenue", "previousYearNetIncome", "previousYearEps",
            "revenueGrowth", "netIncomeGrowth", "epsGrowth",
        ])
    }

    @Test func theExtendedTierIsTheFiveBalanceSheetFields() throws {
        let schema = try Self.realSchema()
        #expect(schema.extendedKeys == ["totalDebt", "shareholdersEquity", "currentAssets", "currentLiabilities", "cash"])
    }

    @Test func kindsFollowTheSpec() throws {
        let schema = try Self.realSchema()
        #expect(schema.field("revenue")?.kind == .amount)
        #expect(schema.field("capex")?.kind == .amount)
        #expect(schema.field("eps")?.kind == .perShare)
        #expect(schema.field("previousYearEps")?.kind == .perShare)
        for key in ["revenueGrowth", "netIncomeGrowth", "epsGrowth"] {
            #expect(schema.field(key)?.kind == .percent)
        }
    }

    @Test func onlyInterestExpenseAndCapexAreStoredAsMagnitudes() throws {
        let schema = try Self.realSchema()
        #expect(schema.fields.filter(\.isMagnitude).map(\.key) == ["interestExpense", "capex"])
    }

    @Test func theThreeGrowthsCanBeFilledByCode() throws {
        let schema = try Self.realSchema()
        let filled = schema.derived.compactMap(\.fills)
        #expect(filled == ["revenueGrowth", "netIncomeGrowth", "epsGrowth"])
        for item in schema.derived {
            #expect(!item.inputs.isEmpty)
        }
    }

    @Test func theRealSchemaHasElevenDerivedValues() throws {
        let schema = try Self.realSchema()
        #expect(schema.derived.count == 11)
    }

    @Test func theBundledCopyIsIdentical() throws {
        let original = try Data(contentsOf: DatasetFiles.url("Dataset/schema.json"))
        let copy = try Data(contentsOf: DatasetFiles.url("FinancialEdgeAI/Resources/schema.json"))
        #expect(original == copy)
    }

    // MARK: - A schema is checked when it is read

    @Test func aValidSchemaIsAccepted() throws {
        let schema = try Schema(data: Self.json(
            fields: [Self.field("a"), Self.field("b", tier: "extended"), Self.field("g", kind: "percent")],
            derived: [Self.derived("ratio", inputs: ["a", "b"], kind: "ratio"),
                      Self.derived("gDerived", inputs: ["a"], kind: "percent", fills: "g")]))
        #expect(schema.coreKeys == ["a", "g"])
        #expect(schema.extendedKeys == ["b"])
        #expect(schema.field("missing") == nil)
    }

    @Test func aDuplicateKeyIsRejected() {
        #expect(throws: SchemaError.duplicateKey("a")) {
            try Schema(data: Self.json(fields: [Self.field("a"), Self.field("a")]))
        }
    }

    @Test func aDerivedKeyCannotReuseAFieldKey() {
        #expect(throws: SchemaError.duplicateKey("a")) {
            try Schema(data: Self.json(fields: [Self.field("a")], derived: [Self.derived("a", inputs: ["a"])]))
        }
    }

    @Test func aDerivedValueCannotReadAnUnknownField() {
        #expect(throws: SchemaError.unknownInput(derived: "d", input: "nope")) {
            try Schema(data: Self.json(fields: [Self.field("a")], derived: [Self.derived("d", inputs: ["a", "nope"])]))
        }
    }

    @Test func aFillMustHaveTheKindOfTheFieldItFills() {
        #expect(throws: SchemaError.badFill(derived: "d", target: "g")) {
            try Schema(data: Self.json(
                fields: [Self.field("a"), Self.field("g", kind: "percent")],
                derived: [Self.derived("d", inputs: ["a"], kind: "amount", fills: "g")]))
        }
        #expect(throws: SchemaError.badFill(derived: "d", target: "unknown")) {
            try Schema(data: Self.json(
                fields: [Self.field("a")],
                derived: [Self.derived("d", inputs: ["a"], fills: "unknown")]))
        }
    }

    @Test func anUnsupportedVersionIsRejected() {
        #expect(throws: SchemaError.unsupportedVersion(2)) {
            try Schema(data: Self.json(version: 2, fields: [Self.field("a")]))
        }
    }

    @Test func aSchemaWithoutCoreFieldsIsRejected() {
        #expect(throws: SchemaError.noCoreFields) {
            try Schema(data: Self.json(fields: [Self.field("a", tier: "extended")]))
        }
    }

    @Test func garbageIsReportedAsMalformed() {
        #expect {
            try Schema(data: Data("not json".utf8))
        } throws: { error in
            if case SchemaError.malformed = error { return true }
            return false
        }
    }
}
