// The embedding retriever of Phase 2f (Specs/phase-2f-pdf-pilot.md, P9): Apple's on-device `NLContextualEmbedding`
// (English), the same API as on iOS. Nothing it reads or writes from a real report is committed (RealSet/ is git-ignored).
//
//   swift Scripts/pdf_embed.swift <pages.json> <queries.json> <out.json>
//
// pages.json: a JSON array of page texts. queries.json: {"<name>": "<query text>"}.
// out.json: {"model": {...}, "scores": {"<name>": [cosine similarity of each page]}, "seconds": <indexing time>}.
//
// Fixed in the spec before any run: a text vector is the mean of its token vectors; the score is the cosine similarity
// between the query vector and the page vector. A page longer than the model's maximum input is split into windows of
// WINDOW_WORDS words and its score is the best window's (WINDOW_WORDS is set below the model's maximum sequence length,
// since one word is one or more tokens). An empty page scores 0.
import Foundation
import NaturalLanguage

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fail("usage: swift Scripts/pdf_embed.swift <pages.json> <queries.json> <out.json>") }
let pages = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let queries = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))

guard let embedding = NLContextualEmbedding(language: .english) else { fail("no English contextual embedding") }
if !embedding.hasAvailableAssets {
    let result = try await embedding.requestAssets()
    guard result == .available else { fail("the embedding assets are not available: \(result)") }
}
try embedding.load()

// Half the maximum sequence length in words keeps a window under the limit for ordinary English text.
let windowWords = max(16, embedding.maximumSequenceLength / 2)

func vector(of text: String) throws -> [Double]? {
    let result = try embedding.embeddingResult(for: text, language: .english)
    var sum = [Double](repeating: 0, count: embedding.dimension)
    var count = 0
    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
        for i in 0..<sum.count { sum[i] += tokenVector[i] }
        count += 1
        return true
    }
    guard count > 0 else { return nil }
    return sum.map { $0 / Double(count) }
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return na == 0 || nb == 0 ? 0 : dot / (na.squareRoot() * nb.squareRoot())
}

func windows(of text: String) -> [String] {
    let words = text.split(whereSeparator: { $0.isWhitespace })
    guard !words.isEmpty else { return [] }
    return stride(from: 0, to: words.count, by: windowWords).map {
        words[$0..<min($0 + windowWords, words.count)].joined(separator: " ")
    }
}

let start = Date()
var queryVectors: [String: [Double]] = [:]
for (name, text) in queries {
    guard let v = try vector(of: text) else { fail("empty query \(name)") }
    queryVectors[name] = v
}
let pageWindows = try pages.map { page in try windows(of: page).compactMap { try vector(of: $0) } }
var scores: [String: [Double]] = [:]
for (name, q) in queryVectors {
    scores[name] = pageWindows.map { ws in ws.map { cosine(q, $0) }.max() ?? 0 }
}
let seconds = Date().timeIntervalSince(start)

struct Output: Encodable {
    let model: [String: String]
    let scores: [String: [Double]]
    let seconds: Double
}
let model = ["identifier": embedding.modelIdentifier, "revision": String(embedding.revision),
             "dimension": String(embedding.dimension), "maximumSequenceLength": String(embedding.maximumSequenceLength),
             "windowWords": String(windowWords)]
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(Output(model: model, scores: scores, seconds: seconds)).write(to: URL(fileURLWithPath: arguments[3]))
print("pages \(pages.count), queries \(queries.count), \(String(format: "%.1f", seconds)) s")
