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



    def test_burst_sustained_and_resolve_sample_windows(self):
        rows = []
        for second in range(40):
            amount = 100 if second in {10, 11, 12} else 10
            row = event("damage", "burst-fight", second, 1000, amount)
            row.update({
                "profile": "pve",
                "resolve_pool": str(second * 2.5),
                "target_id": "boss-1",
                "actor_id": "player-1",
            })
            rows.append(row)

        temporal = importer.build_temporal_performance(rows)
        self.assertEqual(temporal["status"], "calculated")
        self.assertEqual(temporal["burst_windows_seconds"], [1, 3, 5, 10, 15, 30])
        self.assertEqual(temporal["sustained_windows_seconds"], [30, 60, 120, 180, 300])
        fight = temporal["fights"][0]
        self.assertEqual(fight["duration_seconds_estimate"], 40)
        self.assertEqual(fight["duration_band"], "30-60 sec")
        self.assertEqual(fight["target_count"], 1)
        self.assertEqual(fight["target_type"], "single_target")
        self.assertEqual(fight["burst_windows"]["3s"]["mean_rate_per_second"], 100.0)
        self.assertEqual(fight["sustained_windows"]["30s"]["mean_rate_per_second"], 19.0)
        self.assertEqual(fight["sustained_windows"]["60s"]["status"], "insufficient_duration")
        resolve = fight["resolve_sample_summary"]
        self.assertEqual(resolve["samples"], 40)
        self.assertEqual(resolve["mean_sampled_pool"], 48.75)
        self.assertEqual(resolve["peak_sampled_pool"], 97.5)
        self.assertEqual(resolve["sampled_second_share_above"]["50"], 0.5)
        self.assertIn("not time uptime", resolve["method"])



    def test_effective_damage_and_healing_are_separate_estimates(self):
        damage = event("damage", "fight-1", 4, 100, 300)
        damage.update({"target_hp_before": "10", "target_max_hp": "1000"})
        heal = event("healing", "fight-1", 4, 100, 300)
        heal.update({"target_hp_before": "80", "target_max_hp": "1000", "recipient": "self"})
        unknown = event("healing", "fight-1", 4, 100, 150)
        unknown.update({"target_hp_before": "", "hp_quality": "unknown", "target_max_hp": ""})

        report = importer.build_event_effectiveness([damage, heal, unknown])
        damage_row = next(item for item in report["fights"] if item["kind"] == "damage")
        heal_row = next(item for item in report["fights"] if item["kind"] == "healing")

        self.assertEqual(damage_row["reported_amount"], 300)
        self.assertEqual(damage_row["estimated_effective_amount"], 100)
        self.assertEqual(damage_row["estimated_excess_amount"], 200)
        self.assertEqual(damage_row["excess_label"], "overkill_estimated")
        self.assertEqual(heal_row["reported_amount"], 450)
        self.assertEqual(heal_row["estimated_effective_amount"], 200)
        self.assertEqual(heal_row["estimated_excess_amount"], 100)
        self.assertEqual(heal_row["hp_eligible_events"], 1)
        self.assertEqual(heal_row["unknown_hp_events"], 1)
        self.assertEqual(heal_row["excess_label"], "overheal_estimated")
        self.assertEqual(heal_row["classification"], "ESTIMATED")

    def test_critical_analysis_reports_observed_rate_share_and_ratio(self):
        rows = []
        for index, critical, amount in (
            (1, "0", 100), (2, "0", 100),
            (3, "1", 300), (4, "1", 300), (5, "1", 300)
        ):
            row = event("damage", "fight-1", index, 100, amount)
            row["critical"] = critical
            row["ability"] = "Holy Wrath"
            rows.append(row)
        report = importer.build_critical_analysis(rows)
        self.assertEqual(len(report["groups"]), 1)
        row = report["groups"][0]
        self.assertEqual(row["normal_events"], 2)
        self.assertEqual(row["critical_events"], 3)
        self.assertEqual(row["observed_critical_rate_percent"], 60.0)
        self.assertAlmostEqual(row["observed_critical_amount_share_percent"], 81.8182, places=3)
        self.assertEqual(row["normal_average_amount"], 100.0)
        self.assertEqual(row["critical_average_amount"], 300.0)
        self.assertEqual(row["observed_critical_to_normal_average_ratio"], 3.0)
        self.assertEqual(row["classification"], "DERIVED")
        self.assertIn("descriptive_only", row["causal_status"])



if __name__ == "__main__":
    unittest.main()
