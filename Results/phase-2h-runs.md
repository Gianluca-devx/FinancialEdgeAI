# Phase 2h, step 4: the held-out run (counts only)

Spec: `Specs/phase-2h-table-reader-round2.md` (R9, R10, decision rule). Run on 2026-11-12 on the Mac, no phone, no model. Nothing
from a report is committed and no company is named; the predictions stay in the git-ignored `RealSet/`.

- **The reader** is the frozen one: before the run, its three sources and the driver were checked against the hashes of the freeze
  record (`Results/phase-2h-heldout.md`, reader commit 7cca894): all five match.
- **The set and labels:** the 10 new reports (set hash `7015932f15a8`), labels `b5536028cc0c`, 93 stated amounts and 7 null. The
  user spot-checked the report chosen by seed: 10 of 10 confirmed; no label changed.
- **The sensitivity values** (`1f576169107a`, 15 values) were written with the labels, before the run.
- **The keyword ranking** (the pilot's retrievers, unchanged): keywords find a true statement page in the top 3 for **20 of 20**
  statements, embeddings 0 of 20, hybrid 1 of 20 (embedding time 165 s per extraction); keywords are used for C, as before.

## Result

Stated amounts correct out of 93; "confidently wrong" is wrong + column + unit + invented (an amount shown that is not the printed
one). The 7 null labels count as kept when the answer is null.

| On the 10 new reports | Stated amounts correct | Confidently wrong | Missed | Nulls kept | Literal reading also accepted |
|---|---|---|---|---|---|
| **Reader, C (the whole path; the decision rule's condition)** | **51/93 (54.8%)** | **0** | 42 | 7/7 | 51/93 |
| Reader, A (true statement pages) | 62/93 (66.7%) | 0 | 31 | 7/7 | 62/93 |

- **The reader never shows a wrong amount**, on either condition: every amount it does not read is null with its reason.
- **Development against held-out:** all 17 development reports 150/157 on C (95.5%); the 10 new reports 51/93 on C (54.8%) and
  62/93 on A (66.7%). In Phase 2g the gap was small (84.4% against 81.2% on C); here it is about 41 points.
- **The currency check (R10):** no report in another currency was supplied; nothing to run.
- Time: 0.17 s (A) and 0.18 s (C) for the 10 reports on the Mac, without the keyword search.

## The reader's nulls by kind

From a diagnostic run of the same frozen sources (a separate driver in the scratchpad that prints each field's reason; the frozen
driver prints only totals, and no reader file was changed). On A, the 31 missed amounts:

| Kind | Missed on A | Reports |
|---|---|---|
| The year-end date printed on the header line before the years ("Amounts in millions ...; fiscal years ended June 30 2026 2025 2024"): the day, 30, is read as a cell beside the years, so the row is not a year header and neither statement has years (`noYears`) | 10 | 1 |
| The unit printed without "in" ("(MILLIONS, EXCEPT PER SHARE DATA)", "(MILLIONS)") (`noUnit`) | 3 | 1 |
| Revenue rows not in the synonym table ("Net Operating Revenues", "Sales to customers") | 4 | 2 |
| Operating cash flow rows not in the table, with a "used in / provided by" pair ("Net cash (used in)/provided by ...", "Net cash provided by/(used in) ...", "Cash provided (used) by operations") | 3 | 3 |
| Interest expense with a qualifier ("Interest expense, net of portion capitalized", "Interest expense-net of capitalized interest of $..") | 2 | 2 |
| A capex row not in the table ("Purchases of property, equipment and technology") | 1 | 1 |
| EPS: a footnote marker after the label ("... Per Share1") read as an extra cell (`cellCount`) | 2 | 1 |
| EPS: the per-share rows named after net income under a "diluted" heading | 2 | 1 |
| EPS: one row per share class (class A, B-1, ...) under the diluted heading | 2 | 1 |
| Net income: the attributable line printed twice, as a statement row and as a per-share row with another value (`ambiguous`) | 2 | 1 |

C misses 11 more, because 6 of the 20 statement pages were among the keywords' top 3 but **not recognised** by the reader (it needs
a title, a year header and rows of at least 3 fields it knows; checked page by page with the same diagnostic driver):

- the two statements of the report whose header line holds the date's day: no year header (no new miss: A already missed all 10);
- one income statement whose title is alone on the previous PDF page: no title (6 more);
- two income statements and one cash flow statement with a title and years but rows of fewer than 3 fields the reader knows,
  because their revenue, cash flow or per-share rows are among the unknown forms above (4, 0 and 1 more).

The 7 null labels were all left null.
