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

    /// The value of one of the seven keys.
    func value(forKey key: String) -> Double? {
        switch key {
        case "revenue": revenue
        case "revenueGrowth": revenueGrowth
        case "operatingIncome": operatingIncome
        case "operatingIncomeGrowth": operatingIncomeGrowth
        case "netIncome": netIncome
        case "netIncomeGrowth": netIncomeGrowth
        case "previousYearNetIncome": previousYearNetIncome
        default: nil
        }
    }
}
