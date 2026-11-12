#!/usr/bin/env python3
"""Анализ тестовых записей /aou mark (DPScope / AoUMeter optimizer).

Запуск:
    python aou_analyze.py user.cfg [ещё_файлы_или_txt ...] [--ref C0]

Файл может быть конфигом игры (ищутся строки aou_rec_N="...") или обычным текстом, где записи идут по одной в строке
(как их печатает /aou rec list: n|метка|pve|...).

Метка записи: <манекен>_<набор>_<номер>, например d70_B200_2. Записи с одинаковым <манекен>_<набор> усредняются.
Для каждой группы печатаются: средний урон в секунду, разброс, средний пул, доля критов, характеристики и сравнение
с моделью. По умолчанию коэффициент Решимости 0.0015; вариант 0.015 проверяется через --resolve-coefficient 0.015.
Беспощадность x(1+m*(1-HP цели)), Удача: крит x2 с шансом f(s)/1000.
"""
import math, re, sys, statistics as st

COLS = ("n|label|mode|sec|dmg|dps|hits|crits|pool|poolc|thp|heal|hps|M|R|U|L|S|W|B|bM|bR|bU|bS|bW|bB|hp|inc|hpSamples|"
        "poolSamples|outResist|outAbsorb|outBlock|inResist|inAbsorb|inBlock|inPhysical|inElements|inNature|inLight|"
        "healWound|healOver|healPool|healTHP|healSamples|healPoolSamples|inHeal|oHealWound|oHealOver|topDmg|topHeal").split("|")

def read_records(paths):
    recs = []
    for p in paths:
        t = open(p, "rb").read().decode("utf-8", errors="replace")
        found = re.findall(r'aou_rec_\d+=l"([^"]*)"', t)
        if not found:  # обычный текст: строки вида n|label|...
            found = [l.strip() for l in t.splitlines() if re.match(r"^\d+\|[^|]+\|(pve|pvp)\|", l.strip())]
        for r in found:
            f = r.split("|")
            d = dict(zip(COLS, f))
            for k in COLS:
                if k in d and k not in ("label", "mode", "topDmg", "topHeal"):
                    try: d[k] = float(d[k])
                    except ValueError: pass
            recs.append(d)
    return recs

def m_ruth(x):
    if x <= 0: return 0.0
    lo, hi = 0.0, 1e6
    for _ in range(80):
        mid = (lo + hi) / 2
        if mid / math.log(1 + mid) < 1 + x: lo = mid
        else: hi = mid
    return lo

def fcrit(s):
    if s <= 500: return s
    r = 500 / s
    return min(850, 500 + (s - 500) * 0.7 * (r + 0.25 * r**5 - 0.5 * r**3))

def model(d, resolve_coefficient=0.0015):
    """Относительный множитель урона; коэффициент Решимости по умолчанию 0.0015."""
    pool = d.get("pool", 0); h = d.get("thp", 100) / 100 if d.get("thp", -1) >= 0 else 1.0
    return ((1 + d["M"] / 1000) * (1 + d["R"] / 1000 * pool * resolve_coefficient) * (1 + m_ruth(d["U"] / 1000) * (1 - h))
            * (1 + min(1, fcrit(d["L"]) / 1000)))

def k_pool(p):
    return .35 if p < 50 else .3 if p < 60 else .18 if p < 70 else .15 if p < 80 else .1

def pool_sim(rate, c, T):
    p = 0; tot = 0
    for _ in range(int(T)):
        p = min(100, p + round(416.7 * rate / c * k_pool(p)))
        tot += p
        p = math.floor(p * 0.9)
    return tot / max(1, int(T))

def calibrate_c(rate, measured, T):
    lo, hi = 0.05, 50.0
    for _ in range(40):
        mid = math.sqrt(lo * hi)
        if pool_sim(rate, mid, T) > measured: lo = mid
        else: hi = mid
    return math.sqrt(lo * hi)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ref = None
    resolve_coefficient = 0.0015
    if "--ref" in sys.argv:
        idx = sys.argv.index("--ref")
        if idx + 1 >= len(sys.argv): raise SystemExit("--ref требует метку")
        ref = sys.argv[idx + 1]
        args = [a for a in args if a != ref]
    if "--resolve-coefficient" in sys.argv:
        idx = sys.argv.index("--resolve-coefficient")
        if idx + 1 >= len(sys.argv): raise SystemExit("--resolve-coefficient требует число: 0.0015 или 0.015")
        try: resolve_coefficient = float(sys.argv[idx + 1])
        except ValueError: raise SystemExit("--resolve-coefficient требует число: 0.0015 или 0.015")
        if not math.isfinite(resolve_coefficient) or resolve_coefficient < 0:
            raise SystemExit("--resolve-coefficient должен быть конечным неотрицательным числом")
        args = [a for a in args if a != "--resolve-coefficient" and a != sys.argv[idx + 1]]
    if not args:
        print(__doc__); return
    recs = read_records(args)
    print(f"записей: {len(recs)}\n")
    groups = {}
    for d in recs:
        key = re.sub(r"_\d+$", "", str(d.get("label", "?")))
        groups.setdefault(key, []).append(d)
    base = None
    print(f"{'группа':14s}{'n':>3s}{'dps(ср.)':>12s}{'разброс%':>9s}{'пул':>6s}{'HP цели':>8s}{'крит%':>7s}  M/R/U/L          модель  измерено")
    rows = []
    for key, ds in groups.items():
        dps = [d["dps"] for d in ds]; mean = st.mean(dps)
        sd = (st.pstdev(dps) / mean * 100) if len(dps) > 1 and mean else 0
        crit = [d["crits"] / d["hits"] * 100 for d in ds if d.get("hits")]
        mod = st.mean(model(d, resolve_coefficient) for d in ds)
        rows.append((key, ds, mean, sd, st.mean(d["pool"] for d in ds), st.mean(d["thp"] for d in ds),
                     st.mean(crit) if crit else 0, mod))
    ref_row = next((r for r in rows if ref and r[0].endswith(ref)), rows[0] if rows else None)
    for key, ds, mean, sd, pool, thp, crit, mod in rows:
        d0 = ds[0]
        meas = mean / ref_row[2] if ref_row and ref_row[2] else 0
        pred = mod / ref_row[7] if ref_row else 0
        print(f"{key:14s}{len(ds):3d}{mean:12.0f}{sd:9.1f}{pool:6.1f}{thp:8.1f}{crit:7.1f}  "
              f"{d0['M']:.0f}/{d0['R']:.0f}/{d0['U']:.0f}/{d0['L']:.0f}".ljust(18) + f"{pred:8.3f}{meas:10.3f}")
    print(f"\nКоэффициент Решимости в модели: {resolve_coefficient:g}")
    print("Столбцы «модель» и «измерено» даны относительно группы", ref_row[0] if ref_row else "-",
          "(у которой они равны 1.000). Расхождение больше разброса = модель неточна.")
    print("\nКалибровка роста пула Решимости (множитель c в формуле 416.7 * урон / здоровье / c * k):")
    for d in recs:
        if d.get("dps") and d.get("hp") and d.get("poolc"):
            c = calibrate_c(d["dps"] / d["hp"], d["poolc"], d["sec"])
            print(f"  {d['label']:12s} урон/здоровье в сек {d['dps']/d['hp']:.3f}, измеренный пул {d['poolc']:.0f} -> c = {c:.2f}")
        if d.get("hps") and d.get("hp") and d.get("healPool"):
            c = calibrate_c(d["hps"] / d["hp"], d["healPool"], d["sec"])
            print(f"  {d['label']:12s} лечение/здоровье в сек {d['hps']/d['hp']:.3f}, измеренный пул лечения {d['healPool']:.0f} -> c = {c:.2f}")
    print("\nКрит-доля по записям (ожидание по Удаче f(s)/1000):")
    for d in recs:
        if d.get("hits"):
            exp = fcrit(d["L"]) / 1000
            sd_ = math.sqrt(d["hits"] * exp * (1 - exp)) or 1
            print(f"  {d['label']:12s} {int(d['crits'])}/{int(d['hits'])} = {d['crits']/d['hits']*100:5.1f}%  ожидалось {exp*100:.1f}%  отклонение {(d['crits']-d['hits']*exp)/sd_:+.1f} σ")

if __name__ == "__main__":
    main()
