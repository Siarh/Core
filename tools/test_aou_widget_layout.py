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

    def test_resolve_uses_live_current_value_and_separate_sample_range(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:DisplayGlobalInfo(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("unit.GetRage", block)
        self.assertIn("GlobalInfoPanel.Bar:SetPosition(0, 15)", block)
        self.assertIn('GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(currentPool', block)
        self.assertIn('local averagePool = hasSamples and GlobalInfoData.Avg or currentResolve', block)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Avg", common.FormatFloat(averagePool', block)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Min"', block)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Avg"', block)
        self.assertIn('GlobalInfoPanel.Damage:SetVal("Max"', block)
        self.assertIn('GlobalInfoPanel:GetWidth()', block)
        self.assertIn('GlobalInfoPanel.Bar:SetWidth(panelWidth * (percentage / 100))', block)

        init_start = gui.index("function TUMeterGUI:Init()")
        init = gui[init_start:]
        self.assertIn('local globalInfoPanelDesc = self.DetailsPanel:GetChildByName("GlobalInfoPanel"):GetDesc()', init)
        self.assertIn('CreateNewObjectByDesc(wtName, globalInfoPanelDesc, self.DetailsPanel)', init)

        name_xdb = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>5</Pos>", name_xdb)
        self.assertIn("<Size>77</Size>", name_xdb)

        count_xdb = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Count.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>85</Pos>", count_xdb)
        self.assertIn("<Size>42</Size>", count_xdb)

        stats_xdb = (ROOT / "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Pos>132</Pos>", stats_xdb)
        self.assertIn("<Size>200</Size>", stats_xdb)
        self.assertLess(82, 85)
        self.assertLess(127, 132)

    def test_optimizer_uses_local_character_even_when_another_member_is_selected(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateOptim(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("fight.GetCombatant, fight, { id = playerId }", block)
        self.assertIn("local function emptyMode()", block)
        self.assertIn("Optim.BuildLines, optimizerCombatant", block)

    def test_resolve_history_is_sampled_once_per_fight_second(self):
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        self.assertIn("function TUMeter:SampleDetermination()", data)
        self.assertIn("info.LastSampleTime ~= seconds", data)
        self.assertIn("SampleDetermination", events)
        self.assertNotIn("Combatant:UpdateGlobalInfo(params, spellInfo.Determination, mode)", data)

    def test_optimizer_cell_conversion_accepts_non_string_values(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn('local value = tostring(v or "")', gui)


if __name__ == "__main__":
    unittest.main()
