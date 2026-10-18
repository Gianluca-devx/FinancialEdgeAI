## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `baseline-schema1-Qwen3-4B-4bit-iphone-20261016T114216.json` | `lora-v2-Qwen3-4B-4bit-iphone-20261018T120711.json` |
| Adapter | none (the base model) | lora-v2: rank 8, 16 layers, weights `ffbdc621dc72` |
| Evaluation set | test | test |
| Device | iPhone17,3, iOS Version 27.0.1 (Build 24A446) | iPhone17,3, iOS Version 27.0.1 (Build 24A446) |
| Statements x runs | 30 x 3 | 30 x 3 |
| Temperature / max tokens / seeds | 0.2 / 384 / [1, 2, 3] | 0.2 / 384 / [1, 2, 3] |
| Prompt hash | `7779853b346c` | `7779853b346c` |
| Test set hash | `1eb1fc231078` | `1eb1fc231078` |
| Schema hash | `f70490659aa3` | `f70490659aa3` |

The prompt and the test set are **identical**, so the two runs differ only by what is listed above.

## Headline

| Measure | Before | After |
|---|---|---|
| Answers the app can decode (valid JSON) | 90 / 90 (100.0%) | 90 / 90 (100.0%) |
| Exactly the asked keys, right types | 90 / 90 (100.0%) | 90 / 90 (100.0%) |
| **All 13 fields correct** | 57 / 90 (63.3%) | 85 / 90 (94.4%) |
| Fields correct | 1115 / 1170 (95.3%) | 1165 / 1170 (99.6%) |
| Wrong fields | 55 / 1170 (4.7%) | 5 / 1170 (0.4%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 87 (96.7%) | 90 (100.0%) | hallucinated 3 | - |
| `operatingIncome` | 90 (100.0%) | 90 (100.0%) | - | - |
| `netIncome` | 90 (100.0%) | 90 (100.0%) | - | - |
| `eps` | 87 (96.7%) | 90 (100.0%) | hallucinated 3 | - |
| `interestExpense` | 90 (100.0%) | 90 (100.0%) | - | - |
| `operatingCashFlow` | 84 (93.3%) | 90 (100.0%) | hallucinated 6 | - |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 78 (86.7%) | 90 (100.0%) | hallucinated 9, unreadable 3 | - |
| `previousYearNetIncome` | 80 (88.9%) | 85 (94.4%) | hallucinated 6, unreadable 4 | hallucinated 2, unreadable 3 |
| `previousYearEps` | 90 (100.0%) | 90 (100.0%) | - | - |
| `revenueGrowth` | 87 (96.7%) | 90 (100.0%) | unreadable 3 | - |
| `netIncomeGrowth` | 81 (90.0%) | 90 (100.0%) | hallucinated 3, unreadable 6 | - |
| `epsGrowth` | 81 (90.0%) | 90 (100.0%) | hallucinated 3, unreadable 6 | - |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 33 (2.8%) | 2 (0.2%) |
| unreadable | 22 (1.9%) | 3 (0.3%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 52 |
| correct before, **wrong now** | 2 |
| wrong before and still wrong | 3 (of which 3 with another kind of mistake) |

Fixed, by field: `previousYearRevenue` 12, `netIncomeGrowth` 9, `epsGrowth` 9, `previousYearNetIncome` 7, `operatingCashFlow` 6, `revenueGrowth` 3, `revenue` 3, `eps` 3.

Broken, by field: `previousYearNetIncome` 2.

| Statement | Run | Field | Now |
|---|---|---|---|
| 25 | 1 | `previousYearNetIncome` | hallucinated |
| 25 | 3 | `previousYearNetIncome` | hallucinated |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 10.5 s | 12.0 s |
| Median time to first token | 3.68 s | 4.33 s |
| Median generated tokens | 122 | 121 |
| Median tokens per second | 20.6 | 16.9 |
| Peak MLX memory | 2.72 GiB | 2.86 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 16.4 min | 18.5 min |
