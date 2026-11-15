# Spec: Phase 3, the overview and business sections

Status: **APPROVED by the user on 2026-11-15** (written the same day at the user's request, after Phase 2h's "stop this path").
The decisions are mine, each with the alternative.
Depends on `v2.8.0`. Follows `Spec-Driven Development.md`, Phase 3: two free-text sections with their own prompts; the metrics
prompt, schema, parser, dataset and evaluation stay unchanged.

**Goal:** the app shows a short **company overview** and the **main business** next to the metrics, written on the phone by the same
model from the report's own text. Before building, measure on real annual reports whether these texts **say only what the report
says** and **cover its key facts**, and how long they take on the iPhone.

**Out of scope:** PDF import in the app (a backlog spec; the statement path behind it stopped in Phase 2h), the metrics prompt,
schema, parser, dataset and adapter, training an adapter for the sections, reports that are not US annual reports, the balance
sheet call, the table reader, a judge model.

## What we know before starting

- Every report of the 27 (the pilot's 5, Phase 2g's 12, Phase 2h's 10) is a US annual report (Form 10-K). Its **Item 1, "Business"**
  starts with the company's description: what it does, its segments, products, customers. Item 1 is often 10 to 30 pages, too long
  for one prompt on the phone.
- On the 5 development reports (checked while drafting, counts only), a heading rule finds **exactly one** "Item 1. Business" page
  that is not the table of contents; that page and the next two hold 1,250 to 2,100 words.
- Phone costs from Phase 2f (iPhone 16, Debug): about 112 prompt tokens per second, 13.9 generated tokens per second, 2.89 GiB at
  about 1,800 prompt tokens. A section from 2,500 tokens of text is then about 25 s of reading and 7 to 11 s of writing.
- The app loads `lora-v3` for the metrics. The adapter was trained only on JSON extraction; its effect on free text is unknown.
  `mlx-swift-lm` can take an adapter off a loaded model and put it back (`unload(adapter:)`, `load(adapter:)`).
- Nothing of the 22 reports' Item 1 pages has been read. Their statement pages were, in Phases 2g and 2h.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| S1 | **The text measured:** the start of Item 1. The first page with a line "Item 1. Business" (also with a dash or colon) that holds fewer than 4 "Item" headings (so not the table of contents); from it, that page's text and the next pages' up to **2,500 tokens** (Qwen tokenizer), PDFKit text. A report where no page qualifies counts as a miss of the rule, reported, and is left out of the scores. | Keyword search, as for the statements: not needed when a heading exists. All of Item 1: too long for the phone. |
| S2 | **The text in the app:** the pasted text, the **same text for the three sections**. Pasted statements give metrics and "not stated" sections; a pasted business description gives sections and null metrics. | PDF import now: it doubles the scope and brings in the iOS PDFKit question; it is a backlog spec that can feed all three sections later. |
| S3 | **Two calls, one per section,** each a new session with its own prompt files (instructions + template), like the metrics call. | One call for both: saves one reading of the text (about 25 s on the phone), but a failure loses both sections and the answer must be split. A session that reuses the text's cache for the second question: kept for later, if time fails. |
| S4 | **The answers:** plain prose in English. **Overview**, at most 60 words: what the company does, where it is based, how large it is. **Business**, at most 100 words: its segments or business lines as the report names them, its main products or services, its main customers or markets. Only what the text states, no outside knowledge. If the text does not describe the company's business, exactly **"Not stated in the text."** | Bullet lists: easier to check, but the sections are meant to read as text. JSON: the metrics' path, but free text inside JSON brings escaping errors. |
| S5 | **The model:** Qwen3-4B 4-bit, thinking off, temperature 0.2, `maxTokens` 256, seeds 1 to 3, on the Mac (the Phase 2f path, Python `mlx_lm`; 17 of 18 answers were identical on the phone). Condition **B** (the base model) decides the rule. Condition **L** (`lora-v3`, seed 1, checked by hash) is run too: if it is not worse than B beyond the seed spread, the app keeps the adapter on for all calls; otherwise the app takes it off for the two sections, and the switch time is measured. | B only: the app runs with `lora-v3` in practice, so the question must be answered. |
| S6 | **The sets:** development = the pilot's 5 reports (the prompts and the rule of S1 are written on them, and may change only there); held-out = the **22 others**, whose Item 1 pages have never been read. Plus the 30 statements of the frozen test split (synthetic, committed) for "not stated". | New reports from the user: not needed, as these pages were never read; other pages of the same reports were. |
| S7 | **The labels:** for each held-out report, a checklist of **6 facts** from the exact text the model receives (S1): overview: what the company does, its headquarters, one size fact (employees, stores, countries or customers); business: the segments or business lines as named, the main products or services, the main customers or markets. Each fact is a short phrase plus **key terms** (with the synonyms allowed). A fact the text does not state is null and not counted. Written after the freeze and before any run, frozen by hash; the user spot-checks one report chosen by the pilot's seed. | A judgement of each answer without a checklist: written after seeing the answers, it would follow them. |
| S8 | **The measures,** by code, with a hand check of the flags: **format** (not empty, prose: no JSON, heading or list, within the word limit, not cut by `maxTokens`); **invented** (every number and every name in the answer, a name being a capitalised word not at a sentence start and outside a fixed stop list, must be found in the text; each flag is confirmed or rejected by hand against the text, as "$1.2 billion" can be printed "1,200 million"; an answer with one confirmed item counts as an answer **with an invented item**); **coverage** (a stated fact is covered when all its key terms, or their synonyms, are in the answer); **not stated** (the exact phrase on the test split's statements). | A larger model as judge: it would need its own validation, and the report text stays on the Mac. |

## Decision rule (fixed before the held-out run)

Over the 22 held-out reports, condition B, the three seeds pooled:

1. **Build** (the next steps put the two sections into the app): answers with an invented item **at most 5%**; stated facts covered
   **at least 70%**; answers in format **at least 95%**; "not stated" on **at least 90%** of the test split's answers.
2. **Improve:** invented 5% to 15%, or coverage 50% to 70%, or format or "not stated" below their limits, with invented at most 15%
   and coverage at least 50%.
3. **Stop:** answers with an invented item above 15%, or coverage below 50%.
4. **Reported in every case:** development against held-out; B against L, with the seed spread; each section apart; each flag
   confirmed or rejected; the Mac time and prompt tokens; the reports the rule of S1 missed; a hand reading of the seed 1 answers
   for claims with no number or name that the text does not support (counted, not part of the rule).

## Design (built only on "build")

- **Prompts:** `Dataset/sections/` holds the instructions and the template of each section; bundled copies in `Resources/`, checked
  identical by a test. No report text, and no number of the metrics prompt's examples, in them.
- **Services:** `SectionPrompt` (renders a prompt), `SectionAnswer` (reads an answer: trimmed text, "not stated", the format checks
  of S8, pure); `LLMService` gets one call per section, on the base model or with the adapter as S5 decides.
- **State:** `SectionsPresenter` (pure, tested) gives each section its state: waiting, loading, text, not stated, failed (with the
  message), cut. One tap runs the metrics, then the overview, then the business; a failure stops only its own section.
- **UI / UX:** the Extract tab shows the overview, the business and the metrics in that order. Each section shows its own progress,
  its text, "Not stated in the text" in a quieter style, or its error with a retry, and never waits for the others to show what it
  has. The balance sheet keeps its button. Previews with made-up text (light, dark, a large text size).
- **Evaluation mode:** `-evaluationTier sections` runs the two sections on an external set (`Documents/EvalSets/<name>`) and writes a
  report with times, tokens, memory and thermal state, for the phone timing run.

## Tests

The locate rule, the checker and the generation script with a tamper test per measure (an invented number, an invented name, a
missing key term, a cut answer, a list instead of prose), in `Scripts/tests/`. In Swift: prompt rendering, the answer reading on
the same cases as the checker, and the presenter's states, on the simulator. The full suite must stay green and the metrics files
byte-identical to `v2.8.0`.

## Steps (branch `feature/report-sections`, each one commit)

1. **GATE: the user approves this spec.**
2. **Development** (`feat`, `test`, `eval`): the rule of S1, the two prompts, the checker, `Scripts/lora/section_generate.py`, their
   tests; runs B and L on the 5 development reports and on the test split; counts in `Results/phase-3-development.md`.
3. **Freeze, then the labels** (`data`): the commit and the hashes of the prompts, the rule, the checker and the script recorded
   **before** the rule runs on the 22 reports (their page texts exist from Phases 2g and 2h, but no Item 1 page was read); then the
   rule on the 22, the checklists, frozen by hash; the spot-check.
   **GATE: the user's spot-check.**
4. **The held-out run** (`eval`, counts only): B and L, three seeds, on the Mac; the flags checked by hand;
   `Results/phase-3-runs.md`.
5. **Analysis** against the rule, README (`docs`). **GATE: the user decides the app steps** (only on "build").
6. **The app** (`feat`, `test`): prompt files, services, presenter, views, evaluation mode; previews checked; full suite green.
7. **Phone timing run** (**GATE: the user approves the phone use**): the two sections on 5 held-out texts. Acceptance: both
   sections in **at most 90 s** per text (median), memory and thermal state reported; a miss is recorded, and the cache reuse of S3
   becomes the next step.
8. PR `dev` to `main` after the user's go.

## Cost

About 5 to 7 days of my work: development a day, 132 facts of labels a day or a day and a half, the runs and the hand check of the
flags half a day, the app one or two days, the analysis half a day. Mac: about two hours of generation. Phone: about 20 minutes
(step 7). No training.

## Acceptance

1. The prompts, the rule, the checker and the script are frozen by commit and hash before the held-out pages are read; the labels
   are frozen before the run; the decision rule is the one above, unchanged.
2. Each measure of the checker has a tamper test that makes it fail.
3. Counts by measure for the development and the held-out reports, B and L, each section apart; the flags' hand check reported.
4. No report text, page, label or answer, and no company name, in a committed file or commit message; counts only.
5. The metrics path is unchanged: its files byte-identical to `v2.8.0`, the full test suite green.
6. A written conclusion says which rule applies and why.
7. On "build": the three sections load and fail on their own, the previews are checked, and the phone timing is reported against
   90 s.

## Risks

- **The model knows these companies.** It may add true facts that the text does not state (a founding year, a chief executive).
  They count as invented: the app must show what the report says. The hand check notes them apart.
- **Key terms miss paraphrases,** so coverage may be undercounted; the seed 1 hand reading shows by how much.
- **The name flags are noisy** ("U.S." and "United States"); every flag is confirmed or rejected by hand.
- **Item 1 headings vary** ("Items 1 and 2", the word "Business" on its own line); a miss is counted, and the rule does not change
  after the freeze.
- **2,500 tokens may end before the segments are described;** the labels come from the same text, so such a fact is null, but the
  section is thinner.
- **The labeller is the developer;** the freeze order and the spot-check limit it.
- **Memory on the phone** with about 2,800 prompt tokens is estimated at about 3 GiB; measured in step 7.
