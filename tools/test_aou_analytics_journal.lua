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
AOUA.OnFightStart()
expect(AOUA.Session.journal.incomingStats.events, 0, "incoming journal reset at fight start")
expect(next(AOUA.Session.journal.incomingByAbility), nil, "incoming abilities cleared at fight start")
expect(next(AOUA.Session.journal.outgoingByAbility), nil, "outgoing abilities cleared at fight start")
expect(AOUA.Session.rawDiagnostics.incomingCallbacks, 0, "incoming callback counter reset")
expect(AOUA.Session.rawDiagnostics.healCallbacks, 0, "healing callback counter reset")
expect(AOUA.Session.rawDiagnostics.damageFilters, 3, "damage target filter count retained")
expect(AOUA.Session.rawDiagnostics.healFilters, 3, "healing target filter count retained")
expect(AOUA.Session.rawDiagnostics.healthFilters, 3, "health watch count retained")

print("DPScope analytics journal regression tests passed.")
