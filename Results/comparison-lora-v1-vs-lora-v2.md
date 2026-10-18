## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `lora-v1-Qwen3-4B-4bit-iphone-20261016T153448.json` | `lora-v2-Qwen3-4B-4bit-iphone-20261018T120711.json` |
| Adapter | lora-v1: rank 8, 16 layers, weights `aadab981fed8` | lora-v2: rank 8, 16 layers, weights `ffbdc621dc72` |
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
| **All 13 fields correct** | 78 / 90 (86.7%) | 85 / 90 (94.4%) |
| Fields correct | 1155 / 1170 (98.7%) | 1165 / 1170 (99.6%) |
| Wrong fields | 15 / 1170 (1.3%) | 5 / 1170 (0.4%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 90 (100.0%) | 90 (100.0%) | - | - |
| `operatingIncome` | 90 (100.0%) | 90 (100.0%) | - | - |
| `netIncome` | 84 (93.3%) | 90 (100.0%) | missed 6 | - |
| `eps` | 90 (100.0%) | 90 (100.0%) | - | - |
| `interestExpense` | 90 (100.0%) | 90 (100.0%) | - | - |
| `operatingCashFlow` | 87 (96.7%) | 90 (100.0%) | missed 3 | - |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 87 (96.7%) | 90 (100.0%) | missed 3 | - |
| `previousYearNetIncome` | 90 (100.0%) | 85 (94.4%) | - | hallucinated 2, unreadable 3 |
| `previousYearEps` | 90 (100.0%) | 90 (100.0%) | - | - |
| `revenueGrowth` | 90 (100.0%) | 90 (100.0%) | - | - |
| `netIncomeGrowth` | 87 (96.7%) | 90 (100.0%) | missed 3 | - |
| `epsGrowth` | 90 (100.0%) | 90 (100.0%) | - | - |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 0 (0.0%) | 2 (0.2%) |
| missed | 15 (1.3%) | 0 (0.0%) |
| unreadable | 0 (0.0%) | 3 (0.3%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 15 |
| correct before, **wrong now** | 5 |
| wrong before and still wrong | 0 (of which 0 with another kind of mistake) |

Fixed, by field: `netIncome` 6, `operatingCashFlow` 3, `netIncomeGrowth` 3, `previousYearRevenue` 3.

Broken, by field: `previousYearNetIncome` 5.

| Statement | Run | Field | Now |
|---|---|---|---|
| 13 | 1 | `previousYearNetIncome` | unreadable |
| 13 | 2 | `previousYearNetIncome` | unreadable |
| 13 | 3 | `previousYearNetIncome` | unreadable |
| 25 | 1 | `previousYearNetIncome` | hallucinated |
| 25 | 3 | `previousYearNetIncome` | hallucinated |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 11.6 s | 12.0 s |
| Median time to first token | 3.80 s | 4.33 s |
| Median generated tokens | 120 | 121 |
| Median tokens per second | 18.1 | 16.9 |
| Peak MLX memory | 2.86 GiB | 2.86 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 18.5 min | 18.5 min |
