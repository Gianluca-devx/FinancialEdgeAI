//
//  FinancialMetrics.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 01/10/2026.
//
import Foundation

struct FinancialMetrics: Decodable {
    let revenue: Double?
    let revenueGrowth: Double?
    let operatingIncome: Double?
    let operatingIncomeGrowth: Double?
    let netIncome: Double?
    let netIncomeGrowth: Double?
    let previousYearNetIncome: Double?
}
