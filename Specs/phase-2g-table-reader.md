# Spec: Phase 2g, a statement table reader in code (DRAFT)

Status: **DRAFT, not approved** (written 2026-11-02 at the user's request). The decisions are mine, each with the alternative.
Depends on `v2.6.0`: the PDF pilot (`Specs/phase-2f-pdf-pilot.md`, `Results/phase-2f-analysis.md`), whose decision rule gave
"redesign: code for the tables, the model for the prose", borderline.

**Goal:** find out whether **deterministic code can read the 10 statement amounts** (the 7 current-year amounts and the 3
previous-year ones) from the income statement and the cash flow statement of an annual-report PDF, **on reports it was not written
for**, well enough to build PDF import into the app on it. The phase gives a build, improve or stop decision, measured on fresh
reports.

**Out of scope:** the UI for importing a PDF and any change to what the app does today (the reader is a new pure type that nothing
calls yet); the prompt, the schema, the parser, the adapter and the evaluation code; the growth fields (the statements print no
percent, and code already derives growth from the two amounts); the balance sheet fields (the extended call), a natural next
table for the same reader; the overview and business sections; training.

## What the pilot showed

- **Finding the pages works:** keywords (BM25, two fixed queries) put a true statement page in the top 3 in 10 of 10 cases, first in 8.
- **The pilot's row matcher** (written in an hour, before the draw) was correct on 31 of 45 stated amounts with PDFKit text (68.9%)
  and 35 with `pdftotext` (77.8%). Its errors, all mechanical: row names not in its list (10 missed with PDFKit), rows whose label
  and numbers PDFKit puts on different lines (4 of those 10), net sales taken before a larger total (2 wrong), and a cash flow page
  that prints no unit (2).
- **The model** (`lora-v3`) was correct on 53% (PDFKit) and 62%: it takes the oldest of three year columns for previous-year values
  and a neighbouring row for current-year ones. Code can rule out both by construction.
- On five reports, everything above is development evidence. Nothing has been measured on reports the code was not written for.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| T1 | **The reader is written in Swift, as the app will run it:** a pure, `nonisolated` core in `FinancialEdgeAI/Services/` (rows in, amounts out) plus a thin PDFKit layer (a page in, rows out). On the Mac a driver compiled from the same source files runs it on the reports and writes a prediction file; the pilot's committed Python scorer scores it unchanged. | A Python prototype, then a port: two implementations drift, and what is measured would not be what ships. |
| T2 | **Rows from PDFKit's line geometry:** the lines of a page with their bounds (`PDFPage.selection(for:)`, `selectionsByLine()`), grouped into rows by vertical overlap, cells ordered by x; a label that wraps onto a second line is joined to the row that carries the numbers. | `PDFPage.string`: the pilot lost the rows of one report this way (label and numbers on different lines). |
| T3 | **Columns by their year, not their position.** The reader reads the year header of the table and takes the latest year as current and the year before it as previous; an older column is never used. If it cannot read the years, it abstains for the page. | First column = current: right in most reports, wrong when a report orders the years oldest first; the column was the model's main error. |
| T4 | **Rows by a synonym table per field, with the schema's choices as rules:** diluted over basic; attributable to the company over net income including noncontrolling interests; the total of revenues over a partial line (net sales, when a larger total of net sales and revenues is printed); operating income only from a row that names it (never a costs total or income before taxes); interest expense only from its own row. The table is written on the 5 pilot reports only. | Learning the rows from data: five reports are too few. |
| T5 | **Units:** read from the page header ("in millions, except per share amounts"), ignoring a unit that only qualifies shares; if the page prints none, the unit read on the report's other statement page; otherwise abstain. **The output is the number as printed with the unit word** ("416,161 million", "4,475,446 thousand"), which the app's `ValueParser` already reads; per-share values as printed. | A computed value: breaks the app's rule that the reader copies and code converts. |
| T6 | **Abstain rather than guess:** when two rows match a field equally, or the year or the unit is unclear, the field stays null. | Best guess: a missed amount can be shown as "not found"; a wrong one cannot be flagged. |
| T7 | **Measured on fresh reports.** Development uses the 5 pilot reports only. The reader is **frozen (its commit recorded) before any statement page of the held-out reports is read.** The held-out set is **all 12 reports the pilot did not draw** (no draw, so no choice). | 6 now and 6 kept for a second round, drawn by seed: a fresh set for later, but a test hardly larger than the pilot. The user can choose this at approval. |
| T8 | **Labels by the pilot's rules, written down now:** the two statement pages of each report; the 10 amounts as printed with the header's unit; the previous-year amounts follow the same choices as the current-year ones (diluted, attributable, the total of revenues); null where a statement does not print the amount. Frozen by hash before any run; the user spot-checks one report, chosen by seed. The pilot's sensitivity reading (the literal schema wording for previous-year values, and net sales) is reported again. | Labels after seeing the reader's output: the labels would follow the reader. |
| T9 | **Conditions, as in the pilot:** (A) the reader on the true statement pages; (C) the whole path: keywords' top 3 pages per statement (the pilot's queries), the reader taking the first page where it recognises the statement (its title, a year header and at least 3 rows it knows). For comparison on the same held-out pages: the model (`lora-v3` seed 1, Mac, seeds 1 to 3) on the true pages, and the reader with the model filling only the fields the reader leaves null. PDFKit only. | `pdftotext` as well: the app cannot ship it, and the pilot already measured the difference. |
| T10 | **Scoring by the pilot's scorer (P6), unchanged:** correct within half a unit of the last printed digit; the categories correct, unit, column, invented, missed, unparsed, wrong. **"Confidently wrong"** = wrong + column + unit + invented: an amount shown to the user that is not the printed one. | A new scorer: the results would not compare with the pilot. |
| T11 | **No phone in this phase.** The reader is deterministic and runs in milliseconds; the model's phone time was measured by the pilot. Whether PDFKit gives the same lines on iOS as on macOS is checked in the integration spec that would follow a "build". | A phone check now: it needs an entry point in the app, which is out of scope. |

## Decision rule (fixed before the held-out run)

Over the 12 held-out reports, condition C, PDFKit:

1. **Build** (a next spec puts PDF import with this reader into the app): correct on **at least 85%** of the stated amounts, and
   **confidently wrong on at most 3%** of the labelled amounts (at most 3 of about 120).
2. **Improve:** correct on 70% to 85%, or at least 85% with more confidently wrong amounts than rule 1 allows. The reader is close;
   its errors are listed by kind. A second round needs fresh reports (all 17 are used), which the user would supply.
3. **Stop this path:** correct on **less than 70%**. Rules written on five reports do not carry to others; the other path the pilot
   named, an adapter trained on three-year statement tables, becomes the next candidate.
4. **Reported in every case:** A and C on the development reports and on the held-out ones (the gap between them measures how much
   the reader was fitted to its five reports); the model on the held-out true pages (does the pilot's 53% hold?); the reader with
   the model filling its nulls, **recommended only if, over the 3 seeds, it adds more correct amounts than confidently wrong ones**;
   the errors by kind; the sensitivity reading; the reader's time per report on the Mac.

These thresholds are a judgement, disclosed as such: about 110 stated amounts make one amount about 0.9%. A wrong amount weighs
more than a missed one because the app can say "not found" but cannot know a number is wrong.

## Steps (branch `feature/table-reader`, each one commit)

1. **GATE: the user approves this spec.**
2. **The reader and its tests** (`feat`, `test`): the pure core and the PDFKit layer (new Swift files created through the Xcode MCP,
   symlinked into the test target); Swift Testing on made-up tables, each rule of T3 to T6 with a tamper test (the years in reverse
   order, a unit that qualifies shares only, basic printed before diluted, a costs total named "Total", a label wrapped over two
   lines, a page with no unit); the Mac driver. Then development on the 5 pilot reports, A and C (`eval`, counts only). All tuning
   happens here and only here.
3. **Freeze and label** (`data`): record the reader's commit; then locate the two statement pages of each of the 12 held-out reports
   by their titles, label them by T8, freeze the labels by hash; the user spot-checks one report.
4. **The held-out run** (`eval`, counts only): the reader on A and C; the model on the true pages on the Mac (3 seeds, about 15
   minutes); the fallback combination.
5. **Analysis** against the decision rule, README, PR to `main` after the user's go (`docs`).

## Cost

About 5 to 7 days of my work: the reader and its tests 2 to 3 days, labelling about 120 amounts 1 to 2 days, runs and analysis a
day. Mac compute under an hour. No phone, no training.

## Acceptance

1. The reader's commit is recorded before any held-out statement page is read; the labels are frozen before any run; the decision
   rule above is unchanged.
2. A and C have their counts by category on the development and the held-out reports; the model and the fallback on the held-out.
3. Each rule of T3 to T6 has a test and a tamper test; the full Swift test suite passes.
4. No report text, page or answer is committed, and no company name of the reports; counts only.
5. A written conclusion says which rule applies and why.

## Risks

- **Layouts vary more than five reports show:** labels on two lines, subtotals with the same name as a field, segment columns beside
  the years, a statement over two pages. Abstaining keeps these from becoming wrong values; they are counted as missed and listed.
- **The developer is the labeller.** The freeze order (reader, then labels, then run) and the spot-check limit it; it is disclosed.
- **Twelve reports from one filing year and a narrow range of industries.** A build decision would hold for reports like them.
- **PDFKit on iOS may differ from macOS** in how it splits lines; checked in the integration spec.
- **App sources compiled outside Xcode** for the Mac driver: the pure types are `nonisolated`, and the driver checks a made-up table
  against the result of the Swift tests before any report is run.
- A scanned page with no text gives the reader nothing: counted as missed, and reported.
