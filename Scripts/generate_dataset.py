#!/usr/bin/env python3
"""Generate the FinancialEdgeAI extraction dataset (schema version 1, Phase 1).

Deterministic: the same seed always produces the same files, so the test split stays frozen.
Most statements are built from templates, so every label is correct by construction. A small set
of hand-written statements with hand-checked labels is mixed in.

The fields come from Dataset/schema.json (13 core, 5 extended). The prompt is rendered from the
schema by prompt_from_schema.py and written to Dataset/prompt_template.txt.

Outputs (in Dataset/):
  prompt_template.txt           the user prompt, rendered from the schema
  train.jsonl valid.jsonl test.jsonl
                                chat format for mlx-lm. The assistant message holds the 13 core
                                fields, each a string copied as printed in the statement, or null.
  train.labels.jsonl ...        the sidecar: for every line, all 18 fields as {"text", "value"} or
                                null. "text" is the string as printed, "value" the true number
                                (billions of USD, percent, or USD per share). The parser is tested
                                against these values, never against its own output.
  index.csv                     split, line, source, scenario, phrasing pool, unit, distractors

Usage: python3 Scripts/generate_dataset.py
"""
import csv
import json
import random
from decimal import Decimal
from pathlib import Path

from prompt_from_schema import example_leaks, load_schema, render_prompt

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"

SEED = 2025
SCHEMA = load_schema()
FIELDS = [f["key"] for f in SCHEMA["fields"]]
CORE = [f["key"] for f in SCHEMA["fields"] if f["tier"] == "core"]
SYSTEM = (DATASET / "system_prompt.txt").read_text().strip()

# Generated statements per split. Hand-written ones are added on top: 240 / 30 / 30 in total.
GENERATED = {"train": 224, "valid": 27, "test": 25}

# One cycle of scenarios (30). Which fields a statement states, and which it leaves out.
SCENARIOS = (
    ["full"] * 4
    + ["income_basic"] * 3
    + ["prior_no_growth"] * 3
    + ["amounts_only"] * 2
    + ["eps_only"] * 3
    + ["cash_flow"] * 3
    + ["interest"] * 2
    + ["balance_sheet"] * 3
    + ["growth_only"] * 2
    + ["mixed"] * 3
    + ["none"] * 2
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
EPS_A = ["EPS", "diluted EPS"]
EPS_B = ["earnings per share", "diluted earnings per share"]
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
# Statements with none of the requested fields. EPS, cash flow and balance sheet items are fields now.
NONE_A = [
    "The company opened {n} new stores during the year.",
    "{co} appointed a new chief financial officer.",
    "The company employed {k} people at year end.",
    "The board declared a dividend of ${d} per share.",
    "Shares closed the year at ${p}.",
    "The headquarters will move to a new campus next spring.",
]
NONE_B = [
    "{co} announced a new partnership with a logistics provider.",
    "The company completed the integration of its latest acquisition.",
]
# One clause per single-value field: (pool A forms, pool B forms). {M} is the printed amount.
SINGLE = {
    "interestExpense": (["interest expense was {M}", "the company reported interest expense of {M}"],
                        ["interest costs totalled {M}", "interest expense stood at {M}"]),
    "operatingCashFlow": (["net cash from operating activities was {M}", "operating cash flow was {M}"],
                          ["net cash provided by operating activities totalled {M}",
                           "cash generated from operations came to {M}"]),
    "capex": (["capital expenditures were {M}", "capex was {M}"],
              ["capital spending stood at {M}", "the company spent {M} on property, plant and equipment"]),
    "totalDebt": (["total debt was {M}"], ["total borrowings stood at {M}"]),
    "shareholdersEquity": (["shareholders' equity was {M}"], ["total stockholders' equity came to {M}"]),
    "currentAssets": (["total current assets were {M}"], ["current assets stood at {M}"]),
    "currentLiabilities": (["total current liabilities were {M}"], ["current liabilities came to {M}"]),
    "cash": (["cash and cash equivalents were {M}"], ["the company held {M} in cash and cash equivalents"]),
}


def hand(statement, **fields):
    """A hand-written statement. Each field is (text as printed, true value)."""
    return statement, {key: {"text": text, "value": value} for key, (text, value) in fields.items()}


# Hand-written statements with hand-checked labels (fictional companies). A decrease is written
# with a leading minus ("-4%"), as the prompt asks; the statement prints "down 4%".
HAND = {
    "H1": hand(
        "During fiscal year 2025, the company reported revenue of $94 billion, representing a 12% "
        "increase compared with the previous year. Operating income was $25 billion, an increase "
        "of 8%. Net income was $21 billion, down 4% from $21.9 billion in the previous year.",
        revenue=("$94 billion", 94), revenueGrowth=("12%", 12), operatingIncome=("$25 billion", 25),
        netIncome=("$21 billion", 21), netIncomeGrowth=("-4%", -4),
        previousYearNetIncome=("$21.9 billion", 21.9)),
    "H2": hand(
        "Harbor Lane Foods closed 2024 with revenue of $12.4 billion, up 6.5% year over year. "
        "Operating income rose 3% to $1.9 billion, while net income climbed 9% to $1.2 billion.",
        revenue=("$12.4 billion", 12.4), revenueGrowth=("6.5%", 6.5), operatingIncome=("$1.9 billion", 1.9),
        netIncome=("$1.2 billion", 1.2), netIncomeGrowth=("9%", 9)),
    "H3": hand(
        "Quarterly results were mixed. Revenue grew 4% to $3.2 billion but net income fell 11% "
        "to $410 million.",
        revenue=("$3.2 billion", 3.2), revenueGrowth=("4%", 4),
        netIncome=("$410 million", 0.41), netIncomeGrowth=("-11%", -11)),
    "H4": hand(
        "Aster Biotech reported full-year revenue of $870 million, compared with $790 million in "
        "the prior year. The company did not disclose operating income.",
        revenue=("$870 million", 0.87), previousYearRevenue=("$790 million", 0.79)),
    "H5": hand(
        "Net income was $5.6 billion, down from $6.1 billion a year earlier.",
        netIncome=("$5.6 billion", 5.6), previousYearNetIncome=("$6.1 billion", 6.1)),
    "H6": hand(
        "Revenue declined 2.5% year over year and operating income decreased 7%. No other "
        "figures were provided.",
        revenueGrowth=("-2.5%", -2.5)),
    "H7": hand(
        "Lumen Retail Group announced the opening of 40 new stores and the appointment of a new "
        "chief financial officer. Shares closed at $48.20."),
    "H8": hand(
        "For fiscal 2023 the company posted revenue of $41 billion (+8%), operating income of "
        "$6.3 billion (+12%) and net income of $4.8 billion (+15%), versus $4.17 billion in 2022.",
        revenue=("$41 billion", 41), revenueGrowth=("+8%", 8), operatingIncome=("$6.3 billion", 6.3),
        netIncome=("$4.8 billion", 4.8), netIncomeGrowth=("+15%", 15),
        previousYearNetIncome=("$4.17 billion", 4.17)),
    "H9": hand(
        "Management expects revenue of $60 billion next year. This year, revenue was $52 billion, "
        "up 5%, and operating margin reached 21%.",
        revenue=("$52 billion", 52), revenueGrowth=("5%", 5)),
    "H10": hand(
        "Operating income increased 18% to $2.2 billion on revenue of $14 billion. Net income "
        "was $1.5 billion.",
        revenue=("$14 billion", 14), operatingIncome=("$2.2 billion", 2.2), netIncome=("$1.5 billion", 1.5)),
    "H11": hand(
        "Solaris Energy's net income dropped 23% to $730 million, from $948 million the year "
        "before. Revenue for the year was $9.1 billion.",
        revenue=("$9.1 billion", 9.1), netIncome=("$730 million", 0.73), netIncomeGrowth=("-23%", -23),
        previousYearNetIncome=("$948 million", 0.948)),
    "H12": hand(
        "Total revenue: $230 billion, +7%. Operating income: $48 billion, +4%. Net income: $39 "
        "billion, -2%. Prior-year net income: $39.8 billion.",
        revenue=("$230 billion", 230), revenueGrowth=("+7%", 7), operatingIncome=("$48 billion", 48),
        netIncome=("$39 billion", 39), netIncomeGrowth=("-2%", -2),
        previousYearNetIncome=("$39.8 billion", 39.8)),
    "H13": hand(
        "The company's operating income fell 5% to $3.4 billion. Revenue, however, increased "
        "1.8% to $22 billion, and net income edged up 2% to $2.7 billion.",
        revenue=("$22 billion", 22), revenueGrowth=("1.8%", 1.8), operatingIncome=("$3.4 billion", 3.4),
        netIncome=("$2.7 billion", 2.7), netIncomeGrowth=("2%", 2)),
    "H14": hand(
        "In 2022, the group generated $1,750 million in revenue and $210 million in operating "
        "income.",
        revenue=("$1,750 million", 1.75), operatingIncome=("$210 million", 0.21)),
    "H15": hand(
        "Net income came to $15 billion, which is 3% lower than last year's $15.5 billion. "
        "Revenue rose 9% to $120 billion; operating income was $24 billion.",
        revenue=("$120 billion", 120), revenueGrowth=("9%", 9), operatingIncome=("$24 billion", 24),
        netIncome=("$15 billion", 15), netIncomeGrowth=("-3%", -3),
        previousYearNetIncome=("$15.5 billion", 15.5)),
    "H16": hand(
        "Meridian Logistics reported net income of $2.1 billion, with year-over-year growth of "
        "14%.",
        netIncome=("$2.1 billion", 2.1), netIncomeGrowth=("14%", 14)),
    "H17": hand(
        "Revenue totalled $7.8 billion, and the operating margin was 19.5%. Net income margin "
        "was 12%.",
        revenue=("$7.8 billion", 7.8)),
    "H18": hand(
        "Compared with last year, revenue is up 10% and operating income is up 15%, while net "
        "income is down 6%.",
        revenueGrowth=("10%", 10), netIncomeGrowth=("-6%", -6)),
    "H19": hand(
        "Revenues reached $33.3 billion in fiscal 2024, a 3.1% decline from the previous year, "
        "and net income was $2.9 billion, a decline of 12% from $3.3 billion.",
        revenue=("$33.3 billion", 33.3), revenueGrowth=("-3.1%", -3.1), netIncome=("$2.9 billion", 2.9),
        netIncomeGrowth=("-12%", -12), previousYearNetIncome=("$3.3 billion", 3.3)),
    "H20": hand(
        "Highland Optics earned $640 million in operating income this year, up 9.5%, on revenue "
        "of $4.9 billion, up 4%.",
        revenue=("$4.9 billion", 4.9), revenueGrowth=("4%", 4), operatingIncome=("$640 million", 0.64)),
    # Added in Phase 1: the new fields in the wording of a short report.
    "H21": hand(
        "Diluted earnings per share were $2.35, up 12% from $2.10 in the previous year. Revenue "
        "for the year was $18.6 billion.",
        revenue=("$18.6 billion", 18.6), eps=("$2.35", 2.35), previousYearEps=("$2.10", 2.10),
        epsGrowth=("12%", 12)),
    "H22": hand(
        "Net cash from operating activities was $3.1 billion and capital expenditures were $1.2 "
        "billion. Interest expense totalled $240 million, and operating income was $2.0 billion.",
        operatingIncome=("$2.0 billion", 2.0), interestExpense=("$240 million", 0.24),
        operatingCashFlow=("$3.1 billion", 3.1), capex=("$1.2 billion", 1.2)),
    "H23": hand(
        "At year end, total debt was $12.5 billion, shareholders' equity was $30 billion and cash "
        "and cash equivalents were $4.2 billion. Total current assets were $9.8 billion against "
        "current liabilities of $6.1 billion. Net income was $2.6 billion.",
        netIncome=("$2.6 billion", 2.6), totalDebt=("$12.5 billion", 12.5),
        shareholdersEquity=("$30 billion", 30), cash=("$4.2 billion", 4.2),
        currentAssets=("$9.8 billion", 9.8), currentLiabilities=("$6.1 billion", 6.1)),
    "H24": hand(
        "Revenue reached $48 billion, a 9% increase, while net income fell 6% to $5.2 billion "
        "from $5.5 billion. Operating cash flow was $7.9 billion and capex was $2.3 billion.",
        revenue=("$48 billion", 48), revenueGrowth=("9%", 9), netIncome=("$5.2 billion", 5.2),
        netIncomeGrowth=("-6%", -6), previousYearNetIncome=("$5.5 billion", 5.5),
        operatingCashFlow=("$7.9 billion", 7.9), capex=("$2.3 billion", 2.3)),
}
HAND_SPLITS = {
    "test": ["H1", "H12", "H16", "H21", "H22"],
    "valid": ["H4", "H9", "H23"],
    "train": [k for k in HAND if k not in {"H1", "H12", "H16", "H21", "H22", "H4", "H9", "H23"}],
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


def per_share(cents, rng, pool):
    n = f"{cents // 100}.{cents % 100:02d}"
    return pick(rng, ["${n}", "USD {n}"], ["USD {n}", "{n} dollars"], pool).format(n=n)


def pct(gt, rng, pool):
    """gt is an absolute number of tenths of a percent."""
    n = str(gt // 10) if gt % 10 == 0 else f"{gt // 10}.{gt % 10}"
    if pool == "B" and rng.random() < 0.5:
        return f"{n} percent"
    return f"{n}%"


def clause(name, M, up, P, R, rng, pool):
    """One clause about a metric, lowercase-initial and without a final period.

    M is the printed amount, P the printed percent change (its direction is `up`), R the printed
    previous-year amount. Each is a string or None.
    """
    verb = pick(rng, UP_A if up else DOWN_A, UP_B if up else DOWN_B, pool) if P is not None else None
    word, noun, art = ("up", "increase", "an") if up else ("down", "decrease", "a")
    cap = sent(name)

    if M and P and R:
        a = [f"{name} was {M}, {word} {P} from {R} in the previous year",
             f"{cap} {verb} {P} to {M} from {R}"]
        b = [f"{name} came in at {M}, {word} {P} against {R} a year earlier",
             f"{cap} {verb} by {P} to {M}, versus {R} in the prior year"]
    elif M and P:
        a = [f"{name} was {M}, {word} {P} year over year",
             f"{name} was {M}, representing a {P} {noun} compared with the previous year",
             f"{cap} {verb} {P} to {M}",
             f"{name} was {M}, {art} {noun} of {P}"]
        b = [f"{cap} {verb} by {P}, reaching {M}",
             f"{name} stood at {M} ({'+' if up else '-'}{P})",
             f"{name} totalled {M}, {word} {P} on the prior year"]
    elif M and R:
        a = [f"{name} was {M}, compared with {R} in the previous year",
             f"{name} was {M}, versus {R} a year earlier"]
        b = [f"{name} came in at {M}, against {R} in the prior year"]
    elif M:
        a = [f"{name} was {M}", f"the company reported {name} of {M}"]
        b = [f"{name} totalled {M}", f"{name} stood at {M}"]
    elif P and R:
        a = [f"{name} {verb} {P} from {R} in the previous year"]
        b = [f"{name} {verb} by {P} from {R} a year earlier"]
    elif P:
        a = [f"{name} {verb} {P}", f"{name} was {word} {P} year over year"]
        b = [f"{name} {verb} by {P}", f"{name} saw a {P} {'gain' if up else 'drop'}"]
    else:
        a = [f"{name} in the previous year was {R}"]
        b = [f"{name} a year earlier stood at {R}"]
    return rng.choice(b if pool == "B" else a)


def distractors(rng, with_revenue):
    """Sentences with numbers that are NOT requested fields."""
    options = [
        lambda: f"Operating margin was {rng.randint(80, 350) / 10:.1f}%.",
        lambda: f"Net margin was {rng.randint(40, 250) / 10:.1f}%.",
        lambda: f"The company employed {rng.randint(2, 180) * 1000:,} people at year end.",
        lambda: f"The board declared a dividend of ${rng.randint(5, 150) / 100:.2f} per share.",
        lambda: f"Total assets were ${rng.randint(30, 3000) / 10:.1f} billion.",
        lambda: f"Free cash flow was ${rng.randint(3, 300) / 10:.1f} billion.",
        lambda: f"The company opened {rng.randint(5, 90)} new stores during the year.",
        lambda: f"Shares closed the year at ${rng.randint(1000, 25000) / 100:.2f}.",
    ]
    if with_revenue:
        options.append(lambda: f"Management expects revenue of ${rng.randint(30, 3000) / 10:.1f} billion next year.")
        options.append(lambda: f"Management expects revenue to grow {rng.randint(2, 15)}% next year.")
    return rng.choice(options)()


def plan_fields(scenario, rng):
    """The fields a statement states."""
    growths = ("revenueGrowth", "netIncomeGrowth", "epsGrowth")
    if scenario == "full":
        return {"revenue", "revenueGrowth", "previousYearRevenue", "operatingIncome", "netIncome",
                "netIncomeGrowth", "previousYearNetIncome", "eps", "epsGrowth", "previousYearEps"}
    if scenario == "income_basic":
        return {"revenue", "revenueGrowth", "operatingIncome", "netIncome", "netIncomeGrowth"}
    if scenario == "prior_no_growth":
        return {"revenue", "previousYearRevenue", "netIncome", "previousYearNetIncome", "eps", "previousYearEps"}
    if scenario == "amounts_only":
        return {"revenue", "operatingIncome", "netIncome"}
    if scenario == "eps_only":
        return {"eps"} | {k for k in ("epsGrowth", "previousYearEps") if rng.random() < 0.5}
    if scenario == "cash_flow":
        return {"operatingCashFlow", "capex"} | {k for k in ("revenue", "netIncome") if rng.random() < 0.5}
    if scenario == "interest":
        return {"operatingIncome", "interestExpense"} | ({"netIncome"} if rng.random() < 0.5 else set())
    if scenario == "balance_sheet":
        return ({"totalDebt", "shareholdersEquity", "currentAssets", "currentLiabilities", "cash"}
                | {k for k in ("revenue", "netIncome") if rng.random() < 0.5})
    if scenario == "growth_only":
        chosen = set()
        while not chosen:
            chosen = {k for k in growths if rng.random() < 0.7}
        return chosen
    if scenario == "mixed":
        chosen = set()
        while not chosen:
            chosen = {k for k in FIELDS if rng.random() < 0.35}
        return chosen
    return set()  # "none"


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
    no_amounts = scenario in ("growth_only", "none", "eps_only")
    unit = "m" if not no_amounts and rng.random() < 0.2 else "b"

    # Amounts, in tenths of a billion ('b') or millions ('m').
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
    amounts = {
        "revenue": rev,
        "operatingIncome": op,
        "netIncome": net,
        "interestExpense": max(1, int(op * rng.uniform(0.03, 0.20))),
        "operatingCashFlow": max(1, int(net * rng.uniform(0.9, 1.8))),
        "totalDebt": max(1, int(rev * rng.uniform(0.3, 1.5))),
        "shareholdersEquity": max(1, int(rev * rng.uniform(0.5, 2.0))),
        "currentAssets": max(1, int(rev * rng.uniform(0.2, 0.6))),
    }
    amounts["capex"] = max(1, int(amounts["operatingCashFlow"] * rng.uniform(0.2, 0.7)))
    amounts["currentLiabilities"] = max(1, int(amounts["currentAssets"] * rng.uniform(0.4, 0.9)))
    amounts["cash"] = max(1, int(amounts["currentAssets"] * rng.uniform(0.2, 0.6)))
    cents = rng.randint(5, 1500)

    growth = {"revenue": gen_growth(rng), "netIncome": gen_growth(rng), "eps": gen_growth(rng)}
    og = gen_growth(rng)
    rev_prior = prior_for(rev, growth["revenue"] if "revenueGrowth" in f else None, rng)
    net_prior = prior_for(net, growth["netIncome"] if "netIncomeGrowth" in f else None, rng)
    eps_prior = prior_for(cents, growth["eps"] if "epsGrowth" in f else None, rng)
    op_prior = prior_for(op, og, rng)

    # Operating income growth and prior are not fields: when stated, they are distractors.
    show_op_g = "operatingIncome" in f and rng.random() < 0.3
    show_op_prior = "operatingIncome" in f and rng.random() < 0.25

    # Print every value once, and keep the printed string as the label.
    label = {}

    def amount(key, v):
        text = money(v, unit, rng, pool)
        label[key] = {"text": text, "value": num(to_billions(v, unit))}
        return text

    def percent(key, g):
        text = pct(abs(g), rng, pool)
        label[key] = {"text": text if g > 0 else "-" + text, "value": num(Decimal(g) / 10)}
        return text

    def shown_amount(key):
        return amount(key, amounts[key]) if key in f else None

    def shown_percent(key, base):
        return percent(key, growth[base]) if key in f else None

    rev_s = shown_amount("revenue")
    rev_g = shown_percent("revenueGrowth", "revenue")
    rev_p = amount("previousYearRevenue", rev_prior) if "previousYearRevenue" in f else None
    op_s = shown_amount("operatingIncome")
    op_g = pct(abs(og), rng, pool) if show_op_g else None
    op_p = money(op_prior, unit, rng, pool) if show_op_prior else None
    net_s = shown_amount("netIncome")
    net_g = shown_percent("netIncomeGrowth", "netIncome")
    net_p = amount("previousYearNetIncome", net_prior) if "previousYearNetIncome" in f else None
    eps_s = eps_g = eps_p = None
    if "eps" in f:
        eps_s = per_share(cents, rng, pool)
        label["eps"] = {"text": eps_s, "value": num(Decimal(cents) / 100)}
    if "previousYearEps" in f:
        eps_p = per_share(eps_prior, rng, pool)
        label["previousYearEps"] = {"text": eps_p, "value": num(Decimal(eps_prior) / 100)}
    if "epsGrowth" in f:
        eps_g = percent("epsGrowth", growth["eps"])

    groups = [
        (pick(rng, REV_A, REV_B, pool), rev_s, growth["revenue"] > 0, rev_g, rev_p),
        (pick(rng, OP_A, OP_B, pool), op_s, og > 0, op_g, op_p),
        (pick(rng, NET_A, NET_B, pool), net_s, growth["netIncome"] > 0, net_g, net_p),
        (pick(rng, EPS_A, EPS_B, pool), eps_s, growth["eps"] > 0, eps_g, eps_p),
    ]
    if rng.random() < 0.15:
        groups = [groups[2], groups[0], groups[1], groups[3]]

    singles = [
        (key, rng.choice(SINGLE[key][1 if pool == "B" else 0]).format(M=amount(key, amounts[key])))
        for key in SINGLE if key in f
    ]

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
        for name, M, up, P, R in groups:
            if M is None and P is None and R is None:
                continue
            text = clause(name, M, up, P, R, rng, pool)
            if sentences and rng.random() < 0.3:
                sentences[-1] += rng.choice([", while ", "; ", ", and "]) + text[0].lower() + text[1:]
            else:
                sentences.append(sent(text))
        sentences += [sent(text) for _, text in singles]
        if rng.random() < 0.3:
            rng.shuffle(sentences)
        sentences = [s + "." for s in sentences]
        distract = rng.random() < 0.4
        if distract:
            for _ in range(rng.randint(1, 2)):
                sentences.insert(rng.randint(0, len(sentences)), distractors(rng, "revenue" in f))
        intro = pick(rng, INTRO_A, INTRO_B, pool)
        parts = ([intro.format(y=rng.randint(2019, 2025), co=rng.choice(COMPANIES))] if intro else []) + sentences
        statement = " ".join(parts)

    meta = {"scenario": scenario, "pool": pool, "unit": unit, "distractors": int(distract)}
    return statement, label, meta


def full_label(label):
    """All 18 fields, in schema order: {"text", "value"} or None."""
    return {key: label.get(key) for key in FIELDS}


def render(statement, label, template):
    core = {key: (label[key]["text"] if label.get(key) else None) for key in CORE}
    return {"messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": template.replace("<<STATEMENT>>", statement)},
        {"role": "assistant", "content": json.dumps(core, indent=2, ensure_ascii=False)},
    ]}


def main():
    prompt = render_prompt(SCHEMA)
    (DATASET / "prompt_template.txt").write_text(prompt)
    template = prompt.rstrip("\n")
    rng = random.Random(SEED)
    seen = set()
    rows = {}

    for split, n in GENERATED.items():
        items = []
        # Whole cycles, then the rest spread evenly over one more cycle, so that every scenario is
        # in every split (taking the first ones would leave "mixed" and "none" out of a small split).
        whole, rest = divmod(n, len(SCENARIOS))
        cycle = SCENARIOS * whole + [SCENARIOS[i * len(SCENARIOS) // rest] for i in range(rest)]
        for i, scenario in enumerate(cycle):
            pool = "B" if split == "test" and i % 2 == 1 else "A"
            for _ in range(100):
                statement, label, meta = make_example(scenario, pool, rng)
                if statement not in seen and not example_leaks(statement):
                    break
            else:
                raise RuntimeError("could not generate a unique statement")
            seen.add(statement)
            items.append((statement, label, {**meta, "source": "generated"}))
        for key in HAND_SPLITS[split]:
            statement, label = HAND[key]
            assert statement not in seen, key
            assert not example_leaks(statement), f"{key} contains a number of the prompt's examples"
            seen.add(statement)
            items.append((statement, label,
                          {"scenario": "hand", "pool": "A", "unit": "-", "distractors": "-", "source": key}))
        rng.shuffle(items)
        rows[split] = items

    index = []
    for split, items in rows.items():
        with open(DATASET / f"{split}.jsonl", "w") as chat, open(DATASET / f"{split}.labels.jsonl", "w") as side:
            for line, (statement, label, meta) in enumerate(items, start=1):
                chat.write(json.dumps(render(statement, label, template), ensure_ascii=False) + "\n")
                side.write(json.dumps({"line": line, "fields": full_label(label)}, ensure_ascii=False) + "\n")
                index.append([split, line, meta["source"], meta["scenario"], meta["pool"],
                              meta["unit"], meta["distractors"]])
    with open(DATASET / "index.csv", "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["split", "line", "source", "scenario", "pool", "unit", "distractors"])
        w.writerows(index)
    print({split: len(items) for split, items in rows.items()})


if __name__ == "__main__":
    main()
