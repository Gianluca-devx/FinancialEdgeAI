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

    /// The test split bundled with the app.
    static func loadTestSplit() throws -> [ExtractionExample] {
        try parse(
            jsonl: bundledText("test", "jsonl"),
            indexCSV: bundledText("index", "csv"),
            template: ExtractionPrompt.template,
            split: "test"
        )
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
