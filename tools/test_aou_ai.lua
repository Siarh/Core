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
Optim = { Memo = { key = "cached" } }

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
    measuredHealSamples = 60, estimatedHealSamples = 40,
    currentStats = { 100, 200, 300 },
    recommendedStats = { 120, 190, 290 }
})
expect(#rows, 4, "AI panel row count")
expect(rows[1][1], "OptAITitle", "AI title row")
expect(rows[1][2], "LOCAL", "AI row must use ASCII-safe payload")
expect(rows[2][3], "HP 92%", "AI HP payload")
expect(rows[2][4], "RES 83%", "AI Resolve payload")
assert(rows[3][2] ~= "Use /aou ai advice", "AI insight row must contain a real finding")
assert(rows[4][2] ~= "Use /aou ai advice", "AI next-step row must contain a real action")
assert(string.find(DPScopeAI.LastSummary, "союзникам", 1, true),
    "HPS AI summary should identify ally-focused healing")
assert(string.find(DPScopeAI.LastSummary, "Следующий шаг", 1, true),
    "AI summary should provide a next test")

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

DPScopeAI.OnSlash({ "/aou", "ai", "status" })
assert(string.find(output[#output], "ON", 1, true), "AI status should report ON")
assert(string.find(output[#output], "Ollama", 1, true), "AI status should describe the local desktop companion")

print("DPScope AI advisor tests passed.")
