// The text of every page of a PDF with PDFKit, the API the app would use on iOS (`PDFPage.string`).
// Phase 2f, Specs/phase-2f-pdf-pilot.md, P8. Nothing it writes from a real report is committed (RealSet/ is git-ignored).
//
//   swift Scripts/pdf_pages.swift <in.pdf> <out.json>
//
// Writes a JSON array of strings, one per page in page order (an empty string for a page without text).
import Foundation
import PDFKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift Scripts/pdf_pages.swift <in.pdf> <out.json>\n".utf8))
    exit(2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    FileHandle.standardError.write(Data("cannot open \(arguments[1])\n".utf8))
    exit(1)
}
let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
let data = try JSONEncoder().encode(pages)
try data.write(to: URL(fileURLWithPath: arguments[2]))
print("pages \(pages.count)")
