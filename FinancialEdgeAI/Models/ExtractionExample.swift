//
//  ExtractionExample.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// One labelled statement of the dataset.
struct ExtractionExample: Sendable, Identifiable, Equatable {
    /// Line number in the split file, starting at 1.
    let id: Int
    let statement: String
    let expected: FinancialMetrics
    /// "generated" or the id of a hand-written statement.
    let source: String
    let scenario: String
    /// Phrasing pool: "B" statements use wording that is not in train or valid.
    let pool: String
}
