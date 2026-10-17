#!/usr/bin/env python3
"""Build the real-style evaluation set from annual reports (Specs/phase-2b-lora-wording.md, D28). Standard library only;
needs `pdftotext` (poppler).

Nothing this script reads or writes from the reports is committed: its outputs are in /RealSet/ (git-ignored).

  python3 Scripts/real_set.py select --reports ~/Downloads/Reports --out RealSet
      Extracts the text of every PDF, applies the selection rule of the spec (never by reading: a seeded draw) and
      writes RealSet/passages.json: [{"id", "filing", "kind", "text"}]. Nothing is labelled here.

  python3 Scripts/real_set.py build --out RealSet
      Reads RealSet/labels.json ({"<id>": {"<core key>": "<string as printed>" | null, ...}}) written by hand from the
      passages, checks every label appears in its passage and is read by the parser rules to a number, and writes the
      three files of an external evaluation set: RealSet/real/real.jsonl, real.labels.jsonl, index.csv. The folder
      is what is copied to the phone: Documents/EvalSets/real/.

  python3 Scripts/real_set.py check --out RealSet
      Prints the counts of the frozen set (statements, fields stated, hashes). Nothing from the text.
"""
import argparse
import hashlib
import json
import random
import re
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

import generate_dataset as g

SEED = 20261017
KEYWORDS = ["revenue", "net sales", "net income", "net earnings", "operating income", "income from operations",
            "operating profit", "earnings per share", "cash provided by operating", "capital expenditures",
            "interest expense"]
AMOUNT = re.compile(r"\$\s?\d[\d,.]*\s?(million|billion|thousand)\b", re.I)
ABBREVIATIONS = ("U.S.", "Inc.", "Co.", "Corp.", "No.", "vs.", "Ltd.", "St.")
CORE = g.CORE


def extract(pdf: Path, out: Path):
    if not out.exists():
        subprocess.run(["pdftotext", "-nopgbrk", str(pdf), str(out)], check=True, capture_output=True)
    return out.read_text(errors="replace")


def region(text):
    """The Management's Discussion and Analysis part: from its second heading to Item 7A; the whole text if absent."""
    heads = [m.start() for m in re.finditer(r"item\s*7\.?\s*management[’']?s discussion", text, re.I)]
    if not heads:
        return text
    start = heads[1] if len(heads) > 1 else heads[0]
    end = re.search(r"item\s*7a", text[start:], re.I)
    return text[start:start + end.start()] if end else text[start:]


def paragraphs(text):
    for block in re.split(r"\n\s*\n", text):
        flat = re.sub(r"\s+", " ", block).strip()
        if flat:
            yield flat


def sentences(paragraph):
    parts, current = [], ""
    for token in paragraph.split(" "):
        current = f"{current} {token}".strip()
        if re.search(r"[.!?]$", token) and token not in ABBREVIATIONS and not re.search(r"\b[A-Z]\.$", token):
            parts.append(current)
            current = ""
    if current:
        parts.append(current)
    return parts


def prose(paragraph):
    return sum(c.isalpha() or c == " " for c in paragraph) / len(paragraph) >= 0.80


def shape(paragraph):
    words = len(paragraph.split())
    return 40 <= words <= 160 and len(sentences(paragraph)) >= 2 and prose(paragraph)


def has_keyword(paragraph):
    low = paragraph.lower()
    return any(k in low for k in KEYWORDS)


def candidates(text):
    """Paragraphs of the region; if the region has none of a kind (its heading was not found properly), the whole text."""
    def of(body):
        fields = [p for p in paragraphs(body) if shape(p) and AMOUNT.search(p) and has_keyword(p)]
        nones = [p for p in paragraphs(body) if shape(p) and re.search(r"\d", p) and not has_keyword(p)]
        return fields, nones
    fields, nones = of(region(text))
    if not fields or not nones:
        whole_fields, whole_nones = of(text)
        fields, nones = fields or whole_fields, nones or whole_nones
    return fields, nones


def cut(paragraph):
    parts = sentences(paragraph)
    return " ".join(parts[:6])


def select(reports: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    (out / "text").mkdir(exist_ok=True)
    pdfs = sorted(reports.glob("*.pdf"))
    ids = []
    pools = {}
    for pdf in pdfs:
        m = re.search(r"_(\d+)-", pdf.name)
        filing = m.group(1) if m else pdf.stem
        text = extract(pdf, out / "text" / f"{filing}.txt")
        pools[filing] = candidates(text)
        ids.append(filing)
    rng = random.Random(SEED)
    chosen = []
    for filing in ids:                       # draw 1: one paragraph with fields per filing, in filing order
        fields, _ = pools[filing]
        if fields:
            chosen.append((filing, "fields", cut(rng.choice(fields))))
        else:
            print(f"filing {filing}: no candidate paragraph with fields", file=sys.stderr)
    with_none = sorted(rng.sample(ids, 5))   # draw 2: which filings also give a paragraph with no field
    for filing in with_none:                 # draw 3: that paragraph, in filing order
        _, nones = pools[filing]
        if nones:
            chosen.append((filing, "nofield", cut(rng.choice(nones))))
    passages = [{"id": i + 1, "filing": f, "kind": k, "text": t} for i, (f, k, t) in enumerate(chosen)]
    (out / "passages.json").write_text(json.dumps(passages, indent=1, ensure_ascii=False))
    print(f"{len(passages)} passages ({sum(p['kind'] == 'fields' for p in passages)} with fields, "
          f"{sum(p['kind'] == 'nofield' for p in passages)} without) from {len(ids)} filings -> {out / 'passages.json'}")


# --- the parser rules, as in ValueParser.swift (checked against the Swift tests on the dataset) -------------------
NUMBER = r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+"
UNIT = r"thousand|million|billion|trillion|bn|mn|mm|tn|k|m|b|t|%|percent|per cent"
PATTERN = re.compile(r"^(?P<sb>[-+])?\s*(?P<cb>us\$|usd|\$)?\s*(?P<sa>[-+])?\s*(?P<n>" + NUMBER + r")\s*(?P<u>" + UNIT
                     + r")?\s*(?P<ca>dollars?|usd)?$", re.I)
FACTOR = {None: Decimal("0.000000001"), "thousand": Decimal("0.000001"), "k": Decimal("0.000001"),
          "million": Decimal("0.001"), "mn": Decimal("0.001"), "mm": Decimal("0.001"), "m": Decimal("0.001"),
          "billion": Decimal(1), "bn": Decimal(1), "b": Decimal(1), "trillion": Decimal(1000), "tn": Decimal(1000),
          "t": Decimal(1000)}
PERCENT_WORDS = {"%", "percent", "per cent"}


def parse_value(text, kind):
    body = text.strip().strip("\"'").rstrip(".,;:")
    negative = False
    if "(" in body or ")" in body:
        if body.count("(") != 1 or body.count(")") != 1 or body.index("(") > body.index(")"):
            return None
        body = body.replace("(", "").replace(")", "")
        negative = True
    m = PATTERN.match(body.replace("−", "-").replace("–", "-").replace("—", "-"))
    if not m:
        return None
    unit = m["u"].lower() if m["u"] else None
    digits = Decimal(m["n"].replace(",", ""))
    if kind == "amount":
        if unit in PERCENT_WORDS or unit not in FACTOR:
            return None
        value = digits * FACTOR[unit]
    elif kind == "percent":
        if m["cb"] or m["ca"] or (unit and unit not in PERCENT_WORDS):
            return None
        value = digits
    else:
        if unit:
            return None
        value = digits
    signs = [x for x in (m["sb"], m["sa"]) if x]
    if len(signs) > 1:
        return None
    if signs and signs[0] == "-":
        if negative:
            return None
        negative = True
    return -value if negative else value


def build(out: Path):
    schema = g.SCHEMA
    kinds = {f["key"]: f["kind"] for f in schema["fields"]}
    magnitude = {f["key"] for f in schema["fields"] if f.get("magnitude")}
    passages = {p["id"]: p for p in json.loads((out / "passages.json").read_text())}
    labels = json.loads((out / "labels.json").read_text())
    template = (g.DATASET / "prompt_template.txt").read_text().rstrip("\n")
    folder = out / "real"
    folder.mkdir(exist_ok=True)
    errors = []
    chat, side, index = [], [], ["split,line,source,scenario,pool,unit,distractors"]
    for line, (pid, passage) in enumerate(sorted(passages.items()), start=1):
        given = labels.get(str(pid))
        if given is None:
            errors.append(f"passage {pid}: no labels")
            continue
        if set(given) - set(CORE):
            errors.append(f"passage {pid}: unknown keys {sorted(set(given) - set(CORE))}")
        fields = {}
        for key in schema_keys():
            text = given.get(key)
            if text is None:
                fields[key] = None
                continue
            printed = text[1:] if kinds[key] == "percent" and text.startswith("-") else text
            if printed not in passage["text"]:
                errors.append(f"passage {pid}: {key}={text!r} is not in the passage")
            value = parse_value(text, kinds[key])
            if value is None:
                errors.append(f"passage {pid}: {key}={text!r} is not read by the parser rules")
                continue
            if key in magnitude:
                value = abs(value)
            fields[key] = {"text": text, "value": g.num(value)}
        label = {k: v for k, v in fields.items() if v}
        chat.append(json.dumps(g.render(passage["text"], label, template), ensure_ascii=False))
        side.append(json.dumps({"line": line, "fields": g.full_label(label)}, ensure_ascii=False))
        index.append(f"real,{line},filing-{passage['filing']},{'filing' if passage['kind'] == 'fields' else 'nofield'},real,-,-")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    (folder / "real.jsonl").write_text("\n".join(chat) + "\n")
    (folder / "real.labels.jsonl").write_text("\n".join(side) + "\n")
    (folder / "index.csv").write_text("\n".join(index) + "\n")
    check(out)


def schema_keys():
    return CORE


def check(out: Path):
    folder = out / "real"
    chat = (folder / "real.jsonl").read_bytes()
    labels = (folder / "real.labels.jsonl").read_bytes()
    rows = [json.loads(l)["fields"] for l in labels.decode().splitlines()]
    print(f"statements: {len(rows)}")
    for key in CORE:
        print(f"  {key:24s} stated in {sum(1 for r in rows if r[key])}")
    print("set hash (chat + labels), SHA-256:", hashlib.sha256(chat + labels).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["select", "build", "check"])
    parser.add_argument("--reports", type=Path)
    parser.add_argument("--out", type=Path, default=Path("RealSet"))
    args = parser.parse_args()
    if args.command == "select":
        if not args.reports:
            parser.error("select needs --reports")
        select(args.reports, args.out)
    elif args.command == "build":
        build(args.out)
    else:
        check(args.out)


if __name__ == "__main__":
    main()
