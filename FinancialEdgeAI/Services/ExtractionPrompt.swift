//
//  ExtractionPrompt.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 14/10/2026.
//
import Foundation

/// The prompt used for every extraction.
///
/// The text lives in `Dataset/` (`prompt_template.txt`, `system_prompt.txt`) and is bundled
/// with the app, so the dataset, the fine-tuning data and the app always use the same words.
/// `Scripts/validate_dataset.py` fails if a bundled copy differs from the one in `Dataset/`.
enum ExtractionPrompt {
    static let placeholder = "<<STATEMENT>>"

    /// The statement from the first test on the iPhone.
    static let sampleStatement =
        "During fiscal year 2025, the company reported revenue of $94 billion, representing a 12% "
        + "increase compared with the previous year. Operating income was $25 billion, an increase "
        + "of 8%. Net income was $21 billion, down 4% from $21.9 billion in the previous year."

    static let system = load("system_prompt")
    private static let template = load("prompt_template")

    static func userPrompt(for statement: String) -> String {
        template.replacingOccurrences(of: placeholder, with: statement)
    }

    private static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("The bundled file \(name).txt is missing")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
