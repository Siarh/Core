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

print("DPScope analytics journal regression tests passed.")
