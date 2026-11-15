"""Regression checks for DPScope's Resolve row layout."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GlobalInfoLayoutTests(unittest.TestCase):
    def test_global_info_rows_use_the_dedicated_compact_template(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn('local globalInfoPanelDesc = self.DetailsPanel:GetChildByName("GlobalInfoPanel"):GetDesc()', gui)
        self.assertIn('CreateNewObjectByDesc(wtName, globalInfoPanelDesc, self.DetailsPanel)', gui)
        self.assertIn('CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)', gui)

        panel = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/GlobalInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertIn('SpellDetailBar/SpellDetailBar.(WidgetPanel).xdb', panel)

        name = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>5</Pos>", name)
        self.assertIn("<Size>77</Size>", name)

        count = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Count.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>85</Pos>", count)
        self.assertIn("<Size>42</Size>", count)

        stats = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>132</Pos>", stats)
        self.assertIn("<Size>200</Size>", stats)

    def test_opponent_summary_uses_one_full_width_labelled_line(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn("local function targetIsUtf8", gui)
        self.assertIn("local function targetReadableName", gui)
        self.assertIn('if name ~= "" then parts[#parts + 1] = name end', gui)
        self.assertIn('dp.OpponentHeader.Line:SetVal("Name"', gui)
        self.assertNotIn("Без имени", gui)
        self.assertNotIn("Unnamed", gui)
        self.assertNotIn("Нет данных о целях", gui)
        self.assertIn("resistance in events", gui)

        root = (ROOT / "Widgets/SpellInfoPanel/SpellInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertIn('OpponentPanel/OpponentPanel.(WidgetPanel).xdb', root)

        panel = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/OpponentPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertIn('TextViews/Name.(WidgetTextView).xdb', panel)
        line = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<HighPos>0</HighPos>", line)
        self.assertIn("<Pos>5</Pos>", line)

    def test_resolve_value_is_next_to_the_label_and_bar_is_bounded(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:DisplayGlobalInfo(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("unit.GetRage", block)
        self.assertIn("GlobalInfoPanel.Bar:SetPosition(0, 15)", block)
        self.assertIn("local barWidth = math.min(panelWidth, 356)", block)
        self.assertIn('GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(currentPool, "%d%%"))', block)
        self.assertIn('GlobalInfoPanel.Percent:SetVal("Percentage", userMods.ToWString(""))', block)
        for field in ("Min", "Avg", "Max"):
            self.assertIn(f'GlobalInfoPanel.Damage:SetVal("{field}"', block)

    def test_optimizer_is_limited_to_the_selected_local_player(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateOptim(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("c and fight and not self.Hovering", block)
        self.assertIn("c.ID == avatar.GetId()", block)
        self.assertIn("Optim.BuildLines, c", block)

    def test_resolve_statistics_are_updated_from_combat_events(self):
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        self.assertIn("Combatant:UpdateGlobalInfo(params, spellInfo.Determination, mode)", data)


if __name__ == "__main__":
    unittest.main()
