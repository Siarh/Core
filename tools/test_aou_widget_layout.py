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
        self.assertNotIn("GlobalInfoPanel.Name:SetWidth", block)
        self.assertNotIn("GlobalInfoPanel.Name:SetPosition", block)
        self.assertNotIn("GlobalInfoPanel.Count:SetWidth", block)
        self.assertNotIn("GlobalInfoPanel.Count:SetPosition", block)
        self.assertNotIn("GlobalInfoPanel.Damage:SetWidth", block)
        self.assertNotIn("GlobalInfoPanel.Damage:SetPosition", block)
        self.assertNotIn("GlobalInfoPanel.Percent:SetWidth", block)
        self.assertNotIn("GlobalInfoPanel.Percent:SetPosition", block)

    def test_global_info_still_populates_all_fields(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:DisplayGlobalInfo(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        for field in (
            'GlobalInfoPanel.Name:SetVal("Name"',
            'GlobalInfoPanel.Count:SetVal("Count"',
            'GlobalInfoPanel.Damage:SetVal("Min"',
            'GlobalInfoPanel.Damage:SetVal("Avg"',
            'GlobalInfoPanel.Damage:SetVal("Max"',
            'GlobalInfoPanel.Percent:SetVal("Percentage"',
        ):
            with self.subTest(field=field):
                self.assertIn(field, block)
        self.assertIn("GlobalInfoPanel.Bar:SetPosition(0, 13)", block)
        self.assertIn("GlobalInfoPanel.Bar:SetWidth(396 * (GlobalInfoData.Percentage / 100))", block)


if __name__ == "__main__":
    unittest.main()
