# Phase 2h, the statement table reader, second round: analysis against the decision rule

Spec: [`Specs/phase-2h-table-reader-round2.md`](../Specs/phase-2h-table-reader-round2.md) (approved 2026-11-06). Counts:
[`phase-2h-development.md`](phase-2h-development.md) (step 2, the 17 development reports and the gate),
[`phase-2h-heldout.md`](phase-2h-heldout.md) (step 3, the freeze, the inclusion check and the labels),
[`phase-2h-runs.md`](phase-2h-runs.md) (step 4, the held-out run). No report text, page or answer is committed, and no company
is named.

## Conclusion

**Rule 3 applies: "stop this path".** On 10 new annual reports that neither the reader nor its labels had seen, the second-round
reader reads **55% of the stated amounts on the whole path** (51 of 93) and **67% on the true statement pages** (62 of 93). The
threshold of rule 3 is 70%; the result is 15 points under it, not a borderline reading. It **still never shows a wrong amount**:
every amount it does not read is null, with its reason.

The phase answers a question Phase 2g could not: **whether naming the missing forms closes the gap. It does not.** The changes
of this round recovered 21 amounts on the 12 reports they were written from, and **3 amounts on the 10 new ones** (an extra
comparison, below). The new reports brought forms that none of the 17 earlier ones had: a header line that holds the year-end
date's day beside the years, a unit written without "in", a title alone on the page before its table, EPS per share class, and
other names for revenue, operating cash flow and interest expense. A list of rules follows the reports it was written from; each
new set of layouts adds to the list.

## The decision rule, clause by clause

Over the 10 new reports, condition C, PDFKit; 93 stated amounts and 7 null, 100 labelled amounts.

| Rule | Threshold (fixed before the held-out run) | Measured | Applies |
|---|---|---|---|
| 1 Build | correct on at least 85% of stated amounts, and confidently wrong on at most 3% of labelled amounts | 51/93 = **54.8%**; confidently wrong **0** | no |
| 2 Improve | correct on 70% to 85%, or at least 85% with more confidently wrong amounts than rule 1 allows | 54.8% | no |
| 3 Stop this path | correct on less than 70% | 54.8% | **yes** |
| 4 Reported in every case | A and C on the development and new reports; the misses by kind; the currency check; the sensitivity reading; the time | below | - |

## Rule 4: what is reported in every case

| | Development (17 reports, 157 stated) | New held-out (10 reports, 93 stated) |
|---|---|---|
| Reader, A (true pages) | 150/157 (95.5%), 0 wrong | 62/93 (66.7%), 0 wrong |
| Reader, C (whole path) | 150/157 (95.5%), 0 wrong | **51/93 (54.8%), 0 wrong** |

- **The gap between development and held-out is about 41 points** (Phase 2g: 3 points). The 17 development reports had been read
  to write the changes, so their 95.5% measures how well the rules cover the reports they came from, as the development record
  said it would.
- **The misses by kind** (A, 31; details in `phase-2h-runs.md`): layout 15 (a header line with the date's day beside the years,
  10, in one report; a unit without "in", 3; a footnote marker read as a cell, 2); row names not in the synonym table 10
  (revenue 4, operating cash flow 3, interest expense with a qualifier 2, capex 1); the structure of the per-share and net income
  rows 6 (EPS rows named after net income, EPS per share class, an attributable line printed twice). Two reports hold 18 of the
  31. On C, 11 more: 6 of the 20 statement pages were in the keywords' top 3 but not recognised (no year header, a title alone on
  the page before, too few rows the reader knows).
- **The keyword search is not the problem:** a true statement page is in its top 3 for 20 of 20 statements (embeddings: 0 of 20,
  as in the pilot).
- **The currency check (R10)** has nothing to report: no report in another currency was supplied. The guard of R5 is tested only on
  made-up statements (its Swift tests).
- **The sensitivity reading** (the literal schema wording; 15 alternative values) leaves both counts unchanged, as in Phase 2g: the
  reader applies the strict rule.
- **Time:** 0.17 s (A) and 0.18 s (C) for the 10 reports on the Mac, without the keyword search.

## An extra comparison (not in the spec, run after the held-out run, on the user's go)

The Phase 2g reader (tag `v2.7.0`; its sources match the Phase 2g freeze hashes) on the same 10 reports, with the same labels and
scorer: **C 48/93 (51.6%), A 60/93 (64.5%)**, 0 confidently wrong. Against it, the second round gains 3 amounts on C and 2 on A
(two operating cash flow names, and one cash flow page that is now recognised), loses none and adds no wrong amount. So on reports
that neither round has seen, the second round is better by about 3 points; on the 12 reports it was written from, by 19 points.

## Limits

- 10 reports, 93 stated amounts: one amount is about 1.1%. The result is 15 points under the threshold of rule 3, far more than a
  few amounts. The misses are concentrated (two reports hold 18 of the 31 on A), which is what layouts do: one header form can
  empty a whole report.
- The reports are large US companies with 10-K filings, as before; one is a bank, whose statements print no operating income and
  no capex line (nulls by R8).
- The labeller is the developer of the reader; the order (reader frozen, then the inclusion check, then labels, then run) and the
  user's spot-check of the report chosen by seed (10 of 10 confirmed) limit it.
- PDFKit on iOS may split lines differently from macOS; the reader has not run on the phone.
- All 27 reports are now used, as development or as test; any further test needs new reports.

## What "stop this path" means, and what remains

The path that stops is **raising the reader to "build" by adding named rules round by round**. Two results stand and can be reused:

- **The reader never shows a wrong amount**: 0 confidently wrong over the 170 labelled development amounts and over the 220
  labelled held-out amounts of the two rounds (120 and 100; 205 stated, 15 null). Its layer for rows, year columns, units and signs is what the model lacked (the model's main
  errors in Phases 2f and 2g were the oldest column and the first column taken as the current year).
- **The keyword search finds the statement pages** (10 of 10 in the pilot, 20 of 20 here).

The choice of what comes next is the user's. The options, each a new spec with its own decision rule:

1. **Leave PDF statements for now** and go back to the product's other parts (the overview and business sections), with pasted
   text as the app's input.
2. **A different design for the rows**, not a third round of rules: code keeps the rows, the year columns, the unit and the sign,
   and something more general than a synonym table decides which row is which field (for example the model choosing among the
   page's row labels, a closed choice without the columns it misreads). On these 10 reports it would address the 16 misses of
   row names and row structure, not the 15 of layout. It would need new reports again to be measured.
3. **Building with the reader as it is**, its nulls shown as "not found": it never shows a wrong amount but reads only about half
   of them on new reports. That is against rule 3, so only as the user's explicit decision, disclosed as such.
