#!/usr/bin/env python3
"""Phase 3, the overview and business sections (Specs/phase-3-report-sections.md): the texts and the checker.

Standard library only. Nothing from a report is printed: texts, labels, answers and flags stay in RealSet/ (git-ignored).

  locate    --text DIR --out FILE   S1: in every <name>.pdfkit.json of DIR (the page texts of a report), the first page with
                                    an "Item 1. Business" heading (also with a dash or a colon) that holds fewer than 4 Item
                                    headings, so not the table of contents; the text from that heading on, over at most 8 pages
                                    (Scripts/lora/section_generate.py window cuts it at 2,500 tokens); reports with no such page
                                    are listed as missed
  testsplit --out FILE              the 30 statements of the frozen test split (Dataset/test.jsonl) as texts, for "not stated"
  check     --texts FILE --answers FILE [FILE ...] [--labels FILE] [--verdicts FILE] --out FILE
                                    S8: format, invented (the flags, and the answers with a flag confirmed by hand), coverage,
                                    not stated; writes the counts to FILE and the flags still waiting for a verdict to
                                    FILE's name with ".flags.json"

The verdicts file maps "<id>|<kind>|<item>" to "confirmed" (not supported by the text) or "rejected" (supported, in
another form): one verdict per report and item, whatever the answer, section, seed or condition.
"""
import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TEST_SPLIT = REPO / "Dataset" / "test.jsonl"
PROMPTS = REPO / "Prompts"
SECTIONS = ("overview", "business")
WORD_LIMIT = {"overview": 60, "business": 100}         # the format check (S4)
PROMPT_WORDS = {"overview": 50, "business": 85}        # what the prompts ask for, a margin under the check
NOT_STATED = "Not stated in the text."
TOKEN_LIMIT = 2500
MAX_PAGES = 8
TOC_HEADINGS = 4

ITEM1 = re.compile(r"(?im)^[ \t]*item[ \t]*1[ \t]*\.?[ \t]*[-–—:]?[ \t]*business\b")
ITEM_HEADING = re.compile(r"(?im)^[ \t]*item[ \t]*\d+[a-c]?[ \t]*[.:\-–—]")
STATEMENT = re.compile(r'financial statement:\s*"(.*)"\s*Extract the following fields', re.S)

NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")
WORD = re.compile(r"[A-Za-z][A-Za-z0-9&.'’\-]*")
LEGAL_FORMS = {"inc", "corp", "corporation", "company", "co", "ltd", "llc", "plc", "group", "holdings", "i"}
ALIASES = {"u.s": ("united states",), "us": ("united states", "u.s"), "usa": ("united states", "u.s"),
           "u.k": ("united kingdom",), "uk": ("united kingdom", "u.k")}


# ---- S1: the start of Item 1 -------------------------------------------------------------------------------------

def item1_page(pages):
    """The 1-based number of the first page with an Item 1 "Business" heading that is not the table of contents."""
    for number, text in enumerate(pages, start=1):
        if ITEM1.search(text) and len(ITEM_HEADING.findall(text)) < TOC_HEADINGS:
            return number
    return None


def item1_text(pages, number):
    """The text from the heading on, over at most MAX_PAGES pages, and the page numbers it comes from."""
    first = pages[number - 1]
    parts = [first[ITEM1.search(first).start():]] + pages[number:number - 1 + MAX_PAGES]
    numbers = list(range(number, min(len(pages), number - 1 + MAX_PAGES) + 1))
    return "\n".join(part.strip() for part in parts), numbers


def locate(text_dir: Path, out: Path):
    reports, missed = {}, []
    for path in sorted(text_dir.glob("*.pdfkit.json")):
        name = path.name[:-len(".pdfkit.json")]
        pages = json.loads(path.read_text())
        number = item1_page(pages)
        if number is None:
            missed.append(name)
            continue
        text, numbers = item1_text(pages, number)
        reports[name] = {"pages": numbers, "text": text}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"rule": "S1", "from": str(text_dir), "reports": reports, "missed": missed}, indent=1))
    print(f"located: {len(reports)} of {len(reports) + len(missed)} reports, {len(missed)} missed")


def cut(text, encode, decode, limit=TOKEN_LIMIT):
    """The text cut to at most `limit` tokens, at a word boundary, and its token count."""
    count = len(encode(text))
    if count <= limit:
        return text, count
    head = decode(encode(text)[:limit])
    while True:
        space = max(head.rfind(" "), head.rfind("\n"))
        head = head[:space].rstrip() if space > 0 else ""
        count = len(encode(head))
        if count <= limit:
            return head, count


# ---- the test split's statements ------------------------------------------------------------------------------------

def statements(path=TEST_SPLIT):
    texts = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        user = next(m["content"] for m in json.loads(line)["messages"] if m["role"] == "user")
        match = STATEMENT.search(user)
        if not match:
            raise SystemExit(f"{path.name} line {number}: no statement found")
        texts.append({"id": f"test-{number:02d}", "text": match.group(1)})
    return texts


def testsplit(out: Path):
    texts = statements()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"kind": "statements", "texts": texts}, indent=1))
    print(f"test split: {len(texts)} statements")


# ---- the prompts (S3, S4) -------------------------------------------------------------------------------------------

def prompt_files():
    return [PROMPTS / f"{section}.{part}.txt" for section in SECTIONS for part in ("instructions", "template")]


def load_prompts():
    """The four prompt files read once, and their hash: a run uses this snapshot, so an edit during a run changes nothing."""
    data = [path.read_bytes() for path in prompt_files()]
    digest = hashlib.sha256(b"".join(data)).hexdigest()[:12]
    texts = [d.decode().strip() for d in data]
    return {section: (texts[2 * i], texts[2 * i + 1]) for i, section in enumerate(SECTIONS)}, digest


def prompts_hash():
    return load_prompts()[1]


def messages(section, text, prompts=None):
    instructions, template = (prompts or load_prompts()[0])[section]
    return [{"role": "system", "content": instructions}, {"role": "user", "content": template.replace("{text}", text)}]


# ---- S8: the measures ---------------------------------------------------------------------------------------------

def format_problems(answer, section, finish=None):
    """What makes an answer unusable as a section: [] when it is in format."""
    text = answer.strip()
    problems = ["cut"] if finish == "length" else []
    if "<think>" in text or "</think>" in text:
        problems.append("thinking")
    if not text:
        return problems + ["empty"]
    if text == NOT_STATED:
        return problems
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if text[0] in "{[":
        problems.append("json")
    if any(line.startswith("#") or re.fullmatch(r"\*\*[^*]+\*\*:?", line) or (line.endswith(":") and len(line.split()) <= 4)
           for line in lines):
        problems.append("heading")
    if any(re.match(r"(?:[-*•]|\d+[.)])\s", line) for line in lines):
        problems.append("list")
    if len(text.split()) > WORD_LIMIT[section]:
        problems.append("too long")
    return problems


def normal_number(text):
    return text.replace(",", "")


def found(item, text):
    return re.search(r"(?<![A-Za-z0-9])" + re.escape(item) + r"(?![A-Za-z0-9])", text, re.I) is not None


def flags(answer, text):
    """The numbers and names of an answer that the text does not contain, as (kind, item), each once."""
    if answer.strip() == NOT_STATED:
        return []
    out = []
    numbers = {normal_number(n) for n in NUMBER.findall(text)}
    for raw in NUMBER.findall(answer):
        item = normal_number(raw).rstrip(".,")
        if item not in numbers and ("number", item) not in out:
            out.append(("number", item))
    for match in WORD.finditer(answer):
        word = re.sub(r"(?:['’]s)?[.,;:'’]*$", "", match.group())
        if not word or not word[0].isupper() or word.lower() in LEGAL_FORMS:
            continue
        if match.start() > 0 and answer[match.start() - 1].isdigit():
            continue                                                    # "4WD": the number rule checks the digits
        before = answer[:match.start()]
        stripped = before.rstrip()
        if not stripped or stripped[-1] in ".!?:" or "\n" in before[len(stripped):]:
            continue                                                    # a sentence start, capitalised by grammar
        if not grounded_name(word, text) and ("name", word) not in out:
            out.append(("name", word))
    return out


def grounded_name(word, text):
    """A name is in the text as it is, by an alias, as the singular of a plural, or, when hyphenated, by each of its
    capitalised parts ("AI-driven" by "AI")."""
    if found(word, text) or any(found(alias, text) for alias in ALIASES.get(word.lower(), ())):
        return True
    if word.endswith("s") and len(word) > 2 and found(word[:-1], text):
        return True
    parts = [part for part in word.split("-") if part and part[0].isupper()]
    return "-" in word and bool(parts) and all(grounded_name(part, text) for part in parts)


def covered(fact, answer):
    """A stated fact is covered when every group of its key terms has one term in the answer (a term matches at a word
    start, so "store" also matches "stores"; any run of spaces or line breaks counts as one space)."""
    if answer.strip() == NOT_STATED:
        return False
    lower = re.sub(r"\s+", " ", answer.lower())
    return all(any(re.search(r"(?<![a-z0-9])" + re.escape(re.sub(r"\s+", " ", term.lower())), lower) for term in group)
               for group in fact["terms"])


def read_jsonl(path: Path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def check_counts(texts, answers, labels=None, verdicts=None):
    verdicts = verdicts or {}
    for key, verdict in verdicts.items():
        if verdict not in ("confirmed", "rejected"):
            raise SystemExit(f"verdict of {key}: {verdict!r}, expected confirmed or rejected")
    counts = defaultdict(Counter)
    waiting = {}
    for row in answers:
        section, answer, text = row["section"], row["answer"], texts[row["id"]]
        group =[counts[f"{row['condition']}|{section}|{row['seed']}"], counts[f"{row['condition']}|{section}|all"]]
        add = Counter({"answers": 1})
        problems = format_problems(answer, section, row.get("finish"))
        add["in format"] += not problems
        for problem in problems:
            add[f"format: {problem}"] += 1
        add["not stated"] += answer.strip() == NOT_STATED
        confirmed = 0
        for kind, item in flags(answer, text):
            key = f"{row['id']}|{kind}|{item}"
            add[f"flags: {kind}"] += 1
            if verdicts.get(key) == "confirmed":
                confirmed += 1
            elif key not in verdicts:
                add["flags waiting"] += 1
                waiting[key] = {"id": row["id"], "kind": kind, "item": item}
        add["flags confirmed"] += confirmed
        add["answers with an invented item"] += confirmed > 0
        if labels is not None:
            for fact in labels[row["id"]][section]:
                if fact is not None:
                    add["facts stated"] += 1
                    add["facts covered"] += covered(fact, answer)
        for counter in group:
            counter.update(add)
    return {key: dict(sorted(c.items())) for key, c in sorted(counts.items())}, waiting


def check(texts_path: Path, answer_paths, labels_path, verdicts_path, out: Path):
    texts = {t["id"]: t["text"] for t in json.loads(texts_path.read_text())["texts"]}
    answers = [row for path in answer_paths for row in read_jsonl(Path(path))]
    labels = json.loads(Path(labels_path).read_text())["reports"] if labels_path else None
    verdicts = json.loads(Path(verdicts_path).read_text()) if verdicts_path and Path(verdicts_path).exists() else {}
    counts, waiting = check_counts(texts, answers, labels, verdicts)
    out.write_text(json.dumps({"texts": texts_path.name, "answers": [Path(p).name for p in answer_paths],
                               "counts": counts}, indent=1))
    out.with_name(out.stem + ".flags.json").write_text(json.dumps(sorted(waiting.values(), key=lambda f: (
        f["id"], f["kind"], f["item"])), indent=1))
    for key, c in counts.items():
        if not key.endswith("|all"):
            continue
        line = (f"{key[:-4]:<18} answers {c['answers']:>3}  in format {c.get('in format', 0):>3}  not stated "
                f"{c.get('not stated', 0):>3}  invented {c.get('answers with an invented item', 0):>3}  flags waiting "
                f"{c.get('flags waiting', 0):>3}")
        if labels is not None:
            line += f"  covered {c.get('facts covered', 0)}/{c.get('facts stated', 0)}"
        print(line)
    print(f"flags waiting for a verdict: {len(waiting)} (in {out.with_name(out.stem + '.flags.json').name})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["locate", "testsplit", "check"])
    parser.add_argument("--text")
    parser.add_argument("--texts")
    parser.add_argument("--answers", nargs="+")
    parser.add_argument("--labels")
    parser.add_argument("--verdicts")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    out = Path(args.out)
    if args.command == "locate":
        locate(Path(args.text), out)
    elif args.command == "testsplit":
        testsplit(out)
    else:
        check(Path(args.texts), args.answers, args.labels, args.verdicts, out)


if __name__ == "__main__":
    main()
