//
//  EvaluationSetTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 17/10/2026.
//
import Foundation
import Testing

struct EvaluationSetTests {

    @Test func theLaunchNamesChooseTheSets() {
        #expect(EvaluationSet(name: "test") == .test)
        #expect(EvaluationSet(name: "") == .test)
        #expect(EvaluationSet(name: "test2") == .test2)
        #expect(EvaluationSet(name: "test3") == .test3)
        #expect(EvaluationSet(name: "real") == .external("real"))
    }

    @Test func aSetKeepsItsNameForTheReportAndTheIndex() {
        #expect(EvaluationSet.test.name == "test")
        #expect(EvaluationSet.test2.name == "test2")
        #expect(EvaluationSet.external("real").name == "real")
        #expect(EvaluationSet.test2.split == "test2")
        #expect(EvaluationSet.test3.name == "test3")
        #expect(EvaluationSet.test3.split == "test3")
    }

    @Test func theBundledSetsHaveTheirFilesAndAnExternalSetHasNone() {
        #expect(EvaluationSet.test.bundledFiles == .init(chat: "test", labels: "test.labels", index: "index"))
        #expect(EvaluationSet.test2.bundledFiles == .init(chat: "test2", labels: "test2.labels", index: "index.v2"))
        #expect(EvaluationSet.test3.bundledFiles == .init(chat: "test3", labels: "test3.labels", index: "index.v3"))
        #expect(EvaluationSet.external("real").bundledFiles == nil)
    }

    @Test func anExternalSetLivesUnderDocumentsEvalSets() throws {
        let documents = URL(filePath: "/tmp/docs")
        let directory = try #require(EvaluationSet.external("real").externalDirectory(in: documents))
        #expect(directory.path == "/tmp/docs/EvalSets/real")
        #expect(EvaluationSet.test.externalDirectory(in: documents) == nil)
        #expect(EvaluationSet.externalFiles(named: "real")
            == .init(chat: "real.jsonl", labels: "real.labels.jsonl", index: "index.csv"))
    }

    @Test func onlyTheFrozenTestHasABalanceSheetCall() {
        #expect(EvaluationSet.test.supports(.extended))
        #expect(!EvaluationSet.test2.supports(.extended))
        #expect(!EvaluationSet.test3.supports(.extended))
        #expect(!EvaluationSet.external("real").supports(.extended))
        #expect(EvaluationSet.test2.supports(.core))
        #expect(EvaluationSet.external("real").supports(.core))
    }

    /// An external set is read from a folder with the same three files as the dataset, with its own split name.
    @Test func anExternalSetIsReadFromItsFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "evalset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let lines = { (path: String) throws -> [Substring] in
            try DatasetFiles.text(path).split(separator: "\n").prefix(3).map { $0 }
        }
        let files = EvaluationSet.externalFiles(named: "mini")
        try lines("Dataset/v2/test2.jsonl").joined(separator: "\n").appending("\n")
            .write(to: folder.appending(path: files.chat), atomically: true, encoding: .utf8)
        try lines("Dataset/v2/test2.labels.jsonl").joined(separator: "\n").appending("\n")
            .write(to: folder.appending(path: files.labels), atomically: true, encoding: .utf8)
        try "split,line,source,scenario,pool,unit,distractors\nmini,1,real,filing,real,-,-\nmini,2,real,filing,real,-,-\nmini,3,real,none,real,-,-\n"
            .write(to: folder.appending(path: files.index), atomically: true, encoding: .utf8)

        let data = try DatasetLoader.externalSetData(named: "mini", in: folder)
        let examples = try DatasetLoader.parse(
            data, template: DatasetFiles.promptTemplate(), schema: DatasetFiles.schema(), split: "mini")
        #expect(examples.count == 3)
        #expect(examples.map(\.scenario) == ["filing", "filing", "none"])
        #expect(examples.allSatisfy { $0.source == "real" && $0.pool == "real" })
        #expect(data.hashed == data.chat + data.labels)
    }

    @Test func aMissingExternalSetIsAnErrorThatNamesThePath() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString)")
        #expect(throws: DatasetError.self) {
            try DatasetLoader.externalSetData(named: "real", in: folder)
        }
    }

    @Test func theReportRecordsTheSetOnlyWhenItIsKnown() throws {
        // A report written before Phase 2b has no set: it decodes (and counts as the frozen test split).
        let json = """
        {"date":"d","model":"m","device":"x","system":"s","temperature":0.2,"maxTokens":384,"runs":3,"seeds":[1,2,3],
         "examples":30,"promptHash":"p","testSetHash":"t","schemaHash":"h","tier":"core","keys":["revenue"]}
        """
        let old = try JSONDecoder().decode(EvaluationReport.Metadata.self, from: Data(json.utf8))
        #expect(old.evaluationSet == nil)
        let with = try JSONDecoder().decode(
            EvaluationReport.Metadata.self,
            from: Data(json.replacingOccurrences(of: "\"keys\"", with: "\"evaluationSet\":\"test2\",\"keys\"").utf8))
        #expect(with.evaluationSet == "test2")
    }
}
