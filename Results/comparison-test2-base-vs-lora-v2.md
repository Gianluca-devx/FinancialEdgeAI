## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `baseline-test2-Qwen3-4B-4bit-iphone-20261017T181748.json` | `lora-v2-test2-Qwen3-4B-4bit-iphone-20261018T131315.json` |
| Adapter | none (the base model) | lora-v2: rank 8, 16 layers, weights `ffbdc621dc72` |
| Evaluation set | test2 | test2 |
| Device | iPhone17,3, iOS Version 27.0.1 (Build 24A446) | iPhone17,3, iOS Version 27.0.1 (Build 24A446) |
| Statements x runs | 30 x 3 | 30 x 3 |
| Temperature / max tokens / seeds | 0.2 / 384 / [1, 2, 3] | 0.2 / 384 / [1, 2, 3] |
| Prompt hash | `7779853b346c` | `7779853b346c` |
| Test set hash | `002d4f9604dc` | `002d4f9604dc` |
| Schema hash | `f70490659aa3` | `f70490659aa3` |

The prompt and the test set are **identical**, so the two runs differ only by what is listed above.

## Headline

| Measure | Before | After |
|---|---|---|
| Answers the app can decode (valid JSON) | 90 / 90 (100.0%) | 90 / 90 (100.0%) |
| Exactly the asked keys, right types | 90 / 90 (100.0%) | 90 / 90 (100.0%) |
| **All 13 fields correct** | 34 / 90 (37.8%) | 77 / 90 (85.6%) |
| Fields correct | 1073 / 1170 (91.7%) | 1148 / 1170 (98.1%) |
| Wrong fields | 97 / 1170 (8.3%) | 22 / 1170 (1.9%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 87 (96.7%) | 86 (95.6%) | hallucinated 3 | hallucinated 4 |
| `operatingIncome` | 84 (93.3%) | 87 (96.7%) | missed 3, unreadable 3 | missed 3 |
| `netIncome` | 90 (100.0%) | 87 (96.7%) | - | hallucinated 3 |
| `eps` | 87 (96.7%) | 90 (100.0%) | unreadable 3 | - |
| `interestExpense` | 87 (96.7%) | 90 (100.0%) | missed 3 | - |
| `operatingCashFlow` | 81 (90.0%) | 87 (96.7%) | hallucinated 9 | hallucinated 3 |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 63 (70.0%) | 87 (96.7%) | hallucinated 24, wrongValue 3 | missed 3 |
| `previousYearNetIncome` | 81 (90.0%) | 87 (96.7%) | hallucinated 9 | hallucinated 3 |
| `previousYearEps` | 87 (96.7%) | 88 (97.8%) | missed 3 | unreadable 2 |
| `revenueGrowth` | 80 (88.9%) | 90 (100.0%) | hallucinated 10 | - |
| `netIncomeGrowth` | 75 (83.3%) | 89 (98.9%) | hallucinated 14, unreadable 1 | hallucinated 1 |
| `epsGrowth` | 81 (90.0%) | 90 (100.0%) | hallucinated 6, signError 3 | - |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 75 (6.4%) | 14 (1.2%) |
| missed | 9 (0.8%) | 6 (0.5%) |
| wrongValue | 3 (0.3%) | 0 (0.0%) |
| signError | 3 (0.3%) | 0 (0.0%) |
| unreadable | 7 (0.6%) | 2 (0.2%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 85 |
| correct before, **wrong now** | 10 |
| wrong before and still wrong | 12 (of which 3 with another kind of mistake) |

Fixed, by field: `previousYearRevenue` 24, `netIncomeGrowth` 15, `revenueGrowth` 10, `previousYearNetIncome` 9, `epsGrowth` 9, `operatingCashFlow` 6, `operatingIncome` 3, `eps` 3, `interestExpense` 3, `previousYearEps` 3.

Broken, by field: `netIncome` 3, `previousYearNetIncome` 3, `previousYearEps` 2, `revenue` 1, `netIncomeGrowth` 1.

| Statement | Run | Field | Now |
|---|---|---|---|
| 6 | 1 | `previousYearEps` | unreadable |
| 6 | 3 | `previousYearEps` | unreadable |
| 17 | 1 | `netIncome` | hallucinated |
| 17 | 1 | `previousYearNetIncome` | hallucinated |
| 17 | 2 | `netIncome` | hallucinated |
| 17 | 2 | `previousYearNetIncome` | hallucinated |
| 17 | 3 | `netIncome` | hallucinated |
| 17 | 3 | `previousYearNetIncome` | hallucinated |
| 24 | 1 | `revenue` | hallucinated |
| 25 | 1 | `netIncomeGrowth` | hallucinated |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 9.8 s | 10.3 s |
| Median time to first token | 3.65 s | 3.63 s |
| Median generated tokens | 124 | 119 |
| Median tokens per second | 21.1 | 18.9 |
| Peak MLX memory | 2.50 GiB | 2.65 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 15.6 min | 17.1 min |
