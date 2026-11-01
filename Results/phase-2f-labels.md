# Phase 2f, step 3: the draw and the labels (counts only)

Spec: `Specs/phase-2f-pdf-pilot.md` (P2, P3). The reports, their text and the labels are private (`RealSet/pdf/`, git-ignored); this file holds counts and hashes only.

- **Draw:** 5 of the 17 annual reports, seed 20261029 (fixed in `Scripts/pdf_pilot.py` before the draw, commit b3dad25), draw hash `3fa0b7354977`, done on 2026-10-29. The reports have 80, 125, 140, 280 and 295 pages; both extractions (`pdftotext -layout` and PDFKit) give the same page count for every report.
- **Labels:** written by hand from the statement of operations (or income) and the statement of cash flows of each report, one page each, before any model or retriever run; `labels.json` sha256 `c087c0da286b`.
  - **50 amounts** (10 per report), **45 stated** and **5 null** (an operating income not printed in 2 reports, an interest expense not printed in 3). The three growth fields are null in all 5 (no percent on the statement pages).
  - Units: 4 reports in millions, 1 in thousands.
  - The page header gives the unit on **8 of the 10 statement pages** in a form the fixed rule reads as a table unit; on one income page it is read only through a share-count phrase ("in millions of shares"), which happens to be correct, and **one cash flow page prints no unit at all**. By the rule fixed before the draw (P6) a bare number on that page cannot be scored correct; it is reported, not fixed.
- **Spot-check:** one report, chosen by the draw's seed, was checked by the user: asked whether its 10 labels are right, the user answered "Go" (2026-10-31); no label changed.
- **Disclosed:** the 17 reports were partly read for `real1` to `real3` (prose paragraphs of the management discussion); the statement pages were not used before. The statement pages were located by their titles and confirmed by reading.
