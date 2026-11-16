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

    def test_restored_gui_has_no_mixed_in_target_panel_runtime_calls(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        self.assertNotIn("TargetInfoPanel", gui)
        self.assertNotIn("UpdateTargetInfo", gui)
        self.assertNotIn("UpdateTargetInfo", events)


if __name__ == "__main__":
    unittest.main()
