#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import unittest

import aou_event_history_to_profile as importer


def event(kind, fight, second, mastery, amount):
    return {
        "kind": kind, "fight_id": fight, "profile": "DPS", "second": str(second),
        "M": str(mastery), "R": "0", "U": "0", "L": "0",
        "observed_amount": str(amount), "target_hp_before": "100",
        "hp_quality": "measured_pre", "resolve_pool": "50", "critical": "0",
        "runes_absorb": "0", "ability": "Test", "element": "physical",
        "recipient": "self", "target_max_hp": "100000",
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
        self.assertEqual(len(comparison["groups"]), 2)
        low = next(group for group in comparison["groups"] if group["stats"]["mastery"] == 445.1)
        self.assertEqual(low["observed_damage"], 1000)
        self.assertEqual(low["observed_healing"], 500)
        self.assertEqual(low["healing_by_recipient"]["self"]["amount"], 500)
        self.assertEqual(low["observed_dps_estimate"], 500)

    def test_profile_build_accepts_multiple_mastery_snapshots(self):
        rows = [event("damage", "f1", 1, 445.1, 1000), event("damage", "f2", 1, 595.1, 1200)]
        profile = importer.build_profile(rows, 20, 0.015)
        self.assertEqual(profile["import_summary"]["included_events"], 2)
        self.assertEqual(len(profile["stat_comparison"]["groups"]), 2)
        self.assertTrue(any("характеристики менялись" in warning.lower()
                            for warning in profile["import_warnings"]))


if __name__ == "__main__":
    unittest.main()
