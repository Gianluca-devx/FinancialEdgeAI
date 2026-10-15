# Model gate: is `qwen3_4b_4bit` too heavy for the iPhone?

**Date:** 2026-10-14. **Device:** the development iPhone (iOS 27.0.1), app run from Xcode, Debug build.
**Model:** `mlx-community/Qwen3-4B-4bit` (about 2.3 GB). **Fallback if too heavy:** `gemma3_1B_qat_4bit`.

This is a feasibility test, not an accuracy comparison. It used 7 statements, so it says whether the
model fits and runs at a usable speed, nothing more.

## Criteria (fixed before the test)

The model was "too heavy" if any of these happened:

1. The app was killed or the load failed from memory pressure.
2. Median time per statement above about 15 s.
3. Generation speed below about 8 tokens/s.
4. Thermal state reached "serious".
5. The download could not finish in about 20 minutes.

## Result: passes every criterion

| Criterion | Measured | Verdict |
|---|---|---|
| Killed / failed to load | No, no extra entitlement needed | pass |
| Time per statement | 4.9 to 5.5 s (7.8 s for the first, which includes warm-up); median 5.4 s | pass |
| Tokens per second | 21.6 to 21.9 | pass |
| Thermal state | 0 (nominal) for all 7 statements | pass |
| Download + load | 463 s (7.7 min), first launch, includes the download | pass |

Other numbers: time to first token 1.8 to 2.1 s (3.7 s for the first statement), 65 to 75 generated
tokens per answer, MLX active memory 2231 MiB (2.18 GiB), MLX peak memory 2593 MiB (2.53 GiB, the app shows it as "2,53 GB").
`maxTokens` was 256, temperature 0.2, thinking switched off (`enable_thinking: false`). No reasoning
text and no Markdown fence appeared in any answer.

These numbers come from a **Debug build** started from Xcode. A Release build may be faster, so treat
the speeds as a lower bound.

**Decision: keep `qwen3_4b_4bit` as the baseline model.**

## What the 7 answers showed

| # | Statement | Result |
|---|---|---|
| 0, 1, 2 | The sample statement (3 runs) | All 7 fields correct, 3 out of 3, including `previousYearNetIncome = 21.9` |
| 3 | "Net income was $5.6 billion, down from $6.1 billion a year earlier." | `netIncomeGrowth = -0.5`. It should be null: the text gives no percentage (rule 7: do not calculate). The value is also wrong (-0.5 is the difference in billions; the change is about -8.2%) |
| 4 | "Revenue declined 2.5% ... operating income decreased 7%." | Correct |
| 5 | Table-style statement ("Total revenue: $230 billion, +7%. ...") | Correct |
| 6 | "Management expects revenue of $60 billion next year. This year, revenue was $52 billion, up 5%, and operating margin reached 21%." | `revenue = 60` (guidance, expected 52) and `operatingIncome = 21` (an operating margin in percent, expected null) |

So the unmodified 4B model reads clean statements well, and fails on exactly the cases the dataset was
built to probe: calculating a value that is not stated, and mistaking distractor numbers for metrics.
The baseline evaluation on the 30 test statements measures how often.

## How the numbers were collected

A temporary smoke test ran after the model loaded and logged each answer with `os.Logger`
(error level, because the Xcode console only streams that level from a device). It was removed
afterwards and is not in the repository.
