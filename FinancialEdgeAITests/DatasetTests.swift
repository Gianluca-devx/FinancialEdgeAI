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
}

struct DatasetLoaderTests {

    @Test func loadsTheRealTestSplit() throws {
        let examples = try DatasetFiles.testSplit()
        #expect(examples.count == 30)
        #expect(examples.map(\.id) == Array(1...30))
        #expect(examples.allSatisfy { $0.scenario != "unknown" && $0.pool != "unknown" })
        #expect(examples.filter { $0.pool == "B" }.count == 13)
        #expect(examples.filter { $0.scenario == "hand" }.count == 3)
    }

    @Test func theFirstDeviceStatementIsInTheTestSplit() throws {
        let examples = try DatasetFiles.testSplit()
        let sample = try #require(examples.first {
            $0.statement.hasPrefix("During fiscal year 2025, the company reported revenue of $94 billion")
        })
        #expect(sample.expected.revenue == 94)
        #expect(sample.expected.netIncomeGrowth == -4)
        #expect(sample.expected.previousYearNetIncome == 21.9)
        #expect(sample.source == "H1")
    }

    @Test func aMalformedLineIsReported() throws {
        let template = try DatasetFiles.promptTemplate()
        #expect(throws: DatasetError.malformedLine(1, "not a chat record")) {
            try DatasetLoader.parse(jsonl: "not json", indexCSV: "", template: template, split: "test")
        }
    }
}
