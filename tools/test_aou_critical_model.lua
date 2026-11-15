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
    FromWString = function(value) return value.value end,
}
common.IsWString = function(value) return type(value) == "table" and value.__wide == true end
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


-- Innate-stat API regression: accept both plain enum strings and wide strings.
local function wide(value)
    return { __wide = true, value = value }
end
local statRows = {
    { sysName = wide("ENUM_InnateStats_Plain"), effective = 310, base = 100, talents = 20, fairyBonus = 5, buffs = 10, enchants = 5 },
    { sysName = "ENUM_InnateStats_Rage", effective = 420, base = 200 },
    { sysName = "ENUM_InnateStats_Finisher", effective = 530, base = 300 },
    { sysName = "ENUM_InnateStats_CritChance", effective = 210, base = 210 },
    { sysName = "ENUM_InnateStats_Vitality", effective = 160, base = 100 },
    { sysName = "ENUM_InnateStats_Will", effective = 120, base = 80 },
    { sysName = "ENUM_InnateStats_Lifesteal", effective = 90, base = 90 },
}
avatar = { GetInnateStats = function() return statRows end }
unit = {}
local currentStats = Optim.ReadStats()
expect(currentStats.M.total, 310, "automatic Mastery read")
expect(currentStats.M.base, 100, "automatic Mastery base")
expect(currentStats.M.fixed, 40, "automatic Mastery fixed sources")
expect(currentStats.R.total, 420, "automatic Resolve read")
expect(currentStats.U.total, 530, "automatic Ruthlessness read")
expect(currentStats.L.total, 210, "automatic Luck read")
expect(currentStats.S.total, 160, "automatic Fortitude read")
expect(currentStats.W.total, 120, "automatic Will read")
expect(currentStats.B.total, 90, "automatic Bloodthirst read")

enumMode = { Dps = 1, Hps = 2, Def = 3, IHps = 4 }
local noFightSamples = {
    Data = {
        [enumMode.Dps] = { Amount = 0, SpellsList = {} },
        [enumMode.Hps] = { Amount = 0, SpellsList = {} },
        [enumMode.Def] = { Amount = 0, SpellsList = {} },
    }
}
local function findRow(rows, key)
    for _, row in ipairs(rows) do
        if row[1] == key then return row end
    end
end

local noDataLines = Optim.BuildLines(noFightSamples, 0, enumMode.Dps)
local masteryRow = findRow(noDataLines, "OptM")
expect(masteryRow and masteryRow[2], "310", "current stat shown without fight samples")
expect(masteryRow and masteryRow[3], "-", "optimal column marked unavailable without fight samples")
expect(findRow(noDataLines, "OptNoData") ~= nil, true, "no-sample status remains visible")

-- The auto switch affects model input, not whether the live stat panel is populated.
Optim.Cfg.auto = 0
local manualModeLines = Optim.BuildLines(noFightSamples, 0, enumMode.Dps)
local manualModeMastery = findRow(manualModeLines, "OptM")
expect(manualModeMastery and manualModeMastery[2], "310", "live stat remains visible with auto disabled")

-- A partial API response remains displayable rather than disappearing entirely.
avatar.GetInnateStats = function()
    return { { sysName = "ENUM_InnateStats_Plain", effective = 321, base = 123 } }
end
local partial = Optim.ReadStats(true)
expect(partial and partial.M.total, 321, "partial innate-stat snapshot")
expect(Optim.LastStatsRead.found, 1, "partial snapshot count")
local partialLines = Optim.BuildLines(noFightSamples, 0, enumMode.Dps)
local partialMastery = findRow(partialLines, "OptM")
expect(partialMastery and partialMastery[2], "321", "partial live stat reaches optimizer panel")

print("DPScope critical model regression tests passed.")
