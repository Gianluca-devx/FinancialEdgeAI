#!/usr/bin/env python3
"""Build the extraction prompt from Dataset/schema.json.

The list of fields in the prompt is generated from the schema, so the prompt, the parser, the
evaluation and the app cannot disagree about which fields exist. Only the core fields are asked in
this prompt: the extended fields belong to a second call with its own prompt.

Usage:
    python3 Scripts/prompt_from_schema.py           print the prompt
    python3 Scripts/prompt_from_schema.py --write   write Dataset/prompt_template.txt
    python3 Scripts/prompt_from_schema.py --check   exit 1 if Dataset/prompt_template.txt differs

`generate_dataset.py` and `validate_dataset.py` import render_prompt() from here.
"""
import json
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


def load_schema():
    return json.loads((DATASET / "schema.json").read_text())


def core_fields(schema):
    return [f for f in schema["fields"] if f["tier"] == "core"]


def render_prompt(schema):
    """The user prompt, with <<STATEMENT>> where the statement goes. Ends with a newline."""
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


def main():
    schema = load_schema()
    prompt = render_prompt(schema)
    target = DATASET / "prompt_template.txt"
    if "--write" in sys.argv:
        target.write_text(prompt)
        print(f"wrote {target.relative_to(ROOT)}")
    elif "--check" in sys.argv:
        if target.read_text() != prompt:
            sys.exit("Dataset/prompt_template.txt differs from what Dataset/schema.json renders")
        print("prompt_template.txt matches the schema")
    else:
        print(prompt, end="")


if __name__ == "__main__":
    main()
