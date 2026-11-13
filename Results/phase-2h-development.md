# Phase 2h, step 2: the second-round reader on the 17 development reports (counts only)

Spec: `Specs/phase-2h-table-reader-round2.md` (approved 2026-11-06). The development set is every report labelled so far: the 5 of
the PDF pilot (labels `c087c0da286b`) and the 12 of Phase 2g (labels `acf0568af1f5`), 157 stated amounts and 13 null, all frozen and
unchanged. Run on 2026-11-07 on the Mac with `Scripts/table_reader.sh`, PDFKit, scored by the pilot's scorer unchanged. No report
text, page or answer is committed; no company is named.

## The changes (R2 to R5, each with a test and a tamper test)

- Loss rows: "operating loss", "loss from operations", "net loss", "net loss attributable to ..."; a number in parentheses is
  negative, a loss row or loss-per-share row without parentheses is null (`unsignedLoss`).
- A combined "basic and diluted" EPS row under a per-share heading is read as diluted.
- "Consolidated" is ignored at the start of a row label.
- Operating cash flow: "net cash from operations" and four other forms. Capex: "payments for property and equipment"; the broader
  lines ("investment in property, plant, equipment ...", "purchases related to property and equipment ...") only when no strict
  line is printed.
- The cash flow title in either word order ("cash flows statements").
- A note reference ("(Note 12)", "Note 3") is part of the label, never a cell, and is left out when labels are compared.
- Capex only inside the investing section (from its header to its "net cash ... investing" total); without such a section, the
  Phase 2g rule.
- Currency guard: a unit in another currency in the header (a symbol other than $, "of euros", "of Canadian dollars", "EUR
  millions") makes every field of the page null (`currency`); a foreign symbol right before a row's numbers counts too, a foreign
  note line below the header does not.

Tests: 25 new Swift tests (66 for the reader in all), full suite 392/392; the app builds with no warning in the reader's files.
`pdf_pilot.py gate` (R6) with a test that makes it fail on a lost and on a wrong amount; 21 Python tests.

## The development run and the gate (R6)

| Development reports | Phase 2g reader | Phase 2h reader | Gate: gained / lost / confidently wrong |
|---|---|---|---|
| The pilot's 5, A | 38/45 | 38/45 | 0 / 0 / 0 |
| The pilot's 5, C | 38/45 | 38/45 | 0 / 0 / 0 |
| Phase 2g's 12, A | 96/112 | 112/112 | 16 / 0 / 0 |
| Phase 2g's 12, C | 91/112 | 112/112 | 21 / 0 / 0 |
| **All 17, C** | **129/157 (82.2%)** | **150/157 (95.5%)** | **21 / 0 / 0** |

- **The gate passes:** no amount the Phase 2g reader read is lost, and no confidently wrong amount appears; the 13 null labels are
  all left null.
- **The 112/112 is not a result.** The changes were written from exactly the misses of these 12 reports, so the number only shows
  that the named cases are covered. How the reader does on reports it has not seen is what the held-out run of step 4 measures.
- The 7 remaining misses are the one report that prints no dollar unit on either statement page, null by rule as before.
- Time: 0.10 s for the 5 reports, 0.17 to 0.19 s for the 12, on the Mac.

The reader is frozen after this commit (step 3): its commit and file hashes are recorded before any new report is opened.
