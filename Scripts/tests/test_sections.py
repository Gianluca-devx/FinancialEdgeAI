#!/usr/bin/env python3
"""Tests of Scripts/sections.py on made-up texts (no real report, every company and number invented). Standard library only.

  python3 -m unittest discover -s Scripts/tests -v

Each measure has a tamper case: an answer or a page changed so that the measure must fail.
"""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import sections as s  # noqa: E402

TOC = "\n".join(["Table of Contents", "Item 1. Business 4", "Item 1A. Risk Factors 9", "Item 2. Properties 20",
                 "Item 7. Management's Discussion 25", "Item 8. Financial Statements 40"])
BODY = ("Forward-looking statements are on this page.\nPART I\nItem 1. Business\nGeneral\nNewco Widgets Inc. makes "
        "widgets and gears. It is based in Springfield, Ohio, and employs about 4,200 people in 12 countries.")
NEXT = "Segments\nThe company reports two segments, Widgets and Gears, and sells to carmakers and to retailers."
TEXT = BODY + "\n" + NEXT
GOOD = ("Newco Widgets makes widgets and gears. It is based in Springfield, Ohio, and employs about 4,200 people in "
        "12 countries.")
FACTS = [{"name": "does", "terms": [["widget"], ["gear"]]}, {"name": "headquarters", "terms": [["Springfield"]]},
         {"name": "size", "terms": [["4,200", "4200"]]}]


class LocateTests(unittest.TestCase):
    def test_the_body_page_is_found_and_the_table_of_contents_is_not(self):
        pages = ["Cover page, Form 10-K", TOC, BODY, NEXT]
        self.assertEqual(s.item1_page(pages), 3)
        text, numbers = s.item1_text(pages, 3)
        self.assertTrue(text.startswith("Item 1. Business"))                # from the heading, not the page start
        self.assertNotIn("Forward-looking", text)
        self.assertIn("two segments", text)
        self.assertEqual(numbers, [3, 4])

    def test_heading_forms(self):
        for heading in ("ITEM 1. BUSINESS", "Item 1 - Business", "Item 1: Business", "Item 1 — Business", "Item 1 Business"):
            self.assertEqual(s.item1_page(["cover", heading + "\nNewco makes widgets."]), 2, heading)
        for other in ("Item 1A. Risk Factors", "Item 10. Directors", "Items 1 and 2. Business and Properties"):
            self.assertIsNone(s.item1_page(["cover", other + "\nText."]), other)

    def test_tamper_a_short_table_of_contents_would_be_taken(self):
        short = "\n".join(TOC.splitlines()[:4])                             # 3 Item headings: under the limit of 4
        self.assertEqual(s.item1_page(["cover", short, BODY]), 2)
        self.assertEqual(s.item1_page(["cover", TOC, BODY]), 3)

    def test_at_most_eight_pages(self):
        pages = [BODY] + [f"page {n}" for n in range(2, 20)]
        self.assertEqual(s.item1_text(pages, 1)[1], list(range(1, 9)))

    def test_locate_lists_a_report_without_the_heading_as_missed(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "Newco.pdfkit.json").write_text(json.dumps(["cover", TOC, BODY, NEXT]))
            (folder / "Oldco.pdfkit.json").write_text(json.dumps(["cover", "Items 1 and 2. Business and Properties"]))
            with contextlib.redirect_stdout(io.StringIO()):
                s.locate(folder, folder / "out" / "located.json")
            located = json.loads((folder / "out" / "located.json").read_text())
        self.assertEqual(list(located["reports"]), ["Newco"])
        self.assertEqual(located["reports"]["Newco"]["pages"], [3, 4])
        self.assertEqual(located["missed"], ["Oldco"])


class CutTests(unittest.TestCase):
    encode = staticmethod(lambda text: text.split())
    decode = staticmethod(lambda tokens: " ".join(tokens))

    def test_a_short_text_is_kept(self):
        self.assertEqual(s.cut("one two three", self.encode, self.decode, limit=5), ("one two three", 3))

    def test_a_long_text_is_cut_at_a_word_boundary_within_the_limit(self):
        text = " ".join(f"w{n}" for n in range(100))
        head, count = s.cut(text, self.encode, self.decode, limit=10)
        self.assertLessEqual(count, 10)
        self.assertTrue(text.startswith(head))
        self.assertTrue(head.endswith(("w8", "w9")))

    def test_a_token_that_splits_a_word_is_dropped(self):
        encode = lambda text: list(text)                                    # one token per character
        head, count = s.cut("alpha beta gamma", encode, "".join, limit=13)  # "alpha beta ga" would split a word
        self.assertEqual((head, count), ("alpha beta", 10))


class TestSplitTests(unittest.TestCase):
    def test_the_thirty_statements(self):
        texts = s.statements()
        self.assertEqual(len(texts), 30)
        self.assertEqual(texts[0]["id"], "test-01")
        for t in texts:
            self.assertTrue(t["text"].strip())
            self.assertNotIn("Extract the following fields", t["text"])
            self.assertNotIn("financial statement:", t["text"])


class PromptTests(unittest.TestCase):
    def test_each_template_holds_the_text_once_and_the_instructions_never(self):
        for section in s.SECTIONS:
            self.assertEqual((s.PROMPTS / f"{section}.template.txt").read_text().count("{text}"), 1)
            self.assertNotIn("{text}", (s.PROMPTS / f"{section}.instructions.txt").read_text())
            system, user = s.messages(section, "Newco makes widgets.")
            self.assertEqual((system["role"], user["role"]), ("system", "user"))
            self.assertIn("Newco makes widgets.", user["content"])
            self.assertIn(s.NOT_STATED, system["content"])
            self.assertIn(f"at most {s.PROMPT_WORDS[section]} words", system["content"])
            self.assertLess(s.PROMPT_WORDS[section], s.WORD_LIMIT[section])

    def test_no_number_of_the_metrics_examples_in_the_prompts(self):
        for path in s.prompt_files():
            for number in ("7.4", "2.4", "8.2", "6.8"):
                self.assertNotIn(number, path.read_text(), path.name)

    def test_a_run_uses_the_snapshot_of_the_prompts(self):
        snapshot, digest = s.load_prompts()
        self.assertEqual((len(digest), digest), (12, s.prompts_hash()))
        edited = dict(snapshot, overview=("Made-up instructions.", "Made-up template: {text}"))
        system, user = s.messages("overview", "Newco.", edited)
        self.assertEqual((system["content"], user["content"]), ("Made-up instructions.", "Made-up template: Newco."))


class FormatTests(unittest.TestCase):
    def test_a_good_answer_and_not_stated_are_in_format(self):
        self.assertEqual(s.format_problems(GOOD, "overview", "stop"), [])
        self.assertEqual(s.format_problems(" Not stated in the text.\n", "overview"), [])

    def test_tamper_each_problem(self):
        cases = {"empty": "  ", "json": '{"overview": "Newco makes widgets."}', "heading": "# Overview\n" + GOOD,
                 "list": "- Newco makes widgets.\n- It is based in Springfield.", "thinking": "<think>x</think>" + GOOD}
        for problem, answer in cases.items():
            self.assertIn(problem, s.format_problems(answer, "overview", "stop"), problem)
        self.assertIn("heading", s.format_problems("**Overview**\n" + GOOD, "overview"))
        self.assertIn("heading", s.format_problems("Company overview:\n" + GOOD, "overview"))
        self.assertIn("list", s.format_problems("1. Newco makes widgets.", "overview"))
        self.assertIn("cut", s.format_problems(GOOD, "overview", "length"))

    def test_the_word_limit_of_each_section(self):
        self.assertEqual(s.format_problems(" ".join(["word"] * 60), "overview"), [])
        self.assertEqual(s.format_problems(" ".join(["word"] * 61), "overview"), ["too long"])
        self.assertEqual(s.format_problems(" ".join(["word"] * 100), "business"), [])
        self.assertEqual(s.format_problems(" ".join(["word"] * 101), "business"), ["too long"])


class FlagTests(unittest.TestCase):
    def test_a_grounded_answer_has_no_flag(self):
        self.assertEqual(s.flags(GOOD, TEXT), [])
        self.assertEqual(s.flags("Newco employs 4200 people. Its segments are Widgets and Gears.", TEXT), [])

    def test_tamper_an_invented_number_and_an_invented_name(self):
        answer = GOOD + " It was founded in 1921 by Ada Brown in Dayton."
        self.assertEqual(s.flags(answer, TEXT), [("number", "1921"), ("name", "Ada"), ("name", "Brown"),
                                                 ("name", "Dayton")])

    def test_a_sentence_start_is_not_a_name(self):
        self.assertEqual(s.flags("Newco makes widgets. Today it also makes gears.", TEXT), [])
        self.assertEqual(s.flags("Newco makes widgets.\nWell known, it makes gears.", TEXT), [])

    def test_legal_forms_possessives_and_aliases(self):
        self.assertEqual(s.flags("The widgets of Newco Corporation are sold by Newco's own shops.", TEXT), [])
        text_us = TEXT + " Most sales are in the United States."
        self.assertEqual(s.flags("Newco sells mostly in the U.S. and the US.", text_us), [])
        self.assertEqual(s.flags("Newco sells mostly in the U.S.", TEXT), [("name", "U.S")])

    def test_plurals_hyphenated_words_and_digits_before_letters(self):
        text = TEXT + " Its 4WD tractors use AI and the Newco platform."
        self.assertEqual(s.flags("Newco sells 4WD tractors with AI-driven Newcos and Widgets-based tools.", text), [])
        self.assertEqual(s.flags("Newco sells Zorgs and XY-driven tools.", text), [("name", "Zorgs"), ("name", "XY-driven")])
        self.assertEqual(s.flags("Newco sells 9WD tractors.", text), [("number", "9")])           # the digits still count

    def test_not_stated_has_no_flag(self):
        self.assertEqual(s.flags(s.NOT_STATED, "Revenue was $9.1 billion."), [])


class CoverageTests(unittest.TestCase):
    def test_covered_when_every_group_has_a_term(self):
        self.assertTrue(all(s.covered(fact, GOOD) for fact in FACTS))
        self.assertTrue(s.covered({"terms": [["store"]]}, "It runs 300 stores."))           # a word start matches
        self.assertTrue(s.covered({"terms": [["Widgets & Gears"]]}, "segments Widgets &\nGears (WG)"))  # a line break

    def test_tamper_a_missing_term(self):
        self.assertFalse(s.covered(FACTS[0], "Newco makes widgets."))                       # gears missing
        self.assertFalse(s.covered(FACTS[1], GOOD.replace("Springfield", "a city")))
        self.assertFalse(s.covered({"terms": [["tor"]]}, "It runs 300 stores."))            # not inside a word
        self.assertFalse(s.covered(FACTS[2], s.NOT_STATED))


class CheckTests(unittest.TestCase):
    def rows(self, answer, seed=1, section="overview"):
        return {"id": "newco", "section": section, "seed": seed, "condition": "B", "answer": answer, "finish": "stop"}

    def test_counts_with_verdicts_waiting_confirmed_and_rejected(self):
        texts = {"newco": TEXT}
        labels = {"newco": {"overview": FACTS, "business": [None, None, None]}}
        answers = [self.rows(GOOD), self.rows(GOOD + " It was founded in 1921.", seed=2), self.rows(s.NOT_STATED, seed=3)]
        counts, waiting = s.check_counts(texts, answers, labels)
        total = counts["B|overview|all"]
        self.assertEqual((total["answers"], total["in format"], total["not stated"]), (3, 3, 1))
        self.assertEqual((total["facts stated"], total["facts covered"]), (9, 6))
        self.assertEqual(total["flags waiting"], 1)
        self.assertEqual(total.get("answers with an invented item", 0), 0)
        self.assertEqual(list(waiting), ["newco|number|1921"])
        confirmed, _ = s.check_counts(texts, answers, labels, {"newco|number|1921": "confirmed"})
        self.assertEqual(confirmed["B|overview|all"]["answers with an invented item"], 1)
        self.assertEqual(confirmed["B|overview|2"]["answers with an invented item"], 1)
        rejected, waiting = s.check_counts(texts, answers, labels, {"newco|number|1921": "rejected"})
        self.assertEqual((rejected["B|overview|all"].get("answers with an invented item", 0), waiting), (0, {}))

    def test_a_bad_verdict_is_refused(self):
        with self.assertRaises(SystemExit):
            s.check_counts({"newco": TEXT}, [self.rows(GOOD)], None, {"newco|number|1921": "maybe"})

    def test_check_writes_the_counts_and_the_flags_waiting(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "texts.json").write_text(json.dumps({"kind": "reports", "texts": [{"id": "newco", "text": TEXT}]}))
            (folder / "answers.jsonl").write_text(json.dumps(self.rows(GOOD + " Founded in 1921.")) + "\n")
            with contextlib.redirect_stdout(io.StringIO()):
                s.check(folder / "texts.json", [folder / "answers.jsonl"], None, None, folder / "check.json")
            counts = json.loads((folder / "check.json").read_text())["counts"]
            flags = json.loads((folder / "check.flags.json").read_text())
        self.assertEqual(counts["B|overview|1"]["flags waiting"], 1)
        self.assertEqual(flags, [{"id": "newco", "kind": "number", "item": "1921"}])


if __name__ == "__main__":
    unittest.main()
