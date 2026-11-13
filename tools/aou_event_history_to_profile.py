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
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import aou_formula_calculator as calc


REQUIRED_STATS = ("M", "R", "U", "L")
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
    values: dict[str, list[float]] = {key: [] for key in REQUIRED_STATS}
    for row in rows:
        for key in REQUIRED_STATS:
            value = number(row.get(key))
            if value is not None:
                values[key].append(value)
    result: dict[str, float] = {}
    for key, group in values.items():
        if not group:
            raise ValueError(f"В журнале нет снимка характеристики {key}.")
        if max(group) - min(group) > 0.5:
            raise ValueError(
                f"Характеристика {key} менялась между боями ({min(group):.1f}–{max(group):.1f}). "
                "Собери CSV для одного набора экипировки/распределения."
            )
        result[key.lower()] = group[0]
    return result


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
    combat_rows = [
        row for row in rows
        if (row.get("kind") or "").strip().lower() in {"damage", "healing"}
    ]
    if not combat_rows:
        raise ValueError("В CSV нет исходящих событий damage/healing.")

    stats = stat_signature(combat_rows)
    groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    skipped: Counter[str] = Counter()

    for row in combat_rows:
        kind = (row.get("kind") or "").strip().lower()
        mode = "dps" if kind == "damage" else "hps"
        sample, reason = event_to_sample(row, stats, resolve_coefficient, mode)
        if reason:
            skipped[reason] += 1
            continue
        fight_id = (row.get("fight_id") or "unknown").strip()
        profile_name = (row.get("profile") or "unknown").strip()
        groups[(fight_id, mode)].append({
            "sample": sample,
            "profile": profile_name,
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

    if not activities:
        raise ValueError(
            "После фильтрации не осталось пригодных событий. "
            f"Причины исключения: {dict(skipped)}"
        )

    profile_names = sorted({(row.get("profile") or "unknown").strip() for row in combat_rows})
    warnings = [
        "События нормализованы из итоговой величины callback, а не из сырой базовой силы умения.",
        "Неизвестные сопротивления цели, блок/парирование и осторожность цели остаются частью веса конкретного события.",
        "Наблюдаемый пул Решимости зафиксирован отдельно на каждом событии; его обратная динамика при изменении статов не пересчитывается.",
        "Для лечения исходная величина callback рассматривается как номинальная базовая величина; если исходное лечение уже было ограничено недостающим HP, рекомендация будет консервативной.",
    ]
    if skipped:
        warnings.append("Исключено событий по причине: " + ", ".join(f"{key}={value}" for key, value in sorted(skipped.items())))

    return {
        "settings": {
            "level": 1,
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
        "import_warnings": warnings,
        "import_summary": {
            "source_rows": len(combat_rows),
            "included_events": included,
            "skipped_events": dict(skipped),
            "profiles": profile_names,
            "activities": len(activities),
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
