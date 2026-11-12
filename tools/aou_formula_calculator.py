# -*- coding: utf-8 -*-
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path


def n(x, default=0.0):
    try:
        v = float(x)
        return v if math.isfinite(v) else default
    except (TypeError, ValueError):
        return default


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def level_mult(level):
    return 1.14 ** ((n(level, 1) - 1) * 0.2)


def mastery(s):
    s = n(s)
    return 1 + s / 1000 if s >= 0 else 1 / (1 + abs(s) / 1000)


def f_stat(s):
    s = clamp(n(s), 0, 850)
    if s <= 500:
        return s
    r = 500 / s
    return 500 + (s - 500) * 0.7 * (
        r + 0.25 * r**5 - 0.5 * r**3
    )


def crit_chance(luck):
    return clamp(f_stat(luck) / 1000, 0, 1)


def ruthlessness_m(stat):
    x = max(0, n(stat)) / 1000
    if x < 1e-12:
        return 0.0
    target = 1 + x

    def f(m):
        return m / math.log1p(m) if m > 1e-12 else 1.0

    lo, hi = 0.0, max(1.0, 2 * x)
    while f(hi) < target:
        hi *= 2
    for _ in range(90):
        mid = (lo + hi) / 2
        if f(mid) < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def ruthlessness(stat, target_hp):
    return 1 + ruthlessness_m(stat) * (
        1 - clamp(n(target_hp, 1), 0, 1)
    )


def resolve_mult(stat, pool, coefficient):
    return 1 + n(stat) / 1000 * clamp(pool, 0, 100) * coefficient


def resolve_k(pool):
    if pool < 50:
        return 0.35
    if pool < 60:
        return 0.30
    if pool < 70:
        return 0.18
    if pool < 80:
        return 0.15
    return 0.10


def resolve_gain(pool, outgoing, max_hp, divisor):
    if max_hp <= 0 or divisor <= 0:
        return 0
    value = 416.7 * max(0, outgoing) / max_hp / divisor * resolve_k(pool)
    return max(0, math.floor(value + 0.5))


def resolve_decay(pool):
    return math.floor(clamp(pool, 0, 100) * 0.9)


def bloodthirst(stat):
    x = max(0, n(stat)) / 1000
    return x / (x + 1.8) if x else 0


def caution_mult(stat, hp):
    if n(hp, 1) >= 0.40:
        return 1.0
    return 1 - clamp(n(stat), 0, 350) / 1000


def resistance_mult(rating):
    if rating is None:
        return 1.0
    rating = n(rating)
    if rating <= 0:
        raise ValueError("Сопротивление должно быть больше нуля; нейтральное R=10")
    return 10 / rating


def health_from_endurance(level, class_k, endurance, fortitude):
    return (
        n(class_k) / 2 * n(endurance)
        * level_mult(level)
        * (1 + n(fortitude) / 1000)
    )


def will_result(w):
    w = max(0, n(w))
    if not w:
        return {"seconds": None, "gain_percent": 0}
    p = min(900, 1.6 * w / (1 + w**1.05 / 1000)) / 1000
    if p <= 0:
        return {"seconds": None, "gain_percent": 0}
    t = (p / 0.05)**0.75
    denominator = t / p - t
    if denominator <= 0:
        return {"seconds": None, "gain_percent": 0}
    gain = math.ceil(150 / denominator)
    return {
        "seconds": math.ceil(100 / gain),
        "gain_percent": gain
    }


def event_result(event, mode, stats, cfg, pool):
    raw = max(0, n(event.get("raw")))
    target_hp = clamp(n(event.get("target_hp", 1), 1), 0, 1)

    m = mastery(stats.get("mastery", 0))
    r = resolve_mult(
        stats.get("resolve", 0),
        pool,
        n(cfg.get("resolve_coefficient", 0.0015))
    )
    u = ruthlessness(stats.get("ruthlessness", 0), target_hp)

    if "critical" in event:
        crit = 2.0 if event["critical"] else 1.0
    else:
        crit = 1 + crit_chance(stats.get("luck", 0))

    amount = raw * m * r * u * crit

    if mode == "dps" or cfg.get("might_affects_healing", False):
        amount *= max(0, n(stats.get("might", cfg.get("might", 20)))) / 20
        amount *= level_mult(cfg.get("level", 1))
        amount *= max(0, n(event.get(
            "power_scale", cfg.get("power_scale", 10)
        ))) / 10

    if mode == "dps":
        amount *= resistance_mult(
            event.get("target_resistance",
                      cfg.get("default_target_resistance", 10))
        )
        amount *= 1 - clamp(n(event.get("block_fraction")), 0, 1)
        amount *= 1 - clamp(n(event.get("parry_fraction")), 0, 1)
        amount *= caution_mult(
            event.get("target_caution", 0), target_hp
        )

    bt = amount * bloodthirst(stats.get("bloodthirst", 0))
    if mode == "hps":
        bt /= 3

    fury = 0
    if mode == "dps" and event.get("target_is_player", False):
        if event.get("in_combat", True):
            fury = amount * 0.00375 * f_stat(stats.get("fury", 0))

    return amount, bt, fury


def simulate(activity, stats, cfg):
    mode = str(activity.get("mode", "dps")).lower()
    if mode not in ("dps", "hps"):
        raise ValueError("mode должен быть dps или hps")

    samples = activity.get("samples", [])
    if not samples:
        return {
            "mode": mode, "events": 0, "seconds": 0,
            "total": 0, "per_second": 0,
            "resolve_average": 0, "resolve_final": 0
        }

    grouped = defaultdict(list)
    for i, event in enumerate(samples):
        grouped[int(n(event.get("second", i)))].append(event)

    first, last = min(grouped), max(grouped)
    pool = clamp(n(cfg.get("initial_resolve")), 0, 100)
    max_hp = n(cfg.get("max_hp"))
    divisor = n(cfg.get("resolve_gain_divisor", 2.4))

    total = bt_total = fury_total = 0.0
    pool_sum = 0.0
    count = 0

    for sec in range(first, last + 1):
        second_total = 0.0

        for event in grouped.get(sec, []):
            amount, bt, fury = event_result(
                event, mode, stats, cfg, pool
            )
            second_total += amount
            bt_total += bt
            fury_total += fury
            count += 1

            # Входящий урон считается отдельно от DPS/HPS.
            incoming = n(event.get("incoming_raw"))
            if incoming > 0:
                im = resistance_mult(event.get("player_resistance", 10))
                im *= 1 - clamp(n(event.get("incoming_block")), 0, 1)
                im *= 1 - clamp(n(event.get("incoming_parry")), 0, 1)
                im *= caution_mult(
                    stats.get("caution", 0),
                    event.get("player_hp", 1)
                )
                total_incoming = incoming * im
                event["_calculated_incoming"] = total_incoming

        total += second_total

        # Решимость растёт от общего урона/лечения за секунду.
        gain = resolve_gain(pool, second_total, max_hp, divisor)
        pool = min(100, pool + gain)
        pool = resolve_decay(pool)
        pool_sum += pool

    duration = last - first + 1
    return {
        "mode": mode,
        "events": count,
        "seconds": duration,
        "total": total,
        "per_second": total / max(1, duration),
        "resolve_average": pool_sum / max(1, duration),
        "resolve_final": pool,
        "bloodthirst_return": bt_total,
        "fury_healing_absorption": fury_total,
        "crit_chance_percent": crit_chance(
            stats.get("luck", 0)
        ) * 100
    }


def optimize(activity, base_stats, budget, cfg):
    budget = int(clamp(n(budget), 0, 500))
    stats = dict(base_stats)
    for key in ("mastery", "resolve", "ruthlessness", "luck"):
        stats[key] = n(stats.get(key))

    base = simulate(activity, stats, cfg)["total"]
    added = {k: 0 for k in (
        "mastery", "resolve", "ruthlessness", "luck"
    )}

    # Жадное распределение: каждое следующее очко идёт
    # в характеристику с наибольшим приростом результата.
    for _ in range(budget):
        best_key, best_score = None, -1
        for key in added:
            test = dict(stats)
            test[key] += 1
            score = simulate(activity, test, cfg)["total"]
            if score > best_score:
                best_key, best_score = key, score
        if best_key is None:
            break
        stats[best_key] += 1
        added[best_key] += 1

    final = simulate(activity, stats, cfg)
    gain = (final["total"] / base - 1) * 100 if base > 0 else 0
    return {
        "added_points": added,
        "recommended_stats": {
            k: stats[k] for k in added
        },
        "base_total": base,
        "recommended_total": final["total"],
        "estimated_gain_percent": gain,
        "simulation": final
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("profile", help="JSON профиль активности")
    ap.add_argument("--out", help="Куда сохранить отчёт JSON")
    args = ap.parse_args()

    profile = json.loads(
        Path(args.profile).read_text(encoding="utf-8-sig")
    )
    cfg = profile.get("settings", {})
    stats = profile.get("stats", {})
    fixed = profile.get("fixed_stats", stats)
    budget = int(n(profile.get("allocation_budget")))

    report = {
        "formula_model": "AOU server formulas supplied by user",
        "mastery_multiplier": mastery(stats.get("mastery", 0)),
        "crit_percent": crit_chance(stats.get("luck", 0)) * 100,
        "ruthlessness_m": ruthlessness_m(
            stats.get("ruthlessness", 0)
        ),
        "bloodthirst_fraction": bloodthirst(
            stats.get("bloodthirst", 0)
        ),
        "will": will_result(stats.get("will", 0)),
        "activities": {},
        "warnings": [
            "resolve_coefficient по умолчанию 0.0015: это согласуется с текстом «1.5% за 10 пунктов шкалы». В исходной записи 0.015 — противоречие; его можно задать в JSON.",
            "resolve_gain_divisor по умолчанию 2.4 — предварительная калибровка по трём записям, не подтверждённая константа сервера.",
            "Для точных рекомендаций нужны события с raw, временем и HP цели. Агрегированные записи user.cfg не содержат всей этой информации.",
            "Блок/парирование и сопротивление принимаются как данные события. Рунное поглощение пока не моделируется.",
            "Могущество для лечения по умолчанию выключено; включается settings.might_affects_healing=true.",
            "Рекомендация — жадный поиск целых очков, не глобальный перебор всех сочетаний."
        ]
    }

    for name, activity in profile.get("activities", {}).items():
        sim = simulate(activity, stats, cfg)
        item = {"simulation": sim}
        if budget:
            item["recommendation"] = optimize(
                activity, fixed, budget, cfg
            )
        report["activities"][name] = item

    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        Path(args.out).write_text(rendered + "\n", encoding="utf-8")
        print("Отчёт сохранён:", args.out)
    else:
        print(rendered)


if __name__ == "__main__":
    main()