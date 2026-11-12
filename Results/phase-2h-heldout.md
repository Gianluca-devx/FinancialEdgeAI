# Phase 2h, step 3: the reader frozen, then the new held-out reports (counts only)

Spec: `Specs/phase-2h-table-reader-round2.md` (R7, R8). The new reports, their text and their labels are private (git-ignored);
this file holds counts and hashes only, and names no company.

## The freeze (written and committed before any new report is opened)

The reader is frozen on 2026-11-12 at **commit 7cca894**, the last commit that changes its sources (the development run and the
gate, b51cde4 and bd248bd, change no reader file). Until the held-out run (step 4) is done, these files do not change:

| File | sha256 (first 12) | Last changed |
|---|---|---|
| `FinancialEdgeAI/Services/StatementTable.swift` | `93540c0a1006` | da4e522 |
| `FinancialEdgeAI/Services/StatementTableReader.swift` | `bca7ddea35e5` | 7cca894 |
| `FinancialEdgeAI/Services/PDFStatementLines.swift` | `47d27570587b` | 0ed5517 (as in Phase 2g) |
| `Scripts/table_reader/main.swift` (the driver) | `e7833568b7f4` | ef16fad (as in Phase 2g) |
| `Scripts/table_reader.sh` | `6267c08690c3` | ef16fad (as in Phase 2g) |

At this commit no new report has been opened, listed or extracted. The folder the user supplies, `~/Downloads/Reports2`, was only
tested for existence (an attempt to count its files was refused by the system, so not even the count was seen). After this commit:
the inclusion check of R7, extraction, the keyword ranking, the labels by R8 and the user's spot-check, before the reader runs on
any new report.
