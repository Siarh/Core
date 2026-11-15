#!/usr/bin/env python3
import json
import unittest
from unittest.mock import patch

import aou_ai_assistant as ai


class FakeResponse:
    def __init__(self, payload):
        self.payload = json.dumps(payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self.payload


class AIAssistantTests(unittest.TestCase):
    def test_default_model_is_qwen_27b(self):
        self.assertEqual(ai.DEFAULT_MODEL, "qwen3.5:27b")

    def test_russian_school_locale_files_are_utf8(self):
        for name in ("OptSchA.txt", "OptSchE.txt", "OptSchN.txt", "OptSchL.txt"):
            path = __import__("pathlib").Path("../Locales/rus") / name
            raw = path.read_bytes()
            self.assertFalse(raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"), name)
            self.assertNotIn(b"\x00", raw, name)
            text = raw.decode("utf-8")
            self.assertTrue(text.strip(), name)



    def test_compact_payload_omits_raw_event_details(self):
        profile = {
            "settings": {"mode": "mixed", "resolve_coefficient": 0.015, "freeze_resolve_pool": True},
            "stats": {"mastery": 100, "resolve": 200, "ruthlessness": 300, "luck": 40},
            "activities": {
                "raid_fight_1_dps": {
                    "mode": "dps",
                    "samples": [
                        {"raw": 1000, "target_hp": 0.5, "resolve_pool": 50, "ability": "Secret spell", "attacker_id": 12345},
                        {"raw": 2000, "target_hp": 0.4, "resolve_pool": 60, "ability": "Other spell"},
                    ],
                }
            },
            "import_warnings": ["HP values partly estimated"],
            "target_statistics": {
                "status": "calculated", "classification": "DERIVED",
                "target_profiles": 2, "unmatched_target_events": 1,
                "unmatched_target_instances": 1,
                "target_signature_fields": ["normalized_name", "level", "quality", "unit_kind"],
                "limitations": ["Archetype is not full state identity"],
                "targets": [
                    {
                        "target_signature": "[\"training creature\",90,4,\"mob\"]",
                        "target_name": "Training Creature", "target_level": 90,
                        "target_quality": 4, "target_quality_name": "BOSS",
                        "target_kind": "mob", "events": 25, "fights": 3, "instances": 3,
                        "hp": {"pre_event_average_percent": 47.5, "pre_event_measured": 20,
                               "pre_event_estimated": 5, "current_hp_snapshot_average": 50000},
                        "resistance_components": {"classification": "MEASURED_CALLBACK_COMPONENTS",
                            "resist_amount": 12000, "resist_known_events": 20,
                            "rune_absorb_amount": 3000, "note": "Callback components only"},
                        "identity_note": "Archetype only",
                    },
                    {
                        "target_signature": "[\"player name\",90,0,\"player\"]",
                        "target_name": "Private Player Name", "target_level": 90,
                        "target_quality": 0, "target_quality_name": "COMMON",
                        "target_kind": "player", "events": 4, "fights": 1, "instances": 1,
                        "hp": {"pre_event_average_percent": 66.0},
                        "resistance_components": {"classification": "UNAVAILABLE"},
                        "identity_note": "Archetype only",
                    },
                ],
            },
            "event_effectiveness": {
                "status": "calculated",
                "classification": "ESTIMATED",
                "fights": [{
                    "kind": "healing", "reported_amount": 1000,
                    "estimated_effective_amount": 700,
                    "estimated_excess_amount": 300,
                    "excess_label": "overheal_estimated",
                    "hp_coverage_percent": 80
                }]
            },
            "critical_analysis": {
                "status": "calculated",
                "classification": "DERIVED",
                "groups": [{
                    "ability": "Holy Wrath", "normal_events": 2, "critical_events": 3,
                    "observed_critical_rate_percent": 60,
                    "observed_critical_amount_share_percent": 81.8,
                    "observed_critical_to_normal_average_ratio": 3.0,
                    "causal_status": "descriptive_only"
                }]
            },
            "temporal_performance": {
                "status": "calculated",
                "classification": "DERIVED",
                "method": "zero-filled rolling windows",
                "burst_windows_seconds": [1, 3, 5, 10, 15, 30],
                "sustained_windows_seconds": [30, 60, 120, 180, 300],
                "fights": [{
                    "fight_id": "fight-1", "kind": "damage",
                    "duration_seconds_estimate": 60,
                    "burst_windows": {"3s": {"mean_rate_per_second": 500}},
                    "sustained_windows": {"60s": {"mean_rate_per_second": 200}},
                    "resolve_sample_summary": {
                        "mean_sampled_pool": 50, "peak_sampled_pool": 90,
                        "sampled_second_share_above": {"50": 0.5}
                    }
                }]
            },
            "controlled_stat_efficiency": {
                "status": "comparisons_available",
                "method": "matched contexts",
                "outcome_unit": "observed damage per event",
                "minimum_fights_per_build": 3,
                "included_events": 100,
                "excluded_or_unusable": {},
                "contaminated_fights_excluded": 1,
                "insufficient_repeated_pairs": 2,
                "limitations": ["Target ID not recorded"],
                "comparisons": [{
                    "classification": "DERIVED",
                    "causal_status": "not_proven",
                    "mode": "damage", "profile": "pve",
                    "duration_band": "30-60 sec", "ability": "Test",
                    "element": "light", "target_hp_band": "60-80%",
                    "target_hp_quality": "measured_pre", "resolve_pool_band": "50-60%",
                    "critical": True, "critical_scope": "normal_only",
                    "evidence_tier": "strict", "identity_quality": "measured_instance_ids",
                    "snapshot_quality": "fresh",
                    "actor_signature": "[\"private player name\",90,0,\"player\"]",
                    "target_signature": "[\"private target name\",90,0,\"player\"]",
                    "actor_name": "Private Player Name", "actor_kind": "player",
                    "target_name": "Private Target Name", "target_kind": "player",
                    "stat": "mastery", "from": 500, "to": 600,
                    "delta_stat": 100, "delta_result": 25, "result_unit": "reported_amount_per_second",
                    "me_formula": "ME = (Result_test - Result_base) / (Stat_test - Stat_base)",
                    "marginal_efficiency_per_stat": 0.25,
                    "marginal_efficiency_unit_per_stat": "reported amount/s per +1 stat",
                    "marginal_efficiency_unit_per_100": "reported amount/s per +100 stat",
                    "result_direction": "maximize", "beneficial_effect_per_100": 25,
                    "baseline": {"fights": 3, "events": 30},
                    "test": {"fights": 3, "events": 30},
                    "marginal_efficiency_per_100": 25,
                    "relative_change_per_100_percent": 2.5,
                    "confidence_interval_95_per_100": [10, 40], "confidence": "MEDIUM"
                }]
            }
        }
        report = {
            "character": {"crit_chance_percent": 12.0, "max_hp_model": 50000},
            "assumptions": {"resolve_pool_replay": "fixed"},
            "activities": {
                "raid_fight_1_dps": {
                    "simulation": {"events": 2, "total_damage": 3000, "per_second_damage": 1500},
                    "recommendation": {"status": "calculated", "added_points": {"mastery": 2}},
                    "model_marginal_efficiency": {
                        "status": "partial_estimates",
                        "classification": "ESTIMATED",
                        "metric": "total_damage",
                        "metric_per_second": True,
                        "baseline_model_result": 1500,
                        "event_count": 2,
                        "duration_seconds": 2,
                        "method": "finite differences",
                        "resolve_policy": "fixed observed pool",
                        "critical_policy": "expected Luck x2 baseline",
                        "unavailable_stats": {"ruthlessness": "target HP incomplete"},
                        "confidence_interval": None,
                        "note": "Formula estimate only",
                        "curves": {"mastery": {"classification": "ESTIMATED", "points": [
                            {"stat_value": 100, "marginal_efficiency_per_100": 150}
                        ]}},
                        "interactions": [{"classification": "ESTIMATED", "first_stat": "mastery",
                                          "second_stat": "luck", "interaction_effect": 5,
                                          "direction": "synergy"}]
                    }
                }
            },
            "warnings": ["Small sample"],
            "cross_activity_recommendations": {"dps": {"estimated_gain_percent": 2.5}},
        }
        payload = ai.build_ai_payload(profile, report)
        rendered = str(payload)
        self.assertEqual(payload["activities"]["raid_fight_1_dps"]["sample_count"], 2)
        self.assertNotIn("Secret spell", rendered)
        self.assertNotIn("attacker_id", rendered)
        self.assertNotIn("actor_id", rendered)
        self.assertNotIn("target_id", rendered)
        self.assertNotIn("12345", rendered)
        self.assertNotIn("Private Player Name", rendered)
        self.assertNotIn("Private Target Name", rendered)
        self.assertNotIn("private player name", rendered)
        self.assertNotIn("private target name", rendered)
        target_stats = payload["target_statistics"]
        self.assertEqual(target_stats["target_profiles"], 2)
        self.assertEqual(target_stats["target_profiles_in_ai_payload"], 2)
        self.assertEqual(target_stats["targets"][0]["target_quality_name"], "BOSS")
        self.assertEqual(target_stats["targets"][0]["hp"]["pre_event_average_percent"], 47.5)
        self.assertEqual(target_stats["targets"][0]["resistance_components"]["resist_amount"], 12000)
        self.assertEqual(target_stats["targets"][1]["target_name"], "player target")
        self.assertNotIn("target_signature", target_stats["targets"][0])
        self.assertIn("Small sample", rendered)
        self.assertIn("estimated_gain_percent", rendered)
        model = payload["activities"]["raid_fight_1_dps"]["model_marginal_efficiency"]
        self.assertEqual(model["classification"], "ESTIMATED")
        self.assertEqual(model["curves"]["mastery"]["points"][0]["marginal_efficiency_per_100"], 150)
        self.assertEqual(model["interactions"][0]["direction"], "synergy")
        self.assertNotIn("raw", model)
        self.assertEqual(payload["controlled_stat_efficiency"]["status"], "comparisons_available")
        self.assertEqual(payload["controlled_stat_efficiency"]["comparisons"][0]["marginal_efficiency_per_100"], 25)
        comparison = payload["controlled_stat_efficiency"]["comparisons"][0]
        self.assertEqual(comparison["delta_result"], 25)
        self.assertEqual(comparison["delta_stat"], 100)
        self.assertEqual(comparison["marginal_efficiency_per_stat"], 0.25)
        self.assertEqual(comparison["me_formula"], "ME = (Result_test - Result_base) / (Stat_test - Stat_base)")
        self.assertEqual(payload["controlled_stat_efficiency"]["comparisons_included_in_ai_payload"], 1)
        temporal = payload["temporal_performance"]
        self.assertEqual(temporal["classification"], "DERIVED")
        self.assertEqual(temporal["fights"][0]["burst_windows"]["3s"]["mean_rate_per_second"], 500)
        self.assertEqual(temporal["fights"][0]["resolve_sample_summary"]["mean_sampled_pool"], 50)
        effectiveness = payload["event_effectiveness"]
        self.assertEqual(effectiveness["classification"], "ESTIMATED")
        self.assertEqual(effectiveness["fights"][0]["excess_label"], "overheal_estimated")
        critical = payload["critical_analysis"]
        self.assertEqual(critical["classification"], "DERIVED")
        self.assertEqual(critical["groups"][0]["observed_critical_rate_percent"], 60)
        self.assertNotIn("not_selected", rendered)

    def test_compact_payload_keeps_heal_recipient_split(self):
        profile = {
            "activities": {
                "heal_fight_2_hps": {
                    "mode": "hps",
                    "samples": [{"target_hp": 0.4, "resolve_pool": 20, "recipient": "self"}],
                }
            }
        }
        report = {
            "activities": {
                "heal_fight_2_hps": {
                    "simulation": {"events": 1, "effective_heal_coverage_percent": 100},
                    "recommendation": {"status": "calculated"},
                    "recipient_segments": {
                        "self": {"simulation": {"events": 1}, "recommendation": {"status": "calculated"}},
                        "ally": {"simulation": {"events": 0}, "recommendation": {"status": "insufficient_data"}},
                    },
                }
            }
        }
        payload = ai.build_ai_payload(profile, report)
        segments = payload["activities"]["heal_fight_2_hps"]["recipient_segments"]
        self.assertIn("self", segments)
        self.assertIn("ally", segments)

    def test_system_instructions_forbid_invented_formulas(self):
        self.assertIn("Не пересчитывай формулы", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("Не выдумывай", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("model_marginal_efficiency", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("ESTIMATED", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("не являются измеренным игровым эффектом", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("controlled_stat_efficiency", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("ME = ΔResult / ΔStat", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("Не ограничивайся первыми 25", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("legacy_exploratory", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("не доказывает причинность", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("не реальный временной uptime", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("Effective DPS/HPS", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("overheal", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("target_hp_after", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("критический множитель", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("target_statistics", ai.SYSTEM_INSTRUCTIONS)
        self.assertIn("не числовой рейтинг сопротивления", ai.SYSTEM_INSTRUCTIONS)


    def test_normalizes_ollama_host_variants(self):
        self.assertEqual(ai.normalize_ollama_url("localhost:11434/"), "http://localhost:11434")
        self.assertEqual(ai.normalize_ollama_url("http://localhost:11434/api"), "http://localhost:11434")

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_calls_local_ollama_chat_without_api_key(self, urlopen):
        urlopen.return_value = FakeResponse({"message": {"content": "Анализ готов"}})
        result = ai.call_ollama({"activities": {}}, "qwen3.5", "localhost:11434", timeout=42)
        self.assertEqual(result, "Анализ готов")
        request = urlopen.call_args.args[0]
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(request.full_url, "http://localhost:11434/api/chat")
        self.assertEqual(body["model"], "qwen3.5")
        self.assertFalse(body["stream"])
        self.assertEqual(body["messages"][0]["role"], "system")
        self.assertEqual(body["messages"][1]["role"], "user")
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 42)

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_check_accepts_latest_alias(self, urlopen):
        urlopen.return_value = FakeResponse({"models": [{"name": "qwen3.5:latest"}]})
        selected = ai.check_ollama("http://localhost:11434", "qwen3.5")
        self.assertEqual(selected, "qwen3.5:latest")

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_generic_qwen_selects_9b_when_multiple_variants_are_installed(self, urlopen):
        urlopen.return_value = FakeResponse({
            "models": [{"name": "qwen3.5:27b"}, {"name": "qwen3.5:9b"}]
        })
        selected = ai.check_ollama("http://localhost:11434", "qwen3.5")
        self.assertEqual(selected, "qwen3.5:9b")

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_generic_qwen_falls_back_to_only_installed_variant(self, urlopen):
        urlopen.return_value = FakeResponse({"models": [{"name": "qwen3.5:27b"}]})
        selected = ai.check_ollama("http://localhost:11434", "qwen3.5")
        self.assertEqual(selected, "qwen3.5:27b")

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_explicit_qwen_variant_is_respected(self, urlopen):
        urlopen.return_value = FakeResponse({
            "models": [{"name": "qwen3.5:9b"}, {"name": "qwen3.5:27b"}]
        })
        selected = ai.check_ollama("http://localhost:11434", "qwen3.5:27b")
        self.assertEqual(selected, "qwen3.5:27b")

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_check_rejects_missing_model_with_help(self, urlopen):
        urlopen.return_value = FakeResponse({"models": [{"name": "llama3.2:latest"}]})
        with self.assertRaisesRegex(RuntimeError, "Укажи точное имя"):
            ai.check_ollama("http://localhost:11434", "qwen3.5")


    def test_ai_payload_includes_every_me_comparison_and_separates_legacy(self):
        comparisons = []
        for index in range(30):
            tier = "strict" if index < 15 else "legacy_exploratory"
            me = float(index - 10)
            comparisons.append({
                "classification": "DERIVED",
                "causal_status": "not_proven",
                "evidence_tier": tier,
                "identity_quality": "measured_instance_ids" if tier == "strict" else "legacy_identity_unverified",
                "snapshot_quality": "fresh" if tier == "strict" else "legacy_age_unverified",
                "mode": "damage",
                "profile": "pve",
                "duration_band": "30-60 sec",
                "ability": f"Ability {index}",
                "target_hp_band": "60-80%",
                "resolve_pool_band": "50-60%",
                "critical_scope": "all_hits",
                "stat": "mastery",
                "from": 500,
                "to": 600,
                "delta_stat": 100,
                "delta_result": me,
                "me_formula": "ME = (Result_test - Result_base) / (Stat_test - Stat_base)",
                "marginal_efficiency_per_stat": me / 100,
                "marginal_efficiency_per_100": me,
                "marginal_efficiency_unit_per_100": "reported amount/s per +100 stat",
                "result_direction": "maximize",
                "baseline": {"fights": 3, "events": 15, "mean_context_rate_per_second": 100},
                "test": {"fights": 3, "events": 15, "mean_context_rate_per_second": 100 + me},
                "confidence_interval_95_per_100": [me - 1, me + 1],
                "confidence": "VERY_LOW" if tier != "strict" else "MEDIUM",
            })

        profile = {
            "import_summary": {
                "export_records_expected": 1000,
                "export_records_reconstructed": 1000,
                "export_record_count_matches": True,
                "source_rows": 1000,
                "combat_rows": 1000,
                "ignored_non_combat_rows": 0,
                "included_events": 900,
                "skipped_events": {},
            },
            "controlled_stat_efficiency": {
                "status": "comparisons_available",
                "input_event_rows": 1000,
                "validated_event_rows_before_contamination": 1000,
                "strict_valid_event_rows": 300,
                "legacy_exploratory_event_rows": 600,
                "contaminated_event_rows_excluded": 100,
                "included_events": 900,
                "total_comparisons": 30,
                "strict_comparison_count": 15,
                "legacy_exploratory_comparison_count": 15,
                "comparisons": comparisons,
            },
        }
        payload = ai.build_ai_payload(profile, {})
        me_data = payload["controlled_stat_efficiency"]
        self.assertEqual(payload["input_data_coverage"]["export_records_reconstructed"], 1000)
        self.assertEqual(me_data["input_event_rows"], 1000)
        self.assertEqual(me_data["strict_valid_event_rows"], 300)
        self.assertEqual(me_data["legacy_exploratory_event_rows"], 600)
        self.assertEqual(me_data["contaminated_event_rows_excluded"], 100)
        self.assertEqual(me_data["total_comparisons"], 30)
        self.assertEqual(me_data["comparisons_included_in_ai_payload"], 30)
        self.assertEqual(len(me_data["comparisons"]), 30)
        self.assertEqual(me_data["strict_comparison_count"], 15)
        self.assertEqual(me_data["legacy_exploratory_comparison_count"], 15)
        self.assertEqual(len(me_data["me_summary_by_stat"]), 2)
        strict = next(row for row in me_data["me_summary_by_stat"] if row["evidence_tier"] == "strict")
        legacy = next(row for row in me_data["me_summary_by_stat"] if row["evidence_tier"] == "legacy_exploratory")
        self.assertEqual(strict["context_comparison_count"], 15)
        self.assertEqual(legacy["context_comparison_count"], 15)
        self.assertEqual(me_data["comparisons"][0]["evidence_tier"], "strict")



if __name__ == "__main__":
    unittest.main()
