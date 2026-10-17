# Baseline: the extended call (balance sheet), Qwen3-4B (4-bit), no fine-tuning

The second call of the app: the five balance sheet fields (`totalDebt`, `shareholdersEquity`, `currentAssets`,
`currentLiabilities`, `cash`), with its own prompt (`Dataset/prompt_template_extended.txt`), on the same 30 frozen
test statements, three runs, on the iPhone 16. Generated tables:
`baseline-tables-extended-iphone-20261016.md`. Raw report (every raw answer, every judgement):
`baseline-extended-Qwen3-4B-4bit-iphone-20261016T125454.json`. The core call has its own baseline:
`baseline-analysis-schema1.md`. Specs: `Specs/phase-1b-extended-call.md`.

## Read this first

- **A separate experiment, with its own prompt.** The extended prompt is new text (the same structure as the core
  prompt, the five extended fields, no growth rule). Its result is measured here and is not a change to the core
  baseline: the core prompt, the core files and the core report are untouched (checked byte for byte against
  `v2.0.0`).
- **Same settings otherwise:** the same model, temperature 0.2, `maxTokens` 384, seeds 1, 2, 3, thinking off, a
  fresh chat session per statement, the same phone (Debug build). The statements are the same as in the core test.
- **30 statements, not 90 answers.** All 30 statements gave the same extracted strings in all three runs. One
  statement is 3.3 points. The balance sheet fields are stated in only 3 or 4 test statements each, so the
  accuracy of one field is a rough indication.
- The run was started from the command line (`-autoRunEvaluation YES -evaluationTier extended`); the report was
  copied from the app with `xcrun devicectl`. Nobody touched the phone.

## Headline

| Measure | Count | Share |
|---|---|---|
| Valid JSON (the app's decoder can read it) | 90 / 90 | 100% |
| Exactly the 5 extended keys, a string or null each | 90 / 90 | 100% |
| Needed a Markdown fence or a reasoning block | 0 / 90 | 0% |
| **All 5 fields correct** | **78 / 90** | **86.7%** |
| Fields correct | 438 / 450 | 97.3% |
| Wrong fields | 12 / 450 | 2.7% |
| Strings copied exactly like the label (where both have one) | 42 / 57 | 73.7% |

Four of the five fields are 100% correct (`totalDebt`, `shareholdersEquity`, `currentAssets`,
`currentLiabilities`, 90 of 90 each). All 12 wrong fields are `cash`.

## What goes wrong: 12 wrong fields, all `cash`, in 4 of 30 statements

As in the core baseline, the model never wrote a wrong number, never got a unit or a sign wrong, and never
returned null for a value that the text prints. The errors are all the model writing something where the label
is null (9 `hallucinated`) or writing a number in a form the parser refuses (3 `unreadable`). The 4 statements fail
in all three runs.

| Cause | Wrong fields | Statements |
|---|---|---|
| **The operating cash flow written as `cash`** | 9 | 3 (8, 16, 26) |
| **A correct number the parser refuses** (`$924 million dollars`) | 3 | 1 (28) |

- **Cash flow against cash.** The statements 8, 16 and 26 state a cash flow ("cash generated from operations came to
  46.9 billion dollars", "net cash from operating activities was USD 77.6 billion", the same with $3.1 billion)
  and no cash balance. The model returned that amount as `cash`. A cash flow sentence is not "cash and cash
  equivalents", but it contains the word "cash", and a 4B model follows the word. Every statement of the
  `cash_flow` scenario fails (0 of 6 answers fully correct), and so does the hand-written one with the same sentence.
- **The same form as in the core baseline.** Statement 28: the label is `924 million dollars`; the model wrote
  `$924 million dollars` (a `$` in front and the word "dollars" behind). The value is right; the parser has two
  currency markers and refuses it. It is the same case as `$10.3 billion dollars` of the core baseline, so it is now
  seen in both calls: 3 fields here, 3 there.

## By scenario

| Scenario | Answers | All 5 correct |
|---|---|---|
| amounts only, EPS only, all income fields, growth only, basic income, interest, random subset, none of the fields, prior year without growth | 3 + 9 + 12 + 3 + 6 + 6 + 9 + 3 + 9 | 100% |
| balance sheet | 9 | 66.7% (the `$924 million dollars` statement) |
| hand-written | 15 | 80% |
| cash flow | 6 | 0% |

Unseen wording (pool B) is 83.3% fully correct (12 statements), seen wording (pool A) 88.9% (18 statements):
not distinguishable at this sample size.

## What it costs on the iPhone

| | Core call (schema 1 baseline) | Extended call |
|---|---|---|
| Time per statement (median) | 10.5 s | 4.0 s |
| Time to first token (median) | 3.68 s | 2.15 s |
| Prompt tokens / generated tokens (median) | 567 / 122 | 301 / 35 |
| Generation speed (median) | 20.6 tokens/s | 21.7 tokens/s |
| Peak MLX memory | 2.72 GiB | 2.59 GiB |
| Generation time in total (90 answers) | 16.4 min | 6.2 min |

- **Both calls together cost about 14.5 s per statement** (10.5 + 4.0): the button adds about 40% to the time of an
  answer, and it is only paid when the user taps it. This is what the design of the second call was for: the core
  answer is not made longer for everyone.
- The thermal state reached "serious" (7 of the 90 answers ended at it, none started at it). The run took 16.5
  minutes on the wall clock for 6.2 minutes of generation: the rest is the runner waiting for the phone to cool.
- Memory is slightly lower than the core call (a shorter prompt and answer).

## What this means for the project

- **The balance sheet is easier for the model than the income statement:** 86.7% of the answers fully correct on 5
  fields (the core call: 63.3% on 13 fields) and 97.3% of the fields correct (95.3%). It is the same kind of
  failure, though: the model fills a field that should be null.
- **With the four fields that are 100% correct, the app can show four more derived values** (return on
  equity, debt to equity, current ratio, net debt) when the balance sheet is stated.
- **The extended call is a second target for a specialised model** with a very concrete failure: do not take a
  cash flow for the cash balance. It would also profit from the two small things already noted for the core call
  (the parser could accept `$924 million dollars`, a prompt sentence could say that a cash flow is not the cash).
  None of them was changed here: a changed prompt or parser is a new experiment.
- **Nothing is held out for this task:** the extended call is evaluated on the same 30 statements as the core call.

## Limits

- 30 test statements, effectively one run each. `cash` appears in 4 test statements, the other four fields in 3
  or 4: the per-field figures are rough indications.
- Synthetic, short statements, English and USD. No losses, no several periods, no unit given only in a table header.
- Debug build, one iPhone model (iPhone 16).
- "Valid JSON" accepts what Foundation accepts (a trailing comma is read).
- The prompt is new and was measured once; a different wording could do better on the cash flow sentences.
