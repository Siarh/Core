"""Checks that the restored DPScope UI matches the saved working backup."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BackupRestoreCompatibilityTests(unittest.TestCase):
    def test_spell_window_and_global_info_use_the_backup_widget_contract(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        spell_root = (ROOT / "Widgets/SpellInfoPanel/SpellInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        global_panel = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/GlobalInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        header_panel = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/GlobalInfoHeaderPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        values = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")

        self.assertIn('Damage = widget:GetChildByName("SpellDetailTextViewStats").Widget', gui)
        self.assertIn('TextViews/DamageStats.(WidgetTextView).xdb', global_panel)
        self.assertIn('TextViews/DamageStats.(WidgetTextView).xdb', header_panel)
        self.assertIn('<Name>SpellDetailTextViewStats</Name>', values)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Min"', gui)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Avg"', gui)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Max"', gui)
        self.assertNotIn("OpponentPanel", spell_root)

    def test_resolve_columns_use_existing_monospaced_text_views(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        global_header = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        formats = [
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/DamageStats.txt",
        ]

        self.assertIn("local DAMAGE_COLUMN_WIDTH = 7", gui)
        self.assertIn("setDamageColumnHeader(", gui)
        self.assertIn('padDamageColumn(common.FormatFloat(GlobalInfoData.Min', gui)
        self.assertIn('padDamageColumn(common.FormatFloat(spellInfoData.Min', gui)
        self.assertIn('padDamageColumn(cell(ln[2]))', gui)
        self.assertIn("self.DetailsPanel.SpellDetailsHeaderPanel:GetDesc()", gui)
        self.assertIn("SpellDetailHeaderTextViewStats", gui)
        self.assertIn("<Align>WIDGET_ALIGN_LOW</Align>", global_header)
        self.assertIn("<Pos>146</Pos>", global_header)
        self.assertIn("<Size>200</Size>", global_header)
        global_row = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>146</Pos>", global_row)
        self.assertIn("<Size>200</Size>", global_row)

        for path in formats:
            with self.subTest(path=path):
                self.assertIn('fontname="AllodsConsole"', path.read_text(encoding="utf-16"))

    def test_restored_gui_has_no_mixed_in_target_panel_runtime_calls(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        self.assertNotIn("TargetInfoPanel", gui)
        self.assertNotIn("UpdateTargetInfo", gui)
        self.assertNotIn("UpdateTargetInfo", events)


if __name__ == "__main__":
    unittest.main()
