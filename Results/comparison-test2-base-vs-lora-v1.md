## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `baseline-test2-Qwen3-4B-4bit-iphone-20261017T181748.json` | `lora-v1-test2-Qwen3-4B-4bit-iphone-20261017T192549.json` |
| Adapter | none (the base model) | lora-v1: rank 8, 16 layers, weights `aadab981fed8` |
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
| **All 13 fields correct** | 34 / 90 (37.8%) | 48 / 90 (53.3%) |
| Fields correct | 1073 / 1170 (91.7%) | 1111 / 1170 (95.0%) |
| Wrong fields | 97 / 1170 (8.3%) | 59 / 1170 (5.0%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 87 (96.7%) | 84 (93.3%) | hallucinated 3 | missed 6 |
| `operatingIncome` | 84 (93.3%) | 79 (87.8%) | missed 3, unreadable 3 | missed 11 |
| `netIncome` | 90 (100.0%) | 78 (86.7%) | - | missed 12 |
| `eps` | 87 (96.7%) | 90 (100.0%) | unreadable 3 | - |
| `interestExpense` | 87 (96.7%) | 84 (93.3%) | missed 3 | missed 6 |
| `operatingCashFlow` | 81 (90.0%) | 87 (96.7%) | hallucinated 9 | hallucinated 3 |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 63 (70.0%) | 87 (96.7%) | hallucinated 24, wrongValue 3 | missed 3 |
| `previousYearNetIncome` | 81 (90.0%) | 81 (90.0%) | hallucinated 9 | missed 9 |
| `previousYearEps` | 87 (96.7%) | 90 (100.0%) | missed 3 | - |
| `revenueGrowth` | 80 (88.9%) | 90 (100.0%) | hallucinated 10 | - |
| `netIncomeGrowth` | 75 (83.3%) | 87 (96.7%) | hallucinated 14, unreadable 1 | missed 3 |
| `epsGrowth` | 81 (90.0%) | 84 (93.3%) | hallucinated 6, signError 3 | missed 6 |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 75 (6.4%) | 3 (0.3%) |
| missed | 9 (0.8%) | 56 (4.8%) |
| wrongValue | 3 (0.3%) | 0 (0.0%) |
| signError | 3 (0.3%) | 0 (0.0%) |
| unreadable | 7 (0.6%) | 0 (0.0%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 82 |
| correct before, **wrong now** | 44 |
| wrong before and still wrong | 15 (of which 6 with another kind of mistake) |

Fixed, by field: `previousYearRevenue` 24, `netIncomeGrowth` 15, `revenueGrowth` 10, `previousYearNetIncome` 9, `operatingCashFlow` 6, `epsGrowth` 6, `operatingIncome` 3, `eps` 3, `revenue` 3, `previousYearEps` 3.

Broken, by field: `netIncome` 12, `previousYearNetIncome` 9, `operatingIncome` 8, `revenue` 6, `netIncomeGrowth` 3, `interestExpense` 3, `epsGrowth` 3.

| Statement | Run | Field | Now |
|---|---|---|---|
| 6 | 1 | `netIncome` | missed |
| 6 | 1 | `previousYearNetIncome` | missed |
| 6 | 2 | `netIncome` | missed |
| 6 | 2 | `previousYearNetIncome` | missed |
| 6 | 3 | `netIncome` | missed |
| 6 | 3 | `previousYearNetIncome` | missed |
| 9 | 1 | `netIncome` | missed |
| 9 | 2 | `netIncome` | missed |
| 9 | 3 | `netIncome` | missed |
| 11 | 1 | `netIncome` | missed |
| 11 | 2 | `netIncome` | missed |
| 11 | 3 | `netIncome` | missed |
| 12 | 2 | `operatingIncome` | missed |
| 12 | 3 | `operatingIncome` | missed |
| 14 | 1 | `netIncome` | missed |
| 14 | 1 | `previousYearNetIncome` | missed |
| 14 | 2 | `netIncome` | missed |
| 14 | 2 | `previousYearNetIncome` | missed |
| 14 | 3 | `netIncome` | missed |
| 14 | 3 | `previousYearNetIncome` | missed |
| 15 | 1 | `previousYearNetIncome` | missed |
| 15 | 2 | `previousYearNetIncome` | missed |
| 15 | 3 | `previousYearNetIncome` | missed |
| 18 | 1 | `netIncomeGrowth` | missed |
| 18 | 2 | `netIncomeGrowth` | missed |
| 18 | 3 | `netIncomeGrowth` | missed |
| 20 | 1 | `operatingIncome` | missed |
| 20 | 2 | `operatingIncome` | missed |
| 20 | 3 | `operatingIncome` | missed |
| 24 | 1 | `interestExpense` | missed |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 9.8 s | 10.6 s |
| Median time to first token | 3.65 s | 3.76 s |
| Median generated tokens | 124 | 118 |
| Median tokens per second | 21.1 | 18.7 |
| Peak MLX memory | 2.50 GiB | 2.65 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 15.6 min | 16.7 min |
