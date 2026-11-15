-- Regression tests for the empirical critical-hit model in AoUMeterOptim.lua.
-- Run from tools with: lua test_aou_critical_model.lua

function Global(name, value) _G[name] = value end

enumHit = { Normal = 1, Critical = 2 }
local section = {}
common = { GetAddonName = function() return "DPScope" end }
userMods = {
    GetGlobalConfigSection = function() return section end,
    SetGlobalConfigSection = function(_, value) section = value end,
    ToWString = function(value) return value end,
}
Settings = { Opt = {} }
localization = "eng"

dofile("../Scripts/AoUMeterOptim.lua")

local function expect(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function near(actual, expected, epsilon, label)
    if math.abs(actual - expected) > epsilon then
        error(string.format("%s: expected %.6f, got %.6f", label, expected, actual))
    end
end

local function spell(normalCount, normalAmount, criticalCount, criticalAmount)
    return {
        DetailsList = {
            [enumHit.Normal] = { Count = normalCount, Amount = normalAmount },
            [enumHit.Critical] = { Count = criticalCount, Amount = criticalAmount },
        }
    }
end

-- One ability: normal average 100, critical average 300 (3.0x),
-- 2 normal + 3 critical events. The raw 60% share is shrunk towards
-- the Luck-based prior because five hits are not a reliable sample.
local one = Optim.EstimateCritModel({ spell(2, 200, 3, 900) }, 100)
expect(one.normalCount, 2, "normal hit count")
expect(one.criticalCount, 3, "critical hit count")
expect(one.hitCount, 5, "sample count")
expect(one.abilityCount, 1, "paired ability count")
expect(one.pairedCount, 2, "paired normal/critical samples")
near(one.observedChance, 0.6, 1e-9, "observed critical share")
near(one.observedMultiplier, 3.0, 1e-9, "observed critical/normal ratio")
near(one.usedChance, 0.247058823529, 1e-6, "smoothed critical chance")
near(one.usedMultiplier, 2.2, 1e-9, "smoothed critical ratio")
near(one.factor, 1.296470588235, 1e-6, "expected hit multiplier")

-- Multiple abilities are weighted by their all-normal damage contribution,
-- not simply averaged by number of abilities.
local two = Optim.EstimateCritModel({
    spell(2, 200, 2, 600),     -- ratio 3.0, weight 400
    spell(10, 1000, 1, 150),   -- ratio 1.5, weight 1100
}, 100)
expect(two.abilityCount, 2, "two paired abilities")
expect(two.pairedCount, 3, "paired sample count across abilities")
near(two.observedMultiplier, 1.9, 1e-9, "damage-weighted ability ratio")

-- With no hit evidence, preserve the original Luck-based 2x critical prior.
local empty = Optim.EstimateCritModel({}, 100)
expect(empty.hitCount, 0, "empty hit count")
expect(empty.observedChance, nil, "empty observed critical chance")
near(empty.factor, 1.1, 1e-9, "fallback Luck-based multiplier")

print("DPScope critical model regression tests passed.")
