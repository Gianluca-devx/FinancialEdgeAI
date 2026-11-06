# Phase 2g, a statement table reader in code: analysis against the decision rule

Spec: [`Specs/phase-2g-table-reader.md`](../Specs/phase-2g-table-reader.md) (approved 2026-11-02). Counts:
[`phase-2g-development.md`](phase-2g-development.md) (step 2, the 5 development reports), [`phase-2g-heldout.md`](phase-2g-heldout.md)
(step 3, the freeze and the labels), [`phase-2g-runs.md`](phase-2g-runs.md) (step 4, the held-out run). No report text, page or
answer is committed, and no company is named.

## Conclusion

**Rule 2 applies: "improve".** On 12 annual reports it was not written for, the reader reads **81% of the stated amounts on the whole
path** (keyword search, then the page it recognises) and **86% on the true statement pages**, and it **never shows a wrong amount**:
every amount it does not read is null, with its reason. "Build" needed 85% on the whole path; the reader is 4.5 points short, with no
confidently wrong amount against an allowed 3%.

The phase answers the pilot's question: **for statement tables, rules in code beat the model** by a wide margin on fresh reports
(81% with 0 wrong against the model's 56% with about 46 wrong per run), and the reader was not fitted to its five development reports
(84% there, 81 to 86% on the new ones). What it lacks is named and specific: wording its synonym table does not know, two title forms,
and a note reference inside a row.

## The decision rule, clause by clause

Over the 12 held-out reports, condition C, PDFKit; 112 stated amounts and 8 null, about 120 labelled amounts.

| Rule | Threshold (fixed before the held-out run) | Measured | Applies |
|---|---|---|---|
| 1 Build | correct on at least 85% of stated amounts, and confidently wrong on at most 3% of labelled amounts (at most 3 of about 120) | 91/112 = **81.2%**; confidently wrong **0** | no (the first half) |
| 2 Improve | correct on 70% to 85%, or at least 85% with more confidently wrong amounts than rule 1 allows | 81.2% | **yes** |
| 3 Stop this path | correct on less than 70% | 81.2% | no |
| 4 Reported in every case | development against held-out; the model on the held-out pages; the fallback; the errors by kind; the sensitivity reading; the time | below | - |

## Rule 4: what is reported in every case

| | Development (5 reports) | Held-out (12 reports) |
|---|---|---|
| Reader, A (true pages) | 38/45 (84.4%), 0 wrong | 96/112 (85.7%), 0 wrong |
| Reader, C (whole path) | 38/45 (84.4%), 0 wrong | **91/112 (81.2%), 0 wrong** |
| Model `lora-v3`, A, mean of 3 seeds | 24.0/45 (53.3%), 21.7 wrong per run | 62.3/112 (55.7%), 45.7 wrong per run |

- **The gap between development and held-out is small** (A +1.3 points, C -3.2): the rules were not tuned to five reports. The held-out
  misses come from wording and layouts the five reports did not contain, not from rules that only fit them.
- **The pilot's model result holds on fresh reports:** 55.7% against 53.3%, with the same two errors: previous-year values from the
  oldest of three year columns (50 of its 137 confidently wrong amounts), and, new here, the **first column taken as the current year
  in both reports that print their years oldest first** (35). A model that reads columns by position is not a table reader.
- **The fallback (the model filling only the reader's nulls) meets its rule by the letter, by one amount:** over 3 seeds it adds
  28 correct and 27 confidently wrong amounts. Read against rule 1, it takes the reader from 0 confidently wrong amounts per run to 9
  (7.5% of the labelled amounts, more than twice the 3% that "build" allows). Its wrong amounts are the model's known errors: 12
  invented interest expenses (where the statement prints no such line) and 15 values from the oldest column. **As it is, the fallback
  does not belong in the app's statement path**; the decision is the user's.
- **The sensitivity reading** (the literal schema wording for previous-year EPS and net income, and net sales beside a larger total)
  leaves the reader's counts unchanged (91 and 96), because the reader applies the strict rule; the model rises to 59.5%.
- **Time:** the reader reads the 12 reports in 0.16 to 0.20 s on the Mac, without the keyword search; the model needs about 8 s per
  page on the Mac and 18.6 s per page on the phone (Phase 2f).

## The reader's misses by kind

All 21 misses of C are nulls; none is a wrong value.

| Kind | Missed on C | What a fix would be (a second round, measured on new reports) |
|---|---|---|
| A loss year: "Operating loss", "Net loss", one "Basic and diluted" EPS row | 5 | loss forms of the income rows, sign kept from the parentheses |
| A loss-year income statement not recognised (too few rows the reader knows, for the same reason) | 2 | follows from the row above |
| "Consolidated net income attributable to ..." | 2 | the "consolidated" prefix in the attributable rule |
| "Net cash from operations" | 1 | one more operating cash flow form |
| Capex line names: "Investment in ...", "Purchases related to ...", "Payments for property and equipment" | 3 | more capex forms; the broader lines are a labelling choice already agreed |
| Two cash flow statements titled "... cash flows statements" (not recognised in C) | 3 | the title in either word order |
| Two capex lines whose names start the same, with different values (a discontinued-operations line, a financing line, a supplemental line) | 3 | none needed: null by T6, as designed; or a rule for the investing section of continuing operations |
| A note reference inside the EPS rows ("(Note 12)") | 2 | a note reference read as a footnote marker |

How many of these a second round recovers cannot be claimed from these 12 reports: they have been read, so a fix made now would be
tuned to them. It has to be measured on reports neither the rules nor the labels have seen.

## Limits

- 12 reports from one filing year, mostly large US companies in a narrow range of industries; 112 stated amounts make one amount
  about 0.9%. The result sits 4.5 points under the build threshold, which is more than a few amounts.
- The labeller is the developer of the reader. The order (reader frozen, then labels, then run) and the user's spot-checks (the report
  chosen by seed, 10 of 10, and one more) limit it.
- PDFKit on iOS may split lines differently from macOS; the reader has not run on the phone.
- All 17 reports are now used, as development or as test; a second round needs new reports, which the user will supply.

## What "improve" means

The rule says the reader is close. A second round would add the named forms above to the synonym table and the title rule, freeze the
reader again, label new reports and run the same decision rule on them. A "build" would then lead to the integration spec: PDF import
in the app with this reader, the keyword search for the pages, and the check that PDFKit gives the same rows on the phone.
