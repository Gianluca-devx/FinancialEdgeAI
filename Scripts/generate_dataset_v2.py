#!/usr/bin/env python3
"""Generate the Phase 2b dataset (Specs/phase-2b-lora-wording.md), into Dataset/v2/.

Why a second generator: `generate_dataset.py` draws its statements from one random stream, so changing its
wording would change the frozen test split. This script writes new files only and never touches Dataset/*.

What is new, compared with the first dataset:
  * **Wording.** The first training pool has one phrase for net income and operating income, two for revenue and
    EPS. Here every metric has several names, in four disjoint lexicons:
        A    the first dataset's training wording (kept, and mixed in)
        A2   new training wording
        V    validation wording (never in train)
        C    test 2 wording (never in train or validation)
    The old test's unseen wording (pool B of generate_dataset.py) is listed here only to be kept out of train.
  * **Structures.** Prose as before, plus "Label: value" lines, bullet lists and rows of a table, in train; other
    structures in validation (the group, third person) and in test 2 (first person plural, headings, figures
    with dashes). A structure is a way of writing, so it is not checked as strictly as the wording: the wording
    is checked by Scripts/validate_dataset.py.
  * **Coverage.** Every core field is stated in at least 25% of the training statements (it was 10% to 12% for
    interest expense, operating cash flow and capex), and the null scenarios stay.

Outputs (Dataset/v2/): train.jsonl valid.jsonl test2.jsonl (chat format, the core prompt), the matching
*.labels.jsonl sidecars (all 18 fields, {"text", "value"} or null) and index.csv.

Usage: python3 Scripts/generate_dataset_v2.py
"""
import csv
import json
import random
import re
from decimal import Decimal
from pathlib import Path

import generate_dataset as g
from prompt_from_schema import example_leaks

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Dataset" / "v2"
SEED = 2026
COUNTS = {"valid": 48, "test2": 20}      # generated statements; hand-written ones are added
TOTAL = {"train": 480}                     # train: generated statements fill up to this total

# ---------------------------------------------------------------------------------------------------------
# Wording. Names are (phrase, plural). Lowercase phrases; the first letter is capitalised when a sentence starts.
# ---------------------------------------------------------------------------------------------------------
PLURAL = {"earnings from operations", "revenues", "total revenues", "net revenues", "operating revenues", "operating earnings", "total sales",
          "earnings attributable to shareholders", "per-share earnings"}


def n(*phrases):
    return [(p, p in PLURAL) for p in phrases]

NAMES = {
    "revenue": {
        "A": n("revenue", "total revenue"),
        "A2": n("revenues", "total revenues", "consolidated revenue", "net revenues", "turnover"),
        "B": n("net sales", "top-line revenue"),
        "V": n("sales revenue", "total sales"),
        "C": n("gross revenue", "operating revenues", "annual revenue"),
    },
    "operatingIncome": {
        "A": n("operating income"),
        "A2": n("operating earnings", "EBIT", "operating result", "profit from operating activities"),
        "B": n("operating profit", "income from operations"),
        "V": n("earnings from operations", "operating surplus"),
        "C": n("result from operations", "income from operating activities"),
    },
    "netIncome": {
        "A": n("net income"),
        "A2": n("profit for the year", "net income attributable to common shareholders", "net result",
                "profit after tax", "earnings attributable to shareholders"),
        "B": n("net profit", "net earnings"),
        "V": n("profit attributable to owners", "income for the year"),
        "C": n("profit for the period", "net income attributable to the company", "net income after tax"),
    },
    "eps": {
        "A": n("EPS", "diluted EPS"),
        "A2": n("earnings per diluted share", "net income per diluted share", "basic EPS", "profit per share"),
        "B": n("earnings per share", "diluted earnings per share"),
        "V": n("EPS on a diluted basis", "income per share"),
        "C": n("per-share earnings", "diluted per-share income"),
    },
}
# Complete clauses with {M}. "A" is the first dataset's SINGLE list (pool A forms), kept for the mix.
SINGLE = {
    "interestExpense": {
        "A": g.SINGLE["interestExpense"][0],
        "A2": ["finance costs were {M}", "net interest expense was {M}", "borrowing costs came to {M}",
               "interest and debt expense was {M}"],
        "B": g.SINGLE["interestExpense"][1],
        "V": ["interest charges were {M}", "the cost of borrowing was {M}"],
        "C": ["financing expense was {M}", "the interest burden came to {M}"],
    },
    "operatingCashFlow": {
        "A": g.SINGLE["operatingCashFlow"][0],
        "A2": ["cash flow from operating activities was {M}", "cash flows from operations were {M}",
               "operating cash generation came to {M}"],
        "B": g.SINGLE["operatingCashFlow"][1],
        "V": ["cash provided by operations was {M}", "operating activities brought in {M} of cash"],
        "C": ["cash from operations was {M}", "net cash flow from operating activities came to {M}"],
    },
    "capex": {
        "A": g.SINGLE["capex"][0],
        "A2": ["capital investments were {M}", "purchases of property and equipment were {M}",
               "capital outlays came to {M}", "investment in fixed assets was {M}"],
        "B": g.SINGLE["capex"][1],
        "V": ["spending on fixed assets was {M}", "additions to property and equipment were {M}"],
        "C": ["capital outlay was {M}", "the company invested {M} in plant and equipment"],
    },
    "totalDebt": {
        "A": g.SINGLE["totalDebt"][0], "A2": ["gross debt was {M}", "debt outstanding was {M}"],
        "B": g.SINGLE["totalDebt"][1], "V": ["outstanding debt came to {M}"], "C": ["the debt load was {M}"],
    },
    "shareholdersEquity": {
        "A": g.SINGLE["shareholdersEquity"][0], "A2": ["total equity was {M}", "equity attributable to shareholders was {M}"],
        "B": g.SINGLE["shareholdersEquity"][1], "V": ["shareholders' funds were {M}"], "C": ["book equity came to {M}"],
    },
    "currentAssets": {
        "A": g.SINGLE["currentAssets"][0], "A2": ["current assets amounted to {M}"],
        "B": g.SINGLE["currentAssets"][1], "V": ["short-term assets were {M}"], "C": ["assets due within a year were {M}"],
    },
    "currentLiabilities": {
        "A": g.SINGLE["currentLiabilities"][0], "A2": ["current liabilities amounted to {M}"],
        "B": g.SINGLE["currentLiabilities"][1], "V": ["short-term liabilities were {M}"], "C": ["liabilities due within a year were {M}"],
    },
    "cash": {
        "A": g.SINGLE["cash"][0], "A2": ["cash balances were {M}", "cash and short-term deposits were {M}"],
        "B": g.SINGLE["cash"][1], "V": ["cash on hand was {M}"], "C": ["the cash position was {M}"],
    },
}
UP = {"A": g.UP_A, "A2": ["gained", "improved", "jumped", "surged"], "B": g.UP_B,
      "V": ["strengthened", "accelerated", "firmed"], "C": ["swelled", "ticked up", "rallied"]}
DOWN = {"A": g.DOWN_A, "A2": ["shrank", "tumbled", "slid", "retreated"], "B": g.DOWN_B,
        "V": ["weakened", "softened", "fell back"], "C": ["dipped", "sank", "receded"]}
# The previous period, in the sentence: {py} is the previous fiscal year.
PRIOR = {"A": ["in the previous year", "a year earlier"],
         "A2": ["last year", "the year before", "in fiscal {py}"],
         "V": ["in the corresponding period of last year", "in {py}"],
         "C": ["in the earlier year", "for {py}"]}
# Growth, said another way: (up phrase, down phrase), each with {P}.
# A growth as a noun ("growth of 5%") and as a comparison ("5% higher than last year", complete in itself).
GROWTH_NOUN = {"A": [("an increase of {P}", "a decrease of {P}")],
               "A2": [("growth of {P}", "a decline of {P}")],
               "V": [("a rise of {P}", "a fall of {P}")],
               "C": [("an advance of {P}", "a contraction of {P}")]}
GROWTH_CMP = {"A": [], "A2": [("{P} higher than last year", "{P} lower than last year")], "V": [],
              "C": [("{P} above the earlier year", "{P} below the earlier year")]}
INTRO = {
    "A": g.INTRO_A,
    "A2": ["{co} published its {y} annual results.", "{co}: results for the year {y}.", "Financial summary, {y}.",
           "In {y}, {co} recorded the following.", None, None],
    "V": ["The Group's results for {y} were as follows.", "{co}, year ended {y}.", None],
    "C": ["Highlights for fiscal {y}.", "{co} reports on {y}.", "Results of operations, {y}.", None],
}
NONE_SENTENCES = {
    "A": g.NONE_A,
    "A2": ["{co} signed a long-term supply agreement.", "The company launched {n} new products in the year.",
           "Customer demand stayed steady across regions.", "A new chief operating officer joined in the autumn.",
           "The company employed {k} people.", "A dividend of ${d} per share was declared."],
    "V": ["The Group opened a regional office in the spring.", "Management reviewed its sustainability targets.",
          "The Group employed {k} staff at the year end."],
    "C": ["We completed the sale of a non-core division.", "We welcomed {n} new partners in the year.",
          "Our workforce numbered {k} people."],
}

# Number forms the parser reads. Each is a format with {n}.
MONEY_B = {"A": ["${n} billion", "USD {n} billion"], "A2": ["US${n} billion", "{n} billion USD"],
           "V": ["USD{n} billion"], "C": ["${n}B"]}
MONEY_M = {"A": ["${n} million", "USD {n} million"], "A2": ["US${n} million", "{n} million USD"],
           "V": ["USD{n} million"], "C": ["${n}M"]}
EPS_FORMS = {"A": ["${n}", "USD {n}"], "A2": ["US${n}", "{n} USD"], "V": ["USD{n}"], "C": ["$ {n}"]}
PCT_PLAIN = {"A": ["{n}%"], "A2": ["{n}%"], "V": ["{n} per cent", "{n}%"], "C": ["{n}%"]}

# Which lexicons a split draws from (and with which weight: the first dataset's pool is kept in train).
SPLIT_POOLS = {"train": ["A", "A2"], "valid": ["V"], "test2": ["C"]}
STYLES = {
    "train": [("prose", 5), ("lines", 2), ("bullets", 2), ("table", 2)],
    "valid": [("prose", 4), ("group", 3), ("lines", 1)],
    "test2": [("prose", 3), ("we", 3), ("heading", 2), ("dashes", 2)],
}
SCENARIOS = (
    ["full"] * 3 + ["income_basic"] * 3 + ["prior_no_growth"] * 3 + ["amounts_only"] * 2 + ["eps_only"] * 3
    + ["cash_flow"] * 4 + ["interest"] * 4 + ["balance_sheet"] * 3 + ["growth_only"] * 2 + ["mixed"] * 3
    + ["none"] * 2
)
SIGNED_STYLES = {"lines", "bullets", "table", "dashes", "heading", "group_signed"}
GROUP_KEYS = [("revenue", "revenueGrowth", "previousYearRevenue"),
              ("operatingIncome", None, None),
              ("netIncome", "netIncomeGrowth", "previousYearNetIncome"),
              ("eps", "epsGrowth", "previousYearEps")]


def pick_pool(split, rng):
    pools = SPLIT_POOLS[split]
    return pools[0] if len(pools) == 1 else rng.choice(pools if rng.random() < 0.7 else pools[1:])


def money(v, unit, rng, split):
    pool = pick_pool(split, rng)
    pool = "A" if split == "train" and rng.random() < 0.4 else pool
    if unit == "b":
        digits = str(v // 10) if v % 10 == 0 else f"{v // 10}.{v % 10}"
        forms = MONEY_B[pool]
    else:
        digits = f"{v:,}"
        forms = MONEY_M[pool]
    if split == "valid" and rng.random() < 0.5:
        forms = (MONEY_B if unit == "b" else MONEY_M)["A"]
    if split == "test2" and rng.random() < 0.6:
        forms = (MONEY_B if unit == "b" else MONEY_M)["A"]
    return rng.choice(forms).format(n=digits)


def per_share(cents, rng, split):
    digits = f"{cents // 100}.{cents % 100:02d}"
    pool = pick_pool(split, rng)
    forms = EPS_FORMS[pool] if rng.random() < 0.6 else EPS_FORMS["A"]
    return rng.choice(forms).format(n=digits)


def pct_digits(gt):
    return str(gt // 10) if gt % 10 == 0 else f"{gt // 10}.{gt % 10}"


def name_for(metric, split, rng):
    pools = SPLIT_POOLS[split]
    pool = pools[0] if len(pools) == 1 else ("A" if rng.random() < 0.35 else "A2")
    return rng.choice(NAMES[metric][pool])


def word(table, split, rng):
    pools = SPLIT_POOLS[split]
    pool = pools[0] if len(pools) == 1 else ("A" if rng.random() < 0.35 else "A2")
    if pool not in table:
        pool = "A2" if "A2" in table else pools[0]
    return rng.choice(table[pool])


def sent(text):
    return text[0].upper() + text[1:]


def lower_first(text):
    """Lowercase the first letter, unless it starts an acronym (EBIT, EPS)."""
    return text if len(text) > 1 and text[1].isupper() else text[0].lower() + text[1:]


def be(plural):
    return "were" if plural else "was"


def clause(name, plural, M, up, P, R, rng, split, py, has_year):
    """A prose clause about a metric: M printed amount, P printed percent (direction `up`), R printed previous amount."""
    verb = word(UP if up else DOWN, split, rng) if P else None
    w, noun = ("up", "increase") if up else ("down", "decrease")
    # A previous period named by its year ("in 2022") is only clear when the statement names the current year.
    options = [t for pool in SPLIT_POOLS[split] for t in PRIOR[pool] if has_year or "{py}" not in t]
    prior = rng.choice(options).format(py=py)
    last = SPLIT_POOLS[split][-1] if rng.random() < 0.7 else SPLIT_POOLS[split][0]
    noun = rng.choice(GROWTH_NOUN[last])[0 if up else 1].format(P=P) if P else None
    cmps = GROWTH_CMP[last] or GROWTH_CMP[SPLIT_POOLS[split][-1]]
    cmp_ = rng.choice(cmps)[0 if up else 1].format(P=P) if P and cmps else None
    cap, b = sent(name), be(plural)
    if M and P and R:
        opts = [f"{name} {b} {M}, {w} {P} from {R} {prior}", f"{cap} {verb} {P} to {M} from {R}",
                f"{name} reached {M}, {noun}, against {R} {prior}"]
    elif M and P:
        opts = [f"{name} {b} {M}, {w} {P} on the previous year", f"{cap} {verb} {P} to {M}",
                f"{name} came to {M}, {noun}", f"{name} {b} {M}, {noun} versus the previous year"]
        if cmp_:
            opts += [f"{name} {b} {M}, {cmp_}"]
    elif M and R:
        opts = [f"{name} {b} {M}, compared with {R} {prior}", f"{name} came to {M} against {R} {prior}"]
    elif M:
        opts = [f"{name} {b} {M}", f"{name} came to {M}", f"the company reported {name} of {M}",
                f"{name} amounted to {M}"]
    elif P and R:
        opts = [f"{name} {verb} {P} from {R} {prior}"]
    elif P:
        opts = [f"{name} {verb} {P}", f"{name} showed {noun}"]
        if cmp_:
            opts += [f"{name} {b} {cmp_}"]
    else:
        opts = [f"{name} {prior} {b} {R}"]
    return rng.choice(opts)


def plan(scenario, rng):
    f = g.plan_fields(scenario, rng)
    # Spread the rarer fields over the other scenarios, so that every field is stated often enough.
    if scenario not in ("none", "growth_only", "cash_flow", "interest", "balance_sheet", "eps_only"):
        for key, p in (("operatingCashFlow", 0.28), ("capex", 0.32), ("interestExpense", 0.28)):
            if rng.random() < p:
                f.add(key)
    if scenario not in ("none", "growth_only"):
        for key, base, p in (("previousYearRevenue", "revenue", 0.22), ("previousYearNetIncome", "netIncome", 0.22),
                             ("epsGrowth", "eps", 0.55), ("previousYearEps", "eps", 0.25)):
            if base in f and key not in f and rng.random() < p:
                f.add(key)
    if scenario in ("cash_flow", "interest") and rng.random() < 0.35:
        f |= {"operatingCashFlow", "capex", "interestExpense"} if rng.random() < 0.5 else {"interestExpense"}
    return f


def make_example(scenario, split, rng):
    f = plan(scenario, rng)
    style = rng.choices([s for s, _ in STYLES[split]], [w for _, w in STYLES[split]])[0]
    signed = style in SIGNED_STYLES
    no_amounts = scenario in ("growth_only", "none", "eps_only")
    unit = "m" if not no_amounts and rng.random() < 0.2 else "b"
    year = rng.randint(2019, 2025)

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
    amounts = {"revenue": rev, "operatingIncome": op, "netIncome": net,
               "interestExpense": max(1, int(op * rng.uniform(0.03, 0.20))),
               "operatingCashFlow": max(1, int(net * rng.uniform(0.9, 1.8))),
               "totalDebt": max(1, int(rev * rng.uniform(0.3, 1.5))),
               "shareholdersEquity": max(1, int(rev * rng.uniform(0.5, 2.0))),
               "currentAssets": max(1, int(rev * rng.uniform(0.2, 0.6)))}
    amounts["capex"] = max(1, int(amounts["operatingCashFlow"] * rng.uniform(0.2, 0.7)))
    amounts["currentLiabilities"] = max(1, int(amounts["currentAssets"] * rng.uniform(0.4, 0.9)))
    amounts["cash"] = max(1, int(amounts["currentAssets"] * rng.uniform(0.2, 0.6)))
    cents = rng.randint(5, 1500)

    growth = {"revenue": g.gen_growth(rng), "netIncome": g.gen_growth(rng), "eps": g.gen_growth(rng)}
    og = g.gen_growth(rng)
    rev_prior = g.prior_for(rev, growth["revenue"] if "revenueGrowth" in f else None, rng)
    net_prior = g.prior_for(net, growth["netIncome"] if "netIncomeGrowth" in f else None, rng)
    eps_prior = g.prior_for(cents, growth["eps"] if "epsGrowth" in f else None, rng)
    op_prior = g.prior_for(op, og, rng)
    show_op_g = "operatingIncome" in f and rng.random() < 0.3
    show_op_prior = "operatingIncome" in f and rng.random() < 0.25

    label = {}

    def amount(key, v):
        text = money(v, unit, rng, split)
        label[key] = {"text": text, "value": g.num(g.to_billions(v, unit))}
        return text

    def percent(key, gv):
        """Printed growth. Prose says the direction in words; the signed styles print +n% or -n%."""
        digits = pct_digits(abs(gv))
        if signed:
            text = ("+" if gv > 0 else "-") + digits + "%"
            label[key] = {"text": text, "value": g.num(Decimal(gv) / 10)}
            return text
        form = rng.choice(PCT_PLAIN[pick_pool(split, rng)]).format(n=digits)
        label[key] = {"text": form if gv > 0 else "-" + form, "value": g.num(Decimal(gv) / 10)}
        return form

    def unsigned_pct(gt):
        return rng.choice(PCT_PLAIN[pick_pool(split, rng)]).format(n=pct_digits(abs(gt)))

    def shown_amount(key):
        return amount(key, amounts[key]) if key in f else None

    def shown_percent(key, base):
        return percent(key, growth[base]) if key in f else None

    rev_s = shown_amount("revenue")
    rev_g = shown_percent("revenueGrowth", "revenue")
    rev_p = amount("previousYearRevenue", rev_prior) if "previousYearRevenue" in f else None
    op_s = shown_amount("operatingIncome")
    op_g = ("+" if og > 0 else "-") + pct_digits(abs(og)) + "%" if (show_op_g and signed) else (
        unsigned_pct(og) if show_op_g else None)
    op_p = money(op_prior, unit, rng, split) if show_op_prior else None
    net_s = shown_amount("netIncome")
    net_g = shown_percent("netIncomeGrowth", "netIncome")
    net_p = amount("previousYearNetIncome", net_prior) if "previousYearNetIncome" in f else None
    eps_s = eps_g = eps_p = None
    if "eps" in f:
        eps_s = per_share(cents, rng, split)
        label["eps"] = {"text": eps_s, "value": g.num(Decimal(cents) / 100)}
    if "previousYearEps" in f:
        eps_p = per_share(eps_prior, rng, split)
        label["previousYearEps"] = {"text": eps_p, "value": g.num(Decimal(eps_prior) / 100)}
    if "epsGrowth" in f:
        eps_g = percent("epsGrowth", growth["eps"])

    metrics = [("revenue", rev_s, growth["revenue"] > 0, rev_g, rev_p),
               ("operatingIncome", op_s, og > 0, op_g, op_p),
               ("netIncome", net_s, growth["netIncome"] > 0, net_g, net_p),
               ("eps", eps_s, growth["eps"] > 0, eps_g, eps_p)]
    if rng.random() < 0.15:
        metrics = [metrics[2], metrics[0], metrics[1], metrics[3]]
    singles = []
    for key in SINGLE:
        if key in f:
            pool = pick_pool(split, rng)
            if split == "train" and rng.random() < 0.3:
                pool = "A"
            singles.append((key, rng.choice(SINGLE[key][pool]).format(M=amount(key, amounts[key]))))

    meta = {"scenario": scenario, "pool": "+".join(SPLIT_POOLS[split]), "unit": unit, "style": style,
            "distractors": 0}
    py = year - 1
    co = rng.choice(g.COMPANIES)
    if scenario == "none":
        pool_none = NONE_SENTENCES[pick_pool(split, rng)]
        chosen = rng.sample(pool_none, min(rng.randint(2, 3), len(pool_none)))     # different sentences
        sentences = [t.format(n=rng.randint(5, 90), k=f"{rng.randint(2, 180) * 1000:,}",
                              d=f"{rng.randint(5, 150) / 100:.2f}", p=f"{rng.randint(1000, 25000) / 100:.2f}", co=co)
                     for t in chosen]
        return " ".join(sentences), label, meta

    distract = rng.random() < 0.4
    meta["distractors"] = int(distract)
    extras = []
    for _ in range(rng.randint(1, 2) if distract else 0):
        for _ in range(20):
            text = g.distractors(rng, "revenue" in f)
            if all(text[:14] != e[:14] for e in extras):       # not the same kind of sentence twice
                extras.append(text)
                break
    lines = render_style(style, split, rng, metrics, singles, extras, year, py, co, f)
    return lines, label, meta


def metric_cells(metrics):
    """Rows (name, M, P, R) for the styles that print a value per label."""
    rows = []
    for key, M, up, P, R in metrics:
        if M is None and P is None and R is None:
            continue
        rows.append((key, M, P, R, up))
    return rows


def row_name(key, split, rng):
    return name_for(key, split, rng)[0]


def render_style(style, split, rng, metrics, singles, extras, year, py, co, f):
    intro_pool = pick_pool(split, rng)
    intro = rng.choice(INTRO[intro_pool])
    intro = intro.format(y=year, co=co) if intro else None
    prior_word = rng.choice(["previous year", "last year"])
    rows = metric_cells(metrics)
    single_text = [t for _, t in singles]

    if style in ("prose", "group", "we"):
        sentences = []
        for key, M, up, P, R in metrics:
            if M is None and P is None and R is None:
                continue
            name, plural = name_for(key, split, rng)
            text = clause(name, plural, M, up, P, R, rng, split, py, intro is not None)
            if style == "we" and text.lower().startswith(name.lower()):
                text = "our " + lower_first(text)
            if style == "group":
                text = text.replace("the company", "the Group")
            if sentences and rng.random() < 0.3:
                sentences[-1] += rng.choice([", while ", "; ", ", and "]) + lower_first(text)
            else:
                sentences.append(sent(text))
        for t in single_text:
            sentences.append(sent("our " + t if style == "we" and rng.random() < 0.5 and not t.startswith("the ") else t))
        if rng.random() < 0.3:
            rng.shuffle(sentences)
        sentences = [s + "." for s in sentences]
        for extra in extras:
            sentences.insert(rng.randint(0, len(sentences)), extra)
        return " ".join(([intro] if intro else []) + sentences)

    if style == "table" and not any(M or P or R for _, M, P, R, _ in rows):
        style = "lines"        # a table with no row of its own is just lines
    out = []
    if style in ("lines", "bullets"):
        bullet = rng.choice(["- ", "* ", "• "]) if style == "bullets" else ""
        for key, M, P, R, up in rows:
            if not (M or P or R):
                continue
            name = row_name(key, split, rng)
            if M:
                text = f"{sent(name)}: {M}"
                if P:
                    text += f" ({P} year over year)" if rng.random() < 0.5 else f", change {P}"
                if R:
                    text += f"; {prior_word}: {R}"
            elif R:
                text = f"{sent(name)}, {prior_word}: {R}" + (f" ({P})" if P else "")
            else:
                text = f"{sent(name)} growth: {P}"
            out.append(bullet + text)
        for t in single_text:
            out.append(bullet + sent(t))
        out += [bullet + e for e in extras]
        head = [intro] if intro else []
        return "\n".join(head + out)

    if style == "table":
        header = rng.choice([f"Metric | FY{year} | FY{py} | Change", f"Item | {year} | {py} | Change"])
        out = [header]
        for key, M, P, R, up in rows:
            if not (M or P or R):
                continue
            out.append(f"{sent(row_name(key, split, rng))} | {M or 'n/a'} | {R or 'n/a'} | {P or 'n/a'}")
        for _, text in singles:
            out.append(sent(text))
        out += extras
        return "\n".join(out)

    if style == "heading":
        out = [rng.choice(["Results of operations", "Financial highlights", "Summary of results"]) + f", fiscal {year}:"]
        for key, M, P, R, up in rows:
            if not (M or P or R):
                continue
            name = row_name(key, split, rng)
            pieces = []
            if M:
                pieces.append(M)
            if P:
                pieces.append(f"({P} year over year)" if M else f"{P}")
            if R:
                pieces.append(f"against {R} in {py}")
            out.append(f"{sent(name)}" + (" growth" if not M and P else "") + ": " + " ".join(pieces))
        for t in single_text:
            out.append(sent(t))
        out += extras
        return "\n".join(out)

    if style == "dashes":
        out = []
        for key, M, P, R, up in rows:
            if not (M or P or R):
                continue
            name = row_name(key, split, rng)
            bits = []
            if M:
                bits.append(f"FY{year}: {M}")
            if R:
                bits.append(f"FY{py}: {R}")
            if P:
                bits.append(f"change: {P}")
            out.append(f"{sent(name)} — " + "; ".join(bits))
        for t in single_text:
            out.append(sent(t))
        out += extras
        return ("\n".join(([intro] if intro else []) + out))
    raise ValueError(style)


# ---------------------------------------------------------------------------------------------------------
# Held-out wording. A pool's phrases must not appear in the splits that may not see them:
#   train must not contain pool B (the old test), V or C;  valid must not contain B or C;  test2 must not contain B or V.
# ---------------------------------------------------------------------------------------------------------
NUMBER_FORMS = {
    "B": [r"\dbn\b", r"billion dollars", r"million dollars", r"\d\s?percent", r"\d dollars", r"\$\d[\d.,]*m\b"],
    "V": [r"USD\d", r"\d per cent"],
    "C": [r"\$\d[\d.,]*[BM]\b", r"\$ \d"],
}
EXTRA_PHRASES = {
    "B": ["in the prior year", "on the prior year", "against", "year-over-year", "edged up", "top-line",
          "interest costs", "capital spending", "cash generated from operations",
          "net cash provided by operating activities", "property, plant and equipment", "total borrowings",
          "stockholders' equity"],
    "V": ["interest charges", "cost of borrowing", "cash provided by operations", "operating activities brought in",
          "spending on fixed assets", "additions to property and equipment", "outstanding debt",
          "shareholders' funds", "short-term assets", "short-term liabilities", "cash on hand"],
    "C": ["results of operations", "key figures", "financial highlights", "summary of results", "financing expense",
          "interest burden", "cash from operations", "net cash flow from operating activities", "capital outlay",
          "plant and equipment", "debt load", "book equity", "assets due within a year",
          "liabilities due within a year", "cash position"],
}


def _fragments(template):
    return [re.sub(r"\s+", " ", x).strip().lower() for x in re.split(r"\{[^}]*\}", template)]


def phrases_of(pool):
    """The held-out phrases of a pool: names, clauses, verbs, previous-period and growth forms, intros, filler."""
    found = set()
    for names in NAMES.values():
        found.update(p.lower() for p, _ in names[pool])
    for table in SINGLE.values():
        for t in table[pool]:
            found.update(f for f in _fragments(t) if len(f.split()) >= 3 or pool == "B" and f)
    for table in (UP, DOWN):
        found.update(w.lower() for w in table[pool])
    for table in (PRIOR, INTRO, NONE_SENTENCES):
        if pool in table:
            for t in table[pool]:
                if t:
                    found.update(f for f in _fragments(t) if len(f.split()) >= 3)
    for table in (GROWTH_NOUN, GROWTH_CMP):
        for t in table.get(pool, []):
            for form in t:
                found.update(f for f in _fragments(form) if len(f.split()) >= 3 or f in ("a rise of", "a fall of"))
    found.update(EXTRA_PHRASES[pool])
    if pool == "B":
        found.update(f for t in (g.INTRO_B + g.NONE_B) if t for f in _fragments(t) if len(f.split()) >= 3)
        found.discard("against")      # a common word: only the phrases around it are held out
    return {p for p in found if p}


FORBIDDEN = {"train": ["B", "V", "C"], "valid": ["B", "C"], "test2": ["B", "V"]}


def forbidden_hits(statement, split):
    """Held-out wording found in a statement of `split`: [(pool, what)]."""
    low = statement.lower()
    hits = []
    for pool in FORBIDDEN[split]:
        for phrase in sorted(phrases_of(pool)):
            if re.search(rf"(?<![a-z]){re.escape(phrase)}(?![a-z])", low):
                hits.append((pool, phrase))
        for pattern in NUMBER_FORMS[pool]:
            if re.search(pattern, statement):
                hits.append((pool, pattern))
    return hits


# ---------------------------------------------------------------------------------------------------------
# Hand-written statements (labels checked by hand; each field is (text as printed, true value)).
# ---------------------------------------------------------------------------------------------------------
hand = g.hand
HAND_TRAIN_NEW = {
    "H25": hand(
        "Consolidated revenue came to $64.2 billion, a gain of 7% on last year. Profit for the year was $5.1 "
        "billion. Cash flow from operating activities was $9.4 billion, with capital investments of $3.3 billion.",
        revenue=("$64.2 billion", 64.2), revenueGrowth=("7%", 7), netIncome=("$5.1 billion", 5.1),
        operatingCashFlow=("$9.4 billion", 9.4), capex=("$3.3 billion", 3.3)),
    "H26": hand(
        "Northwind Holdings: operating earnings of $890 million (up 4% from $856 million the year before) and "
        "finance costs of $64 million. Diluted EPS was $1.82.",
        operatingIncome=("$890 million", 0.89), interestExpense=("$64 million", 0.064), eps=("$1.82", 1.82)),
    "H27": hand(
        "Total revenues were US$11.3 billion in fiscal 2025 against US$10.6 billion in fiscal 2024. Net income "
        "attributable to common shareholders was US$1.4 billion.",
        revenue=("US$11.3 billion", 11.3), previousYearRevenue=("US$10.6 billion", 10.6),
        netIncome=("US$1.4 billion", 1.4)),
    "H28": hand(
        "Net result: $740 million, -6% on the previous year. Turnover: $8.9 billion, +3%.",
        revenue=("$8.9 billion", 8.9), revenueGrowth=("+3%", 3), netIncome=("$740 million", 0.74),
        netIncomeGrowth=("-6%", -6)),
    "H29": hand(
        "The group earned a profit after tax of $2.2 billion, compared with $2.5 billion last year. Revenues of "
        "$30.5 billion were 2% lower.",
        revenue=("$30.5 billion", 30.5), revenueGrowth=("-2%", -2), netIncome=("$2.2 billion", 2.2),
        previousYearNetIncome=("$2.5 billion", 2.5)),
    "H30": hand(
        "Earnings per diluted share rose 11% to $3.04, from $2.74 in fiscal 2024. Operating result was $4.1 "
        "billion; interest and debt expense was $310 million.",
        eps=("$3.04", 3.04), epsGrowth=("11%", 11), previousYearEps=("$2.74", 2.74),
        operatingIncome=("$4.1 billion", 4.1), interestExpense=("$310 million", 0.31)),
    "H31": hand(
        "Customer demand stayed steady during the year. The company employed 12,400 people. A dividend of $0.85 per "
        "share was declared."),
    "H32": hand(
        "Revenues rose 5% to $22.8 billion, EBIT was $3.6 billion and profit for the year was $2.7 billion, "
        "versus $2.3 billion last year. Cash flows from operations were $4.2 billion.",
        revenue=("$22.8 billion", 22.8), revenueGrowth=("5%", 5), operatingIncome=("$3.6 billion", 3.6),
        netIncome=("$2.7 billion", 2.7), previousYearNetIncome=("$2.3 billion", 2.3),
        operatingCashFlow=("$4.2 billion", 4.2)),
}
HAND_TEST2 = {
    "T1": hand(
        "Highlights for fiscal 2025. We generated gross revenue of $18.4 billion, up 9%, and result from "
        "operations of $2.9 billion. Profit for the period reached $2.1 billion, compared with $1.9 billion in "
        "the earlier year.",
        revenue=("$18.4 billion", 18.4), revenueGrowth=("9%", 9), operatingIncome=("$2.9 billion", 2.9),
        netIncome=("$2.1 billion", 2.1), previousYearNetIncome=("$1.9 billion", 1.9)),
    "T2": hand(
        "Key figures (USD): operating revenues 7.6 billion; income from operating activities 1.1 billion; net "
        "income attributable to the company 0.8 billion.",
        revenue=("7.6 billion", 7.6), operatingIncome=("1.1 billion", 1.1), netIncome=("0.8 billion", 0.8)),
    "T3": hand(
        "Annual revenue was $540 million. Our result from operations improved 15% to $88 million, and cash from "
        "operations was $97 million. We invested $31 million in plant and equipment.",
        revenue=("$540 million", 0.54), operatingIncome=("$88 million", 0.088),
        operatingCashFlow=("$97 million", 0.097), capex=("$31 million", 0.031)),
    "T4": hand(
        "Diluted per-share income was $4.12 (previous year: $3.77). Net income after tax was $3.3 billion; in the "
        "previous year it was $3.0 billion.",
        eps=("$4.12", 4.12), previousYearEps=("$3.77", 3.77), netIncome=("$3.3 billion", 3.3),
        previousYearNetIncome=("$3.0 billion", 3.0)),
    "T5": hand(
        "Results of operations — Gross revenue: $91.0 billion (+4% year over year). Income from operating "
        "activities: $12.2 billion. Financing expense: $0.9 billion. Net cash flow from operating activities: "
        "$15.1 billion; capital outlay: $5.0 billion.",
        revenue=("$91.0 billion", 91.0), revenueGrowth=("+4%", 4), operatingIncome=("$12.2 billion", 12.2),
        interestExpense=("$0.9 billion", 0.9), operatingCashFlow=("$15.1 billion", 15.1),
        capex=("$5.0 billion", 5.0)),
    "T6": hand(
        "The company completed the sale of its European division and welcomed 1,200 new employees. Free cash flow "
        "was $2.8 billion and the operating margin was 14.1%."),
    "T7": hand(
        "Gross revenue climbed 6% to $27.3 billion. Net income attributable to the company dipped 3% to $2.5 "
        "billion.",
        revenue=("$27.3 billion", 27.3), revenueGrowth=("6%", 6), netIncome=("$2.5 billion", 2.5),
        netIncomeGrowth=("-3%", -3)),
    "T8": hand(
        "We ended the year with the debt load at $14 billion and the cash position at $3.2 billion. Annual "
        "revenue was $26 billion and profit for the period was $1.7 billion.",
        revenue=("$26 billion", 26), netIncome=("$1.7 billion", 1.7), totalDebt=("$14 billion", 14),
        cash=("$3.2 billion", 3.2)),
    "T9": hand(
        "Revenue growth was 8% and net income growth was 5%, while diluted per-share income growth was 6%. No "
        "absolute figures were disclosed.",
        revenueGrowth=("8%", 8), netIncomeGrowth=("5%", 5), epsGrowth=("6%", 6)),
    "T10": hand(
        "Operating revenues for 2025 amounted to $3.9 billion versus $3.6 billion in 2024. Result from "
        "operations: $510 million versus $480 million.",
        revenue=("$3.9 billion", 3.9), previousYearRevenue=("$3.6 billion", 3.6),
        operatingIncome=("$510 million", 0.51)),
}
# The first dataset's hand-written training statements, kept in the v2 training split when their wording passes
# the check of Scripts/validate_dataset.py (decided there, not here).
V1_HAND_TRAIN = [k for k in g.HAND_SPLITS["train"] if not forbidden_hits(g.HAND[k][0], "train")]


def build(split):
    rng = random.Random(f"{SEED}-{split}")
    items, seen = [], set()
    hand_items = []
    if split == "train":
        hand_items = [(k, *g.HAND[k]) for k in V1_HAND_TRAIN] + [(k, *HAND_TRAIN_NEW[k]) for k in HAND_TRAIN_NEW]
    elif split == "test2":
        hand_items = [(k, *HAND_TEST2[k]) for k in HAND_TEST2]
    n_gen = (TOTAL["train"] - len(hand_items)) if split == "train" else COUNTS[split]
    whole, rest = divmod(n_gen, len(SCENARIOS))
    cycle = SCENARIOS * whole + [SCENARIOS[i * len(SCENARIOS) // rest] for i in range(rest)] if rest else SCENARIOS * whole
    for scenario in cycle:
        for _ in range(200):
            statement, label, meta = make_example(scenario, split, rng)
            if (statement not in seen and not example_leaks(statement) and '"' not in statement
                    and not forbidden_hits(statement, split)):
                break
        else:
            raise RuntimeError("could not generate a unique statement")
        seen.add(statement)
        items.append((statement, label, {**meta, "source": "generated"}))
    for key, statement, label in hand_items:
        assert statement not in seen, key
        assert not example_leaks(statement), f"{key} contains a number of the prompt's examples"
        seen.add(statement)
        items.append((statement, label, {"scenario": "hand", "pool": "+".join(SPLIT_POOLS[split]), "unit": "-",
                                         "distractors": "-", "style": "hand", "source": key}))
    rng.shuffle(items)
    return items


def main():
    template = (g.DATASET / "prompt_template.txt").read_text().rstrip("\n")
    OUT.mkdir(exist_ok=True)
    index = []
    sizes = {}
    for split in ("train", "valid", "test2"):
        items = build(split)
        sizes[split] = len(items)
        with open(OUT / f"{split}.jsonl", "w") as chat, open(OUT / f"{split}.labels.jsonl", "w") as side:
            for line, (statement, label, meta) in enumerate(items, start=1):
                chat.write(json.dumps(g.render(statement, label, template), ensure_ascii=False) + "\n")
                side.write(json.dumps({"line": line, "fields": g.full_label(label)}, ensure_ascii=False) + "\n")
                index.append([split, line, meta["source"], meta["scenario"], meta["pool"], meta["unit"],
                              meta["distractors"], meta["style"]])
    with open(OUT / "index.csv", "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["split", "line", "source", "scenario", "pool", "unit", "distractors", "style"])
        w.writerows(index)
    print(sizes)


if __name__ == "__main__":
    main()
