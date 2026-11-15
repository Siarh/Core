#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import unittest

import aou_event_history_to_profile as importer


def event(kind, fight, second, mastery, amount):
    return {
        "kind": kind, "fight_id": fight, "profile": "pve", "second": str(second),
        "M": str(mastery), "R": "0", "U": "0", "L": "0",
        "observed_amount": str(amount), "target_hp_before": "100",
        "hp_quality": "measured_pre", "resolve_pool": "50", "critical": "0",
        "runes_absorb": "0", "ability": "Test", "element": "physical",
        "recipient": "self", "target_max_hp": "100000", "actor_id": "player-1", "target_id": "target-1", "stat_sample_second": str(second), "stat_sample_age": "0",
    }


class ChangingStatsTests(unittest.TestCase):
    def test_stat_signature_uses_median_instead_of_rejecting_changes(self):
        rows = [event("damage", "f1", 1, 445.1, 1000), event("damage", "f2", 1, 595.1, 1200)]
        stats = importer.stat_signature(rows)
        self.assertEqual(stats["mastery"], 595.1)

    def test_comparison_reports_separate_stat_sets_and_rates(self):
        rows = [event("damage", "f1", 1, 445.1, 1000), event("damage", "f2", 1, 595.1, 1200),
                event("healing", "f1", 2, 445.1, 500)]
        comparison = importer.compare_stat_sets(rows)
        self.assertEqual(len(comparison["groups"]), 3)
        low = next(group for group in comparison["groups"]
                   if group["stats"]["mastery"] == 445.1 and group["kind"] == "damage")
        low_heal = next(group for group in comparison["groups"] if group["kind"] == "healing")
        self.assertEqual(low["observed_damage"], 1000)
        self.assertEqual(low["observed_healing"], 0)
        self.assertEqual(low["observed_dps_estimate"], 500)
        self.assertEqual(low_heal["observed_healing"], 500)
        self.assertEqual(low_heal["healing_by_recipient"]["self"]["amount"], 500)

    def test_profile_build_accepts_multiple_mastery_snapshots(self):
        rows = [event("damage", "f1", 1, 445.1, 1000), event("damage", "f2", 1, 595.1, 1200)]
        profile = importer.build_profile(rows, 20, 0.015)
        self.assertEqual(profile["import_summary"]["included_events"], 2)
        self.assertEqual(len(profile["stat_comparison"]["groups"]), 2)
        self.assertEqual(profile["controlled_stat_efficiency"]["status"], "insufficient_data")
        self.assertTrue(any("характеристики менялись" in warning.lower()
                            for warning in profile["import_warnings"]))


    def test_controlled_efficiency_matches_ability_hp_resolve_and_crit(self):
        rows = []

        def add_fight(prefix, mastery, base_amount):
            for fight_number in range(1, 4):
                fight = f"{prefix}{fight_number}"
                for repeat in range(5):
                    row = event("damage", fight, 5 + repeat % 3, mastery, base_amount)
                    row.update({
                        "profile": "pve",
                        "M": str(mastery),
                        "R": "200", "U": "300", "L": "400",
                        "S": "500", "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "54", "critical": "0",
                        "ability": "Holy Wrath", "damage_source": "spell",
                        "element": "light", "target_max_hp": "1000000",
                    })
                    rows.append(row)
                    crit_row = dict(row)
                    crit_row["critical"] = "1"
                    crit_row["observed_amount"] = str(base_amount * 2)
                    rows.append(crit_row)

        add_fight("base", 1000, 1000)
        add_fight("test", 1100, 1050)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        mastery = [item for item in analysis["comparisons"]
                   if item["stat"] == "mastery" and item["critical"] is False]
        critical = [item for item in analysis["comparisons"]
                    if item["stat"] == "mastery" and item["critical"] is True]
        self.assertEqual(len(mastery), 1)
        self.assertEqual(len(critical), 1)
        self.assertEqual(mastery[0]["duration_band"], "0-10 sec")
        self.assertEqual(mastery[0]["critical_scope"], "normal_only")
        self.assertEqual(mastery[0]["baseline"]["mean_event_amount"], 1000.0)
        self.assertEqual(mastery[0]["baseline"]["mean_context_rate_per_second"], 625.0)
        self.assertEqual(mastery[0]["target_hp_band"], "60-80%")
        self.assertEqual(mastery[0]["resolve_pool_band"], "50-60%")
        self.assertEqual(mastery[0]["baseline"]["fights"], 3)
        self.assertEqual(mastery[0]["test"]["fights"], 3)
        self.assertEqual(mastery[0]["marginal_efficiency_per_100"], 31.25)
        self.assertEqual(mastery[0]["confidence_interval_95_per_100"], [31.25, 31.25])
        self.assertEqual(critical[0]["marginal_efficiency_per_100"], 62.5)
        self.assertEqual(critical[0]["critical_scope"], "critical_only")
        self.assertEqual(mastery[0]["marginal_efficiency_unit"], "reported amount per second per +100 stat points")
        self.assertEqual(mastery[0]["classification"], "DERIVED")
        self.assertIn("not_proven", mastery[0]["causal_status"])

    def test_defensive_stat_efficiency_uses_incoming_events(self):
        rows = []
        for prefix, fortitude, amount in (("low", 1000, 1000), ("high", 1100, 900)):
            for fight_number in range(1, 4):
                for repeat in range(5):
                    row = event("incoming", f"{prefix}{fight_number}", 5 + repeat % 3, 500, amount)
                    row.update({
                        "profile": "pvp",
                        "M": "100", "R": "200", "U": "300", "L": "400",
                        "S": str(fortitude), "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "", "critical": "0",
                        "ability": "Enemy strike", "damage_source": "attack",
                        "element": "physical", "target_max_hp": "50000",
                    })
                    rows.append(row)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        fortitude = [item for item in analysis["comparisons"] if item["stat"] == "fortitude"]
        self.assertEqual(len(fortitude), 1)
        self.assertEqual(fortitude[0]["mode"], "incoming")
        self.assertEqual(fortitude[0]["profile"], "pvp")
        self.assertEqual(fortitude[0]["marginal_efficiency_per_100"], -62.5)

    def test_other_stat_change_rejects_marginal_comparison(self):
        rows = []
        for prefix, mastery, resolve in (("base", 1000, 200), ("test", 1100, 300)):
            for fight_number in range(1, 4):
                for repeat in range(5):
                    row = event("damage", f"{prefix}{fight_number}", 5 + repeat % 3, mastery, 1000)
                    row.update({
                        "profile": "pve", "R": str(resolve), "U": "300", "L": "400",
                        "S": "500", "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "54", "critical": "0",
                        "ability": "Holy Wrath", "damage_source": "spell",
                    })
                    rows.append(row)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        self.assertEqual(analysis["status"], "insufficient_data")
        self.assertEqual(analysis["comparisons"], [])

    def test_stats_changed_inside_fight_excludes_that_fight(self):
        rows = []
        for prefix, mastery, amount in (("base", 1000, 1000), ("test", 1100, 1050)):
            for fight_number in range(1, 4):
                for repeat in range(5):
                    row = event("damage", f"{prefix}{fight_number}", 5 + repeat % 3, mastery, amount)
                    row.update({
                        "profile": "pve", "R": "200", "U": "300", "L": "400",
                        "S": "500", "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "54", "critical": "0",
                        "ability": "Holy Wrath", "damage_source": "spell",
                    })
                    rows.append(row)
        changed = dict(rows[0])
        changed["M"] = "1200"
        rows.append(changed)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        self.assertEqual(analysis["contaminated_fights_excluded"], 1)
        self.assertEqual(analysis["status"], "insufficient_data")
        self.assertEqual(analysis["comparisons"], [])


    def test_luck_uses_all_hits_so_critical_frequency_is_included(self):
        rows = []
        for prefix, luck, critical_positions in (
            ("base", 100, {8, 9}),
            ("test", 200, {7, 8, 9}),
        ):
            for fight_number in range(1, 4):
                fight = f"{prefix}{fight_number}"
                for event_index in range(10):
                    is_critical = event_index in critical_positions
                    amount = 2000 if is_critical else 1000
                    row = event("damage", fight, event_index, 500, amount)
                    row.update({
                        "profile": "pve",
                        "M": "500", "R": "200", "U": "300", "L": str(luck),
                        "S": "500", "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "54", "critical": "1" if is_critical else "0",
                        "ability": "Holy Wrath", "damage_source": "spell",
                        "element": "light", "target_max_hp": "1000000",
                    })
                    rows.append(row)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        luck = [item for item in analysis["comparisons"] if item["stat"] == "luck"]
        self.assertEqual(len(luck), 1)
        self.assertEqual(luck[0]["critical_scope"], "all_hits")
        self.assertIsNone(luck[0]["critical"])
        self.assertEqual(luck[0]["baseline"]["events"], 30)
        self.assertEqual(luck[0]["test"]["events"], 30)
        self.assertEqual(luck[0]["marginal_efficiency_per_100"], 100.0)
        self.assertEqual(luck[0]["baseline"]["mean_event_amount"], 1200.0)
        self.assertEqual(luck[0]["test"]["mean_event_amount"], 1300.0)



    def test_stale_stat_snapshots_are_excluded_from_controlled_analysis(self):
        rows = []
        for prefix, mastery, amount in (("base", 1000, 1000), ("test", 1100, 1050)):
            for fight_number in range(1, 4):
                for repeat in range(5):
                    row = event("damage", f"{prefix}{fight_number}", 5 + repeat % 3, mastery, amount)
                    row["stat_sample_age"] = "6"
                    rows.append(row)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        self.assertEqual(analysis["status"], "insufficient_data")
        self.assertEqual(analysis["comparisons"], [])
        self.assertEqual(analysis["excluded_or_unusable"]["stat_snapshot_stale"], 30)



    def test_different_target_ids_are_not_matched(self):
        rows = []
        for prefix, mastery, target in (("base", 1000, "boss-a"), ("test", 1100, "boss-b")):
            for fight_number in range(1, 4):
                for repeat in range(5):
                    row = event("damage", f"{prefix}{fight_number}", 5 + repeat % 3, mastery, 1000)
                    row.update({
                        "profile": "pve", "R": "200", "U": "300", "L": "400",
                        "S": "500", "W": "600", "B": "700", "C": "800",
                        "target_hp_before": "70", "hp_quality": "measured_pre",
                        "resolve_pool": "54", "critical": "0",
                        "ability": "Holy Wrath", "damage_source": "spell",
                        "target_id": target, "actor_id": "player-1",
                    })
                    rows.append(row)
        analysis = importer.analyze_controlled_stat_efficiency(rows)
        self.assertEqual(analysis["status"], "insufficient_data")
        self.assertEqual(analysis["comparisons"], [])



if __name__ == "__main__":
    unittest.main()
