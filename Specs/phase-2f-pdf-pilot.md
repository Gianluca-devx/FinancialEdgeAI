# Spec: Phase 2f, a PDF pilot (DRAFT)

Status: **DRAFT, not approved** (written 2026-10-26; the comparison of three retrievers, P9, added on 2026-10-28 at the user's request). Nothing in it is built. It becomes binding when the user approves it. The decisions are mine, each with the alternative.
Depends on `v2.5.0` (`lora-v3`) and its third-seed analysis (`Results/lora-seed3-analysis.md`).

**Goal:** find out, on whole annual-report PDFs, **where the path from a PDF to the 13 core fields breaks**, and whether the current model and adapter are usable on it. The pilot should give a go, a
redesign or a stop for building the PDF pipeline in the app, and a measured estimate of the time per report on the phone.

**Out of scope:** any change to the app, the prompt, the schema, the parser, the adapter or the evaluation code (the pilot runs as scripts on the Mac); training; the overview and business sections; the
extended (balance sheet) call; UI for importing a PDF.

## What is known, and what was never tested

- **Known:** the real sets (`real1` to `real3`) were already taken from PDFs. `Scripts/real_set.py` runs `pdftotext` on the 17 reports in `~/Downloads/Reports`, then a keyword rule
  picks **single prose paragraphs** that already contain an amount. So the model has seen PDF text, but only paragraphs that were found for it and cut to six sentences.
- **Never tested:**
  1. **Tables.** The figures of an annual report are mostly in the financial statements, which are tables. As text they become rows of numbers, with the unit in a header ("in millions, except per share") rather than next to the number.
     The prompt asks for strings "as printed, with the unit word", and `ValueParser` reads "245,122" as 245,122. All training data is prose.
  2. **Finding the pages.** A report is long: the 17 extracted texts hold about 1.36 million words, about 80,000 words each, far beyond one call. The relevant pages (income statement, cash flow statement, highlights) must be found first.
  3. **Several calls per report**, and combining their answers into one result when they disagree.
  4. **The extraction the app would use** (PDFKit on iOS) against `pdftotext`.
  5. **The time per report on the phone**: about 11 s per call for a short statement today. The prompt-processing rate measured in Phase 1 (567 prompt tokens, 3.7 s to the first token) is about 150 tokens per second, so a 1,500-token page costs about 10 s before any answer.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| P1 | **Run the pilot on the Mac** with `mlx_lm` (the same `Qwen3-4B-4bit`, `lora-v3` seed 1, the same prompt, temperature 0.2, seeds 1 to 3). The phone is used only for one timing measurement, with the user's approval (P7). The Mac and the iPhone gave identical answers in the v1.1.0 baseline. | The phone for everything: hours of phone time for a pilot whose main questions (tables, finding, combining) do not depend on the device. |
| P2 | **Five reports, drawn by a committed seeded rule** from the 17 before any is labelled. The PDFs and their text are never committed; only counts are published, as for the real sets. The 17 were partly read for `real1` to `real3`, which is disclosed; the financial statements were not used before. | All 17: too much labelling for a pilot. Choosing by hand: cherry-picking. |
| P3 | **Ground truth from the statements:** for each report, the 7 current-year amounts (`revenue`, `operatingIncome`, `netIncome`, `eps`, `interestExpense`, `operatingCashFlow`, `capex`) and the 3 previous-year ones, read by me from the income statement and the cash flow statement, with their unit. The growth fields are labelled only if a percent is printed. The user spot-checks one report. | Labels from a data provider: they use their own definitions (adjusted figures), not the printed ones. |
| P4 | **Three conditions, measured separately, so each failure has its own number.** (A) **Oracle pages:** the model gets the true statement pages, which isolates the table problem (the generator alone). (B) **Page finder:** three retrievers (P9) each pick the top 3 pages per statement, which measures finding (the retriever alone). (C) **The whole path:** the chosen retriever (P9), the model on each picked page, then combining. This is a retrieval-augmented design (RAG) with two separate parts, a retriever and a generator, each with its own measure. | Measuring only the whole path: a bad result would not say what broke. |
| P5 | **A table baseline in code:** a deterministic row matcher on the same page text ("Total net sales", "Net income", "Diluted", "Purchases of property and equipment"), with the unit from the header. It is compared with the model on condition A. If code reads statement tables better than the model, the design may be "code reads the tables, the model reads the prose", and the pilot should say so. | Assuming the model is the right tool for tables. |
| P6 | **Units and scoring:** a value counts as correct if the number the model copied, scaled by the unit detected in the page header (millions, thousands, billions), equals the label. The detection is a pilot script, not a change to `ValueParser`. Separately counted: number right but no unit, wrong column (previous year for current), invented, missed. | Scoring strictly with today's parser: every table value would fail on the unit, which says nothing new. |
| P7 | **One timing run on the phone** (about 30 minutes, only with the user's approval): the pages of condition C for one report, through the app's existing external-set path (`-evaluationSet`), so no app change is needed. It gives the time per page and per report. | Estimating from the Mac: Mac speed says little about an iPhone at "serious" thermal state. |
| P8 | **PDFKit against `pdftotext`:** the text of the same statement pages extracted with PDFKit, by a Swift script on the Mac (the same `PDFPage.string` API as on iOS), compared with `pdftotext -layout` by whether the table rows stay intact (counts). Condition A is run with both. | Using only `pdftotext`: the app cannot ship poppler, so the result would not carry over. |
| P9 | **Three retrievers compared in condition B, on the same pages and the same two fixed queries** (one for the income statement: "consolidated statements of operations income net sales revenue operating income net income earnings per share"; one for the cash flow statement: "consolidated statements of cash flows operating activities purchases of property and equipment capital expenditures"). The unit retrieved is **one page**, so a table keeps its header and its unit. (1) **Keywords:** a BM25 score of each page against the query, in the pilot script. (2) **Embeddings:** Apple's on-device `NLContextualEmbedding` (English), run by a Swift script on the Mac (the same API as on iOS); a page vector is the mean of its token vectors, and the score is the cosine similarity with the query vector; if a page is longer than the model's maximum input, it is split into windows and its score is the best window's. (3) **Hybrid:** reciprocal rank fusion of the two rankings (score = sum of 1 / (60 + rank)). **Measure:** for each report and statement, whether a true statement page is in the top 3 (recall at 3), over 5 reports x 2 statements = 10 cases per retriever; the rank of the first true page is also reported. **Choice for condition C, fixed now:** the retriever with the highest recall at 3; on a tie, keywords, then hybrid (the simpler one wins). The choice is made on the same 5 reports it is then used on, which is disclosed. No reranking step in this pilot. | Keywords only: the design would not say whether a retriever by meaning finds pages the keywords miss. An embedding model from the Hub: a download and a second runtime, while `NLContextualEmbedding` ships with iOS. Chunks smaller than a page: they can separate a table's rows from its unit header. |

## Decision rule (fixed before the pilot runs)

Over the 5 reports, for the 10 labelled current-year and previous-year amounts:

1. **Go, build the PDF pipeline with the model:** on condition A, at least **70%** of the labelled amounts are correct as numbers (P6) with either extraction, and the chosen retriever (P9) has a true page of both statements in its top 3 for **at least 4 of 5** reports.
2. **Redesign:** if the code baseline (P5) is correct on at least **15 more amounts** than the model on condition A, or the model is below 70% on A while the code is at or above it, the proposal becomes "code for tables, model for prose". That would be a new spec.
3. **Stop and rethink:** if both the model and the code are below **50%** on condition A, or the best of the three retrievers fails on 3 or more reports. Table reading or finding is then the problem to solve first, with training data built from tables or a better finder (for example a reranking step).
4. **Reported in every case:** condition C's result and its number of calls; the measured time per report from P7, if run; conflicts between pages; PDFKit against `pdftotext`; the recall at 3 and first-true-page rank of all three retrievers, and the time to index a report on the Mac with embeddings.

A negative result is valid and is reported as it is. These thresholds are a judgement for a pilot of 5 reports and are disclosed as such: 50 labelled amounts give a coarse measure (one amount is 2%).

## Steps (branch `feature/pdf-pilot`, each one commit)

1. **GATE: the user approves this spec.**
2. `Scripts/pdf_pilot.py` (draw, extraction, keyword retriever, rank fusion, code baseline, scoring, counts only), `Scripts/pdf_pages.swift` (PDFKit text) and `Scripts/pdf_embed.swift` (`NLContextualEmbedding` page scores). Tests on a made-up PDF, and a tamper test showing the scorer fails on a wrong value and the recall count fails on a wrong page (`feat`, `test`).
3. Draw the 5 reports and freeze the draw (hash). Label the statements and save the labels privately in `RealSet/pdf/`, never committed; the user spot-checks one report (`data`, counts only).
4. Run conditions A, B and C on the Mac (`eval`, counts only).
5. **GATE:** the phone timing run (P7), only if the user approves.
6. Analysis against the decision rule, README, PR to `main` after the user's go (`docs`).

## Cost

About 4 to 6 days of my work (scripts, labelling about 50 amounts, analysis; the retriever comparison adds about a day), a few hours of Mac compute and no training. Phone: one run of about 30 minutes, only with approval. This is about 1 to 2 weeks of
calendar time, as estimated on 2026-10-26 (retrievers added 2026-10-28).

## Acceptance

1. The draw and the labels are frozen before any model run; the decision rule above is unchanged.
2. Every condition has its count of correct, unit-missing, wrong-column, invented and missed amounts, per extraction; each of the three retrievers has its recall at 3 over the 10 cases.
3. No PDF text, page or passage is committed; only counts are published.
4. A written conclusion says which rule applies (go, redesign or stop) and why.

## Risks

- **Five reports are few.** The decision is coarse, and a borderline result is reported as borderline.
- **The finder is simple on purpose.** A failure of a keyword finder does not mean finding is impossible, only that it needs work. It is reported as such.
- **The retrievers are compared on 10 cases each** (5 reports x 2 statements): a difference of one or two cases is not a ranking. `NLContextualEmbedding` was not built for financial text and its quality there is unknown; a weak result for embeddings says that of this model, not of embeddings in general. The indexing time on the phone (about 200 to 300 pages per report) is not measured by this pilot.
- **The labels are mine.** One report is spot-checked by the user; statements have little ambiguity compared with prose, but segment and adjusted figures still need the strict rule.
- **Mac and phone may differ** for the adapter (only the unmodified model was compared, in v1.1.0). P7 checks the timing on the phone, not the answers.
