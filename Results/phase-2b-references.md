# Phase 2b, step 5: the references before `lora-v2`

The unmodified model and `lora-v1` (iteration 150) on the new test sets, with the same prompt (`7779853b346c`), seeds
1, 2, 3, temperature 0.2, `maxTokens` 384, thinking off, the same iPhone 16 and the same Debug build. `lora-v2` is measured on
the same sets later; its success criteria are in `Specs/phase-2b-lora-wording.md`. Nothing here was used to train.

## Test 2 (`Dataset/v2/test2.jsonl`: 30 statements, wording in no training statement of either dataset)

Tables: `baseline-test2-tables-iphone-20261017.md`, `lora-v1-test2-tables-iphone-20261017.md`. Side by side, answer by answer:
`comparison-test2-base-vs-lora-v1.md`. Raw reports: `baseline-test2-...json`, `lora-v1-test2-...json`.

| | Unmodified model | `lora-v1` |
|---|---|---|
| Decodable answers | 90 / 90 | 90 / 90 |
| **All 13 fields correct** | 34 / 90 (37.8%) | **48 / 90 (53.3%)** |
| Fields correct | 1073 / 1170 (91.7%) | 1111 / 1170 (95.0%) |
| Wrong fields | 97 | 59 |
| Invented values (hallucinated) | 75 | **3** |
| **Missed values** (null where the text states one) | 9 | **56** |
| Other (wrong number, sign, unreadable) | 13 | 0 |
| Time per statement (median) / peak memory | 9.8 s / 2.50 GiB | 10.6 s / 2.65 GiB |

- **The finding of Phase 2 repeats on a fresh set.** The adapter removes almost every invented value (75 to 3), which is what
  it was trained to do, and replaces them with missed values (9 to 56): 12 `netIncome`, 11 `operatingIncome`, 9
  `previousYearNetIncome`, 6 `revenue`, 6 `interestExpense`, 6 `epsGrowth`. These are new wordings ("profit for the period",
  "net income attributable to the company", "result from operations") that it never saw. The diagnosis of
  `lora-v1-analysis.md` (the adapter learned the phrases, and null is its safe answer) is now confirmed on 30 other statements
  written by another pool.
- **Test 2 is harder than the old test for the unmodified model** (37.8% fully correct against 63.3%): the wording and the
  structures (lines, tables, first person) are new to it too. That is the reference for the criterion on test 2.
- **Reference numbers for `lora-v2` on test 2** (criterion of the spec): at least 9 more fully correct answers than `lora-v1`, so
  **at least 57 of 90**, no fewer than the unmodified model (34), and **fewer than 59 wrong fields**.

## The real-style sets (from the user's 17 annual reports): counts only

The passages are not in the repository, by the user's instruction (`RealSet/` is git-ignored; no commit contains a passage).
The sets are described in `Specs/phase-2b-lora-wording.md` (D28 and its two amendments). The numbers below come from
`python3 Scripts/report_counts.py`, which prints counts and never a statement. **The labels were spot-checked by the
user on 18 October: 3 of the 5 listed labels are confirmed; for the other two the answer was "not understanding" and "depends on
the context before and after". Those two stay as I wrote them (the rule is: from the passage text only), flagged uncertain, and
they touch 3 fields per model: the revenue of one `real1` passage (a hypothetical constant-currency figure, which only `lora-v2`
wrote as revenue) and the net income of one `real2` passage (`lora-v2` wrote the cash flow amount there; `lora-v1` left it null; the
unmodified model wrote the figure that I labelled). If they were labelled the other way, at most 3 answers per model would change sides
in each set, and the order of the models would not.**

Both sets are mostly null: the passages of an annual report's discussion rarely state a headline figure in a sentence (those
are in tables, outside the dataset's rules), so these sets measure above all whether a model **invents values on real text**.

| | `real1`, unmodified | `real1`, `lora-v1` | `real2`, unmodified | `real2`, `lora-v1` |
|---|---|---|---|---|
| Passages x runs / fields stated in the labels | 21 x 3 / 3 | 21 x 3 / 3 | 10 x 3 / 9 | 10 x 3 / 9 |
| Decodable answers | 63 / 63 | **60 / 63** | 30 / 30 | **27 / 30** |
| **Fully correct answers** | 39 / 63 | **50 / 63** | 21 / 30 | **12 / 30** |
| Fields correct | 771 / 819 | 764 / 819 | 366 / 390 | 321 / 390 |
| Invented values (hallucinated) | 42 | **16** | 21 | 24 |
| Missed values | 0 | 0 | 0 | 3 |
| Answers not decodable | 0 | 3 | 0 | 3 |
| Time per statement (median) / peak memory | 9.4 s / 2.55 GiB | 10.3 s / 2.71 GiB | 9.2 s / 2.52 GiB | 10.0 s / 2.67 GiB |
| Prompt tokens (median) | 654 | 654 | | |

- **`real1` (mostly distractors): the adapter helps.** It halves the invented values (42 to 16) and fully matches 50 of 63
  answers against 39.
- **`real2` (headline statements): the adapter hurts.** 12 of 30 fully correct against 21; 24 invented values against 21 and 3
  missed values out of 9 stated.
- **A new kind of failure, only with the adapter: a garbled key.** One passage makes the adapter write the key
  `previous6YearEps` instead of `previousYearEps` in all three runs: the JSON is valid, the schema is not, the answer cannot be
  used (3 answers in each set, the same passage, which is in both sets). The unmodified model never does it. It is one
  passage; it shows that an adapter can break the output format on text it has not seen, which the 90 clean synthetic
  answers could not show. In the field counts, the 3 undecodable answers cost 39 fields (13 each) in each set.
- **Read these with caution:** 21 and 10 passages, 3 and 9 stated fields, three runs that are nearly identical, 2 of the labels uncertain (3 fields per model), text
  chosen by a rule that I wrote and amended once after reading the first draw (disclosed in the spec).

## What this means for the next step

1. On the old test the adapter looks good (78 of 90 against 57); on test 2 it is better than the unmodified model but with 56
   missed values; on real text it halves the inventions in distractor-heavy passages and is worse on headline statements.
   The adapter is specialised to the wording of the training data. More varied wording is the right experiment, as the spec says.
2. The format failure on real text is a second thing to watch in `lora-v2`: the number of undecodable answers must stay 0.
3. The checkpoint choice matters (`lora-v1-checkpoints.md`: 68, 42, 78 fully correct at iterations 50, 100, 150): the Phase 2b
   training uses the validation split with held-out wording and a stop rule written in advance.

## Limits

One adapter (one training run, one seed), one phone (Debug build), 30 statements in test 2, 21 and 10 passages in the real sets, three
runs that are nearly identical. The statements of test 2 are synthetic and written by the same author as the training data
(another pool, other structures). The real sets are real text, but selected and labelled by me; 3 of the 5 labels in doubt were confirmed by the user, 2 stay uncertain.
