--------------------------------------------------------------------------------
-- File: AoUMeterAnalytics.lua
-- DPScope build 28 analytics for Allods Sunshine 6.0
-- Event-driven measurements. Unknown / unavailable values are not fabricated.
--------------------------------------------------------------------------------

AOUA = AOUA or {}
AOUA.Version = "28"
AOUA.HpCache = AOUA.HpCache or {}
AOUA.HealthTransitions = AOUA.HealthTransitions or {}
AOUA.Profile = AOUA.Profile or "pve"

local PHASES = {
    { key = "100_75", label = "100-75%", min = 0.75 },
    { key = "75_50",  label = "75-50%",  min = 0.50 },
    { key = "50_25",  label = "50-25%",  min = 0.25 },
    { key = "25_0",   label = "25-0%",   min = 0.00 }
}

local function N(v)
    local x = tonumber(v)
    if x == nil then return 0 end
    return x
end

local function bucket()
    return {
        events = 0, amount = 0, crits = 0, glancing = 0,
        effective = 0, overheal = 0, reportedOverheal = 0,
        healResisted = 0, runeResisted = 0, healAbsorbed = 0,
        hpMeasured = 0, hpEstimated = 0, hpUnknown = 0,
        determinationSum = 0, determinationSamples = 0,
        last = {}
    }
end

local function freshDeterminationStats()
    return { sum = 0, min = nil, max = nil, samples = 0,
        above50 = 0, above67 = 0, above90 = 0 }
end

local function freshJournal()
    return {
        incomingByType = {}, incomingByAbility = {}, incomingByAttacker = {},
        incomingTargetEffects = {}, incomingSourceEffects = {}, incomingByElement = {},
        outgoingByType = {}, outgoingByAbility = {}, outgoingByElement = {},
        outgoingTargetEffects = {}, outgoingSourceEffects = {},
        receivedHealByAbility = {}, outgoingHealByAbility = {},
        incomingStats = {
            events = 0, amount = 0, zeroAmountEvents = 0,
            fullyAbsorbedEvents = 0, fullyPreventedEvents = 0,
            dodgedEvents = 0, missedEvents = 0, otherZeroAmountEvents = 0
        }
    }
end

local function freshSession()
    return {
        damage = bucket(), incoming = bucket(),
        healing = bucket(), receivedHeal = bucket(),
        phases = {
            damage_100_75 = bucket(), damage_75_50 = bucket(),
            damage_50_25 = bucket(), damage_25_0 = bucket(),
            healing_100_75 = bucket(), healing_75_50 = bucket(),
            healing_50_25 = bucket(), healing_25_0 = bucket()
        },
        defense = {
            events = 0, amount = 0, shieldBlock = 0, parry = 0,
            resist = 0, barrier = 0, absorb = 0, runesAbsorb = 0,
            toMount = 0, multipliersAbsorb = 0,
            overallAbsorbed = 0, overallPrevented = 0,
            totalAbsorbedSamples = 0, totalPreventedSamples = 0,
            shieldPoolLoss = 0, shieldPoolGain = 0, shieldPoolSamples = 0,
            zeroAmountEvents = 0, fullyAbsorbedEvents = 0,
            fullyPreventedEvents = 0, dodgedEvents = 0, missedEvents = 0,
            otherZeroAmountEvents = 0
        },
        journal = freshJournal(),
        rawDiagnostics = {
            incomingCallbacks = 0, incomingMatched = 0, incomingOther = 0, incomingAccepted = 0,
            healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0
        },
        determination = freshDeterminationStats(),
        determinationByMode = {
            damage = freshDeterminationStats(),
            healing = freshDeterminationStats()
        },
        targetHealth = { samples = 0, estimated = 0, unknown = 0, changedEvents = 0 },
        started = false
    }
end

AOUA.Session = AOUA.Session or freshSession()
local function ensureSession()
    if not AOUA.Session.damage or not AOUA.Session.phases or
        not AOUA.Session.defense or not AOUA.Session.determination or
        not AOUA.Session.targetHealth then
        AOUA.Session = freshSession()
    end
    AOUA.Session.determinationByMode = AOUA.Session.determinationByMode or {}
    for _, name in ipairs({ "damage", "healing" }) do
        if not AOUA.Session.determinationByMode[name] then
            AOUA.Session.determinationByMode[name] = freshDeterminationStats()
        end
    end
    for _, name in ipairs({ "healing", "receivedHeal" }) do
        local b = AOUA.Session[name]
        b.healResisted = b.healResisted or 0
        b.runeResisted = b.runeResisted or 0
        b.healAbsorbed = b.healAbsorbed or 0
    end
    local d = AOUA.Session.defense
    d.shieldPoolLoss = d.shieldPoolLoss or 0
    d.shieldPoolGain = d.shieldPoolGain or 0
    d.shieldPoolSamples = d.shieldPoolSamples or 0
    d.zeroAmountEvents = d.zeroAmountEvents or 0
    d.fullyAbsorbedEvents = d.fullyAbsorbedEvents or 0
    d.fullyPreventedEvents = d.fullyPreventedEvents or 0
    d.dodgedEvents = d.dodgedEvents or 0
    d.missedEvents = d.missedEvents or 0
    d.otherZeroAmountEvents = d.otherZeroAmountEvents or 0
    AOUA.Session.journal = AOUA.Session.journal or freshJournal()
    AOUA.Session.rawDiagnostics = AOUA.Session.rawDiagnostics or {
        incomingCallbacks = 0, incomingMatched = 0, incomingOther = 0, incomingAccepted = 0,
        healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0
    }
    local j = AOUA.Session.journal
    for _, key in ipairs({
        "incomingByType", "incomingByAbility", "incomingByAttacker",
        "incomingTargetEffects", "incomingSourceEffects", "incomingByElement",
        "outgoingByType", "outgoingByAbility", "outgoingByElement",
        "outgoingTargetEffects", "outgoingSourceEffects",
        "receivedHealByAbility", "outgoingHealByAbility"
    }) do j[key] = j[key] or {} end
    j.incomingStats = j.incomingStats or {
        events = 0, amount = 0, zeroAmountEvents = 0,
        fullyAbsorbedEvents = 0, fullyPreventedEvents = 0,
        dodgedEvents = 0, missedEvents = 0, otherZeroAmountEvents = 0
    }
    AOUA.Session.targetHealth.changedEvents = AOUA.Session.targetHealth.changedEvents or 0
end
ensureSession()

-- Detailed API journal is fight-scoped; keep the last one until the next fight.
function AOUA.OnFightStart()
    ensureSession()
    AOUA.Session.journal = freshJournal()
    AOUA.Session.rawDiagnostics = {
        incomingCallbacks = 0, incomingMatched = 0, incomingOther = 0, incomingAccepted = 0,
        healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0
    }
end

local function safeHealth(id)
    if not id or not Optim or type(Optim.GetHealth) ~= "function" then return nil end
    local ok, value, limit, real = pcall(Optim.GetHealth, id)
    if not ok or value == nil or not limit or limit <= 0 then return nil end
    return value, limit, real == true
end

local function phaseFor(frac)
    if frac >= 0.75 then return "100_75" end
    if frac >= 0.50 then return "75_50" end
    if frac >= 0.25 then return "50_25" end
    return "25_0"
end

local function addEvent(b, amount, params)
    b.events = b.events + 1
    b.amount = b.amount + amount
    if params.isCritical then b.crits = b.crits + 1 end
    if params.isGlancing then b.glancing = b.glancing + 1 end
    b.last[#b.last + 1] = { amount = amount, crit = params.isCritical and 1 or 0 }
    if #b.last > 20 then table.remove(b.last, 1) end
end

local function addDetermination(value, activity)
    value = tonumber(value)
    if value == nil or value <= 0 then return end
    local function addTo(d)
        d.samples = d.samples + 1
        d.sum = d.sum + value
        if d.min == nil or value < d.min then d.min = value end
        if d.max == nil or value > d.max then d.max = value end
        if value >= 50 then d.above50 = d.above50 + 1 end
        if value >= 67 then d.above67 = d.above67 + 1 end
        if value >= 90 then d.above90 = d.above90 + 1 end
    end
    addTo(AOUA.Session.determination)
    local byMode = AOUA.Session.determinationByMode
    if activity and byMode and byMode[activity] then addTo(byMode[activity]) end
end

local function recordHealthPhase(kind, params, amount, confidence)
    local id
    if kind == "damage" then id = params.target
    elseif kind == "healing" or kind == "receivedHeal" then id = params.unitId end
    if not id and kind == "damage" and Optim and Optim.GetTarget then
        local ok, target = pcall(Optim.GetTarget)
        if ok then id = target end
    end
    -- Keep the previous percentage-only snapshot: GetHealthInfo may expose enemy HP
    -- as valuePercents only, without absolute HP. That snapshot is the best available
    -- pre-hit estimate for the next event; using the current post-hit percentage for
    -- every hit incorrectly pins an entire fight to one phase.
    local previous = id and AOUA.HpCache[id] or nil
    local value, limit, real = safeHealth(id)
    local transition = AOUA.HealthTransitions[id]
    local expectedDirection = (kind == "damage") and -1 or 1
    local useTransition = false
    if transition then
        if transition.direction == expectedDirection and transition.beforeFrac ~= nil then
            if transition.delta ~= nil then
                local difference = math.abs(math.abs(transition.delta) - amount)
                useTransition = difference <= math.max(2, amount * 0.05)
            else
                -- Percent-only delta: useful phase estimate, but not a measured HP amount.
                useTransition = true
            end
        end
        -- Never let an unmatched or opposite-direction transition leak into a later hit.
        if not useTransition then AOUA.HealthTransitions[id] = nil end
    end
    if value == nil and not useTransition then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return
    end
    if (kind == "healing" or kind == "receivedHeal") and not real and not useTransition then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return
    end

    if value ~= nil then AOUA.HpCache[id] = { value = value, limit = limit, real = real } end
    local frac
    if useTransition then
        frac = transition.beforeFrac
        AOUA.HealthTransitions[id] = nil
        if transition.exact then confidence = "reported" else confidence = "estimated" end
    elseif kind == "damage" and real then
        -- Fallback only: reconstruct pre-hit HP from a post-hit exact snapshot.
        frac = math.min(1, math.max(0, (value + amount) / limit))
    elseif kind == "damage" and not real and previous and previous.value ~= nil
        and previous.limit and previous.limit > 0 then
        -- Enemy API often reports only percentages. Use the preceding sample as
        -- pre-hit HP instead of repeatedly classifying by the current post-hit HP.
        frac = previous.value / previous.limit
        confidence = "estimated"
    elseif (kind == "healing" or kind == "receivedHeal") and real then
        frac = math.min(1, math.max(0, (value - amount) / limit))
    elseif (kind == "healing" or kind == "receivedHeal") and not real
        and previous and previous.value ~= nil and previous.limit and previous.limit > 0 then
        frac = previous.value / previous.limit
        confidence = "estimated"
    else
        frac = value / limit
    end
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    AOUA.Session.targetHealth.samples = AOUA.Session.targetHealth.samples + 1
    local key = kind .. "_" .. phaseFor(frac)
    local b = AOUA.Session.phases[key]
    if b then
        addEvent(b, amount, params)
        if confidence == "reported" and real then
            b.hpMeasured = b.hpMeasured + 1
        else
            b.hpEstimated = b.hpEstimated + 1
            AOUA.Session.targetHealth.estimated = AOUA.Session.targetHealth.estimated + 1
        end
    end
end

-- Health-change events provide the before/after delta directly. They are
-- correlated with personal damage/heal events by target, direction and (when
-- exact HP is available) amount; percent-only transitions remain estimates.
function AOUA.OnHealthChanged(params)
    if type(params) ~= "table" or not params.id then return end
    ensureSession()
    local id = params.id
    local delta = tonumber(params.healthDelta)
    local percentDelta = tonumber(params.healthPercentsDelta)
    local value, limit, real = safeHealth(id)
    local afterFrac
    if value ~= nil and limit and limit > 0 then
        afterFrac = value / limit
    elseif percentDelta ~= nil then
        local old = AOUA.HpCache[id]
        if old and old.value ~= nil and old.limit and old.limit > 0 then
            afterFrac = old.value / old.limit + percentDelta / 100
        end
    end
    local beforeFrac
    local limitDelta = tonumber(params.healthLimitDelta) or 0
    if real and delta ~= nil and limit and (limit - limitDelta) > 0 then
        beforeFrac = (value - delta) / (limit - limitDelta)
    elseif afterFrac ~= nil and percentDelta ~= nil then
        beforeFrac = afterFrac - percentDelta / 100
    end
    if beforeFrac ~= nil then
        beforeFrac = math.max(0, math.min(1, beforeFrac))
        local directionDelta = delta
        if directionDelta == nil or directionDelta == 0 then directionDelta = percentDelta end
        AOUA.HealthTransitions[id] = {
            beforeFrac = beforeFrac,
            direction = directionDelta and (directionDelta < 0 and -1 or (directionDelta > 0 and 1 or 0)) or 0,
            delta = delta,
            exact = (delta ~= nil and real == true)
        }
        AOUA.Session.targetHealth.changedEvents = AOUA.Session.targetHealth.changedEvents + 1
    end
    if value ~= nil then
        AOUA.HpCache[id] = { value = value, limit = limit, real = real }
    end
    local additionalDelta = tonumber(params.additionalDelta)
    if additionalDelta ~= nil and avatar and avatar.GetId then
        local ok, playerId = pcall(avatar.GetId)
        if ok and id == playerId then
            local d = AOUA.Session.defense
            d.shieldPoolSamples = d.shieldPoolSamples + 1
            if additionalDelta < 0 then
                d.shieldPoolLoss = d.shieldPoolLoss - additionalDelta
            elseif additionalDelta > 0 then
                d.shieldPoolGain = d.shieldPoolGain + additionalDelta
            end
        end
    end
end


local function eventText(value)
    if value == nil then return nil end
    if common and type(common.IsWString) == "function" and userMods and type(userMods.FromWString) == "function" then
        local ok, wide = pcall(common.IsWString, value)
        if ok and wide then
            local okText, plain = pcall(userMods.FromWString, value)
            if okText and plain ~= nil then value = plain end
        end
    end
    local text = string.gsub(tostring(value), "[%c|]", " ")
    return text ~= "" and text or nil
end

local function resourceKey(value)
    if value == nil then return nil end
    if type(value) == "string" or type(value) == "number" then return tostring(value) end
    local ok, id = pcall(function() return value:GetInstanceId() end)
    return (ok and id ~= nil) and tostring(id) or nil
end

local function abilityLabel(params)
    local name = eventText(params.ability)
    local id = resourceKey(params.spellId or params.abilityId or params.buffId)
    if name and id then return name .. " [" .. id .. "]" end
    return name or (id and ("id:" .. id)) or "unknown"
end

local function journalRow(map, key, limit)
    key = eventText(key) or "unknown"
    if #key > 72 then key = string.sub(key, 1, 72) end
    if map[key] then return map[key] end
    if (map._count or 0) >= (limit or 48) then
        if map["(other)"] then return map["(other)"] end
        key = "(other)"
    end
    local row = { events = 0, amount = 0 }
    map[key] = row
    map._count = (map._count or 0) + 1
    return row
end

local function tagInfo(tag)
    local ok, info = pcall(function() return tag:GetInfo() end)
    if not ok or type(info) ~= "table" then return nil, nil end
    return eventText(info.shortName) or eventText(info.name), info.isHelpful
end

local function addTagRows(map, tags, amount)
    if type(tags) ~= "table" then return end
    for _, tag in pairs(tags) do
        local name, helpful = tagInfo(tag)
        if name then
            local row = journalRow(map, name, 48)
            row.events = row.events + 1
            row.amount = row.amount + amount
            if helpful == true then row.helpful = (row.helpful or 0) + 1 end
            if helpful == false then row.harmful = (row.harmful or 0) + 1 end
        end
    end
end

local function recordDamageJournal(activity, params, amount)
    local j = AOUA.Session.journal
    local sourceType = eventText(params.damageSource) or "unknown"
    local ability = sourceType .. " / " .. abilityLabel(params)
    local typeMap, abilityMap = j[activity .. "ByType"], j[activity .. "ByAbility"]
    local elementMap = j[activity .. "ByElement"]
    if elementMap then
        local row = journalRow(elementMap, element, 48)
        row.events, row.amount = row.events + 1, row.amount + amount
    end
    if typeMap then
        local row = journalRow(typeMap, sourceType, 48)
        row.events, row.amount = row.events + 1, row.amount + amount
        row.absorbed = (row.absorbed or 0) + N(params.overallAbsorbedDamage)
        row.prevented = (row.prevented or 0) + N(params.overallPreventedDamage)
        row.runesAbsorb = (row.runesAbsorb or 0) + N(params.runesAbsorb)
        row.buffAbsorb = (row.buffAbsorb or 0) + N(params.absorb)
        row.barrier = (row.barrier or 0) + N(params.barrier)
        row.mount = (row.mount or 0) + N(params.toMount)
        row.multiplierAbsorb = (row.multiplierAbsorb or 0) + N(params.multipliersAbsorb)
        row.block = (row.block or 0) + N(params.shieldBlock)
        row.parry = (row.parry or 0) + N(params.parry)
        row.resist = (row.resist or 0) + N(params.resist)
    end
    if abilityMap then
        local row = journalRow(abilityMap, ability, 64)
        row.events, row.amount = row.events + 1, row.amount + amount
        row.crits = (row.crits or 0) + (params.isCritical and 1 or 0)
        row.absorbed = (row.absorbed or 0) + N(params.overallAbsorbedDamage)
        row.prevented = (row.prevented or 0) + N(params.overallPreventedDamage)
        row.runesAbsorb = (row.runesAbsorb or 0) + N(params.runesAbsorb)
        row.buffAbsorb = (row.buffAbsorb or 0) + N(params.absorb)
        row.barrier = (row.barrier or 0) + N(params.barrier)
        row.mount = (row.mount or 0) + N(params.toMount)
        row.multiplierAbsorb = (row.multiplierAbsorb or 0) + N(params.multipliersAbsorb)
        row.block = (row.block or 0) + N(params.shieldBlock)
        row.parry = (row.parry or 0) + N(params.parry)
        row.resist = (row.resist or 0) + N(params.resist)
    end
    if activity == "incoming" then
        local attacker = eventText(params.sourceName) or resourceKey(params.source) or "unknown"
        local row = journalRow(j.incomingByAttacker, attacker, 48)
        row.events, row.amount = row.events + 1, row.amount + amount
        addTagRows(j.incomingTargetEffects, params.targetTags, amount)
        addTagRows(j.incomingSourceEffects, params.sourceTags, amount)
    else
        addTagRows(j.outgoingTargetEffects, params.targetTags, amount)
        addTagRows(j.outgoingSourceEffects, params.sourceTags, amount)
    end
end

local function recordHealingJournal(kind, params, amount, effective, overheal, known)
    local map = (kind == "receivedHeal") and AOUA.Session.journal.receivedHealByAbility
        or AOUA.Session.journal.outgoingHealByAbility
    local row = journalRow(map, abilityLabel(params), 64)
    row.events, row.amount = row.events + 1, row.amount + amount
    row.effective = (row.effective or 0) + (effective or 0)
    row.overheal = (row.overheal or 0) + (overheal or 0)
    row.wound = (row.wound or 0) + N(params.resisted)
    row.runeWound = (row.runeWound or 0) + N(params.runeResisted)
    row.absorbed = (row.absorbed or 0) + N(params.absorbed)
    row.lifeSteal = (row.lifeSteal or 0) + (params.isLifeSteal and 1 or 0)
    row.crits = (row.crits or 0) + (params.isCritical and 1 or 0)
    local lethality = tonumber(params.lethality)
    if lethality ~= nil then
        row.lethalitySum = (row.lethalitySum or 0) + lethality
        row.lethalitySamples = (row.lethalitySamples or 0) + 1
    end
    if known then row.known = (row.known or 0) + 1 else row.unknown = (row.unknown or 0) + 1 end
end

local function isLocalObject(id)
    if not id or not avatar or type(avatar.GetId) ~= "function" then return false end
    local ok, playerId = pcall(avatar.GetId)
    return ok and id == playerId
end

local function recordHealing(kind, params, amount)
    local b = AOUA.Session[kind]
    if amount > 0 then addEvent(b, amount, params) end
    local reported = tonumber(params.overload)
    local resisted, runeResisted, absorbed = math.max(0, N(params.resisted)),
        math.max(0, N(params.runeResisted)), math.max(0, N(params.absorbed))
    b.healResisted = b.healResisted + resisted
    b.runeResisted = b.runeResisted + runeResisted
    b.healAbsorbed = b.healAbsorbed + absorbed
    local reportedLoss = resisted + runeResisted + absorbed
    local effective, overheal, method
    if reported ~= nil then
        overheal = math.max(0, math.min(amount, reported))
        effective = math.max(0, amount - overheal - reportedLoss)
        method = "reported"
    elseif amount > 0 then
        local hp, maxHp, real = safeHealth(params.unitId)
        local previous = params.unitId and AOUA.HpCache[params.unitId] or nil
        local transition = params.unitId and AOUA.HealthTransitions[params.unitId] or nil
        local gained
        if transition and transition.direction == 1 and transition.delta and transition.delta > 0 then
            gained = transition.delta
        elseif hp ~= nil and real and previous and previous.real and previous.limit == maxHp then
            gained = math.max(0, hp - previous.value)
        end
        if gained ~= nil then
            local afterLoss = math.max(0, amount - reportedLoss)
            effective, overheal, method = math.min(afterLoss, gained), math.max(0, afterLoss - gained), "hp-estimate"
        end
    end
    if effective ~= nil then
        b.effective, b.overheal = b.effective + effective, b.overheal + overheal
        if method == "reported" then b.hpMeasured = b.hpMeasured + 1 else b.hpEstimated = b.hpEstimated + 1 end
        if effective > 0 then recordHealthPhase(kind, params, effective, method) end
    elseif amount > 0 then
        b.hpUnknown = b.hpUnknown + 1
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
    end
    if reported ~= nil then b.reportedOverheal = b.reportedOverheal + reported end
    recordHealingJournal(kind, params, amount, effective, overheal, effective ~= nil)
end

function AOUA.OnHit(combatant, mode, params, determination)
    if type(params) ~= "table" then return end
    ensureSession()
    local kind
    if enumMode then
        if mode == enumMode.Dps then kind = "damage"
        elseif mode == enumMode.Def then kind = "incoming"
        elseif mode == enumMode.Hps then kind = "healing"
        elseif mode == enumMode.IHps then kind = "receivedHeal" end
    end
    if not kind then return end
    -- Raw target-filtered API events collect personal incoming damage/healing.
    if kind == "incoming" or kind == "receivedHeal" then return end

    if not combatant or not combatant.ID or not avatar or not avatar.GetId then return end
    local okId, playerId = pcall(avatar.GetId)
    if not okId or combatant.ID ~= playerId then return end

    local amount = (kind == "healing") and N(params.heal or params.amount) or N(params.amount)
    if amount <= 0 then return end
    local b = AOUA.Session[kind]
    addEvent(b, amount, params)

    local rawDetermination = determination or params.determination
    if kind == "damage" or kind == "healing" then
        addDetermination(rawDetermination, kind)
        local dv = tonumber(rawDetermination)
        if dv ~= nil and dv > 0 then
            b.determinationSum = b.determinationSum + dv
            b.determinationSamples = b.determinationSamples + 1
        end
    end
    if kind == "damage" then
        recordHealthPhase(kind, params, amount, "estimated")
        recordDamageJournal("outgoing", params, amount)
    elseif kind == "healing" then
        recordHealing("healing", params, amount)
    end
end


function AOUA.OnIncomingDamage(params)
    ensureSession()
    local diag = AOUA.Session.rawDiagnostics
    diag.incomingCallbacks = diag.incomingCallbacks + 1
    if type(params) ~= "table" then return end
    if isLocalObject(params.target) then
        diag.incomingMatched = diag.incomingMatched + 1
    else
        diag.incomingOther = diag.incomingOther + 1
        return
    end
    diag.incomingAccepted = diag.incomingAccepted + 1
    local amount = math.max(0, N(params.amount))
    addEvent(AOUA.Session.incoming, amount, params)
    local fightStats = AOUA.Session.journal.incomingStats
    fightStats.events = fightStats.events + 1
    fightStats.amount = fightStats.amount + amount
    local d = AOUA.Session.defense
    d.events, d.amount = d.events + 1, d.amount + amount
    d.shieldBlock = d.shieldBlock + N(params.shieldBlock)
    d.parry = d.parry + N(params.parry)
    d.resist = d.resist + N(params.resist)
    d.barrier = d.barrier + N(params.barrier)
    d.absorb = d.absorb + N(params.absorb)
    d.runesAbsorb = d.runesAbsorb + N(params.runesAbsorb)
    d.toMount = d.toMount + N(params.toMount)
    d.multipliersAbsorb = d.multipliersAbsorb + N(params.multipliersAbsorb)
    if params.overallAbsorbedDamage ~= nil then
        d.overallAbsorbed = d.overallAbsorbed + N(params.overallAbsorbedDamage)
        d.totalAbsorbedSamples = d.totalAbsorbedSamples + 1
    end
    if params.overallPreventedDamage ~= nil then
        d.overallPrevented = d.overallPrevented + N(params.overallPreventedDamage)
        d.totalPreventedSamples = d.totalPreventedSamples + 1
    end
    if amount <= 0 then
        d.zeroAmountEvents = d.zeroAmountEvents + 1
        fightStats.zeroAmountEvents = fightStats.zeroAmountEvents + 1
        if params.isDodge then
            d.dodgedEvents = d.dodgedEvents + 1
            fightStats.dodgedEvents = fightStats.dodgedEvents + 1
        elseif params.isMiss then
            d.missedEvents = d.missedEvents + 1
            fightStats.missedEvents = fightStats.missedEvents + 1
        else
            local prevented = math.max(0, N(params.overallAbsorbedDamage))
                + math.max(0, N(params.overallPreventedDamage))
                + math.max(0, N(params.shieldBlock))
                + math.max(0, N(params.parry))
                + math.max(0, N(params.resist))
                + math.max(0, N(params.barrier))
                + math.max(0, N(params.absorb))
                + math.max(0, N(params.toMount))
                + math.max(0, N(params.runesAbsorb))
            if prevented > 0 then
                d.fullyPreventedEvents = d.fullyPreventedEvents + 1
                fightStats.fullyPreventedEvents = fightStats.fullyPreventedEvents + 1
            elseif tonumber(params.multipliersAbsorb) == nil or N(params.multipliersAbsorb) == 0 then
                -- API documentation: no damage and no avoidance/mitigation modifier => full absorb.
                d.fullyAbsorbedEvents = d.fullyAbsorbedEvents + 1
                fightStats.fullyAbsorbedEvents = fightStats.fullyAbsorbedEvents + 1
            else
                d.otherZeroAmountEvents = d.otherZeroAmountEvents + 1
                fightStats.otherZeroAmountEvents = fightStats.otherZeroAmountEvents + 1
            end
        end
    end
    recordDamageJournal("incoming", params, amount)
end

function AOUA.OnReceivedHeal(params)
    ensureSession()
    local diag = AOUA.Session.rawDiagnostics
    diag.healCallbacks = diag.healCallbacks + 1
    if type(params) ~= "table" then return end
    if isLocalObject(params.unitId) then
        diag.healMatched = diag.healMatched + 1
    else
        diag.healOther = diag.healOther + 1
        return
    end
    diag.healAccepted = diag.healAccepted + 1
    recordHealing("receivedHeal", params, math.max(0, N(params.heal or params.amount)))
end

local function fmt(v)
    return string.format("%.0f", N(v))
end
local function pct(part, total)
    if not total or total <= 0 then return "n/a" end
    return string.format("%.1f%%", part * 100 / total)
end
local function basicReport(label, b)
    return label .. ": events=" .. fmt(b.events) ..
        ", amount=" .. fmt(b.amount) ..
        ", crit=" .. pct(b.crits, b.events) ..
        ", avg=" .. (b.events > 0 and fmt(b.amount / b.events) or "n/a")
end

local function phaseReport(kind)
    local out = { "Target HP phases (" .. kind .. "):" }
    local total, measured, estimated = 0, 0, 0
    for _, p in ipairs(PHASES) do
        local b = AOUA.Session.phases[kind .. "_" .. p.key]
        total = total + b.amount
        measured = measured + b.hpMeasured
        estimated = estimated + b.hpEstimated
        out[#out + 1] = p.label .. ": events=" .. fmt(b.events) ..
            ", amount=" .. fmt(b.amount) .. ", crit=" .. pct(b.crits, b.events) ..
            ", HP measured/estimated=" .. fmt(b.hpMeasured) .. "/" .. fmt(b.hpEstimated)
    end
    out[#out + 1] = "Phase total=" .. fmt(total) ..
        ", HP samples measured/estimated=" .. fmt(measured) .. "/" .. fmt(estimated)
    out[#out + 1] = "Health-change API events=" .. fmt(AOUA.Session.targetHealth.changedEvents or 0) ..
        ", phase samples unknown=" .. fmt(AOUA.Session.targetHealth.unknown)
    return table.concat(out, "\n")
end

local function healingReport()
    local a, b = AOUA.Session.healing, AOUA.Session.receivedHeal
    local function one(label, x)
        return label .. ": nominal=" .. fmt(x.amount) ..
            ", effective=" .. fmt(x.effective) ..
            ", overheal=" .. fmt(x.overheal) ..
            ", wound/debuff loss=" .. fmt(x.healResisted + x.runeResisted + x.healAbsorbed) ..
            ", confidence reported/estimated/unknown=" ..
            fmt(x.hpMeasured) .. "/" .. fmt(x.hpEstimated) .. "/" .. fmt(x.hpUnknown)
    end
    return "Healing:\n" .. one("outgoing", a) .. "\n" .. one("received", b)
end

local function defenseReport()
    local d = AOUA.Session.defense
    return "Defense: events=" .. fmt(d.events) .. ", incoming=" .. fmt(d.amount) ..
        "\nComponents (not summed; may overlap): block=" .. fmt(d.shieldBlock) ..
        ", parry=" .. fmt(d.parry) .. ", resist=" .. fmt(d.resist) ..
        ", barrier=" .. fmt(d.barrier) .. ", absorb=" .. fmt(d.absorb) ..
        ", runeAbsorb=" .. fmt(d.runesAbsorb) .. ", mount=" .. fmt(d.toMount) ..
        ", multiplierAbsorb=" .. fmt(d.multipliersAbsorb) ..
        "\nAPI totals: absorbed=" .. fmt(d.overallAbsorbed) ..
        " (" .. fmt(d.totalAbsorbedSamples) .. " samples), prevented=" ..
        fmt(d.overallPrevented) .. " (" .. fmt(d.totalPreventedSamples) .. " samples)" ..
        "\nZero-amount events=" .. fmt(d.zeroAmountEvents) ..
        ", full absorb inferred=" .. fmt(d.fullyAbsorbedEvents) ..
        ", mitigated=" .. fmt(d.fullyPreventedEvents) ..
        ", dodge/miss/other=" .. fmt(d.dodgedEvents) .. "/" .. fmt(d.missedEvents) ..
        "/" .. fmt(d.otherZeroAmountEvents) ..
        "\nShield pool change (not necessarily damage absorbed): loss=" .. fmt(d.shieldPoolLoss) ..
        ", gain=" .. fmt(d.shieldPoolGain) .. ", samples=" .. fmt(d.shieldPoolSamples)
end


local function topJournalRows(title, map, field, formatter, limit)
    local rows = {}
    for key, value in pairs(map or {}) do
        if type(value) == "table" then rows[#rows + 1] = { key = key, row = value } end
    end
    table.sort(rows, function(x, y) return N(x.row[field]) > N(y.row[field]) end)
    local out = { title .. ":" }
    if #rows == 0 then out[#out + 1] = "  no samples"
    else
        for i = 1, math.min(limit or 4, #rows) do
            out[#out + 1] = "  " .. formatter(rows[i].key, rows[i].row)
        end
    end
    return table.concat(out, "\n")
end

local function journalReport()
    local j = AOUA.Session.journal
    local d = j.incomingStats
    local rd = AOUA.Session.rawDiagnostics or {}
    local out = {
        "Combat API event journal (current/last combat, local player):",
        "Raw callbacks incoming=" .. fmt(rd.incomingCallbacks) ..
            " matched=" .. fmt(rd.incomingMatched) .. " other=" .. fmt(rd.incomingOther) ..
            " accepted=" .. fmt(rd.incomingAccepted) ..
            "; heals=" .. fmt(rd.healCallbacks) .. "/" .. fmt(rd.healMatched) ..
            "/" .. fmt(rd.healAccepted),
        "Incoming: events=" .. fmt(d.events) .. ", damage=" .. fmt(d.amount) ..
            ", zero amount=" .. fmt(d.zeroAmountEvents) ..
            ", full absorb (inferred)=" .. fmt(d.fullyAbsorbedEvents) ..
            ", mitigated=" .. fmt(d.fullyPreventedEvents) ..
            ", dodge/miss/other=" .. fmt(d.dodgedEvents) .. "/" .. fmt(d.missedEvents) ..
            "/" .. fmt(d.otherZeroAmountEvents)
    }
    out[#out + 1] = topJournalRows("Incoming damage by school", j.incomingByElement, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " damage=" .. fmt(x.amount)
    end, 5)
    out[#out + 1] = topJournalRows("Incoming damage by source type", j.incomingByType, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " damage=" .. fmt(x.amount) ..
            " API absorbed/prevented=" .. fmt(x.absorbed) .. "/" .. fmt(x.prevented) ..
            " runes=" .. fmt(x.runesAbsorb)
    end, 5)
    out[#out + 1] = topJournalRows("Incoming abilities", j.incomingByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " amount=" .. fmt(x.amount) ..
            " block/parry/resist=" .. fmt(x.block) .. "/" .. fmt(x.parry) .. "/" .. fmt(x.resist) ..
            " buff/barrier/mount=" .. fmt(x.buffAbsorb) .. "/" .. fmt(x.barrier) .. "/" .. fmt(x.mount) ..
            " rune/multiplier=" .. fmt(x.runesAbsorb) .. "/" .. fmt(x.multiplierAbsorb)
    end, 5)
    out[#out + 1] = topJournalRows("Incoming attackers", j.incomingByAttacker, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " damage=" .. fmt(x.amount)
    end, 4)
    out[#out + 1] = topJournalRows("Effects on you during incoming hits (correlation only)", j.incomingTargetEffects, "amount", function(k, x)
        return k .. " hits=" .. fmt(x.events) .. " amount-during-effect=" .. fmt(x.amount) ..
            " helpful/harmful=" .. fmt(x.helpful) .. "/" .. fmt(x.harmful)
    end, 5)
    out[#out + 1] = topJournalRows("Attacker effects during incoming hits (correlation only)", j.incomingSourceEffects, "amount", function(k, x)
        return k .. " hits=" .. fmt(x.events) .. " damage-during-effect=" .. fmt(x.amount)
    end, 4)
    out[#out + 1] = topJournalRows("Outgoing damage by school", j.outgoingByElement, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " damage=" .. fmt(x.amount)
    end, 5)
    out[#out + 1] = topJournalRows("Outgoing abilities", j.outgoingByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " damage=" .. fmt(x.amount) ..
            " crits=" .. fmt(x.crits) .. " target absorbed/prevented=" .. fmt(x.absorbed) .. "/" .. fmt(x.prevented)
    end, 4)
    out[#out + 1] = topJournalRows("Received healing by ability", j.receivedHealByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " nominal/effective/overheal=" ..
            fmt(x.amount) .. "/" .. fmt(x.effective) .. "/" .. fmt(x.overheal) ..
            " wound/rune/absorbed=" .. fmt(x.wound) .. "/" .. fmt(x.runeWound) .. "/" .. fmt(x.absorbed) ..
            " crits=" .. fmt(x.crits) .. " lifeSteal=" .. fmt(x.lifeSteal) ..
            " lethality avg=" .. (N(x.lethalitySamples) > 0 and string.format("%.1f", N(x.lethalitySum) / N(x.lethalitySamples)) or "n/a") ..
            " (n=" .. fmt(x.lethalitySamples) .. ") unknown=" .. fmt(x.unknown)
    end, 5)
    out[#out + 1] = topJournalRows("Outgoing healing by ability", j.outgoingHealByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " nominal/effective/overheal=" ..
            fmt(x.amount) .. "/" .. fmt(x.effective) .. "/" .. fmt(x.overheal) ..
            " wounds/runes/absorbed=" .. fmt(x.wound) .. "/" .. fmt(x.runeWound) .. "/" .. fmt(x.absorbed)
    end, 4)
    out[#out + 1] = "Effect tags are hit-time snapshots; exact absorbed damage is not attributed to individual tags."
    return table.concat(out, "\n")
end

local function determinationReport()
    local function one(label, d)
        if not d or d.samples == 0 then
            return label .. ": no numeric pool samples"
        end
        return label .. ": n=" .. fmt(d.samples) ..
            ", avg=" .. string.format("%.1f", d.sum / d.samples) ..
            ", min/max=" .. fmt(d.min) .. "/" .. fmt(d.max) ..
            ", >=50/67/90=" .. pct(d.above50, d.samples) .. "/" ..
            pct(d.above67, d.samples) .. "/" .. pct(d.above90, d.samples)
    end
    local byMode = AOUA.Session.determinationByMode or {}
    return "Resolve pool:\n" .. one("All activities", AOUA.Session.determination) ..
        "\n" .. one("DD outgoing damage", byMode.damage) ..
        "\n" .. one("HEAL outgoing healing", byMode.healing)
end

local function innateStatsReport()
    if not avatar or type(avatar.GetInnateStats) ~= "function" then
        return "Innate stats: API unavailable."
    end
    local ok, list = pcall(avatar.GetInnateStats)
    if not ok or type(list) ~= "table" then
        return "Innate stats: read failed."
    end
    local out = { "Innate stats (raw API values; no stat-name assumptions):" }
    for _, e in pairs(list) do
        if type(e) == "table" and type(e.sysName) == "string" then
            local line = e.sysName ..
                " eff=" .. fmt(e.effective) ..
                " base=" .. fmt(e.base) ..
                " talents=" .. fmt(e.talents) ..
                " equip=" .. fmt(e.equipment) ..
                " enchants=" .. fmt(e.enchants) ..
                " buffs=" .. fmt(e.buffs) ..
                " fairy=" .. fmt(e.fairyBonus)
            local secondary = e.secondary and e.secondary.current
            if type(secondary) == "table" then
                local values = {}
                for _, k in ipairs({ "N1", "N2", "N3", "N4" }) do
                    if secondary[k] ~= nil then values[#values + 1] = k .. "=" .. fmt(secondary[k]) end
                end
                if #values > 0 then line = line .. " secondary{" .. table.concat(values, ",") .. "}" end
            end
            out[#out + 1] = line
        end
    end
    if #out == 1 then out[#out + 1] = "No innate-stat entries returned." end
    return table.concat(out, "\n")
end

local function getCommand(input)
    local s = ""
    if type(input) == "string" then s = input
    elseif type(input) == "table" then
        local parts = {}
        for i, v in ipairs(input) do
            if type(v) == "string" or type(v) == "number" then parts[#parts + 1] = tostring(v) end
        end
        s = table.concat(parts, " ")
    else s = tostring(input or "") end
    s = string.lower(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "^/", "")
    s = string.gsub(s, "^aou%s*", "")
    s = string.gsub(s, "^dpscope%s*", "")
    return s
end

function AOUA.OnSlash(input)
    local command = getCommand(input)
    local cmd, rest = string.match(command, "^(%S+)%s*(.-)$")
    cmd = cmd or ""

    if cmd == "diff" then
        return true, "AOUA build 28\n" ..
            basicReport("damage", AOUA.Session.damage) .. "\n" ..
            basicReport("incoming", AOUA.Session.incoming) .. "\n" ..
            basicReport("healing", AOUA.Session.healing) .. "\n" ..
            basicReport("receivedHeal", AOUA.Session.receivedHeal) .. "\n" ..
            determinationReport()
    end
    if cmd == "phase" then
        return true, phaseReport("damage")
    end
    if cmd == "heal" then
        return true, healingReport()
    end
    if cmd == "defstat" then
        return true, defenseReport()
    end
    if cmd == "events" or cmd == "journal" then
        return true, journalReport()
    end
    if cmd == "stats" then
        return true, determinationReport() ..
            "\nMastery/Ruthlessness: no isolated causal coefficient is inferred from these event fields." ..
            "\n" .. innateStatsReport()
    end
    if cmd == "log" then
        local out = { "AOUA recent events:" }
        local names = { "damage", "incoming", "healing", "receivedHeal" }
        for _, name in ipairs(names) do
            local b = AOUA.Session[name]
            local first = math.max(1, #b.last - 4)
            for i = first, #b.last do
                local e = b.last[i]
                out[#out + 1] = name .. " amount=" .. fmt(e.amount) ..
                    " crit=" .. fmt(e.crit)
            end
        end
        if #out == 1 then out[#out + 1] = "No events collected yet." end
        return true, table.concat(out, "\n")
    end
    if cmd == "prof" then
        local profile = string.match(rest, "^(%S+)")
        if not profile or profile == "list" then
            return true, "Profiles: pve, raid, pvp, heal, tank. Current: " .. AOUA.Profile
        end
        if profile == "pve" or profile == "raid" or profile == "pvp" or profile == "heal" or profile == "tank" then
            AOUA.Profile = profile
            return true, "AOUA profile: " .. profile
        end
        return true, "Unknown profile. Use /aou prof list"
    end
    -- "reset" belongs to the legacy optimizer settings command.
    -- Never clear the analytics session from the shared slash dispatcher.
    return false
end
