#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Local Ollama-powered DPScope combat review.

This desktop companion is intentionally separate from the in-game Lua addon:
Allods' addon runtime has no confirmed outbound HTTP client. It sends only a
compact profile/calculator summary, not raw player IDs or the full event log.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


SYSTEM_INSTRUCTIONS = """Ты — аналитический помощник DPScope для Allods Online / Sunshine 6.0.
Работай строго по переданному JSON-отчёту и профилю боя.

Правила:
- Не пересчитывай формулы и не придумывай коэффициенты. Числа оптимизатора из отчёта считай результатом детерминированного калькулятора.
- Не выдавай оценочные HP, сопротивления или полезное лечение за измеренные.
- Не предлагай конкретное перераспределение очков, если в отчёте нет calculated/partial рекомендации для этой активности.
- Отдельно анализируй УВС (DPS), лечение себя, лечение союзников и защиту (TANK); не складывай разные режимы в одну метрику.
- Учитывай размер выборки, HP coverage, Resolve pool coverage и warnings. При низкой полноте данных предпочитай следующий тест, а не уверенный совет.
- Сравнивай активности только с оглядкой на их собственные условия; не объявляй победителем бой только из-за большего абсолютного урона.
- Не выдумывай игровые механики, способности, свойства класса или значения характеристик, которых нет во входных данных.
- Ясно разделяй: наблюдение, вывод, рекомендацию для теста, неопределённость.
- Отвечай на русском, компактно и конкретно. Не называй вероятный эффект доказанным.

Формат ответа:
1. Итог по профилю.
2. Что подтверждено данными.
3. Что выглядит перспективным (только при наличии рекомендации калькулятора).
4. Ограничения и риски.
5. Следующий контролируемый тест в игре.
"""


def _number(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _compact_activity(profile_activity: dict[str, Any], report_item: dict[str, Any]) -> dict[str, Any]:
    samples = profile_activity.get("samples", [])
    mode = str(profile_activity.get("mode", "unknown")).lower()
    hp_values = [_number(row.get("target_hp")) for row in samples if row.get("target_hp") is not None]
    pools = [_number(row.get("resolve_pool")) for row in samples if row.get("resolve_pool") is not None]
    hp_values = [value for value in hp_values if value is not None]
    pools = [value for value in pools if value is not None]

    simulation = report_item.get("simulation", {}) or {}
    recommendation = report_item.get("recommendation", {}) or {}
    compact_sim = {}
    for key in (
        "events", "seconds", "total_damage", "per_second_damage",
        "nominal_heal_total", "effective_heal_total", "effective_heal_events",
        "effective_heal_optimization_events", "effective_heal_coverage_percent",
        "per_second_effective_heal", "incoming_total_after_defense",
        "incoming_per_second", "bloodthirst_sustain_per_second",
        "net_incoming_per_second", "survival_seconds", "resolve_average_after_events",
        "resolve_final", "resolve_samples",
    ):
        if key in simulation:
            compact_sim[key] = simulation[key]
    compact_rec = {}
    for key in (
        "status", "objective", "added_points", "recommended_stats",
        "base_score", "recommended_score", "estimated_gain_percent", "method", "reason",
    ):
        if key in recommendation:
            compact_rec[key] = recommendation[key]

    recipient_segments = {}
    for recipient, segment in (report_item.get("recipient_segments", {}) or {}).items():
        segment_sim = segment.get("simulation", {}) or {}
        segment_rec = segment.get("recommendation", {}) or {}
        recipient_segments[recipient] = {
            "events": segment_sim.get("events"),
            "effective_heal_total": segment_sim.get("effective_heal_total"),
            "effective_heal_coverage_percent": segment_sim.get("effective_heal_coverage_percent"),
            "recommendation": {
                key: segment_rec[key] for key in (
                    "status", "objective", "added_points", "recommended_stats",
                    "estimated_gain_percent", "reason",
                ) if key in segment_rec
            },
        }

    result: dict[str, Any] = {
        "mode": mode,
        "weight": profile_activity.get("weight", 1.0),
        "sample_count": len(samples),
        "target_hp": {
            "samples": len(hp_values),
            "mean_fraction": (sum(hp_values) / len(hp_values)) if hp_values else None,
            "min_fraction": min(hp_values) if hp_values else None,
            "max_fraction": max(hp_values) if hp_values else None,
        },
        "resolve_pool": {
            "samples": len(pools),
            "mean": (sum(pools) / len(pools)) if pools else None,
            "min": min(pools) if pools else None,
            "max": max(pools) if pools else None,
        },
        "simulation": compact_sim,
        "recommendation": compact_rec,
    }
    if recipient_segments:
        result["recipient_segments"] = recipient_segments
    if simulation.get("warnings"):
        result["simulation_warnings"] = simulation["warnings"]
    return result


def build_ai_payload(profile: dict[str, Any], report: dict[str, Any]) -> dict[str, Any]:
    """Build a small, ID-free summary and omit raw event rows."""
    activities = {}
    profile_activities = profile.get("activities", {}) or {}
    report_activities = report.get("activities", {}) or {}
    for name, activity in profile_activities.items():
        activities[name] = _compact_activity(activity, report_activities.get(name, {}) or {})

    character = report.get("character", {}) or {}
    compact_character = {
        key: character[key]
        for key in ("crit_chance_percent", "ruthlessness_m", "bloodthirst_fraction", "max_hp_model")
        if key in character
    }
    payload = {
        "product": "DPScope",
        "game_version": "Allods Sunshine 6.0",
        "settings": {
            key: value for key, value in (profile.get("settings", {}) or {}).items()
            if key in ("mode", "resolve_coefficient", "freeze_resolve_pool", "max_hp", "level")
        },
        "current_stats": profile.get("stats", {}),
        "formula_assumptions": report.get("assumptions", {}),
        "character_summary": compact_character,
        "activities": activities,
        "cross_activity_recommendations": report.get("cross_activity_recommendations", {}),
        "import_summary": profile.get("import_summary", {}),
        "warnings": list(dict.fromkeys(
            list(profile.get("import_warnings", []) or []) +
            list(report.get("warnings", []) or [])
        )),
    }
    return payload


def normalize_ollama_url(value: str) -> str:
    """Normalize OLLAMA_HOST values such as localhost:11434 or /api URLs."""
    base = (value or "http://localhost:11434").strip().rstrip("/")
    if not base.startswith(("http://", "https://")):
        base = "http://" + base
    if base.endswith("/api"):
        base = base[:-4]
    return base


def _ollama_json(url: str, body: dict[str, Any] | None = None, timeout: int = 30) -> dict[str, Any]:
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url, data=data, headers=headers, method="POST" if data is not None else "GET"
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:2000]
        if exc.code == 404:
            raise RuntimeError(
                "Ollama вернул HTTP 404: модель или endpoint не найдены. "
                "Проверь имя модели через ollama list и при необходимости выполни "
                f"ollama pull. {detail}"
            ) from None
        raise RuntimeError(f"Ollama вернул HTTP {exc.code}: {detail}") from None
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Не удалось подключиться к Ollama по адресу {url}. Убедись, что Ollama "
            f"запущена и локальный сервер доступен. Подробности: {exc.reason}"
        ) from None
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise RuntimeError(f"Ollama вернула некорректный JSON: {exc}") from None


def list_ollama_models(base_url: str, timeout: int = 10) -> list[str]:
    data = _ollama_json(normalize_ollama_url(base_url) + "/api/tags", timeout=timeout)
    return [
        str(item.get("name") or item.get("model"))
        for item in data.get("models", [])
        if item.get("name") or item.get("model")
    ]


def _model_name_matches(installed: str, requested: str) -> bool:
    def normalize(name: str) -> str:
        return name[:-7] if name.endswith(":latest") else name
    return normalize(installed.strip()) == normalize(requested.strip())


def check_ollama(base_url: str, model: str, timeout: int = 10) -> list[str]:
    models = list_ollama_models(base_url, timeout)
    if not any(_model_name_matches(item, model) for item in models):
        installed = ", ".join(models) if models else "(список пуст)"
        raise RuntimeError(
            f"Модель {model} не найдена в локальном Ollama. Установленные модели: {installed}. "
            f"Выполни ollama pull {model} или укажи установленную модель через --model."
        )
    return models


def call_ollama(
    payload: dict[str, Any], model: str,
    base_url: str = "http://localhost:11434", timeout: int = 300
) -> str:
    """Send the compact report to the local Ollama /api/chat endpoint."""
    request_body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {
                "role": "user",
                "content": "Проанализируй этот компактный отчёт DPScope. Не добавляй сведения вне данных.\n\n"
                           + json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            },
        ],
        "stream": False,
    }
    response_data = _ollama_json(
        normalize_ollama_url(base_url) + "/api/chat", request_body, timeout=timeout
    )
    result = ((response_data.get("message") or {}).get("content") or "").strip()
    if not result:
        raise RuntimeError("Ollama вернула пустой message.content. Проверь модель и повтори запрос.")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Локальный AI-разбор DPScope через Ollama (без OpenAI API и API-ключа)."
    )
    parser.add_argument("--profile", type=Path, default=Path("aou_event_profile.json"))
    parser.add_argument("--report", type=Path, default=Path("aou_report.json"))
    parser.add_argument("--out", type=Path, default=Path("aou_ai_advice.md"))
    parser.add_argument(
        "--model", default=os.environ.get("OLLAMA_MODEL", "qwen3.5"),
        help="имя локальной модели Ollama; по умолчанию qwen3.5"
    )
    parser.add_argument(
        "--ollama-url", default=os.environ.get("OLLAMA_HOST", "http://localhost:11434"),
        help="локальный адрес Ollama; по умолчанию http://localhost:11434"
    )
    parser.add_argument(
        "--timeout", type=int, default=300,
        help="тайм-аут генерации в секундах (по умолчанию 300)"
    )
    parser.add_argument("--check", action="store_true", help="проверить Ollama и наличие выбранной модели")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="сохранить компактный JSON без обращения к Ollama"
    )
    args = parser.parse_args()

    try:
        if args.check:
            models = check_ollama(args.ollama_url, args.model)
            print("Ollama доступна. Установленные модели: " + ", ".join(models))
            print(f"Выбранная модель найдена: {args.model}")
            return 0

        profile = json.loads(args.profile.read_text(encoding="utf-8"))
        report = json.loads(args.report.read_text(encoding="utf-8"))
        payload = build_ai_payload(profile, report)
        if args.dry_run:
            args.out.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            print(f"Сводка без отправки сохранена: {args.out}")
            return 0

        print(
            f"Отправляю компактную сводку локально в Ollama ({args.model}); "
            "внешний API и ключ не используются."
        )
        answer = call_ollama(payload, args.model, args.ollama_url, args.timeout)
        args.out.write_text(answer + "\n", encoding="utf-8")
        print(f"Локальный AI-разбор сохранён: {args.out} (model={args.model})")
        return 0
    except (OSError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
        print(f"Ошибка AI-помощника: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
