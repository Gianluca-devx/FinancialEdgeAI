# Spec: Phase 2h, the statement table reader, second round

Status: **APPROVED by the user on 2026-11-06** (written 2026-11-06 at the user's request). The decisions are mine, each with the alternative.
Depends on `v2.7.0`: Phase 2g (`Specs/phase-2g-table-reader.md`, `Results/phase-2g-analysis.md`), whose decision rule gave
"improve": 81.2% of the stated amounts on the whole path, 0 confidently wrong, on 12 reports the reader was not written for.

**Goal:** close the gaps Phase 2g named, and measure the reader again, with the **same decision rule**, on **reports neither the
reader nor its labels have seen**, which the user supplies. The phase gives a build, improve or stop decision for the reader.

**Out of scope:** the app (PDF import, UI), the prompt, the schema, the parser, the adapter, the evaluation code, the model (its result
on statement pages is established: 53.3% and 55.7% on 17 reports), the fallback (it adds as many wrong amounts as correct ones), the
balance sheet fields, training, the phone.

## What Phase 2g showed, and what this round changes

All 21 misses of Phase 2g's whole path were nulls with a named cause; none was a wrong value. They are the list of changes, fixed here
before any new development:

| Phase 2g miss (on C) | Count | The change (R2) |
|---|---|---|
| A loss year: "Operating loss", "Net loss", one "Basic and diluted" EPS row; the page then not recognised | 7 | loss forms of the income rows (R3); a combined "basic and diluted" row read as diluted |
| "Consolidated net income attributable to ..." | 2 | "consolidated" ignored at the start of a row label, as in titles |
| "Net cash from operations" | 1 | more operating cash flow forms |
| Capex lines named "Investment in ...", "Purchases related to ...", "Payments for property and equipment" | 3 | more capex forms; the broader lines (with intangibles, or net) as a second level, used only when no strict line is printed (the labelling choice the user agreed in Phase 2g) |
| Cash flow titles in the form "... cash flows statements" | 3 | the title in either word order |
| Two capex lines with different values (discontinued operations, financing, supplemental) | 3 | capex read only inside the investing section (R4) |
| A note reference inside a row ("(Note 12)") | 2 | a note reference read as part of the label, never as a cell |

One change comes from a risk, not a miss: **the reader does not look at the currency.** A statement "in millions of euros" would give
"X million", which the app's `ValueParser` reads as dollars. That is a wrong amount waiting for the first report in another currency
(R5).

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| R1 | **The development set is all 17 labelled reports** (the pilot's 5 and Phase 2g's 12), with their frozen labels, unchanged. They have been read, so none of them can be a test again. | Keeping the 12 as a test: they were read to sort the misses; a fix written now would be tuned to them. |
| R2 | **The changes are the ones in the table above, and only those.** A further change found while developing on the 17 is allowed only if it fixes a counted miss of the 17, comes with a test, and is disclosed. | Any change that helps: the rules would follow the development reports, the overfitting Phase 2g measured as small. |
| R3 | **Loss rows:** "operating loss", "loss from operations", "net loss", "net loss attributable to ..." are the field's rows; a number in parentheses is negative, as printed. A loss row whose number has **no** parentheses is **null**: some statements print a loss as a positive number under a "loss" label, others in parentheses, and the number alone cannot tell. | Taking the word "loss" as the sign: right for one style, a wrong sign (a wrong amount) for the other. |
| R4 | **Capex only inside the investing section:** the first matching row between the investing activities header and its total; a matching row outside it (discontinued operations, financing, supplemental lines) is ignored. If the page has no investing header, the Phase 2g rule applies (two different values give null). | Keeping the null on duplicates: safe, but it loses capex in 3 of 17 reports. |
| R5 | **Currency guard:** a unit phrase that names another currency (euro, pound, yen, franc, krona, yuan, won, rupee, peso, real, or a symbol other than $) gives no unit, so every amount of that page is null. | Converting: the app reads dollars only, and a rate is outside the statements. |
| R6 | **A development gate before the freeze:** on the 17 reports, the changed reader must keep **0 confidently wrong amounts** and must **not lose any amount** that Phase 2g's reader read correctly. A change that fails it is dropped, and that is disclosed. | No gate: a new rule could fix one report and break another, and the test would find it too late. |
| R7 | **The new held-out set:** every report the user supplies that (a) is an annual report PDF with a text layer, (b) prints its statements in US dollars, and (c) belongs to a company **not among the 17** (another year of the same company shares its layout). No draw. The check is a script run before any statement page is read; excluded reports are listed with their reason. **At least 10 qualifying reports.** With fewer, the user decides between bringing more and a smaller test, disclosed as such. | Any report: a second year of the same company would test the same layout twice; a report in euros cannot be scored in dollars (it is used for the R5 check instead, below). |
| R8 | **Labels by Phase 2g's rules (T8), with the judgement calls the user agreed there:** interest expense null without a line of its own; a broader capex line when it is the statement's only one; losses as negative values. Frozen by hash before the run; the user spot-checks one report, chosen by the pilot's seed. | New rules: the two rounds would not compare. |
| R9 | **The same conditions and scorer as Phase 2g:** A (true pages) and C (the whole path), PDFKit, the pilot's scorer unchanged, "confidently wrong" as before. The sensitivity reading is reported again. No model run. | Running the model again: about 15 minutes, but its result on statement pages is already established twice. |
| R10 | **The currency check:** any report the user supplies in another currency is run through the reader too, and every amount it gives must be null. Counted and reported; not part of the decision rule. | No check: R5 would be tested only on made-up text. |

## Decision rule (the same as Phase 2g, fixed before the held-out run)

Over the new held-out reports, condition C, PDFKit:

1. **Build** (the next spec puts PDF import with this reader into the app): correct on **at least 85%** of the stated amounts, and
   **confidently wrong on at most 3%** of the labelled amounts.
2. **Improve:** correct on 70% to 85%, or at least 85% with more confidently wrong amounts than rule 1 allows.
3. **Stop this path:** correct on less than 70%.
4. **Reported in every case:** A and C on the 17 development reports and on the new ones; the misses by kind; the currency check
   (R10); the sensitivity reading; the reader's time per report on the Mac.

If the rule gives "improve" a second time, the analysis sets out the choice between a third round and building with the reader's
nulls shown in the app as "not found"; the decision is the user's.

## Steps (branch `feature/table-reader-2`, each one commit)

1. **GATE: the user approves this spec.**
2. **The changes and their tests** (`feat`, `test`): each change of R2 to R5 with a Swift test and a tamper test (a loss row with and
   without parentheses, a combined EPS row, "consolidated net income attributable to", a note reference, each title order, a capex
   row inside and outside the investing section, a statement in euros). Then the reader on the 17 development reports, A and C, and
   the development gate R6 (`eval`, counts only).
3. **Freeze, then the new reports** (`data`): record the reader's commit and file hashes **before** any new report is extracted. Then
   the inclusion check (R7), extraction, the keyword ranking, the labels (R8, checked by script against their pages), the spot-check.
4. **The held-out run** (`eval`, counts only): A and C, and the currency check.
5. **Analysis** against the decision rule, README, PR to `main` after the user's go (`docs`).

## What the user supplies

Annual reports as PDF files in a new folder, `~/Downloads/Reports2` (kept apart from the 17 in `~/Downloads/Reports`): at least 10,
of companies not among the 17, with their statements in US dollars (a US 10-K is the simplest case). Reports in another currency are
welcome for the currency check but do not count toward the 10. Nothing in the folder is opened before the freeze of step 3.

## Cost

About 3 to 5 days of my work: the changes and their tests a day or two, labelling about 100 to 120 amounts a day or two, the run and
the analysis half a day. Mac compute: minutes. No phone, no training.

## Acceptance

1. The reader's commit and hashes are recorded before any new report is read; the labels are frozen before the run; the decision rule
   is the one above, unchanged.
2. Each change of R2 to R5 has a test and a tamper test; the development gate R6 passes, or a dropped change is disclosed.
3. A and C have their counts by category on the 17 development reports and on the new ones; the currency check is reported.
4. No report text, page or answer is committed, and no company is named; counts only.
5. A written conclusion says which rule applies and why.

## Risks

- **The new reports may bring forms none of the 22 known reports had.** That is what the test measures; they are counted as nulls and
  named.
- **Ten or so reports are again a small test**, and the result may land near a threshold again; a borderline result is reported as
  borderline.
- **The labeller is the developer**, as before; the freeze order and the spot-check limit it.
- **R4 depends on finding the investing section's header and total**; a statement without them falls back to the Phase 2g rule.
- **PDFKit on iOS may differ from macOS**; still not checked here (the integration spec, after a build).
