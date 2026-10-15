//
//  GenerationResult.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// One answer from the model, with the numbers needed to judge what it cost.
struct GenerationResult: Codable, Sendable {
    let text: String
    let promptTokens: Int
    let generatedTokens: Int
    /// Seconds to process the prompt, that is until the first token.
    let promptTime: TimeInterval
    /// Seconds to generate the remaining tokens.
    let generateTime: TimeInterval
    /// Wall-clock seconds of the whole request.
    let totalTime: TimeInterval
    let tokensPerSecond: Double
    /// Bytes allocated by MLX when the request ended.
    let activeMemory: Int
    /// Highest number of bytes allocated by MLX since the app launched.
    let peakMemory: Int
}
