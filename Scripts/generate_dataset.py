#!/usr/bin/env python3
"""Generate the FinancialEdgeAI extraction dataset.

Deterministic: the same seed always produces the same files, so the test split
stays frozen. Most statements are built from templates, so every label is
correct by construction. A small set of hand-written statements with
hand-checked labels is mixed in.

Outputs (in Dataset/): train.jsonl, valid.jsonl, test.jsonl (chat format for
mlx-lm) and index.csv (split, line, source, scenario, phrasing pool, unit,
distractors) for error analysis.

Usage: python3 Scripts/generate_dataset.py
"""
import csv
import json
import random
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"

SEED = 2025
KEYS = (
    "revenue",
    "revenueGrowth",
    "operatingIncome",
    "operatingIncomeGrowth",
    "netIncome",
    "netIncomeGrowth",
    "previousYearNetIncome",
)
SYSTEM = (DATASET / "system_prompt.txt").read_text().strip()

# Generated statements per split. Hand-written ones are added on top.
GENERATED = {"train": 225, "valid": 28, "test": 27}

# One cycle of scenarios (28). Which fields a statement states, and which it leaves out.
SCENARIOS = (
    ["full"] * 5
    + ["no_prior"] * 3
    + ["prior_no_growth"] * 3
    + ["amounts_only"] * 3
    + ["no_operating"] * 3
    + ["revenue_only"] * 2
    + ["net_only"] * 2
    + ["growth_only"] * 3
    + ["none"] * 2
    + ["mixed"] * 2
)

# Phrasing pools. Pool "A" is used everywhere. Pool "B" is held out of train and
# valid and used only by half of the test statements (unseen wording).
UP_A = ["increased", "rose", "grew", "climbed"]
UP_B = ["advanced", "expanded", "edged up"]
DOWN_A = ["decreased", "fell", "declined", "dropped"]
DOWN_B = ["slipped", "contracted", "eased"]
REV_A = ["revenue", "total revenue"]
REV_B = ["net sales", "top-line revenue"]
OP_A = ["operating income"]
OP_B = ["operating profit", "income from operations"]
NET_A = ["net income"]
NET_B = ["net profit", "net earnings"]
INTRO_A = [
    "During fiscal year {y}, the company reported the following results.",
    "{co} released its results for fiscal {y}.",
    "Full-year {y} results:",
    "For the year ended December 31, {y}, {co} reported the following.",
    None,
    None,
]
INTRO_B = [
    "{co} closed {y} with the following results.",
    "Annual report highlights for {y}.",
]
COMPANIES = [
    "Northwind Holdings", "Harbor Lane Foods", "Aster Biotech", "Lumen Retail Group",
    "Solaris Energy", "Meridian Logistics", "Highland Optics", "Cobalt Systems",
    "Evergreen Materials", "Blue Peak Software", "Ironbridge Capital", "Silverline Airways",
    "Orchid Pharma", "Granite Construction Group", "Tidewater Media", "Quartz Semiconductors",
    "Redwood Hospitality", "Summit Auto Parts", "Willow Health", "Atlas Freight",
]
NONE_A = [
    "The company opened {n} new stores during the year.",
    "{co} appointed a new chief financial officer.",
    "The company employed {k} people at year end.",
    "The board declared a dividend of ${d} per share.",
    "Diluted earnings per share were ${d}.",
    "Shares closed the year at ${p}.",
    "The headquarters will move to a new campus next spring.",
]
NONE_B = [
    "{co} announced a new partnership with a logistics provider.",
    "The company completed the integration of its latest acquisition.",
]


def hand(statement, rev=None, revg=None, op=None, opg=None, net=None, netg=None, prev=None):
    label = dict(zip(KEYS, (rev, revg, op, opg, net, netg, prev)))
    return statement, label


# Hand-written statements with hand-checked labels (fictional companies).
HAND = {
    "H1": hand(
        "During fiscal year 2025, the company reported revenue of $94 billion, representing a 12% "
        "increase compared with the previous year. Operating income was $25 billion, an increase "
        "of 8%. Net income was $21 billion, down 4% from $21.9 billion in the previous year.",
        94, 12, 25, 8, 21, -4, 21.9),
    "H2": hand(
        "Harbor Lane Foods closed 2024 with revenue of $12.4 billion, up 6.5% year over year. "
        "Operating income rose 3% to $1.9 billion, while net income climbed 9% to $1.2 billion.",
        12.4, 6.5, 1.9, 3, 1.2, 9, None),
    "H3": hand(
        "Quarterly results were mixed. Revenue grew 4% to $3.2 billion but net income fell 11% "
        "to $410 million.",
        3.2, 4, None, None, 0.41, -11, None),
    "H4": hand(
        "Aster Biotech reported full-year revenue of $870 million, compared with $790 million in "
        "the prior year. The company did not disclose operating income.",
        0.87),
    "H5": hand(
        "Net income was $5.6 billion, down from $6.1 billion a year earlier.",
        net=5.6, prev=6.1),
    "H6": hand(
        "Revenue declined 2.5% year over year and operating income decreased 7%. No other "
        "figures were provided.",
        revg=-2.5, opg=-7),
    "H7": hand(
        "Lumen Retail Group announced the opening of 40 new stores and the appointment of a new "
        "chief financial officer. Shares closed at $48.20."),
    "H8": hand(
        "For fiscal 2023 the company posted revenue of $41 billion (+8%), operating income of "
        "$6.3 billion (+12%) and net income of $4.8 billion (+15%), versus $4.17 billion in 2022.",
        41, 8, 6.3, 12, 4.8, 15, 4.17),
    "H9": hand(
        "Management expects revenue of $60 billion next year. This year, revenue was $52 billion, "
        "up 5%, and operating margin reached 21%.",
        52, 5),
    "H10": hand(
        "Operating income increased 18% to $2.2 billion on revenue of $14 billion. Net income "
        "was $1.5 billion.",
        14, None, 2.2, 18, 1.5, None, None),
    "H11": hand(
        "Solaris Energy's net income dropped 23% to $730 million, from $948 million the year "
        "before. Revenue for the year was $9.1 billion.",
        9.1, None, None, None, 0.73, -23, 0.948),
    "H12": hand(
        "Total revenue: $230 billion, +7%. Operating income: $48 billion, +4%. Net income: $39 "
        "billion, -2%. Prior-year net income: $39.8 billion.",
        230, 7, 48, 4, 39, -2, 39.8),
    "H13": hand(
        "The company's operating income fell 5% to $3.4 billion. Revenue, however, increased "
        "1.8% to $22 billion, and net income edged up 2% to $2.7 billion.",
        22, 1.8, 3.4, -5, 2.7, 2, None),
    "H14": hand(
        "In 2022, the group generated $1,750 million in revenue and $210 million in operating "
        "income.",
        1.75, None, 0.21),
    "H15": hand(
        "Net income came to $15 billion, which is 3% lower than last year's $15.5 billion. "
        "Revenue rose 9% to $120 billion; operating income was $24 billion.",
        120, 9, 24, None, 15, -3, 15.5),
    "H16": hand(
        "Meridian Logistics reported net income of $2.1 billion, with year-over-year growth of "
        "14%.",
        net=2.1, netg=14),
    "H17": hand(
        "Revenue totalled $7.8 billion, and the operating margin was 19.5%. Net income margin "
        "was 12%.",
        7.8),
    "H18": hand(
        "Compared with last year, revenue is up 10% and operating income is up 15%, while net "
        "income is down 6%.",
        revg=10, opg=15, netg=-6),
    "H19": hand(
        "Revenues reached $33.3 billion in fiscal 2024, a 3.1% decline from the previous year, "
        "and net income was $2.9 billion, a decline of 12% from $3.3 billion.",
        33.3, -3.1, None, None, 2.9, -12, 3.3),
    "H20": hand(
        "Highland Optics earned $640 million in operating income this year, up 9.5%, on revenue "
        "of $4.9 billion, up 4%.",
        4.9, 4, 0.64, 9.5),
}
HAND_SPLITS = {
    "test": ["H1", "H12", "H16"],
    "valid": ["H4", "H9"],
    "train": [k for k in HAND if k not in {"H1", "H12", "H16", "H4", "H9"}],
}


def pick(rng, a, b, pool):
    return rng.choice(b if pool == "B" and b else a)


def sent(text):
    return text[0].upper() + text[1:]


def num(d):
    """Decimal to int when whole, else float, so JSON shows 94 and 21.9."""
    return int(d) if d == d.to_integral_value() else float(d)


def to_billions(v, unit):
    """Base units are tenths of a billion ('b') or millions ('m')."""
    return Decimal(v) / (10 if unit == "b" else 1000)


def money(v, unit, rng, pool):
    if unit == "b":
        n = str(v // 10) if v % 10 == 0 else f"{v // 10}.{v % 10}"
        form = pick(rng, ["${n} billion", "USD {n} billion"], ["${n}bn", "{n} billion dollars"], pool)
    else:
        n = f"{v:,}"
        form = pick(rng, ["${n} million", "USD {n} million"], ["${n}m", "{n} million dollars"], pool)
    return form.format(n=n)


def pct(gt, rng, pool):
    """gt is an absolute number of tenths of a percent."""
    n = str(gt // 10) if gt % 10 == 0 else f"{gt // 10}.{gt % 10}"
    if pool == "B" and rng.random() < 0.5:
        return f"{n} percent"
    return f"{n}%"


def clause(name, amt, g, prior, unit, rng, pool):
    """One clause about a metric, lowercase-initial and without a final period."""
    up = g is not None and g > 0
    M = money(amt, unit, rng, pool) if amt is not None else None
    R = money(prior, unit, rng, pool) if prior is not None else None
    P = pct(abs(g), rng, pool) if g is not None else None
    verb = pick(rng, UP_A if up else DOWN_A, UP_B if up else DOWN_B, pool) if g is not None else None
    word, noun, art = ("up", "increase", "an") if up else ("down", "decrease", "a")
    cap = sent(name)

    if amt is not None and g is not None and prior is not None:
        a = [f"{name} was {M}, {word} {P} from {R} in the previous year",
             f"{cap} {verb} {P} to {M} from {R}"]
        b = [f"{name} came in at {M}, {word} {P} against {R} a year earlier",
             f"{cap} {verb} by {P} to {M}, versus {R} in the prior year"]
    elif amt is not None and g is not None:
        a = [f"{name} was {M}, {word} {P} year over year",
             f"{name} was {M}, representing a {P} {noun} compared with the previous year",
             f"{cap} {verb} {P} to {M}",
             f"{name} was {M}, {art} {noun} of {P}"]
        b = [f"{cap} {verb} by {P}, reaching {M}",
             f"{name} stood at {M} ({'+' if up else '-'}{P})",
             f"{name} totalled {M}, {word} {P} on the prior year"]
    elif amt is not None and prior is not None:
        a = [f"{name} was {M}, compared with {R} in the previous year",
             f"{name} was {M}, versus {R} a year earlier"]
        b = [f"{name} came in at {M}, against {R} in the prior year"]
    elif amt is not None:
        a = [f"{name} was {M}", f"the company reported {name} of {M}"]
        b = [f"{name} totalled {M}", f"{name} stood at {M}"]
    elif g is not None and prior is not None:
        a = [f"{name} {verb} {P} from {R} in the previous year"]
        b = [f"{name} {verb} by {P} from {R} a year earlier"]
    elif g is not None:
        a = [f"{name} {verb} {P}", f"{name} was {word} {P} year over year"]
        b = [f"{name} {verb} by {P}", f"{name} saw a {P} {'gain' if up else 'drop'}"]
    else:
        a = [f"{name} in the previous year was {R}"]
        b = [f"{name} a year earlier stood at {R}"]
    return rng.choice(b if pool == "B" else a)


def distractors(rng, with_revenue):
    """Sentences with numbers that are NOT requested metrics."""
    options = [
        lambda: f"Operating margin was {rng.randint(80, 350) / 10:.1f}%.",
        lambda: f"The company employed {rng.randint(2, 180) * 1000:,} people at year end.",
        lambda: f"Diluted earnings per share were ${rng.randint(50, 1500) / 100:.2f}.",
        lambda: f"The board declared a dividend of ${rng.randint(5, 150) / 100:.2f} per share.",
        lambda: f"Capital expenditures totalled ${rng.randint(3, 300) / 10:.1f} billion.",
        lambda: f"Cash and cash equivalents were ${rng.randint(5, 900) / 10:.1f} billion.",
        lambda: f"The company opened {rng.randint(5, 90)} new stores during the year.",
    ]
    if with_revenue:
        options.append(lambda: f"Management expects revenue of ${rng.randint(30, 3000) / 10:.1f} billion next year.")
        options.append(lambda: f"Management expects revenue to grow {rng.randint(2, 15)}% next year.")
    return rng.choice(options)()


def plan_fields(scenario, rng):
    names = ("rev_amt", "rev_g", "op_amt", "op_g", "net_amt", "net_g", "net_prior")
    on = {
        "full": names,
        "no_prior": names[:-1],
        "prior_no_growth": ("rev_amt", "rev_g", "op_amt", "op_g", "net_amt", "net_prior"),
        "amounts_only": ("rev_amt", "op_amt", "net_amt"),
        "no_operating": ("rev_amt", "rev_g", "net_amt", "net_g", "net_prior"),
        "revenue_only": ("rev_amt", "rev_g"),
        "net_only": ("net_amt", "net_g", "net_prior"),
        "growth_only": ("rev_g", "op_g", "net_g"),
        "none": (),
    }
    if scenario == "mixed":
        chosen = ()
        while not chosen:
            chosen = tuple(n for n in names if rng.random() < 0.5)
        return set(chosen)
    return set(on[scenario])


def gen_growth(rng):
    g = rng.randint(5, 400)
    if rng.random() < 0.5:
        g = max(10, round(g / 10) * 10)
    return -g if rng.random() < 0.4 else g


def prior_for(amount, g, rng):
    p = round(amount / (1 + g / 1000)) if g is not None else round(amount * rng.uniform(0.8, 1.25))
    if p == amount:
        p = amount + 1
    return max(p, 1)


def make_example(scenario, pool, rng):
    f = plan_fields(scenario, rng)
    unit = "m" if scenario not in ("growth_only", "none") and rng.random() < 0.2 else "b"

    if unit == "b":
        rev = rng.randint(30, 3000)
        if rng.random() < 0.5:
            rev = max(10, round(rev / 10) * 10)
    else:
        rev = rng.randint(300, 9000)
    op = max(1, int(rev * rng.uniform(0.10, 0.35)))
    net = max(1, int(op * rng.uniform(0.55, 0.90)))
    if unit == "b" and rng.random() < 0.5:
        op, net = max(10, round(op / 10) * 10), max(10, round(net / 10) * 10)
    rg, og, ng = gen_growth(rng), gen_growth(rng), gen_growth(rng)
    rev_prior = prior_for(rev, rg, rng)
    op_prior = prior_for(op, og, rng)
    net_prior = prior_for(net, ng if "net_g" in f else None, rng)

    # Prior-year revenue / operating income are not requested: they are distractors.
    show_rev_prior = "rev_amt" in f and rng.random() < 0.25
    show_op_prior = "op_amt" in f and rng.random() < 0.25

    label = dict.fromkeys(KEYS)
    if "rev_amt" in f: label["revenue"] = num(to_billions(rev, unit))
    if "rev_g" in f: label["revenueGrowth"] = num(Decimal(rg) / 10)
    if "op_amt" in f: label["operatingIncome"] = num(to_billions(op, unit))
    if "op_g" in f: label["operatingIncomeGrowth"] = num(Decimal(og) / 10)
    if "net_amt" in f: label["netIncome"] = num(to_billions(net, unit))
    if "net_g" in f: label["netIncomeGrowth"] = num(Decimal(ng) / 10)
    if "net_prior" in f: label["previousYearNetIncome"] = num(to_billions(net_prior, unit))

    groups = [
        (pick(rng, REV_A, REV_B, pool), rev if "rev_amt" in f else None,
         rg if "rev_g" in f else None, rev_prior if show_rev_prior else None),
        (pick(rng, OP_A, OP_B, pool), op if "op_amt" in f else None,
         og if "op_g" in f else None, op_prior if show_op_prior else None),
        (pick(rng, NET_A, NET_B, pool), net if "net_amt" in f else None,
         ng if "net_g" in f else None, net_prior if "net_prior" in f else None),
    ]
    if rng.random() < 0.15:
        groups = [groups[2], groups[0], groups[1]]

    sentences = []
    if scenario == "none":
        pool_none = NONE_B if pool == "B" else NONE_A
        for _ in range(rng.randint(2, 3)):
            text = rng.choice(pool_none).format(
                n=rng.randint(5, 90), k=f"{rng.randint(2, 180) * 1000:,}",
                d=f"{rng.randint(5, 150) / 100:.2f}", p=f"{rng.randint(1000, 25000) / 100:.2f}",
                co=rng.choice(COMPANIES))
            if text not in sentences:
                sentences.append(text)
        statement = " ".join(sentences)
        distract = False
    else:
        for name, amt, g, prior in groups:
            if amt is None and g is None and prior is None:
                continue
            text = clause(name, amt, g, prior, unit, rng, pool)
            if sentences and rng.random() < 0.3:
                sentences[-1] += rng.choice([", while ", "; ", ", and "]) + text[0].lower() + text[1:]
            else:
                sentences.append(sent(text))
        sentences = [s + "." for s in sentences]
        distract = rng.random() < 0.4
        if distract:
            for _ in range(rng.randint(1, 2)):
                sentences.insert(rng.randint(0, len(sentences)), distractors(rng, "rev_amt" in f) )
        intro = pick(rng, INTRO_A, INTRO_B, pool)
        parts = ([intro.format(y=rng.randint(2019, 2025), co=rng.choice(COMPANIES))] if intro else []) + sentences
        statement = " ".join(parts)

    meta = {"scenario": scenario, "pool": pool, "unit": unit, "distractors": int(distract)}
    return statement, label, meta


def render(statement, label, template):
    return {"messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": template.replace("<<STATEMENT>>", statement)},
        {"role": "assistant", "content": json.dumps(label, indent=2)},
    ]}


def main():
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    rng = random.Random(SEED)
    seen = set()
    rows = {}

    for split, n in GENERATED.items():
        items = []
        cycle = (SCENARIOS * (n // len(SCENARIOS) + 1))[:n]
        for i, scenario in enumerate(cycle):
            pool = "B" if split == "test" and i % 2 == 1 else "A"
            for _ in range(100):
                statement, label, meta = make_example(scenario, pool, rng)
                if statement not in seen:
                    break
            else:
                raise RuntimeError("could not generate a unique statement")
            seen.add(statement)
            items.append((statement, label, {**meta, "source": "generated"}))
        for key in HAND_SPLITS[split]:
            statement, label = HAND[key]
            assert statement not in seen, key
            seen.add(statement)
            items.append((statement, label,
                          {"scenario": "hand", "pool": "A", "unit": "-", "distractors": "-", "source": key}))
        rng.shuffle(items)
        rows[split] = items

    index = []
    for split, items in rows.items():
        with open(DATASET / f"{split}.jsonl", "w") as out:
            for line, (statement, label, meta) in enumerate(items, start=1):
                out.write(json.dumps(render(statement, label, template), ensure_ascii=False) + "\n")
                index.append([split, line, meta["source"], meta["scenario"], meta["pool"],
                              meta["unit"], meta["distractors"]])
    with open(DATASET / "index.csv", "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["split", "line", "source", "scenario", "pool", "unit", "distractors"])
        w.writerows(index)
    print({split: len(items) for split, items in rows.items()})


if __name__ == "__main__":
    main()
