# Spec: Phase 1b, the extended call

Status: **approved by delegation** on 2026-10-16 (the user asked to continue without stopping for approvals;
the decisions below are mine, with the alternative). Depends on `Specs/phase-0-metrics.md` (D3) and
`Specs/phase-1-schema-prompt.md`. In `CLAUDE.local.md` it is step 3 of the order of work, before LoRA.

**Goal:** the user taps a button next to the text field and gets the five balance sheet fields of the same
statement, and with them the four derived values that need them (return on equity, debt to equity, current
ratio, net debt). The extended call is measured on its own, like the core call.

**Out of scope:** LoRA; any change to the core prompt, the core fields, the statements or the test split
(the schema 1 baseline stays valid and comparable); extracting the extended fields automatically with every
answer; the overview and business sections.

**Inputs:** `Dataset/schema.json` (5 extended fields, already labelled in the sidecars), the schema 1 baseline.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D8 | The extended prompt has its own file, `Dataset/prompt_template_extended.txt`, rendered from the schema by `prompt_from_schema.py` (the extended fields, rules 1 to 3 of the core prompt without the growth rule). The system message is shared. | Adding the fields to the core prompt: that is what D3 ruled out, it changes the core baseline. |
| D9 | The extended call is **independent of the core call**: same statement, its own prompt, nothing chained. | Passing the core answer into the second prompt: longer, couples the two measurements. |
| D10 | The button is next to Sample and Send. It runs on the **last statement sent** (the view model keeps it, the field is cleared after Send). It is disabled until a statement has been sent and while a call runs. | A toggle that adds the extended call to every Send: doubles the cost of every answer. |
| D11 | The extended fields are shown in their own group, and the derived values that need them appear as soon as the inputs exist. An unreadable string is shown with a warning, like in the core group. | |
| D12 | Same generation settings (temperature 0.2, `maxTokens` 384, a fresh chat session, thinking off). | A lower token limit: not needed, the answer is about 60 tokens. |
| D13 | The Evaluate tab gets a picker, core or extended. The same 30 statements, 3 runs and seeds are used, the extended fields are judged against the sidecar. A report records its `tier` and `keys`. A report without a `tier` is a core report. | A separate screen: more code for the same thing. |
| D14 | Chat files for the extended task are generated from the sidecars: `train.extended.jsonl`, `valid.extended.jsonl`, `test.extended.jsonl`. The statements are the same, so every core file stays **byte-identical**. They are what a later LoRA step would train on. | Regenerating the dataset: it would change the core test split. |

## Design

- **Prompt and dataset:** `prompt_from_schema.py` renders either tier. `generate_dataset.py` writes the
  extended prompt and the three extended chat files, and touches nothing else. The validator checks the
  extended prompt against the schema, the extended labels against their statements (verbatim), and the
  bundled copies (`prompt_template_extended.txt`, `test.extended.jsonl`).
- **Swift:** `Schema` knows the keys of a tier. `MetricsParser` takes the tier it parses (the keys it demands).
  `ExtractionPrompt` has the extended prompt. `LLMService.generate(statement:tier:)`. `EvaluationMetrics`
  and `EvaluationRunner` judge the keys of a tier. `FinancialMetrics` can be merged (core and extended).
- **View model and screen:** `ChatViewModel` keeps the last statement and the extended outcome.
  `MetricsPresenter` builds the extended rows and shows the derived rows whose inputs are there.
- **Tests:** the extended prompt renders from the schema and asks only the extended keys; the parser demands
  the extended keys for the extended tier and rejects a core key; the oracle tests also cover the extended
  labels (the parser against the true values, the dataset's own extended answers score 100%); the presenter
  shows the four derived values once the extended fields are there; evaluation per tier.

## UI / UX

States of the extended group: not asked (the button is available after a first Send), running (progress),
done (five rows, null visible, derived rows added), a string that cannot be read (a warning row, the others
stay), an error (the same alert as the core call). Starting a new Send clears the extended group.

## Acceptance

1. Every core file is byte-identical to `v2.0.0` (`git diff v2.0.0 --stat` shows no change to `Dataset/{train,valid,test}.jsonl`, the core prompt, `index.csv`, the labels, `schema.json`).
2. `validate_dataset.py` passes, including the extended prompt and files.
3. All tests pass on the simulator, including the extended oracle tests.
4. The app builds without warnings in the files touched.
5. The extended baseline runs on the iPhone: every answer decodable, report saved under a new name with the
   hashes and `tier`, a written analysis. The core baseline of v2.0.0 is not re-run: its prompt did not change.

## Risks

- The extended prompt is new text: a result measured with it is a new experiment with its own baseline.
- Balance sheet items are in 3 or 4 test statements each, so one field's accuracy is a rough indication.
- The core test split is also used here (same statements), so nothing new is held out for the extended task.
- The UI states cannot be tapped from here (the Xcode device tools only offer simulators): they are covered
  by presenter tests and by building the app.

## Steps (each one commit)

1. Prompt and dataset: render the extended tier, generate the extended files, validator (`data`).
2. Swift core of the call: tier in `Schema`, `MetricsParser`, `ExtractionPrompt`, `LLMService` (`feat`, `test`).
3. Presenter, view model and screen (`feat`, `test`).
4. Evaluation per tier: runner, view model, picker, report, summary script (`feat`, `test`).
5. The extended baseline on the iPhone (needs the phone unlocked), results, analysis, README (`eval`, `docs`).
6. Merge into `dev`, PR to `main`, tag after the merge.

**Branch and commits:** `feature/extended-call`; `data`, `feat`, `test`, `eval`, `docs`. No attribution lines.
Never stage `xcshareddata/` or `xcuserdata/`.
