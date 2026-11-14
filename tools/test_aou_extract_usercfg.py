#!/usr/bin/env python3
import unittest

from aou_extract_usercfg import (
    EVENT_COLUMNS,
    extract_named_table,
    parse_config_value,
    parse_dpscope_config,
)


def row(number: int) -> str:
    fields = [
        "fight1", "pve", str(number), "damage", "1000", "0.5",
        "measured_pre", "50000", "0", "physical", "test", "0",
        "0", "0", "0", "0", "0", "0", "0", "0", "0", "50",
        "self", "Ability name", "100", "200", "300", "40", "10",
        "20", "30", "40", "50000",
    ]
    assert len(fields) == len(EVENT_COLUMNS.split("|"))
    return "|".join(fields)


class UserCfgExtractorTests(unittest.TestCase):
    def test_extracts_dpscope_global_section(self):
        text = "\n".join([
            "table_begin ScriptUserMods_DPScope",
            " table_begin data",
            '  aou_evt_schema=l"v1"',
            "  aou_evt_count=2",
            f'  aou_evt_1=l"{row(1)}"',
            f'  aou_evt_2=l"{row(2)}"',
            " table_end data",
            "table_end ScriptUserMods_DPScope",
        ])
        rows, summary = parse_dpscope_config(text)
        self.assertEqual(len(rows), 2)
        self.assertEqual(summary["stored_events"], 2)
        self.assertEqual(rows[1].split("|")[2], "2")

    def test_ignores_other_addon_tables(self):
        text = "\n".join([
            "table_begin ScriptUserMods_OtherAddon",
            " table_begin data",
            "  aou_evt_count=99",
            " table_end data",
            "table_end ScriptUserMods_OtherAddon",
            "table_begin ScriptUserMods_DPScope",
            " table_begin data",
            "  aou_evt_count=1",
            f'  aou_evt_1=l"{row(1)}"',
            " table_end data",
            "table_end ScriptUserMods_DPScope",
        ])
        rows, _ = parse_dpscope_config(text)
        self.assertEqual(len(rows), 1)

    def test_missing_record_is_rejected(self):
        text = "\n".join([
            "table_begin ScriptUserMods_DPScope",
            " table_begin data",
            "  aou_evt_count=2",
            f'  aou_evt_1=l"{row(1)}"',
            " table_end data",
            "table_end ScriptUserMods_DPScope",
        ])
        with self.assertRaisesRegex(ValueError, "отсутствуют записи"):
            parse_dpscope_config(text)

    def test_wrong_row_schema_is_rejected(self):
        text = "\n".join([
            "table_begin ScriptUserMods_DPScope",
            " table_begin data",
            "  aou_evt_count=1",
            '  aou_evt_1=l"bad|row"',
            " table_end data",
            "table_end ScriptUserMods_DPScope",
        ])
        with self.assertRaisesRegex(ValueError, "полей вместо"):
            parse_dpscope_config(text)

    def test_quoted_value_unescapes_quotes(self):
        self.assertEqual(parse_config_value(r'l"abc\"def"'), 'abc"def')

    def test_named_table_extracts_balanced_nested_tables(self):
        block = extract_named_table(
            "table_begin outer\n table_begin child\n x=1\n table_end child\n"
            "table_end outer",
            "outer",
        )
        self.assertIn("table_begin child", block)
        self.assertIn("x=1", block)


if __name__ == "__main__":
    unittest.main()
