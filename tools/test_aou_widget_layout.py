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

    def test_resolve_bar_keeps_original_global_info_row_layout(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        global_header = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        global_row = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        global_formats = [
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.txt",
        ]

        self.assertIn("<Align>WIDGET_ALIGN_HIGH</Align>", global_header)
        self.assertIn("<Size>160</Size>", global_header)
        self.assertIn("<Pos>132</Pos>", global_row)
        self.assertIn("<Size>200</Size>", global_row)
        self.assertNotIn('padDamageColumn(common.FormatFloat(GlobalInfoData.Min', gui)
        self.assertNotIn('setDamageColumnHeader(', gui.split("function TUMeterGUI:UpdateSpellList()", 1)[1].split("function TUMeterGUI:UpdateValues()", 1)[0])

        for path in global_formats:
            with self.subTest(path=path):
                self.assertNotIn('fontname="AllodsConsole"', path.read_text(encoding="utf-16"))

    def test_spell_detail_and_optimizer_columns_remain_monospaced(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        formats = [
            ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/DamageStats.txt",
        ]
        self.assertIn("local DAMAGE_COLUMN_WIDTH = 7", gui)
        self.assertIn('padDamageColumn(common.FormatFloat(spellInfoData.Min', gui)
        self.assertIn('padDamageColumn(cell(ln[2]))', gui)
        self.assertIn("self.DetailsPanel.SpellDetailsHeaderPanel:GetDesc()", gui)
        for path in formats:
            with self.subTest(path=path):
                self.assertIn('fontname="AllodsConsole"', path.read_text(encoding="utf-16"))

    def test_global_info_and_optimizer_headers_have_no_trailing_hash(self):
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        locale = (ROOT / "Locales/rus/GlobalInfo.txt").read_bytes().decode("utf-8-sig")
        global_count = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/Count.txt").read_text(encoding="utf-16")
        optimizer_count = (ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/Count.txt").read_text(encoding="utf-16")
        self.assertIn('globalInfoCaption = Optim.ToWString("Информация...")', events)
        self.assertIn('local globalInfoCaption = GetTextLocalized("GlobalInfo")', events)
        self.assertEqual(locale, "Глобальная информационная")
        self.assertIn('<r name="Count"/>', global_count)
        self.assertNotIn('<r name="Count"/>#', global_count)
        self.assertIn('<r name="Count"/>', optimizer_count)
        self.assertNotIn('<r name="Count"/>#', optimizer_count)

    def test_restored_gui_has_no_mixed_in_target_panel_runtime_calls(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        self.assertNotIn("TargetInfoPanel", gui)
        self.assertNotIn("UpdateTargetInfo", gui)
        self.assertNotIn("UpdateTargetInfo", events)


if __name__ == "__main__":
    unittest.main()
