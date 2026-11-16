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

        self.assertIn("TGlobalInfoPanelGUI:CreateNewObjectByDesc", gui)

    def test_min_avg_max_use_independent_matching_fixed_columns(self):
        columns = (
            ("Min", 196, 46, "DamageMin.txt"),
            ("Sep1", 242, 8, "DamageSeparator.txt"),
            ("Avg", 250, 50, "DamageAvg.txt"),
            ("Sep2", 300, 8, "DamageSeparator.txt"),
            ("Max", 308, 48, "DamageMax.txt"),
        )
        panel_dirs = (
            ("GlobalInfoPanel", "SpellDetailTextView"),
            ("GlobalInfoHeaderPanel", "GlobalInfoHeaderTextView"),
        )
        for panel_dir, prefix in panel_dirs:
            panel = (ROOT / "Widgets/SpellInfoPanel" / panel_dir /
                     (panel_dir + ".(WidgetPanel).xdb")).read_text(encoding="utf-8")
            self.assertNotIn("TextViews/DamageStats.(WidgetTextView).xdb", panel)
            for key, x, width, format_file in columns:
                view = (ROOT / "Widgets/SpellInfoPanel" / panel_dir / "TextViews" /
                        f"{key}.(WidgetTextView).xdb").read_text(encoding="utf-8")
                self.assertIn(f"<Name>{prefix}{key}</Name>", view)
                self.assertIn(f"<Pos>{x}</Pos>", view)
                self.assertIn(f"<Size>{width}</Size>", view)
                self.assertIn(f'href="{format_file}"', view)

        for metric in ("Min", "Avg", "Max"):
            for panel_dir in ("GlobalInfoPanel", "GlobalInfoHeaderPanel"):
                fmt_path = (ROOT / "Widgets/SpellInfoPanel" / panel_dir / "TextViews" /
                            f"Damage{metric}.txt")
                raw = fmt_path.read_bytes()
                self.assertTrue(raw.startswith(b"\xff\xfe"))
                fmt = raw.decode("utf-16")
                self.assertIn('alignx = "center"', fmt)

        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        self.assertIn("GlobalInfoPanel.Min:SetVal", gui)
        self.assertIn("GlobalInfoPanel.Avg:SetVal", gui)
        self.assertIn("GlobalInfoPanel.Max:SetVal", gui)
        self.assertIn("dp.OptHeaderMin:SetVal", gui)
        self.assertIn("dp.OptHeaderAvg:SetVal", gui)
        self.assertIn("dp.OptHeaderMax:SetVal", gui)

    def test_target_row_is_a_dynamic_child_of_the_analyzer_and_drawn_above_global_rows(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        panel = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/OpponentPanel.(WidgetPanel).xdb").read_text(encoding="utf-8")
        line = (ROOT / "Widgets/SpellInfoPanel/OpponentPanel/TextViews/Name.(WidgetTextView).xdb").read_text(encoding="utf-8")
        self.assertIn("<Name>TargetInfoPanel</Name>", panel)
        self.assertIn("<Name>TargetInfoTextView</Name>", line)
        init = gui[gui.index("function TUMeterGUI:Init()"):]
        self.assertIn('local targetTemplate = self.DetailsPanel:GetChildByName("TargetInfoPanel")', init)
        self.assertIn("local targetPanelDesc = targetTemplate:GetDesc()", init)
        self.assertIn("targetTemplate:Destroy()", init)
        self.assertIn('TWidget:CreateNewObjectByDesc(\n\t\t"TargetInfoAnalyzerPanel", targetPanelDesc, self.DetailsPanel)', init)

        block = gui[gui.index("function TUMeterGUI:UpdateOptim()"):gui.index("\n--------------------------------------------------------------------------------\n-- Fill the spell panel", gui.index("function TUMeterGUI:UpdateOptim()"))]
        self.assertIn("local hasTargetLine = targetPanel ~= nil and not self.Hovering", block)
        self.assertIn("if lines or hasTargetLine then", block)
        self.assertIn("targetPanel:SetPosition(22, y + 18)", block)
        self.assertIn("targetPanel:Show()", block)
        self.assertIn("local targetRowOffset = 0", block)
        self.assertIn("row:SetPosition(22, y + 18 + (i - 1 + targetRowOffset) * 18)", block)
        self.assertIn("table.getn(lines)", block)

    def test_target_info_reads_live_current_target_and_unknown_hp_stays_unknown(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateTargetInfo()")
        end = gui.index("\nend", start)
        block = gui[start:end]
        for token in ("avatar.GetTarget", "object.IsExist", "object.GetName", "unit.GetLevel",
                      "object.GetHealthInfo", "health.value", "health.limit", "health.valuePercents"):
            self.assertIn(token, block)
        self.assertIn('string.format("%s | ур. %s | HP %s/%s (%s%%)"', block)
        self.assertIn('text:SetVal("Name", targetText(line))', block)
        self.assertIn('targetText(localization == "rus" and "Цель не выбрана" or "No target selected")', block)

    def test_target_health_watch_uses_filtered_main_thread_and_retargets(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        events = (ROOT / "Scripts/AoUMeterEvents.lua").read_text(encoding="utf-8")
        start = gui.index("function TUMeterGUI:UpdateTargetHealthSubscription(")
        end = gui.index("\nend", start)
        block = gui[start:end]
        self.assertIn('"EVENT_OBJECT_HEALTH_CHANGED", { id = targetId }, true)', block)
        self.assertIn('"EVENT_OBJECT_HEALTH_CHANGED", { id = oldId }, true)', block)
        self.assertIn("SameObjectId(params.id, watchedId)", gui)
        self.assertIn('onMyEvent["EVENT_AVATAR_TARGET_CHANGED"]', events)
        self.assertIn("pcall(gui.UpdateOptim, gui)", events)

    def test_target_row_survives_optimizer_nil_and_is_updated_after_child_refresh(self):
        gui = (ROOT / "Scripts/AoUMeterGUI.lua").read_text(encoding="utf-8")
        spell_start = gui.index("function TUMeterGUI:UpdateSpellList()")
        spell_end = gui.index("\nend", spell_start)
        spell_block = gui[spell_start:spell_end]
        self.assertLess(spell_block.index("detailsPanel:HideAllChild()"), spell_block.index("self:UpdateTargetInfo()"))
        self.assertLess(spell_block.index("self:UpdateTargetInfo()"), spell_block.index("self:UpdateOptim()"))
        optim_start = gui.index("function TUMeterGUI:UpdateOptim()")
        optim_end = gui.index("\n--------------------------------------------------------------------------------\n-- Fill the spell panel", optim_start)
        optim = gui[optim_start:optim_end]
        self.assertIn("if lines or hasTargetLine then", optim)
        self.assertIn("local lineCount = lines and table.getn(lines) or 0", optim)
        self.assertIn("height = y + 18 + (lineCount + targetRowOffset) * 18 + 20", optim)

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
        self.assertIn("if not isResolve then", block)
        self.assertIn("local barWidth = math.min(panelWidth, 356)", block)
        self.assertIn('GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(currentPool, "%d%%"))', block)
        self.assertIn('GlobalInfoPanel.Percent:SetVal("Percentage", userMods.ToWString(""))', block)
        for field in ("Min", "Avg", "Max"):
            self.assertIn(f'GlobalInfoPanel.{field}:SetVal("{field}"', block)

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
