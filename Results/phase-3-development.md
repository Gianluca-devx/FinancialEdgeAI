# Phase 3, development: the overview and business sections on the 5 development reports

Step 2 of [`Specs/phase-3-report-sections.md`](../Specs/phase-3-report-sections.md), 2026-11-15, on the Mac (no phone). Counts only:
no report text, label or answer, and no company name. Texts, labels, answers and verdicts are in `RealSet/sections/` (git-ignored).
This is development, not a result: the prompts were changed while looking at these answers.

## The texts (S1)

- **The rule of S1 found the Item 1 heading on 5 of 5 development reports,** each time on a page that is not the table of contents.
  The text starts at the heading line, not at the top of its page.
- **All 5 texts were longer than 2,500 tokens** over the 8 pages allowed, so all were cut: 2,494 to 2,499 tokens, 1,372 to 1,975
  words. With the final prompts, a call reads 2,882 to 2,899 tokens.
- **The test split** (`Dataset/test.jsonl`): 30 statements, extracted by `sections.py testsplit`; none holds a word such as
  "makes", "sells", "segment" or "customers".

## The development labels (S7)

- **30 facts, 21 stated:** overview 6 of 15 (what the company does 5, a size 1, a headquarters 0), business 15 of 15 (segments 5,
  products 5, customers 5). sha256 `eb8ef2b76fe9`. **None of the 5 texts states a headquarters city**: in a 10-K it is on the cover
  page, outside Item 1.
- **Each stated fact was checked against its own text** by the coverage rule: 21 of 21 found; a made-up term that is not in the text
  fails, as it must.
- **The labelling rules used, kept for step 3:** what the company does is its main activity as the text first states it, as two or
  three groups of key terms (the main product or service categories, with the text's other names for them); the headquarters is a
  city the text names; the size is the first count of employees, stores, countries or customers in the text, never an amount of
  money; the segments are every reportable segment the text names (with its abbreviation and its "&" or "and" form), or the
  business lines when no segment is named; the products are up to four groups of the main products or services the text names
  first; the customers are up to four groups of the customer types or markets the text states. A fact the text does not state is
  null.

## The checker during development (S8)

Three changes, each made after the first run showed the problem, each with a test (26 tests for `sections.py`, 49 Python tests in
all):

1. **A key term matches across a line break:** a segment name in one text is split over two lines.
2. **Name flags:** a plural counts as found when its singular is in the text, a hyphenated word by its capitalised parts, and
   letters right after digits ("4WD") are left to the number rule. These three forms gave 4 of the first run's 6 flags, all false.
3. **A run reads the prompts once** and records the hash of what it read, so a prompt edited during a run cannot mix two versions.

Hand verdicts on the development answers: 5 flags confirmed (the two words of a headquarters country, for two reports, and one
number copied from a prompt's example), 0 rejected after the fixes above.

## The prompts, version by version (condition B, seeds 1 to 3)

Development: 5 reports, 15 answers per section; the test split: 90 answers per section. "Invented" counts the answers with a
confirmed item. The format check is 60 and 100 words; from version 2 the prompts ask for 50 and 85.

| Version | Hash | What changed | Format (overview, business) | Invented | Covered: overview, business | Test split "not stated" |
|---|---|---|---|---|---|---|
| v1 | `93398f82e8c8` | the spec's S4 as written | 13, 13 | 3, 0 | 18/18, 26/45 | 6/90, 0/90 |
| v2 | `13033f3fc0d0` | results belong to another section; a place only when stated; all segments; customers; 50 and 85 words asked | 15, 15 | 0, 0 | 18/18, 27/45 | 0/90, 21/90 |
| v3 | `de9677f8736e` | the decision first (does the text say what the company makes, sells or provides?), no guessing from the company's name, products as the text names them; v2's sentence about "the app" removed, as the overview then described the app | 15, 15 | 3, 0 | 18/18, 28/45 | 0/90, 60/90 |
| v4 | `338d20e17bee` | two made-up examples in each prompt: financial results only, answered "Not stated in the text."; a description, answered | 12, 15 | 0, 0 | 18/18, 33/45 | 69/90, 84/90 |
| v5 | `3c5e9cf0887d` | overview: no segments or customers; a third example (employees, stores and results, answered "not stated") | 12, 15 | 0, 0 | 18/18, 33/45 | 75/90, 84/90 |
| v6 | `a2f8f10a809f` | overview: one or two sentences in a fixed order instead of a word count | 15, 15 | 3, 0 | 18/18, 33/45 | 75/90, 84/90 |
| v7 | `729b1df1c804` | v6 with no number in the examples | 13, 15 | 3, 0 | 18/18, 33/45 | 75/90, 84/90 |
| v8 | `eb246e80bd26` | v5 with v7's examples (no number that can be copied) | 12, 15 | 0, 0 | 18/18, 33/45 | 75/90, 84/90 |

The business prompt is unchanged from v4 on. In v6 the employee count of an example was copied into one report's overview, in all
three seeds; v7 then named a headquarters country the text does not give, as v1 and v3 had.

**The selection rule, written before v8 ran:** the fewest development answers with an invented item, then the most "not stated" on
the test split, then format, then coverage. v5 and v8 tie on all four; **v8 is the candidate for the freeze**, for the reason given
before its run: its examples hold no number an answer could copy.

## What development shows (to read step 4 with, not a result)

- **The seeds barely differ.** At temperature 0.2 the three seeds give nearly the same answer, so each development count moves by a
  whole report (3 answers). These are 5 reports, not 15 independent answers; the held-out set has 22.
- **The invented facts are of one kind:** where the company is based, written in 3 of 8 versions for 2 of 5 reports, though no text
  states it. The other was a number copied from a prompt's example.
- **The word limit is not kept by one report's overview** (63 to 67 words in 4 of 8 versions; in v1 two other reports were over).
  The overview also names the segments in most answers, despite the instruction; no measure counts that, but it repeats the
  business section.
- **"Not stated" needed examples:** without them the base model rewrites a statement's financial results as an overview (v1 to v3).
  With v8, 5 of 30 statements still get an overview (company names that suggest an industry, and a statement about a new chief
  financial officer and a headquarters move) and 2 of 30 a business section.
- **A hand reading of v8's seed 1 answers** (10) for claims with no flagged number or name: 1 answer with 2 unsupported claims, a
  product placed in the wrong product line. The check cannot see it, because every name in it is in the text; the held-out seed 1
  reading of the spec counts such claims.

## Condition L (`lora-v3`, seed 1)

| Prompts | Format (overview, business) | Cut at 256 tokens | Test split "not stated" |
|---|---|---|---|
| v1 | 1/15, 3/15 | 24 of 30 | 0/90, 0/90 |
| v8 | 1/15, 1/15 | 26 of 30 | 0/90, 0/90 |

The adapter, trained only on JSON extraction, breaks free text: long answers cut at the token limit, stray markup, numbers that
are not in the text (L's 41 flags on the development reports were not checked by hand: its format fails before that matters). By S5 the app will take it off for the two sections; step 4 measures L again on the held-out reports.

## Time on the Mac

Condition B, v8: median 11.3 s per answer on the reports (about 2,890 prompt tokens, 85 generated), 1.5 s on the test split.
Condition L: about 1.5 times longer per call, and its answers run to the token limit. From Phase 2f's phone speeds, a section on
the phone is about 26 s of reading and 6 s of writing; step 7 measures it.

## Open before the freeze

**"Not stated" was developed on the test split,** the same 30 statements that the spec's decision rule uses for it, so the rule
would score it on data the prompts were shaped on. Proposed for the user's decision before step 3: measure "not stated" in step 4 on
**test 2** (`Dataset/v2/test2.jsonl`, 30 synthetic statements, never used in this phase, none with a business word; checked to
extract), and report the test split as development.
