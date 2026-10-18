## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `lora-v1-test2-Qwen3-4B-4bit-iphone-20261017T192549.json` | `lora-v2-test2-Qwen3-4B-4bit-iphone-20261018T131315.json` |
| Adapter | lora-v1: rank 8, 16 layers, weights `aadab981fed8` | lora-v2: rank 8, 16 layers, weights `ffbdc621dc72` |
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
| **All 13 fields correct** | 48 / 90 (53.3%) | 77 / 90 (85.6%) |
| Fields correct | 1111 / 1170 (95.0%) | 1148 / 1170 (98.1%) |
| Wrong fields | 59 / 1170 (5.0%) | 22 / 1170 (1.9%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 84 (93.3%) | 86 (95.6%) | missed 6 | hallucinated 4 |
| `operatingIncome` | 79 (87.8%) | 87 (96.7%) | missed 11 | missed 3 |
| `netIncome` | 78 (86.7%) | 87 (96.7%) | missed 12 | hallucinated 3 |
| `eps` | 90 (100.0%) | 90 (100.0%) | - | - |
| `interestExpense` | 84 (93.3%) | 90 (100.0%) | missed 6 | - |
| `operatingCashFlow` | 87 (96.7%) | 87 (96.7%) | hallucinated 3 | hallucinated 3 |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 87 (96.7%) | 87 (96.7%) | missed 3 | missed 3 |
| `previousYearNetIncome` | 81 (90.0%) | 87 (96.7%) | missed 9 | hallucinated 3 |
| `previousYearEps` | 90 (100.0%) | 88 (97.8%) | - | unreadable 2 |
| `revenueGrowth` | 90 (100.0%) | 90 (100.0%) | - | - |
| `netIncomeGrowth` | 87 (96.7%) | 89 (98.9%) | missed 3 | hallucinated 1 |
| `epsGrowth` | 84 (93.3%) | 90 (100.0%) | missed 6 | - |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 3 (0.3%) | 14 (1.2%) |
| missed | 56 (4.8%) | 6 (0.5%) |
| unreadable | 0 (0.0%) | 2 (0.2%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 53 |
| correct before, **wrong now** | 16 |
| wrong before and still wrong | 6 (of which 0 with another kind of mistake) |

Fixed, by field: `netIncome` 12, `previousYearNetIncome` 9, `operatingIncome` 8, `interestExpense` 6, `epsGrowth` 6, `revenue` 6, `netIncomeGrowth` 3, `operatingCashFlow` 3.

Broken, by field: `revenue` 4, `operatingCashFlow` 3, `netIncome` 3, `previousYearNetIncome` 3, `previousYearEps` 2, `netIncomeGrowth` 1.

| Statement | Run | Field | Now |
|---|---|---|---|
| 6 | 1 | `previousYearEps` | unreadable |
| 6 | 3 | `previousYearEps` | unreadable |
| 7 | 1 | `operatingCashFlow` | hallucinated |
| 7 | 2 | `operatingCashFlow` | hallucinated |
| 7 | 3 | `operatingCashFlow` | hallucinated |
| 17 | 1 | `netIncome` | hallucinated |
| 17 | 1 | `previousYearNetIncome` | hallucinated |
| 17 | 1 | `revenue` | hallucinated |
| 17 | 2 | `netIncome` | hallucinated |
| 17 | 2 | `previousYearNetIncome` | hallucinated |
| 17 | 2 | `revenue` | hallucinated |
| 17 | 3 | `netIncome` | hallucinated |
| 17 | 3 | `previousYearNetIncome` | hallucinated |
| 17 | 3 | `revenue` | hallucinated |
| 24 | 1 | `revenue` | hallucinated |
| 25 | 1 | `netIncomeGrowth` | hallucinated |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 10.6 s | 10.3 s |
| Median time to first token | 3.76 s | 3.63 s |
| Median generated tokens | 118 | 119 |
| Median tokens per second | 18.7 | 18.9 |
| Peak MLX memory | 2.65 GiB | 2.65 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 16.7 min | 17.1 min |
