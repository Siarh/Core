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


def calculate_event(event: dict[str, Any], mode: str, stats: dict[str, Any], cfg: dict[str, Any], pool: float) -> dict[str, Any]:
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
        cfg.get("resolve_coefficient", 0.0015),
    )
    u_mult = ruthlessness_multiplier(stats.get("ruthlessness", 0.0), target_hp)
    if "critical" in event:
        crit_mult = 2.0 if bool(event["critical"]) else 1.0
        crit_basis = "event"
    else:
        crit_mult = 1.0 + crit_chance(stats.get("luck", 0.0))
        crit_basis = "expected"

    resistance = _event_resistance(event, cfg)
    resist_mult = resistance_multiplier(resistance) if mode == "dps" else 1.0
    base_after_stats = raw * might_mult * m_mult * r_mult * u_mult * crit_mult
    after_resist = base_after_stats * resist_mult
    after_block, blocked, parried, rune_absorbed = _reduction_after_resist(after_resist, event)
    caution = caution_multiplier(event.get("target_caution", 0.0), target_hp) if mode == "dps" else 1.0
    amount = after_block * caution

    wound_absorb = max(0.0, num(event.get("healing_absorb", event.get("wound_absorb", 0.0)))) if mode == "hps" else 0.0
    effective = None
    overheal = None
    if mode == "hps":
        if event.get("effective_heal") is not None:
            effective = clamp(num(event["effective_heal"]), 0.0, amount)
            overheal = max(0.0, amount - wound_absorb - effective)
        else:
            available = _target_missing_hp(event)
            if available is not None:
                effective = min(max(0.0, amount - wound_absorb), available)
                overheal = max(0.0, amount - wound_absorb - effective)

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
        "raw_incoming": raw, "incoming_after_defense": taken,
        "resistance_rating": rating, "resistance_multiplier": resist_mult,
        "blocked": blocked, "parried": parried, "rune_absorbed": rune_absorbed,
        "caution_multiplier": caution, "bloodthirst_return": bt,
    }


def _objective(result: dict[str, Any], mode: str, cfg: dict[str, Any]) -> tuple[float | None, str]:
    if mode == "dps":
        return num(result.get("total_damage")), "total_damage"
    if mode == "hps":
        count = result.get("events", 0)
        coverage = result.get("effective_heal_events", 0)
        if count > 0 and coverage == count:
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


def simulate(activity: dict[str, Any], stats: dict[str, Any], cfg: dict[str, Any]) -> dict[str, Any]:
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
    resolve_event_values: list[float] = []
    per_second: list[dict[str, float]] = []
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
                resist_saved += calc["raw_incoming"] - calc["raw_incoming"] * calc["resistance_multiplier"]
                continue

            calc = calculate_event(event, mode, stats, cfg, pool)
            second_total += calc["nominal"]
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

            # Pool grows per event, using the pool-dependent k at that event.
            if owner_hp > 0:
                supplied_divisor = num(event.get("resolve_divisor_multiplier"), 0.0)
                divisor = supplied_divisor if supplied_divisor > 0 else calc["full_multiplier"]
                gain = resolve_gain(calc["nominal"], owner_hp, divisor, pool)
                pool = min(100.0, pool + gain)
            if event.get("resolve_pool_after") is not None:
                pool = clamp(num(event["resolve_pool_after"]), 0.0, 100.0)
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

    result: dict[str, Any] = {
        "mode": mode, "events": event_count, "seconds": duration,
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
    result = simulate(activity, stats, cfg)
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
    base_score, basis = _score_for_optimization(activity, stats, cfg)
    if base_score is None:
        return {
            "status": "insufficient_data", "objective": basis,
            "reason": "Нет достаточных событий для честной оптимизации выбранной активности.",
            "added_points": {key: 0 for key in candidates},
        }
    added = {key: 0 for key in candidates}
    if budget == 0:
        final = simulate(activity, stats, cfg)
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

    final = simulate(activity, stats, cfg)
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


def calculate_profile(profile: dict[str, Any]) -> dict[str, Any]:
    cfg = dict(profile.get("settings", {}))
    stats = dict(profile.get("stats", {}))
    fixed = dict(profile.get("fixed_stats", stats))
    budget = int(num(profile.get("allocation_budget", 0)))
    report: dict[str, Any] = {
        "formula_model": "user-supplied Allods 7.0/Sunshine formula set",
        "assumptions": {
            "resolve_coefficient": num(cfg.get("resolve_coefficient", 0.0015)),
            "might_affects_healing": bool(cfg.get("might_affects_healing", True)),
            "resolve_gain_uses_actual_divided_by_event_multiplier": True,
            "will_in_tank_optimizer_requires_control_weight": True,
            "rune_absorption": "only applied when rune_absorbed or rune_absorb_fraction is supplied per event",
            "healing_effective": "uses effective_heal or target_max_hp + target_hp; otherwise unknown",
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
        "warnings": [],
    }
    # The source text itself contains a 10x ambiguity in the Resolve multiplier.
    coefficient = num(cfg.get("resolve_coefficient", 0.0015))
    if abs(coefficient - 0.0015) < 1e-12:
        report["warnings"].append("Resolve coefficient 0.0015 selected from the explanatory sentence; literal equation alternative is 0.015. Verify which scale the server uses.")
    elif abs(coefficient - 0.015) < 1e-12:
        report["warnings"].append("Resolve coefficient 0.015 selected from the literal equation; explanatory sentence alternative implies 0.0015. Verify which scale the server uses.")
    else:
        report["warnings"].append("Custom Resolve coefficient used. Compare it against the exact server scale before treating recommendations as calibrated.")
    if "max_hp" not in cfg and "class_k" not in cfg:
        report["warnings"].append("No max_hp/class_k supplied: automatic Resolve gain and tank health cannot be modelled accurately.")
    for name, activity in profile.get("activities", {}).items():
        sim = simulate(activity, stats, cfg)
        item: dict[str, Any] = {"simulation": sim}
        if budget > 0:
            item["recommendation"] = optimize(activity, fixed, budget, cfg)
        report["activities"][name] = item
        report["warnings"].extend(sim.get("warnings", []))
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
