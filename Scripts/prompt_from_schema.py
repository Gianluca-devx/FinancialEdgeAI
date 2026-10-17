#!/usr/bin/env python3
"""Build the extraction prompt from Dataset/schema.json.

The list of fields in the prompt is generated from the schema, so the prompt, the parser, the
evaluation and the app cannot disagree about which fields exist. Only the core fields are asked in
this prompt: the extended fields belong to a second call with its own prompt.

Usage:
    python3 Scripts/prompt_from_schema.py                   print the core prompt
    python3 Scripts/prompt_from_schema.py --tier extended   print the extended prompt
    python3 Scripts/prompt_from_schema.py --write           write both prompt files of Dataset/
    python3 Scripts/prompt_from_schema.py --check           exit 1 if a prompt file differs

`generate_dataset.py` and `validate_dataset.py` import render_prompt() from here.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"

# The examples written in the rules of the prompt. No statement of the dataset may contain these
# numbers: a statement that is also an example of the prompt would be answered by the prompt itself.
EXAMPLE_AMOUNT = "$7.4 billion"
EXAMPLE_NEGATIVE = "(2.4) billion"
EXAMPLE_PERCENT = "8.2%"
EXAMPLE_DECREASE = "-6.8%"
EXAMPLE_NUMBERS = ("7.4", "2.4", "8.2", "6.8")


def example_leaks(statement):
    """The numbers of the prompt's own examples that a statement also contains."""
    return [n for n in EXAMPLE_NUMBERS if re.search(rf"(?<![\d.,]){re.escape(n)}(?!\d)", statement)]


def load_schema():
    return json.loads((DATASET / "schema.json").read_text())


def tier_fields(schema, tier="core"):
    return [f for f in schema["fields"] if f["tier"] == tier]


def core_fields(schema):
    return tier_fields(schema, "core")


def render_prompt(schema, tier="core"):
    """The user prompt of a tier, with <<STATEMENT>> where the statement goes. Ends with a newline.

    The core prompt is the one measured by the baselines and must not change. The extended prompt is
    its own text: the same structure, the extended fields, and no growth rule.
    """
    if tier == "extended":
        return _render_extended(schema)
    fields = core_fields(schema)
    lines = [
        "You are a financial information extraction system.",
        "Analyze the following financial statement:",
        '"<<STATEMENT>>"',
        "Extract the following fields:",
        *[f"- {f['key']}: {f['description']}" for f in fields],
        "",
        "Rules:",
        "",
        "1. Return ONLY valid JSON. Do not include Markdown or explanations.",
        "2. Every value is a string copied exactly as printed in the text, with its currency symbol, "
        f'its unit word and its sign, for example "{EXAMPLE_AMOUNT}", "{EXAMPLE_NEGATIVE}" or '
        f'"{EXAMPLE_PERCENT}". Use null if the value is not in the text.',
        "3. Do not calculate, convert or round anything.",
        "4. Growth fields: only if the text states the percent change. Write a decrease with a "
        f'leading minus, for example "{EXAMPLE_DECREASE}".',
        "",
        "Use exactly this JSON structure:",
        "",
        "{",
        *[f'"{f["key"]}": null' + ("," if i < len(fields) - 1 else "") for i, f in enumerate(fields)],
        "}",
    ]
    return "\n".join(lines) + "\n"


def _render_extended(schema):
    fields = tier_fields(schema, "extended")
    lines = [
        "You are a financial information extraction system.",
        "Analyze the following financial statement:",
        '"<<STATEMENT>>"',
        "Extract the following fields:",
        *[f"- {f['key']}: {f['description']}" for f in fields],
        "",
        "Rules:",
        "",
        "1. Return ONLY valid JSON. Do not include Markdown or explanations.",
        "2. Every value is a string copied exactly as printed in the text, with its currency symbol, "
        f'its unit word and its sign, for example "{EXAMPLE_AMOUNT}" or "{EXAMPLE_NEGATIVE}". '
        "Use null if the value is not in the text.",
        "3. Do not calculate, convert or round anything.",
        "",
        "Use exactly this JSON structure:",
        "",
        "{",
        *[f'"{f["key"]}": null' + ("," if i < len(fields) - 1 else "") for i, f in enumerate(fields)],
        "}",
    ]
    return "\n".join(lines) + "\n"


PROMPT_FILES = {"core": "prompt_template.txt", "extended": "prompt_template_extended.txt"}


def main():
    schema = load_schema()
    tier = sys.argv[sys.argv.index("--tier") + 1] if "--tier" in sys.argv else None
    tiers = [tier] if tier else list(PROMPT_FILES)
    if "--write" in sys.argv:
        for t in tiers:
            target = DATASET / PROMPT_FILES[t]
            target.write_text(render_prompt(schema, t))
            print(f"wrote {target.relative_to(ROOT)}")
    elif "--check" in sys.argv:
        for t in tiers:
            if (DATASET / PROMPT_FILES[t]).read_text() != render_prompt(schema, t):
                sys.exit(f"Dataset/{PROMPT_FILES[t]} differs from what Dataset/schema.json renders")
            print(f"{PROMPT_FILES[t]} matches the schema")
    else:
        print(render_prompt(schema, tier or "core"), end="")


if __name__ == "__main__":
    main()
