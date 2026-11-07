#!/usr/bin/env python3
"""Phase 2f, the PDF pilot (Specs/phase-2f-pdf-pilot.md). Standard library only; needs `pdftotext` (poppler) and `swift`
(for Scripts/pdf_pages.swift and Scripts/pdf_embed.swift). The model runs are a separate script, Scripts/lora/pdf_generate.py.

Nothing this script reads or writes from a report is committed: every output is in RealSet/pdf/ (git-ignored). The printed
output is counts only: no page text, no label, no answer.

  draw     --reports DIR             the seeded draw of 5 of the reports (P2); refuses to overwrite a frozen draw
  heldout  --reports DIR --out DIR   Phase 2g (T7): every report the pilot did not draw (--pilot, default RealSet/pdf), as the
                                     draw file of a new set; no choice is made; refuses to overwrite
  extract  --reports DIR             the text of every page of the drawn reports, with `pdftotext -layout` and with PDFKit (P8)
  retrieve                           the three retrievers (P9): keywords (BM25), embeddings (NLContextualEmbedding), hybrid
  recall                             recall at 3 of each retriever against the labelled pages, and the retriever chosen for C
  rows                               P8: the labelled rows found intact (label and number on one line), per extraction
  baseline --extraction X            P5: the code row matcher on the oracle pages, written as a prediction file
  inputs   --condition A|C --extraction X     the model inputs (one per page) for Scripts/lora/pdf_generate.py
  combine  --answers FILE --condition A|C --extraction X   the model's answers per page combined into one per report
  score    --pred FILE [--also F]  P6: counts of correct, unit, column, invented, missed, unparsed and wrong amounts;
                                     with --also, a second, separate count that also accepts the values of F
                                     ({"<report>": {"<key>": ["<decimal>", ...]}}), a sensitivity reading made in step 6
  kinds    --pred FILE               step 6: where each wrong or invented amount sits on its page (the labelled row or
                                     another row, and its column), counts only; the counts of `score` do not change
  fallback --pred R --model M       Phase 2g (T9): the reader's answers (R), with the model's (M, same pages, per seed) only
                                     where the reader left a field null; prints what the model adds, correct and confidently wrong
  gate     --pred NEW --old OLD      Phase 2h (R6): the development gate; fails (exit 1) if NEW loses an amount OLD read
                                     correctly, or shows any confidently wrong amount
  phoneset                           P7: the condition C pages of one report (the seeded spot-check report) as an external
                                     evaluation set for the app, RealSet/pdf/phone/pdfc/ (labels all null: time only)

All of them take --out (default RealSet/pdf). Fixed here before the draw, as the spec asks, where it left a detail open:
- The retrievers rank pages of the PDFKit text (the app's extraction) for the decision rule; the pdftotext text is ranked
  too and reported beside it.
- Condition C feeds the union of the top 3 pages for each of the two statements (at most 6 pages), in rank order.
- Combining (A and C): for each field, the first page in priority order that gives a readable value wins (A: income
  statement pages, then cash flow pages; C: by best rank). A field with two different readable values is a conflict, counted.
- A bare number takes the unit of its page header ("in millions"...); a number with a unit word is read by the app's
  parser rules (Scripts/real_set.py); `capex` and `interestExpense` are compared as magnitudes (schema: magnitude).
- A value is correct when it equals the label within half a unit of the last digit printed.

Labels (step 3), RealSet/pdf/labels.json, written by hand from the statements:
  {"<report file name>": {"pages": {"income": [page numbers, from 1], "cashflow": [...]},
                          "values": {"<key>": "<decimal, in dollars, or per share for EPS>" | null, ...}}}
"""
import argparse
import hashlib
import json
import math
import random
import re
import subprocess
import sys
from collections import Counter
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_set as rs  # noqa: E402  (the parser rules of the app)

SEED_PDF = 20261029            # fixed in the committed script before the draw
DRAWN = 5
TOP = 3
RRF_K = 60
BM25_K1, BM25_B = 1.5, 0.75
QUERIES = {
    "income": "consolidated statements of operations income net sales revenue operating income net income earnings per share",
    "cashflow": "consolidated statements of cash flows operating activities purchases of property and equipment capital expenditures",
}
EXTRACTIONS = ["pdfkit", "layout"]
PRIMARY = "pdfkit"
RETRIEVERS = ["keywords", "embeddings", "hybrid"]
TIE_ORDER = ["keywords", "hybrid", "embeddings"]           # the simpler one wins a tie (P9)
SCORED = ["revenue", "operatingIncome", "netIncome", "eps", "interestExpense", "operatingCashFlow", "capex",
          "previousYearRevenue", "previousYearNetIncome", "previousYearEps"]
GROWTH = ["revenueGrowth", "netIncomeGrowth", "epsGrowth"]
COUNTERPART = {"revenue": "previousYearRevenue", "previousYearRevenue": "revenue", "netIncome": "previousYearNetIncome",
               "previousYearNetIncome": "netIncome", "eps": "previousYearEps", "previousYearEps": "eps"}
STATEMENT_OF = {"operatingCashFlow": "cashflow", "capex": "cashflow"}       # every other scored key: income
SCHEMA = json.loads((ROOT / "Dataset" / "schema.json").read_text())
KIND = {f["key"]: f["kind"] for f in SCHEMA["fields"]}
MAGNITUDE = {f["key"] for f in SCHEMA["fields"] if f.get("magnitude")}
SCALE = {"thousands": Decimal(1000), "millions": Decimal(10) ** 6, "billions": Decimal(10) ** 9}
HEADER = re.compile(r"\bin\s+(thousands|millions|billions)\b|\b(thousands|millions|billions)\s+of\s+(?:u\.s\.\s+)?dollars\b", re.I)

# P5, the code baseline: row labels as they start a line of a statement (first match wins).
ROWS = {
    "revenue": [r"total net sales", r"total revenues?", r"net sales", r"total net revenues?", r"net revenues?", r"revenues?"],
    "operatingIncome": [r"operating income", r"income from operations", r"operating profit", r"total operating income"],
    "netIncome": [r"net income attributable to [\w .,&'-]+", r"net income", r"net earnings"],
    "eps": [r"diluted"],
    "interestExpense": [r"interest expense"],
    "operatingCashFlow": [r"net cash (?:provided by|from|generated by|provided by \(used in\)) operating activities",
                          r"cash generated by operating activities", r"net cash provided by operations"],
    "capex": [r"purchases of property(?:, plant)? and equipment", r"payments for acquisition of property, plant and equipment",
              r"capital expenditures", r"additions to property(?:, plant)? and equipment"],
}
NUMBER_TOKEN = re.compile(r"\(?\$?\s?\d{1,3}(?:,\d{3})+(?:\.\d+)?\)?|\(?\$?\s?\d+\.\d+\)?|\(?\$?\s?\d+\)?")


def out_dir(args):
    return Path(args.out)


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stem(name):
    return re.sub(r"[^A-Za-z0-9]+", "_", Path(name).stem).strip("_")


def load_json(path: Path):
    return json.loads(path.read_text())


def draw_file(out):
    return load_json(out / "draw.json")


# --- P2, the draw --------------------------------------------------------------------------------------------------
def draw(reports: Path, out: Path):
    target = out / "draw.json"
    if target.exists():
        sys.exit(f"{target} exists: the draw is frozen and is never redone")
    names = sorted(p.name for p in reports.glob("*.pdf"))
    if len(names) < DRAWN:
        sys.exit(f"only {len(names)} reports in {reports}")
    chosen = sorted(random.Random(SEED_PDF).sample(names, DRAWN))
    entries = [{"name": n, "sha256": sha256(reports / n)} for n in chosen]
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    out.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"seed": SEED_PDF, "from": len(names), "reports": entries, "hash": digest}, indent=1))
    print(f"drew {DRAWN} of {len(names)} reports with seed {SEED_PDF}; draw hash {digest[:12]} -> {target}")


def heldout(reports: Path, out: Path, pilot: Path):
    """Phase 2g, T7: the held-out set is every report the pilot did not draw, so nothing is chosen."""
    target = out / "draw.json"
    if target.exists():
        sys.exit(f"{target} exists: the held-out set is frozen and is never redone")
    pilot_draw = draw_file(pilot)
    drawn = {e["name"] for e in pilot_draw["reports"]}
    names = sorted(p.name for p in reports.glob("*.pdf") if p.name not in drawn)
    entries = [{"name": n, "sha256": sha256(reports / n)} for n in names]
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    out.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"rule": "every report the PDF pilot did not draw", "from": len(names) + len(drawn),
                                  "pilotDraw": pilot_draw["hash"], "reports": entries, "hash": digest}, indent=1))
    print(f"held out {len(names)} reports (every one the pilot did not draw); hash {digest[:12]} -> {target}")


# --- extraction (P8) --------------------------------------------------------------------------------------------------
def text_file(out, name, extraction):
    return out / "text" / f"{stem(name)}.{extraction}.json"


def pages_layout(pdf: Path):
    result = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], check=True, capture_output=True)
    pages = result.stdout.decode("utf-8", errors="replace").split("\f")
    if pages and not pages[-1].strip():
        pages = pages[:-1]
    return pages


def pages_pdfkit(pdf: Path, target: Path):
    subprocess.run(["swift", str(ROOT / "Scripts" / "pdf_pages.swift"), str(pdf), str(target)], check=True, capture_output=True)
    return load_json(target)


def extract(reports: Path, out: Path):
    (out / "text").mkdir(parents=True, exist_ok=True)
    for entry in draw_file(out)["reports"]:
        pdf = reports / entry["name"]
        if sha256(pdf) != entry["sha256"]:
            sys.exit(f"{entry['name']} changed since the draw")
        layout = pages_layout(pdf)
        text_file(out, entry["name"], "layout").write_text(json.dumps(layout, ensure_ascii=False))
        pdfkit = pages_pdfkit(pdf, text_file(out, entry["name"], "pdfkit"))
        print(f"{stem(entry['name'])}: pages layout {len(layout)}, pdfkit {len(pdfkit)}")


def pages_of(out, name, extraction):
    return load_json(text_file(out, name, extraction))


# --- P9, the retrievers -------------------------------------------------------------------------------------------------
def tokens(text):
    return re.findall(r"[a-z]+", text.lower())


def bm25(pages, query):
    docs = [Counter(tokens(p)) for p in pages]
    lengths = [sum(d.values()) for d in docs]
    average = (sum(lengths) / len(lengths)) if lengths and sum(lengths) else 1.0
    n = len(docs)
    scores = []
    for d, length in zip(docs, lengths):
        s = 0.0
        for term in set(tokens(query)):
            df = sum(1 for x in docs if term in x)
            if not df or term not in d:
                continue
            idf = math.log(1 + (n - df + 0.5) / (df + 0.5))
            tf = d[term]
            s += idf * tf * (BM25_K1 + 1) / (tf + BM25_K1 * (1 - BM25_B + BM25_B * length / average))
        scores.append(s)
    return scores


def ranking(scores):
    """Page numbers (from 1), best first; a tie keeps page order."""
    return [i + 1 for i in sorted(range(len(scores)), key=lambda i: (-scores[i], i))]


def fuse(*rankings):
    """Reciprocal rank fusion: score = sum of 1 / (RRF_K + rank)."""
    total = Counter()
    for r in rankings:
        for rank, page in enumerate(r, start=1):
            total[page] += 1.0 / (RRF_K + rank)
    pages = sorted(total)
    return [p for p in sorted(pages, key=lambda p: (-total[p], p))]


def embed_scores(out, name, extraction, pages):
    target = out / "embed" / f"{stem(name)}.{extraction}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    source = text_file(out, name, extraction)
    queries = out / "embed" / "queries.json"
    queries.write_text(json.dumps(QUERIES))
    if not target.exists():
        subprocess.run(["swift", str(ROOT / "Scripts" / "pdf_embed.swift"), str(source), str(queries), str(target)],
                       check=True, capture_output=True)
    result = load_json(target)
    for q in QUERIES:
        if len(result["scores"][q]) != len(pages):
            sys.exit(f"embedding scores of {name} do not match its pages")
    return result


def rank_all(pages, embedded):
    result = {}
    for q, query in QUERIES.items():
        keywords = ranking(bm25(pages, query))
        embeddings = ranking(embedded["scores"][q])
        result[q] = {"keywords": keywords, "embeddings": embeddings, "hybrid": fuse(keywords, embeddings)}
    return result


def retrieve(out: Path):
    for extraction in EXTRACTIONS:
        everything = {}
        for entry in draw_file(out)["reports"]:
            pages = pages_of(out, entry["name"], extraction)
            embedded = embed_scores(out, entry["name"], extraction, pages)
            everything[entry["name"]] = {"rankings": rank_all(pages, embedded), "embedSeconds": embedded["seconds"],
                                         "pages": len(pages)}
        (out / f"retrieval.{extraction}.json").write_text(json.dumps(everything, indent=1))
        seconds = sum(v["embedSeconds"] for v in everything.values())
        print(f"{extraction}: ranked {len(everything)} reports; embedding time {seconds:.1f} s in total")


# --- recall at 3 ---------------------------------------------------------------------------------------------------------
def labels_file(out):
    return load_json(out / "labels.json")


def recall_counts(retrieval, labels):
    """{retriever: {"hits": n, "cases": n, "ranks": [rank of the first true page per case]}}."""
    counts = {r: {"hits": 0, "cases": 0, "ranks": []} for r in RETRIEVERS}
    for name, label in labels.items():
        for q in QUERIES:
            true = set(label["pages"][q])
            for r in RETRIEVERS:
                order = retrieval[name]["rankings"][q][r]
                first = next((i + 1 for i, p in enumerate(order) if p in true), None)
                counts[r]["cases"] += 1
                counts[r]["hits"] += int(first is not None and first <= TOP)
                counts[r]["ranks"].append(first)
    return counts


def choose(counts):
    best = max(c["hits"] for c in counts.values())
    return next(r for r in TIE_ORDER if counts[r]["hits"] == best)


def found_both(retrieval, labels, retriever):
    """Reports for which a true page of both statements is in the retriever's top 3 (decision rule 1)."""
    return sum(1 for name, label in labels.items()
               if all(set(label["pages"][q]) & set(retrieval[name]["rankings"][q][retriever][:TOP]) for q in QUERIES))


def recall(out: Path):
    labels = labels_file(out)
    for extraction in EXTRACTIONS:
        retrieval = load_json(out / f"retrieval.{extraction}.json")
        counts = recall_counts(retrieval, labels)
        for r in RETRIEVERS:
            c = counts[r]
            print(f"{extraction:6s} {r:10s} recall at {TOP}: {c['hits']}/{c['cases']}; reports with both statements found: "
                  f"{found_both(retrieval, labels, r)}/{len(labels)}; first true page rank {c['ranks']}")
        if extraction == PRIMARY:
            print(f"chosen for condition C (on {PRIMARY}): {choose(counts)}")


# --- values and scoring (P6) --------------------------------------------------------------------------------------------
def header_unit(page_text):
    m = HEADER.search(page_text)
    return (m.group(1) or m.group(2)).lower() if m else None


def read_value(text, key, page_text):
    """The value of an answer as a Decimal (dollars, or per share), or None if it cannot be read."""
    if text is None:
        return None
    body = str(text).strip().strip("\"'").rstrip(".,;:")
    kind = KIND[key]
    match = rs.PATTERN.match(body.replace("(", "").replace(")", "").replace("−", "-").replace("–", "-"))
    if not match:
        return None
    if kind == "amount":
        value = rs.parse_value(body, "amount")
        if value is None:
            return None
        value = value * Decimal(10) ** 9                 # the parser reads amounts in billions
        if not match["u"]:                               # a bare number: the unit of the page header
            value = value * SCALE.get(header_unit(page_text), Decimal(1))
    else:
        value = rs.parse_value(body, kind)
        if value is None:
            return None
    return abs(value) if key in MAGNITUDE else value


def tolerance(text, key, page_text):
    body = str(text).replace("(", "").replace(")", "")
    match = rs.PATTERN.match(body.strip().strip("\"'").rstrip(".,;:"))
    digits = match["n"] if match else "0"
    decimals = len(digits.split(".")[1]) if "." in digits else 0
    place = Decimal(10) ** -decimals
    if KIND[key] == "amount":
        unit = (match["u"] or "").lower() if match else ""
        if unit:
            place = place * rs.FACTOR.get(unit, Decimal(1)) * Decimal(10) ** 9
        else:
            place = place * SCALE.get(header_unit(page_text), Decimal(1))
    return place / 2


def classify(key, answer, labels, pages):
    """One of: correct, unit, column, invented, missed, unparsed, wrong."""
    label = labels.get(key)
    if answer is None:
        return "correct" if label is None else "missed"
    if label is None:
        return "invented"
    page_text = pages[answer["page"] - 1] if answer.get("page") else ""
    value = read_value(answer["text"], key, page_text)
    if value is None:
        return "unparsed"
    truth = Decimal(label)
    if key in MAGNITUDE:
        truth = abs(truth)
    tol = tolerance(answer["text"], key, page_text)
    if abs(value - truth) <= tol:
        return "correct"
    other = labels.get(COUNTERPART.get(key, ""))
    if other is not None:
        o = Decimal(other)
        if abs(value - o) <= tol:
            return "column"
    if value != 0 and KIND[key] == "amount":
        for factor in (Decimal(1), Decimal(1000), Decimal(10) ** 6, Decimal(10) ** 9, Decimal("0.001")):
            for ratio in (factor, 1 / factor):
                if abs(value * ratio - truth) <= tol * ratio:
                    return "unit"
    return "wrong"


def score_runs(pred, labels, out):
    totals = Counter()
    growth_invented = 0
    stated = 0
    for run in pred["runs"]:
        for name, label in labels.items():
            pages = pages_of(out, name, pred["extraction"])
            answers = run["answers"].get(name, {})
            for key in SCORED:
                totals[classify(key, answers.get(key), label["values"], pages)] += 1
                stated += int(label["values"].get(key) is not None)
            growth_invented += sum(1 for key in GROWTH if answers.get(key) is not None and label["values"].get(key) is None)
    correct_stated = totals["correct"] - sum(
        1 for run in pred["runs"] for name, label in labels.items() for key in SCORED
        if label["values"].get(key) is None and run["answers"].get(name, {}).get(key) is None)
    return totals, stated, correct_stated, growth_invented


def score(path: Path, out: Path, also_path=None):
    pred = load_json(path)
    labels = load_json(out / "labels.json")
    totals, stated, correct_stated, growth_invented = score_runs(pred, labels, out)
    share = 100.0 * correct_stated / stated if stated else 0.0
    order = ["correct", "unit", "column", "invented", "missed", "unparsed", "wrong"]
    print(f"{pred['condition']} {pred['extraction']} runs {len(pred['runs'])}: "
          + ", ".join(f"{k} {totals[k]}" for k in order)
          + f"; stated amounts correct {correct_stated}/{stated} ({share:.1f}%); conflicts {pred.get('conflicts', 0)}; "
          f"growth invented {growth_invented}; undecodable {pred.get('undecodable', 0)}")
    if also_path:
        lenient = also_correct(pred, labels, load_json(Path(also_path)), out)
        print(f"  sensitivity, also accepting {Path(also_path).name}: stated amounts correct {lenient}/{stated} "
              f"({100.0 * lenient / stated if stated else 0.0:.1f}%)")


# --- step 6: where the wrong answers sit, and a sensitivity reading (counts only; the counts of `score` stay) ---------
def digits_of(text):
    """A number as printed, without sign, currency or parentheses: '$(1,360)' -> '1,360'."""
    m = re.search(r"\d[\d,]*(?:\.\d+)?", str(text))
    return m.group(0).rstrip(",") if m else None


def printed_label(key, label, page_text):
    """The labelled value as a statement prints it: in the unit of the page header, or per share."""
    value = abs(Decimal(label))
    if KIND[key] != "amount":
        return str(value)
    value = value / SCALE.get(header_unit(page_text), Decimal(1))
    return f"{int(value):,}" if value == value.to_integral_value() else None


def where(key, answer, label, pages):
    """(row, column) of an answer on its page. row: "labelled row" (its number is on a line that also prints the label),
    "another row", or "not on the page"; column: the position of its number among the numbers of that line (1 is the
    first number, the current year in these statements), None when it is not on the page."""
    page_text = pages[answer["page"] - 1] if answer.get("page") else ""
    digits = digits_of(answer["text"])
    found = []
    for line in page_text.splitlines():
        cells = [digits_of(c) for c in numbers(line)]
        if digits in cells:
            found.append((cells, cells.index(digits) + 1))
    if not found:
        return "not on the page", None
    printed = printed_label(key, label, page_text) if label is not None else None
    for cells, column in found:
        if printed and printed in cells:
            return "labelled row", column
    return "another row", found[0][1]


def kinds(path: Path, out: Path):
    pred = load_json(path)
    labels = load_json(out / "labels.json")
    counts = Counter()
    for run in pred["runs"]:
        for name, label in labels.items():
            pages = pages_of(out, name, pred["extraction"])
            for key in SCORED:
                answer = run["answers"].get(name, {}).get(key)
                category = classify(key, answer, label["values"], pages)
                if category in ("wrong", "invented"):
                    group = "previous year" if key.startswith("previousYear") else "current year"
                    counts[(category, group) + where(key, answer, label["values"].get(key), pages)] += 1
    print(f"{pred['condition']} {pred['extraction']} runs {len(pred['runs'])}: wrong and invented amounts by where they sit")
    for (category, group, row, column), n in sorted(counts.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[0][2], kv[0][3] or 0)):
        print(f"  {category:8s} {group:13s} {row:15s} column {column if column else '-'}: {n}")


def also_correct(pred, labels, also, out):
    """Stated amounts correct when an answer may also equal one of the values of `also` for its report and key."""
    count = 0
    for run in pred["runs"]:
        for name, label in labels.items():
            pages = pages_of(out, name, pred["extraction"])
            answers = run["answers"].get(name, {})
            for key in SCORED:
                if label["values"].get(key) is None:
                    continue
                options = [label["values"][key]] + also.get(name, {}).get(key, [])
                count += any(classify(key, answers.get(key), dict(label["values"], **{key: v}), pages) == "correct"
                             for v in options)
    return count


# --- P5, the code baseline, and P8, the rows ----------------------------------------------------------------------------
def numbers(line):
    found = []
    for token in NUMBER_TOKEN.findall(line):
        bare = token.replace("$", "").replace("(", "").replace(")", "").strip()
        if re.fullmatch(r"(19|20)\d\d", bare):            # a year in a column header
            continue
        if token.startswith("(") and token.endswith(")") and re.fullmatch(r"\d", bare):
            continue                                       # a footnote marker
        found.append(token.replace("$", "").replace(" ", ""))
    return found


def match_row(pages, page_numbers, key):
    for pattern in ROWS[key]:
        rx = re.compile(r"^\s*" + pattern + r"\b[^\d(]*", re.I)
        for p in page_numbers:
            for line in pages[p - 1].splitlines():
                m = rx.match(line)
                if not m:
                    continue
                values = numbers(line[m.end():])
                if key == "eps":
                    values = [v for v in values if "." in v]
                if values:
                    return p, values
    return None, []


def baseline_answers(pages, label):
    answers = {}
    for key in ROWS:
        statement = STATEMENT_OF.get(key, "income")
        page, values = match_row(pages, label["pages"][statement], key)
        answers[key] = {"text": values[0], "page": page} if values else None
        previous = COUNTERPART.get(key) if key in ("revenue", "netIncome", "eps") else None
        if previous:
            answers[previous] = {"text": values[1], "page": page} if len(values) > 1 else None
    return answers


def baseline(extraction, out: Path):
    labels = labels_file(out)
    answers = {name: baseline_answers(pages_of(out, name, extraction), label) for name, label in labels.items()}
    target = out / f"pred.baseline.{extraction}.json"
    target.write_text(json.dumps({"condition": "A-code", "extraction": extraction, "runs": [{"seed": 0, "answers": answers}]}))
    print(f"wrote {target}")


def rows(out: Path):
    labels = labels_file(out)
    for extraction in EXTRACTIONS:
        intact = 0
        for name, label in labels.items():
            pages = pages_of(out, name, extraction)
            for key in ROWS:
                if label["values"].get(key) is None:
                    continue
                _, values = match_row(pages, label["pages"][STATEMENT_OF.get(key, "income")], key)
                intact += int(bool(values))
        print(f"{extraction}: labelled rows found with their number on the same line: {intact}")


# --- model inputs and combining ---------------------------------------------------------------------------------------
def condition_pages(condition, name, label, retrieval, chosen):
    """Pages in priority order."""
    if condition == "A":
        return list(dict.fromkeys(label["pages"]["income"] + label["pages"]["cashflow"]))
    picked = []
    for rank in range(TOP):
        for q in QUERIES:
            page = retrieval[name]["rankings"][q][chosen][rank]
            if page not in picked:
                picked.append(page)
    return picked


def chosen_retriever(out):
    counts = recall_counts(load_json(out / f"retrieval.{PRIMARY}.json"), labels_file(out))
    return choose(counts)


def inputs(condition, extraction, out: Path):
    labels = labels_file(out)
    retrieval = load_json(out / f"retrieval.{extraction}.json") if condition == "C" else None
    chosen = chosen_retriever(out) if condition == "C" else None
    template = (ROOT / "Dataset" / "prompt_template.txt").read_text().rstrip("\n")
    system = (ROOT / "Dataset" / "system_prompt.txt").read_text().strip()
    target = out / f"inputs.{condition}.{extraction}.jsonl"
    count = 0
    with target.open("w") as f:
        for name, label in labels.items():
            pages = pages_of(out, name, extraction)
            for priority, page in enumerate(condition_pages(condition, name, label, retrieval, chosen)):
                messages = [{"role": "system", "content": system},
                            {"role": "user", "content": template.replace("<<STATEMENT>>", pages[page - 1])}]
                f.write(json.dumps({"report": name, "page": page, "priority": priority, "messages": messages}) + "\n")
                count += 1
    print(f"wrote {count} inputs -> {target}" + (f" (retriever {chosen})" if chosen else ""))


def combine_answers(per_page, pages):
    """per_page: [(page, {key: text | None})] in priority order -> ({key: {"text", "page"} | None}, conflicts)."""
    combined, conflicts = {}, 0
    for key in SCORED + GROWTH:
        seen = []
        for page, answer in per_page:
            text = answer.get(key)
            if text is None:
                continue
            value = read_value(text, key, pages[page - 1]) if key in SCORED else text
            if value is None:
                continue
            seen.append((page, text, value))
        combined[key] = {"text": seen[0][1], "page": seen[0][0]} if seen else None
        conflicts += int(len({v for _, _, v in seen}) > 1)
    return combined, conflicts


def combine(answers_path: Path, condition, extraction, out: Path):
    rows_ = [json.loads(line) for line in answers_path.read_text().splitlines() if line.strip()]
    keys = SCORED + GROWTH
    runs, conflicts, undecodable = [], 0, 0
    for seed in sorted({r["seed"] for r in rows_}):
        answers = {}
        for name in dict.fromkeys(r["report"] for r in rows_):
            pages = pages_of(out, name, extraction)
            mine = sorted((r for r in rows_ if r["seed"] == seed and r["report"] == name), key=lambda r: r["priority"])
            per_page = []
            for r in mine:
                try:
                    decoded = json.loads(r["answer"])
                    if not isinstance(decoded, dict) or set(decoded) != set(rs.schema_keys()):
                        raise ValueError
                except (ValueError, TypeError):
                    undecodable += 1
                    continue
                per_page.append((r["page"], {k: decoded.get(k) for k in keys}))
            answers[name], c = combine_answers(per_page, pages)
            conflicts += c
        runs.append({"seed": seed, "answers": answers})
    target = out / f"pred.{condition}.{extraction}.json"
    target.write_text(json.dumps({"condition": condition, "extraction": extraction, "runs": runs,
                                  "conflicts": conflicts, "undecodable": undecodable}))
    print(f"wrote {target}: runs {len(runs)}, conflicts {conflicts}, undecodable {undecodable}")


# --- Phase 2g: the reader with the model filling its nulls (T9) -----------------------------------------------------
WRONG = ("wrong", "column", "unit", "invented")


def fallback_runs(reader, model):
    """One run per model seed: each field is the reader's answer, or the model's when the reader's is null."""
    base = reader["runs"][0]["answers"]
    runs = []
    for run in model["runs"]:
        answers = {}
        for name, mine in base.items():
            theirs = run["answers"].get(name, {})
            answers[name] = {key: mine.get(key) if mine.get(key) is not None else theirs.get(key) for key in SCORED + GROWTH}
        runs.append({"seed": run["seed"], "answers": answers})
    return runs


def fallback(reader_path: Path, model_path: Path, out: Path):
    reader, model = load_json(reader_path), load_json(model_path)
    if reader["extraction"] != model["extraction"]:
        sys.exit("the reader and the model must read the same extraction")
    labels = labels_file(out)
    runs = fallback_runs(reader, model)
    tag = reader["condition"].split("-")[-1]
    target = out / f"pred.fallback.{tag}.{reader['extraction']}.json"
    target.write_text(json.dumps({"condition": f"fallback-{tag}", "extraction": reader["extraction"], "runs": runs}))
    before, _, correct_before, _ = score_runs(reader, labels, out)
    after, _, correct_after, _ = score_runs({"extraction": reader["extraction"], "runs": runs}, labels, out)
    seeds = len(runs)
    added_correct = correct_after - correct_before * seeds
    added_wrong = sum(after[k] for k in WRONG) - sum(before[k] for k in WRONG) * seeds
    print(f"wrote {target}: over {seeds} seeds the model adds {added_correct} correct and {added_wrong} confidently wrong amounts "
          f"to the reader's nulls")


def gate_counts(new, old, labels, out):
    """(gained, lost, wrong): stated amounts OLD missed and NEW reads, stated amounts OLD read and NEW does not, and the
    confidently wrong amounts of NEW (on stated and null labels)."""
    gained = lost = wrong = 0
    for name, label in labels.items():
        pages = pages_of(out, name, new["extraction"])
        for key in SCORED:
            after = classify(key, new["runs"][0]["answers"].get(name, {}).get(key), label["values"], pages)
            before = classify(key, old["runs"][0]["answers"].get(name, {}).get(key), label["values"], pages)
            if label["values"].get(key) is not None:
                gained += int(before != "correct" and after == "correct")
                lost += int(before == "correct" and after != "correct")
            wrong += int(after in WRONG)
    return gained, lost, wrong


def gate(new_path: Path, old_path: Path, out: Path):
    gained, lost, wrong = gate_counts(load_json(new_path), load_json(old_path), labels_file(out), out)
    passed = lost == 0 and wrong == 0
    print(f"gate {'passes' if passed else 'FAILS'}: amounts gained {gained}, lost {lost}, confidently wrong {wrong}")
    return passed


# --- P7, the phone timing run ------------------------------------------------------------------------------------------
PHONE_SET = "pdfc"


def phone_report(out):
    """The report the draw's seed picked for the spot-check: no report is chosen by hand."""
    return random.Random(SEED_PDF).choice([e["name"] for e in draw_file(out)["reports"]])


def phoneset(out: Path):
    """The condition C pages of one report (PDFKit text, the app's extraction) in the format of an external set:
    <name>.jsonl (the chat file, the core prompt around each page), <name>.labels.jsonl, index.csv. Every label is null:
    P7 measures the time on the phone, not the answers, so the accuracy counts of the phone report are not a result."""
    name = phone_report(out)
    rows_ = [json.loads(line) for line in (out / f"inputs.C.{PRIMARY}.jsonl").read_text().splitlines() if line.strip()]
    mine = sorted((r for r in rows_ if r["report"] == name), key=lambda r: r["priority"])
    folder = out / "phone" / PHONE_SET
    folder.mkdir(parents=True, exist_ok=True)
    chat, side, index = [], [], ["split,line,source,scenario,pool,unit,distractors"]
    for line, r in enumerate(mine, start=1):
        messages = r["messages"] + [{"role": "assistant", "content": json.dumps({k: None for k in rs.schema_keys()}, indent=2)}]
        chat.append(json.dumps({"messages": messages}, ensure_ascii=False))
        side.append(json.dumps({"line": line, "fields": rs.g.full_label({})}, ensure_ascii=False))
        index.append(f"{PHONE_SET},{line},page-{r['page']},pdf,real,-,-")
    (folder / f"{PHONE_SET}.jsonl").write_text("\n".join(chat) + "\n")
    (folder / f"{PHONE_SET}.labels.jsonl").write_text("\n".join(side) + "\n")
    (folder / "index.csv").write_text("\n".join(index) + "\n")
    digest = hashlib.sha256((folder / f"{PHONE_SET}.jsonl").read_bytes() + (folder / f"{PHONE_SET}.labels.jsonl").read_bytes())
    print(f"wrote {len(mine)} pages -> {folder}; set hash (chat + labels) {digest.hexdigest()[:12]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["draw", "heldout", "extract", "retrieve", "recall", "rows", "baseline", "inputs", "combine", "score",
                                            "kinds", "phoneset", "fallback", "gate"])
    parser.add_argument("--reports", default=str(Path.home() / "Downloads" / "Reports"))
    parser.add_argument("--out", default=str(ROOT / "RealSet" / "pdf"))
    parser.add_argument("--extraction", choices=EXTRACTIONS, default=PRIMARY)
    parser.add_argument("--condition", choices=["A", "C"])
    parser.add_argument("--answers")
    parser.add_argument("--pred")
    parser.add_argument("--also")
    parser.add_argument("--model")
    parser.add_argument("--old")
    parser.add_argument("--pilot", default=str(ROOT / "RealSet" / "pdf"))
    args = parser.parse_args()
    out = out_dir(args)
    if args.command == "draw":
        draw(Path(args.reports), out)
    elif args.command == "heldout":
        heldout(Path(args.reports), out, Path(args.pilot))
    elif args.command == "extract":
        extract(Path(args.reports), out)
    elif args.command == "retrieve":
        retrieve(out)
    elif args.command == "recall":
        recall(out)
    elif args.command == "rows":
        rows(out)
    elif args.command == "baseline":
        baseline(args.extraction, out)
    elif args.command == "inputs":
        inputs(args.condition, args.extraction, out)
    elif args.command == "combine":
        combine(Path(args.answers), args.condition, args.extraction, out)
    elif args.command == "score":
        score(Path(args.pred), out, args.also)
    elif args.command == "kinds":
        kinds(Path(args.pred), out)
    elif args.command == "phoneset":
        phoneset(out)
    elif args.command == "fallback":
        fallback(Path(args.pred), Path(args.model), out)
    elif args.command == "gate":
        sys.exit(0 if gate(Path(args.pred), Path(args.old), out) else 1)


if __name__ == "__main__":
    main()
