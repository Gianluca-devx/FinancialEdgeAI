# Phase 3, step 4: the held-out run (counts only)

Step 4 of [`Specs/phase-3-report-sections.md`](../Specs/phase-3-report-sections.md) (with Amendment 1), 2026-11-16, on the Mac (no
phone). Counts only: no report text, label or answer, and no company name. Answers, checks, verdicts and the hand reading are in
`RealSet/sections/` (git-ignored). The reading of the decision rule is written in step 5.

## The run

- **Before it:** the 8 frozen files matched the hashes of [`phase-3-heldout.md`](phase-3-heldout.md), as did the 22 page-text files
  (`a860faafe82b`), the labels (`39bcb5f7b718`) and the `lora-v3` weights (`26a0d90702e19f00`, also checked by the script); no frozen
  file had changed since ec6b9e3; 51 Python tests passed. **After it** the same hashes matched again.
- **What ran:** condition B (the base model), then L (`lora-v3`), each on the 21 located held-out texts and on test 2's 30
  statements, two sections, seeds 1 to 3: **612 answers** (126 and 180 per condition), all with prompts `eb246e80bd26`, none
  missing or repeated. One run, started 16:45 and ended 19:11; nothing was re-run.
- **The held-out set:** the rule of S1 located 21 of the 22 reports. The missed one has no text, so it has no answer and no fact.
  The labels hold 90 stated facts, so each condition has 270 facts to cover over its three seeds.
- **A pause:** the Mac was on battery and its lid was closed from 17:58 to 18:59, so it slept and the run paused during L on
  test 2. The answers are not affected, because each depends only on its prompt, text and seed. The times of the 2 answers that
  spanned the pause (2,182 s and 1,167 s) are left out of the times below.

## Condition B (it decides the rule)

| Held-out, 21 texts | Answers | In format | With an invented item | Facts covered | "Not stated" |
|---|---|---|---|---|---|
| Overview | 63 | 49 (14 too long) | 2 | 83/102 | 1 |
| Business | 63 | 61 (2 too long) | 0 | 87/168 | 0 |
| **Both** | **126** | **110 (87.3%)** | **2 (1.6%)** | **170/270 (63.0%)** | 1 |

| Test 2, 30 statements | Answers | In format | With an invented item | "Not stated" |
|---|---|---|---|---|
| Overview | 90 | 90 | 0 | 69 |
| Business | 90 | 90 | 0 | 87 |
| **Both** | **180** | 180 | 0 | **156 (86.7%)** |

- **Coverage by fact:**

  | Fact | Covered |
  |---|---|
  | What the company does | 53/60 |
  | A headquarters | 0/6 |
  | A size | 30/36 |
  | Segments or business lines | 24/54 |
  | Products | 31/54 |
  | Customers | 32/60 |

  The overview covers 81%, the business 52%: the business answers describe the company in general terms and leave out the
  names of its segments and products.
- **Format:** every miss is a word count over the limit. 14 overviews are over 60 words (the prompt asks for 50; the median is 54),
  and 2 business answers are over 100. None is cut, and none has a heading, list or JSON.
- **Invented:** the 2 answers are overviews, seeds 2 and 3, on the text with no business description. They give the company a home
  country that the text does not name.
- **"Not stated" on test 2:** the 24 misses come from 7 statements in the overview and 1 in the business, each in all three seeds.
  5 of the 8 answers restate the financial results. The other 2 overview statements, with events and a workforce but no
  description of the business, are restated as an overview. On the held-out set, the one "not stated" is the seed 1 overview of
  the text with no business description; its other 5 answers describe it anyway.
- **By where the text starts:** on the 18 texts that start at the Item 1 heading of the body, B covers 158/246 facts (64.2%) and has
  97/108 answers in format. On the other 3, it covers 12/24 (50.0%) and has 13/18 in format. Those 3 are 2 texts taken from a
  table of contents and 1 from an index followed by the signature page.

## Against the decision rule (read in step 5)

| Clause of "build" | Limit | B, held-out (test 2 for "not stated") |
|---|---|---|
| Answers with an invented item | at most 5% | 1.6% (2/126) |
| Stated facts covered | at least 70% | 63.0% (170/270) |
| Answers in format | at least 95% | 87.3% (110/126) |
| "Not stated" on test 2 | at least 90% | 86.7% (156/180) |

The stop clauses are not met: invented is at most 15%, and coverage is at least 50%. Three clauses of "build" are not met.

## Condition L (`lora-v3`, reported)

| | Answers | In format | Cut at 256 tokens | With an invented item | Facts covered | "Not stated" |
|---|---|---|---|---|---|---|
| Held-out, overview | 63 | 32 | 17 | 18 | 84/102 | 0 |
| Held-out, business | 63 | 31 | 31 | 19 | 84/168 | 0 |
| **Held-out, both** | **126** | **63 (50.0%)** | 48 | **37 (29.4%)** | **168/270 (62.2%)** | 0 |
| **Test 2, both** | **180** | **69 (38.3%)** | 109 | **139 (77.2%)** | - | **0** |

- **The invented items are of three kinds:**
  - **Made-up image links and web addresses**, with long runs of digits: in 102 of the 126 held-out answers and 145 of the 180 on
    test 2.
  - **The prompt's made-up example company**, copied word for word into the answer: 6 held-out answers on 2 reports, and 71 test 2
    answers.
  - **A home country the text does not name:** 3 held-out reports.
- **Coverage is the same as B's,** and L gives the 2 stated headquarters in 5 of 6 answers (B in none). L never answers "not stated".

## B against L, with the seed spread

Both sections are pooled, and each cell gives seeds 1, 2 and 3.

| | B | L | Difference of the means | Larger seed spread | Reading |
|---|---|---|---|---|---|
| Held-out answers with an invented item | 0, 1, 1 | 12, 15, 10 | 11.7 | 5 | L worse |
| Held-out answers in format | 38, 36, 36 | 18, 21, 24 | 15.7 | 6 | L worse |
| Held-out facts covered | 57, 57, 56 | 60, 54, 54 | 0.7 | 6 | not distinguishable |
| Test 2 "not stated" | 52, 52, 52 | 0, 0, 0 | 52 | 0 | L worse |

B's three seeds differ by at most 2 answers on any measure. **L is worse than B beyond the seed spread** on three measures, and the
two cover the same. By S5, the app takes the adapter off for the two sections, which matters only on "build".

## The hand check of the flags

There is one verdict per report and item, whatever the answer, seed or condition. Each item was checked against its text.

- **Held-out, 101 items: 99 confirmed, 2 rejected.**
  - Rejected, as in the text in another form: an employee count written in millions where the text prints the full figure, and the
    text's own web address copied with a space in it.
  - Confirmed:
    - 89 numbers or names inside made-up links, all from L;
    - 6 for the two words of a home country, on 3 reports: 1 of them in B and L, the text with no business description, and 2 in L
      only;
    - 4 names from the prompt's made-up example, on 2 reports, from L.
  - B had 3 items: the country, confirmed, and the employee count, rejected.
- **Test 2, 309 items: 302 confirmed, 7 rejected.**
  - Rejected:
    - an amount written in billions where the statement prints millions (B's only item on test 2);
    - an abbreviation of the statement's per-share earnings;
    - 2 sentence starts after a quotation mark;
    - 3 common words capitalised as list items.
  - Confirmed, all from L:
    - 162 numbers inside made-up links;
    - 86 names from the prompt's made-up example, on 18 statements;
    - 29 items of a home country, on 14 statements;
    - 25 numbers of employees, stores, customers or countries that the statements do not give.
- **The 89 held-out and 162 test 2 link items** were found by a helper (each item lies inside a link in every answer where it
  appears) and confirmed after reading them: no test 2 statement holds a web address. Of the held-out texts that hold one, a single
  link copies the text's own address, and that item is rejected above. All other items were read one by one.

## The hand reading of B's seed 1 answers (42)

These are claims with no flagged number or name. They are counted, as the spec asks, and are not part of the rule.

- **2 answers with an unsupported claim**, 1 claim each:
  - On the text with no business description, the business answer says the report details the company's segments, products
    and markets. The text, an index of the report, names none of them.
  - One business answer says the company sells to three groups that the text says it works with.
- **2 borderline cases, not counted:**
  - A company said to have two segments, where the text gives two for its main business and a third group besides.
  - A therapeutic area named among the products, where the text names it for licensing agreements and research.
- **What the key terms miss:** of the 33 seed 1 facts they did not count, 2 are stated in other words. One is a company's segments
  described by its business lines without their names; the other is one of three segments in other words. **By hand, seed 1 covers
  59/90 facts instead of 57/90.**
- **What no measure counts:**
  - 5 of the 21 overviews name the segments, although the prompt says not to.
  - Neither text that states a headquarters gets it in a B answer.
  - On the text with no business description, the business answer describes the report's contents in all three seeds.

## Development against held-out (B, prompts v8)

| | Development, 5 reports | Held-out, 21 reports |
|---|---|---|
| In format | 27/30 (90.0%) | 110/126 (87.3%) |
| With an invented item | 0/30 | 2/126 (1.6%) |
| Covered, overview | 18/18 | 83/102 (81.4%) |
| Covered, business | 33/45 (73.3%) | 87/168 (51.8%) |
| Covered, both | 51/63 (81.0%) | 170/270 (63.0%) |
| "Not stated" | 159/180 on the test split (88.3%, development) | 156/180 on test 2 (86.7%) |

The drop is in coverage, and mostly in the business section. Format, invented and "not stated" are close to development.

## Time on the Mac

| | Median per answer | Prompt tokens | Generated, median |
|---|---|---|---|
| B, held-out, overview | 11.3 s | 1,267 to 2,899 | 77 |
| B, held-out, business | 12.7 s | 1,256 to 2,888 | 106 |
| B, test 2 (each section) | 1.8 s | 418 to 549 | 7 |
| L, held-out, overview | 14.5 s | same | 93 |
| L, held-out, business | 18.6 s | same | 229 |
| L, test 2 (each section) | 9.0 s | same | 256 |

The total generation time was:

| | Held-out | Test 2 |
|---|---|---|
| B | 24.7 min | 5.7 min |
| L | 34.3 min | 25.0 min, without the 2 answers over the pause |

The phone is timed in step 7, and only on "build".

## Private files (`RealSet/sections/`, git-ignored)

- `heldout/answers.B.jsonl`, `heldout/answers.L.jsonl`, `test2/answers.B.jsonl`, `test2/answers.L.jsonl`.
- In both folders: `check.json` (the counts), `check.flags.json` (now empty), `verdicts.json`, and `verdicts.reasons.json` (the
  reason of each rejected item and of each link item).
- In both folders: `flags.links.json`, the link items found by the helper.
