#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Convert DPScope /aou eventexport CSV into an offline formula profile.

The in-game callback reports applied damage/healing, not the server's pre-stat
ability base. This converter therefore removes the recorded Mastery, Resolve,
Ruthlessness and actual crit multipliers to build a normalized per-event base.
All other unreported/target-side factors remain folded into that event's base.
Measured Resolve pool values are kept fixed during counterfactual optimization.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import random
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median, stdev
from typing import Any

import aou_formula_calculator as calc


STAT_COLUMNS = {
    "M": "mastery",
    "R": "resolve",
    "U": "ruthlessness",
    "L": "luck",
}
REQUIRED_STATS = tuple(STAT_COLUMNS)
PRE_HP_QUALITIES = {"measured_pre", "estimated_pre"}


def number(value: Any) -> float | None:
    try:
        out = float(str(value).strip().replace(",", "."))
        return out if math.isfinite(out) else None
    except (TypeError, ValueError):
        return None


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source, delimiter=";"))


def stat_signature(rows: list[dict[str, str]]) -> dict[str, float]:
    """Return median reference stats for optimizer; event normalization uses per-row snapshots."""
    result: dict[str, float] = {}
    for key, label in STAT_COLUMNS.items():
        values = [value for row in rows if (value := number(row.get(key))) is not None]
        if not values:
            raise ValueError(f"В журнале нет снимка характеристики {key} ({label}).")
        result[label] = sorted(values)[len(values) // 2]
    return result


def optional_stat_signature(rows: list[dict[str, str]], key: str, label: str) -> float:
    values = [value for row in rows if (value := number(row.get(key))) is not None]
    return sorted(values)[len(values) // 2] if values else 0.0


def event_stats(row: dict[str, str], fallback: dict[str, float]) -> dict[str, float]:
    """Use the stat snapshot attached to this event, falling back only when absent."""
    keys = {"M": "mastery", "R": "resolve", "U": "ruthlessness", "L": "luck",
            "S": "fortitude", "W": "will", "B": "bloodthirst", "C": "caution"}
    result = dict(fallback)
    for column, name in keys.items():
        value = number(row.get(column))
        if value is not None:
            result[name] = value
    return result


ALL_STAT_COLUMNS = {
    "M": "mastery", "R": "resolve", "U": "ruthlessness", "L": "luck",
    "S": "fortitude", "W": "will", "B": "bloodthirst", "C": "caution",
}
OFFENSIVE_EXPERIMENT_STATS = ("mastery", "resolve", "ruthlessness", "luck")
DEFENSIVE_EXPERIMENT_STATS = ("fortitude", "will", "bloodthirst", "caution")
MIN_STAT_STEP = 25.0
MIN_FIGHTS_PER_BUILD = 3
MIN_EVENTS_PER_FIGHT_CONTEXT = 3
MAX_STAT_SNAPSHOT_AGE_SECONDS = 3.0
BOOTSTRAP_REPLICATES = 500


def compare_stat_sets(rows: list[dict[str, str]]) -> dict[str, Any]:
    """Descriptive totals split by activity, profile and full stat snapshot.

    This report is intentionally not a marginal-efficiency estimate.
    """
    columns = ALL_STAT_COLUMNS
    buckets: dict[tuple[str, str, tuple[float | None, ...]], dict[str, Any]] = {}
    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing", "incoming"}:
            continue
        profile = (row.get("profile") or "unknown").strip().lower()
        signature = tuple(number(row.get(key)) for key in columns)
        bucket_key = (kind, profile, signature)
        bucket = buckets.setdefault(bucket_key, {
            "kind": kind,
            "profile": profile,
            "stats": {name: value for name, value in zip(columns.values(), signature)},
            "damage": 0.0, "healing": 0.0, "incoming": 0.0,
            "damage_events": 0, "healing_events": 0, "incoming_events": 0,
            "critical_events": 0, "normal_events": 0, "unknown_critical_events": 0,
            "fights": set(), "seconds": {}, "healing_by_recipient": {},
        })
        amount = number(row.get("observed_amount")) or 0.0
        fight = (row.get("fight_id") or "unknown").strip()
        second = max(0, int(number(row.get("second")) or 0))
        bucket["fights"].add(fight)
        bucket["seconds"].setdefault(fight, set()).add(second)
        critical = (row.get("critical") or "").strip()
        if critical == "1":
            bucket["critical_events"] += 1
        elif critical == "0":
            bucket["normal_events"] += 1
        else:
            bucket["unknown_critical_events"] += 1

        if kind == "damage":
            bucket["damage"] += amount
            bucket["damage_events"] += 1
        elif kind == "incoming":
            bucket["incoming"] += amount
            bucket["incoming_events"] += 1
        else:
            bucket["healing"] += amount
            bucket["healing_events"] += 1
            recipient = (row.get("recipient") or "unknown").strip().lower()
            segment = bucket["healing_by_recipient"].setdefault(
                recipient, {"amount": 0.0, "events": 0}
            )
            segment["amount"] += amount
            segment["events"] += 1

    result = []
    for bucket in buckets.values():
        # This is the span covered by observed events, not guaranteed full fight time.
        # The addon timer is elapsed from fight start; use last observed second + 1.
        # This includes quiet gaps before the first recorded hit, unlike max-min span.
        observed_seconds = sum(
            max(1, max(seconds) + 1)
            for seconds in bucket["seconds"].values()
        )
        result.append({
            "kind": bucket["kind"],
            "profile": bucket["profile"],
            "stats": bucket["stats"],
            "fights": len(bucket["fights"]),
            "damage_events": bucket["damage_events"],
            "healing_events": bucket["healing_events"],
            "incoming_events": bucket["incoming_events"],
            "critical_events": bucket["critical_events"],
            "normal_events": bucket["normal_events"],
            "unknown_critical_events": bucket["unknown_critical_events"],
            "observed_damage": round(bucket["damage"], 2),
            "observed_healing": round(bucket["healing"], 2),
            "observed_incoming": round(bucket["incoming"], 2),
            "healing_by_recipient": {
                key: {"amount": round(value["amount"], 2), "events": value["events"]}
                for key, value in sorted(bucket["healing_by_recipient"].items())
            },
            "observed_fight_seconds_estimate": observed_seconds,
            "observed_dps_estimate": round(bucket["damage"] / observed_seconds, 2) if observed_seconds else None,
            "observed_hps_estimate": round(bucket["healing"] / observed_seconds, 2) if observed_seconds else None,
            "observed_incoming_rate_estimate": round(bucket["incoming"] / observed_seconds, 2) if observed_seconds else None,
        })
    result.sort(key=lambda item: (
        item["profile"], item["kind"],
        item["stats"].get("mastery") or 0,
        item["stats"].get("resolve") or 0,
    ))
    return {
        "method": "descriptive totals by activity, profile and complete stat snapshot",
        "groups": result,
        "note": "Описательная статистика, не причинный эффект и не Marginal Efficiency. Время оценено по максимальной секунде таймера каждого боя + 1; это не точная длительность при отсутствии завершающего события.",
    }


def _duration_band(seconds: int) -> str:
    if seconds <= 10:
        return "0-10 sec"
    if seconds <= 30:
        return "10-30 sec"
    if seconds <= 60:
        return "30-60 sec"
    if seconds <= 120:
        return "60-120 sec"
    if seconds <= 300:
        return "120-300 sec"
    return "300+ sec"


def build_temporal_performance(rows: list[dict[str, str]]) -> dict[str, Any]:
    """Build observed raw burst/sustained windows and sampled-Resolve summaries per fight."""
    fight_last_second: dict[str, int] = {}
    for row in rows:
        fight = (row.get("fight_id") or "unknown").strip()
        second = number(row.get("second"))
        if fight and fight != "unknown" and second is not None:
            fight_last_second[fight] = max(fight_last_second.get(fight, 0), int(second))

    grouped: dict[tuple[str, str], dict[int, float]] = defaultdict(lambda: defaultdict(float))
    grouped_events: Counter[tuple[str, str]] = Counter()
    resolve_by_second: dict[tuple[str, str], dict[int, list[float]]] = defaultdict(lambda: defaultdict(list))
    profile_by_fight: dict[str, str] = {}
    targets_by_fight: dict[str, set[str]] = defaultdict(set)
    target_missing_by_fight: Counter[str] = Counter()

    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing", "incoming"}:
            continue
        fight = (row.get("fight_id") or "unknown").strip()
        if not fight or fight == "unknown":
            continue
        second_value = number(row.get("second"))
        amount = number(row.get("observed_amount"))
        if second_value is None or amount is None or amount < 0:
            continue
        second = max(0, int(second_value))
        grouped[(fight, kind)][second] += amount
        grouped_events[(fight, kind)] += 1
        profile_by_fight[fight] = (row.get("profile") or "unknown").strip().lower()
        target_id = (row.get("target_id") or "").strip()
        if target_id and target_id.lower() not in {"unknown", "none"}:
            targets_by_fight[fight].add(target_id)
        else:
            target_missing_by_fight[fight] += 1

        pool = number(row.get("resolve_pool"))
        if kind in {"damage", "healing"} and pool is not None:
            resolve_by_second[(fight, kind)][second].append(max(0.0, min(100.0, pool)))

    burst_windows = (1, 3, 5, 10, 15, 30)
    sustained_windows = (30, 60, 120, 180, 300)
    fight_reports: list[dict[str, Any]] = []

    for (fight, kind), totals in sorted(grouped.items()):
        duration = max(1, fight_last_second.get(fight, max(totals)) + 1)
        by_second = [0.0] * duration
        for second, amount in totals.items():
            if 0 <= second < duration:
                by_second[second] += amount
        prefix = [0.0]
        for amount in by_second:
            prefix.append(prefix[-1] + amount)

        windows: dict[str, Any] = {}
        for window in sorted(set(burst_windows + sustained_windows)):
            label = f"{window}s"
            if duration < window:
                windows[label] = {
                    "status": "insufficient_duration",
                    "duration_seconds": duration,
                    "observed_amount": None,
                    "mean_rate_per_second": None,
                    "start_second": None,
                    "end_second": None,
                }
                continue
            best_amount = -1.0
            best_start = 0
            for start_second in range(0, duration - window + 1):
                total = prefix[start_second + window] - prefix[start_second]
                if total > best_amount:
                    best_amount = total
                    best_start = start_second
            windows[label] = {
                "status": "calculated",
                "classification": "DERIVED",
                "observed_amount": round(best_amount, 4),
                "mean_rate_per_second": round(best_amount / window, 4),
                "start_second": best_start,
                "end_second": best_start + window,
                "window_seconds": window,
            }

        resolve = resolve_by_second.get((fight, kind), {})
        per_second_resolve = [sum(values) / len(values) for values in resolve.values() if values]
        resolve_summary = None
        if per_second_resolve:
            resolve_summary = {
                "classification": "DERIVED",
                "samples": len(per_second_resolve),
                "mean_sampled_pool": round(sum(per_second_resolve) / len(per_second_resolve), 4),
                "median_sampled_pool": round(median(per_second_resolve), 4),
                "peak_sampled_pool": round(max(per_second_resolve), 4),
                "sampled_second_share_above": {
                    str(threshold): round(sum(1 for value in per_second_resolve if value >= threshold) / len(per_second_resolve), 4)
                    for threshold in (25, 50, 75, 90)
                },
                "method": "mean of event-pool readings within each sampled second; sample share, not time uptime",
            }

        known_targets = targets_by_fight.get(fight, set())
        missing_targets = target_missing_by_fight.get(fight, 0)
        target_classification = (
            "single_target" if len(known_targets) == 1 and missing_targets == 0
            else "multi_target_or_aoe" if len(known_targets) > 1 and missing_targets == 0
            else "unknown"
        )
        fight_reports.append({
            "fight_id": fight,
            "profile": profile_by_fight.get(fight, "unknown"),
            "profile_source": "configured_not_automatically_classified",
            "kind": kind,
            "classification": "DERIVED",
            "duration_seconds_estimate": duration,
            "duration_band": _duration_band(duration),
            "event_count": grouped_events[(fight, kind)],
            "target_count": len(known_targets) if missing_targets == 0 else None,
            "target_type": target_classification,
            "burst_windows": {f"{w}s": windows[f"{w}s"] for w in burst_windows},
            "sustained_windows": {f"{w}s": windows[f"{w}s"] for w in sustained_windows},
            "resolve_sample_summary": resolve_summary,
            "limitations": [
                "Окна используют observed_amount callback: это raw reported output, не Effective DPS/HPS.",
                "Длительность оценена как max(second)+1; точность зависит от полноты события в конце боя.",
                "Resolve sample share — доля секунд с замерами, а не временной uptime.",
                "PvE/PvP берётся из выбранного профиля, классификация активности автоматически не доказана.",
            ],
        })

    return {
        "status": "calculated" if fight_reports else "insufficient_data",
        "classification": "DERIVED",
        "method": "per-fight elapsed-second aggregation and full rolling windows with zero-filled quiet seconds",
        "burst_windows_seconds": list(burst_windows),
        "sustained_windows_seconds": list(sustained_windows),
        "fights": fight_reports,
    }


def build_event_effectiveness(rows: list[dict[str, str]]) -> dict[str, Any]:
    """Keep callback-reported amounts separate from HP-capped effective estimates."""
    fight_last_second: dict[str, int] = {}
    for row in rows:
        fight = (row.get("fight_id") or "unknown").strip()
        second = number(row.get("second"))
        if fight and fight != "unknown" and second is not None:
            fight_last_second[fight] = max(fight_last_second.get(fight, 0), int(second))

    buckets: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing", "incoming", "receivedheal"}:
            continue
        fight = (row.get("fight_id") or "unknown").strip()
        profile = (row.get("profile") or "unknown").strip().lower()
        if not fight or fight == "unknown":
            continue
        recipient = (row.get("recipient") or "unknown").strip().lower()
        key = (fight, profile, kind, recipient)
        bucket = buckets.setdefault(key, {
            "fight_id": fight, "profile": profile, "kind": kind, "recipient": recipient,
            "reported_amount": 0.0, "events": 0,
            "estimated_effective_amount": 0.0, "estimated_excess_amount": 0.0,
            "hp_eligible_events": 0, "measured_hp_events": 0, "estimated_hp_events": 0,
            "unknown_hp_events": 0,
        })
        amount = number(row.get("observed_amount"))
        if amount is None or amount < 0:
            continue
        bucket["reported_amount"] += amount
        bucket["events"] += 1
        hp_pct = number(row.get("target_hp_before"))
        hp_max = number(row.get("target_max_hp"))
        hp_quality = (row.get("hp_quality") or "").strip().lower()
        if hp_pct is None or hp_max is None or hp_max <= 0 or hp_quality not in PRE_HP_QUALITIES:
            bucket["unknown_hp_events"] += 1
            continue

        if kind in {"healing", "receivedheal"}:
            available_hp = max(0.0, min(float(hp_max), float(hp_max) * (1.0 - hp_pct / 100.0)))
        else:
            available_hp = max(0.0, min(float(hp_max), float(hp_max) * (hp_pct / 100.0)))
        effective_estimate = min(amount, available_hp)
        excess_estimate = max(0.0, amount - effective_estimate)
        bucket["estimated_effective_amount"] += effective_estimate
        bucket["estimated_excess_amount"] += excess_estimate
        bucket["hp_eligible_events"] += 1
        if hp_quality == "measured_pre":
            bucket["measured_hp_events"] += 1
        else:
            bucket["estimated_hp_events"] += 1

    results = []
    for bucket in buckets.values():
        duration = max(1, fight_last_second.get(bucket["fight_id"], 0) + 1)
        reported = bucket["reported_amount"]
        effective = bucket["estimated_effective_amount"]
        excess = bucket["estimated_excess_amount"]
        is_heal = bucket["kind"] in {"healing", "receivedheal"}
        results.append({
            **bucket,
            "reported_amount": round(reported, 4),
            "estimated_effective_amount": round(effective, 4),
            "estimated_excess_amount": round(excess, 4),
            "classification": "ESTIMATED",
            "duration_seconds_estimate": duration,
            "reported_rate_per_second": round(reported / duration, 4),
            "effective_rate_per_second_estimated": round(effective / duration, 4),
            "excess_rate_per_second_estimated": round(excess / duration, 4),
            "effective_share_percent_estimated": round(effective / reported * 100.0, 4) if reported > 0 else None,
            "excess_share_percent_estimated": round(excess / reported * 100.0, 4) if reported > 0 else None,
            "excess_label": "overheal_estimated" if is_heal else "overkill_estimated",
            "hp_coverage_percent": round(bucket["hp_eligible_events"] / bucket["events"] * 100.0, 4) if bucket["events"] else 0.0,
            "method": "per-event HP cap: min(reported amount, missing HP for healing or remaining HP for damage)",
            "limitations": [
                "Не является MEASURED effective amount: callback не содержит надёжный target_hp_after для каждого события.",
                "Не учитывает последовательные события в одной временной метке, щиты, поглощения, модификаторы и серверную очередность.",
                "Неизвестный HP исключается из effective estimate, но reported amount сохраняется отдельно.",
            ],
        })
    results.sort(key=lambda item: (item["fight_id"], item["kind"], item["recipient"]))
    return {
        "status": "calculated" if results else "insufficient_data",
        "classification": "ESTIMATED",
        "fights": results,
    }


def build_critical_analysis(rows: list[dict[str, str]]) -> dict[str, Any]:
    """Descriptive per-ability critical contribution from event flags and amounts."""
    groups: dict[tuple[Any, ...], dict[str, Any]] = {}
    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing"}:
            continue
        profile = (row.get("profile") or "unknown").strip().lower()
        ability = (row.get("ability") or row.get("damage_source") or "unknown").strip()
        if not ability or ability.lower() == "unknown":
            continue
        critical = (row.get("critical") or "").strip()
        amount = number(row.get("observed_amount"))
        if amount is None or amount <= 0:
            continue
        hp = number(row.get("target_hp_before"))
        hp_band = "unknown" if hp is None else f"{min(80, int(max(0, min(100, hp)) // 20) * 20)}-{min(100, int(max(0, min(100, hp)) // 20) * 20) + 20}%"
        pool = number(row.get("resolve_pool"))
        pool_band = "unknown" if pool is None else f"{min(90, int(max(0, min(100, pool)) // 10) * 10)}-{min(100, int(max(0, min(100, pool)) // 10) * 10) + 10}%"
        stats = _fight_stat_signature(row)
        recipient = (row.get("recipient") or "unknown").strip().lower()
        element = (row.get("element") or "unknown").strip().lower()
        key = (kind, profile, ability.lower(), element, hp_band, pool_band, recipient, stats)
        bucket = groups.setdefault(key, {
            "kind": kind, "profile": profile, "ability": ability, "element": element,
            "target_hp_band": hp_band, "resolve_pool_band": pool_band,
            "recipient": recipient, "stats": (
                {name: value for name, value in zip(ALL_STAT_COLUMNS.values(), stats)}
                if stats is not None else None
            ),
            "normal_events": 0, "critical_events": 0, "unknown_critical_events": 0,
            "normal_amount": 0.0, "critical_amount": 0.0, "fights": set(),
        })
        fight = (row.get("fight_id") or "unknown").strip()
        if fight and fight != "unknown":
            bucket["fights"].add(fight)
        if critical == "0":
            bucket["normal_events"] += 1
            bucket["normal_amount"] += amount
        elif critical == "1":
            bucket["critical_events"] += 1
            bucket["critical_amount"] += amount
        else:
            bucket["unknown_critical_events"] += 1

    results = []
    for bucket in groups.values():
        normal_n, critical_n = bucket["normal_events"], bucket["critical_events"]
        known_n = normal_n + critical_n
        total_amount = bucket["normal_amount"] + bucket["critical_amount"]
        normal_avg = bucket["normal_amount"] / normal_n if normal_n else None
        critical_avg = bucket["critical_amount"] / critical_n if critical_n else None
        results.append({
            **{key: value for key, value in bucket.items() if key != "fights"},
            "classification": "DERIVED",
            "fight_count": len(bucket["fights"]),
            "known_critical_flag_events": known_n,
            "observed_critical_rate_percent": round(critical_n / known_n * 100.0, 4) if known_n else None,
            "observed_critical_amount_share_percent": round(bucket["critical_amount"] / total_amount * 100.0, 4) if total_amount else None,
            "normal_average_amount": round(normal_avg, 4) if normal_avg is not None else None,
            "critical_average_amount": round(critical_avg, 4) if critical_avg is not None else None,
            "observed_critical_to_normal_average_ratio": round(critical_avg / normal_avg, 4)
                if normal_avg and critical_avg is not None else None,
            "causal_status": "descriptive_only_target_buffs_rotation_may_confound",
        })
    results.sort(key=lambda item: (
        item["kind"], item["profile"], item["ability"], item["target_hp_band"],
        item["resolve_pool_band"], -(item["normal_events"] + item["critical_events"]),
    ))
    return {"status": "calculated" if results else "insufficient_data", "classification": "DERIVED", "groups": results}


def _percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    position = (len(ordered) - 1) * fraction
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def _bootstrap_effect_ci(
    baseline_fights: list[float],
    test_fights: list[float],
    stat_delta: float,
    seed: int,
) -> list[float] | None:
    if len(baseline_fights) < MIN_FIGHTS_PER_BUILD or len(test_fights) < MIN_FIGHTS_PER_BUILD:
        return None
    rng = random.Random(seed)
    effects = []
    for _ in range(BOOTSTRAP_REPLICATES):
        baseline = sum(rng.choice(baseline_fights) for _ in baseline_fights) / len(baseline_fights)
        test = sum(rng.choice(test_fights) for _ in test_fights) / len(test_fights)
        effects.append((test - baseline) * 100.0 / stat_delta)
    return [round(_percentile(effects, 0.025), 4), round(_percentile(effects, 0.975), 4)]


def _fight_stat_signature(row: dict[str, str]) -> tuple[float, ...] | None:
    values = [number(row.get(column)) for column in ALL_STAT_COLUMNS]
    if any(value is None for value in values):
        return None
    return tuple(round(float(value), 2) for value in values)



def _entity_match_signature(row: dict[str, str], prefix: str) -> str | None:
    """Build a conservative cross-instance entity signature from live API metadata.

    A signature is usable only when name, level, quality and mob classification
    are all present. It is an archetype hint, not a globally unique template ID.
    """
    name = " ".join(str(row.get(f"{prefix}_name") or "").split()).casefold()
    level = number(row.get(f"{prefix}_level"))
    quality = number(row.get(f"{prefix}_quality"))
    is_mob_raw = str(row.get(f"{prefix}_is_mob") or "").strip().lower()
    if not name or level is None or quality is None or is_mob_raw not in {"0", "1", "true", "false"}:
        return None
    is_mob = is_mob_raw in {"1", "true"}
    level_value = int(level) if level.is_integer() else round(level, 4)
    quality_value = int(quality) if quality.is_integer() else round(quality, 4)
    return json.dumps(
        [name, level_value, quality_value, is_mob],
        ensure_ascii=False,
        separators=(",", ":"),
    )


def analyze_controlled_stat_efficiency(rows: list[dict[str, str]]) -> dict[str, Any]:
    """Compare one-stat changes within matched event contexts and independent fights.

    The main outcome is per-fight amount/second for the matched ability context.
    Mean event amount is retained as a secondary diagnostic. Results are DERIVED
    controlled observations; unlogged target and encounter conditions can confound.
    """
    fight_last_second: dict[str, int] = {}
    for row in rows:
        fight = (row.get("fight_id") or "unknown").strip()
        second = number(row.get("second"))
        if second is not None:
            fight_last_second[fight] = max(fight_last_second.get(fight, 0), int(second))

    ContextMap = dict[tuple[Any, ...], dict[tuple[float, ...], dict[str, list[tuple[float, int]]]]]
    contexts: ContextMap = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    # Luck changes the mixture of Normal/Critical hits. It must be compared across
    # all hits of the same ability rather than conditioning on a hit already being crit.
    contexts_all_hits: ContextMap = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    fight_signatures: dict[str, set[tuple[float, ...]]] = defaultdict(set)
    fight_valid_event_counts: Counter[str] = Counter()
    validated_event_rows = 0
    strict_valid_event_rows = 0
    legacy_exploratory_event_rows = 0
    skipped: Counter[str] = Counter()

    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing", "incoming"}:
            continue
        profile = (row.get("profile") or "").strip().lower()
        if profile not in {"pve", "raid", "pvp", "heal", "tank"}:
            skipped["profile_unknown_or_not_classified"] += 1
            continue
        profile_environment = (
            "pve" if profile in {"pve", "raid"}
            else "pvp" if profile == "pvp"
            else "unknown_role_profile"
        )
        fight = (row.get("fight_id") or "unknown").strip()
        if not fight or fight == "unknown":
            skipped["fight_id_unknown"] += 1
            continue
        amount = number(row.get("observed_amount"))
        if amount is None or amount <= 0:
            skipped["amount_missing_or_non_positive"] += 1
            continue
        second_value = number(row.get("second"))
        if second_value is None:
            skipped["timestamp_missing"] += 1
            continue
        hp = number(row.get("target_hp_before"))
        hp_quality = (row.get("hp_quality") or "").strip().lower()
        if hp is None or hp_quality not in PRE_HP_QUALITIES:
            skipped["pre_event_hp_unavailable"] += 1
            continue
        if hp < 0 or hp > 100:
            skipped["pre_event_hp_out_of_range"] += 1
            continue
        critical_text = (row.get("critical") or "").strip()
        if critical_text not in {"0", "1"}:
            skipped["critical_flag_unknown"] += 1
            continue
        if kind in {"damage", "healing"} and number(row.get("resolve_pool")) is None:
            skipped["resolve_pool_unknown"] += 1
            continue

        snapshot_age = number(row.get("stat_sample_age"))
        if snapshot_age is not None and (
            snapshot_age < 0 or snapshot_age > MAX_STAT_SNAPSHOT_AGE_SECONDS
        ):
            skipped["stat_snapshot_stale"] += 1
            continue
        snapshot_quality = "fresh" if snapshot_age is not None else "legacy_age_unverified"

        actor_id = (row.get("actor_id") or "").strip()
        target_id = (row.get("target_id") or "").strip()
        actor_id_known = bool(actor_id and actor_id.lower() not in {"unknown", "none"})
        target_id_known = bool(target_id and target_id.lower() not in {"unknown", "none"})
        identity_is_known = actor_id_known and target_id_known
        if identity_is_known:
            identity_quality = "measured_instance_ids"
        else:
            # Legacy rows can still be explored, but missing identifiers are
            # never invented or promoted to strict evidence.
            identity_quality = "legacy_identity_unverified"

        actor_signature = _entity_match_signature(row, "actor")
        target_signature = _entity_match_signature(row, "target")
        actor_name = " ".join(str(row.get("actor_name") or "").split())
        target_name = " ".join(str(row.get("target_name") or "").split())
        actor_level = number(row.get("actor_level"))
        actor_quality = number(row.get("actor_quality"))
        actor_is_mob = str(row.get("actor_is_mob") or "").strip()
        target_level = number(row.get("target_level"))
        target_quality = number(row.get("target_quality"))
        target_is_mob = str(row.get("target_is_mob") or "").strip()

        # Canonicalize metadata for both comparison grouping and reporting.
        # Case or boolean spelling changes must not split one archetype.
        if actor_signature:
            actor_descriptor = json.loads(actor_signature)
            actor_name, actor_level, actor_quality = actor_descriptor[:3]
            actor_is_mob = "1" if actor_descriptor[3] else "0"
        if target_signature:
            target_descriptor = json.loads(target_signature)
            target_name, target_level, target_quality = target_descriptor[:3]
            target_is_mob = "1" if target_descriptor[3] else "0"

        # Keep the player actor tied to its exact instance ID. Cross-instance
        # archetype matching is allowed for targets only, with a complete
        # signature; actor descriptors remain diagnostic metadata.
        actor_match_method = "instance_id" if actor_id_known else "legacy_unverified"
        target_match_method = "entity_signature" if target_signature else (
            "instance_id" if target_id_known else "legacy_unverified"
        )
        actor_match_key = (
            "instance:" + actor_id if actor_id_known
            else "legacy_unknown_actor"
        )
        target_match_key = (
            "entity:" + target_signature if target_signature
            else "instance:" + target_id if target_id_known
            else "legacy_unknown_target"
        )

        signature = _fight_stat_signature(row)
        if signature is None:
            skipped["full_stat_snapshot_missing"] += 1
            continue
        fight_signatures[fight].add(signature)

        ability = (row.get("ability") or "").strip()
        damage_source = (row.get("damage_source") or "").strip()
        if not ability or ability.lower() == "unknown":
            ability = damage_source
        if not ability or ability.lower() in {"unknown", "none"}:
            skipped["ability_or_damage_source_unknown"] += 1
            continue

        element = (row.get("element") or "").strip().lower()
        target_max_hp = number(row.get("target_max_hp"))
        target_hp_scale = (
            int(math.floor(math.log10(target_max_hp)))
            if target_max_hp is not None and target_max_hp > 0 else None
        )
        hp_band_start = min(80, int(hp // 20) * 20)
        if kind == "incoming":
            resolve_band = None
        else:
            pool = max(0.0, min(100.0, float(number(row.get("resolve_pool")))))
            resolve_band = min(90, int(pool // 10) * 10)
        recipient = (row.get("recipient") or "unknown").strip().lower() if kind == "healing" else ""
        duration_seconds = max(1, fight_last_second.get(fight, int(second_value)) + 1)
        duration = _duration_band(duration_seconds)
        validated_event_rows += 1
        fight_valid_event_counts[fight] += 1
        if identity_quality == "measured_instance_ids" and snapshot_quality == "fresh":
            strict_valid_event_rows += 1
        else:
            legacy_exploratory_event_rows += 1
        base_stratum = (
            kind, profile, profile_environment, duration,
            actor_match_key, target_match_key, actor_match_method, target_match_method,
            actor_signature or "", target_signature or "",
            actor_name, actor_level, actor_quality, actor_is_mob,
            target_name, target_level, target_quality, target_is_mob,
            identity_quality, snapshot_quality,
            ability.lower(), element, damage_source.lower(),
            hp_band_start, hp_quality, target_hp_scale, resolve_band,
        )
        sample = (float(amount), int(second_value))
        stratum = base_stratum + (critical_text, recipient)
        contexts[stratum][signature][fight].append(sample)

        if kind in {"damage", "healing"}:
            all_hits_stratum = base_stratum + ("any", recipient)
            contexts_all_hits[all_hits_stratum][signature][fight].append(sample)

    # A build change inside one fight invalidates that fight as a controlled sample.
    contaminated_fights = {
        fight for fight, signatures in fight_signatures.items() if len(signatures) > 1
    }
    if contaminated_fights:
        skipped["stats_changed_during_fight"] += len(contaminated_fights)
        for context_map in (contexts, contexts_all_hits):
            for stratum in list(context_map):
                for signature in list(context_map[stratum]):
                    for fight in list(context_map[stratum][signature]):
                        if fight in contaminated_fights:
                            del context_map[stratum][signature][fight]
                    if not context_map[stratum][signature]:
                        del context_map[stratum][signature]
                if not context_map[stratum]:
                    del context_map[stratum]

    comparisons: list[dict[str, Any]] = []
    insufficient_pairs = 0
    comparison_id = 0

    def process_context_map(context_map: ContextMap, all_hits_for_luck: bool = False) -> None:
        nonlocal insufficient_pairs, comparison_id
        for stratum, builds in context_map.items():
            (kind, profile, profile_environment, duration,
             actor_match_key, target_match_key, actor_match_method, target_match_method,
             actor_signature, target_signature,
             actor_name, actor_level, actor_quality, actor_is_mob,
             target_name, target_level, target_quality, target_is_mob,
             identity_quality, snapshot_quality,
             ability, element, damage_source, hp_band, hp_quality, hp_scale,
             resolve_band, crit, recipient) = stratum
            if all_hits_for_luck:
                stat_names = ("luck",)
            elif kind in {"damage", "healing"}:
                stat_names = tuple(name for name in OFFENSIVE_EXPERIMENT_STATS if name != "luck")
            else:
                stat_names = DEFENSIVE_EXPERIMENT_STATS

            signatures = list(builds.keys())
            for stat_name in stat_names:
                column = next(column for column, name in ALL_STAT_COLUMNS.items() if name == stat_name)
                index = list(ALL_STAT_COLUMNS).index(column)
                for first_index in range(len(signatures)):
                    for second_index in range(first_index + 1, len(signatures)):
                        first, second = signatures[first_index], signatures[second_index]
                        first_value, second_value = first[index], second[index]
                        if first_value == second_value:
                            continue
                        low_sig, high_sig = (first, second) if first_value < second_value else (second, first)
                        low_value, high_value = low_sig[index], high_sig[index]
                        delta = high_value - low_value
                        if delta < max(MIN_STAT_STEP, abs(low_value) * 0.03):
                            continue

                        other_stats_match = True
                        for other_index, _ in enumerate(ALL_STAT_COLUMNS):
                            if other_index == index:
                                continue
                            baseline_value, test_value = low_sig[other_index], high_sig[other_index]
                            tolerance = max(5.0, max(abs(baseline_value), abs(test_value)) * 0.005)
                            if abs(test_value - baseline_value) > tolerance:
                                other_stats_match = False
                                break
                        if not other_stats_match:
                            continue

                        def fight_values(signature: tuple[float, ...]) -> tuple[list[float], list[float], int, list[int]]:
                            selected = {
                                fight: samples for fight, samples in builds[signature].items()
                                if len(samples) >= MIN_EVENTS_PER_FIGHT_CONTEXT
                            }
                            event_means: list[float] = []
                            context_rates: list[float] = []
                            elapsed_seconds: list[int] = []
                            event_count = 0
                            for fight, samples in selected.items():
                                amounts = [sample[0] for sample in samples]
                                elapsed = max(1, fight_last_second.get(fight, max(sample[1] for sample in samples)) + 1)
                                event_means.append(sum(amounts) / len(amounts))
                                context_rates.append(sum(amounts) / elapsed)
                                elapsed_seconds.append(elapsed)
                                event_count += len(amounts)
                            return event_means, context_rates, event_count, elapsed_seconds

                        baseline_event_means, baseline_rates, baseline_events, baseline_durations = fight_values(low_sig)
                        test_event_means, test_rates, test_events, test_durations = fight_values(high_sig)
                        if (len(baseline_rates) < MIN_FIGHTS_PER_BUILD
                                or len(test_rates) < MIN_FIGHTS_PER_BUILD):
                            insufficient_pairs += 1
                            continue

                        baseline_mean = sum(baseline_rates) / len(baseline_rates)
                        test_mean = sum(test_rates) / len(test_rates)
                        baseline_event_mean = sum(baseline_event_means) / len(baseline_event_means)
                        test_event_mean = sum(test_event_means) / len(test_event_means)
                        delta_result = test_mean - baseline_mean
                        marginal_per_stat = delta_result / delta
                        effect_per_100 = marginal_per_stat * 100.0
                        relative_per_100 = (
                            ((test_mean / baseline_mean) ** (100.0 / delta) - 1.0) * 100.0
                            if baseline_mean > 0 and test_mean > 0 else None
                        )
                        comparison_id += 1
                        ci = _bootstrap_effect_ci(
                            baseline_rates, test_rates, delta,
                            seed=20261115 + comparison_id * 101,
                        )
                        quality_label = "measured_pre" if hp_quality == "measured_pre" else "estimated_pre"
                        ci_excludes_zero = bool(ci and (ci[0] > 0 or ci[1] < 0))
                        # Legacy rows have no instance IDs/snapshot-age metadata.
                        # Keep their ME for exploratory review, but never promote it
                        # above VERY_LOW confidence, regardless of a narrow bootstrap CI.
                        if identity_quality != "measured_instance_ids" or snapshot_quality != "fresh":
                            confidence = "VERY_LOW"
                        else:
                            confidence = (
                                "MEDIUM" if ci_excludes_zero and quality_label == "measured_pre"
                                and min(len(baseline_rates), len(test_rates)) >= 5 else "LOW"
                            )
                        comparisons.append({
                            "status": "derived_controlled_observation",
                            "classification": "DERIVED",
                            "causal_status": "not_proven_unobserved_confounders_remain",
                            "mode": kind,
                            "profile": profile,
                            "environment_classification": profile_environment,
                            "duration_band": duration,
                            "actor_match_method": actor_match_method,
                            "target_match_method": target_match_method,
                            "actor_signature": actor_signature or None,
                            "target_signature": target_signature or None,
                            "actor_name": actor_name or None,
                            "actor_level": actor_level,
                            "actor_quality": actor_quality,
                            "actor_is_mob": actor_is_mob or None,
                            "target_name": target_name or None,
                            "target_level": target_level,
                            "target_quality": target_quality,
                            "target_is_mob": target_is_mob or None,
                            "target_match_basis": (
                                "normalized name + level + quality + mob classification"
                                if target_match_method == "entity_signature"
                                else "exact instance ID" if target_match_method == "instance_id"
                                else "legacy identity unavailable"
                            ),
                            "comparison_identity_scope": (
                                "same_actor_instance_and_target_archetype"
                                if target_match_method == "entity_signature"
                                else "same_actor_and_target_instances"
                                if actor_match_method == "instance_id" and target_match_method == "instance_id"
                                else "legacy_exploratory_identity"
                            ),
                            "identity_quality": identity_quality,
                            "snapshot_quality": snapshot_quality,
                            "evidence_tier": (
                                "strict" if identity_quality == "measured_instance_ids" and snapshot_quality == "fresh"
                                else "legacy_exploratory"
                            ),
                            "ability": ability,
                            "element": element or "unknown",
                            "damage_source": damage_source or "unknown",
                            "target_hp_band": f"{hp_band}-{hp_band + 20}%",
                            "target_hp_quality": quality_label,
                            "target_max_hp_order": hp_scale,
                            "resolve_pool_band": (f"{resolve_band}-{resolve_band + 10}%" if resolve_band is not None else None),
                            "critical": None if crit == "any" else (crit == "1"),
                            "critical_scope": "all_hits" if crit == "any" else "normal_only" if crit == "0" else "critical_only",
                            "recipient": recipient or None,
                            "stat": stat_name,
                            "from": low_value,
                            "to": high_value,
                            "delta_stat": delta,
                            "delta_result": round(delta_result, 6),
                            "result_unit": "reported_amount_per_second",
                            "me_formula": "ME = (Result_test - Result_base) / (Stat_test - Stat_base)",
                            "marginal_efficiency_per_stat": round(marginal_per_stat, 6),
                            "marginal_efficiency_unit_per_stat": "reported amount per second per +1 stat point",
                            "marginal_efficiency_per_100": round(effect_per_100, 4),
                            "marginal_efficiency_unit_per_100": "reported amount per second per +100 stat points",
                            "result_direction": "minimize" if kind == "incoming" else "maximize",
                            "beneficial_effect_per_100": round(-effect_per_100 if kind == "incoming" else effect_per_100, 4),
                            "baseline": {
                                "fights": len(baseline_rates), "events": baseline_events,
                                "mean_context_rate_per_second": round(baseline_mean, 4),
                                "median_fight_context_rate_per_second": round(median(baseline_rates), 4),
                                "sd_between_fights_rate": round(stdev(baseline_rates), 4) if len(baseline_rates) > 1 else 0.0,
                                "mean_event_amount": round(baseline_event_mean, 4),
                                "elapsed_seconds": baseline_durations,
                            },
                            "test": {
                                "fights": len(test_rates), "events": test_events,
                                "mean_context_rate_per_second": round(test_mean, 4),
                                "median_fight_context_rate_per_second": round(median(test_rates), 4),
                                "sd_between_fights_rate": round(stdev(test_rates), 4) if len(test_rates) > 1 else 0.0,
                                "mean_event_amount": round(test_event_mean, 4),
                                "elapsed_seconds": test_durations,
                            },
                            "mean_event_amount_delta_per_100": round((test_event_mean - baseline_event_mean) * 100.0 / delta, 4),
                            "relative_change_per_100_percent": round(relative_per_100, 4) if relative_per_100 is not None else None,
                            "confidence_interval_95_per_100": ci,
                            "confidence_interval_95_per_stat": (
                                [round(ci[0] / 100.0, 6), round(ci[1] / 100.0, 6)] if ci else None
                            ),
                            "confidence": confidence,
                            "n_independent_fights": len(baseline_rates) + len(test_rates),
                        })

    process_context_map(contexts, all_hits_for_luck=False)
    process_context_map(contexts_all_hits, all_hits_for_luck=True)

    included_events = sum(
        len(values)
        for builds in contexts.values()
        for fights in builds.values()
        for values in fights.values()
    )
    strict_comparison_count = sum(
        1 for item in comparisons if item.get("evidence_tier") == "strict"
    )
    legacy_exploratory_comparison_count = sum(
        1 for item in comparisons if item.get("evidence_tier") == "legacy_exploratory"
    )

    contaminated_event_rows = sum(
        fight_valid_event_counts.get(fight, 0) for fight in contaminated_fights
    )
    included_luck_all_hit_events = sum(
        len(values)
        for builds in contexts_all_hits.values()
        for fights in builds.values()
        for values in fights.values()
    )

    comparisons.sort(
        key=lambda item: (
            item["stat"], item["mode"], item["profile"], item["ability"],
            item["target_hp_band"], item["resolve_pool_band"] or "",
            -item["n_independent_fights"],
        )
    )
    return {
        "status": "comparisons_available" if comparisons else "insufficient_data",
        "method": "one-stat-at-a-time matched ability context; mean per-fight context rate; bootstrap over independent fight rates",
        "outcome_unit": "observed matched-target ability amount per elapsed fight second; mean event amount is secondary; not full-character DPS/HPS; healing is not effective healing",
        "luck_method": "Luck is compared across all Normal+Critical hits for the same ability; other stats are compared in separate Normal/Critical strata",
        "minimum_stat_step": MIN_STAT_STEP,
        "minimum_fights_per_build": MIN_FIGHTS_PER_BUILD,
        "minimum_events_per_fight_context": MIN_EVENTS_PER_FIGHT_CONTEXT,
        "max_stat_snapshot_age_seconds": MAX_STAT_SNAPSHOT_AGE_SECONDS,
        "bootstrap_replicates": BOOTSTRAP_REPLICATES,
        "input_event_rows": len(rows),
        "validated_event_rows_before_contamination": validated_event_rows,
        "strict_valid_event_rows": strict_valid_event_rows,
        "legacy_exploratory_event_rows": legacy_exploratory_event_rows,
        "contaminated_event_rows_excluded": contaminated_event_rows,
        "included_events": included_events,
        "included_luck_all_hit_events": included_luck_all_hit_events,
        "total_comparisons": len(comparisons),
        "strict_comparison_count": strict_comparison_count,
        "legacy_exploratory_comparison_count": legacy_exploratory_comparison_count,
        "legacy_policy": "v1 rows with missing target identity or snapshot age are retained only as legacy_exploratory and forced to VERY_LOW confidence; never merge with strict results",
        "excluded_or_unusable": dict(sorted(skipped.items())),
        "contaminated_fights_excluded": len(contaminated_fights),
        "insufficient_repeated_pairs": insufficient_pairs,
        "comparisons": comparisons,
        "limitations": [
            "actor_id/target_id сохраняются как instance IDs. Между разными экземплярами допускается сопоставление только при полном entity signature (имя + уровень + элитность + признак моба); signature является приближённым archetype key, а не уникальным server template ID.",
            "Entity signature может объединить разные варианты с одинаковым именем, уровнем и элитностью; target HP max order, ability, HP band, Resolve band, element и остальные strata дополнительно ограничивают совпадение, но скрытые состояния цели всё ещё могут различаться.",
            "Баффы, дебаффы, аспект, таланты, ротация и состав группы не сохраняются по каждому событию; скрытое смешение условий остаётся возможным.",
            "ME учитывает rate matched ability context по таймеру боя; это не DPS всего персонажа и зависит от использования способности/ротации.",
            "Для лечения сравнивается reported healing rate, не Effective HPS: callback не содержит достоверный overheal для всех событий.",
            "Снимок статов обновляется не чаще одного раза в 3 секунды. Переключение статов и возврат к исходным значениям между двумя снимками может остаться незамеченным.",
            "Legacy v1 rows without actor_id/target_id or stat_sample_age form a separate exploratory comparison tier with VERY_LOW confidence; it is not strict target-matched evidence.",
            "Строгое сравнение использует только строки со stat_sample_age не старше 3 секунд.",
            "ME рассчитана только при изменении одной характеристики; остальные сохранённые характеристики должны оставаться в допуске.",
            "Результат DERIVED и controlled-observational, но не доказывает причинность."
        ],
    }


def resistance_family(element: str) -> str | None:
    value = (element or "").lower().replace("enum_subelement_", "").replace("enum_subelement", "")
    return calc.SCHOOLS.get(value)


def tank_event_to_sample(
    row: dict[str, str],
    stats: dict[str, float],
) -> tuple[dict[str, Any] | None, str | None, str | None, float | None]:
    """Reconstruct only events with a separately reported resistance component.

    Other direct reduction components are not added together: events with any
    positive block/parry/barrier/absorb/mount field are excluded because these
    may overlap and would make the incoming base ambiguous.
    """
    if (row.get("kind") or "").strip().lower() != "incoming":
        return None, None, None, None
    amount = number(row.get("observed_amount"))
    hp = number(row.get("target_hp_before"))
    quality = (row.get("hp_quality") or "").strip()
    resist = number(row.get("resist"))
    rune = number(row.get("runes_absorb")) or 0.0
    school = resistance_family(row.get("element") or "")
    if amount is None or amount <= 0:
        return None, "incoming_amount_missing_or_fully_prevented", None, None
    if hp is None or quality not in PRE_HP_QUALITIES:
        return None, "incoming_hp_unknown", None, None
    if resist is None:
        return None, "resistance_component_unknown", None, None
    if not school:
        return None, "damage_school_unknown", None, None

    other_components = ("block", "parry", "barrier", "absorb", "mount")
    positive = [key for key in other_components if (number(row.get(key)) or 0.0) > 0.0]
    if positive:
        return None, "overlapping_defense_components:" + ",".join(positive), None, None

    hp_fraction = max(0.0, min(1.0, hp / 100.0))
    caution = calc.caution_multiplier(stats.get("caution", 0.0), hp_fraction)
    # amount is observed after Caution. Undo it before reversing the separately
    # measured rune and resistance reductions, so the simulator can reapply Caution.
    after_caution = amount / max(1e-12, caution)
    after_resist = after_caution + rune
    raw_before_resist = after_resist + resist
    if after_resist <= 0 or raw_before_resist <= 0:
        return None, "incoming_reconstruction_failed", None, None
    inferred_rating = raw_before_resist * 10.0 / after_resist
    if not math.isfinite(inferred_rating) or inferred_rating <= 0:
        return None, "incoming_resistance_invalid", None, None

    sample = {
        "second": int(number(row.get("second")) or 0),
        "actor_id": row.get("actor_id") or "unknown",
        "target_id": row.get("target_id") or "unknown",
        "incoming_raw": raw_before_resist,
        "player_hp": hp_fraction,
        "damage_school": (row.get("element") or "").replace("ENUM_SubElement_", ""),
        "rune_absorbed": rune,
        "ability": row.get("ability") or "unknown",
    }
    return sample, None, school, inferred_rating


def event_to_sample(
    row: dict[str, str],
    stats: dict[str, float],
    coefficient: float,
    mode: str,
) -> tuple[dict[str, Any] | None, str | None]:
    amount = number(row.get("observed_amount"))
    hp_percent = number(row.get("target_hp_before"))
    pool = number(row.get("resolve_pool"))
    quality = (row.get("hp_quality") or "").strip()
    if amount is None or amount <= 0:
        return None, "amount_missing"
    if hp_percent is None or quality not in PRE_HP_QUALITIES:
        return None, "target_hp_before_unknown"
    if pool is None:
        return None, "resolve_pool_unknown"

    hp_fraction = max(0.0, min(1.0, hp_percent / 100.0))
    m_mult = calc.mastery_multiplier(stats["mastery"])
    r_mult = calc.resolve_multiplier(stats["resolve"], pool, coefficient)
    u_mult = calc.ruthlessness_multiplier(stats["ruthlessness"], hp_fraction)

    critical_text = (row.get("critical") or "").strip()
    if critical_text == "1":
        actual_crit = 2.0
        critical: bool | None = True
    elif critical_text == "0":
        actual_crit = 1.0
        critical = False
    else:
        actual_crit = 1.0 + calc.crit_chance(stats["luck"])
        critical = None

    rune_absorbed = number(row.get("runes_absorb")) or 0.0
    if mode == "hps":
        rune_absorbed = 0.0
        target_max_hp = number(row.get("target_max_hp"))
        if target_max_hp is None or target_max_hp <= 0:
            return None, "target_max_hp_unknown"
        # The API value is applied healing. Treating it as the nominal baseline
        # is conservative when the original cast may already have been capped.
        raw = amount / max(1e-12, m_mult * r_mult * u_mult * actual_crit)
    else:
        target_max_hp = number(row.get("target_max_hp"))
        # Rune absorption is reported as an absolute amount before Ruthlessness.
        # Re-add it while undoing the current stat multipliers, then apply it
        # again in the calculator so it is not double-counted.
        raw = (amount / max(1e-12, u_mult) + rune_absorbed) / max(
            1e-12, m_mult * r_mult * actual_crit
        )

    if not math.isfinite(raw) or raw <= 0:
        return None, "normalization_failed"

    sample: dict[str, Any] = {
        "second": int(number(row.get("second")) or 0),
        "actor_id": row.get("actor_id") or "unknown",
        "target_id": row.get("target_id") or "unknown",
        "raw": raw,
        "target_hp": hp_fraction,
        "resolve_pool": max(0.0, min(100.0, pool)),
        "replay_resolve": False,
        "ability": row.get("ability") or "unknown",
        "damage_school": row.get("element") or "",
    }
    if critical is not None:
        sample["critical"] = critical
    if mode == "dps" and rune_absorbed > 0:
        sample["rune_absorbed"] = rune_absorbed
    if mode == "hps":
        sample["target_max_hp"] = target_max_hp
        sample["recipient"] = (row.get("recipient") or "unknown").strip().lower()
    return sample, None


def build_profile(
    rows: list[dict[str, str]],
    allocation_budget: int,
    resolve_coefficient: float,
) -> dict[str, Any]:
    outgoing_rows = [
        row for row in rows
        if (row.get("kind") or "").strip().lower() in {"damage", "healing"}
    ]
    incoming_rows = [
        row for row in rows
        if (row.get("kind") or "").strip().lower() == "incoming"
    ]
    combat_rows = outgoing_rows + incoming_rows
    if not outgoing_rows and not incoming_rows:
        raise ValueError("В CSV нет событий damage/healing/incoming.")

    stats = stat_signature(combat_rows)
    defense_stats = {
        "fortitude": optional_stat_signature(combat_rows, "S", "Стойкость"),
        "will": optional_stat_signature(combat_rows, "W", "Воля"),
        "bloodthirst": optional_stat_signature(combat_rows, "B", "Кровожадность"),
        "caution": optional_stat_signature(combat_rows, "C", "Осторожность"),
        "endurance": 0.0,  # class base coefficient is not present in the event callback
    }
    max_hp = optional_stat_signature(combat_rows, "HPmax", "максимальное здоровье")
    if max_hp > 0:
        defense_stats["max_hp"] = max_hp
    stats.update(defense_stats)

    groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    skipped: Counter[str] = Counter()
    tank_rows_by_fight: dict[str, list[tuple[dict[str, Any], str, float]]] = defaultdict(list)
    resistance_samples: dict[str, list[tuple[float, float]]] = defaultdict(list)

    for row in combat_rows:
        kind = (row.get("kind") or "").strip().lower()
        fight_id = (row.get("fight_id") or "unknown").strip()
        profile_name = (row.get("profile") or "unknown").strip()
        if kind == "incoming":
            sample, reason, school, rating = tank_event_to_sample(row, event_stats(row, stats))
            if reason:
                skipped[reason] += 1
                continue
            assert sample is not None and school is not None and rating is not None
            tank_rows_by_fight[fight_id].append((sample, profile_name, rating))
            # Weight the inferred school rating by pre-resistance damage, not by event count.
            resistance_samples[school].append((rating, sample["incoming_raw"]))
            continue

        mode = "dps" if kind == "damage" else "hps"
        sample, reason = event_to_sample(row, event_stats(row, stats), resolve_coefficient, mode)
        if reason:
            skipped[reason] += 1
            continue
        groups[(fight_id, mode)].append({
            "sample": sample,
            "profile": profile_name,
            "observed_amount": number(row.get("observed_amount")) or 0.0,
        })

    activities: dict[str, Any] = {}
    included = 0
    for (fight_id, mode), entries in sorted(groups.items()):
        if not entries:
            continue
        name = f"{entries[0]['profile']}_fight_{fight_id}_{mode}"
        samples = [entry["sample"] for entry in entries]
        if mode == "hps":
            # The recipient is recorded for the recipient-specific report.
            samples = [sample for sample in samples if sample.get("recipient") in {"self", "ally"}]
            if not samples:
                skipped["heals_without_self_or_ally_tag"] += len(entries)
                continue
        activities[name] = {"mode": mode, "weight": 1.0, "samples": samples}
        included += len(samples)

    resistance_ratings: dict[str, float] = {}
    for school, samples in resistance_samples.items():
        total_weight = sum(weight for _, weight in samples)
        if total_weight > 0:
            resistance_ratings[school] = sum(rating * weight for rating, weight in samples) / total_weight
    stats["resistances"] = resistance_ratings
    stats.update(resistance_ratings)

    outgoing_per_second: dict[tuple[str, int], float] = defaultdict(float)
    for (fight_id, mode), entries in groups.items():
        if mode == "dps":
            for entry in entries:
                sec = int(entry["sample"]["second"])
                outgoing_per_second[(fight_id, sec)] += entry["observed_amount"]

    for fight_id, entries in tank_rows_by_fight.items():
        if not entries:
            continue
        counts: Counter[int] = Counter(sample["second"] for sample, _, _ in entries)
        tank_samples = []
        for sample, _, _ in entries:
            sec = int(sample["second"])
            # Divide the real outgoing damage of that second across incoming events
            # to avoid multiplying one second of Bloodthirst return by event count.
            sample["outgoing_damage"] = outgoing_per_second.get((fight_id, sec), 0.0) / max(1, counts[sec])
            tank_samples.append(sample)
        activities[f"tank_fight_{fight_id}"] = {"mode": "tank", "weight": 1.0, "samples": tank_samples}
        included += len(tank_samples)

    if not activities:
        raise ValueError(
            "После фильтрации не осталось пригодных событий. "
            f"Причины исключения: {dict(skipped)}"
        )

    profile_names = sorted({(row.get("profile") or "unknown").strip() for row in combat_rows})
    warnings = [
        "События нормализованы из итоговой величины callback, а не из сырой базовой силы умения.",
        "Защита: в tank-профиль включаются события с HP до удара, отдельным полем resist и без положительных других прямых компонентов, чтобы не суммировать перекрывающиеся поглощения.",
        "Резист по группе выведен из observed damage + отдельно сообщённый resist + rune absorb; он остаётся оценкой API-компонентов, а не отдельным снимком рейтинга сопротивления.",
        "Стойкость, Воля, Кровожадность и Осторожность берутся из снимка S/W/B/C. Базовый классный коэффициент Выносливости не присутствует в callback; используется измеренное HP и относительное влияние Стойкости.",
        "Для tank-профиля кровожадность использует реальный исходящий урон за ту же секунду, распределённый между входящими событиями этой секунды.",
        "Неизвестные сопротивления цели, блок/парирование и осторожность цели остаются частью веса конкретного события.",
        "Наблюдаемый пул Решимости зафиксирован отдельно на каждом событии; его обратная динамика при изменении статов не пересчитывается.",
        "Для лечения исходная величина callback рассматривается как номинальная базовая величина; если исходное лечение уже было ограничено недостающим HP, рекомендация будет консервативной.",
    ]
    stat_ranges = {}
    for key, label in ALL_STAT_COLUMNS.items():
        values = [number(row.get(key)) for row in combat_rows]
        values = [value for value in values if value is not None]
        if values and max(values) - min(values) > 0.5:
            stat_ranges[label] = {"min": min(values), "max": max(values), "distinct_rounded": len({round(value, 1) for value in values})}
    if stat_ranges:
        warnings.append("Характеристики менялись в журнале; каждое событие нормализовано по собственному снимку статов. Для сводного оптимизатора используются медианные характеристики. Диапазоны: " + json.dumps(stat_ranges, ensure_ascii=False))
    if skipped:
        warnings.append("Исключено событий по причине: " + ", ".join(f"{key}={value}" for key, value in sorted(skipped.items())))

    controlled_efficiency = analyze_controlled_stat_efficiency(combat_rows)
    temporal_performance = build_temporal_performance(combat_rows)
    event_effectiveness = build_event_effectiveness(combat_rows)
    critical_analysis = build_critical_analysis(combat_rows)

    return {
        "settings": {
            "level": 1,
            "max_hp": max_hp,
            "base_stats": dict(stats),
            "might": 20,
            "might_source": "assumed_default",
            "power_scale": 10,
            "resolve_coefficient": resolve_coefficient,
            "might_affects_healing": True,
            "freeze_resolve_pool": True,
            "allow_nominal_hps_optimization": False,
            "mode": profile_names[0] if len(profile_names) == 1 else "mixed",
        },
        "stats": stats,
        "fixed_stats": dict(stats),
        "allocation_budget": allocation_budget,
        "activities": activities,
        "stat_comparison": compare_stat_sets(combat_rows),
        "temporal_performance": temporal_performance,
        "event_effectiveness": event_effectiveness,
        "critical_analysis": critical_analysis,
        "controlled_stat_efficiency": controlled_efficiency,
        "import_warnings": warnings,
        "import_summary": {
            "source_rows": len(rows),
            "combat_rows": len(combat_rows),
            "ignored_non_combat_rows": len(rows) - len(combat_rows),
            "included_events": included,
            "skipped_events": dict(skipped),
            "profiles": profile_names,
            "activities": len(activities),
            "outgoing_events": len(outgoing_rows),
            "incoming_events": len(incoming_rows),
            "resistance_families": sorted(resistance_ratings),
            "stat_comparison": compare_stat_sets(combat_rows),
            "temporal_fight_reports": len(temporal_performance["fights"]),
            "event_effectiveness_groups": len(event_effectiveness["fights"]),
            "critical_analysis_groups": len(critical_analysis["groups"]),
            "controlled_stat_comparisons": len(controlled_efficiency["comparisons"]),
            "controlled_stat_analysis_status": controlled_efficiency["status"],
            "contaminated_fights_excluded": controlled_efficiency["contaminated_fights_excluded"],
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert DPScope event CSV into a formula-calculator profile.")
    parser.add_argument("csv_file", type=Path, help="CSV downloaded from AoU_ChatLog_To_CSV.html")
    parser.add_argument("--out", type=Path, default=Path("aou_event_profile.json"))
    parser.add_argument("--budget", type=int, default=20, help="free points to distribute (default: 20)")
    parser.add_argument("--resolve-coefficient", type=float, default=0.015, choices=(0.015, 0.0015))
    args = parser.parse_args()

    rows = read_csv(args.csv_file)
    profile = build_profile(rows, max(0, min(500, args.budget)), args.resolve_coefficient)
    args.out.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Профиль сохранён: {args.out}")
    print(json.dumps(profile["import_summary"], ensure_ascii=False, indent=2))
    print("Коэффициент Решимости:", args.resolve_coefficient)
    print("Данные ограничены доступными полями callback; см. import_warnings в JSON.")


if __name__ == "__main__":
    main()
