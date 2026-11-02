# Phase 2g, step 3: the reader frozen, then the held-out labels (counts only)

Spec: `Specs/phase-2g-table-reader.md` (T7, T8). The held-out reports, their text and their labels are private
(`RealSet/pdf-heldout/`, git-ignored); this file holds counts and hashes only, and names no company.

## The freeze (written and committed before any statement page of the held-out reports is read)

The reader is frozen on 2026-11-02 at **commit 6919bd6**, the last commit that changes its sources. Until the held-out run (step 4)
is done, these files do not change:

| File | sha256 (first 12) |
|---|---|
| `FinancialEdgeAI/Services/StatementTable.swift` | `ff8f7bcca103` |
| `FinancialEdgeAI/Services/StatementTableReader.swift` | `6bf45df5c275` |
| `FinancialEdgeAI/Services/PDFStatementLines.swift` | `47d27570587b` |
| `Scripts/table_reader/main.swift` (the driver, ef16fad) | `e7833568b7f4` |
| `Scripts/table_reader.sh` | `6267c08690c3` |

At this commit no held-out report has been extracted: `RealSet/pdf-heldout/` does not exist yet. The held-out set is then built by
`Scripts/pdf_pilot.py heldout` (every report the pilot did not draw), its text extracted and its pages ranked by the pilot's
retrievers; the statement pages are located by their titles and labelled by hand by the rules of T8, before the reader runs on them.

## The labels

To be filled after labelling: the number of reports and amounts, stated and null, the units, the label hash, and the report chosen
by seed for the user's spot-check.
