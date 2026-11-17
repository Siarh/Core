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

    def test_resolve_bar_and_min_avg_max_columns_remain_aligned(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        global_header = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        global_row = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        global_formats = [
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoHeaderPanel/TextViews/DamageStats.txt",
            ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.txt",
        ]

        self.assertIn("<Align>WIDGET_ALIGN_LOW</Align>", global_header)
        self.assertIn("<Pos>146</Pos>", global_header)
        self.assertIn("<Size>200</Size>", global_header)
        self.assertIn("<Align>WIDGET_ALIGN_LOW</Align>", global_row)
        self.assertIn("<Pos>146</Pos>", global_row)
        self.assertIn("<Size>200</Size>", global_row)
        self.assertIn('function TUMeterGUI:SetGlobalInfoStatsHeader()', gui)
        self.assertIn('setDamageColumnHeader(\n\t\tdetails.GlobalInfoHeaderStatsText', gui)
        self.assertIn('padDamageColumn(common.FormatFloat(GlobalInfoData.Min', gui)
        self.assertIn('padDamageColumn(common.FormatFloat(GlobalInfoData.Avg', gui)
        self.assertIn('padDamageColumn(common.FormatFloat(GlobalInfoData.Max', gui)

        for path in global_formats:
            with self.subTest(path=path):
                self.assertIn('fontname="AllodsConsole"', path.read_text(encoding="utf-16"))

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

    def test_spell_detail_hit_counts_have_their_own_column(self):
        header_name = (ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        row_name = (ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        header_count = (ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/Count.(WidgetTextView).xdb").read_text(encoding="utf-8")
        row_count = (ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/Count.(WidgetTextView).xdb").read_text(encoding="utf-8")
        header_stats = (ROOT / "Widgets/SpellInfoPanel/SpellDetailHeaderPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        row_stats = (ROOT / "Widgets/SpellInfoPanel/SpellDetailPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")

        # Name: x=5..135; Count: x=136..191; Min/Avg/Max: x=196..356.
        for text_view in (header_name, row_name):
            with self.subTest(view="name"):
                self.assertIn("<HighPos>261</HighPos>", text_view)
        for text_view in (header_count, row_count):
            with self.subTest(view="count"):
                self.assertIn("<Align>WIDGET_ALIGN_LOW</Align>", text_view)
                self.assertIn("<Pos>136</Pos>", text_view)
                self.assertIn("<Size>55</Size>", text_view)
        for text_view in (header_stats, row_stats):
            with self.subTest(view="stats"):
                self.assertIn("<HighPos>40</HighPos>", text_view)
                self.assertIn("<Size>160</Size>", text_view)

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

    def test_target_summary_reuses_the_existing_two_line_title(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        analytics = (ROOT / "Scripts/AoUMeterAnalytics.lua").read_text(encoding="utf-8")
        title_format = (ROOT / "Widgets/SpellInfoPanel/TextViews/Name.txt").read_text(encoding="utf-8-sig")
        title_widget = (ROOT / "Widgets/SpellInfoPanel/TextViews/SpellPlayerName.(WidgetTextView).xdb").read_text(encoding="utf-8")

        self.assertIn("function TUMeterGUI:GetActiveTargetDisplayRow()", gui)
        self.assertIn("pcall(AOUA.GetTargetDisplayRows, 1)", gui)
        self.assertIn("fight.AOUATargetRows", gui)
        self.assertIn('SetVal("TargetName"', gui)
        self.assertIn('SetVal("TargetLevel"', gui)
        self.assertIn('SetVal("TargetType"', gui)
        self.assertIn('SetVal("TargetHealth"', gui)
        self.assertIn("function AOUA.GetTargetDisplayRows(limit)", analytics)
        self.assertIn("row.hpLimit = profile.hpLimit", analytics)
        self.assertIn("<br>", title_format)
        for tag in ("TargetName", "TargetLevel", "TargetType", "TargetHealth"):
            with self.subTest(tag=tag):
                self.assertIn(f'<r name="{tag}"/>', title_format)
        self.assertIn("<Size>50</Size>", title_widget)
        self.assertIn("function TUMeterGUI:SetWillControlDisplayValue()", gui)
        self.assertIn("function AOUA.GetWillControlSummary()", analytics)
        self.assertIn("function AOUA.OnWillControlBuffAdded(params)", analytics)
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        self.assertIn("currentFight.AOUAWillControl = summary", data)
        self.assertIn("AOUAWillControl", gui)
        self.assertIn("EVENT_OBJECT_BUFF_ADDED", analytics)
        self.assertIn("EVENT_OBJECT_BUFF_CHANGED", analytics)
        self.assertIn("EVENT_OBJECT_BUFF_REMOVED", analytics)
        self.assertIn('<r name="WillInfo"/>', title_format)
        spell_root = (ROOT / "Widgets/SpellInfoPanel/SpellInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertNotIn("TargetInfoPanel", spell_root)

    def test_restored_gui_has_no_mixed_in_target_panel_runtime_calls(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        self.assertNotIn("TargetInfoPanel", gui)
        self.assertNotIn("UpdateTargetInfo", gui)
        self.assertNotIn("UpdateTargetInfo", events)


if __name__ == "__main__":
    unittest.main()
