-- Regression tests for the in-game DPScope AI advisor controls.
-- Run from tools with: lua test_aou_ai.lua

function Global(name, value) _G[name] = value end
local section = {}
local output = {}
common = { GetAddonName = function() return "DPScope" end }
userMods = {
    GetGlobalConfigSection = function() return section end,
    SetGlobalConfigSection = function(_, value) section = value end,
}
message = function(value) output[#output + 1] = tostring(value) end
Optim = {
    Memo = { key = "cached" },
    ToWString = function(value) return "W:" .. tostring(value) end
}

dofile("../Scripts/AoUMeterAI.lua")

local function expect(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

expect(DPScopeAI.IsEnabled(), true, "AI advisor default enabled")
local handled = DPScopeAI.OnSlash({ "/aou", "ai", "off" })
expect(handled, true, "AI off command handled")
expect(DPScopeAI.IsEnabled(), false, "AI advisor disabled")
expect(section.aou_ai_enabled, 0, "AI off persisted")
expect(Optim.Memo.key, nil, "AI toggle invalidates optimizer cache")

DPScopeAI.OnSlash({ "/aou", "ai", "on" })
expect(DPScopeAI.IsEnabled(), true, "AI advisor enabled")
expect(section.aou_ai_enabled, 1, "AI on persisted")

local rows = DPScopeAI.BuildLines({
    mode = "hps", eventCount = 120, hpSamples = 110, poolSamples = 100,
    selfAmount = 1000, allyAmount = 9000,
    selfHealPerSecond = 10, allyHealPerSecond = 90, incomingPerSecond = 40,
    survivalDeltaPct = 3.2, hpMax = 10000,
    avgTargetHpPct = 68.4, avgResolve = 36.2, hpSampleLabel = "цели",
    critCount = 3, normalCount = 2, critSamples = 5,
    critRateObserved = 0.60, critMultiplier = 3.09, critPairedCount = 2,
    measuredHealSamples = 60, estimatedHealSamples = 40,
    currentStats = { 100, 200, 300 },
    recommendedStats = { 120, 190, 290 }
})
expect(#rows, 6, "AI panel row count")
expect(rows[1][1], "OptAITitle", "AI title row")
expect(rows[1][2], "LOCAL", "AI row must use ASCII-safe payload")
expect(rows[2][3], "HP 92%", "AI HP payload")
expect(rows[2][4], "RES 83%", "AI Resolve sample coverage")
expect(rows[3][1], "OptAIMeans", "average metrics row")
expect(rows[3][2], "HP цели 68.4%", "average target HP")
expect(rows[3][3], "RES 36.2", "average Resolve")
expect(rows[4][1], "OptAICrit", "critical profile row")
expect(rows[4][2], "Крит 3 / Норм 2", "normal and critical counts")
expect(rows[4][3], "60%", "observed critical share")
expect(rows[4][4], "x3.09", "per-ability observed critical multiplier")
assert(rows[5][2] ~= "Use /aou ai advice", "AI insight row must contain a real finding")
assert(rows[6][2] ~= "Use /aou ai advice", "AI next-step row must contain a real action")
assert(string.find(DPScopeAI.LastSummary, "союзникам", 1, true),
    "HPS AI summary should identify ally-focused healing")
assert(string.find(DPScopeAI.LastSummary, "Следующий шаг", 1, true),
    "AI summary should provide a next test")
assert(not string.find(DPScopeAI.LastSummary, "HP цели=68.4%", 1, true),
    "average target HP must stay in the analysis panel, not chat advice")
assert(string.find(DPScopeAI.LastSummary, "Средняя Решимость=36.2", 1, true),
    "AI summary should report average Resolve")
assert(string.find(DPScopeAI.LastSummary, "Криты=3, обычные=2", 1, true),
    "AI summary should expose normal and critical counts")

local weak = DPScopeAI.Analyze({ mode = "dps", eventCount = 5, hpSamples = 1, poolSamples = 0 })
expect(weak.confidence, "низкая", "low sample confidence")
assert(string.find(weak.nextStep, "30+", 1, true),
    "low sample analysis should ask for more events")
assert(string.find(weak.insight, "Мало событий", 1, true),
    "low sample analysis should not claim the build is already optimal")

local unknownHeal = DPScopeAI.Analyze({
    mode = "hps", eventCount = 50, hpSamples = 45, poolSamples = 45,
    totalHealAmount = 1200, incomingPerSecond = 0
})
assert(string.find(unknownHeal.insight, "получатели", 1, true),
    "HPS analysis should not attribute heals when recipient IDs are missing")
local unknownHealWhileHit = DPScopeAI.Analyze({
    mode = "hps", eventCount = 50, hpSamples = 45, poolSamples = 45,
    totalHealAmount = 1200, incomingPerSecond = 500
})
assert(string.find(unknownHealWhileHit.insight, "получатели", 1, true),
    "HPS analysis should disclose unknown recipients even during incoming damage")

local defense = DPScopeAI.Analyze({
    mode = "tank", eventCount = 45, hpSamples = 0, poolSamples = 0,
    incomingPerSecond = 500, survivalDeltaPct = 4.5, hpMax = 12000
})
expect(defense.confidence, "средняя", "defense confidence uses incoming event count")
assert(string.find(defense.insight, "+4.5%", 1, true),
    "defense analysis should show modeled survivability change")
local defenseRows = DPScopeAI.BuildLines({
    mode = "tank", eventCount = 45, hpSamples = 0, poolSamples = 0,
    incomingPerSecond = 500, survivalDeltaPct = 4.5, hpMax = 12000
})
expect(defenseRows[2][3], "IN", "defense quality uses incoming samples")
expect(defenseRows[2][4], "HP/RES -", "defense quality does not reuse attack sample ratios")

-- Restore the HPS context before testing the advice command: the defensive
-- BuildLines call above intentionally replaced LastSummary with its own mode.
DPScopeAI.BuildLines({
    mode = "hps", eventCount = 120, hpSamples = 110, poolSamples = 100,
    selfAmount = 1000, allyAmount = 9000,
    selfHealPerSecond = 10, allyHealPerSecond = 90, incomingPerSecond = 40,
    survivalDeltaPct = 3.2, hpMax = 10000,
    avgTargetHpPct = 68.4, avgResolve = 36.2, hpSampleLabel = "цели",
    critCount = 3, normalCount = 2, critSamples = 5,
    critRateObserved = 0.60, critMultiplier = 3.09, critPairedCount = 2,
    measuredHealSamples = 60, estimatedHealSamples = 40
})
local beforeStatus = #output
DPScopeAI.OnSlash({ "/aou", "ai", "status" })
local statusOutput = table.concat(output, "\n", beforeStatus + 1)
assert(string.find(statusOutput, "ON", 1, true), "AI status should report ON")
assert(string.find(statusOutput, "Ollama", 1, true), "AI status should describe the local desktop companion")
local beforeAdvice = #output
DPScopeAI.OnSlash({ "/aou", "ai", "advice" })
local adviceOutput = table.concat(output, "\n", beforeAdvice + 1)
assert(string.find(adviceOutput, "W:", 1, true), "Russian chat output should pass through the wide-string converter")
local adviceText = string.gsub(string.gsub(adviceOutput, "W:", ""), "[\\r\\n]", "")
assert(not string.find(adviceText, "HP цели=", 1, true), "chat advice must not print average target HP")
assert(string.find(adviceText, "Средняя Решимость=", 1, true), "chat advice should include average Resolve")
assert(string.find(adviceText, "Криты=3", 1, true), "chat advice should include critical-hit counts")

print("DPScope AI advisor tests passed.")
