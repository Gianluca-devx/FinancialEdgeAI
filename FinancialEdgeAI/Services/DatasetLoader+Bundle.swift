//
//  DatasetLoader+Bundle.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// The part of the loader that needs the app bundle. It stays out of `DatasetLoader.swift`
/// so that file can be compiled and tested without the app.
extension DatasetLoader {

    /// The test split bundled with the app, for the core call or the extended call.
    static func loadTestSplit(tier: FieldTier = .core) throws -> [ExtractionExample] {
        try loadSet(.test, tier: tier).examples
    }

    /// The files of a set: bundled (`test`, `test2`, `test3`) or copied to the app's Documents (`external`).
    static func setData(for set: EvaluationSet, tier: FieldTier = .core, documents: URL = .documentsDirectory) throws -> SetData {
        guard set.supports(tier) else { throw DatasetError.unsupportedTier(set: set.name, tier: tier.rawValue) }
        if let files = set.bundledFiles {
            let chat = set == .test ? testFileName(for: tier) : files.chat
            return SetData(chat: try bundledData(chat, "jsonl"), labels: try bundledData(files.labels, "jsonl"),
                           index: try bundledData(files.index, "csv"))
        }
        guard let directory = set.externalDirectory(in: documents) else { throw DatasetError.missingExternalSet(set.name) }
        return try externalSetData(named: set.name, in: directory)
    }

    /// A set's examples and the bytes they were read from.
    static func loadSet(_ set: EvaluationSet, tier: FieldTier = .core) throws -> (examples: [ExtractionExample], data: SetData) {
        let data = try setData(for: set, tier: tier)
        let examples = try parse(data, template: ExtractionPrompt.template(for: tier), schema: Schema.bundled,
                                 split: set.split, tier: tier)
        return (examples, data)
    }

    /// The bundled chat file of a tier (without the extension).
    static func testFileName(for tier: FieldTier) -> String {
        switch tier {
        case .core: "test"
        case .extended: "test.extended"
        }
    }

    /// The bytes of the bundled files that define an experiment, for the hashes in a report.
    static func bundledData(_ name: String, _ ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url)
        else { throw DatasetError.missingResource("\(name).\(ext)") }
        return data
    }

    private static func bundledText(_ name: String, _ ext: String) throws -> String {
        String(decoding: try bundledData(name, ext), as: UTF8.self)
    }
}
