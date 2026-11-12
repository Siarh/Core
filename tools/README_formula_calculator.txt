DPScope Formula Engine (DD / HEAL / TANK)
========================================

Purpose
-------
This is an offline calculator for the formula set supplied for Allods 7.0 /
Allods Sunshine 6.0. It consumes explicit event samples in JSON and produces
separate activity reports and optional stat-allocation recommendations.
It does NOT read the game process and it does NOT silently fill missing HP,
resistance, rune absorption, or effective-heal values.

Run
---
From the tools folder:

    python .\aou_formula_calculator.py .\aou_profile_template.json
    python .\aou_formula_calculator.py .\profile.json --out .\report.json

Run unit tests:

    python -m unittest -v .\test_aou_formula_calculator.py

Profile structure
-----------------
settings: character level, actual max HP or class_k, Might, Resolve formula
coefficient, and other explicitly supplied constants.
stats: current stats. Names used by the calculator are descriptive JSON keys:
mastery, resolve, ruthlessness, luck, might, bloodthirst, fury, fortitude,
endurance, caution, will, and optionally resistances {armor,elements,divine,nature}.
activities: independently named activities. Each activity has mode dps, hps,
or tank and a samples array.

DPS / HPS event fields
----------------------
second                    integer second from activity start
raw                       pre-formula ability/heal amount
critical                  optional actual event critical flag; if absent, expected
                          average damage/heal is used from Luck probability
target_hp                 target HP before the event, fraction 0..1
target_max_hp             max HP of target; used to compute effective healing
missing_hp                alternative direct missing HP value
effective_heal            optional directly measured effective heal
healing_absorb            optional known wound/Fury absorption amount
power_scale               weapon damage/10 or magic power/10; default 10
damage_school             physical/fire/cold/lightning/poison/disease/acid/holy/
                          shadow/astral; used to select resistance family
target_resistances        optional map with armor/elements/divine/nature values
target_resistance         optional direct resistance R; R=10 is neutral
block_fraction            measured block fraction 0..1
parry_fraction             measured parry fraction 0..1
rune_absorbed              measured absolute rune absorption amount
rune_absorb_fraction       measured rune absorption fraction 0..1
resolve_pool               optional measured pool before this event
resolve_pool_after         optional measured pool after this event
resolve_divisor_multiplier optional explicit divisor in pool-gain formula
player_died / owner_died     true on death; resets the simulated Resolve pool
target_is_player           true only when target is a player
in_combat                  true when the target is in combat (Fury condition)

TANK event fields
-----------------
second, incoming_raw, damage_school, player_hp, player_resistance,
block_fraction, parry_fraction, rune_absorbed/rune_absorb_fraction.
Optional outgoing_damage is the player's outgoing damage for Bloodthirst return.
Optional activity.control_windows is a list of control durations in seconds.

Formulas included
-----------------
* Mastery: 1+s/1000; negative values use 1/(1+abs(s)/1000).
* Resolve: 1 + s/1000 * pool * coefficient; pool is clamped to 0..100.
  Per-event pool growth uses the given k thresholds and 10% per-second decay.
* Ruthlessness: m/ln(1+m)=1+s/1000, then 1+m*(1-target HP fraction).
* Luck and Fury use the supplied soft-cap function f(s), capped at 850.
* Critical events use x2; where no critical flag is supplied, expected multiplier
  is 1 + critical probability.
* Bloodthirst: x/(x+1.8); HPS return is divided by 3.
* Caution: below 40% HP, damage multiplier 1-min(s,350)/1000.
* Will: full-second control accumulation and time to immunity; 4-second immunity.
* Might, level multiplier, power scale, Fortitude/Endurance HP, four resistance
  families, block/parry, and separately measured rune absorption.
* Hit order: Might/level, Mastery, Resolve, critical, resistance, block/parry,
  measured rune absorption, Ruthlessness, then target Caution. Ruthlessness is
  applied after fixed rune absorption so an absolute absorbed amount is not
  multiplied a second time.
* Death marker: an event with player_died=true or owner_died=true resets Resolve to 0.

Explicit unresolved ambiguities
-------------------------------
1. Resolve multiplier coefficient: the written equation says 0.015, but the
   accompanying sentence "1.5% for every 10 pool points" with a 0..100 pool
   implies 0.0015. The calculator defaults to 0.0015 based on the explanation;
   set settings.resolve_coefficient to 0.015 to test the literal equation.
2. Resolve gain formula divides damage by a "multiplier". The calculator uses
   actual calculated event amount divided by its total event multiplier, which
   recovers the raw pre-multiplier event amount. An event may override this through
   resolve_divisor_multiplier. No fitted constant such as 2.4 is hard-coded.
3. Class K is not mapped to classes here. Supply settings.class_k explicitly
   before using the Endurance-derived HP formula.
4. Rune absorption has no standalone formula in the supplied specification.
   It is only applied when a measured amount or fraction is provided per event.
5. Resistance rating is taken from the event or the supplied stat family. R=10
   is neutral. The calculator does not guess missing resistance values.
6. Effective HPS is available only if effective_heal is supplied or the event
   contains target_max_hp and target_hp-before. Otherwise it is marked unknown;
   HPS optimization is refused unless allow_nominal_hps_optimization=true.
7. Fury absorption is calculated from the supplied 0.375% * f(s) expression.
   No extra cap is invented. Treat results above 100% as a prompt to validate
   the server interpretation of the stat scaling.
8. Will only enters the Tank objective when mode=pvp and settings.control_weight
   is explicitly supplied. This is required because the spec gives no common
   numeric exchange rate between survival seconds and control seconds.

Optimizer
---------
DD and HEAL allocate integer points across Mastery, Resolve, Ruthlessness,
and Luck. HEAL uses effective healing only when every event has an effective
value; otherwise it refuses recommendations by default. Bloodthirst self-heal
can be included with settings.healer_bloodthirst_weight, which is a user-chosen
objective weight, not a game formula.
TANK allocates Fortitude, Endurance, Bloodthirst, Caution and the four resistance
families. Will is available in PvP only with an explicit control_weight.
The allocation is a greedy marginal search, not an exhaustive global optimum.
Recommendations are model outputs, not proof of a best in-game build.

Reports also contain event amounts by target-HP phase (when target_hp is known)
and first-half / second-half activity rates. Critical percentages are shown only
for events where the actual critical flag is known. During counterfactual stat
allocation, Luck uses expected critical value rather than replaying the old
critical/not-critical flags. HPS optimization requires effective-heal data that
can be recalculated for alternative stats: target HP/missing HP, or a reusable
effective-heal ratio. A bare historical effective_heal number is reported but
not reused as though it would stay fixed under a different build. DD/HPS stat
optimization is refused when any target HP sample is missing, because otherwise
the Ruthlessness contribution would be silently treated as zero. Reports group
Tank incoming mitigation by physical, elements, divine and nature resistance.

Event log format
----------------
Keep raw event samples in JSON (one profile per activity or one merged profile).
Do not replace raw fields with calculated totals: formulas can then be revised
and old battles recalculated. If only aggregated /aou rec records are available,
they are insufficient to reconstruct all per-event health, timing, target,
resistance and rune data.


Saved-record analyzer consistency
---------------------------------
`aou_analyze.py` now uses the same Resolve coefficient as the event calculator by default: 0.0015.
To compare against the literal coefficient from the alternate reading of the supplied equation, run:

    python aou_analyze.py records.txt --resolve-coefficient 0.015

The coefficient is printed in the report. This does not resolve the source-specification ambiguity: with a 0..100 pool, 0.0015 corresponds to +1.5% per 10 pool points at 1000 Resolve, while 0.015 corresponds to +15% per 10 points.

Important integration note
--------------------------
The in-game Lua optimizer (`Scripts/AoUMeterOptim.lua`) still uses the literal 0.015 coefficient in its current branch revision. The offline calculator and saved-record analyzer default to 0.0015. This discrepancy is intentionally not hidden: the supplied equation and the stated +1.5% per 10 pool points imply different coefficients. Do not treat the Lua optimizer and offline engine as numerically equivalent for Resolve until a controlled Sunshine 6.0 test settles the coefficient. Both interpretations remain testable offline.
