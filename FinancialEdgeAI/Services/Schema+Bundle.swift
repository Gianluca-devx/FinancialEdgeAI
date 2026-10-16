//
//  Schema+Bundle.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import Foundation

/// The part of the schema that needs the app bundle. It stays out of `Schema.swift` so that file can
/// be compiled and tested without the app.
nonisolated extension Schema {

    /// The schema bundled with the app: a copy of `Dataset/schema.json`, checked for drift by
    /// `Scripts/validate_dataset.py`.
    static let bundled: Schema = {
        guard let url = Bundle.main.url(forResource: "schema", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            preconditionFailure("The bundled file schema.json is missing")
        }
        do {
            return try Schema(data: data)
        } catch {
            preconditionFailure("The bundled schema.json is not valid: \(error.localizedDescription)")
        }
    }()
}
