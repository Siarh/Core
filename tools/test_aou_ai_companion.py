#!/usr/bin/env python3
import unittest

from aou_ai_companion import parse_aoucsv_text


class AOUCSVParserTests(unittest.TestCase):
    def test_reassembles_chunks_in_order_and_sorts_records(self):
        text = "\n".join([
            "13:01 AOUCSV|H|2|2|U|L|observed_amount",
            "AOUCSV|R2|2|2|200|30|600",
            "AOUCSV|H|1|2|kind|M|R|",
            "AOUCSV|R1|2|2|300|40|500",
            "AOUCSV|R1|1|2|damage|100|200|",
            "AOUCSV|R2|1|2|healing|150|250|",
            "AOUCSV|BEGIN|1|1|export-start",
        ])
        header, rows, info = parse_aoucsv_text(text)
        self.assertEqual(header, ["kind", "M", "R", "U", "L", "observed_amount"])
        self.assertEqual(rows[0], ["damage", "100", "200", "300", "40", "500"])
        self.assertEqual(rows[1], ["healing", "150", "250", "200", "30", "600"])
        self.assertEqual(info["data_records"], 2)

    def test_identical_duplicate_chunk_is_ignored(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "AOUCSV|R1|1|1|damage|1|2|3|4|5",
        ])
        header, rows, _ = parse_aoucsv_text(text)
        self.assertEqual(len(header), 6)
        self.assertEqual(len(rows), 1)

    def test_missing_chunk_is_rejected(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "AOUCSV|R1|1|2|damage|1|2|3|4|5",
        ])
        with self.assertRaisesRegex(ValueError, "отсутствуют части"):
            parse_aoucsv_text(text)

    def test_conflicting_duplicate_is_rejected(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "AOUCSV|R1|1|1|damage|1|2|3|4|5",
            "AOUCSV|R1|1|1|damage|1|2|3|4|6",
        ])
        with self.assertRaisesRegex(ValueError, "распознана по-разному"):
            parse_aoucsv_text(text)

    def test_damaged_aoucsv_line_is_rejected(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "OCR AOUCSV damaged text",
            "AOUCSV|R1|1|1|damage|1|2|3|4|5",
        ])
        with self.assertRaisesRegex(ValueError, "формат не распознан"):
            parse_aoucsv_text(text)

    def test_extra_pipe_in_data_is_rejected(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L|observed_amount",
            "AOUCSV|R1|1|1|damage|1|2|3|4|5|unexpected",
        ])
        with self.assertRaisesRegex(ValueError, "полей больше"):
            parse_aoucsv_text(text)

    def test_missing_required_header_is_rejected(self):
        text = "\n".join([
            "AOUCSV|H|1|1|kind|M|R|U|L",
            "AOUCSV|R1|1|1|damage|1|2|3|4",
        ])
        with self.assertRaisesRegex(ValueError, "отсутствуют столбцы"):
            parse_aoucsv_text(text)


if __name__ == "__main__":
    unittest.main()
