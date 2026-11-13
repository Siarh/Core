# -*- coding: utf-8 -*-
"""DPScope formula calculator for the user-supplied Allods 7.0/Sunshine model.

Input is a JSON profile with per-event samples. This program is an offline
calculator; it does not read game memory or claim that every API field is
available in the live addon.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

SCHOOLS = {
    "physical": "armor", "armor": "armor",
    "fire": "elements", "cold": "elements", "lightning": "elements",
    "elements": "elements",
    "holy": "divine", "shadow": "divine", "astral": "divine",
    "divine": "divine",
    "poison": "nature", "disease": "nature", "acid": "nature",
    "nature": "nature",
}


def num(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def round_game(value: float) -> int:
    """Positive-number equivalent of the game's round(x) convention."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def level_multiplier(level: float) -> float:
    return 1.14 ** ((num(level, 1.0) - 1.0) * 0.2)


def mastery_multiplier(stat: float) -> float:
    stat = num(stat)
    return 1.0 + stat / 1000.0 if stat >= 0 else 1.0 / (1.0 + abs(stat) / 1000.0)


def softened_stat(stat: float) -> float:
    stat = clamp(num(stat), 0.0, 850.0)
    if stat <= 500:
        return stat
    ratio = 500.0 / stat
    return 500.0 + (stat - 500.0) * 0.7 * (
        ratio + 0.25 * ratio**5 - 0.5 * ratio**3
    )


def crit_chance(stat: float) -> float:
    """Probability as a fraction; one effective point = 0.1 percentage point."""
    return clamp(softened_stat(stat) / 1000.0, 0.0, 1.0)


def ruthlessness_m(stat: float) -> float:
    x = max(0.0, num(stat)) / 1000.0
    if x <= 1e-12:
        return 0.0
    target = 1.0 + x

    def fn(m: float) -> float:
        return m / math.log1p(m) if m > 1e-12 else 1.0

    lo, hi = 0.0, max(1.0, 2.0 * x)
    while fn(hi) < target:
        hi *= 2.0
    for _ in range(90):
        mid = (lo + hi) / 2.0
        if fn(mid) < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def ruthlessness_multiplier(stat: float, target_hp: float) -> float:
    hp = clamp(num(target_hp, 1.0), 0.0, 1.0)
    return 1.0 + ruthlessness_m(stat) * (1.0 - hp)


def resolve_multiplier(stat: float, pool: float, coefficient: float) -> float:
    return 1.0 + num(stat) / 1000.0 * clamp(num(pool), 0.0, 100.0) * num(coefficient)


def resolve_k(pool: float) -> float:
    pool = clamp(num(pool), 0.0, 100.0)
    if pool < 50:
        return 0.35
    if pool < 60:
        return 0.30
    if pool < 70:
        return 0.18
    if pool < 80:
        return 0.15
    return 0.10


def resolve_gain(raw_amount: float, max_hp: float, multiplier: float, pool: float) -> int:
    """Pool += round(416.7 * (actual / multiplier) / maxHP * k(pool)).

    'multiplier' is the complete event multiplier. Since actual = raw*multiplier,
    actual/multiplier recovers the pre-multiplier event amount. It can be
    supplied directly per event as resolve_divisor_multiplier when known.
    """
    if max_hp <= 0 or multiplier <= 0:
        return 0
    base_amount = max(0.0, raw_amount) / multiplier
    return max(0, round_game(416.7 * base_amount / max_hp * resolve_k(pool)))


def resolve_decay(pool: float) -> int:
    return math.floor(clamp(num(pool), 0.0, 100.0) * 0.9)


def bloodthirst_fraction(stat: float) -> float:
    x = max(0.0, num(stat)) / 1000.0
    return x / (x + 1.8) if x > 0 else 0.0


def caution_multiplier(stat: float, hp_fraction: float) -> float:
    if num(hp_fraction, 1.0) >= 0.40:
        return 1.0
    return 1.0 - clamp(num(stat), 0.0, 350.0) / 1000.0


def resistance_multiplier(rating: float) -> float:
    rating = num(rating, 10.0)
    if rating <= 0:
        raise ValueError("Сопротивление R должно быть > 0; нейтральное значение R=10")
    return 10.0 / rating


def will_result(stat: float) -> dict[str, Any]:
    w = max(0.0, num(stat))
    if w <= 0:
        return {"gain_percent_per_full_second": 0, "seconds_to_immunity": None, "immunity_seconds": 4}
    p = min(900.0, 1.6 * w / (1.0 + w**1.05 / 1000.0)) / 1000.0
    if p <= 0:
        return {"gain_percent_per_full_second": 0, "seconds_to_immunity": None, "immunity_seconds": 4}
    t = (p / 0.05) ** 0.75
    denominator = t / p - t
    if denominator <= 0:
        return {"gain_percent_per_full_second": 0, "seconds_to_immunity": None, "immunity_seconds": 4}
    gain = math.ceil(150.0 / denominator)
    return {
        "gain_percent_per_full_second": gain,
        "seconds_to_immunity": math.ceil(100.0 / gain),
        "immunity_seconds": 4,
    }


def endurance_health(level: float, class_k: float, endurance: float, fortitude: float) -> float:
    if num(class_k) <= 0:
        raise ValueError("Для расчёта здоровья по Выносливости требуется settings.class_k")
    return (
        num(class_k) / 2.0 * max(0.0, num(endurance))
        * level_multiplier(level)
        * (1.0 + num(fortitude) / 1000.0)
    )


def _school_key(event: dict[str, Any]) -> str | None:
    school = str(event.get("damage_school", event.get("school", ""))).lower()
    return SCHOOLS.get(school)


def _event_resistance(event: dict[str, Any], cfg: dict[str, Any]) -> float:
    school = _school_key(event)
    per_school = event.get("target_resistances") or cfg.get("target_resistances") or {}
    if school and school in per_school:
        return num(per_school[school], 10.0)
    return num(event.get("target_resistance", event.get("resistance", cfg.get("default_target_resistance", 10))), 10.0)


def _reduction_after_resist(amount: float, event: dict[str, Any]) -> tuple[float, float, float, float]:
    """Apply block/parry and separately reported rune absorption without double counting."""
    block = clamp(num(event.get("block_fraction")), 0.0, 1.0)
    parry = clamp(num(event.get("parry_fraction")), 0.0, 1.0)
    before_runes = amount * (1.0 - block) * (1.0 - parry)
    if event.get("rune_absorbed") is not None:
        rune_abs = clamp(num(event.get("rune_absorbed")), 0.0, before_runes)
    else:
        rune_abs = before_runes * clamp(num(event.get("rune_absorb_fraction")), 0.0, 1.0)
    after = max(0.0, before_runes - rune_abs)
    return after, amount * block, amount * (1.0 - block) * parry, rune_abs


def _target_missing_hp(event: dict[str, Any]) -> float | None:
    maximum = num(event.get("target_max_hp"), 0.0)
    if maximum > 0 and event.get("target_hp") is not None:
        return maximum * (1.0 - clamp(num(event["target_hp"]), 0.0, 1.0))
    if event.get("missing_hp") is not None:
        return max(0.0, num(event["missing_hp"]))
    return None


def calculate_event(event: dict[str, Any], mode: str, stats: dict[str, Any], cfg: dict[str, Any], pool: float, expected_crit: bool = False) -> dict[str, Any]:
    """Calculate one outgoing damage/heal event. 'raw' is pre-formula amount."""
    raw = max(0.0, num(event.get("raw")))
    pool_used = clamp(num(event.get("resolve_pool", pool)), 0.0, 100.0)
    target_hp = clamp(num(event.get("target_hp", 1.0), 1.0), 0.0, 1.0)

    might = num(stats.get("might", cfg.get("might", 20.0)), 20.0)
    power_scale = num(event.get("power_scale", cfg.get("power_scale", 10.0)), 10.0)
    use_might = mode == "dps" or bool(cfg.get("might_affects_healing", True))
    might_mult = (might / 20.0) * level_multiplier(cfg.get("level", 1.0)) * (power_scale / 10.0) if use_might else 1.0
    m_mult = mastery_multiplier(stats.get("mastery", 0.0))
    r_mult = resolve_multiplier(
        stats.get("resolve", 0.0), pool_used,
        cfg.get("resolve_coefficient", 0.015),
    )
    # Ruthlessness is applied after resistance, block/parry and measured rune
    # absorption, matching the supplied hit sequence. This matters when rune_absorbed
    # is an absolute amount rather than a percentage.
    u_mult = ruthlessness_multiplier(stats.get("ruthlessness", 0.0), target_hp)
    if "critical" in event and not expected_crit:
        crit_mult = 2.0 if bool(event["critical"]) else 1.0
        crit_basis = "event"
    else:
        crit_mult = 1.0 + crit_chance(stats.get("luck", 0.0))
        crit_basis = "expected"

    resistance = _event_resistance(event, cfg)
    resist_mult = resistance_multiplier(resistance) if mode == "dps" else 1.0
    base_after_stats = raw * might_mult * m_mult * r_mult * crit_mult
    after_resist = base_after_stats * resist_mult
    after_block, blocked, parried, rune_absorbed = _reduction_after_resist(after_resist, event)
    # The user-supplied order places Ruthlessness after block/parry. Keep rune
    # absorption upstream as well, so a fixed absorbed amount is not amplified.
    after_ruthlessness = after_block * u_mult
    caution = caution_multiplier(event.get("target_caution", 0.0), target_hp) if mode == "dps" else 1.0
    amount = after_ruthlessness * caution

    wound_absorb = max(0.0, num(event.get("healing_absorb", event.get("wound_absorb", 0.0)))) if mode == "hps" else 0.0
    effective = None
    overheal = None
    if mode == "hps":
        healable = max(0.0, amount - wound_absorb)
        if event.get("effective_heal_fraction") is not None:
            fraction = clamp(num(event["effective_heal_fraction"]), 0.0, 1.0)
            effective = min(healable, amount * fraction)
            overheal = max(0.0, healable - effective)
        else:
            available = _target_missing_hp(event)
            if available is not None:
                effective = min(healable, available)
                overheal = max(0.0, healable - effective)
            elif event.get("effective_heal") is not None and event.get("observed_nominal") is not None:
                observed_nominal = num(event.get("observed_nominal"))
                if observed_nominal > 0:
                    fraction = clamp(num(event["effective_heal"]) / observed_nominal, 0.0, 1.0)
                    effective = min(healable, amount * fraction)
                    overheal = max(0.0, healable - effective)
            elif event.get("effective_heal") is not None:
                # Useful as a historical measured value, but not enough to
                # recalculate healing under alternative stat allocations.
                effective = clamp(num(event["effective_heal"]), 0.0, healable)
                overheal = max(0.0, healable - effective)

    bt_base = amount * bloodthirst_fraction(stats.get("bloodthirst", 0.0))
    bt_return = bt_base / 3.0 if mode == "hps" else bt_base

    fury_absorb = 0.0
    if mode == "dps" and bool(event.get("target_is_player")) and bool(event.get("in_combat", True)):
        fury_absorb = amount * 0.00375 * softened_stat(stats.get("fury", 0.0))

    full_multiplier = amount / raw if raw > 0 else 1.0
    return {
        "raw": raw, "nominal": amount, "effective": effective, "overheal": overheal,
        "healing_absorb": wound_absorb, "bloodthirst_return": bt_return,
        "fury_healing_absorption": fury_absorb,
        "resolve_pool_used": pool_used,
        "resolve_multiplier": r_mult, "mastery_multiplier": m_mult,
        "ruthlessness_multiplier": u_mult, "might_level_multiplier": might_mult,
        "crit_multiplier": crit_mult, "crit_basis": crit_basis,
        "target_resistance": resistance, "resistance_multiplier": resist_mult,
        "blocked": blocked, "parried": parried, "rune_absorbed": rune_absorbed,
        "caution_multiplier": caution,
        "full_multiplier": full_multiplier,
    }


def _max_hp(stats: dict[str, Any], cfg: dict[str, Any], baseline_stats: dict[str, Any] | None = None) -> float:
    level = num(cfg.get("level", 1.0), 1.0)
    if num(cfg.get("class_k")) > 0:
        return endurance_health(level, cfg["class_k"], stats.get("endurance", 0), stats.get("fortitude", 0))
    measured = num(cfg.get("max_hp"), 0.0)
    if measured <= 0:
        return 0.0
    base = baseline_stats or cfg.get("base_stats") or stats
    base_f = num(base.get("fortitude", 0.0))
    base_e = num(base.get("endurance", 0.0))
    new_f = num(stats.get("fortitude", base_f))
    new_e = num(stats.get("endurance", base_e))
    hp = measured
    if 1.0 + base_f / 1000.0 > 0:
        hp *= (1.0 + new_f / 1000.0) / (1.0 + base_f / 1000.0)
    if base_e > 0:
        hp *= max(0.0, new_e) / base_e
    elif new_e > 0 and base_e == 0:
        # Cannot infer a baseline endurance contribution from measured HP alone.
        pass
    return hp


def calculate_incoming(event: dict[str, Any], stats: dict[str, Any], cfg: dict[str, Any]) -> dict[str, Any]:
    raw = max(0.0, num(event.get("incoming_raw", event.get("raw", 0.0))))
    school = _school_key(event)
    resistances = stats.get("resistances", {}) or {}
    rating = num(event.get("player_resistance", stats.get(school, resistances.get(school, cfg.get("default_player_resistance", 10)))), 10.0)
    resist_mult = resistance_multiplier(rating)
    after_resist = raw * resist_mult
    after_block, blocked, parried, rune_absorbed = _reduction_after_resist(after_resist, event)
    player_hp = clamp(num(event.get("player_hp", 1.0), 1.0), 0.0, 1.0)
    caution = caution_multiplier(stats.get("caution", 100.0), player_hp)
    taken = after_block * caution
    outgoing = max(0.0, num(event.get("outgoing_damage", 0.0)))
    bt = outgoing * bloodthirst_fraction(stats.get("bloodthirst", 0.0))
    return {
        "raw_incoming": raw, "after_resistance": after_resist,
        "incoming_after_defense": taken,
        "resistance_rating": rating, "resistance_multiplier": resist_mult,
        "resistance_reduction": raw - after_resist,
        "blocked": blocked, "parried": parried, "rune_absorbed": rune_absorbed,
        "caution_multiplier": caution, "bloodthirst_return": bt,
    }


def _objective(result: dict[str, Any], mode: str, cfg: dict[str, Any]) -> tuple[float | None, str]:
    if mode == "dps":
        return num(result.get("total_damage")), "total_damage"
    if mode == "hps":
        count = result.get("events", 0)
        coverage = result.get("effective_heal_events", 0)
        optimization_coverage = result.get("effective_heal_optimization_events", 0)
        if count > 0 and coverage == count and optimization_coverage == count:
            score = num(result.get("effective_heal_total"))
            score += num(cfg.get("healer_bloodthirst_weight", 0.0)) * num(result.get("bloodthirst_return"))
            return score, "effective_heal_plus_weighted_self_sustain"
        if bool(cfg.get("allow_nominal_hps_optimization", False)):
            return num(result.get("nominal_heal_total")), "nominal_heal_fallback"
        return None, "effective_heal_data_incomplete"
    if mode == "tank":
        survival = result.get("survival_seconds")
        if survival is None:
            return None, "survival_seconds_unavailable"
        control_weight = num(cfg.get("control_weight", 0.0))
        score_value = float(survival) - control_weight * num(result.get("estimated_control_seconds", 0.0))
        return score_value, "survival_seconds_minus_weighted_control" if control_weight > 0 else "survival_seconds"
    return None, "unsupported_mode"


def simulate(activity: dict[str, Any], stats: dict[str, Any], cfg: dict[str, Any], expected_crit: bool = False) -> dict[str, Any]:
    mode = str(activity.get("mode", "dps")).lower()
    if mode not in ("dps", "hps", "tank"):
        raise ValueError("mode должен быть dps, hps или tank")
    samples = activity.get("samples", [])
    if not isinstance(samples, list):
        raise ValueError("activity.samples должен быть массивом")
    if not samples:
        return {
            "mode": mode, "events": 0, "seconds": 0,
            "warnings": ["Нет событий для расчёта."]
        }

    grouped: dict[int, list[dict[str, Any]]] = {}
    for index, event in enumerate(samples):
        second = int(num(event.get("second", index)))
        grouped.setdefault(second, []).append(event)
    first, last = min(grouped), max(grouped)
    duration = max(1, last - first + 1)

    pool = clamp(num(cfg.get("initial_resolve", 0.0)), 0.0, 100.0)
    owner_hp = _max_hp(stats, cfg, cfg.get("base_stats"))
    total_damage = nominal_heal = effective_heal = overheal = 0.0
    bloodthirst = fury_absorb = incoming_total = rune_total = resist_saved = 0.0
    effective_heal_events = 0
    effective_heal_optimization_events = 0
    resolve_event_values: list[float] = []
    per_second: list[dict[str, float]] = []
    phase_keys = ("100_75", "75_50", "50_25", "25_0")
    phase_labels = {"100_75": "100-75%", "75_50": "75-50%", "50_25": "50-25%", "25_0": "25-0%"}
    phases = {key: {"events": 0, "amount": 0.0, "crit_events": 0, "crit_known": 0} for key in phase_keys}
    phase_unknown_events = 0
    half_totals = [0.0, 0.0]
    half_events = [0, 0]
    half_known_events = [0, 0]
    half_seconds = [math.ceil(duration / 2), math.floor(duration / 2)]
    tank_schools: dict[str, dict[str, float]] = {}
    warnings: list[str] = []
    event_count = 0

    for sec in range(first, last + 1):
        second_total = 0.0
        second_events = grouped.get(sec, [])
        for event in second_events:
            event_count += 1
            if mode == "tank":
                calc = calculate_incoming(event, stats, cfg)
                incoming_total += calc["incoming_after_defense"]
                bloodthirst += calc["bloodthirst_return"]
                rune_total += calc["rune_absorbed"]
                resist_saved += calc["resistance_reduction"]
                school = _school_key(event) or "unknown"
                row = tank_schools.setdefault(school, {"events": 0, "raw": 0.0, "resistance_reduction": 0.0, "blocked": 0.0, "parried": 0.0, "rune_absorbed": 0.0, "after_defense": 0.0})
                row["events"] += 1
                row["raw"] += calc["raw_incoming"]
                row["resistance_reduction"] += calc["resistance_reduction"]
                row["blocked"] += calc["blocked"]
                row["parried"] += calc["parried"]
                row["rune_absorbed"] += calc["rune_absorbed"]
                row["after_defense"] += calc["incoming_after_defense"]
                half_index = 0 if (sec - first) < math.ceil(duration / 2) else 1
                half_totals[half_index] += calc["incoming_after_defense"]
                half_events[half_index] += 1
                half_known_events[half_index] += 1
                continue

            calc = calculate_event(event, mode, stats, cfg, pool, expected_crit=expected_crit)
            second_total += calc["nominal"]
            measured_known = mode == "dps" or calc["effective"] is not None
            if measured_known:
                measured_for_phase = calc["nominal"] if mode == "dps" else calc["effective"]
                half_index = 0 if (sec - first) < math.ceil(duration / 2) else 1
                half_totals[half_index] += measured_for_phase
                half_known_events[half_index] += 1
                if event.get("target_hp") is not None:
                    hp_fraction = clamp(num(event.get("target_hp")), 0.0, 1.0)
                    phase_key = "100_75" if hp_fraction >= 0.75 else "75_50" if hp_fraction >= 0.50 else "50_25" if hp_fraction >= 0.25 else "25_0"
                    phase = phases[phase_key]
                    phase["events"] += 1
                    phase["amount"] += measured_for_phase
                    if event.get("critical") is not None:
                        phase["crit_known"] += 1
                        if bool(event.get("critical")):
                            phase["crit_events"] += 1
                else:
                    phase_unknown_events += 1
            else:
                phase_unknown_events += 1
            half_index = 0 if (sec - first) < math.ceil(duration / 2) else 1
            half_events[half_index] += 1
            bloodthirst += calc["bloodthirst_return"]
            fury_absorb += calc["fury_healing_absorption"]
            rune_total += calc["rune_absorbed"]
            if mode == "dps":
                total_damage += calc["nominal"]
                resist_saved += calc["raw"] * calc["might_level_multiplier"] * calc["mastery_multiplier"] * calc["resolve_multiplier"] * calc["ruthlessness_multiplier"] * calc["crit_multiplier"] - calc["raw"] * calc["might_level_multiplier"] * calc["mastery_multiplier"] * calc["resolve_multiplier"] * calc["ruthlessness_multiplier"] * calc["crit_multiplier"] * calc["resistance_multiplier"]
            else:
                nominal_heal += calc["nominal"]
                if calc["effective"] is not None:
                    effective_heal += calc["effective"]
                    overheal += num(calc["overheal"])
                    effective_heal_events += 1
                    hp_evidence = (event.get("target_max_hp") is not None and event.get("target_hp") is not None) or event.get("missing_hp") is not None
                    ratio_evidence = event.get("effective_heal_fraction") is not None or (event.get("effective_heal") is not None and event.get("observed_nominal") is not None and num(event.get("observed_nominal")) > 0)
                    if hp_evidence or ratio_evidence:
                        effective_heal_optimization_events += 1

            # Pool grows per event, using the pool-dependent k at that event.
            if owner_hp > 0:
                supplied_divisor = num(event.get("resolve_divisor_multiplier"), 0.0)
                divisor = supplied_divisor if supplied_divisor > 0 else calc["full_multiplier"]
                gain = resolve_gain(calc["nominal"], owner_hp, divisor, pool)
                pool = min(100.0, pool + gain)
            if event.get("resolve_pool_after") is not None:
                pool = clamp(num(event["resolve_pool_after"]), 0.0, 100.0)
            if event.get("player_died") or event.get("owner_died"):
                pool = 0.0
            resolve_event_values.append(pool)

        if mode in ("dps", "hps"):
            pool = float(resolve_decay(pool))
            per_second.append({"second": sec, "event_amount": second_total, "resolve_end": pool})

    control = activity.get("control_windows", [])
    will = will_result(stats.get("will", 0.0))
    threshold = will["seconds_to_immunity"]
    control_total = 0.0
    for window in control:
        secs = max(0.0, num(window))
        control_total += min(secs, float(threshold)) if threshold is not None else secs

    phase_report = {}
    for key in phase_keys:
        item = phases[key]
        phase_report[phase_labels[key]] = {
            "events": item["events"],
            "amount": item["amount"],
            "average_per_event": item["amount"] / item["events"] if item["events"] else None,
            "critical_percent": (item["crit_events"] / item["crit_known"] * 100.0) if item["crit_known"] else None,
        }
    first_complete = half_known_events[0] == half_events[0]
    second_complete = half_known_events[1] == half_events[1]
    first_rate = (half_totals[0] / max(1, half_seconds[0])) if first_complete else None
    second_rate = (half_totals[1] / max(1, half_seconds[1])) if second_complete and half_seconds[1] else None
    stability = {
        "first_half_total_known": half_totals[0], "second_half_total_known": half_totals[1],
        "first_half_per_second": first_rate,
        "second_half_per_second": second_rate,
        "second_vs_first_percent": ((second_rate / first_rate - 1.0) * 100.0) if second_rate is not None and first_rate is not None and first_rate > 0 else None,
        "known_event_amount_spread_between_halves_percent": ((max(half_totals) - min(half_totals)) / (sum(half_totals) / 2.0) * 100.0) if sum(half_totals) > 0 else None,
        "first_half_effective_coverage_percent": (half_known_events[0] / max(1, half_events[0]) * 100.0),
        "second_half_effective_coverage_percent": (half_known_events[1] / max(1, half_events[1]) * 100.0),
        "half_seconds": half_seconds,
    }
    result: dict[str, Any] = {
        "mode": mode, "events": event_count, "seconds": duration,
        "hp_phase_breakdown": phase_report if mode in ("dps", "hps") else None,
        "hp_phase_unknown_events": phase_unknown_events if mode in ("dps", "hps") else None,
        "half_battle_stability": stability,
        "incoming_by_school": tank_schools if mode == "tank" else None,
        "bloodthirst_return": bloodthirst,
        "fury_healing_absorption": fury_absorb,
        "rune_absorbed": rune_total,
        "resistance_saved_estimate": resist_saved,
        "resolve_average_after_events": (sum(resolve_event_values) / len(resolve_event_values)) if resolve_event_values else 0.0,
        "resolve_final": pool,
        "resolve_samples": len(resolve_event_values),
        "per_second": per_second,
        "will": will,
        "estimated_control_seconds": control_total,
        "warnings": warnings,
    }

    if mode == "dps":
        result.update({"total_damage": total_damage, "per_second_damage": total_damage / duration})
    elif mode == "hps":
        coverage = effective_heal_events / max(1, event_count)
        result.update({
            "nominal_heal_total": nominal_heal,
            "effective_heal_total": effective_heal if effective_heal_events == event_count else None,
            "effective_heal_known_sum": effective_heal,
            "effective_heal_events": effective_heal_events,
            "effective_heal_optimization_events": effective_heal_optimization_events,
            "effective_heal_coverage_percent": coverage * 100.0,
            "overheal_known_sum": overheal,
            "per_second_effective_heal": (effective_heal / duration) if effective_heal_events == event_count else None,
        })
        if effective_heal_events != event_count:
            warnings.append("Не для всех событий известны effective_heal или HP до лечения; эффективный HPS и рекомендации не объявляются точными.")
    else:
        hp = owner_hp
        incoming_dps = incoming_total / duration
        sustain_dps = bloodthirst / duration
        net_dps = max(0.0, incoming_dps - sustain_dps)
        survival = (hp / net_dps) if hp > 0 and net_dps > 0 else None
        result.update({
            "max_hp_model": hp,
            "incoming_total_after_defense": incoming_total,
            "incoming_per_second": incoming_dps,
            "bloodthirst_sustain_per_second": sustain_dps,
            "net_incoming_per_second": net_dps,
            "survival_seconds": survival,
        })
        if hp <= 0:
            warnings.append("Для оценки здоровья танка укажи settings.max_hp или class_k и stats.endurance.")
        if incoming_total <= 0:
            warnings.append("Нет событий входящего урона; время выживания не оценивается.")
        if stats.get("will", 0) and not control:
            warnings.append("Воля рассчитана отдельно, но control_windows не заданы; её вклад не включён в оценку выживаемости.")

    if phase_unknown_events > 0:
        warnings.append(str(phase_unknown_events) + " событий без HP цели: для расчёта Беспощадности временно использовано нейтральное состояние 100% HP; фазовая разбивка неполная.")
    return result


def _optimizable_stats(mode: str, cfg: dict[str, Any]) -> list[str]:
    if mode == "dps":
        keys = ["mastery", "resolve", "ruthlessness", "luck"]
    elif mode == "hps":
        keys = ["mastery", "resolve", "ruthlessness", "luck"]
        # Bloodthirst is a separate self-sustain benefit, not effective group HPS.
        if num(cfg.get("healer_bloodthirst_weight", 0.0)) > 0:
            keys.append("bloodthirst")
    else:
        keys = ["fortitude", "endurance", "bloodthirst", "caution", "armor", "elements", "divine", "nature"]
        if str(cfg.get("mode", "pve")).lower() == "pvp" and num(cfg.get("control_weight", 0.0)) > 0:
            keys.append("will")
    return keys


def _score_for_optimization(activity: dict[str, Any], stats: dict[str, Any], cfg: dict[str, Any]) -> tuple[float | None, str]:
    result = simulate(activity, stats, cfg, expected_crit=True)
    mode = str(activity.get("mode", "dps")).lower()
    score_value, basis = _objective(result, mode, cfg)
    if score_value is None:
        return None, basis
    return float(score_value), basis


def optimize(activity: dict[str, Any], base_stats: dict[str, Any], budget: int, cfg: dict[str, Any]) -> dict[str, Any]:
    budget = int(clamp(num(budget), 0, 500))
    stats = dict(base_stats)
    # Promote nested resistance ratings so allocation points are added to the existing rating, not to zero.
    nested_res = dict(stats.get("resistances", {}) or {})
    for resistance_key in ("armor", "elements", "divine", "nature"):
        if resistance_key not in stats and resistance_key in nested_res:
            stats[resistance_key] = num(nested_res[resistance_key], 10.0)
    mode = str(activity.get("mode", "dps")).lower()
    candidates = _optimizable_stats(mode, cfg)
    if mode in ("dps", "hps"):
        missing_hp = sum(1 for event in activity.get("samples", []) if event.get("target_hp") is None)
        if missing_hp > 0 and "ruthlessness" in candidates:
            return {
                "status": "insufficient_data",
                "objective": "target_hp_required_for_ruthlessness",
                "reason": str(missing_hp) + " событий не содержат HP цели; оптимизация Беспощадности и общего множителя не выполняется, чтобы не считать неизвестную цель полной.",
                "added_points": {key: 0 for key in candidates},
            }
    base_score, basis = _score_for_optimization(activity, stats, cfg)
    if base_score is None:
        return {
            "status": "insufficient_data", "objective": basis,
            "reason": "Нет достаточных событий для честной оптимизации выбранной активности.",
            "added_points": {key: 0 for key in candidates},
        }
    added = {key: 0 for key in candidates}
    if budget == 0:
        final = simulate(activity, stats, cfg, expected_crit=True)
        return {"status": "no_budget", "objective": basis, "added_points": added,
                "base_score": base_score, "recommended_score": base_score, "simulation": final}

    for _ in range(budget):
        best_key, best_score = None, -math.inf
        for key in candidates:
            test = dict(stats)
            test[key] = num(test.get(key)) + 1
            try:
                candidate_score, candidate_basis = _score_for_optimization(activity, test, cfg)
            except (ValueError, OverflowError):
                candidate_score = None
            if candidate_score is not None and candidate_score > best_score:
                best_key, best_score = key, candidate_score
        if best_key is None:
            break
        stats[best_key] = num(stats.get(best_key)) + 1
        added[best_key] += 1

    final = simulate(activity, stats, cfg, expected_crit=True)
    final_score, final_basis = _objective(final, mode, cfg)
    delta = ((final_score / base_score) - 1.0) * 100.0 if final_score is not None and base_score > 0 else 0.0
    return {
        "status": "calculated" if sum(added.values()) == budget else "partial",
        "objective": final_basis,
        "added_points": added,
        "recommended_stats": {key: num(stats.get(key)) for key in candidates},
        "base_score": base_score,
        "recommended_score": final_score,
        "estimated_gain_percent": delta,
        "simulation": final,
        "method": "greedy integer marginal allocation; approximate, not exhaustive",
    }



def optimize_multi_activity(
    activities: list[tuple[str, dict[str, Any], float]],
    base_stats: dict[str, Any],
    budget: int,
    cfg: dict[str, Any],
) -> dict[str, Any]:
    """Allocate the same stat budget against several activities.

    Each activity is normalized to its own baseline before weighting, so a
    high-throughput raid does not drown out a lower-number PvP or solo activity.
    Activities without a defensible objective are excluded and named explicitly.
    """
    budget = int(clamp(num(budget), 0, 500))
    if not activities:
        return {"status": "insufficient_data", "reason": "Нет выбранных активностей."}

    modes = {str(activity.get("mode", "dps")).lower() for _, activity, _ in activities}
    if len(modes) != 1:
        return {
            "status": "unsupported",
            "reason": "Общий бюджет оптимизируется отдельно для УВС, HPS и защиты; смешивать разные цели нельзя.",
        }
    mode = next(iter(modes))
    stats = dict(base_stats)
    nested_res = dict(stats.get("resistances", {}) or {})
    for resistance_key in ("armor", "elements", "divine", "nature"):
        if resistance_key not in stats and resistance_key in nested_res:
            stats[resistance_key] = num(nested_res[resistance_key], 10.0)

    included = []
    excluded = []
    for name, activity, weight in activities:
        weight = max(0.0, num(weight, 1.0))
        if weight <= 0:
            excluded.append({"activity": name, "reason": "zero_weight"})
            continue
        score, basis = _score_for_optimization(activity, stats, cfg)
        if score is None or score <= 0:
            excluded.append({"activity": name, "reason": basis})
        else:
            included.append({
                "name": name, "activity": activity, "weight": weight,
                "baseline": float(score), "basis": basis,
            })
    if not included:
        return {
            "status": "insufficient_data",
            "reason": "Ни одна активность не имеет достаточных данных для оптимизации.",
            "excluded_activities": excluded,
        }

    candidates = _optimizable_stats(mode, cfg)
    total_weight = sum(row["weight"] for row in included)

    def normalized_score(candidate_stats: dict[str, Any]) -> float | None:
        total = 0.0
        for row in included:
            score, _ = _score_for_optimization(row["activity"], candidate_stats, cfg)
            if score is None:
                return None
            total += row["weight"] * score / row["baseline"]
        return total / total_weight if total_weight > 0 else None

    baseline_score = normalized_score(stats)
    added = {key: 0 for key in candidates}
    if budget <= 0:
        return {
            "status": "no_budget", "mode": mode, "added_points": added,
            "baseline_normalized_score": baseline_score,
            "recommended_normalized_score": baseline_score,
            "included_activities": [row["name"] for row in included],
            "excluded_activities": excluded,
        }

    for _ in range(budget):
        best_key = None
        best_score = -math.inf
        for key in candidates:
            test = dict(stats)
            test[key] = num(test.get(key)) + 1
            candidate_score = normalized_score(test)
            if candidate_score is not None and candidate_score > best_score:
                best_key, best_score = key, candidate_score
        if best_key is None:
            break
        stats[best_key] = num(stats.get(best_key)) + 1
        added[best_key] += 1

    final_score = normalized_score(stats)
    return {
        "status": "calculated" if sum(added.values()) == budget else "partial",
        "mode": mode,
        "objective": "weighted_mean_of_per_activity_relative_gains",
        "added_points": added,
        "recommended_stats": {key: num(stats.get(key)) for key in candidates},
        "baseline_normalized_score": baseline_score,
        "recommended_normalized_score": final_score,
        "estimated_gain_percent": ((final_score - 1.0) * 100.0) if final_score is not None else None,
        "included_activities": [
            {"name": row["name"], "weight": row["weight"], "baseline": row["baseline"], "objective": row["basis"]}
            for row in included
        ],
        "excluded_activities": excluded,
        "method": "greedy integer marginal allocation; each activity normalized to its own baseline",
    }


def _healing_recipient_segments(activity: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Split measured HPS samples into self and ally subsets when recipient is known."""
    result: dict[str, dict[str, Any]] = {}
    samples = activity.get("samples", [])
    for role in ("self", "ally"):
        selected = [
            event for event in samples
            if str(event.get("recipient", event.get("target_role", ""))).lower() == role
        ]
        if selected:
            result[role] = {**activity, "samples": selected}
    return result


def calculate_profile(profile: dict[str, Any]) -> dict[str, Any]:
    cfg = dict(profile.get("settings", {}))
    stats = dict(profile.get("stats", {}))
    fixed = dict(profile.get("fixed_stats", stats))
    budget = int(num(profile.get("allocation_budget", 0)))
    report: dict[str, Any] = {
        "formula_model": "user-supplied Allods Sunshine 6.0 formula set",
        "assumptions": {
            "resolve_coefficient": num(cfg.get("resolve_coefficient", 0.015)),
            "might_affects_healing": bool(cfg.get("might_affects_healing", True)),
            "resolve_gain_uses_actual_divided_by_event_multiplier": True,
            "will_in_tank_optimizer_requires_control_weight": True,
            "rune_absorption": "only applied when rune_absorbed or rune_absorb_fraction is supplied per event",
            "healing_effective": "uses effective_heal or target_max_hp + target_hp; otherwise unknown",
            "resolve_pool_replay": "measured pool snapshots are held fixed when settings.freeze_resolve_pool is true",
        },
        "character": {
            "level_multiplier": level_multiplier(cfg.get("level", 1)),
            "crit_chance_percent": crit_chance(stats.get("luck", 0)) * 100.0,
            "ruthlessness_m": ruthlessness_m(stats.get("ruthlessness", 0)),
            "bloodthirst_fraction": bloodthirst_fraction(stats.get("bloodthirst", 0)),
            "will": will_result(stats.get("will", 0)),
            "max_hp_model": _max_hp(stats, cfg, fixed),
        },
        "activities": {},
        "warnings": list(profile.get("import_warnings", [])),
    }
    # The supplied literal Resolve equation uses 0.015; the explanatory sentence implies 0.0015.
    coefficient = num(cfg.get("resolve_coefficient", 0.015))
    if abs(coefficient - 0.015) < 1e-12:
        report["warnings"].append("Resolve coefficient 0.015 selected from the literal equation supplied by the user; the explanatory sentence implies 0.0015. Confirm this 10x scale against the live server.")
    elif abs(coefficient - 0.0015) < 1e-12:
        report["warnings"].append("Resolve coefficient 0.0015 selected from the explanatory sentence; the literal equation supplied by the user says 0.015. Confirm this 10x scale against the live server.")
    else:
        report["warnings"].append("Custom Resolve coefficient used. Compare it against the exact server scale before treating recommendations as calibrated.")
    if "max_hp" not in cfg and "class_k" not in cfg and not bool(cfg.get("freeze_resolve_pool", False)):
        report["warnings"].append("No max_hp/class_k supplied: automatic Resolve gain and tank health cannot be modelled accurately.")
    if bool(cfg.get("freeze_resolve_pool", False)):
        report["warnings"].append("Resolve pool is fixed to measured per-event samples; growth feedback for a changed build is not recalculated from unavailable raw server base values.")
    weighted_by_mode: dict[str, list[tuple[str, dict[str, Any], float]]] = {}
    for name, activity in profile.get("activities", {}).items():
        sim = simulate(activity, stats, cfg)
        item: dict[str, Any] = {"simulation": sim}
        mode = str(activity.get("mode", "dps")).lower()
        weight = num(activity.get("weight", 1.0), 1.0)
        weighted_by_mode.setdefault(mode, []).append((name, activity, weight))
        if budget > 0:
            item["recommendation"] = optimize(activity, fixed, budget, cfg)
            if mode == "hps":
                segments = {}
                for role, subset in _healing_recipient_segments(activity).items():
                    segment_sim = simulate(subset, stats, cfg)
                    segment = {"simulation": segment_sim}
                    segment["recommendation"] = optimize(subset, fixed, budget, cfg)
                    segments[role] = segment
                if segments:
                    item["recipient_segments"] = segments
        report["activities"][name] = item
        report["warnings"].extend(sim.get("warnings", []))

    if budget > 0:
        report["cross_activity_recommendations"] = {
            mode: optimize_multi_activity(rows, fixed, budget, cfg)
            for mode, rows in weighted_by_mode.items()
            if mode in ("dps", "hps", "tank")
        }
    # Stable unique warnings.
    report["warnings"] = list(dict.fromkeys(report["warnings"]))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="DPScope calculator: DD / HEAL / TANK")
    parser.add_argument("profile", help="JSON file with stats and event samples")
    parser.add_argument("--out", help="Save report to JSON")
    args = parser.parse_args()
    profile = json.loads(Path(args.profile).read_text(encoding="utf-8-sig"))
    report = calculate_profile(profile)
    rendered = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        Path(args.out).write_text(rendered + "\n", encoding="utf-8")
        print("Отчёт сохранён:", args.out)
    else:
        print(rendered)


if __name__ == "__main__":
    main()
