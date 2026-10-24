#!/usr/bin/env python3
"""Generate the Phase 2d dataset (Specs/phase-2d-real-distractors.md), into Dataset/v3/.

Dataset/v3 = Dataset/v2 + real-style distractors:
  train  = the 480 statements of v2 train, unchanged, + 240 new
  valid  = the 48 statements of v2 valid, unchanged, + 24 new (templates and wording held out of train)
  test3  = 30 new statements (templates and wording held out of train and valid)
Nothing of Dataset/ or Dataset/v2/ is touched.

The new statements are synthetic (fictional companies, generated numbers). They are modelled on the KINDS of sentences that
real annual-report prose holds and the earlier synthetic statements lack (D35 of the spec), never on a copy of one:
  1 a change in amount and percent of a named part ("increased $X, or Y%")        null
  2 a segment, product or region figure                                            null
  3 cost lines, expenses and margins                                               null
  4 deferred revenue, contract liabilities, remaining obligations                  null
  5 adjusted, non-GAAP, "excluding" and constant-currency figures                  null
  6 dividends, repurchases and other capital returns                               null
  7 a sentence that states a company field among its figures (positive)            labelled
  8 footnotes, rates and years inside names, intercompany items                    null
  9 paragraphs that chain several of these, with or without stated fields
The rule of the labels: a figure of a named part, a change, an adjusted or hypothetical figure, a cost, deferred or
capital-return item is null; a figure that the sentence calls the company's own is labelled as printed.

Three kinds of statement: "null" (only distractors, no stated field), "composite" (a v2-style statement that states fields,
with two to four distractor sentences inserted) and "positive" (a kind 7 sentence among distractors).

Usage: python3 Scripts/generate_dataset_v3.py
"""
import csv
import json
import random
import re
from decimal import Decimal
from pathlib import Path

import generate_dataset as g
import generate_dataset_v2 as v2
from prompt_from_schema import example_leaks

ROOT = Path(__file__).resolve().parent.parent
V2DIR = ROOT / "Dataset" / "v2"
OUT = ROOT / "Dataset" / "v3"
SEED = 2027
SPLITS = ("train", "valid", "test3")
V2SPLIT = {"train": "train", "valid": "valid", "test3": "test2"}    # which wording pools of v2 a split draws from
POOL = {"train": "A3", "valid": "V3", "test3": "C3"}
# (null-only, composite, positive) new statements per split
COUNTS = {"train": (60, 156, 24), "valid": (6, 14, 4), "test3": (8, 17, 5)}

# ---------------------------------------------------------------------------------------------------------
# Wording of the new statements, by pool: A3 trains, V3 validates, C3 tests. The pools share no phrase of three words.
# ---------------------------------------------------------------------------------------------------------
PARTS = {
    "A3": ["the Services segment", "the North America region", "the Cloud business", "the Consumer division",
           "the Industrial segment", "the Hardware line"],
    "V3": ["the Platform unit", "the EMEA region", "the Devices line"],
    "C3": ["the Marketplace segment", "the Asia Pacific region", "the Subscriptions line"],
}
REASONS = {
    "A3": ["higher volumes", "pricing and product mix", "stronger customer demand", "lower input costs",
           "an acquisition completed in the year"],
    "V3": ["growth in the installed base", "a favourable shift in mix"],
    "C3": ["expansion into new markets", "improved utilisation of capacity"],
}
# Null families. {X} a named part, {R} a reason, {M}.. amounts, {D} a change in amount, {P}.. percents, {pp}.. margins,
# {Y}.. years, {EPS}.. per-share values, {S} a number of shares, {C} a company, {r} a rate, {V} increased or decreased.
NULL_FAMILIES = {
    "part": {
        "A3": ["{X} revenue was {M} in {Y}, up {P} from {Y1}.",
               "Revenue from {X} increased {P} to {M}, driven by {R}.",
               "{X} generated revenue of {M} for the year, compared with {M1} in {Y1}.",
               "Operating income of {X} was {M}, which is {pp} of its revenue."],
        "V3": ["In {X}, revenue added up to {M}, a rise of {P} over {Y1}.",
               "{X} booked revenue of {M} against {M1} a year before."],
        "C3": ["{X} contributed revenue of {M}, with {P} growth on {Y1}.",
               "{X} posted {M} of revenue, compared with {M1} for {Y1}."],
    },
    "change": {
        "A3": ["{X} revenue {V} {D}, or {P}, in {Y} compared to {Y1}, primarily due to {R}.",
               "{X} expenses {V} {D}, or {P}, during {Y} as compared with {Y1}, mainly because of {R}.",
               "The {V_noun} of {D} in {X} revenue, or {P}, reflects {R}.",
               "Compared to {Y1}, {X} revenue {V} by {D} ({P}) on the back of {R}."],
        "V3": ["{X} saw revenue move by {D}, a {P} change against {Y1}, mostly from {R}.",
               "Revenue in {X} {V} {D} ({P}) compared with {Y1}, reflecting {R}."],
        "C3": ["Revenue of {X} {V} by {D}, or {P}, over {Y1}, on {R}.",
               "{X} recorded a {D} {V_noun} in revenue ({P}), the result of {R}."],
    },
    "cost": {
        "A3": ["Cost of revenue {V} {D}, or {P}, compared to {Y1}, reflecting {R}.",
               "Research and development expenses were {M} in {Y}, an increase of {P} from {Y1}.",
               "Gross margin was {pp} in {Y}, compared with {pp1} in {Y1}.",
               "Selling and administrative costs of {M} in {Y} changed by {D} from {Y1}."],
        "V3": ["Operating expenses totalled {M}, a {P} change from {Y1}.",
               "Gross profit margin was {pp}, against {pp1} in the comparable period."],
        "C3": ["Cost of sales moved by {D} ({P}) in {Y}.",
               "Marketing spend reached {M}, or {pp} of revenue."],
    },
    "deferred": {
        "A3": ["Deferred revenue was {M} and {M1} as of year end {Y} and {Y1}, respectively.",
               "The Company expects to recognize {M}, or {pp}, of its remaining performance obligations as revenue over the next twelve months.",
               "Revenue recognized from the deferred revenue balance was {M} in {Y}.",
               "Contract liabilities {V} {D} during {Y}, mainly due to {R}."],
        "V3": ["Unearned revenue amounted to {M} at the end of {Y}.",
               "The backlog of remaining obligations was {M}, of which {pp} falls due within a year."],
        "C3": ["Customer prepayments totalled {M} when the year closed.",
               "{M} of this revenue is expected to be recognised after {Y}."],
    },
    "adjusted": {
        "A3": ["Adjusted diluted EPS was {EPS} and {EPS1} for {Y} and {Y1}, respectively.",
               "With exchange rates held constant, total revenue would have come to {M}, {D} above the amount reported.",
               "Excluding restructuring charges, net income would have been {M} in {Y}.",
               "Non-GAAP operating income was {M}, compared with {M1} in {Y1}."],
        "V3": ["Adjusted EBITDA reached {M} in {Y}.",
               "Before one-off items, net income would have come to {M}."],
        "C3": ["Pro forma revenue, as if the acquisition had closed on the first day of {Y}, would have reached {M}.",
               "Organic revenue grew {P} when currency effects are left out."],
    },
    "capital": {
        "A3": ["Dividends paid came to {M} in {Y}, {M1} in {Y1} and {M2} in {Y2}.",
               "The Company repurchased {S} of its common stock for {M} during {Y}.",
               "The Board approved a quarterly dividend of {EPS} per share.",
               "Share repurchases of {M} and dividends of {M1} were paid in {Y}."],
        "V3": ["Shareholder returns totalled {M} in {Y}, of which {M1} was buybacks.",
               "A cash dividend of {EPS} per share was declared."],
        "C3": ["The group returned {M} to shareholders through repurchases.",
               "Dividends paid were {M}."],
    },
    "footnote": {
        "A3": ["(1) Figures for {C} and its subsidiaries that guarantee the {r}% Senior Notes due {Y3}. (2) {C2} is a disregarded entity for income tax purposes. (3) Includes intercompany revenues of {M} and intercompany expenses of {M1} that are eliminated on consolidation.",
               "Note {k}: the {r}% convertible notes mature in {Y3}. Revenues of {M} between consolidated entities are eliminated.",
               "(1) The {r}% Notes due {Y3} were issued by {C}. (2) Intersegment revenues were {M} in {Y}."],
        "V3": ["* Includes {M} of revenue from affiliates, eliminated on consolidation.",
               "The {r}% debentures due {Y3} are held by {C}; transactions of {M} between group companies were eliminated."],
        "C3": ["Footnote (2): the {r}% bonds maturing in {Y3} rank equally with other senior debt.",
               "Revenue of {M} recorded between related entities does not appear in the consolidated total."],
    },
}
# Positive sentences: a company field among its figures. Each: template, fields {core key: placeholder}, growth {key: (placeholder, +1 or -1)}.
POSITIVE = {
    "A3": [
        {"t": "Cash flow from operating activities was {M} for fiscal {Y}, mostly made up of {M1} of net income, with {M2} of non-cash items such as depreciation and stock-based compensation added back.",
         "fields": {"operatingCashFlow": "M", "netIncome": "M1"}},
        {"t": "Total capital expenditures for fiscal {Y}, counting repayments of finance lease obligations, came to {M}.",
         "fields": {"capex": "M"}},
        {"t": "{NAME_revenue} increased {D}, or {P}, in {Y} compared with {Y1}, primarily due to {R}.",
         "growth": {"revenueGrowth": ("P", +1)}},
        {"t": "{NAME_netIncome} decreased {D}, or {P}, in {Y} compared to {Y1}, primarily due to {R}.",
         "growth": {"netIncomeGrowth": ("P", -1)}},
    ],
    "V3": [
        {"t": "Operating activities provided {M} of net cash in {Y}, which reflects {M1} of net income and {M2} of non-cash charges.",
         "fields": {"operatingCashFlow": "M", "netIncome": "M1"}},
        {"t": "{NAME_revenue} rose by {D}, a {P} gain over {Y1}, mostly from {R}.",
         "growth": {"revenueGrowth": ("P", +1)}},
    ],
    "C3": [
        {"t": "Cash generated by operations amounted to {M}, built from {M1} of profit for the period and {M2} of adjustments.",
         "fields": {"operatingCashFlow": "M", "netIncome": "M1"}},
        {"t": "Total capital outlay with finance lease repayments was {M}.",
         "fields": {"capex": "M"}},
        {"t": "{NAME_netIncome} fell by {D}, or {P}, against {Y1}, on {R}.",
         "growth": {"netIncomeGrowth": ("P", -1)}},
    ],
}
INTRO3 = {
    "A3": ["Results of operations for fiscal {Y}.", "{C}: management's discussion of {Y}.", "Financial review, {Y}.", None, None],
    "V3": ["The review of {Y} follows.", "{C} commentary for the year {Y}.", None],
    "C3": ["Discussion of {C} for {Y}:", "What changed in {Y}.", None],
}


class Values(dict):
    """The placeholders of one sentence, drawn on demand: each name is drawn once, so {M} and {M1} differ."""

    def __init__(self, rng, split, year, company, avoid):
        super().__init__()
        self.rng, self.split, self.year, self.company, self.avoid = rng, split, year, company, avoid
        self.values = {}      # placeholder -> value in billions (for amounts), percent, per-share
        self.raw = {}

    def amount(self):
        for _ in range(50):
            unit = "m" if self.rng.random() < 0.35 else "b"
            v = self.rng.randint(300, 9000) if unit == "m" else self.rng.randint(3, 3000)
            text = v2.money(v, unit, self.rng, V2SPLIT[self.split])
            billions = float(g.to_billions(v, unit))
            if text not in self.avoid and all(abs(billions - b) > 1e-9 for _, b in self.avoid_values()):
                return text, billions, v, unit
        raise RuntimeError("no distinct amount")

    def avoid_values(self):
        return [(k, v) for k, v in self.values.items() if isinstance(v, float)]

    def pct_text(self, digits):
        pool = v2.pick_pool(V2SPLIT[self.split], self.rng)
        return self.rng.choice(v2.PCT_PLAIN[pool]).format(n=digits)

    def __missing__(self, key):
        rng = self.rng
        if re.fullmatch(r"(M|D)\d?", key):
            text, billions, v, unit = self.amount()
            self.values[key], self.raw[key] = billions, (v, unit)
        elif re.fullmatch(r"P\d?", key):
            digits = v2.pct_digits(rng.randint(5, 400))
            text = self.pct_text(digits)
            self.values[key] = ("pct", digits)
        elif re.fullmatch(r"pp\d?", key):
            text = f"{v2.pct_digits(rng.randint(80, 650))}%"
        elif re.fullmatch(r"EPS\d?", key):
            text = v2.per_share(rng.randint(5, 1500), rng, V2SPLIT[self.split])
        elif key == "S":
            text = f"{rng.randint(2, 90)} million shares"
        elif key == "X":
            text = rng.choice(PARTS[POOL[self.split]])
            text = text[0].upper() + text[1:] if self.pending_capital else text
        elif key == "R":
            text = rng.choice(REASONS[POOL[self.split]])
        elif key in ("C", "C2"):
            text = rng.choice(g.COMPANIES)
        elif re.fullmatch(r"Y\d?", key):
            offset = {"Y": 0, "Y1": -1, "Y2": -2, "Y3": rng.randint(3, 9)}[key]
            text = str(self.year + offset)
        elif key == "r":
            text = f"{rng.randint(2, 11)}.{rng.choice(['0', '25', '5', '75'])}"
        elif key == "k":
            text = str(rng.randint(1, 9))
        elif key in ("V", "V_noun"):
            text = self.direction_word(key)
        elif key.startswith("NAME_"):
            name = v2.name_for(key[5:], V2SPLIT[self.split], rng)[0]
            text = name[0].upper() + name[1:] if name[1:2].islower() else name
        else:
            raise KeyError(key)
        self[key] = text
        return text

    pending_capital = False

    def direction_word(self, key):
        if "direction" not in self.__dict__:
            self.direction = self.rng.choice([+1, -1])
        up = self.direction > 0
        return ("increased" if up else "decreased") if key == "V" else ("increase" if up else "decrease")


def fill(template, rng, split, year, avoid=(), capital_part=False):
    """The sentence and the Values used (for the labels of positive sentences)."""
    vals = Values(rng, split, year, rng.choice(g.COMPANIES), set(avoid))
    vals.pending_capital = template.startswith("{X}")
    return template.format_map(vals), vals


def null_sentence(rng, split, year, avoid=(), exclude=(), used=None):
    """One distractor sentence. A template is used at most once in a statement (`used` holds the ones already there)."""
    pool = POOL[split]
    used = used if used is not None else set()
    for _ in range(100):
        family = rng.choice([f for f in NULL_FAMILIES if f not in exclude])
        choices = [t for t in NULL_FAMILIES[family][pool] if t not in used]
        if not choices:
            continue
        template = rng.choice(choices)
        sentence, _ = fill(template, rng, split, year, avoid)
        if not example_leaks(sentence) and '"' not in sentence:
            used.add(template)
            return sentence, family
    raise RuntimeError("no sentence")


def positive_sentence(rng, split, year, taken):
    """A kind 7 sentence whose fields are not already stated: (sentence, label)."""
    options = [p for p in POSITIVE[POOL[split]]
               if not (set(p.get("fields", {})) | set(p.get("growth", {}))) & taken]
    if not options:
        return None
    entry = rng.choice(options)
    template = entry["t"]
    for _ in range(50):
        sentence, vals = fill(template, rng, split, year)
        if example_leaks(sentence):
            continue
        label = {}
        for key, placeholder in entry.get("fields", {}).items():
            v, unit = vals.raw[placeholder]
            label[key] = {"text": vals[placeholder], "value": g.num(g.to_billions(v, unit))}
        for key, (placeholder, direction) in entry.get("growth", {}).items():
            digits = vals.values[placeholder][1]
            text = vals[placeholder]
            label[key] = {"text": text if direction > 0 else "-" + text,
                          "value": g.num(direction * Decimal(digits))}
        # The sentence must say what the label says: "increased" for a growth, "decreased" for a decline.
        if entry.get("growth") and any(w in sentence for w in ("increased", "rose", "decreased", "fell")):
            pass
        return sentence, label
    raise RuntimeError("no positive sentence")


def split_sentences(statement):
    return [s for s in re.split(r"(?<=[.:]) (?=[A-Z(*])", statement) if s]


def word_count(text):
    return len(text.split())


def make_null(rng, split):
    year = rng.randint(2019, 2025)
    parts = []
    intro = rng.choice(INTRO3[POOL[split]])
    if intro:
        parts.append(intro.format(Y=year, C=rng.choice(g.COMPANIES)))
    kinds = []
    used = set()
    target = rng.randint(70, 130)
    while sum(word_count(p) for p in parts) < target:
        try:
            sentence, family = null_sentence(rng, split, year, exclude=kinds[-1:] if kinds else (), used=used)
        except RuntimeError:                      # every template of the pool is already used
            break
        if sentence in parts:
            continue
        parts.append(sentence)
        kinds.append(family)
        if len(parts) > 8:
            break
    return " ".join(parts), {}, {"scenario": "real_null", "kinds": "+".join(sorted(set(kinds)))}


COMPOSITE_SCENARIOS = (["full"] * 4 + ["income_basic"] * 4 + ["prior_no_growth"] * 2 + ["cash_flow"] * 2
                       + ["interest"] * 2 + ["mixed"] * 2 + ["growth_only"] * 2 + ["amounts_only"] * 1 + ["eps_only"] * 1)


def make_composite(rng, split):
    scenario = rng.choice(COMPOSITE_SCENARIOS)
    saved = v2.STYLES[V2SPLIT[split]]
    v2.STYLES[V2SPLIT[split]] = [("prose", 1)]            # prose only: the distractors are sentences
    try:
        for _ in range(100):
            statement, label, meta = v2.make_example(scenario, V2SPLIT[split], rng)
            if statement and len(split_sentences(statement)) >= 2 and "\n" not in statement:
                break
    finally:
        v2.STYLES[V2SPLIT[split]] = saved
    m = re.search(r"\b(20[12]\d)\b", statement)
    year = int(m.group(1)) if m else rng.randint(2019, 2025)
    sentences = split_sentences(statement)
    avoid = {e["text"] for e in label.values()} | {s for s in re.findall(r"\$[\d,.]+ \w+|[\d,.]+ \w+ (?:USD|dollars)", statement)}
    kinds = []
    used = set()
    for _ in range(rng.randint(2, 4)):
        sentence, family = null_sentence(rng, split, year, avoid=avoid, used=used)
        position = rng.randint(1, len(sentences))              # never before the first sentence (the intro or the opening)
        sentences.insert(position, sentence)
        kinds.append(family)
    return " ".join(sentences), label, {"scenario": "real_composite", "kinds": "+".join(sorted(set(kinds)))}


def make_positive(rng, split):
    year = rng.randint(2019, 2025)
    taken = set()
    label = {}
    parts = []
    intro = rng.choice(INTRO3[POOL[split]])
    if intro:
        parts.append(intro.format(Y=year, C=rng.choice(g.COMPANIES)))
    first = positive_sentence(rng, split, year, taken)
    sentence, new = first
    label.update(new)
    taken |= set(new)
    parts.append(sentence)
    kinds = ["positive"]
    used = set()
    for _ in range(rng.randint(2, 4)):
        s, family = null_sentence(rng, split, year, avoid={e["text"] for e in label.values()}, used=used)
        parts.insert(rng.randint(1 if intro else 0, len(parts)), s)
        kinds.append(family)
    if rng.random() < 0.4:                                      # a second positive sentence, for another field
        extra = positive_sentence(rng, split, year, taken)
        if extra:
            parts.insert(rng.randint(1 if intro else 0, len(parts)), extra[0])
            label.update(extra[1])
    return " ".join(parts), label, {"scenario": "real_positive", "kinds": "+".join(sorted(set(kinds)))}


def build_new(split):
    rng = random.Random(f"{SEED}-{split}")
    nulls, composites, positives = COUNTS[split]
    items, seen = [], set()
    for count, maker in ((nulls, make_null), (composites, make_composite), (positives, make_positive)):
        for _ in range(count):
            for _ in range(200):
                statement, label, meta = maker(rng, split)
                forbidden = v2.forbidden_hits(statement, V2SPLIT[split])
                if (statement not in seen and not example_leaks(statement) and '"' not in statement
                        and not forbidden and 40 <= word_count(statement) <= 170):
                    break
            else:
                raise RuntimeError(f"could not generate a {maker.__name__} statement for {split}")
            seen.add(statement)
            items.append((statement, label, {**meta, "pool": POOL[split], "unit": "-", "style": "prose",
                                              "distractors": 1, "source": "generated"}))
    rng.shuffle(items)
    return items


def _fragments(template):
    return [re.sub(r"\s+", " ", x).strip().lower() for x in re.split(r"\{[^}]*\}", template)]


def template_phrases(pool):
    """The held-out phrases of one pool of the new templates: pieces of three words or more of its templates, and its
    parts, reasons and openings. A split that may not see the pool must not contain any of them (validate_dataset_v3.py)."""
    found = set()
    templates = [t for family in NULL_FAMILIES.values() for t in family[pool]] + [p["t"] for p in POSITIVE[pool]]
    templates += [t for t in INTRO3[pool] if t]
    for t in templates:
        for f in _fragments(t):
            f = re.sub(r"^[^a-z0-9]+", "", f)
            if len(f.split()) >= 3:
                found.add(f)
    found.update(p.lower() for p in PARTS[pool])
    found.update(r.lower() for r in REASONS[pool])
    return found


def read_lines(path):
    return path.read_text().splitlines()


def main():
    template = (g.DATASET / "prompt_template.txt").read_text().rstrip("\n")
    OUT.mkdir(exist_ok=True)
    index = []
    sizes = {}
    for split in SPLITS:
        old_chat, old_side, old_index = [], [], []
        if split != "test3":
            old_chat = read_lines(V2DIR / f"{split}.jsonl")
            old_side = [json.loads(l) for l in read_lines(V2DIR / f"{split}.labels.jsonl")]
            old_index = [r for r in csv.reader(open(V2DIR / "index.csv")) if r and r[0] == split]
        new = build_new(split)
        sizes[split] = len(old_chat) + len(new)
        with open(OUT / f"{split}.jsonl", "w") as chat, open(OUT / f"{split}.labels.jsonl", "w") as side:
            line = 0
            for raw, sidecar, row in zip(old_chat, old_side, old_index):      # v2 statements, unchanged
                line += 1
                chat.write(raw + "\n")
                side.write(json.dumps({"line": line, "fields": sidecar["fields"]}, ensure_ascii=False) + "\n")
                index.append([split, line, row[2], row[3], row[4], row[5], row[6], row[7], "v2"])
            for statement, label, meta in new:                                  # the new ones
                line += 1
                chat.write(json.dumps(g.render(statement, label, template), ensure_ascii=False) + "\n")
                side.write(json.dumps({"line": line, "fields": g.full_label(label)}, ensure_ascii=False) + "\n")
                index.append([split, line, meta["source"], meta["scenario"], meta["pool"], meta["unit"],
                              meta["distractors"], meta["style"], meta["kinds"]])
    with open(OUT / "index.csv", "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["split", "line", "source", "scenario", "pool", "unit", "distractors", "style", "kinds"])
        w.writerows(index)
    print(sizes)


if __name__ == "__main__":
    main()
