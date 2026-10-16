# Spec: Phase 0, the metrics and the output format

Status: **approved** on 2026-10-16. Design only: no code, prompt, dataset or schema changed by this spec.
Baseline v1.1.0 (`Results/`) is kept as history and is not the reference for Phase 2 any more: Phase 1 produces
the new baseline.

**Goal:** the final field set, units and rules are fixed once, so the dataset, the baseline and LoRA all depend
on one schema.

**Out of scope:** share price (so no P/E or P/B), multi-year history, currency conversion (non-USD text is not
handled), header-only units ("in millions"), the extended-call prompt and its button (built later, but their
fields are defined now), the overview and business sections.

**Inputs:** the v1.1.0 baseline (`Results/baseline-analysis.md`), the value-investor metric research, decisions D1 to D7.

## Decisions

| | Decision |
|---|---|
| D1 | The model only extracts what is printed. Code derives the rest. The printed value wins, code fills only what is null, and the app flags derived numbers. |
| D2 | 12 inputs from the value-investor research, no share price. Core: 7. Extended: 5. |
| D3 | The extended tier is a second call with its own prompt, on the user's request (a button next to the text field). The core prompt and baseline stay untouched. All fields are defined in the schema now. |
| D4 | Growth set A: previous-year amount and printed growth for revenue, net income and EPS. The core is 13 fields. `operatingIncomeGrowth` of the old baseline is dropped. |
| D5 | The model copies each value as printed, as a string. A deterministic parser in code converts it. No `unit` field. |
| D6 | The field list lives once in `Dataset/schema.json`, with a bundled copy and a drift check. `FinancialMetrics` is keyed by field name. |
| D7 | One call for the 13 core fields, an optional call for the 5 extended ones. `maxTokens` goes from 256 to 384. |

## The 13 core fields (one call, every answer)

The model returns each value as a string copied exactly as printed, or `null`. It never calculates.

| Field | Meaning | Statement | Parsed to |
|---|---|---|---|
| `revenue` | total revenue or net sales, current period | income | amount (billions USD) |
| `operatingIncome` | operating income or operating profit; EBIT if that is the operating figure printed | income | amount |
| `netIncome` | net income, profit or earnings | income | amount |
| `eps` | earnings per share, diluted if both are printed | income | USD per share |
| `interestExpense` | interest expense | income | amount, positive |
| `operatingCashFlow` | net cash from operating activities | cash flow | amount |
| `capex` | purchases of property, plant and equipment | cash flow | amount, positive |
| `previousYearRevenue` | same as `revenue`, prior period | income | amount |
| `previousYearNetIncome` | same as `netIncome`, prior period | income | amount |
| `previousYearEps` | same as `eps`, prior period | income | USD per share |
| `revenueGrowth` | percent change, only if printed | income | percent |
| `netIncomeGrowth` | percent change, only if printed | income | percent |
| `epsGrowth` | percent change, only if printed | income | percent |

## The 5 extended fields (second call, on the user's request)

| Field | Meaning | Statement | Parsed to |
|---|---|---|---|
| `totalDebt` | total borrowings as printed | balance sheet | amount |
| `shareholdersEquity` | total shareholders' equity | balance sheet | amount |
| `currentAssets` | total current assets | balance sheet | amount |
| `currentLiabilities` | total current liabilities | balance sheet | amount |
| `cash` | cash and cash equivalents | balance sheet | amount |

## Derived by code (the model never writes these)

| Metric | Formula |
|---|---|
| `revenueGrowth`, `netIncomeGrowth`, `epsGrowth` when null | (current − previous) ÷ \|previous\| × 100 |
| operating margin, net margin | operatingIncome ÷ revenue × 100, netIncome ÷ revenue × 100 |
| free cash flow | operatingCashFlow − capex |
| interest coverage | operatingIncome ÷ interestExpense |
| ROE, debt-to-equity | netIncome ÷ shareholdersEquity × 100, totalDebt ÷ shareholdersEquity |
| current ratio, net debt | currentAssets ÷ currentLiabilities, totalDebt − cash |

Any derived value is null if an input is null or a denominator is 0. The app marks derived numbers as derived.

## Output rules

- The JSON has exactly the keys of `Dataset/schema.json`, nothing else. A value that is not in the text is
  `null`, never guessed or calculated.
- The parser handles unit words (thousand, million, billion, bn, mn), commas, currency symbols, percent signs,
  and parentheses as negative. A string it cannot parse is flagged as such, never guessed.
- Losses are negative. `interestExpense` and `capex` are positive magnitudes, whatever sign is printed.
- Where more than one number fits a field, the one that matches the field's definition. Net income "attributable
  to shareholders" wins over the total if both are printed.

## Design

- **Schema:** `Dataset/schema.json` is the only field list: key, tier, kind, label, description. A bundled copy in
  the app gets a drift check, like the prompt's.
- **Layers:** raw strings from the model, then `FinancialMetrics`, keyed by field name, with numbers.
- **Prompt:** the field list is generated from the schema. Rules 7 and 8 are rewritten as "copy as printed,
  never calculate". `maxTokens` is 384.
- **Dataset:** regenerated once with all 18 extracted fields labelled, so the extended baseline later needs no
  data change. Labels become the printed strings plus the parsed values.

## UI / UX

The Extract tab shows every core field, with null fields visible rather than hidden, and derived numbers marked
as derived. The extended button comes later, with its own spec.

## Tests

- Parser: every unit word, parentheses, percent, an unparseable string.
- Derivations: each formula, null inputs, a zero denominator.
- The oracle test, with the new labels.
- A check that every schema key has a UI row and a parser path.

All of these run on the simulator.

## Acceptance (Phase 0)

- Every metric has a definition, a source statement, a unit, a null rule and a tier.
- The one-call design and the extensible schema are decided.
- Approved by the user.

## Risks

- The dataset and the test split change, so the v1.1.0 baseline can no longer be compared with the new one
  (only a few fields exist in both, and only as an indication). Phase 1 step 3 is a gate for that reason.
- The model must copy strings reliably. The baseline's "wrong line" error is not fixed by this design, and
  Phase 1 measures it.
- Time and token numbers are estimates until measured: core about 10.8 s, extended about +5.7 s, core about
  180 tokens.
