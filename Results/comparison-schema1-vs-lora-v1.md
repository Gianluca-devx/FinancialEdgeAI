## What changed between the two runs

|  | Before | After |
|---|---|---|
| Report | `baseline-schema1-Qwen3-4B-4bit-iphone-20261016T114216.json` | `lora-v1-Qwen3-4B-4bit-iphone-20261016T153448.json` |
| Adapter | none (the base model) | lora-v1: rank 8, 16 layers, weights `aadab981fed8` |
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
| **All 13 fields correct** | 57 / 90 (63.3%) | 78 / 90 (86.7%) |
| Fields correct | 1115 / 1170 (95.3%) | 1155 / 1170 (98.7%) |
| Wrong fields | 55 / 1170 (4.7%) | 15 / 1170 (1.3%) |

## Field by field

| Field | Correct before | Correct after | Mistakes before | Mistakes after |
|---|---|---|---|---|
| `revenue` | 87 (96.7%) | 90 (100.0%) | hallucinated 3 | - |
| `operatingIncome` | 90 (100.0%) | 90 (100.0%) | - | - |
| `netIncome` | 90 (100.0%) | 84 (93.3%) | - | missed 6 |
| `eps` | 87 (96.7%) | 90 (100.0%) | hallucinated 3 | - |
| `interestExpense` | 90 (100.0%) | 90 (100.0%) | - | - |
| `operatingCashFlow` | 84 (93.3%) | 87 (96.7%) | hallucinated 6 | missed 3 |
| `capex` | 90 (100.0%) | 90 (100.0%) | - | - |
| `previousYearRevenue` | 78 (86.7%) | 87 (96.7%) | hallucinated 9, unreadable 3 | missed 3 |
| `previousYearNetIncome` | 80 (88.9%) | 90 (100.0%) | hallucinated 6, unreadable 4 | - |
| `previousYearEps` | 90 (100.0%) | 90 (100.0%) | - | - |
| `revenueGrowth` | 87 (96.7%) | 90 (100.0%) | unreadable 3 | - |
| `netIncomeGrowth` | 81 (90.0%) | 87 (96.7%) | hallucinated 3, unreadable 6 | missed 3 |
| `epsGrowth` | 81 (90.0%) | 90 (100.0%) | hallucinated 3, unreadable 6 | - |

## Mistakes, over all fields of all answers

| Kind | Before | After |
|---|---|---|
| hallucinated | 33 (2.8%) | 0 (0.0%) |
| missed | 0 (0.0%) | 15 (1.3%) |
| unreadable | 22 (1.9%) | 0 (0.0%) |

## What moved, answer by answer

| Of the same answers (same statement, same run) | Fields |
|---|---|
| wrong before, **correct now** | 55 |
| correct before, **wrong now** | 15 |
| wrong before and still wrong | 0 (of which 0 with another kind of mistake) |

Fixed, by field: `previousYearRevenue` 12, `previousYearNetIncome` 10, `netIncomeGrowth` 9, `epsGrowth` 9, `operatingCashFlow` 6, `revenueGrowth` 3, `revenue` 3, `eps` 3.

Broken, by field: `netIncome` 6, `operatingCashFlow` 3, `netIncomeGrowth` 3, `previousYearRevenue` 3.

| Statement | Run | Field | Now |
|---|---|---|---|
| 6 | 1 | `netIncome` | missed |
| 6 | 2 | `netIncome` | missed |
| 6 | 3 | `netIncome` | missed |
| 8 | 1 | `operatingCashFlow` | missed |
| 8 | 2 | `operatingCashFlow` | missed |
| 8 | 3 | `operatingCashFlow` | missed |
| 17 | 1 | `netIncomeGrowth` | missed |
| 17 | 2 | `netIncomeGrowth` | missed |
| 17 | 3 | `netIncomeGrowth` | missed |
| 25 | 1 | `netIncome` | missed |
| 25 | 1 | `previousYearRevenue` | missed |
| 25 | 2 | `netIncome` | missed |
| 25 | 2 | `previousYearRevenue` | missed |
| 25 | 3 | `netIncome` | missed |
| 25 | 3 | `previousYearRevenue` | missed |

## What it cost on the device

| Measure | Before | After |
|---|---|---|
| Median time per statement | 10.5 s | 11.6 s |
| Median time to first token | 3.68 s | 3.80 s |
| Median generated tokens | 122 | 120 |
| Median tokens per second | 20.6 | 18.1 |
| Peak MLX memory | 2.72 GiB | 2.86 GiB |
| Highest thermal state (0 nominal, 3 critical) | 2 | 2 |
| Generation time in total | 16.4 min | 18.5 min |
