# Spec: Phase 2d, real-style distractors in the training data (lora-v3)

Status: **approved by the user on 2026-10-19** (written the same day). Nothing was built when it was approved. The decisions below are mine, each
with the alternative; the user approved them with the spec. Depends on `Specs/phase-2b-lora-wording.md` and its results
(`Results/lora-v2-analysis.md`, `Results/phase-2b-references.md`), and on `Specs/phase-2c-app-safeguards.md` (tag `v2.4.0`).

**Goal:** find out whether training on synthetic statements that contain the **kinds of distractors found in real annual-report
prose** (a segment's figure, a change in amount, a cost line, a deferred item, an adjusted or hypothetical figure) stops the adapter from
inventing values on real text, **without losing the gains on short synthetic statements** and without the garbled-key failure; and size
how much of any difference is just the draw of one training run.

**Out of scope:** any change to the prompt, the schema, the parser, the app, or the way an evaluation judges an answer; **real text in the
training data** (it stays out: see D34); the balance sheet call; the overview and business sections; PDF input.

## What the data says about the gap

`lora-v2` fixed the synthetic misses and is no better than the unmodified model on real passages. Over the two real sets together
(93 answers, counts only):

| | Fully correct | Invented values | Undecodable answers |
|---|---|---|---|
| Unmodified model | 60 | 63 | 0 |
| `lora-v1` | 62 | 40 | 6 |
| `lora-v2` | 47 | 62 | 6 |

The real passages hold what the synthetic statements do not: **a named part's figure that is not the company's** (a segment, a product, a
region), **a change in amount** ("increased $2.7 billion, or 27%": a difference is not a previous value, and a part's growth is not the
company's), **cost lines and margins**, **deferred revenue and remaining obligations**, **adjusted (non-GAAP) and constant-currency
figures**, **capital returned to shareholders**, **footnote numbers and rates inside names** ("7.5% Notes"), and they are **longer**: median
74 to 101 words against 37 in the training statements. The training statements have a few distractors (total assets, free cash flow, guidance,
margins), none of these.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D34 | **No real text in the training data**, and none in the repository. The new statements are **synthetic**, with fictional companies and generated numbers, modelled on the **kinds** of sentences in the real passages (listed in D35), never copying a sentence. A local check (run only where `RealSet/` exists, counts only) fails if any run of **6 consecutive words** of a real passage is in a training statement. | Training on some filings and testing on the others: 17 filings and 31 passages are too few to split, and weights trained on the user's reports would be derived from them. |
| D35 | **A catalogue of nine real-style distractor kinds**, each a template family with several wordings: (1) a change in amount and percent ("increased $X, or Y%") for a part or for the company; (2) a segment, product or region figure and growth ("Services revenue", "the Cloud segment"); (3) cost lines, expenses and margins; (4) deferred revenue, contract liabilities, remaining obligations; (5) adjusted, non-GAAP, "excluding" and constant-currency ("would have been") figures; (6) dividends, repurchases and other capital returns; (7) a figure inside a sentence that also states a company field ("operating activities provided $X, of which net income was $Y"): **positive** examples among distractors; (8) footnotes, rates and years inside names, intercompany items; (9) longer paragraphs (60 to 160 words) that chain several of these. **The rule of the labels:** a figure of a **named part**, a **change**, an **adjusted or hypothetical** figure, a **cost, deferred or capital-return** item is **null**; a figure the sentence calls the company's own (total revenue, net income, operating cash flow, capital expenditures...) is labelled as printed. Only unambiguous sentences are used. | Writing statements by hand: too few, and too close to what I read. Using the real sentences: D34. |
| D36 | **`Dataset/v3/`**, written by `Scripts/generate_dataset_v3.py` (own random streams, never touching `Dataset/` or `Dataset/v2/`): **train = the 480 statements of v2 + 240 new real-style statements** (about 70% with few or no stated fields, 30% positive as in kind 7), **valid = the 48 of v2 + 24 new** (templates and wording held out of train), and a new synthetic test, **test 3** (30 real-style statements, templates held out of train and valid). Every core field stays stated in at least 25% of the training statements (checked), so the null prior does not grow back to the Phase 2 level. | Replacing v2 train: the Phase 2b gains must not be lost, and a mix keeps them comparable. A bigger share of null statements: it brings back the missed values of `lora-v1`. |
| D37 | **A third real set, `real3`, drawn blind.** Fresh passages from the same 17 reports by the **same committed rule** (`Scripts/real_set.py`, new seed), drawn and frozen (hash of the passages) **after `Dataset/v3` is frozen and committed**; I read and label them **after** that, so nothing I read can have shaped the training data. `real1` and `real2` were read while the catalogue was written: they are no longer blind, and are reported as such. The labels follow the strict rule of Phase 2b; the user is asked to confirm the doubtful ones. | Reusing `real1` and `real2` as the test: I read them to design the catalogue. |
| D38 | **Training:** the recipe of `lora-v2` (rank 8, scale 20, 16 layers, learning rate 1e-4, batch 4, loss on the answer only) on `Dataset/v3`, up to 900 iterations (5 epochs of 720), the stop rule as a program (`stop_rule.py`) with the held-out validation, committed before the run. **Two seeds for `lora-v3` (1 and 2) and a second seed for `lora-v2`** (the existing run is seed 1): the spread between the two seeds of the same recipe is the noise. | One run per recipe: `lora-v1`'s checkpoints varied from 42 to 78 correct answers, so a single run cannot tell a recipe from a draw. |
| D39 | **A rule for reading the result:** a difference between two recipes counts only if it is **larger than the spread between the two seeds of the same recipe** on that measure; otherwise it is reported as "not distinguishable". The criteria below are for `lora-v3` seed 1; the seeds decide what they mean. | Declaring a win on one run. |
| D40 | **References before training:** the unmodified model and `lora-v2` on `test3` and on `real3`, so that the criteria that depend on them are fixed from numbers that do not depend on `lora-v3`. | Setting the thresholds after seeing `lora-v3`. |

## Success criteria (fixed before training; `lora-v3` seed 1, three runs of 30 statements; the real sets in answers)

1. **No loss on the old test:** at least **82 / 90** fully correct (`lora-v2` 85), at most **5** missed values (0), **90 / 90** decodable.
2. **No loss on test 2:** at least **72 / 90** (`lora-v2` 77), at most **10** missed values (6), **90 / 90** decodable.
3. **Test 3 (synthetic real-style):** fully correct at least **9 answers more than `lora-v2`** on it, and **at most half** of `lora-v2`'s invented values.
4. **Real text, `real1` and `real2` together (93 answers; not blind):** fully correct at least **62** (the best of the references, `lora-v1`) and invented values at most **40** (the lowest reference, `lora-v1`).
5. **Real text, `real3` (blind):** fully correct **no fewer than the unmodified model's**, and invented values **at most 70% of `lora-v2`'s**.
6. **No garbled key and no broken answer:** **0 undecodable** answers on every set, real ones included (a garbled key repaired by the app still counts as an undecodable answer here: the measure is the model's own output).
7. **Practical:** peak memory at most 3.0 GiB, thermal state no worse than "serious", median time per statement at most **12.5 s** (the 12 s of Phase 2b was missed by 6 ms; the margin is now explicit and the reason is disclosed).
8. **The seeds:** the second seed of `lora-v3` and of `lora-v2` are evaluated on the old test, test 3, `real1`, `real2` and `real3`; each conclusion is stated against the spread (D39).

A mixed or negative result is a valid result and is reported as it is. The success of criteria 4 and 5 is the point; 1 and 2 guard what was won.

## Design

- **Data (`Scripts/generate_dataset_v3.py`, `Dataset/v3/`):** the nine template families with fictional companies, generated numbers, several wordings each, chained
  into paragraphs of 40 to 160 words; labels written by the generator (the sidecar, as before). Wording and templates of train, valid and test 3 are disjoint.
- **Validator (`validate_dataset_v3.py`, called by `validate_dataset.py`):** `Dataset/` and `Dataset/v2/` byte-identical to `v2.4.0`; every label grounded;
  no statement shared between splits; the held-out templates and wording of valid and test 3 are not in train; every core field in at least 25% of train;
  the share of statements with no stated field reported; **the 6-word check against the private real passages** (counts only, skipped where `RealSet/` is absent,
  and proven to fail by a tamper test that puts a 6-word run of a made-up passage into a training statement).
- **App:** a launch argument already chooses the set; `test3` is bundled like `test2` (a symlinked pure loader, a drift check). Nothing else changes, and no evaluation code.
- **Training:** `Scripts/lora/lora-v3.yaml` (data `adapters/data-v3`, seed 1; seed 2 by a flag), `prepare_data.py` reads `Dataset/v3` and checks both test sets plus test 3, the run
  record `Scripts/lora/runs/lora-v3.md`.
- **Measurement:** the existing scripts and `report_counts.py` (counts only) for the real sets; `compare_baselines.py` for the synthetic ones.

## UI / UX

No screen changes. The Evaluate tab shows the set name as it does today.

## Steps (each one commit, branch `feature/lora-v3`)

1. **GATE: approve this spec.**
2. `Scripts/generate_dataset_v3.py`, `Dataset/v3/`, the validator and its tamper tests, tests of the oracle kind (the parser reads every label) (`data`, `test`).
   **GATE:** I show the coverage table and ten statements of each new kind before anything else, because the data decides the experiment.
3. `test3` in the app (bundle, drift check), then the references on `test3`: the unmodified model and `lora-v2` (two phone runs) (`feat`, `eval`).
4. **Freeze `Dataset/v3`** (hash in the run record), then draw **`real3`** blind by the committed rule, freeze its passages, then read and label it; the user confirms the
   doubtful labels; the references on `real3` (two phone runs) (`data`, `eval`).
5. Train `lora-v3` seed 1 and seed 2, and `lora-v2` seed 2, on the Mac with the stop rule (`model`). The Mac works while the phone runs the references.
6. Evaluate `lora-v3` seed 1 on all six sets (old test, test 2, test 3, `real1`, `real2`, `real3`), and the two seed-2 adapters on five (all but test 2) (`eval`).
7. Analysis against every criterion and against the spread, comparisons, README, PR to `main`, tag after the merge (proposed `v2.5.0`) (`docs`).

## Cost

| | Time |
|---|---|
| References (4 phone runs: test 3 and `real3`, two models) | about 3 hours of phone time |
| `lora-v3` seed 1 on six sets | about 4.5 hours of phone time |
| Seed 2 of `lora-v3` and of `lora-v2`, each on five sets (all but test 2) | about 7 hours of phone time |
| Training: three runs of up to 900 iterations (`lora-v2` took 2 hours for 350) | about 6 to 12 hours on the Mac, in parallel with the phone |
| My work | the generator, the validator, the labelling of `real3`, the analysis |

About **15 hours of phone time** over two to three days, automated (a script retries the launch until the phone is unlocked). The seed runs are the part to cut if the time is
too much: without them the criteria still run, but D39 cannot be applied and the result is one draw.

## Acceptance

1. `Dataset/v3` is generated and validated (every check green, the real-text check run where possible); `Dataset/` and `Dataset/v2/` unchanged.
2. `real3` is drawn after the data is frozen, by the committed rule, and its labels confirmed.
3. The references exist before training; the stop rule is applied by the program; the chosen checkpoints are named and recorded.
4. Every evaluation has 90 or 63 or 30 answers, all decodable or counted as failures, with the adapter recorded in the report.
5. A written analysis states every criterion as met or not, applies the seed spread, and keeps the real sets as counts only; earlier result files are unchanged.
6. A conclusion: do real-style distractors in the training data reduce invented values on real text, and by more than the noise of a training run.

## Risks

- **The null prior grows.** 70% of the new statements have few or no stated fields: the adapter may fall back to the missed values of `lora-v1`. Criteria 1 and 2 check it
  and the positive share (kind 7) and the 25% floor are the guard.
- **The catalogue comes from what I read.** `real1` and `real2` are not blind; only `real3` is. A failure on `real3` with a success on `real1` and `real2` would mean the
  templates are fitted to what I read.
- **Real text is richer than any templates.** Nine kinds cover what two small sets showed; real reports have more. The result is "better on these kinds", not "good on annual reports".
- **Labels of real passages are judgement calls** (the doubtful ones are confirmed by the user, as in Phase 2b); `real3` has few stated fields, so its numbers are mostly about invented values.
- **Longer statements cost time:** about 2 to 3 times the tokens of a training statement; training and the evaluation of the real sets take longer.
- **One phone, one build, Debug.** As before.

## Amendment 1, 2026-10-19, before anything was built

D36 said "about 70% with few or no stated fields, 30% positive" **and** "every core field stays stated in at least 25% of the training
statements". The two cannot both hold. Counted on `Dataset/v2/train` (480 statements), adding 240 statements with no stated field would drop the
share of eight fields from 26% to 31% down to **18% to 21%** (previous-year fields, growths, operating cash flow, capital expenditures, interest, EPS),
below the floor that fixed the missed values of `lora-v1`. The floor is the guard that matters, so the mix follows it: of the 240 new
training statements **about a quarter (60) are null-only paragraphs of distractors, about 65% (156) are paragraphs that state fields among
two to four inserted distractor sentences, and 10% (24) are positive sentences of the kind in D35 (7)**; the validation and test 3 splits have the
same proportions. The floor of 25% per core field over the whole of train (720) stays a hard check of the validator.


## Amendment 2, 2026-10-19, before `real3` was drawn (Step 4)

Written and committed **before** the draw, after `Dataset/v3` was committed (0b40ca6) and test 3 was bundled in the app (6ddc8a2). Nothing of `real3` has been
drawn, read or counted when this is written.

**1. The freeze.** `Dataset/v3` has not changed since 0b40ca6. SHA-256 of every file, and of the seven files read one after the other in the order below:

| File | SHA-256 |
|---|---|
| `train.jsonl` | `0218c6632f8ded1d3c88f63cc6c78a1bc0e2da75a5a155c67e8c7773ed21edff` |
| `train.labels.jsonl` | `8a87d19a525e2574a16514316b8c82561ba5f2f629434498ece16600fe3486bd` |
| `valid.jsonl` | `3f303a2325ebc48f56d3edda73fb86c7acd7e012939e0484ac11d1adaf98a2d2` |
| `valid.labels.jsonl` | `f14d4d2f1b7f46309f053d28f528b9a1489e41d965ae9ae81ebd3c0409b1fa21` |
| `test3.jsonl` | `d2061b25fca4524e33a38fd86e5e2cdaa26c939dfcd4ecdd5838e54ae29428db` |
| `test3.labels.jsonl` | `5c131b3b3dffc2bca794fac5894ddf89b40ae00ed6e936c62bc9a613647e474a` |
| `index.csv` | `d21e2317c767075411e387d56ab0ed76c10203ad059392c20c8303f32e2bfa40` |
| all seven, in this order | `66181954b3c74c17519096a3c3bc3e01bef3702784d3962171b066699bea4a12` |

From here a change to `Dataset/v3` is a new dataset, not a repair: lora-v3 is trained on exactly these bytes (the run record repeats the hash).

**2. What "the same committed rule" means for `real3`.** D37 says "the same committed rule, a new seed". `real1` used rule 1 and `real2` rule 2, so `real3` uses
**both, with one new seed `SEED3 = 20261019`** (`Scripts/real_set.py select --rule 3`): per filing one paragraph with a keyword and an amount (draw 1); five filings
that also give a paragraph with no field (draws 2 and 3); and one headline paragraph per filing that has one (rule 2). The shape tests, the keywords, the
region and the cut to six sentences are those of rules 1 and 2, unchanged (proven: rules 1 and 2 still reproduce `passages1.json` and `passages2.json` byte for byte).
The expected size is about 20 to 30 passages from the same 17 filings.

**3. Fresh passages.** Before each draw, a paragraph whose cut shares **a run of 6 consecutive words** (the measure of the data validator) with a passage of `real1`,
of `real2` or with one already drawn for `real3` is removed from the pool. Without it the same paragraph could come twice. The number removed is printed (a count).
Proven on a synthetic set (deterministic, no overlap with the earlier set or inside `real3`; with the check switched off 3 passages overlap).

**4. After the draw.** The passages are frozen (SHA-256 recorded in the run record), then read and labelled by the strict rule of Phase 2b (labels in
`RealSet/labels3.json`, never committed); the doubtful labels are put to the user; the references (unmodified model and `lora-v2`) run on `real3` before any
training run starts. The data validator's private check also reads `passages3.json` (the glob `RealSet/passages*.json`): a six-word run of `real3` in `Dataset/v3`
would be a leak by coincidence; if one appears it is **disclosed with its count**, and the data stays frozen.

**5. Unchanged.** The criteria 1 to 8, the stop rule, the seeds and the cost. Criterion 5 reads `real3` as drawn here (not blind by labels, blind by construction).

## Amendment 3, 2026-10-19, after a first draw of `real3` that was discarded unread

What happened, in order. Amendment 2 was committed (fbebf18); `select --rule 3` was run once: **12 passages (6 with fields, 5 with no field, 1 headline), 60 candidate
paragraphs removed as not fresh, SHA-256 of that file `a1669dbf5b244e23068e95222a69b5ea8434389bea48df81bc5d441d11c053ae`**. Only these counts and the hash were looked
at: no passage was opened, read or labelled.

**The deviation.** Amendment 2 says the freshness measure is "the measure of the data validator", which ignores the standard date phrase ("year ended December").
`real_set.py` did not ignore it (an implementation slip, not a choice). It is corrected (`GENERIC` in `real_set.py`, same regular expression as the validator), a test
shows that the phrase alone no longer makes two passages overlap and that a real shared run still does, and rules 1 and 2 still reproduce `passages1.json` and
`passages2.json` byte for byte. The draw is deterministic, so it is run again with the corrected measure; the first file is overwritten (its hash is above).

**What the counts showed, which Amendment 2 got wrong.** The estimate "about 20 to 30 passages" was a guess. Counted per filing (counts only), the 17 reports hold **53** paragraphs
with a keyword and an amount (16 already drawn for `real1`, 22 still fresh in 6 filings), **380** with no field (341 fresh), and **18** headline paragraphs (3 fresh): real1 and
real2 took most of the paragraphs of the kinds that carry fields. So `real3` will be **small (about 12 passages), with few stated fields**, and its numbers are mostly about invented values.
This is not changed here: the shape rule, the keywords and the six-sentence cut stay, and no rule is relaxed to get more passages (that would be a change made after seeing the counts).
`real3` stays what D37 says, with this limit stated; it is **one** of three real sets, and the conclusion on real text is read on `real1`, `real2` and `real3` together as well as on
each. If the user supplies more reports later, they can make a further fresh set (a new experiment, not a change to this one).

**Result of the corrected draw (added after it was run).** The second draw is **byte-identical to the first** (same SHA-256 `a1669dbf5b244e23068e95222a69b5ea8434389bea48df81bc5d441d11c053ae`, 12 passages: 6 with fields, 5 with
no field, 1 headline, 60 removed as not fresh): the slip changed nothing. The hash was mistyped (one character missing) in the first version of this amendment (commit 61e05b0) and is
corrected here. `real3` is frozen with this hash; reading and labelling start now.

## Amendment 4, 2026-10-25, after the release v2.5.0: a third seed of both recipes (written before any run)

**What was seen first.** All of the Phase 2d results: two seeds of `lora-v3` and of `lora-v2` on the old test, test 3, `real1`, `real2` and `real3`
(`Results/lora-v3-analysis.md`), including the one garbled key of `lora-v3` seed 1 on `real3` and its absence in seed 2. The analysis itself says that two seeds
are a thin measure of noise (a spread is one range of two points) and that `lora-v3` may miss more growth and previous-year values. Nothing else was seen: no third-seed run exists.

**What is added.** An extension, not a change to the criteria: **seed 3 of `lora-v3` and seed 3 of `lora-v2`**, trained with the same configs, the same data (the frozen `Dataset/v3`
and `Dataset/v2`, checked byte-identical to `adapters/data-v3` and `adapters/data-v2`), the same stop rule applied by `stop_rule.py`, and only `--seed 3 --adapter-path adapters/<name>`
on the command line, exactly as the seed-2 runs. Names: `lora-v3-s3` and `lora-v2-s3`. Each is evaluated on the same five sets as the seed-2 adapters (old test, test 3, `real1`, `real2`, `real3`;
not test 2) with the same prompt, build, seeds 1 to 3 and settings. The user approved the work, including the phone use, on 2026-10-25 ("do all of them").

**How the result is read (fixed now).**
1. The criteria 1 to 8 stay as written for `lora-v3` seed 1 and are **not re-judged** on seed 3; the verdict of `lora-v3-analysis.md` (seven of eight met, criterion 6 not met) stays as published.
2. D39 is applied again with three seeds: means over the three seeds, spread = maximum minus minimum over the three, and a difference counts only if it exceeds the larger of the two spreads. Each conclusion
   marked "beyond the noise" or "not distinguishable" in the analysis is re-read; **if a third seed reverses one, that is reported as it is**, with the old reading kept in the table.
3. Counted separately, per recipe: how many seeds give an undecodable answer on each set (the garbled key), and the missed values on the old test (criterion 1 was met with zero margin).
4. No adapter is chosen, dropped or re-run because of how it scores; a seed whose training stops late or early is kept as the rule gives it. An interrupted run is kept as evidence and restarted from scratch.
5. The real-set numbers stay counts only (`Scripts/phase2d_table.py`, which will list the new adapter names); the results go in a new file `Results/lora-seed3-analysis.md`, and the earlier analysis is not edited.

**Cost.** Training about 2 to 5 hours each on the Mac (the seed-2 runs took 124 and 109 minutes, seed 1 of `lora-v3` 289), the evaluations about 3.5 hours of phone time each. The `lora-v2-s3` training runs
on the Mac while the phone evaluates `lora-v3-s3`.
