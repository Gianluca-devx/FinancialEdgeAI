# Spec: Phase 2b, LoRA with more varied wording

Status: **approved by the user on 2026-10-17** (written the same day; D28 revised after the user shared 17 annual reports). Nothing is built yet. The decisions below
are mine, each with the alternative; the user approved them with the spec.
Depends on `Specs/phase-2-lora.md` and its result (`Results/lora-v1-analysis.md`, tag `v2.2.0`).

**Goal:** find out whether training the adapter on **more varied wording** removes the missed values of
`lora-v1` (15 fields, 4 test statements) without bringing back the errors of the unmodified model, and measure
that on wording the adapter has not seen.

**Out of scope:**
- The core prompt, the schema, the parser, the core fields (they stay byte-identical, so every earlier report stays
  comparable).
- The visible "possible miss" check in the app: Phase 2c, below. It changes the app, not the model; mixing it
  into this experiment would make two changes at once.
- An adapter for the balance sheet call (Phase 2d).
- A different model, a Release build, energy. (Real reports are D28, a separate test that is never committed.)

## What Phase 2 found, and what the data says about why

`lora-v1` fixed all 55 baseline errors and made 15 new ones, all **missed values**: the model answers null where the
text states the value, always for wording that is in none of the 270 training statements. The training data
explains it (counts from `Dataset/train.labels.jsonl` and the statements):

| Observation in the 240 training statements | Count |
|---|---|
| "net income" | 167 |
| "net earnings", "net profit" (the label of statements 6 and 25 uses them) | 0 and 0 |
| "operating income" / "operating profit" | 99 / 0 |
| "revenue" / "net sales" | 162 / 0 |
| "year over year" / "year-over-year" | 47 / 0 |
| "cash generated from operations" | 0 |
| `operatingCashFlow`, `capex`, `interestExpense` stated (not null) | 29, 30, 23 of 240 (12%, 12%, 10%) |
| `previousYearRevenue` stated | 60 of 240 (25%) |

Two causes, both in the data and not in the hyperparameters:
1. **One phrase per field.** The generator's training pool has a single wording for net income (`net income`) and for
   operating income, two for revenue and EPS. The held-out wording (pool B) is exactly what the adapter misses.
   Note that the prompt itself says "net income, net profit or net earnings": the adapter ignored the prompt's own
   synonym, so it learned the phrase, not the meaning.
2. **A strong null prior.** For the rarer fields the answer is null in 88% to 90% of the training statements, so
   null is the safe guess when the wording is not familiar.

The validation split has the same wording as the train split, so its loss (0.001) could not show any of this.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D21 | **The 30 test statements stay frozen and stay the primary comparison.** Their unseen wording (pool B) must stay unseen: the new training wording is chosen to be **disjoint** from pool B (no shared key phrase, checked by the validator). `lora-v1`, `lora-v2` and the baseline are then compared on the same 30 statements, answer by answer. | Putting the pool B wording into training: the failing statements would be fixed by memorising them, and the old test would no longer measure generalisation. |
| D22 | **The new data goes to `Dataset/v2/`**; every file of `Dataset/` stays byte-identical (checked against `v2.2.0`). A second generator path with its own random streams (`Scripts/generate_dataset_v2.py`) writes it. | Editing `generate_dataset.py` in place: its random stream would change the frozen test statements. |
| D23 | **Training wording pool A2:** at least 4 wordings per core field (names of the metric, the previous-year forms, the growth forms), none shared with pool B, test 2 or the validation pool; plus sentence **structures** the generator does not have yet (a bullet list, "Label: value" lines, a short paragraph, the fields in another order). Every field is stated in **at least 25% of the training statements** (today 10% to 12% for three of them). The null scenarios (prior year without growth, none of the fields, distractors) stay, so the model keeps seeing nulls where the text states nothing. | Only adding statements with the same pool: the same one phrase, more of it. A higher share of stated fields without keeping the null scenarios: it would bring back the hallucinations of the baseline. |
| D24 | **A validation split with held-out wording (pool V),** disjoint from train, pool B and test 2. Its loss rises when the adapter overfits the training wording, so the checkpoint choice finally means something. | The old validation split: it cannot show the problem (loss 0.001 from iteration 50). |
| D25 | **A second test set, test 2:** 30 new statements, with wording (pool C) and structures in none of train, validation or the old test, 10 of them hand-written in the style of a short report (several sentences, tables as text, a note in another unit). Frozen and hashed **before training**, never used to choose a checkpoint. The unmodified model and `lora-v1` are measured on it first, as references. | Using only the old test: 12 statements with unseen wording make one statement 8 points of pool B. |
| D26 | **Size and training:** 480 training statements (456 generated and 24 hand-written: the 16 already in train plus 8 new ones), 48 validation, same method and hyperparameters as `lora-v1` (rank 8, scale 20, 16 layers, learning rate 1e-4, batch 4, loss on the answer only, seed 1). Up to 600 iterations, validation and checkpoint every 50. **Stop rule written now:** stop when the validation loss on pool V has not improved for 3 evaluations in a row, or at 600. Use the checkpoint with the lowest validation loss. | A hand stop, as in v1 (a judgement made on the training log): the rule removes it. More layers or a higher rank: nothing says the capacity is the problem. |
| D27 | **First, a free experiment:** the checkpoints of `lora-v1` at iterations 50 and 100 (they exist on the Mac) are evaluated on the old test, with no change to the dataset or the app. If an earlier checkpoint already misses fewer values, the overfitting is partly a matter of training length. | Skipping it: it is two runs of an hour and tells us how much of the problem is training length and how much is data. |
| D28 | **A real-style test from the user's 17 annual reports** (`~/Downloads/Reports`, SEC Form 10-K filings, English, with a text layer). One narrative passage per filing (2 to 6 sentences, copied word for word, never edited), chosen by a **rule written before I read them** (the first narrative paragraph of the results discussion that states at least one core field, plus passages that state few or none, so the nulls are tested too; passages whose units appear only in a table header are skipped and listed). Labels come from the passage text only, by the dataset's rules, never from what I know of the companies; the user spot-checks 5. **Nothing from the filings is committed:** the passages live in a git-ignored folder, are copied to the phone's `Documents` like an adapter (the app loads a set from there, not from the bundle), and only counts (no passage text, no failing-statement listing) go into committed results. Measured for the unmodified model, `lora-v1` and `lora-v2`; never used for training or for choosing a checkpoint. | Committing the excerpts: ruled out by the user. Writing realistic statements myself: they are not real. |

## Success criteria (fixed before training)

Measured on the **old test** (30 statements x 3 runs, the same prompt, seeds, settings and phone as every earlier run):

1. **Fully correct answers: at least 84 / 90 (93.3%)**, against 78 for `lora-v1` and 57 for the baseline (at most 2 failing statements).
2. **Missed values: at most 5 fields**, against 15 (the criterion that `lora-v1` failed).
3. **The old errors do not return:** hallucinated + unreadable + unit + sign + wrong-number fields at most 6 together, against 0 for `lora-v1` and 55 for the baseline. 90 / 90 decodable.
4. **Unseen wording (pool B, 36 answers): at least 30 fully correct (83.3%)**, against 27 for `lora-v1` and 21 for the baseline; wording seen in training (pool A, 54 answers) not worse than 49 (90.7%), against 51.
5. **Practical:** median time per statement at most 12 s, peak memory at most 3.0 GiB, thermal no worse than "serious" (the adapter has the same size, so this is a check, not a hope).

Measured on **test 2** (new wording and structures, three runs): `lora-v2` fully correct at least **9 answers more than `lora-v1`** and **no fewer than the unmodified model**, with fewer wrong fields than `lora-v1`. Test 2 is the honest generalisation check: if criteria 1 to 5 are met on the old test and not on test 2, the result is "the adapter learned the new wording, not the task", and it is reported as that.

A mixed or negative result is a valid result.

## Design

- **Data (`Scripts/generate_dataset_v2.py`, `Dataset/v2/`):** `train.jsonl` (480), `valid.jsonl` (48, pool V),
  `test2.jsonl` (30, pool C), their sidecars (`*.labels.jsonl`, all 18 fields, true values written by the
  generator) and an index. Same chat format, same system and core user prompt. The extended chat files are not
  generated (out of scope). Every label is correct by construction (generated) or checked by hand (hand-written).
- **Validator (`Scripts/validate_dataset_v2.py`, called by `Scripts/validate_dataset.py`):** every `Dataset/` file byte-identical to `v2.2.0`; every
  label verbatim in its statement (as today); **no phrase of pool B, C or V in train**; no statement shared between
  splits (train, valid, test, test 2); no prompt example number in a statement; every core field stated in at least
  25% of the training statements and in at least 4 different wordings; a count table per field and per wording
  printed. The check is proven to fail when a pool B phrase is put into train.
- **App:** a launch argument `-evaluationSet test2` (default: the old test), a bundled copy of `test2.jsonl` and its
  labels with the usual drift check, a test-set name in the report (the hash is already recorded). The prompt, the
  parser and the evaluation judgements do not change. No change to the screens.
- **Training:** `Scripts/lora/lora-v2.yaml` (data `adapters/data-v2`), `prepare_data.py` takes the data folder and
  keeps its three checks (training text equals inference text, token counts equal the iPhone's, no test statement in
  the training data, now for both test sets). A run record `Scripts/lora/runs/lora-v2.md` with the stop rule applied
  as written. Weights never committed; `mlx_lm.lora --test` never used.
- **Scripts:** `summarize_results.py` and `compare_baselines.py` read the test-set name; the comparison table gains a
  column per run (baseline, `lora-v1`, `lora-v2`) for the same test.
- **Tests:** the new test set loads and its labels agree with the sidecar (oracle test, as for the old one); the
  parser reads every new label to its true value (the new forms: `EBIT`, bullet lists, "+14% y/y" if used);
  the adapter-name and test-set fields are in the report; all 218 earlier tests stay green.

## UI / UX

No screen changes in this phase. The Evaluate tab shows the test-set name next to the adapter name (one line, as the
adapter is shown today).

## Steps (each one commit, `feature/lora-v2`)

1. **GATE: approve this spec.**
2. `Scripts/lora/` and results: evaluate the `lora-v1` checkpoints 50 and 100 on the old test (D27). Two phone runs,
   about 70 minutes each. A short note `Results/lora-v1-checkpoints.md` (`eval`).
3. `Scripts/generate_dataset_v2.py`, `Dataset/v2/`, validator checks, tests of the generator (`data`). **GATE:** the
   validator is green and I show you the coverage and wording tables and 10 statements of each split before any
   training or test 2 run, because the data decides the experiment.
4. App: `-evaluationSet`, the bundled test 2, drift check, tests, scripts (`feat`, `test`).
5. References on test 2 and on the real-style set: the unmodified model and `lora-v1` (four phone runs). The real-style
   set is built first (git-ignored, selection rule applied, 5 labels spot-checked by the user, app loads it from
   `Documents`). Both sets are frozen (hashes in the run record) before step 6 starts (`eval`, `feat`).
6. Train `lora-v2` on the Mac with the stop rule (`model`).
7. Evaluate `lora-v2` on the old test and on test 2 (two phone runs) (`eval`).
8. Analysis against every criterion, comparison of the three runs on both sets, README, PR to `main`, tag after the
   merge (`docs`).

## Cost

| | Time |
|---|---|
| Steps 2 and 5 (six phone runs; the real-style passages are longer, so their runs are slower) | about 6.5 h of phone time, no Mac time |
| Step 6 (training, up to 600 iterations) | about 1.5 to 2.5 h on the Mac (v1 took about 70 minutes for 170 iterations while the Mac was under load) |
| Step 7 (three phone runs) | about 3.5 h |
| My work | the generator, validator, app change and analysis: the larger part of the effort |

The phone must be unlocked at each launch (the run scripts retry every 10 s); the Mac should have little else
running during training (Zoom slowed v1).

## Acceptance

1. The dataset v2 is generated and validated: every check above green; `Dataset/` byte-identical to `v2.2.0`.
2. The validator is proven to fail on a pool B phrase in train.
3. Test 2 is frozen and hashed before training; the references are measured.
4. Training stopped by the stop rule as written; the chosen checkpoint is named; the run record is committed.
5. Both evaluations on the iPhone: 90 answers each, every one decodable, the report records the adapter and the set.
6. Results under new names; a written analysis with **every criterion above checked, met or not**; the three runs
   compared field by field on the old test and on test 2; the earlier result files unchanged.
7. A conclusion: did wording variety fix the misses, and what does test 2 say about generalisation.

## Risks

- **Disjoint wording is lexical, not semantic.** "Cash flow from operating activities" may be close enough to "cash
  generated from operations" to help, or too far; that is the point of the experiment, and test 2 tells.
- **I write the training wording, test 2 and the hand-written statements.** The same author and the same generator
  family: the result is "better on wording I did not put in training", not "good on real text" (D28).
- **More stated fields may bring back hallucinations,** because the model sees fewer nulls. Criterion 3 checks it; the
  null scenarios stay in the mix.
- **The stop rule may stop early or run to 600** on the new validation split; either is reported as it happens.
- **30 statements per test, one seed, one run of training.** One statement is 3.3 points; a second seed is the next
  step if the result is close to a criterion.
- **Time on the phone:** about 10 hours in total, thermal pauses included.
- **The real-style passages are longer and denser than any statement so far** (many figures, company-specific names such as "net sales" or "net earnings"). A bad score there is information, not a failure of the phase; it has no criterion on purpose, because its first measurement is the unmodified model's.

## Phase 2c (a sketch, its own spec later): make a missed value visible

A pure Swift check "amounts in the text that no field used" (for example "1 amount in the text is not in any
field: $11.6 billion"), shown as a warning row. It is code, so it is measured without the phone: on every statement
of the dataset with the true labels as the answer (false alarms: the distractor sentences) and with one label
blanked (how many misses it flags). It touches neither the prompt, the dataset nor the evaluation code.

## D28: the selection rule of the real-style set (written and committed before any passage was chosen or read)

The 17 annual reports (SEC Form 10-K, English, with a text layer) are in `~/Downloads/Reports`. Nothing from them is
committed (`/RealSet/` is git-ignored); this rule and `Scripts/real_set.py` are.

1. **Text:** `pdftotext` (reading order, no page breaks), lines joined into paragraphs at blank lines.
2. **Region:** from the end of "Item 7. Management's Discussion and Analysis" (its second occurrence, the first is the
   table of contents) to "Item 7A"; the whole document if it is not found.
   *Amendment, 2026-10-17, before any passage was read:* the first run of the script found no candidate for 5 of the 17
   filings, because only one "Item 7" heading was found (the table of contents entry) and the region was tiny. From
   counts alone, and not from any text: if the region has no candidate of a kind, the whole document is used for that kind.
3. **Candidate paragraph with fields:** 40 to 160 words; at least 2 sentences; at least 80% of its characters are letters
   or spaces (prose, not a table); at least one amount with its unit word in the text (`$` + number +
   million/billion/thousand); at least one core keyword (revenue, net sales, net income, net earnings, operating income,
   income from operations, operating profit, earnings per share, cash provided by operating, capital expenditures,
   interest expense).
4. **Choice:** one candidate per filing, drawn uniformly at random with a seeded generator (seed 20261017) from the
   candidates in order of position. Never chosen by reading.
5. **Passages with no field:** for 5 of the 17 filings (drawn with the same generator), one more paragraph of the same
   length and prose test that contains a digit and **none** of the core keywords, drawn uniformly. They test the nulls.
6. **Length:** a paragraph with more than 6 sentences is cut after the sixth, at a sentence boundary; the words are never
   edited.
7. **Labels:** by me, from the passage text only, by the dataset's rules (the string as printed; a decrease gets a leading
   minus; null if the passage does not state the field; never calculated; never from what I know of the company).
   The user spot-checks 5. Until then the set's results are marked **provisional**. (Done on 18 October: all 5 confirmed, two of them after an explanation; see `Results/phase-2b-references.md`.)
8. **Not changed afterwards:** once the set is frozen (hash recorded), no label or passage is edited to make a result
   look better. A label error found later is fixed, announced, and every run on the set is re-judged (the judging is
   pure, the answers are in the report).
9. **What is committed:** counts, hashes and rates only; no passage, no failing-statement listing, no per-statement
   table of the real-style set.

**Amendment 2, 2026-10-17, after reading the 21 passages of the first draw and before running any model on them.**
Every one of the 21 passages (16 with keywords, 5 without) turned out to hold no company-level current-period figure
as the dataset defines it: they explain changes (segment growth, cost lines, deferred revenue, dividends, amounts that
are only a difference). Labelled strictly from the text, the first draw has one stated field (an ambiguous one) in 21
passages, so it measures hallucination on real text and nothing about extraction. The first draw is **kept as it is**
and becomes the set **`real1`** (a real-text test of not inventing values). A second set, **`real2`**, uses rule 2: the
same seed, one paragraph per filing, but the paragraph must contain a headline statement, a sentence of the form
`<metric> ... was/were/of/to $<amount>` for one of revenue, net sales, net income, net earnings, operating income, income
from operations, operating profit, diluted earnings per share, cash provided by operating activities, capital expenditures
or interest expense, where the metric is not preceded by "cost of", "deferred", "unearned", "segment", "intersegment" or
"other". The labels follow rule 7 above (strictly from the text, as printed; a segment figure that the text does not call a
segment is labelled as printed, and flagged as ambiguous for the spot-check). Both sets are measured for the same models;
rule 2 was written knowing what rule 1 returned, which is disclosed here: it is a repair of the test's validity, made
before any model saw either set, and it cannot favour a model.
