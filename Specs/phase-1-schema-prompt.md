# Spec: Phase 1, schema and prompt experiment

Status: **approved** on 2026-10-16. Depends on `Specs/phase-0-metrics.md`.

**Goal:** the app extracts the 13 core fields as copied strings, code turns them into numbers and derives the
rest, and the unmodified model is measured once on the iPhone with the new schema.

**Out of scope:** the extended call and its button, LoRA, overview and business sections, PDF input, any prompt
rule beyond the ones below (for example "ignore guidance").

**Inputs:** `Specs/phase-0-metrics.md`; v1.1.0 results (kept untouched).

## Design

- **`Dataset/schema.json`:** `fields` (key, tier, kind, label, description) for the 18 extracted fields, and
  `derived` (key, label, kind, inputs). It is the only field list.
- **Prompt:** `Scripts/generate_dataset.py` writes `prompt_template.txt` from the schema, so the field list
  cannot drift. The system message is unchanged. The user prompt keeps its current structure, with these rules:
  1. Return ONLY valid JSON, no Markdown, no explanations.
  2. Every value is a string copied exactly as printed in the text, with its currency symbol, unit word and
     sign, for example `"$726 million"`, `"23.5%"`. Use `null` if the value is not in the text.
  3. Do not calculate, convert or round anything.
  4. Growth fields: only if the text states the percent change. Write a decrease with a leading minus (`"-4%"`).
  5. Use exactly this JSON structure (the 13 core keys, each `null`).
- **Code, new pure files:** `Schema`, `ValueParser` (string to number), `Derivations` (the formula table).
- **Code, changed:** `FinancialMetrics` keyed by field name. `MetricsParser` checks strings or null against the
  schema. `ExtractionExample`, `DatasetLoader` and `EvaluationMetrics` read the schema instead of 7 hardcoded
  keys. `FieldOutcome` gets one new case, for a string the parser cannot read. `maxTokens` becomes 384.
- **Dataset:** the generator gains EPS, interest expense, operating cash flow, capex, previous-year revenue and
  EPS, and balance sheet sentences. Chat labels are the 13 core strings. A sidecar `labels.jsonl` per split
  holds all 18 fields, each as printed string plus true value, so the parser is checked against ground truth,
  not against itself.
- **Evaluation:** judges the parsed core fields against the true values. It also records whether the string was
  copied verbatim. Derived values are covered by unit tests only.

## UI / UX

The Extract tab shows the 13 core rows with null visible, then a "Derived" group with each row flagged derived.
Derived rows whose inputs need the extended tier (ROE, debt-to-equity, current ratio, net debt) are not shown
until that exists. A string that cannot be parsed shows the raw text with a warning on its row, and the other
rows still appear. The loading, error and Retry states stay as they are.

## Tests

- `ValueParser`: every unit word, commas, currency symbols, percent, parentheses, a leading minus, and an
  unparseable string.
- `Derivations`: each formula, null inputs, zero denominator, negative previous value.
- Oracle: for every line of every split, the parsed label strings equal the sidecar values.
- Schema: the key list matches the prompt and the parser, and every core key has a UI row.
- `MetricsParser` and `EvaluationMetrics` tests updated.
- Simulator for all of it; the baseline run is on the iPhone (the user runs it, the agent gives the steps).

## Acceptance

1. `validate_dataset.py` passes: every non-null label string appears verbatim in its statement, the prompt's
   field list matches the schema, and the drift check is green for the bundled prompt, schema, test split and
   index.
2. All unit tests pass on the simulator, including the oracle test.
3. Every answer of the iPhone run is decodable. The report records `maxTokens` 384 and the prompt, schema and
   test-set hashes.
4. New results are saved under new names. `git diff` shows no change to the v1.1.0 files.
5. A written comparison with v1.1.0 covers fully correct, fields correct, error categories, tokens/s, time and
   peak memory, with the caveat that only the overlapping fields are comparable.

## Risks

- The test split changes, so the old numbers are history only (gate at step 4).
- More fields may lower per-field accuracy for a 4B model. That is what the baseline measures.
- New pure files must be added to the test target (symlinks) and registered in the Xcode project through the
  Xcode MCP.
- Time per statement is an estimate (about 10.8 s) until measured.

## Steps (each one commit, in this order)

1. `schema.json` and `Schema`, with tests and the drift check (`feat`, `test`).
2. `ValueParser` and `Derivations`, with tests (`feat`, `test`).
3. The generator writes the prompt from the schema, and the validator is updated. The dataset is not
   regenerated yet (`data`).
4. **GATE:** tell the user the planned dataset size and the test split size, with options, before regenerating,
   because the train, valid and test split changes and the old results stop being comparable. Then regenerate
   (`data`).
5. The switch-over: `FinancialMetrics`, `MetricsParser`, loader, evaluation, view model and UI use the schema
   (`feat`, `test`).
6. Run the tests, check the oracle test, and give the user the iPhone steps. The user runs the baseline.
7. Save the results and write the comparison (`eval`, `experiment`, `docs`). Then merge into `dev`, open the PR
   to `main`, and tag.

**Branch and commits:** `feature/metrics-schema`, cut from `dev`. Commit types: `feat`, `data`, `test`,
`experiment`, `eval`, `docs`. Each diff is shown to the user before committing. Never stage `xcshareddata/` or
`xcuserdata/`.
