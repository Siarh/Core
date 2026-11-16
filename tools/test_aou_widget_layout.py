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
        self.assertIn("resisted damage by school", gui)

        root = (ROOT / "Widgets/SpellInfoPanel/SpellInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertIn('OpponentPanel/OpponentPanel.(WidgetPanel).xdb', root)

        panel = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/OpponentPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        self.assertIn('TextViews/Name.(WidgetTextView).xdb', panel)
        line = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<HighPos>0</HighPos>", line)
        self.assertIn("<Pos>5</Pos>", line)

    def test_opponent_fallback_reads_current_target_without_last_event(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateOpponentInfo()")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("local hasReadableRow = false", block)
        self.assertIn("if not hasReadableRow and allowCurrentTargetFallback then", block)
        self.assertIn("targetQualityLabel(data.qualityName or data.quality)", block)
        self.assertIn("local ev = Optim and Optim.LastEv and Optim.LastEv[enumMode.Dps] or nil", block)
        self.assertIn("common.IsWString", gui)
        self.assertIn("userMods.FromWString", gui)
        self.assertIn("local eventTarget = ev and ev.target or nil", block)
        self.assertIn("object.IsExist", block)
        self.assertIn("object.IsUnit", block)
        self.assertIn("addCandidate(eventTarget)", block)
        self.assertIn("avatar.GetTarget", block)
        self.assertIn("for candidateIndex = 1, #candidates do", block)
        self.assertIn("pcall(Optim.GetTarget)", block)
        self.assertIn('hpText = (russian and "HP " or "HP ") .. "~"', block)
        self.assertNotIn("if #rows == 0 and Optim and Optim.LastEv", block)
        self.assertIn('key = string.gsub(key, "^ENUM_SubElement_", "")', gui)
        self.assertIn("local numeric = tonumber(key)", gui)
        self.assertIn("row.qualityName = tostring(value)", block)

    def test_primary_window_has_a_persistent_opponent_section(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateMainOpponentInfo()")
        end = gui.index("--------------------------------------------------------------------------------\n-- Type TMainPanelGUI", start)
        block = gui[start:end]

        self.assertIn('"Противники"', block)
        self.assertIn('"Цель не определена"', block)
        self.assertIn("MainOpponentHeader:Show()", block)
        self.assertIn("activeFight.AOUATargetRows", block)
        self.assertIn("AOUA.GetTargetDisplayRows", block)
        self.assertIn("avatar.GetTarget", block)
        update_values = gui[gui.index("function TUMeterGUI:UpdateValues()"):]
        self.assertIn("self:UpdateMainOpponentInfo()", update_values)
        self.assertIn("DPSMeterGUI.UpdateMainOpponentInfo", events)
        init = gui[gui.index("function TUMeterGUI:Init()"):]
        self.assertIn('"MainOpponentHeaderPanel"', init)
        self.assertIn('"MainOpponentPanel" .. opponentIndex', init)

    def test_target_and_combatant_checks_use_canonical_object_ids(self):
        util = (ROOT / "Scripts/AoUMeterUtil.lua").read_text(encoding="utf-8")
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")

        self.assertIn("function SameObjectId(left, right)", util)
        self.assertIn('for _, methodName in ipairs({ "GetId", "GetInstanceId" }) do', util)
        self.assertIn("SameObjectId(Combatant.ID, member.id)", data)
        self.assertIn("SameObjectId(ID, C.ID)", data)
        self.assertIn("local function isAvatarCombatant(combatant)", gui)
        self.assertIn("and isAvatarCombatant(self.SelectedCombatant)", gui)
        self.assertIn("isAvatarCombatant(c)", gui)
        self.assertIn("SameObjectId(params[personalField], id)", events)

    def test_optimizer_target_lookup_falls_back_to_avatar_target(self):
        optim = (ROOT / "Scripts/AoUMeterOptim.lua").read_text(encoding="utf-8")
        start = optim.index("function Optim.GetTarget()")
        end = optim.index("\nend", start)
        block = optim[start:end]
        self.assertIn("object.IsExist", block)
        self.assertIn("object.IsUnit", block)
        self.assertLess(block.index("avatar.GetTarget"), block.index("unit.GetTarget"))
        self.assertIn("if ok then", block)
        self.assertIn("if id ~= nil then return id end", block)

    def test_opponent_section_collapses_to_visible_row_count(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn("local function updateOpponentSectionLayout(dp, displayedRows)", gui)
        self.assertIn("local sectionHeight = displayedRows > 0 and (18 + displayedRows * 18 + 7) or 0", gui)
        self.assertIn("updateOpponentSectionLayout(dp, 0)", gui)
        self.assertIn("dp.OpponentSectionHeight = sectionHeight", gui)
        self.assertIn("dp.OptSpellTop = dp.OptSpellTop + delta", gui)
        self.assertIn("local height = 826 + (dp.OpponentSectionHeight or TARGET_INFO_HEIGHT)", gui)
        self.assertIn("movePanelVertically(dp.SpellHeaderPanel, delta)", gui)
        self.assertIn("movePanelVertically(dp.SpellDetailsHeaderPanel, delta)", gui)

        full_height = 18 + 4 * 18 + 7
        self.assertEqual(full_height, 97)
        self.assertEqual(18 + 1 * 18 + 7, 43)
        self.assertEqual(18 + 2 * 18 + 7, 61)
        self.assertEqual(18 + 3 * 18 + 7, 79)
        self.assertEqual(0, 0)

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
        self.assertIn("isAvatarCombatant(c)", block)
        self.assertNotIn("c.ID == avatar.GetId()", block)
        self.assertIn("Optim.BuildLines, c", block)

    def test_resolve_statistics_are_updated_from_combat_events(self):
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        self.assertIn("Combatant:UpdateGlobalInfo(params, spellInfo.Determination, mode)", data)


    def test_opponent_summary_is_saved_and_shown_for_previous_fight(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        data = (ROOT / "Scripts/AoUMeterData.lua").read_text(encoding="utf-8")
        self.assertIn("self.ActiveFight == self.DPSMeter.Fight.Previous", gui)
        self.assertIn("activeFight.AOUATargetRows", gui)
        self.assertIn("if not hasReadableRow and allowCurrentTargetFallback then", gui)
        self.assertIn("currentFight.AOUATargetRows = rows", data)
        self.assertIn("if currentFight then currentFight.AOUATargetRows = nil end", data)

    def test_current_target_is_visible_before_combat_starts(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateOpponentInfo()")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("local allowCurrentTargetFallback = self.ActiveFight == self.DPSMeter.Fight.Current", block)
        self.assertIn("local liveCurrentFight = self.ActiveFight == self.DPSMeter.Fight.Current", block)
        self.assertIn("and self.DPSMeter.bCollectData == true", block)
        self.assertIn("if not hasReadableRow and allowCurrentTargetFallback then", block)
        self.assertIn("self.ActiveFight == self.DPSMeter.Fight.Previous", block)

    def test_targettest_reports_outgoing_event_pipeline(self):
        optim = (ROOT / "Scripts/AoUMeterOptim.lua").read_text(encoding="utf-8")
        analytics = (ROOT / "Scripts/AoUMeterAnalytics.lua").read_text(encoding="utf-8")
        self.assertIn("outgoing callbacks/owner/accepted/other=", optim)
        self.assertIn("diag.outgoingHitCallbacks", analytics)
        self.assertIn("outgoingHitOwnerMatched", analytics)
        self.assertIn("diag.lastOutgoingTarget", optim)


if __name__ == "__main__":
    unittest.main()
