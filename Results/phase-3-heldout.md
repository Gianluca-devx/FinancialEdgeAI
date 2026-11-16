# Phase 3, step 3: the code and prompts frozen, then the held-out texts and their labels (counts only)

Spec: `Specs/phase-3-report-sections.md` (S1, S6, S7, Amendment 1). The held-out texts, labels and answers are private
(`RealSet/sections/`, git-ignored); this file holds counts and hashes only, and names no company.

## The freeze (written and committed before any held-out Item 1 page is read)

Frozen on 2026-11-16 at **commit ec6b9e3** (Amendment 1). Until the held-out run (step 4) is done, these files do not change:

| File | sha256 (first 12) | Last changed |
|---|---|---|
| `Scripts/sections.py` (the rule of S1, the checker of S8) | `b7c50f95b544` | c8ee5ff |
| `Scripts/lora/section_generate.py` (the windows and the runs) | `7fa0ca017ff9` | 981cb11 |
| `Prompts/overview.instructions.txt` | `6c05893a92a2` | 29abfc3 (v8) |
| `Prompts/overview.template.txt` | `56b72c100e0a` | 5e688f3 |
| `Prompts/business.instructions.txt` | `8ee8c89747bf` | 29abfc3 (v8, unchanged since v4) |
| `Prompts/business.template.txt` | `177e59e60af9` | 5e688f3 |
| `Scripts/tests/test_sections.py` | `dbb37e3c610f` | c8ee5ff |
| `Dataset/v2/test2.jsonl` (the "not stated" set, Amendment 1) | `cf47613d60f2` | c289b23 (Phase 2b) |

- **The prompts' hash,** as every answer line records it: `eb246e80bd26` (v8, chosen by the selection rule of the development
  record).
- **The model:** `mlx-community/Qwen3-4B-4bit`, thinking off, temperature 0.2, at most 256 tokens, seeds 1 to 3; condition L with
  `lora-v3` seed 1, weights sha256 starting `26a0d90702e19f00`, checked by the script before any call.
- **The inputs:** the PDFKit page texts of the 22 held-out reports, extracted in Phases 2g (12) and 2h (10) and unchanged since:
  22 files, sha256 of their bytes in name order (the Phase 2g folder, then the Phase 2h one) `a860faafe82b`.
- **What has been seen of them:** their statement pages (Phases 2g and 2h) and the keyword ranking over all pages; **no Item 1
  page.** Of test 2: what Amendment 1 lists.

After this commit, in order: the rule of S1 on the 22 reports (one run over both folders), the windows of 2,500 tokens, the
checklists of S7 by the labelling rules of the development record, each stated fact checked against its own text, the labels
frozen by hash, the spot-check report chosen by the pilot's seed; then the user's spot-check, before any answer is generated on a
held-out text or on test 2.

## The held-out texts and their labels (2026-11-16, after the freeze above)

- **The rule of S1** (`sections.py locate`, one run over both folders): **21 of 22 reports located, 1 missed.** Of the 21, 18 texts
  start at the Item 1 heading of the report's body. In 2 the rule took the table of contents, whose "Item" lines have no period
  after the number, so fewer than 4 headings were counted; their texts run on into Item 1 within the window (about 250 and 1,200
  words of it). In 1 it took a cross-reference index near the end of the report, followed by the signature page: that text holds
  no business description. The missed report's only "Item 1 ... Business" line is in a cross-reference index with 13 headings.
  The rule is not changed after the freeze; these 4 cases are reported in step 5.
- **The windows** (`section_generate.py window`): 21 texts; 20 cut at 2,500 tokens (2,496 to 2,500), 1 shorter (867 tokens, 2 pages,
  where the report ends); 516 to 2,019 words, median 1,816.
- **Test 2** (`sections.py testsplit --source Dataset/v2/test2.jsonl`): 30 statements, ids `test2-01` to `test2-30`.
- **The labels (S7):** 21 reports, 126 facts, **90 stated**: overview 34 of 63 (what the company does 20, a headquarters 2, a size
  12), business 56 of 63 (segments or business lines 18, products 18, customers 20). sha256 `39bcb5f7b718`
  (`RealSet/sections/heldout/labels.json`). The text with no business description has all six facts null.
- **Each stated fact was checked against its own text** by the coverage rule: 90 of 90 found; a made-up term put in one group
  fails, as it must.
- **How the labelling rules of the development record were applied** where they leave a choice: a headquarters only where the text
  names a city as the headquarters or the principal executive offices (2), not where it names a city where the company was founded
  or began, nor a country; the size is the first count in the text, with its rounded forms accepted where it is large, and
  users of products are not customers; where the text names many products, one group per business line in the text's order (8
  reports); where no segment is named, the text's own statement of them ("one operating segment", a table by segment, the only
  reportable segment) or its business lines (4 reports); a text that names no product or category, only "merchandise" or
  "products", has products null (2).
- **The spot-check:** the report chosen by the pilot's seed (20261029) among the 21, in the order of the texts file (position 18).
  The file `RealSet/sections/heldout/spotcheck.md` holds its six facts with the sentences they come from, and my judgement calls
  on the other 20 reports.

**GATE: the user's spot-check.** No answer has been generated on a held-out text or on test 2.
