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
    measuredHealSamples = 60, estimatedHealSamples = 40,
    currentStats = { 100, 200, 300 },
    recommendedStats = { 120, 190, 290 }
})
expect(#rows, 4, "AI panel row count")
expect(rows[1][1], "OptAITitle", "AI title row")
assert(string.find(DPScopeAI.LastSummary, "союзникам", 1, true),
    "HPS AI summary should identify ally-focused healing")
assert(string.find(DPScopeAI.LastSummary, "Следующий шаг", 1, true),
    "AI summary should provide a next test")

local weak = DPScopeAI.Analyze({ mode = "dps", eventCount = 5, hpSamples = 1, poolSamples = 0 })
expect(weak.confidence, "низкая", "low sample confidence")
assert(string.find(weak.insight, "мало событий", 1, true),
    "low sample analysis should ask for more events")

DPScopeAI.OnSlash({ "/aou", "ai", "status" })
assert(string.find(output[#output], "ON", 1, true), "AI status should report ON")

print("DPScope AI advisor tests passed.")
