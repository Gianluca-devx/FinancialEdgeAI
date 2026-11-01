# Phase 2f, the PDF pilot: analysis against the decision rule

Spec: [`Specs/phase-2f-pdf-pilot.md`](../Specs/phase-2f-pdf-pilot.md) (approved 2026-10-29). Counts: [`phase-2f-labels.md`](phase-2f-labels.md)
(step 3), [`phase-2f-runs.md`](phase-2f-runs.md) (steps 4 and 5). Five annual reports drawn by a committed seed, 45 stated amounts and
5 null, `lora-v3` seed 1 on the Mac (3 seeds) and once on the iPhone 16 for time. No report text, page or answer is committed.

## Conclusion

**Rule 2 applies, "redesign", and it is borderline.** On the true statement pages the model is correct on 53% (PDFKit text) and
62% (`pdftotext`) of the stated amounts, under the 70% that a "go" needs; a simple row matcher in code is correct on 69% and 78%.
The spec proposes "code reads the tables, the model reads the prose", as a new spec. Finding the pages is not the problem: a
keyword search puts a true page of both statements in its top 3 for all 5 reports.

Why borderline: rule 2 does not say which extraction counts. With `pdftotext` the code is at 78% and the model at 62%, so the rule
applies. With PDFKit, the app's extraction, the code is at 69%, one amount short of 70%. Read per run, the code is about 7 amounts
ahead of the model, not the 15 of the rule's first clause. The reading was agreed with the user before this analysis was written
(2026-11-01). A sensitivity reading below makes it firmer, not weaker.

## The decision rule, clause by clause

Amounts are counted per run of the 45 stated amounts (the code runs once and is deterministic; the model's 3 runs are averaged).

| Rule | Threshold (fixed before the pilot) | Measured | Applies |
|---|---|---|---|
| 1 Go | model on A at least 70% with either extraction, and the chosen retriever finds both statements for at least 4 of 5 reports | model 53.3% (PDFKit), 61.5% (`pdftotext`); keywords 5 of 5 | **no** (the model) |
| 2 Redesign | code at least 15 amounts above the model on A | 7.0 (PDFKit: 31 against 24.0), 7.3 (`pdftotext`: 35 against 27.7) | no |
| | or the model below 70% on A while the code is at or above it | PDFKit: 53.3% against 68.9%; `pdftotext`: 61.5% against 77.8% | **yes, with `pdftotext`** |
| 3 Stop | model and code both below 50% on A, or the best retriever fails on 3 or more reports | model at least 53.3%, code at least 68.9%; keywords fail on none | no |

If the 15 amounts were counted over the model's three runs against three copies of the code's one run, the difference would be 21
and 22, and the first clause would apply too. The amounts of the rule are the 45 labelled ones, so it is read per run here.

## Where the path breaks

| Part | Result | Reading |
|---|---|---|
| Finding the pages (B) | keywords 10/10, embeddings 0/10, hybrid 0/10 | **Not the problem.** Statement pages have distinctive titles; BM25 finds them. |
| Reading the tables (A) | model 53% / 62%, code 69% / 78% | **The problem.** See the kinds of errors below. |
| The extraction (P8) | `pdftotext` beats PDFKit: model +3.7 amounts per run, code +4, rows intact 27 against 25 of 30 | The app cannot ship `pdftotext`; PDFKit's text costs about 4 of 45 amounts. |
| The whole path (C) | 74/135 (54.8%) with keywords and 6 pages per report | **As good as A with PDFKit** (72/135): the retrieval loses nothing. 53 conflicts between pages, 3 undecodable answers on one non-statement page. |
| Time on the phone (P7) | 18.6 s per page, about 2 minutes per report (6 pages), 2.89 GiB, thermal nominal | Usable for a report the user opens and waits for; not for a batch. |

## The model's errors on the tables

`Scripts/pdf_pilot.py kinds` sorts each wrong or invented amount by where its number is printed on the page: on the labelled row or
another row, and in which column (1 is the current year). The counts of the scorer do not change.

| Condition A, 3 runs | PDFKit | `pdftotext` |
|---|---|---|
| Previous year, **third column** (two years back), labelled row | 9 | 6 |
| Previous year, **third column**, another row | 20 | 17 |
| Previous year, right column, another row | 4 | 7 |
| Current year, right column, **another row** | 22 | 16 |
| Invented (label null), another row | 4 | 6 |
| **Wrong or invented in all** | 59 | 52 |

- **Three-year tables.** The statements print three years. For a previous-year field, the model copies the oldest column in 29 of
  33 wrong answers with PDFKit (23 of 30 with `pdftotext`). The training statements only ever had two periods.
- **The right year, another row.** Every current-year error is a neighbouring row: basic earnings per share where diluted is printed
  too, net income including noncontrolling interests instead of the part attributable to shareholders, and net sales where a report
  also prints a larger total of net sales and revenues. The schema names the first two choices; the model does not follow them on a table.
- **Invented values:** an operating income taken from a costs total or an income before taxes, on the two reports that print none.
- The errors repeat across seeds (per run: 23, 25, 24 correct with PDFKit; 28, 27, 28 with `pdftotext`): they come from the input,
  not from sampling.

## The code's errors

The row matcher is not correct on 14 amounts with PDFKit and 10 with `pdftotext`:
- **missed, 10 and 6:** a row name not in its list (a revenue row called only "Sales", earnings per share rows whose long names do
  not start with "Diluted"), and, with PDFKit only, rows of one report whose label and number fall on different lines;
- **wrong, 2:** one report prints "Net sales" before a larger total, and the matcher takes the first;
- **unit, 2:** the two amounts of the cash flow page that prints no unit, scored as for the model.

Its patterns were written before the draw; widening them now would fit them to these five reports, so any better matcher must be
measured on reports it has not seen.

## A sensitivity reading (made after seeing the results; not used for the decision)

The schema says "diluted if both are printed" and "attributable to shareholders if both are printed" for the current year only; for
the previous year it says just "earnings per share of the previous year" and "net income of the previous year", and revenue is
"total revenue or net sales". My labels apply the current-year rule to the previous year too, and take the total where a report
prints both net sales and a total. A second count (`score --also`, with 11 alternative values from the statement pages, private)
also accepts the literal reading: the basic EPS and the total net income of the previous year, and net sales.

| Stated amounts correct | Fixed labels | Literal reading also accepted |
|---|---|---|
| Model A, PDFKit | 72/135 (53.3%) | 79/135 (58.5%) |
| Model A, `pdftotext` | 83/135 (61.5%) | 93/135 (68.9%) |
| Model C, PDFKit | 74/135 (54.8%) | 81/135 (60.0%) |
| Code A, PDFKit | 31/45 (68.9%) | 33/45 (73.3%) |
| Code A, `pdftotext` | 35/45 (77.8%) | 37/45 (82.2%) |

The model stays under 70% on both extractions; the code passes it on both. Under this reading, rule 2 applies with either
extraction. The schema's previous-year wording is loose and could be made explicit in a later schema version (a new experiment).

## Other findings

- **Embeddings do not find statements.** `NLContextualEmbedding` with mean-pooled vectors puts prose first (6% of words with a digit
  in its top pages, 30% on the statement pages) and the true pages at ranks 36 to 177; the fusion with keywords drags the hybrid down
  to 0/10. It says this of this model and this pooling, not of embeddings in general. Indexing costs about 96 s per 920 pages on the
  Mac. Not worth carrying into the app for this task.
- **Growth.** The labels cover the statement pages, which print no percent, so every growth label is null. In condition C, 7 growth
  values came from a page of the management discussion of one report: each is printed there with a percent sign and matches the growth
  computed from the labelled amounts, rounded to a whole percent. They are counted as "growth invented" by the fixed scorer but are
  not invented.
- **Mac and phone agree.** 17 of 18 answers on the phone were the same text as on the Mac for the same page and seed, so the Mac
  results stand for the phone for this adapter.
- **The garbled key appears on a PDF page too** (`previous48YearEps`, 2 of 3 seeds on one non-statement page), as on `real3`.

## Limits

- Five reports and 45 stated amounts: one amount is 2.2% of a run. The thresholds are a judgement for a pilot, and the result sits
  close to two of them.
- The labels are mine; the user answered the spot-check of one report with "Go".
- The retriever was chosen on the same 5 reports it was used on (disclosed in the spec); with 10/10 against 0/10 the choice is not
  close.
- The 17 reports were read before for `real1` to `real3` (prose paragraphs, not the statements). 12 reports are left that the pilot
  did not draw: a next spec can draw a fresh set from them.
- One model, one adapter (`lora-v3` seed 1), one prompt, the Mac for the answers and the phone for the time only.

## What the rule's outcome means

The rule says: a new spec where **code reads the statement tables and the model reads the prose**. The analysis also shows what
that spec must face, without deciding it here:

- **Code for tables** needs a matcher that holds on reports it has not seen (row names vary: "Sales", "Total revenues", "Net sales
  and revenues"), the unit from the header, and the three-year columns; it is exact when it matches and silent when it does not.
- **The model's table errors are specific**: the third column, and the neighbouring row where the schema names the choice. Training
  data built from three-year statement tables, with those neighbouring rows, is the other possible path (the remedy that rule 3
  names). It would be a new adapter and a new experiment.
- Either way, **keywords find the pages**, PDFKit is the extraction to measure, and about 2 minutes per report on the phone is the
  cost of the model on 6 pages.
