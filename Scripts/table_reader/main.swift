// Phase 2g (Specs/phase-2g-table-reader.md): the Mac driver of the statement table reader. It is compiled together with the
// app's own source files by Scripts/table_reader.sh, so it runs the code the app would ship.
//
//   Scripts/table_reader.sh --condition A|C [--out RealSet/pdf] [--reports ~/Downloads/Reports]
//
// A: the true statement pages of each labelled report (labels.json). C: the first page the reader recognises among the
// keywords' top 3 pages for each statement (retrieval.pdfkit.json, the PDF pilot's retriever). Writes
// <out>/pred.reader.<A|C>.pdfkit.json in the pilot's prediction format, scored unchanged by
// `python3 Scripts/pdf_pilot.py score --pred ...`. Nothing from a report is printed: counts only.
import Foundation
import PDFKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var options = ["--out": "RealSet/pdf", "--reports": NSHomeDirectory() + "/Downloads/Reports"]
var arguments = CommandLine.arguments.dropFirst()
while let key = arguments.popFirst() {
    guard let value = arguments.popFirst() else { fail("no value for \(key)") }
    options[key] = value
}
guard let condition = options["--condition"], ["A", "C"].contains(condition) else {
    fail("usage: Scripts/table_reader.sh --condition A|C [--out DIR] [--reports DIR]")
}
let out = URL(fileURLWithPath: options["--out"]!)
let reports = URL(fileURLWithPath: options["--reports"]!)

// The self-check: a made-up statement must read as the Swift tests expect before any report is read, so a build outside
// Xcode that behaves differently stops here.
let madeUp = ["CONSOLIDATED STATEMENTS OF OPERATIONS", "(In millions, except per-share amounts)", "2025 2024 2023",
              "Total net sales $ 1,234 $ 1,100 $ 950", "Net income $ 210 $ 190 $ 170", "Earnings per share:",
              "Diluted $ 2.15 $ 1.95 $ 1.77"]
let check = StatementTableReader.read(income: madeUp.map(StatementTable.row(from:)), cashFlow: nil).amounts.mapValues(\.text)
guard check == ["revenue": "1,234 million", "previousYearRevenue": "1,100 million", "netIncome": "210 million",
                "previousYearNetIncome": "190 million", "eps": "2.15", "previousYearEps": "1.95"] else {
    fail("self-check failed: \(check)")
}

func json(_ url: URL) -> Any {
    guard let data = try? Data(contentsOf: url), let value = try? JSONSerialization.jsonObject(with: data) else {
        fail("cannot read \(url.lastPathComponent)")
    }
    return value
}

guard let labels = json(out.appending(path: "labels.json")) as? [String: [String: Any]] else {
    fail("labels.json has an unexpected shape")
}
let retrieval = condition == "C" ? json(out.appending(path: "retrieval.pdfkit.json")) as? [String: [String: Any]] : nil
if condition == "C", retrieval == nil { fail("retrieval.pdfkit.json has an unexpected shape") }

let statements: [(kind: StatementKind, query: String)] = [(.income, "income"), (.cashFlow, "cashflow")]
var answers: [String: [String: Any]] = [:]
var nulls: [String: Int] = [:]
var pagesRead = 0
let start = Date()
for name in labels.keys.sorted() {
    guard let document = PDFDocument(url: reports.appending(path: name)), let label = labels[name] else {
        fail("cannot open a report")
    }
    var chosen: [StatementKind: (page: Int, rows: [TableRow])] = [:]
    for (kind, query) in statements {
        let candidates: [Int]
        if condition == "A" {
            guard let page = (label["pages"] as? [String: [Int]])?[query]?.first else { fail("a label has no \(query) page") }
            candidates = [page]
        } else {
            guard let ranking = (retrieval?[name]?["rankings"] as? [String: [String: [Int]]])?[query]?["keywords"] else {
                fail("a report has no keyword ranking")
            }
            candidates = Array(ranking.prefix(3))
        }
        for page in candidates {
            guard let rows = PDFStatementLines.rows(of: document, page: page) else { continue }
            if condition == "A" || StatementTableReader.recognises(kind, rows: rows) {
                chosen[kind] = (page, rows)
                pagesRead += 1
                break
            }
        }
    }
    let reading = StatementTableReader.read(income: chosen[.income]?.rows, cashFlow: chosen[.cashFlow]?.rows)
    var answer: [String: Any] = [:]
    for key in StatementTableReader.keys {
        let kind: StatementKind = ["operatingCashFlow", "capex"].contains(key) ? .cashFlow : .income
        if let amount = reading.amounts[key], let page = chosen[kind]?.page {
            answer[key] = ["text": amount.text, "page": page]
        } else {
            answer[key] = NSNull()
            nulls[reading.abstained[key]?.rawValue ?? "unknown", default: 0] += 1
        }
    }
    answers[name] = answer
}
let seconds = Date().timeIntervalSince(start)
let prediction: [String: Any] = ["condition": "reader-\(condition)", "extraction": "pdfkit",
                                 "runs": [["seed": 0, "answers": answers]], "nulls": nulls, "seconds": seconds]
let target = out.appending(path: "pred.reader.\(condition).pdfkit.json")
do {
    try JSONSerialization.data(withJSONObject: prediction, options: [.sortedKeys]).write(to: target)
} catch {
    fail("cannot write \(target.lastPathComponent)")
}
let reasons = nulls.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
print("reader \(condition): \(labels.count) reports, statement pages read \(pagesRead)/\(labels.count * 2), "
      + "nulls: \(reasons.isEmpty ? "none" : reasons); \(String(format: "%.2f", seconds)) s; wrote \(target.lastPathComponent)")
