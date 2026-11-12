import math
import unittest

import aou_formula_calculator as calc
import aou_analyze


class FormulaTests(unittest.TestCase):
    def test_saved_record_analyzer_resolve_default_matches_formula_engine(self):
        record = {"M": 0, "R": 1000, "U": 0, "L": 0, "pool": 10, "thp": 100}
        self.assertAlmostEqual(aou_analyze.model(record), 1.015)
        self.assertAlmostEqual(aou_analyze.model(record, 0.015), 1.15)

    def test_mastery_positive_and_negative(self):
        self.assertAlmostEqual(calc.mastery_multiplier(1000), 2.0)
        self.assertAlmostEqual(calc.mastery_multiplier(-500), 2 / 3)

    def test_resolve_coefficient_ambiguity_is_explicit(self):
        self.assertAlmostEqual(calc.resolve_multiplier(1000, 10, 0.0015), 1.015)
        self.assertAlmostEqual(calc.resolve_multiplier(1000, 10, 0.015), 1.15)

    def test_resolve_k_boundaries(self):
        self.assertEqual([calc.resolve_k(x) for x in (0, 50, 60, 70, 80)], [0.35, 0.30, 0.18, 0.15, 0.10])

    def test_resolve_gain_divides_by_multiplier(self):
        self.assertEqual(calc.resolve_gain(200, 1000, 2, 0), 15)

    def test_resolve_decay(self):
        self.assertEqual(calc.resolve_decay(99), 89)

    def test_ruthlessness_equation_and_full_hp(self):
        m = calc.ruthlessness_m(1000)
        self.assertAlmostEqual(m / math.log1p(m), 2.0, places=9)
        self.assertEqual(calc.ruthlessness_multiplier(1000, 1.0), 1.0)
        self.assertGreater(calc.ruthlessness_multiplier(1000, 0.0), 1.0)

    def test_softened_stat_cap_and_crit(self):
        self.assertEqual(calc.softened_stat(900), calc.softened_stat(850))
        self.assertAlmostEqual(calc.crit_chance(160), 0.16)

    def test_bloodthirst_return_and_heal_third(self):
        share = calc.bloodthirst_fraction(1800)
        self.assertAlmostEqual(share, 0.5)
        dps = calc.calculate_event({"raw": 1000}, "dps", {"bloodthirst": 1800}, {"level": 1}, 0)
        hps = calc.calculate_event({"raw": 1000}, "hps", {"bloodthirst": 1800}, {"level": 1}, 0)
        self.assertAlmostEqual(dps["bloodthirst_return"], 500)
        self.assertAlmostEqual(hps["bloodthirst_return"], 1000 / 6)

    def test_caution_only_below_40_percent_and_caps(self):
        self.assertEqual(calc.caution_multiplier(350, 0.4), 1.0)
        self.assertAlmostEqual(calc.caution_multiplier(500, 0.39), 0.65)

    def test_resistance_formula(self):
        self.assertEqual(calc.resistance_multiplier(20), 0.5)
        with self.assertRaises(ValueError):
            calc.resistance_multiplier(0)

    def test_endurance_and_fortitude_health(self):
        self.assertAlmostEqual(calc.endurance_health(1, 16.2, 1000, 100), 8910)

    def test_will_reference_values(self):
        expected = {170: 7, 227: 6, 316: 5, 467: 4, 733: 3, 1177: 2}
        for stat, seconds in expected.items():
            self.assertEqual(calc.will_result(stat)["seconds_to_immunity"], seconds)

    def test_healing_effective_and_overheal(self):
        event = {"raw": 50000, "target_hp": 0.6, "target_max_hp": 100000}
        out = calc.calculate_event(event, "hps", {}, {"level": 1, "might_affects_healing": False}, 0)
        self.assertEqual(out["effective"], 40000)
        self.assertEqual(out["overheal"], 10000)

    def test_healing_unknown_without_hp_evidence(self):
        out = calc.calculate_event({"raw": 1000}, "hps", {}, {"level": 1}, 0)
        self.assertIsNone(out["effective"])
        sim = calc.simulate({"mode": "hps", "samples": [{"second": 0, "raw": 1000}]}, {}, {"level": 1})
        self.assertIsNone(sim["effective_heal_total"])
        self.assertEqual(sim["effective_heal_events"], 0)

    def test_rune_absorption_is_separate(self):
        out = calc.calculate_event({"raw": 1000, "rune_absorb_fraction": 0.25}, "dps", {}, {"level": 1}, 0)
        self.assertEqual(out["rune_absorbed"], 250)
        self.assertEqual(out["nominal"], 750)

    def test_ruthlessness_is_applied_after_absolute_rune_absorption(self):
        stats = {"ruthlessness": 1000}
        event = {"raw": 1000, "target_hp": 0.0, "rune_absorbed": 100}
        out = calc.calculate_event(event, "dps", stats, {"level": 1}, 0)
        expected = 900 * calc.ruthlessness_multiplier(1000, 0.0)
        self.assertAlmostEqual(out["nominal"], expected)
        self.assertEqual(out["rune_absorbed"], 100)

    def test_fury_only_applies_to_player_in_combat(self):
        stats = {"fury": 100}
        yes = calc.calculate_event({"raw": 1000, "target_is_player": True, "in_combat": True}, "dps", stats, {"level": 1}, 0)
        no = calc.calculate_event({"raw": 1000, "target_is_player": False}, "dps", stats, {"level": 1}, 0)
        self.assertGreater(yes["fury_healing_absorption"], 0)
        self.assertEqual(no["fury_healing_absorption"], 0)

    def test_tank_uses_school_resistance_and_caution(self):
        event = {"second": 0, "incoming_raw": 1000, "damage_school": "physical", "player_hp": 0.3}
        stats = {"armor": 20, "caution": 100}
        out = calc.calculate_incoming(event, stats, {"level": 1})
        self.assertAlmostEqual(out["incoming_after_defense"], 450)

    def test_optimizer_refuses_unknown_effective_hps(self):
        activity = {"mode": "hps", "samples": [{"second": 0, "raw": 1000}]}
        out = calc.optimize(activity, {"mastery": 100}, 5, {"level": 1})
        self.assertEqual(out["status"], "insufficient_data")

    def test_dps_optimizer_respects_budget(self):
        activity = {"mode": "dps", "samples": [{"second": 0, "raw": 1000, "critical": False, "target_hp": 0.5}]}
        out = calc.optimize(activity, {"mastery": 100, "resolve": 100, "ruthlessness": 100, "luck": 0}, 5,
                            {"level": 1, "max_hp": 100000, "resolve_coefficient": 0.0015})
        self.assertEqual(sum(out["added_points"].values()), 5)
        self.assertEqual(out["status"], "calculated")

    def test_tank_optimizer_uses_available_budget(self):
        activity = {"mode": "tank", "samples": [
            {"second": 0, "incoming_raw": 100000, "damage_school": "physical", "player_hp": 0.3, "outgoing_damage": 10000},
            {"second": 1, "incoming_raw": 90000, "damage_school": "fire", "player_hp": 0.6, "outgoing_damage": 12000},
        ]}
        stats = {"fortitude": 100, "endurance": 1000, "bloodthirst": 100, "caution": 100,
                 "resistances": {"armor": 10, "elements": 10, "divine": 10, "nature": 10}}
        cfg = {"level": 1, "max_hp": 1000000, "base_stats": {"fortitude": 100, "endurance": 1000}}
        out = calc.optimize(activity, stats, 4, cfg)
        self.assertEqual(sum(out["added_points"].values()), 4)
        self.assertEqual(out["status"], "calculated")

    def test_tank_will_only_allocated_with_explicit_control_weight_in_pvp(self):
        keys = calc._optimizable_stats("tank", {"mode": "pvp"})
        self.assertNotIn("will", keys)
        keys = calc._optimizable_stats("tank", {"mode": "pvp", "control_weight": 1.0})
        self.assertIn("will", keys)

    def test_counterfactual_optimizer_uses_expected_crit_not_recorded_crit_flag(self):
        event = {"raw": 1000, "critical": False}
        stats = {"luck": 100}
        actual = calc.calculate_event(event, "dps", stats, {"level": 1}, 0)
        expected = calc.calculate_event(event, "dps", stats, {"level": 1}, 0, expected_crit=True)
        self.assertEqual(actual["crit_multiplier"], 1.0)
        self.assertAlmostEqual(expected["crit_multiplier"], 1.1)

    def test_phase_breakdown_and_half_battle_stability(self):
        activity = {"mode": "dps", "samples": [
            {"second": 0, "raw": 100, "target_hp": 0.9},
            {"second": 1, "raw": 200, "target_hp": 0.6},
            {"second": 2, "raw": 300, "target_hp": 0.3},
            {"second": 3, "raw": 400, "target_hp": 0.1},
        ]}
        result = calc.simulate(activity, {}, {"level": 1})
        self.assertEqual(result["hp_phase_breakdown"]["100-75%"]["amount"], 100)
        self.assertEqual(result["hp_phase_breakdown"]["75-50%"]["amount"], 200)
        self.assertEqual(result["hp_phase_breakdown"]["50-25%"]["amount"], 300)
        self.assertEqual(result["hp_phase_breakdown"]["25-0%"]["amount"], 400)
        self.assertEqual(result["half_battle_stability"]["first_half_per_second"], 150)
        self.assertEqual(result["half_battle_stability"]["second_half_per_second"], 350)

    def test_hps_direct_absolute_effective_heal_not_reused_for_stat_optimization(self):
        activity = {"mode": "hps", "samples": [{"second": 0, "raw": 1000, "effective_heal": 700}]}
        result = calc.simulate(activity, {}, {"level": 1})
        self.assertEqual(result["effective_heal_total"], 700)
        self.assertEqual(result["effective_heal_optimization_events"], 0)
        opt = calc.optimize(activity, {"mastery": 100}, 3, {"level": 1})
        self.assertEqual(opt["status"], "insufficient_data")

    def test_hps_effective_heal_ratio_scales_with_candidate_heal(self):
        event = {"raw": 1000, "effective_heal": 500, "observed_nominal": 1000}
        baseline = calc.calculate_event(event, "hps", {}, {"level": 1}, 0)
        stronger = calc.calculate_event(event, "hps", {"mastery": 1000}, {"level": 1}, 0)
        self.assertEqual(baseline["effective"], 500)
        self.assertEqual(stronger["effective"], 1000)

    def test_tank_school_breakdown_preserves_resistance_families(self):
        activity = {"mode": "tank", "samples": [
            {"second": 0, "incoming_raw": 1000, "damage_school": "physical"},
            {"second": 1, "incoming_raw": 1000, "damage_school": "fire"},
        ]}
        stats = {"resistances": {"armor": 20, "elements": 10, "divine": 10, "nature": 10}}
        result = calc.simulate(activity, stats, {"level": 1, "max_hp": 100000})
        self.assertEqual(result["incoming_by_school"]["armor"]["resistance_reduction"], 500)
        self.assertEqual(result["incoming_by_school"]["elements"]["resistance_reduction"], 0)

    def test_resolve_pool_resets_on_death_marker(self):
        activity = {"mode": "dps", "samples": [
            {"second": 0, "raw": 10000, "target_hp": 0.5, "player_died": True}
        ]}
        result = calc.simulate(activity, {"resolve": 1000}, {"level": 1, "max_hp": 100000, "initial_resolve": 80})
        self.assertEqual(result["resolve_final"], 0)


if __name__ == "__main__":
    unittest.main()
