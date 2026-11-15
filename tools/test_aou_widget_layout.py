"""Regression checks for DPScope's global-info display path."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GlobalInfoLayoutTests(unittest.TestCase):
    def test_global_info_display_does_not_call_wrapper_methods_on_raw_children(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:DisplayGlobalInfo(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        for widget in ("Name", "Count", "Damage", "Percent"):
            self.assertNotIn(f"GlobalInfoPanel.{widget}:SetWidth", block)
            self.assertNotIn(f"GlobalInfoPanel.{widget}:SetPosition", block)

    def test_global_info_resolve_value_is_inline_and_range_is_preserved(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:DisplayGlobalInfo(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("GlobalInfoPanel.Bar:SetPosition(0, 15)", block)
        self.assertIn('GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(GlobalInfoData.Avg', block)
        self.assertIn('GlobalInfoPanel.Percent:SetVal("Percentage", userMods.ToWString(""))', block)
        for field in ("Min", "Avg", "Max"):
            self.assertIn(f'GlobalInfoPanel.Damage:SetVal("{field}"', block)
        self.assertIn("GlobalInfoPanel.Bar:SetWidth(396 * (GlobalInfoData.Percentage / 100))", block)

        count_xdb = (ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/Count.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Align>WIDGET_ALIGN_LOW</Align>", count_xdb)
        self.assertIn("<Pos>76</Pos>", count_xdb)
        self.assertIn("<Size>45</Size>", count_xdb)

    def test_optimizer_cell_conversion_accepts_non_string_values(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn('local value = tostring(v or "")', gui)


if __name__ == "__main__":
    unittest.main()