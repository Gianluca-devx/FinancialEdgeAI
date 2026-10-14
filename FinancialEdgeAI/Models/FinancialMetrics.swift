//
//  FinancialMetrics.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import Foundation

struct FinancialMetrics: Codable, Equatable, Sendable {
    let revenue: Double?
    let revenueGrowth: Double?
    let operatingIncome: Double?
    let operatingIncomeGrowth: Double?
    let netIncome: Double?
    let netIncomeGrowth: Double?
    let previousYearNetIncome: Double?

    /// The seven keys the model must return, in the order of the prompt.
    static let keys = [
        "revenue", "revenueGrowth", "operatingIncome", "operatingIncomeGrowth",
        "netIncome", "netIncomeGrowth", "previousYearNetIncome",
    ]
}
