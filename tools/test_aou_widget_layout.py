"""Regression checks for the runtime DPScope global-info row layout."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GlobalInfoLayoutTests(unittest.TestCase):
    def test_global_info_rows_use_the_runtime_clone_template(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn(
            'local spellInfoPanelDesc = self.DetailsPanel:GetChildByName("SpellDetailPanel"):GetDesc()',
            gui,
        )
        self.assertIn(
            'self.DetailsPanel.GlobalInfoList[extraIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)',
            gui,
        )

    def test_global_info_text_columns_are_separated_at_runtime(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        expected = (
            "GlobalInfoPanel.Name:SetWidth(110)",
            "GlobalInfoPanel.Name:SetPosition(5, 1)",
            "GlobalInfoPanel.Count:SetWidth(30)",
            "GlobalInfoPanel.Count:SetPosition(120, 1)",
            "GlobalInfoPanel.Damage:SetWidth(160)",
            "GlobalInfoPanel.Damage:SetPosition(156, 1)",
            "GlobalInfoPanel.Percent:SetWidth(35)",
            "GlobalInfoPanel.Percent:SetPosition(percentageX, 1)",
        )
        for statement in expected:
            with self.subTest(statement=statement):
                self.assertIn(statement, gui)

    def test_percent_follows_the_bar_without_covering_stats(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn("local globalInfoBarWidth = 356", gui)
        self.assertIn(
            "local globalInfoFilledWidth = globalInfoBarWidth * (GlobalInfoData.Percentage / 100)",
            gui,
        )
        self.assertIn(
            "local percentageX = math.max(321, math.min(361, globalInfoFilledWidth + 5))",
            gui,
        )

    def test_min_avg_max_spacing_is_changed_in_the_active_clone_format(self):
        fmt = (
            ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/DamageStats.txt"
        ).read_text(encoding="utf-8-sig")
        self.assertGreaterEqual(fmt.count("   |   "), 2)


if __name__ == "__main__":
    unittest.main()
