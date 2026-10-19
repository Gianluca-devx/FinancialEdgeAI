//
//  EvaluationSet.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 17/10/2026.
//
import Foundation

/// Which statements an evaluation runs on. The launch argument `-evaluationSet <name>` chooses it.
///
/// - `test`: the frozen test split of every earlier experiment (bundled).
/// - `test2`: the second test set of Phase 2b, wording that is in no training statement (bundled).
/// - `test3`: the third test set of Phase 2d, synthetic statements in the style of real reports, with wording and
///   templates that are in no training statement (bundled).
/// - `external(name)`: a set that is not in the repository, copied to the app's
///   `Documents/EvalSets/<name>/` (for example text from real reports, which is never committed).
///
/// A set is three files in the same format as the dataset: the chat file with the core prompt around each
/// statement, its sidecar of labels, and an index. The expected values come from the sidecar.
nonisolated enum EvaluationSet: Equatable, Sendable {
    case test
    case test2
    case test3
    case external(String)

    /// "test" and "test2" are the bundled sets; any other name is an external set.
    init(name: String) {
        switch name {
        case "test", "": self = .test
        case "test2": self = .test2
        case "test3": self = .test3
        default: self = .external(name)
        }
    }

    /// The name written in a report and shown on the screen.
    var name: String {
        switch self {
        case .test: "test"
        case .test2: "test2"
        case .test3: "test3"
        case .external(let name): name
        }
    }

    /// The value of the `split` column of the index that belongs to this set's lines.
    var split: String { name }

    /// File names, without the extension for the bundled sets, with it for an external set.
    struct Files: Equatable, Sendable {
        let chat: String
        let labels: String
        let index: String
    }

    var bundledFiles: Files? {
        switch self {
        case .test: Files(chat: "test", labels: "test.labels", index: "index")
        case .test2: Files(chat: "test2", labels: "test2.labels", index: "index.v2")
        case .test3: Files(chat: "test3", labels: "test3.labels", index: "index.v3")
        case .external: nil
        }
    }

    /// Where an external set lives under the app's Documents folder: `EvalSets/<name>/`.
    func externalDirectory(in documents: URL) -> URL? {
        guard case .external(let name) = self else { return nil }
        return documents.appending(path: "EvalSets").appending(path: name)
    }

    /// The three file names inside an external set's folder.
    static func externalFiles(named name: String) -> Files {
        Files(chat: "\(name).jsonl", labels: "\(name).labels.jsonl", index: "index.csv")
    }

    /// Only the frozen test has an extended (balance sheet) chat file.
    func supports(_ tier: FieldTier) -> Bool {
        tier == .core || self == .test
    }
}
