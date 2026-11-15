-- Focused regression tests for DPScope combat analytics.
-- Run from the tools directory with: lua test_aou_analytics_journal.lua

avatar = {
    GetId = function() return 1001 end
}
enumMode = {
    Dps = 1,
    Def = 2,
    Hps = 3,
    IHps = 4
}

AOUA = nil
dofile("../Scripts/AoUMeterAnalytics.lua")

local function expect(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

-- Outgoing healing must be counted once in the aggregate and once in its
-- per-ability journal row, not twice in the aggregate.
AOUA.OnHit(
    { ID = 1001 },
    enumMode.Hps,
    { heal = 100, amount = 100, overload = 10, resisted = 20, runeResisted = 30, absorbed = 40 },
    50,
    { Name = "Test outgoing heal" }
)
expect(AOUA.Session.healing.amount, 100, "outgoing healing total")
expect(AOUA.Session.healing.events, 1, "outgoing healing events")
local outgoing = AOUA.Session.journal.outgoingHealByAbility["Test outgoing heal"]
assert(outgoing, "outgoing healing ability row missing")
expect(outgoing.amount, 100, "outgoing ability amount")
expect(outgoing.effective, 100, "outgoing applied heal")
expect(outgoing.overload, 10, "outgoing overload modifier")
expect(outgoing.wound, 20, "outgoing wound modifier")
expect(outgoing.runeWound, 30, "outgoing rune modifier")
expect(outgoing.absorbed, 40, "outgoing absorb modifier")
expect(AOUA.Session.healing.effective, 100, "outgoing applied total")
expect(AOUA.Session.healing.overhealUnknown, 1, "outgoing unknown overheal count")
expect(AOUA.Session.healing.reportedOverload, 10, "outgoing reported overload total")
expect(outgoing.events, 1, "outgoing ability events")
expect(AOUA.Session.determinationByMode.healing.samples, 1, "outgoing healing Resolve sample in history")

-- A raw received-heal callback is recorded immediately. The legacy meter then
-- supplies a resolved spell name for the same params table. Relabel the row
-- without incrementing the received-heal total a second time.
local receivedParams = {
    unitId = 1001,
    healerId = 1001,
    heal = 50,
    amount = 50,
    overload = 5,
    resisted = 120,
    runeResisted = 200,
    absorbed = 300
}
AOUA.OnReceivedHeal(receivedParams)
expect(AOUA.Session.receivedHeal.amount, 50, "received healing raw total")
expect(AOUA.Session.receivedHeal.events, 1, "received healing raw events")
AOUA.OnHit(
    nil,
    enumMode.IHps,
    receivedParams,
    nil,
    { Name = "Resolved received heal" }
)
expect(AOUA.Session.receivedHeal.amount, 50, "received healing total after name resolution")
expect(AOUA.Session.receivedHeal.events, 1, "received healing events after name resolution")
expect(AOUA.Session.receivedHeal.effective, 50, "received applied heal despite larger raw modifiers")
expect(AOUA.Session.receivedHeal.reportedOverload, 5, "received overload modifier total")
expect(AOUA.Session.receivedHeal.healResisted, 120, "received wound modifier total")
expect(AOUA.Session.receivedHeal.runeResisted, 200, "received rune modifier total")
expect(AOUA.Session.receivedHeal.healAbsorbed, 300, "received absorbed modifier total")
assert(
    AOUA.Session.journal.receivedHealByAbility.unknown == nil,
    "unknown received-heal row should be moved after resolving the ability name"
)
local received = AOUA.Session.journal.receivedHealByAbility["Resolved received heal"]
assert(received, "resolved received-heal ability row missing")
expect(received.amount, 50, "resolved received-heal ability amount")
expect(received.effective, 50, "resolved received-heal applied amount")
expect(received.overload, 5, "resolved received-heal overload modifier")
expect(received.wound, 120, "resolved received-heal wound modifier")
expect(received.runeWound, 200, "resolved received-heal rune modifier")
expect(received.absorbed, 300, "resolved received-heal absorbed modifier")
expect(received.events, 1, "resolved received-heal ability events")

-- Damage schools should retain the API enum value without its internal prefix.
AOUA.OnIncomingDamage({
    target = 1001,
    amount = 42,
    damageSource = "DamageSource_SPELL",
    sysSubElement = "ENUM_SubElement_ASTRAL",
    ability = "Test incoming spell"
})
local astral = AOUA.Session.journal.incomingByElement.ASTRAL
assert(astral, "ASTRAL damage school row missing")
expect(astral.amount, 42, "ASTRAL damage amount")

-- Damage multipliers can increase damage. overallPreventedDamage is a signed
-- net value (multipliersAbsorb + runesAbsorb), so a negative value is valid and
-- must not be clamped or presented as negative absorption.
AOUA.OnIncomingDamage({
    target = 1001,
    amount = 100,
    damageSource = "DamageSource_SPELL",
    ability = "Test amplified incoming hit",
    overallAbsorbedDamage = 0,
    overallPreventedDamage = -123,
    multipliersAbsorb = -150,
    runesAbsorb = 27
})
expect(AOUA.Session.defense.overallPrevented, -123, "signed net prevented total")
local amplified = AOUA.Session.journal.incomingByAbility["DamageSource_SPELL / Test amplified incoming hit"]
assert(amplified, "amplified incoming ability row missing")
expect(amplified.prevented, -123, "signed net prevented ability value")
expect(amplified.multiplierAbsorb, -150, "negative multiplier component")
expect(amplified.runesAbsorb, 27, "positive rune component")
local _, defenseText = AOUA.OnSlash("defstat")
assert(string.find(defenseText, "net prevented=-123", 1, true), "defense report should label signed net prevention")

-- Outgoing damage uses the same signed target-side modifier semantics.
AOUA.OnHit(
    { ID = 1001 },
    enumMode.Dps,
    {
        amount = 100,
        damageSource = "DamageSource_SPELL",
        ability = "Test amplified outgoing hit",
        overallAbsorbedDamage = 0,
        overallPreventedDamage = -123,
        multipliersAbsorb = -150,
        runesAbsorb = 27
    },
    nil,
    { Name = "Test amplified outgoing hit" }
)
local outgoingDamage = AOUA.Session.journal.outgoingByAbility["DamageSource_SPELL / Test amplified outgoing hit"]
assert(outgoingDamage, "amplified outgoing ability row missing")
expect(outgoingDamage.prevented, -123, "signed outgoing target net prevention")
local _, eventsText = AOUA.OnSlash("events")
assert(string.find(eventsText, "target absorbed/net prevented=0/-123", 1, true),
    "event report should label target-side signed net prevention")
assert(string.find(eventsText, "Negative net prevented values indicate damage amplification", 1, true),
    "event report should explain negative net prevention")

-- The detailed journal is per-fight; registration counts survive the reset.
AOUA.OnEventRegistrationStats(3, 3, 3)
local beforeResetEvents = AOUA.Session.journal.incomingStats.events
assert(beforeResetEvents > 0, "expected incoming journal data before fight reset")
AOUA.HpCache[2002] = { value = 123, limit = 1000, real = true, second = 99 }
AOUA.HealthTransitions[2002] = { beforeFrac = 0.5, direction = -1, delta = -10, limit = 1000, exact = true }
AOUA.OnFightStart()
expect(next(AOUA.Session.targetProfiles), nil, "live target profiles cleared between fights")
expect(next(AOUA.HpCache), nil, "HP cache cleared between fights")
expect(next(AOUA.HealthTransitions), nil, "HP transitions cleared between fights")
expect(AOUA.Session.journal.incomingStats.events, 0, "incoming journal reset at fight start")
expect(next(AOUA.Session.journal.incomingByAbility), nil, "incoming abilities cleared at fight start")
expect(next(AOUA.Session.journal.outgoingByAbility), nil, "outgoing abilities cleared at fight start")
expect(AOUA.Session.rawDiagnostics.incomingCallbacks, 0, "incoming callback counter reset")
expect(AOUA.Session.rawDiagnostics.healCallbacks, 0, "healing callback counter reset")
expect(AOUA.Session.rawDiagnostics.damageFilters, 3, "damage target filter count retained")
expect(AOUA.Session.rawDiagnostics.healFilters, 3, "healing target filter count retained")
expect(AOUA.Session.rawDiagnostics.healthFilters, 3, "health watch count retained")


-- Raw event history is isolated from /aou rec rows, survives fight stop,
-- and exports using the existing AOUCSV chunk protocol.
local persistedConfig = {}
local emittedMessages = {}
common = { GetAddonName = function() return "DPScope" end }
userMods = {
    GetGlobalConfigSection = function() return persistedConfig end,
    SetGlobalConfigSection = function(_, value) persistedConfig = value end,
}
message = function(value) emittedMessages[#emittedMessages + 1] = value end
avatar.IsExist = function() return true end
Optim = {
    MyId = 1001,
    GetHealth = function() return 500, 1000, true end,
    ReadStats = function()
        return {
            M = { total = 101 }, R = { total = 202 }, U = { total = 303 }, L = { total = 40 },
            S = { total = 55 }, W = { total = 66 }, B = { total = 77 }, C = { total = 88 }
        }
    end
}
AOUA.Profile = "raid"
object = {
    IsUnit = function(id) return id == 1001 or id == 2002 end,
    GetName = function(id)
        if id == 1001 then return "Test Actor" end
        if id == 2002 then return "Test Target" end
        return ""
    end,
    IsMob = function(id) return id == 2002 end,
    IsPlayer = function(id) return id == 1001 end,
    IsExist = function() return true end
}
unit = {
    GetLevel = function() return 90 end,
    GetQuality = function(id) return id == 2002 and 4 or 0 end
}
AOUA.OnFightStart()
AOUA.OnHit(
    { ID = 1001 },
    enumMode.Dps,
    { source = 1001, target = 2002, amount = 125, isCritical = true, sysSubElement = "ENUM_SubElement_PHYSICAL",
      damageSource = "DamageSource_SPELL", ability = "Recorded damage", resist = 10, runesAbsorb = 5 },
    42,
    { Name = "Recorded damage" }
)
local targetRows, targetTotal = AOUA.GetTargetDisplayRows(4)
expect(targetTotal, 1, "live target profile count")
expect(targetRows[1].name, "Test Target", "live target name")
expect(targetRows[1].kind, "mob", "live target category")
expect(targetRows[1].level, 90, "live target level")
expect(targetRows[1].quality, 4, "live target quality")
expect(targetRows[1].hpCurrent, 500, "live target current HP")
expect(targetRows[1].hpLimit, 1000, "live target maximum HP")
expect(targetRows[1].hpPercent, 50, "live target HP percent")
expect(targetRows[1].resistTotal, 10, "live target resisted damage amount")
expect(targetRows[1].resistSchools[1].element, "PHYSICAL", "live target resistance school")
expect(targetRows[1].resistSchools[1].samples, 1, "live target resistance sample count")

-- The selected-target getter may be nil; outgoing damage must use params.target.
-- Distinct ObjectId wrappers representing the same player must still match.
local originalAvatarGetId = avatar.GetId
avatar.GetTarget = function() return nil end
avatar.GetId = function() return { GetId = function() return 1001 end } end
AOUA.OnFightStart()
AOUA.OnHit(
    { ID = { GetId = function() return 1001 end } },
    enumMode.Dps,
    { source = 1001, target = 2002, amount = 111, resist = 7,
      sysSubElement = "ENUM_SubElement_FIRE", ability = "Target from event" },
    nil,
    { Name = "Target from event" }
)
expect(AOUA.Session.damage.events, 1, "outgoing hit accepted with nil selected target")
expect(AOUA.Session.rawDiagnostics.outgoingHitCallbacks, 1, "outgoing hit callback count")
expect(AOUA.Session.rawDiagnostics.outgoingHitOwnerMatched, 1, "ObjectId wrapper owner match")
expect(AOUA.Session.rawDiagnostics.outgoingHitAccepted, 1, "outgoing hit accepted count")
expect(AOUA.Session.rawDiagnostics.outgoingHitOtherCombatant, 0, "outgoing hit not misclassified as another actor")
expect(AOUA.Session.rawDiagnostics.lastOutgoingTarget, "2002", "last outgoing event target")
local eventTargetRows, eventTargetTotal = AOUA.GetTargetDisplayRows(4)
expect(eventTargetTotal, 1, "event target profile without selected target")
expect(eventTargetRows[1].name, "Test Target", "event target name without selected target")
expect(eventTargetRows[1].level, 90, "event target level without selected target")
expect(eventTargetRows[1].hpCurrent, 500, "event target HP without selected target")
expect(eventTargetRows[1].resistSchools[1].amount, 7, "event target resistance without selected target")
avatar.GetId = originalAvatarGetId

-- Simulate the real TUMeter stop/start lifecycle: final target rows stay on
-- the stopped fight and move to Previous when the next fight begins.
Global = function(name, value) _G[name] = value end
group = { IsCreatureInGroup = function() return false end }
dofile("../Scripts/AoUMeterData.lua")
local function makeFightStub()
    return {
        StopFight = function() end,
        StartFight = function() end
    }
end
local currentFight = makeFightStub()
local totalFight = makeFightStub()
local simulatedMeter = setmetatable({
    FightsList = { [1] = totalFight, [2] = {}, [3] = currentFight },
    Fight = { Total = 1, Previous = 2, Current = 3 },
    bCollectData = true,
    CopyFightFromCurrenToPrev = function(self)
        local previousRows = {}
        for i, row in ipairs(self.FightsList[3].AOUATargetRows or {}) do
            local copied = {}
            for key, value in pairs(row) do copied[key] = value end
            previousRows[i] = copied
        end
        self.FightsList[2] = { AOUATargetRows = previousRows }
    end,
    ResetFight = function() end,
    RegenCombatantList = function() end
}, { __index = TUMeter })
simulatedMeter:Stop()
expect(currentFight.AOUATargetRows[1].name, "Test Target", "stopped fight keeps target snapshot")
simulatedMeter:Start()
expect(simulatedMeter.FightsList[2].AOUATargetRows[1].name, "Test Target", "target snapshot copied to previous fight")
expect(currentFight.AOUATargetRows, nil, "new current fight does not inherit old targets")
local clearedRows, clearedTotal = AOUA.GetTargetDisplayRows(4)
expect(clearedTotal, 0, "new current fight starts with empty target profiles")

AOUA.OnHit(
    { ID = 1001 },
    enumMode.Hps,
    { unitId = 1001, heal = 80, amount = 80, isCritical = false },
    35,
    { Name = "Recorded self heal" }
)
AOUA.OnIncomingDamage({
    target = 1001, amount = 50, ability = "Recorded incoming",
    sysSubElement = "ENUM_SubElement_FIRE", runesAbsorb = 12
})
expect(#AOUA.Session.eventSamples, 3, "raw event buffer count")

-- An exact health-change callback is already a pre-hit sample. The following
-- incoming-damage callback must consume it without another GetHealthInfo read.
local healthReads = 0
Optim.GetHealth = function()
    healthReads = healthReads + 1
    return 400, 1000, true
end
AOUA.OnHealthChanged({ id = 1001, healthDelta = -50, healthLimitDelta = 0 })
local readsAfterHealthEvent = healthReads
AOUA.OnIncomingDamage({ target = 1001, amount = 50, ability = "Transition correlation" })
expect(healthReads, readsAfterHealthEvent, "incoming hit reuses exact health transition")
expect(#AOUA.Session.eventSamples, 4, "transition incoming event sample appended")
local transitionRow = AOUA.Session.eventSamples[#AOUA.Session.eventSamples]
assert(transitionRow:find("|50.0000|45.0000|measured_pre|1000.0000|", 1, true),
    "incoming sample should preserve exact pre-hit health fraction")
expect(AOUA.Session.eventSamples[1]:find("damage", 1, true) ~= nil, true, "outgoing damage sample saved")

local function splitPipe(value)
    local cells = {}
    for cell in (value .. "|"):gmatch("(.-)|") do cells[#cells + 1] = cell end
    return cells
end
local damageFields = splitPipe(AOUA.Session.eventSamples[1])
expect(damageFields[38], "Test Actor", "actor name metadata")
expect(damageFields[39], "90.0000", "actor level metadata")
expect(damageFields[42], "player", "actor kind metadata")
expect(damageFields[43], "0", "actor mob classification")
expect(damageFields[44], "Test Target", "target name metadata")
expect(damageFields[45], "90.0000", "target level metadata")
expect(damageFields[46], "4.0000", "target quality metadata")
expect(damageFields[48], "mob", "target kind metadata")
expect(damageFields[49], "1", "target mob classification")
expect(damageFields[50], "500.0000", "target current HP snapshot")
expect(damageFields[52], "1000.0000", "target HP limit snapshot")
expect(damageFields[53], "measured", "target HP snapshot quality")
-- Schema v3 appends actor/target descriptors after the v2 columns, so old
-- persisted rows remain aligned and receive blank trailing metadata on export.
expect(AOUA.Session.eventSamples[2]:find("|35.0000|self|Recorded self heal|", 1, true) ~= nil, true,
    "self-heal Resolve and recipient saved")
local savedOk, savedCount = AOUA.OnFightStop()
expect(savedOk, true, "event history persisted")
expect(savedCount, 4, "persisted event count")
expect(persistedConfig.aou_evt_count, 4, "event config count")
expect(persistedConfig.aou_evt_schema, "v3", "event schema version")
expect(persistedConfig.aou_rec_count, nil, "legacy record keys untouched")
local exportOk = AOUA.EventExport(3)
expect(exportOk, true, "event export success")
assert(emittedMessages[1] == "AOUCSV|BEGIN|3|3|events", "event export begin marker missing")
assert(emittedMessages[#emittedMessages] == "AOUCSV|END", "event export end marker missing")

-- Unknown object kinds must remain separate by ObjectId in the live UI profile.
AOUA.OnFightStart()
AOUA.OnHit({ ID = 1001 }, enumMode.Dps,
    { source = 1001, target = 3001, amount = 20, ability = "Unknown target A" }, nil,
    { Name = "Unknown target A" })
AOUA.OnHit({ ID = 1001 }, enumMode.Dps,
    { source = 1001, target = 3002, amount = 30, ability = "Unknown target B" }, nil,
    { Name = "Unknown target B" })
local unknownRows, unknownTotal = AOUA.GetTargetDisplayRows(4)
expect(unknownTotal, 2, "unknown target object IDs remain separate")
expect(unknownRows[1].kind, "unknown", "unknown target category")
expect(unknownRows[1].name, "", "unknown target name remains unavailable")
AOUA.OnFightStart()

-- The bounded event buffer must keep the newest 2,000 samples without
-- shifting the whole table on every callback after it fills.
AOUA.OnFightStart()
for i = 1, 2005 do
    AOUA.OnHit(
        { ID = 1001 }, enumMode.Dps,
        { target = 2002, amount = i, ability = "Ring buffer test" },
        nil, { Name = "Ring buffer test" }
    )
end
expect(AOUA.Session.eventSampleCount, 2000, "ring buffer sample count")
expect(AOUA.Session.eventSamplesDropped, 5, "ring buffer overwritten rows")
local ringFirst = AOUA.Session.eventSamples[6]
local ringLast = AOUA.Session.eventSamples[5]
assert(ringFirst:find("|6.0000|", 1, true), "ring buffer oldest sample should be event 6")
assert(ringLast:find("|2005.0000|", 1, true), "ring buffer newest sample should be event 2005")
local ringSaved, ringCount = AOUA.OnFightStop()
expect(ringSaved, true, "ring buffer persistence")
expect(ringCount, 2000, "ring buffer rows persisted before history cap")
expect(persistedConfig.aou_evt_count, 1000, "persisted event history remains capped")
assert(persistedConfig.aou_evt_1:find("|1006.0000|", 1, true),
    "persisted history should begin with newest 1,000 ring rows")
assert(persistedConfig.aou_evt_1000:find("|2005.0000|", 1, true),
    "persisted history should end with latest event")

print("DPScope analytics journal regression tests passed.")
