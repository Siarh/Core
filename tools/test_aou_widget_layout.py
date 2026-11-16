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

    def test_target_row_reuses_xdb_text_style_under_resolve_and_before_abilities(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        root = (ROOT / "Widgets/SpellInfoPanel/SpellInfoPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        panel = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/OpponentPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        line = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        style = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/TextViews/Name.txt").read_text(encoding="utf-8")

        self.assertIn('OpponentPanel/OpponentPanel.(WidgetPanel).xdb', root)
        self.assertIn("<Name>TargetInfoPanel</Name>", panel)
        self.assertIn('TextViews/Name.(WidgetTextView).xdb', panel)
        self.assertIn("<Name>TargetInfoTextView</Name>", line)
        self.assertIn('<header alignx="left" fontsize="11" outline="1">', style)

        init = gui[gui.index("function TUMeterGUI:Init()"):]
        self.assertIn("local targetInfoOffset = GlobalInfoOffset + EXTRATYPES * 18 + 7", init)
        self.assertIn('self.DetailsPanel.TargetInfoPanel = self.DetailsPanel:GetChildByName("TargetInfoPanel")', init)
        self.assertIn('self.DetailsPanel.TargetInfoText = self.DetailsPanel.TargetInfoPanel:GetChildByName("TargetInfoTextView").Widget', init)
        self.assertIn("self.DetailsPanel.TargetInfoPanel:SetPosition(22, targetInfoOffset)", init)
        self.assertIn("local spellHeaderOffset = targetInfoOffset + 18", init)

        global_info = gui[gui.index("function TUMeterGUI:DisplayGlobalInfo("):gui.index("\n--------------------------------------------------------------------------------\n-- The target strip", gui.index("function TUMeterGUI:DisplayGlobalInfo("))]
        self.assertIn("GlobalInfoPanel.Bar:Hide()", global_info)
        self.assertIn("if isResolve then", global_info)

    def test_target_info_reads_current_object_health_and_keeps_unknown_hp_unknown(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateTargetInfo()")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn("avatar.GetTarget", block)
        self.assertIn("object.IsExist", block)
        self.assertIn("object.GetName", block)
        self.assertIn("userMods.FromWString", gui)
        self.assertIn("unit.GetLevel", block)
        self.assertIn("object.GetHealthInfo", block)
        self.assertIn("health.value", block)
        self.assertIn("health.limit", block)
        self.assertIn("health.valuePercents", block)
        self.assertIn('string.format("%s | ур. %s | HP %s/%s (%s%%)"', block)
        self.assertIn('text:SetVal("Name", targetText(line))', block)
        self.assertIn('targetText("Цель не выбрана")', block)
        self.assertNotIn('hpCurrentPercent .. "/100"', block)

    def test_target_health_watch_is_filtered_and_retargeted_cleanly(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        sub_start = gui.index("function TUMeterGUI:UpdateTargetHealthSubscription(")
        sub_end = gui.index("\nend", sub_start)
        sub = gui[sub_start:sub_end]
        self.assertIn('common.RegisterEventHandler(self.TargetHealthHandler,', sub)
        self.assertIn('"EVENT_OBJECT_HEALTH_CHANGED", { id = targetId }', sub)
        self.assertIn('common.UnRegisterEventHandler(self.TargetHealthHandler,', sub)
        self.assertIn('"EVENT_OBJECT_HEALTH_CHANGED", { id = oldId }', sub)
        self.assertIn("SameObjectId(params.id, watchedId)", gui)
        self.assertIn('onMyEvent["EVENT_AVATAR_TARGET_CHANGED"]', events)
        self.assertIn('onMyEvent["EVENT_UNIT_LEVEL_CHANGED"]', events)
        self.assertIn("params.unitId", events)

    def test_target_row_is_updated_after_child_refresh_and_not_inside_optimizer(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateSpellList()")
        end = gui.index("\nend", start)
        spell_list = gui[start:end]
        self.assertLess(spell_list.index("detailsPanel:HideAllChild()"), spell_list.index("self:UpdateTargetInfo()"))
        optim_start = gui.index("function TUMeterGUI:UpdateOptim()")
        optim_end = gui.index("\n--------------------------------------------------------------------------------\n-- Fill the spell panel", optim_start)
        optim = gui[optim_start:optim_end]
        self.assertNotIn("TargetInfoPanel", optim)
        self.assertNotIn("OpponentLineVisible", optim)
        self.assertIn("height = y + 18 + table.getn(lines) * 18 + 20", optim)

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
        self.assertNotIn("isAvatarCombatant(self.SelectedCombatant)", gui)
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


    def test_targettest_reports_outgoing_event_pipeline(self):
        optim = (ROOT / "Scripts/AoUMeterOptim.lua").read_text(encoding="utf-8")
        analytics = (ROOT / "Scripts/AoUMeterAnalytics.lua").read_text(encoding="utf-8")
        self.assertIn("outgoing callbacks/owner/accepted/other=", optim)
        self.assertIn("diag.outgoingHitCallbacks", analytics)
        self.assertIn("outgoingHitOwnerMatched", analytics)
        self.assertIn("diag.lastOutgoingTarget", optim)


if __name__ == "__main__":
    unittest.main()
