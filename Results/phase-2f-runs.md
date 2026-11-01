# Phase 2f, step 4: conditions A, B and C on the Mac (counts only)

Spec: `Specs/phase-2f-pdf-pilot.md`. Run on 2026-10-31 on the Mac, with no phone, by the committed scripts (`Scripts/pdf_pilot.py`,
`Scripts/pdf_embed.swift`, `Scripts/lora/pdf_generate.py`, commit b3dad25), on the frozen draw (`3fa0b7354977`) and the frozen labels
(`c087c0da286b`, unchanged; the user answered the spot-check of one report with "Go" on 2026-10-31). The reports, their text, the
model's answers and the per-report results stay in `RealSet/pdf/` (git-ignored). This file holds counts only. The reading against the
decision rule is step 6.

Model: `mlx-community/Qwen3-4B-4bit` with `lora-v3` seed 1 (weights `26a0d90702e19f00`, checked before every run), the core prompt of
schema 1, one page per call, thinking off, temperature 0.2, at most 384 tokens, seeds 1, 2, 3; `mlx_lm` 0.32.2, `mlx` 0.32.4.

## Condition B: the three retrievers (P9)

10 cases per retriever (5 reports x 2 statements); a case is a hit when a true statement page is in the top 3. 920 pages in all
(80 to 295 per report).

| Extraction | Retriever | Recall at 3 | Reports with both statements in the top 3 | Rank of the first true page, per case |
|---|---|---|---|---|
| PDFKit | keywords (BM25) | **10/10** | **5/5** | 1, 1, 1, 2, 1, 2, 1, 1, 1, 1 |
| PDFKit | embeddings | 0/10 | 0/5 | 80, 60, 177, 152, 44, 174, 117, 108, 40, 66 |
| PDFKit | hybrid (RRF) | 0/10 | 0/5 | 18, 12, 38, 28, 12, 28, 29, 23, 12, 16 |
| pdftotext | keywords (BM25) | 10/10 | 5/5 | 1, 1, 1, 2, 1, 2, 1, 1, 1, 1 |
| pdftotext | embeddings | 0/10 | 0/5 | 80, 61, 172, 157, 36, 172, 118, 106, 40, 68 |
| pdftotext | hybrid (RRF) | 0/10 | 0/5 | 18, 14, 36, 31, 12, 27, 30, 23, 12, 16 |

- **Chosen for condition C by the fixed rule (highest recall at 3 on the PDFKit text): keywords.**
- **Embedding indexing time on the Mac:** 95.5 s for the 920 pages with the PDFKit text (9.2 to 32.7 s per report), 96.1 s with
  `pdftotext`. `NLContextualEmbedding` English, 512 dimensions, maximum 256 tokens, windows of 128 words.
- **Checked before reporting the 0/10, so it is not a bug:** the ranking is best first; on made-up pages the script gives 1.0 to a
  page equal to the query. But it gives a made-up income statement 0.828 for the income query, against 0.803 for an unrelated
  paragraph about sustainability; for the cash flow query the unrelated paragraph wins (0.832 against 0.830). On the real reports all
  page scores lie between about 0.75 and 0.95, and the true pages sit near the median. The pages the embeddings put in their top 3
  are prose: 6% of their words contain a digit, against 30% on the true statement pages (11% over all pages). Mean-pooled vectors of
  this model do not separate a statement table from prose about the same subject.

## Rows kept intact (P8)

The labelled current-year rows (30 stated amounts) whose label and number are on one line of the page text: **PDFKit 25/30,
`pdftotext -layout` 27/30.**

## Condition A: the oracle pages (the generator alone)

The true statement pages of each report (2 per report, 10 calls per seed). 45 stated amounts and 5 null per run; the model has 3 runs
(135 stated), the code 1 (45 stated). "Correct" counts the null labels left null too (5 per run).

| | Extraction | Correct | Unit | Column | Invented | Missed | Unparsed | Wrong | **Stated amounts correct** | Per seed | Conflicts | Undecodable |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Code baseline (P5) | PDFKit | 36 | 2 | 0 | 0 | 10 | 0 | 2 | **31/45 (68.9%)** | - | 0 | 0 |
| Code baseline (P5) | pdftotext | 40 | 2 | 0 | 0 | 6 | 0 | 2 | **35/45 (77.8%)** | - | 0 | 0 |
| Model | PDFKit | 83 | 6 | 0 | 4 | 2 | 0 | 55 | **72/135 (53.3%)** | 23, 25, 24 | 13 | 0 |
| Model | pdftotext | 92 | 6 | 0 | 6 | 0 | 0 | 46 | **83/135 (61.5%)** | 28, 27, 28 | 16 | 0 |

- No growth value was invented on condition A (the three growth fields are null in all labels).
- The 2 "unit" amounts per run are the two amounts of the cash flow page that prints no unit (reported in
  `Results/phase-2f-labels.md`): by the fixed rule they cannot be scored correct, for the model and for the code alike.
- "Column" only counts the current and previous year swapped. An amount copied from the third year column (two years back) of a
  three-year table is counted as "wrong". The kinds of "wrong" are sorted in step 6, without changing the counts above.

## Condition C: the whole path

Keywords pick the top 3 pages per statement; their union is at most 6 pages per report. Here it was **6 pages for every report:
30 calls per seed**, 90 in all, combined per report by best rank.

| Extraction | Correct | Unit | Column | Invented | Missed | Unparsed | Wrong | **Stated amounts correct** | Per seed | Conflicts | Undecodable | Growth invented |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PDFKit | 84 | 0 | 0 | 5 | 0 | 0 | 61 | **74/135 (54.8%)** | 24, 25, 25 | 53 | 3 | 7 |

- **The 3 undecodable answers** all come from the same non-statement page of one report, one per seed: twice a garbled key
  (`previous48YearEps` and `previous48` instead of `previousYearEps`, valid JSON with a wrong key), once a run of repeated digits up
  to the token limit (not JSON). The garbled key is the weakness already known from `lora-v3` on real text (`Results/lora-v3-analysis.md`).
- The 53 conflicts count fields for which two pages of a report gave two different readable values (over the 3 runs). With 6 pages
  per report, most pages are not statements.

## Time on the Mac (for scale only; the phone is P7)

| Condition | Calls | Prompt tokens, median (max) | Seconds per call, median (max) | Total minutes |
|---|---|---|---|---|
| A, PDFKit | 30 | 1,373 (1,661) | 8.4 (9.2) | 4.2 |
| A, pdftotext | 30 | 1,512 (1,828) | 8.8 (9.3) | 4.4 |
| C, PDFKit | 90 | 1,377 (2,783) | 8.0 (16.5) | 12.2 |

A statement page is about 1,100 to 1,800 prompt tokens, two to three times the 567 tokens of a synthetic statement. Condition C
costs 6 calls per report, so about 50 s per report on the Mac before any phone measurement.

## Step 5: the timing run on the phone (P7)

Run on 2026-10-31 on the user's approval, with the details fixed and committed before it (spec, "Details fixed before the phone
run", 59c9bd3). iPhone 16 (iPhone17,3), iOS 27.0.1, the build already on the phone (no app code changed since it was installed),
`-evaluationSet pdfc -adapterName lora-v3`. The report records `lora-v3` with weights `26a0d90702e1` and config `a5a91a164061`
(the expected ones), prompt hash `7779853b346c` and schema hash `f70490659aa3` (the same as every `lora-v3` run), and the set hash
`ff8eec2c38e1` (the set built by `phoneset`). The set is the 6 condition C pages of one report (the seeded spot-check report), 3 runs:
18 calls. The report is private (`RealSet/reports/`, sha256 `22f13c3cb4c0`): it holds the answers.

| Measure | Phone | Mac (the same 18 calls, step 4) |
|---|---|---|
| Prompt tokens per page | 1,028 to 1,535 | the same |
| Time per page, median (min to max) | **18.6 s** (13.8 to 22.6) | 7.7 s |
| Time to the first token (prompt processing), median | 11.0 s (about 112 prompt tokens per second) | - |
| Generation speed, median | 13.9 tokens per second | - |
| **Time per report (6 pages)** | **102 s in run 1, 122 s in runs 2 and 3** | 46 s |
| Model load | 3.0 s | - |
| Peak memory | 2.89 GiB | - |
| Thermal state | nominal in all 18 calls | - |
| Valid JSON with the schema's keys | 18/18 | 18/18 |
| Answer identical to the Mac's (same page, same seed) | **17/18** | - |

- **About 2 minutes per report on the phone** for condition C's 6 pages, without the embedding or keyword indexing (keywords take no
  model). Run 1 was faster (the first pages at 18 tokens per second); from its fourth page on, generation settled at about 14 tokens
  per second, although the app read the thermal state as nominal throughout.
- The prompt rate (about 112 tokens per second) is lower than the 150 estimated in the spec from Phase 1's short prompts, so a
  1,500-token page costs about 13 s before the first token, not 10.
- **17 of the 18 answers are the same text on the phone and on the Mac** for the same page and seed: for this adapter, the Mac
  runs of step 4 stand for the phone (the risk named in the spec). P7 measures time; the answers are not scored here.
