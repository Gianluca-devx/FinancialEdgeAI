//
//  DatasetTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation
import Testing

struct PromptTemplateTests {

    @Test func rendersAndRecoversTheStatement() throws {
        let template = try #require(PromptTemplate(text: "Read:\n\"<<STATEMENT>>\"\nThen answer."))
        let prompt = template.render("Revenue was 5.")
        #expect(prompt == "Read:\n\"Revenue was 5.\"\nThen answer.")
        #expect(template.statement(in: prompt) == "Revenue was 5.")
    }

    @Test func needsExactlyOnePlaceholder() {
        #expect(PromptTemplate(text: "no placeholder") == nil)
        #expect(PromptTemplate(text: "<<STATEMENT>> and <<STATEMENT>>") == nil)
    }

    @Test func aPromptFromAnotherTemplateDoesNotMatch() throws {
        let template = try #require(PromptTemplate(text: "A <<STATEMENT>> B"))
        #expect(template.statement(in: "X something Y") == nil)
    }

    @Test func theRealTemplateHasOnePlaceholder() throws {
        _ = try DatasetFiles.promptTemplate()
    }

    /// The field list of the prompt is generated from the schema. The Python validator checks the whole
    /// text; this checks, from Swift, that the prompt asks for the core keys, in order, and for nothing else.
    @Test func thePromptAsksForTheCoreFieldsOfTheSchema() throws {
        let prompt = try DatasetFiles.text("Dataset/prompt_template.txt")
        let schema = try DatasetFiles.schema()
        let bulletKeys = prompt.split(separator: "\n")
            .filter { $0.hasPrefix("- ") }
            .compactMap { $0.dropFirst(2).split(separator: ":").first.map(String.init) }
        #expect(bulletKeys == schema.coreKeys)
        for key in schema.extendedKeys {
            #expect(!prompt.contains("\"\(key)\""), "the extended field \(key) must not be in the core prompt")
        }
    }
}

extension PromptTemplateTests {

    /// The extended prompt is rendered from the schema too: it asks the extended keys, in order, and no core key.
    @Test func theExtendedPromptAsksForTheExtendedFieldsOfTheSchema() throws {
        let prompt = try DatasetFiles.text("Dataset/prompt_template_extended.txt")
        let schema = try DatasetFiles.schema()
        #expect(PromptTemplate(text: prompt.trimmingCharacters(in: .whitespacesAndNewlines)) != nil)
        let bulletKeys = prompt.split(separator: "\n")
            .filter { $0.hasPrefix("- ") }
            .compactMap { $0.dropFirst(2).split(separator: ":").first.map(String.init) }
        #expect(bulletKeys == schema.extendedKeys)
        for key in schema.coreKeys {
            #expect(!prompt.contains("\"\(key)\""), "the core field \(key) must not be in the extended prompt")
        }
        #expect(!prompt.localizedStandardContains("growth"), "the extended prompt has no growth rule")
    }
}

struct DatasetLoaderTests {

    @Test func loadsTheRealTestSplit() throws {
        let examples = try DatasetFiles.testSplit()
        #expect(examples.count == 30)
        #expect(examples.map(\.id) == Array(1...30))
        #expect(examples.allSatisfy { $0.scenario != "unknown" && $0.pool != "unknown" })
        #expect(examples.filter { $0.pool == "B" }.count == 12)
        #expect(examples.filter { $0.scenario == "hand" }.count == 5)
        #expect(examples.contains { $0.scenario == "none" })
    }

    @Test func loadsTheExtendedTestSplitWithTheExtendedLabels() throws {
        let schema = try DatasetFiles.schema()
        let examples = try DatasetFiles.testSplit(tier: .extended)
        #expect(examples.count == 30)
        let core = Set(schema.coreKeys)
        for example in examples {
            #expect(core.isDisjoint(with: example.expected.values.keys))
            #expect(Set(example.expected.values.keys).isSubset(of: Set(schema.extendedKeys)))
        }
        #expect(examples.contains { !$0.expected.values.isEmpty })
        // The balance sheet statement written by hand (H23, in the validation split): debt, equity, cash,
        // current assets and liabilities.
        let validation = try DatasetFiles.split("valid", tier: .extended)
        let sample = try #require(validation.first { $0.source == "H23" })
        #expect(sample.expected.value(forKey: "totalDebt") == 12.5)
        #expect(sample.expected.value(forKey: "currentLiabilities") == 6.1)
    }

    @Test func loadsAllThreeSplitsWithTheirSizes() throws {
        #expect(try DatasetFiles.split("train").count == 240)
        #expect(try DatasetFiles.split("valid").count == 30)
        #expect(try DatasetFiles.split("test").count == 30)
    }

    @Test func theFirstDeviceStatementIsInTheTestSplit() throws {
        let examples = try DatasetFiles.testSplit()
        let sample = try #require(examples.first {
            $0.statement.hasPrefix("During fiscal year 2025, the company reported revenue of $94 billion")
        })
        #expect(sample.expected.value(forKey: "revenue") == 94)
        #expect(sample.expected.text(forKey: "revenue") == "$94 billion")
        #expect(sample.expected.value(forKey: "netIncomeGrowth") == -4)
        #expect(sample.expected.text(forKey: "netIncomeGrowth") == "-4%")
        #expect(sample.expected.value(forKey: "previousYearNetIncome") == 21.9)
        #expect(sample.expected.value(forKey: "eps") == nil)
        #expect(sample.source == "H1")
    }

    @Test func theExpectedValuesAreTheCoreFieldsOnly() throws {
        let schema = try DatasetFiles.schema()
        let extended = Set(schema.extendedKeys)
        for example in try DatasetFiles.testSplit() {
            #expect(extended.isDisjoint(with: example.expected.values.keys))
            #expect(Set(example.expected.values.keys) == Set(example.expected.texts.keys))
        }
    }

    @Test func aMalformedLineIsReported() throws {
        let template = try DatasetFiles.promptTemplate()
        let schema = try DatasetFiles.schema()
        #expect(throws: DatasetError.malformedLine(1, "not a chat record")) {
            try DatasetLoader.parse(
                jsonl: "not json", labelsJSONL: "{}", indexCSV: "", template: template, schema: schema, split: "test")
        }
    }

    @Test func aMissingLabelLineIsReported() throws {
        let template = try DatasetFiles.promptTemplate()
        let schema = try DatasetFiles.schema()
        let chat = try DatasetFiles.text("Dataset/test.jsonl")
        #expect(throws: DatasetError.labelCountMismatch(statements: 30, labels: 0)) {
            try DatasetLoader.parse(
                jsonl: chat, labelsJSONL: "", indexCSV: "", template: template, schema: schema, split: "test")
        }
    }

    @Test func aLabelLineWithAnotherNumberIsReported() throws {
        let template = try DatasetFiles.promptTemplate()
        let schema = try DatasetFiles.schema()
        let chat = try #require(try DatasetFiles.text("Dataset/test.jsonl").split(separator: "\n").first)
        let labels = try #require(try DatasetFiles.text("Dataset/test.labels.jsonl").split(separator: "\n").first)
            .replacingOccurrences(of: "\"line\": 1", with: "\"line\": 7")
        #expect(throws: DatasetError.malformedLine(1, "the label line is not valid or has another number")) {
            try DatasetLoader.parse(
                jsonl: String(chat), labelsJSONL: labels, indexCSV: "", template: template, schema: schema, split: "test")
        }
    }
}
