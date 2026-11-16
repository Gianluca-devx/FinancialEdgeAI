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
