#!/usr/bin/env python3
"""Tests of Scripts/pdf_pilot.py on a made-up four-page PDF (no real report). Standard library only.

  python3 -m unittest discover -s Scripts/tests -v

The PDF has a prose page, an income statement table, a cash flow table and an unrelated prose page; every number is made
up. The tamper tests change one label or one page and check that the scorer and the recall count fail as they must.
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pdf_pilot as p  # noqa: E402

COLUMNS = (72, 360, 460)
PAGES = [
    [("Letter to shareholders",), ("Dear shareholders, the company had a good year and thanks its employees.",)],
    [("CONSOLIDATED STATEMENTS OF OPERATIONS",), ("(In millions, except per-share amounts)",),
     ("", "2025", "2024"),
     ("Total net sales", "$ 1,234", "$ 1,100"),
     ("Operating income", "300", "250"),
     ("Interest expense", "(12)", "(10)"),
     ("Net income", "$ 210", "$ 190"),
     ("Earnings per share:",),
     ("Diluted", "$ 2.15", "$ 1.95")],
    [("CONSOLIDATED STATEMENTS OF CASH FLOWS",), ("(In millions)",),
     ("", "2025", "2024"),
     ("Net cash provided by operating activities", "400", "350"),
     ("Purchases of property and equipment", "(90)", "(80)")],
    [("Community",), ("Our employees met for a picnic in the park with their families.",)],
]
LABEL = {
    "pages": {"income": [2], "cashflow": [3]},
    "values": {"revenue": "1234000000", "operatingIncome": "300000000", "netIncome": "210000000", "eps": "2.15",
               "interestExpense": "12000000", "operatingCashFlow": "400000000", "capex": "90000000",
               "previousYearRevenue": "1100000000", "previousYearNetIncome": "190000000", "previousYearEps": "1.95",
               "revenueGrowth": None, "netIncomeGrowth": None, "epsGrowth": None},
}


def pdf_string(text):
    return "(" + text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


def make_pdf(path: Path):
    """A minimal PDF, one text object per cell, Helvetica 10 pt."""
    objects = ["<< /Type /Catalog /Pages 2 0 R >>", None, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    kids = []
    for lines in PAGES:
        ops = []
        for row, cells in enumerate(lines):
            y = 740 - 18 * row
            for x, cell in zip(COLUMNS, cells):
                if cell:
                    ops.append(f"BT /F1 10 Tf {x} {y} Td {pdf_string(cell)} Tj ET")
        stream = "\n".join(ops)
        objects.append(f"<< /Length {len(stream.encode())} >>\nstream\n{stream}\nendstream")
        content = len(objects)
        objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {content} 0 R "
                       f"/Resources << /Font << /F1 3 0 R >> >> >>")
        kids.append(len(objects))
    objects[1] = f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {len(kids)} >>"
    body, offsets = b"%PDF-1.4\n", []
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(body))
        body += f"{i} 0 obj\n{obj}\nendobj\n".encode()
    xref = len(body)
    body += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    body += "".join(f"{o:010d} 00000 n \n" for o in offsets).encode()
    body += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(body)


def quiet(fn, *args):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*args)


@unittest.skipUnless(shutil.which("pdftotext"), "needs pdftotext")
class PdfPilotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.pdf = cls.tmp / "made-up.pdf"
        make_pdf(cls.pdf)
        cls.pages = p.pages_layout(cls.pdf)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def labels(self, **values):
        label = json.loads(json.dumps(LABEL))
        label["values"].update(values)
        return {"made-up.pdf": label}

    # extraction and units
    def test_layout_keeps_one_page_per_page_and_rows_on_one_line(self):
        self.assertEqual(len(self.pages), 4)
        self.assertTrue(any("Total net sales" in line and "1,234" in line and "1,100" in line
                            for line in self.pages[1].splitlines()))

    def test_header_unit(self):
        self.assertEqual(p.header_unit(self.pages[1]), "millions")
        self.assertEqual(p.header_unit(self.pages[2]), "millions")
        self.assertIsNone(p.header_unit(self.pages[0]))
        self.assertEqual(p.header_unit("(Dollars in thousands)"), "thousands")
        self.assertEqual(p.header_unit("Millions of U.S. dollars"), "millions")

    def test_read_value_bare_and_with_unit(self):
        self.assertEqual(p.read_value("1,234", "revenue", self.pages[1]), 1234 * 10 ** 6)
        self.assertEqual(p.read_value("$1.234 billion", "revenue", ""), 1234 * 10 ** 6)
        self.assertEqual(p.read_value("(90)", "capex", self.pages[2]), 90 * 10 ** 6)       # magnitude
        self.assertEqual(str(p.read_value("$2.15", "eps", self.pages[1])), "2.15")
        self.assertIsNone(p.read_value("about a billion", "revenue", ""))

    # P5, the code baseline, and the scorer
    def test_code_baseline_reads_every_labelled_amount(self):
        answers = p.baseline_answers(self.pages, LABEL)
        for key in p.SCORED:
            self.assertEqual(p.classify(key, answers.get(key), LABEL["values"], self.pages), "correct", key)

    def test_tamper_a_wrong_label_is_not_correct(self):
        answers = p.baseline_answers(self.pages, LABEL)
        tampered = dict(LABEL["values"], revenue="1235000000")
        self.assertEqual(p.classify("revenue", answers["revenue"], tampered, self.pages), "wrong")

    def test_categories(self):
        values = LABEL["values"]
        on = lambda text, page=2: {"text": text, "page": page}
        self.assertEqual(p.classify("revenue", on("1,100"), values, self.pages), "column")
        self.assertEqual(p.classify("revenue", on("1,234", page=1), values, self.pages), "unit")    # no header on page 1
        self.assertEqual(p.classify("revenue", None, values, self.pages), "missed")
        self.assertEqual(p.classify("revenue", on("n/a"), values, self.pages), "unparsed")
        self.assertEqual(p.classify("revenue", on("1,234"), dict(values, revenue=None), self.pages), "invented")
        self.assertEqual(p.classify("revenue", None, dict(values, revenue=None), self.pages), "correct")
        self.assertEqual(p.classify("revenue", on("$1.2 billion"), values, self.pages), "correct")   # within half of 0.1 billion
        self.assertEqual(p.classify("revenue", on("$1.3 billion"), values, self.pages), "wrong")

    def test_score_counts_only_stated_amounts_as_the_share(self):
        out = self.tmp / "score"
        (out / "text").mkdir(parents=True, exist_ok=True)
        p.text_file(out, "made-up.pdf", "layout").write_text(json.dumps(self.pages))
        answers = p.baseline_answers(self.pages, LABEL)
        totals, stated, correct, _ = p.score_runs({"extraction": "layout", "runs": [{"seed": 0, "answers": {"made-up.pdf": answers}}]},
                                                  {"made-up.pdf": LABEL}, out)
        self.assertEqual((stated, correct, totals["correct"]), (10, 10, 10))
        labels = self.labels(interestExpense=None)
        totals, stated, correct, _ = p.score_runs({"extraction": "layout", "runs": [{"seed": 0, "answers": {"made-up.pdf": answers}}]},
                                                  labels, out)
        self.assertEqual((stated, correct, totals["invented"]), (9, 9, 1))

    # P9, the retrievers and recall at 3
    def test_keywords_rank_the_statement_pages_first(self):
        self.assertEqual(p.ranking(p.bm25(self.pages, p.QUERIES["income"]))[0], 2)
        self.assertEqual(p.ranking(p.bm25(self.pages, p.QUERIES["cashflow"]))[0], 3)

    def test_rank_fusion(self):
        self.assertEqual(p.fuse([1, 2, 3], [3, 1, 2]), [1, 3, 2])

    def retrieval(self):
        fake = {"scores": {"income": [0.1, 0.9, 0.2, 0.0], "cashflow": [0.1, 0.2, 0.9, 0.0]}}
        return {"made-up.pdf": {"rankings": p.rank_all(self.pages, fake)}}

    def test_recall_and_its_tamper(self):
        retrieval = self.retrieval()
        counts = p.recall_counts(retrieval, {"made-up.pdf": LABEL})
        self.assertEqual({r: c["hits"] for r, c in counts.items()}, {"keywords": 2, "embeddings": 2, "hybrid": 2})
        self.assertEqual(p.choose(counts), "keywords")                  # a tie: the simpler one
        self.assertEqual(p.found_both(retrieval, {"made-up.pdf": LABEL}, "hybrid"), 1)
        tampered = json.loads(json.dumps(LABEL))
        tampered["pages"]["income"] = [4]                               # the picnic page, ranked last
        counts = p.recall_counts(retrieval, {"made-up.pdf": tampered})
        self.assertEqual(counts["keywords"]["hits"], 1)
        self.assertEqual(counts["keywords"]["ranks"][0], 4)
        self.assertEqual(p.found_both(retrieval, {"made-up.pdf": tampered}, "keywords"), 0)

    def test_choice_breaks_ties_in_the_fixed_order(self):
        counts = {"keywords": {"hits": 7}, "embeddings": {"hits": 8}, "hybrid": {"hits": 8}}
        self.assertEqual(p.choose(counts), "hybrid")

    def test_condition_pages(self):
        retrieval = self.retrieval()
        self.assertEqual(p.condition_pages("A", "made-up.pdf", LABEL, None, None), [2, 3])
        picked = p.condition_pages("C", "made-up.pdf", LABEL, retrieval, "keywords")
        self.assertEqual(picked[:2], [2, 3])
        self.assertLessEqual(len(picked), 2 * p.TOP)

    # combining
    def test_combine_takes_the_first_readable_value_and_counts_conflicts(self):
        per_page = [(2, {"revenue": "1,234", "netIncome": None}), (3, {"revenue": "1,300", "netIncome": "210"})]
        combined, conflicts = p.combine_answers(per_page, self.pages)
        self.assertEqual(combined["revenue"], {"text": "1,234", "page": 2})
        self.assertEqual(combined["netIncome"], {"text": "210", "page": 3})
        self.assertEqual(conflicts, 1)

    # P2, the draw
    def test_draw_is_seeded_and_frozen(self):
        reports, out = self.tmp / "reports", self.tmp / "draw"
        reports.mkdir()
        for i in range(8):
            (reports / f"R{i}.pdf").write_bytes(b"%PDF-1.4 made up " + bytes([i]))
        quiet(p.draw, reports, out)
        first = json.loads((out / "draw.json").read_text())
        self.assertEqual(len(first["reports"]), p.DRAWN)
        with self.assertRaises(SystemExit):
            quiet(p.draw, reports, out)
        shutil.rmtree(out)
        quiet(p.draw, reports, out)
        self.assertEqual(json.loads((out / "draw.json").read_text())["hash"], first["hash"])

    def test_phone_set_keeps_each_page_whole_inside_the_app_prompt(self):
        out = self.tmp / "phone"
        out.mkdir()
        names = ["A.pdf", "B.pdf", "C.pdf"]
        (out / "draw.json").write_text(json.dumps({"reports": [{"name": n} for n in names]}))
        chosen = p.phone_report(out)
        self.assertEqual(chosen, p.random.Random(p.SEED_PDF).choice(names))
        template = (p.ROOT / "Dataset" / "prompt_template.txt").read_text().rstrip("\n")
        prefix, suffix = template.split("<<STATEMENT>>")
        texts = {n: [f'{n} page {i} "quoted"\nNet income 12 {i}' for i in range(3)] for n in names}
        with (out / "inputs.C.pdfkit.jsonl").open("w") as f:
            for n in names:
                for priority, text in reversed(list(enumerate(texts[n]))):
                    messages = [{"role": "system", "content": "s"},
                                {"role": "user", "content": template.replace("<<STATEMENT>>", text)}]
                    f.write(json.dumps({"report": n, "page": priority + 1, "priority": priority, "messages": messages}) + "\n")
        quiet(p.phoneset, out)
        folder = out / "phone" / p.PHONE_SET
        chat = [json.loads(line) for line in (folder / f"{p.PHONE_SET}.jsonl").read_text().splitlines()]
        labels = (folder / f"{p.PHONE_SET}.labels.jsonl").read_text().splitlines()
        index = (folder / "index.csv").read_text().splitlines()
        self.assertEqual((len(chat), len(labels), len(index)), (3, 3, 4))
        for line, record in enumerate(chat):
            user = record["messages"][1]["content"]
            self.assertTrue(user.startswith(prefix) and user.endswith(suffix))
            self.assertEqual(user[len(prefix):len(user) - len(suffix)], texts[chosen][line])
        self.assertTrue(all(v is None for line in labels for v in json.loads(line)["fields"].values()))

    # the Swift scripts
    @unittest.skipUnless(shutil.which("swift"), "needs swift")
    def test_pdfkit_text_and_embeddings(self):
        out = self.tmp / "swift"
        (out / "text").mkdir(parents=True)
        pages = p.pages_pdfkit(self.pdf, p.text_file(out, "made-up.pdf", "pdfkit"))
        self.assertEqual(len(pages), 4)
        self.assertIn("Total net sales", pages[1])
        embedded = p.embed_scores(out, "made-up.pdf", "pdfkit", pages)
        self.assertEqual(sorted(embedded["scores"]), ["cashflow", "income"])
        self.assertEqual(len(embedded["scores"]["income"]), 4)


if __name__ == "__main__":
    unittest.main()
