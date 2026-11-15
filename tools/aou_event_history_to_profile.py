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
    skipped: Counter[str] = Counter()

    for row in rows:
        kind = (row.get("kind") or "").strip().lower()
        if kind not in {"damage", "healing", "incoming"}:
            continue
        profile = (row.get("profile") or "").strip().lower()
        if profile not in {"pve", "pvp"}:
            skipped["profile_unknown_or_not_classified"] += 1
            continue
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
        base_stratum = (
            kind, profile, duration, ability.lower(), element, damage_source.lower(),
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
            kind, profile, duration, ability, element, damage_source, hp_band, hp_quality, hp_scale, resolve_band, crit, recipient = stratum
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
                        effect_per_100 = (test_mean - baseline_mean) * 100.0 / delta
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
                        # Unlogged target identity and combat modifiers prevent HIGH causal
                        # confidence, even when the bootstrap interval is narrow.
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
                            "duration_band": duration,
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
                            "marginal_efficiency_per_100": round(effect_per_100, 4),
                            "marginal_efficiency_unit": "reported amount per second per +100 stat points",
                            "mean_event_amount_delta_per_100": round((test_event_mean - baseline_event_mean) * 100.0 / delta, 4),
                            "relative_change_per_100_percent": round(relative_per_100, 4) if relative_per_100 is not None else None,
                            "confidence_interval_95_per_100": ci,
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
        "outcome_unit": "observed matched-context amount per elapsed fight second; mean event amount is secondary; not full-character DPS/HPS; healing is not effective healing",
        "luck_method": "Luck is compared across all Normal+Critical hits for the same ability; other stats are compared in separate Normal/Critical strata",
        "minimum_stat_step": MIN_STAT_STEP,
        "minimum_fights_per_build": MIN_FIGHTS_PER_BUILD,
        "minimum_events_per_fight_context": MIN_EVENTS_PER_FIGHT_CONTEXT,
        "bootstrap_replicates": BOOTSTRAP_REPLICATES,
        "included_events": included_events,
        "included_luck_all_hit_events": sum(
            len(values)
            for builds in contexts_all_hits.values()
            for fights in builds.values()
            for values in fights.values()
        ),
        "excluded_or_unusable": dict(sorted(skipped.items())),
        "contaminated_fights_excluded": len(contaminated_fights),
        "insufficient_repeated_pairs": insufficient_pairs,
        "comparisons": comparisons[:100],
        "limitations": [
            "Цели не имеют отдельного target_id в текущей версии журнала; одинаковое имя способности и HP-диапазон не гарантируют одну и ту же цель.",
            "Баффы, дебаффы, аспект, таланты, ротация и состав группы не сохраняются по каждому событию; скрытое смешение условий остаётся возможным.",
            "ME учитывает rate matched ability context по таймеру боя; это не DPS всего персонажа и зависит от использования способности/ротации.",
            "Для лечения сравнивается reported healing rate, не Effective HPS: callback не содержит достоверный overheal для всех событий.",
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

    return {
        "settings": {
            "level": 1,
            "max_hp": max_hp,
            "base_stats": dict(stats),
            "might": 20,
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
        "controlled_stat_efficiency": controlled_efficiency,
        "import_warnings": warnings,
        "import_summary": {
            "source_rows": len(combat_rows),
            "included_events": included,
            "skipped_events": dict(skipped),
            "profiles": profile_names,
            "activities": len(activities),
            "outgoing_events": len(outgoing_rows),
            "incoming_events": len(incoming_rows),
            "resistance_families": sorted(resistance_ratings),
            "stat_comparison": compare_stat_sets(combat_rows),
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
