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
        }
        report = {
            "character": {"crit_chance_percent": 12.0, "max_hp_model": 50000},
            "assumptions": {"resolve_pool_replay": "fixed"},
            "activities": {
                "raid_fight_1_dps": {
                    "simulation": {"events": 2, "total_damage": 3000, "per_second_damage": 1500},
                    "recommendation": {"status": "calculated", "added_points": {"mastery": 2}},
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
        self.assertNotIn("12345", rendered)
        self.assertIn("Small sample", rendered)
        self.assertIn("estimated_gain_percent", rendered)

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
        models = ai.check_ollama("http://localhost:11434", "qwen3.5")
        self.assertIn("qwen3.5:latest", models)

    @patch("aou_ai_assistant.urllib.request.urlopen")
    def test_check_rejects_missing_model_with_help(self, urlopen):
        urlopen.return_value = FakeResponse({"models": [{"name": "llama3.2:latest"}]})
        with self.assertRaisesRegex(RuntimeError, "ollama pull qwen3.5"):
            ai.check_ollama("http://localhost:11434", "qwen3.5")


if __name__ == "__main__":
    unittest.main()
