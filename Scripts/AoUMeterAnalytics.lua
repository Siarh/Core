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

local EVENT_HISTORY_LIMIT = 1000
local EVENT_BUFFER_LIMIT = 2000

local function N(v)
    local x = tonumber(v)
    if x == nil then return 0 end
    return x
end

local function bucket()
    return {
        events = 0, amount = 0, crits = 0, glancing = 0,
        effective = 0, overheal = 0, reportedOverheal = 0,
        reportedOverload = 0, overhealUnknown = 0,
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
            healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0, damageFilters = 0, healFilters = 0, healthFilters = 0,
            outgoingHitCallbacks = 0, outgoingHitOwnerMatched = 0, outgoingHitAccepted = 0,
            outgoingHitOtherCombatant = 0, outgoingHitRejected = 0,
            lastOutgoingTarget = "", lastOutgoingAmount = 0
        },
        determination = freshDeterminationStats(),
        determinationByMode = {
            damage = freshDeterminationStats(),
            healing = freshDeterminationStats()
        },
        targetHealth = { samples = 0, estimated = 0, unknown = 0, changedEvents = 0 },
        eventSamples = {}, eventSamplesDropped = 0, eventSampleCount = 0, eventSampleNext = 1,
        elapsedSeconds = 0, fightId = 0, statSnapshot = nil,
        statSnapshotSecond = nil, statSnapshotAttemptSecond = nil,
        objectMetadata = {}, objectMetadataCount = 0,
        targetProfiles = {}, targetProfileCount = 0,
        willControl = {
            effects = {}, active = false, segmentStartMs = nil,
            totalSeconds = 0, maxSegmentSeconds = 0, segments = 0,
            lastEventMs = nil
        },
        started = false
    }
end

AOUA.Session = AOUA.Session or freshSession()
AOUA.PendingReceivedHeal = AOUA.PendingReceivedHeal or setmetatable({}, { __mode = "k" })
local function ensureSession()
    -- This migration/shape check walks the session journal. Run it once when
    -- the module loads, not for every combat callback.
    if AOUA.SessionReady then return end
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
        b.reportedOverload = b.reportedOverload or b.reportedOverheal or 0
        b.overhealUnknown = b.overhealUnknown or 0
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
        healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0, damageFilters = 0, healFilters = 0, healthFilters = 0,
        outgoingHitCallbacks = 0, outgoingHitOwnerMatched = 0, outgoingHitAccepted = 0,
        outgoingHitOtherCombatant = 0, outgoingHitRejected = 0,
        lastOutgoingTarget = "", lastOutgoingAmount = 0
    }
    local rd = AOUA.Session.rawDiagnostics
    for _, key in ipairs({
        "outgoingHitCallbacks", "outgoingHitOwnerMatched", "outgoingHitAccepted",
        "outgoingHitOtherCombatant", "outgoingHitRejected"
    }) do
        rd[key] = tonumber(rd[key]) or 0
    end
    rd.lastOutgoingTarget = rd.lastOutgoingTarget or ""
    rd.lastOutgoingAmount = tonumber(rd.lastOutgoingAmount) or 0
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
    AOUA.Session.eventSamples = AOUA.Session.eventSamples or {}
    AOUA.Session.eventSamplesDropped = AOUA.Session.eventSamplesDropped or 0
    AOUA.Session.objectMetadata = AOUA.Session.objectMetadata or {}
    AOUA.Session.objectMetadataCount = tonumber(AOUA.Session.objectMetadataCount) or 0
    AOUA.Session.targetProfiles = AOUA.Session.targetProfiles or {}
    AOUA.Session.targetProfileCount = tonumber(AOUA.Session.targetProfileCount) or 0
    AOUA.Session.willControl = AOUA.Session.willControl or {
        effects = {}, active = false, segmentStartMs = nil,
        totalSeconds = 0, maxSegmentSeconds = 0, segments = 0,
        lastEventMs = nil
    }
    AOUA.Session.willControl.effects = AOUA.Session.willControl.effects or {}
    AOUA.Session.willControl.totalSeconds = tonumber(AOUA.Session.willControl.totalSeconds) or 0
    AOUA.Session.willControl.maxSegmentSeconds = tonumber(AOUA.Session.willControl.maxSegmentSeconds) or 0
    AOUA.Session.willControl.segments = tonumber(AOUA.Session.willControl.segments) or 0
    AOUA.Session.eventSampleCount = math.max(0, math.min(EVENT_BUFFER_LIMIT,
        math.floor(tonumber(AOUA.Session.eventSampleCount) or #AOUA.Session.eventSamples)))
    AOUA.Session.eventSampleNext = math.floor(tonumber(AOUA.Session.eventSampleNext) or
        ((AOUA.Session.eventSampleCount >= EVENT_BUFFER_LIMIT) and 1 or (AOUA.Session.eventSampleCount + 1)))
    if AOUA.Session.eventSampleNext < 1 or AOUA.Session.eventSampleNext > EVENT_BUFFER_LIMIT then
        AOUA.Session.eventSampleNext = 1
    end
    AOUA.Session.elapsedSeconds = AOUA.Session.elapsedSeconds or 0
    AOUA.SessionReady = true
end
AOUA.SessionReady = false
ensureSession()

-- Detailed API journal is fight-scoped; keep the last one until the next fight.
function AOUA.OnFightStart()
    ensureSession()
    local previous = AOUA.Session.rawDiagnostics or {}
    AOUA.Session.journal = freshJournal()
    AOUA.Session.eventSamples = {}
    AOUA.Session.eventSamplesDropped = 0
    AOUA.Session.objectMetadata = {}
    AOUA.Session.objectMetadataCount = 0
    AOUA.Session.targetProfiles = {}
    AOUA.Session.targetProfileCount = 0
    AOUA.Session.willControl = {
        effects = {}, active = false, segmentStartMs = nil,
        totalSeconds = 0, maxSegmentSeconds = 0, segments = 0,
        lastEventMs = nil
    }
    -- HP transitions from an earlier fight must never leak into the new fight.
    AOUA.HpCache = {}
    AOUA.HealthTransitions = {}
    AOUA.Session.eventSampleCount = 0
    AOUA.Session.eventSampleNext = 1
    AOUA.Session.elapsedSeconds = 0
    AOUA.Session.statSnapshot = nil
    AOUA.Session.statSnapshotSecond = nil
    AOUA.Session.statSnapshotAttemptSecond = nil
    AOUA.Session.started = true
    local sequence = 0
    pcall(function()
        local section = userMods.GetGlobalConfigSection(common.GetAddonName())
        sequence = tonumber(section and section.aou_evt_fight_id) or 0
    end)
    AOUA.Session.fightId = sequence + 1
    AOUA.PendingReceivedHeal = setmetatable({}, { __mode = "k" })
    AOUA.Session.rawDiagnostics = {
        incomingCallbacks = 0, incomingMatched = 0, incomingOther = 0, incomingAccepted = 0,
        healCallbacks = 0, healMatched = 0, healOther = 0, healAccepted = 0,
        -- These are per-target filter counts, not handler totals.
        damageFilters = tonumber(previous.damageFilters) or 0,
        healFilters = tonumber(previous.healFilters) or 0,
        healthFilters = tonumber(previous.healthFilters) or 0,
        outgoingHitCallbacks = 0, outgoingHitOwnerMatched = 0, outgoingHitAccepted = 0,
        outgoingHitOtherCombatant = 0, outgoingHitRejected = 0,
        lastOutgoingTarget = "", lastOutgoingAmount = 0
    }
    if type(AOUA.SeedWillControlBuffs) == "function" then
        pcall(AOUA.SeedWillControlBuffs)
    end
end

function AOUA.OnFightSecond()
    ensureSession()
    if AOUA.Session.started then
        AOUA.Session.elapsedSeconds = AOUA.Session.elapsedSeconds + 1
        AOUA.UpdateWillControlSeconds()
    end
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

-- Consume the matching pre-hit HP transition once. A valid transition means
-- the health-change callback already did the expensive game API read.
local function takeHealthTransition(id, expectedDirection, amount)
    local transition = id and AOUA.HealthTransitions[id] or nil
    if not transition then return nil end
    local matches = transition.direction == expectedDirection and transition.beforeFrac ~= nil
    if matches and transition.delta ~= nil then
        local difference = math.abs(math.abs(transition.delta) - amount)
        matches = difference <= math.max(2, amount * 0.05)
    end
    AOUA.HealthTransitions[id] = nil
    return matches and transition or nil
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
    local expectedDirection = (kind == "damage") and -1 or 1
    local transition = takeHealthTransition(id, expectedDirection, amount)
    local useTransition = transition ~= nil
    -- A matching health-change event already contains the pre-hit fraction.
    -- Avoid another expensive game API query for the same combat event.
    local value, limit, real
    if not useTransition then value, limit, real = safeHealth(id) end
    if value == nil and not useTransition then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return nil, "unknown", nil
    end
    if (kind == "healing" or kind == "receivedHeal") and not real and not useTransition then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return nil, "unknown", nil
    end

    if value ~= nil then
        AOUA.HpCache[id] = {
            value = value, limit = limit, real = real,
            second = tonumber(AOUA.Session.elapsedSeconds) or 0
        }
    end
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
    local sampleQuality
    if useTransition then sampleQuality = transition.exact and "measured_pre" or "estimated_pre"
    elseif real then sampleQuality = "estimated_pre" -- reconstructed from post-event HP plus the reported event amount
    elseif previous and previous.value ~= nil then sampleQuality = "estimated_pre"
    else sampleQuality = "post_only" end
    return frac, sampleQuality, (real and limit or (useTransition and transition.limit or nil))
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
            limit = limit,
            exact = (delta ~= nil and real == true)
        }
        AOUA.Session.targetHealth.changedEvents = AOUA.Session.targetHealth.changedEvents + 1
    end
    if value ~= nil then
        AOUA.HpCache[id] = {
            value = value, limit = limit, real = real,
            second = tonumber(AOUA.Session.elapsedSeconds) or 0
        }
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

local resourceKeyCache = setmetatable({}, { __mode = "k" })

local function resourceKey(value)
    if value == nil then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" then return tostring(value) end
    if valueType ~= "table" and valueType ~= "userdata" then return nil end

    local cached = resourceKeyCache[value]
    if cached ~= nil then return cached or nil end

    -- ResourceId:GetInstanceId may return an opaque UniqueId userdata.
    -- Cache its stable label: these metadata calls can otherwise repeat on every hit.
    local result
    local okPath, path = pcall(function() return value:GetPath() end)
    result = okPath and eventText(path) or nil

    if not result then
        local okInfo, info = pcall(function() return value:GetInfo() end)
        if okInfo and type(info) == "table" then
            result = eventText(info.sysName) or eventText(info.name) or eventText(info.shortName)
        end
    end

    if not result then
        local okId, id = pcall(function() return value:GetInstanceId() end)
        if okId and (type(id) == "string" or type(id) == "number") then result = tostring(id) end
    end
    resourceKeyCache[value] = result or false
    return result
end

local function abilityLabel(params, fallbackName)
    local name = eventText(params.ability)
    if name and string.match(name, "^userdata:") then name = nil end
    if not name or name == "" then name = eventText(fallbackName) end
    local id = resourceKey(params.spellId or params.abilityId or params.buffId or params.mapModifierId)
    if name and id then return name .. " [" .. id .. "]" end
    return name or (id and ("id:" .. id)) or "unknown"
end

local isLocalObject
local EVENT_COLUMNS = "fight_id|profile|second|kind|observed_amount|target_hp_before|hp_quality|target_max_hp|actor_id|target_id|critical|element|damage_source|resist|absorb|runes_absorb|block|parry|barrier|mount|multiplier_absorb|overall_absorbed|overall_prevented|resolve_pool|recipient|ability|M|R|U|L|S|W|B|C|HPmax|stat_sample_second|stat_sample_age|actor_name|actor_level|actor_quality|actor_quality_name|actor_kind|actor_is_mob|target_name|target_level|target_quality|target_quality_name|target_kind|target_is_mob|target_hp_current|target_hp_current_percent|target_hp_limit|target_hp_snapshot_quality|target_hp_snapshot_age"

local function sampleNumber(value)
    local n = tonumber(value)
    if n == nil then return "" end
    return string.format("%.4f", n)
end

-- Return only an instance identifier, never a resource template path/name.
-- If the callback does not expose a stable primitive ID, strict experiment
-- matching receives an empty field and excludes the event.
local function eventObjectId(value)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" then
        return tostring(value)
    end
    if valueType ~= "table" and valueType ~= "userdata" then return nil end
    for _, methodName in ipairs({ "GetId", "GetInstanceId" }) do
        local okFn, fn = pcall(function() return value[methodName] end)
        if okFn and type(fn) == "function" then
            local okId, id = pcall(fn, value)
            if okId and (type(id) == "string" or type(id) == "number") then
                return tostring(id)
            end
        end
    end
    return nil
end


local function sameEventObject(left, right)
    if left == right then return true end
    local leftKey = eventObjectId(left)
    local rightKey = eventObjectId(right)
    return leftKey ~= nil and rightKey ~= nil and leftKey == rightKey
end

local TARGET_METADATA_CACHE_LIMIT = 512
local QUALITY_LABELS = {
    "COMMON", "ELITE", "FLAVOR_ELITE", "MINI_BOSS",
    "BOSS", "RAID_BOSS", "RAID_ELITE", "CRITTER"
}

local function qualityLabel(value)
    local numeric = tonumber(value)
    if numeric == nil then return "" end
    for i = 1, #QUALITY_LABELS do
        local name = QUALITY_LABELS[i]
        local constant = (_G and _G["UNIT_QUALITY_" .. name]) or nil
        if constant ~= nil and tonumber(constant) == numeric then return name end
    end
    return "ENUM:" .. tostring(numeric)
end

-- Cache descriptive data by ObjectId for this fight. ObjectId identifies an
-- instance; cross-fight matching is done offline from name + level + quality
-- + known unit kind. Missing/unknown types must never be merged by archetype.
local function readObjectMetadata(id)
    local key = eventObjectId(id)
    if not key then return {} end
    local session = AOUA.Session
    session.objectMetadata = session.objectMetadata or {}
    local cached = session.objectMetadata[key]
    if cached then return cached end
    if (tonumber(session.objectMetadataCount) or 0) >= TARGET_METADATA_CACHE_LIMIT then
        return { kind = "unknown" }
    end

    local meta = { kind = "unknown" }
    local exists = true
    if object and type(object.IsExist) == "function" then
        local ok, value = pcall(object.IsExist, id)
        exists = ok and value == true
    end
    if exists and object and type(object.IsUnit) == "function" then
        local okUnit, isUnit = pcall(object.IsUnit, id)
        if okUnit and isUnit == true then
            local isMob, isPlayer
            if type(object.IsMob) == "function" then
                local ok, value = pcall(object.IsMob, id)
                if ok then isMob = value == true end
            end
            if type(object.IsPlayer) == "function" then
                local ok, value = pcall(object.IsPlayer, id)
                if ok then isPlayer = value == true end
            end
            if isMob == true then meta.kind = "mob"
            elseif isPlayer == true then meta.kind = "player"
            elseif isMob == false and isPlayer == false then meta.kind = "npc"
            end

            if type(object.GetName) == "function" then
                local ok, value = pcall(object.GetName, id)
                if ok then meta.name = eventText(value) or "" end
            end
            if unit and type(unit.GetLevel) == "function" then
                local ok, value = pcall(unit.GetLevel, id)
                if ok and tonumber(value) then meta.level = tonumber(value) end
            end
            if unit and type(unit.GetQuality) == "function" then
                local ok, value = pcall(unit.GetQuality, id)
                if ok and tonumber(value) then
                    meta.quality = tonumber(value)
                    meta.qualityName = qualityLabel(value)
                end
            end
            if meta.kind == "mob" then meta.isMob = true
            elseif meta.kind == "player" or meta.kind == "npc" then meta.isMob = false end
        end
    end

    session.objectMetadata[key] = meta
    session.objectMetadataCount = (tonumber(session.objectMetadataCount) or 0) + 1
    return meta
end

local function metadataCsv(meta)
    meta = meta or {}
    return eventText(meta.name) or "",
        sampleNumber(meta.level), sampleNumber(meta.quality),
        eventText(meta.qualityName) or "", meta.kind or "unknown",
        (meta.isMob == nil) and "" or (meta.isMob and "1" or "0")
end

-- Aggregate live opponent data for the in-game details panel. Profiles are
-- keyed by the target ObjectId for this fight; unknown object types are never
-- merged merely because their metadata is unavailable.
local function updateTargetProfile(targetKey, targetMeta, amount, hpBefore, hpQuality,
    hpCurrent, hpLimit, hpPercent, hpAge, element, params)
    if not targetKey or targetKey == "" then return end
    local session = AOUA.Session
    session.targetProfiles = session.targetProfiles or {}
    local profile = session.targetProfiles[targetKey]
    if not profile then
        session.targetProfileCount = (tonumber(session.targetProfileCount) or 0) + 1
        profile = {
            ordinal = session.targetProfileCount,
            name = eventText(targetMeta and targetMeta.name) or "",
            level = targetMeta and tonumber(targetMeta.level) or nil,
            quality = targetMeta and tonumber(targetMeta.quality) or nil,
            qualityName = targetMeta and eventText(targetMeta.qualityName) or "",
            kind = targetMeta and targetMeta.kind or "unknown",
            events = 0, damage = 0,
            resistTotal = 0, resistSamples = 0, resistByElement = {}
        }
        session.targetProfiles[targetKey] = profile
    end

    profile.events = profile.events + 1
    profile.damage = profile.damage + N(amount)
    profile.lastSecond = tonumber(session.elapsedSeconds) or 0

    if hpCurrent ~= nil and hpLimit ~= nil and hpLimit > 0 then
        profile.hpCurrent = hpCurrent
        profile.hpLimit = hpLimit
        profile.hpPercent = hpPercent
        profile.hpSecond = math.max(0, profile.lastSecond - (tonumber(hpAge) or 0))
    end
    if hpBefore ~= nil then
        profile.hpBeforePercent = hpBefore * 100
        profile.hpBeforeQuality = hpQuality or "unknown"
        profile.hpBeforeSecond = profile.lastSecond
    end

    local resist = tonumber(params and params.resist)
    if resist and resist > 0 then
        local school = (element and element ~= "") and element or "UNKNOWN"
        local schoolRow = profile.resistByElement[school]
        if not schoolRow then
            schoolRow = { amount = 0, samples = 0 }
            profile.resistByElement[school] = schoolRow
        end
        schoolRow.amount = schoolRow.amount + resist
        schoolRow.samples = schoolRow.samples + 1
        profile.resistTotal = profile.resistTotal + resist
        profile.resistSamples = profile.resistSamples + 1
    end
end

-- Public, read-only view consumed by the GUI. HP snapshots remain explicitly
-- measured; pre-hit HP is exposed separately and must be labelled as an estimate
-- or as a pre-hit sample rather than as current HP.
function AOUA.GetTargetDisplayRows(limit)
    ensureSession()
    local rows = {}
    local now = tonumber(AOUA.Session.elapsedSeconds) or 0
    for _, profile in pairs(AOUA.Session.targetProfiles or {}) do
        local row = {
            ordinal = profile.ordinal,
            name = profile.name,
            level = profile.level,
            quality = profile.quality,
            qualityName = profile.qualityName,
            kind = profile.kind,
            events = profile.events,
            damage = profile.damage,
            resistTotal = profile.resistTotal or 0,
            resistSamples = profile.resistSamples or 0,
            resistSchools = {}
        }
        if profile.hpCurrent ~= nil and profile.hpLimit ~= nil and profile.hpLimit > 0 then
            row.hpAge = math.max(0, now - (tonumber(profile.hpSecond) or now))
            if row.hpAge <= 30 then
                row.hpCurrent = profile.hpCurrent
                row.hpLimit = profile.hpLimit
                row.hpPercent = profile.hpPercent
                row.hpQuality = "measured"
            end
        end
        if row.hpCurrent == nil and profile.hpBeforePercent ~= nil then
            row.hpBeforePercent = profile.hpBeforePercent
            row.hpBeforeAge = math.max(0, now - (tonumber(profile.hpBeforeSecond) or now))
            row.hpBeforeQuality = profile.hpBeforeQuality or "unknown"
        end
        for school, stat in pairs(profile.resistByElement or {}) do
            row.resistSchools[#row.resistSchools + 1] = {
                element = school, amount = stat.amount, samples = stat.samples
            }
        end
        table.sort(row.resistSchools, function(a, b) return a.amount > b.amount end)
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.damage or 0) == (b.damage or 0) then
            return (a.events or 0) > (b.events or 0)
        end
        return (a.damage or 0) > (b.damage or 0)
    end)
    local total = #rows
    local maximum = math.max(0, math.floor(tonumber(limit) or total))
    while #rows > maximum do rows[#rows] = nil end
    return rows, total
end

-- Refresh innate stats at most once per elapsed fight second interval.
-- Re-reading the API for every hit would add avoidable work to the combat hot path.
local STAT_SNAPSHOT_INTERVAL = 3
local SNAPSHOT_STAT_KEYS = { "M", "R", "U", "L", "S", "W", "B", "C" }

-- Willpower is a PvP mechanic: only full seconds actually spent under a control
-- effect contribute to its hidden 0..100% resistance bar. The client exposes
-- control buffs and their remaining duration, so keep a union of those intervals
-- instead of sampling a visual state once per second.
local WILL_CONTROL_TOKENS = {
    "stun", "fear", "silence", "blind", "disable", "immobil", "freeze",
    "sleep", "charm", "hypnosis", "astral", "knockback", "disarm", "slow",
    "snare", "оглуш", "страх", "немот", "ослеп", "обездвиж", "замороз",
    "усып", "очар", "гипноз", "астрал", "отбрасыв", "обезоруж", "замедл"
}
local WILL_GROUP_TOKENS = {
    "slow", "stun", "fear", "silence", "blind", "disable",
    "enum_diminishinggroup", "diminishinggroup",
    "замедл", "оглуш", "страх", "немот", "ослеп", "обездвиж"
}

local function willNowMs()
    if common and type(common.GetAbsTimeMs) == "function" then
        local ok, value = pcall(common.GetAbsTimeMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return (tonumber(AOUA.Session.elapsedSeconds) or 0) * 1000
end

local function lowerText(value)
    local s = eventText(value)
    return s and string.lower(s) or ""
end

local function hasWillToken(value, tokens)
    local s = lowerText(value)
    if s == "" then return false end
    for i = 1, #tokens do
        if string.find(s, tokens[i], 1, true) then return true end
    end
    return false
end

local function isWillControlBuff(info)
    if type(info) ~= "table" then return false, "unknown" end

    -- Prefer the server/client diminishing-group metadata when it is exposed
    -- by the buff resource. This is the strongest signal available to addons.
    if type(info.groups) == "table" then
        for groupName, enabled in pairs(info.groups) do
            if enabled and hasWillToken(groupName, WILL_GROUP_TOKENS) then
                return true, "diminishing_group"
            end
        end
    end

    -- Some builds do not expose the diminishing group in buff metadata.
    -- Fall back to the system name / localized name. This is deliberately
    -- conservative and is reported as heuristic in the exported summary.
    if hasWillToken(info.sysName, WILL_CONTROL_TOKENS) or hasWillToken(info.name, WILL_CONTROL_TOKENS) then
        return true, "name_heuristic"
    end
    return false, "unknown"
end

local function willRefreshActive(now)
    local w = AOUA.Session.willControl
    local active = false
    local latestExpiry = nil
    for buffId, effect in pairs(w.effects or {}) do
        local expiresAt = effect and tonumber(effect.expiresAtMs) or nil
        if expiresAt and expiresAt > now then
            active = true
            if latestExpiry == nil or expiresAt > latestExpiry then
                latestExpiry = expiresAt
            end
        else
            if expiresAt and (latestExpiry == nil or expiresAt > latestExpiry) then
                latestExpiry = expiresAt
            end
            w.effects[buffId] = nil
        end
    end
    if active and not w.active then
        w.active = true
        w.segmentStartMs = now
    elseif not active and w.active then
        local finish = latestExpiry or now
        if finish > now then finish = now end
        local start = tonumber(w.segmentStartMs) or finish
        local seconds = math.max(0, math.floor((finish - start) / 1000))
        w.totalSeconds = w.totalSeconds + seconds
        if seconds > w.maxSegmentSeconds then w.maxSegmentSeconds = seconds end
        w.segments = w.segments + 1
        w.active = false
        w.segmentStartMs = nil
    end
    return active
end

local function willFinalizeSegment(now)
    local w = AOUA.Session.willControl
    if not w.active then return end
    local finish = now
    for _, effect in pairs(w.effects or {}) do
        if effect and tonumber(effect.expiresAtMs) and effect.expiresAtMs < finish then
            finish = effect.expiresAtMs
        end
    end
    local start = tonumber(w.segmentStartMs) or finish
    local seconds = math.max(0, math.floor((finish - start) / 1000))
    w.totalSeconds = w.totalSeconds + seconds
    if seconds > w.maxSegmentSeconds then w.maxSegmentSeconds = seconds end
    w.segments = w.segments + 1
    w.active = false
    w.segmentStartMs = nil
end

local function willUpsertBuff(buffId)
    if not buffId or not object or type(object.GetBuffInfo) ~= "function" then return end
    local ok, info = pcall(object.GetBuffInfo, buffId)
    if not ok or type(info) ~= "table" then return end
    local isControl, confidence = isWillControlBuff(info)
    local now = willNowMs()
    if not isControl then
        AOUA.Session.willControl.effects[buffId] = nil
        willRefreshActive(now)
        return
    end
    local remaining = tonumber(info.remainingMs)
    if remaining == nil or remaining <= 0 then
        AOUA.Session.willControl.effects[buffId] = nil
        willRefreshActive(now)
        return
    end
    -- Update the interval before changing the active set, so a genuine gap
    -- between two controls is not silently merged into one long control.
    willRefreshActive(now)
    AOUA.Session.willControl.effects[buffId] = {
        expiresAtMs = now + remaining,
        confidence = confidence
    }
    AOUA.Session.willControl.lastEventMs = now
    willRefreshActive(now)
end

function AOUA.OnWillControlBuffAdded(params)
    if type(params) ~= "table" or not isLocalObject(params.objectId) then return end
    ensureSession()
    if not AOUA.Session.started then return end
    willUpsertBuff(params.buffId)
end

function AOUA.OnWillControlBuffChanged(params)
    if type(params) ~= "table" or not isLocalObject(params.objectId) then return end
    ensureSession()
    if not AOUA.Session.started then return end
    willUpsertBuff(params.buffId)
end

function AOUA.OnWillControlBuffRemoved(params)
    if type(params) ~= "table" or not isLocalObject(params.objectId) then return end
    ensureSession()
    if not AOUA.Session.started then return end
    local now = willNowMs()
    AOUA.Session.willControl.effects[params.buffId] = nil
    willRefreshActive(now)
end

function AOUA.SeedWillControlBuffs()
    ensureSession()
    if not object or type(object.GetBuffs) ~= "function" or not avatar or type(avatar.GetId) ~= "function" then return end
    local okId, id = pcall(avatar.GetId)
    if not okId then return end
    local ok, buffs = pcall(object.GetBuffs, id, false)
    if not ok or type(buffs) ~= "table" then return end
    for _, buffId in pairs(buffs) do willUpsertBuff(buffId) end
end

function AOUA.UpdateWillControlSeconds()
    ensureSession()
    if not AOUA.Session.started then return end
    local now = willNowMs()
    willRefreshActive(now)
end

function AOUA.FinalizeWillControl()
    ensureSession()
    if AOUA.Session.willControl.active then
        willFinalizeSegment(willNowMs())
    end
end

function AOUA.OnWillControlCombatStatus(params)
    if type(params) ~= "table" or not isLocalObject(params.objectId) then return end
    if params.inCombat == false then
        AOUA.FinalizeWillControl()
        local w = AOUA.Session.willControl
        w.effects = {}
        w.active = false
        w.segmentStartMs = nil
        w.resetReason = "combat_end"
    end
end

function AOUA.OnWillControlAliveChanged(params)
    if type(params) ~= "table" then return end
    if params.alive == false then
        AOUA.FinalizeWillControl()
        local w = AOUA.Session.willControl
        w.effects = {}
        w.active = false
        w.segmentStartMs = nil
        w.resetReason = "death"
    end
end

function AOUA.ResetWillControl(reason)
    ensureSession()
    local w = AOUA.Session.willControl
    if w.active then willFinalizeSegment(willNowMs()) end
    w.effects = {}
    w.active = false
    w.segmentStartMs = nil
    w.totalSeconds = 0
    w.maxSegmentSeconds = 0
    w.segments = 0
    w.lastEventMs = nil
    w.resetReason = reason
end

local WILL_THRESHOLDS = {
    { seconds = 25, minWill = 1, maxWill = 2 },
    { seconds = 20, minWill = 3, maxWill = 5 },
    { seconds = 17, minWill = 6, maxWill = 12 },
    { seconds = 15, minWill = 13, maxWill = 21 },
    { seconds = 13, minWill = 22, maxWill = 33 },
    { seconds = 12, minWill = 34, maxWill = 50 },
    { seconds = 10, minWill = 51, maxWill = 91 },
    { seconds = 9, minWill = 92, maxWill = 115 },
    { seconds = 8, minWill = 116, maxWill = 169 },
    { seconds = 7, minWill = 170, maxWill = 226 },
    { seconds = 6, minWill = 227, maxWill = 315 },
    { seconds = 5, minWill = 316, maxWill = 466 },
    { seconds = 4, minWill = 467, maxWill = 732 },
    { seconds = 3, minWill = 733, maxWill = 1176 },
    { seconds = 2, minWill = 1177, maxWill = 2413 },
    { seconds = 1, minWill = 2414, maxWill = nil }
}

local function willExpectedSeconds(will)
    will = tonumber(will)
    if not will or will <= 0 then return nil, nil end
    local p = math.min(900, 1.6 * will / (1 + will ^ 1.05 / 1000)) / 1000
    local t = (p / 0.05) ^ 0.75
    local increment = math.ceil(150 / (t / p - t))
    return math.ceil(100 / increment), increment
end

local function willThresholdRange(seconds)
    for i = 1, #WILL_THRESHOLDS do
        if WILL_THRESHOLDS[i].seconds == seconds then return WILL_THRESHOLDS[i] end
    end
    return nil
end

function AOUA.GetWillControlSummary()
    ensureSession()
    local will
    if unit and type(unit.GetWill) == "function" and avatar and type(avatar.GetId) == "function" then
        local okId, id = pcall(avatar.GetId)
        if okId then
            local ok, value = pcall(unit.GetWill, id)
            if ok then will = tonumber(value) end
        end
    end
    if will == nil and AOUA.Session.statSnapshot then
        will = tonumber(AOUA.Session.statSnapshot.W)
    end
    local expected, increment = willExpectedSeconds(will)
    local w = AOUA.Session.willControl
    if w.active then willRefreshActive(willNowMs()) end
    local range = expected and willThresholdRange(expected) or nil
    return {
        will = will,
        expectedSeconds = expected,
        increment = increment,
        totalControlSeconds = w.totalSeconds,
        maxControlSeconds = w.maxSegmentSeconds,
        segments = w.segments,
        thresholdReached = expected and w.maxSegmentSeconds >= expected or false,
        thresholdMinWill = range and range.minWill or nil,
        thresholdMaxWill = range and range.maxWill or nil,
        resetReason = w.resetReason,
        pvpOnly = true
    }
end


local function captureStatSnapshot()
    local session = AOUA.Session
    local currentSecond = math.max(0, math.floor(tonumber(session.elapsedSeconds) or 0))
    local previous = session.statSnapshot

    local previousSecond = tonumber(session.statSnapshotSecond)
    local lastAttemptSecond = tonumber(session.statSnapshotAttemptSecond)
    if lastAttemptSecond == currentSecond then
        return previous or {}
    end
    if previous and previousSecond and (currentSecond - previousSecond) < STAT_SNAPSHOT_INTERVAL then
        return previous
    end
    if lastAttemptSecond and (currentSecond - lastAttemptSecond) < STAT_SNAPSHOT_INTERVAL then
        return previous or {}
    end

    -- One attempt per interval, even when the API temporarily fails.
    session.statSnapshotAttemptSecond = currentSecond
    local values
    if Optim and type(Optim.ReadStats) == "function" then
        local ok, result = pcall(Optim.ReadStats)
        if ok and type(result) == "table" then values = result end
    end
    if not values then return previous or {} end

    local snapshot = {}
    local changed = previous == nil
    for i = 1, #SNAPSHOT_STAT_KEYS do
        local key = SNAPSHOT_STAT_KEYS[i]
        local row = values[key]
        local value = row and tonumber(row.total) or nil
        snapshot[key] = value
        local oldValue = previous and tonumber(previous[key]) or nil
        if value ~= nil and oldValue ~= nil and math.abs(value - oldValue) > 0.01 then
            changed = true
        elseif (value == nil) ~= (oldValue == nil) then
            changed = true
        end
    end

    -- Max HP is stable for a stat snapshot. Re-read it only when a stat changed
    -- or when no valid value has ever been captured.
    if changed or not (previous and tonumber(previous.HPmax) and previous.HPmax > 0) then
        if avatar and type(avatar.GetId) == "function" and Optim and type(Optim.GetHealth) == "function" then
            local okId, id = pcall(avatar.GetId)
            if okId then
                local okHp, _, maximum, real = pcall(Optim.GetHealth, id)
                if okHp and real and tonumber(maximum) and maximum > 0 then
                    snapshot.HPmax = tonumber(maximum)
                end
            end
        end
    else
        snapshot.HPmax = previous.HPmax
    end

    session.statSnapshot = snapshot
    session.statSnapshotSecond = currentSecond
    return snapshot
end

local function appendEventSample(kind, params, amount, hpBefore, hpQuality, targetMaxHp, determination, resolvedAbilityName)
    if not AOUA.Session.started then return end
    local samples = AOUA.Session.eventSamples
    local sampleCount = AOUA.Session.eventSampleCount or #samples
    local sampleIndex
    if sampleCount < EVENT_BUFFER_LIMIT then
        sampleIndex = sampleCount + 1
        sampleCount = sampleCount + 1
    else
        -- Fixed-size ring buffer: overwrite the oldest row in O(1). The old
        -- table.remove(samples, 1) shifted up to 1,999 rows for every later hit.
        sampleIndex = AOUA.Session.eventSampleNext or 1
        AOUA.Session.eventSamplesDropped = AOUA.Session.eventSamplesDropped + 1
    end
    local targetId = (kind == "damage" or kind == "incoming") and params.target or params.unitId
    if not targetId and kind == "damage" and Optim and type(Optim.GetTarget) == "function" then
        local ok, target = pcall(Optim.GetTarget)
        if ok then targetId = target end
    end
    local actorId = (kind == "healing" or kind == "receivedHeal")
        and (params.healerId or params.source) or params.source
    local targetKey = eventObjectId(targetId) or ""
    local actorKey = eventObjectId(actorId) or ""
    local actorMeta = readObjectMetadata(actorId)
    local targetMeta = readObjectMetadata(targetId)
    local actorName, actorLevel, actorQuality, actorQualityName, actorKind, actorIsMob =
        metadataCsv(actorMeta)
    local targetName, targetLevel, targetQuality, targetQualityName, targetKind, targetIsMob =
        metadataCsv(targetMeta)
    local targetHealth = targetId and AOUA.HpCache[targetId] or nil
    local targetHpCurrent, targetHpCurrentPercent, targetHpLimit, targetHpSnapshotQuality, targetHpSnapshotAge
    if targetHealth and targetHealth.real == true and tonumber(targetHealth.value)
        and tonumber(targetHealth.limit) and targetHealth.limit > 0 then
        targetHpCurrent = tonumber(targetHealth.value)
        targetHpLimit = tonumber(targetHealth.limit)
        targetHpCurrentPercent = targetHpCurrent / targetHpLimit * 100
        targetHpSnapshotQuality = "measured"
        local hpSecond = tonumber(targetHealth.second)
        if hpSecond ~= nil then
            targetHpSnapshotAge = math.max(0, (tonumber(AOUA.Session.elapsedSeconds) or 0) - hpSecond)
        end
    else
        targetHpSnapshotQuality = "unknown"
    end
    local recipient = ""
    if kind == "healing" or kind == "receivedHeal" then
        recipient = isLocalObject(targetId) and "self" or "ally"
    end
    local stats = captureStatSnapshot()
    local currentSecond = math.max(0, math.floor(tonumber(AOUA.Session.elapsedSeconds) or 0))
    local snapshotSecond = tonumber(AOUA.Session.statSnapshotSecond)
    local snapshotAge = snapshotSecond and math.max(0, currentSecond - snapshotSecond) or nil
    local ability = eventText(resolvedAbilityName) or abilityLabel(params, nil) or "unknown"
    local element = eventText(params.sysSubElement or params.subElement or params.element) or ""
    element = string.gsub(element, "^ENUM_SubElement_", "")
    local values = {
        tostring(AOUA.Session.fightId or 0), AOUA.Profile or (Optim and Optim.Cfg and Optim.Cfg.mode) or "pve",
        tostring(AOUA.Session.elapsedSeconds or 0), kind,
        sampleNumber(amount), sampleNumber((hpBefore ~= nil) and hpBefore * 100 or nil),
        hpQuality or "unknown", sampleNumber(targetMaxHp), actorKey, targetKey,
        (params.isCritical == nil) and "" or (params.isCritical and "1" or "0"), element,
        eventText(params.damageSource) or "", sampleNumber(params.resist),
        sampleNumber(params.absorb), sampleNumber(params.runesAbsorb),
        sampleNumber(params.shieldBlock), sampleNumber(params.parry),
        sampleNumber(params.barrier), sampleNumber(params.toMount),
        sampleNumber(params.multipliersAbsorb), sampleNumber(params.overallAbsorbedDamage),
        sampleNumber(params.overallPreventedDamage), sampleNumber(determination or params.determination),
        recipient, ability,
        sampleNumber(stats.M), sampleNumber(stats.R), sampleNumber(stats.U), sampleNumber(stats.L),
        sampleNumber(stats.S), sampleNumber(stats.W), sampleNumber(stats.B), sampleNumber(stats.C),
        sampleNumber(stats.HPmax), sampleNumber(snapshotSecond), sampleNumber(snapshotAge),
        actorName, actorLevel, actorQuality, actorQualityName, actorKind, actorIsMob,
        targetName, targetLevel, targetQuality, targetQualityName, targetKind, targetIsMob,
        sampleNumber(targetHpCurrent), sampleNumber(targetHpCurrentPercent),
        sampleNumber(targetHpLimit), targetHpSnapshotQuality or "unknown",
        sampleNumber(targetHpSnapshotAge)
    }
    samples[sampleIndex] = table.concat(values, "|")
    if kind == "damage" then
        updateTargetProfile(targetKey, targetMeta, amount, hpBefore, hpQuality,
            targetHpCurrent, targetHpLimit, targetHpCurrentPercent, targetHpSnapshotAge,
            element, params)
    end
    AOUA.Session.eventSampleCount = sampleCount
    AOUA.Session.eventSampleNext = (sampleIndex % EVENT_BUFFER_LIMIT) + 1
end

local function currentEventSamples()
    local source = AOUA.Session.eventSamples or {}
    local count = math.max(0, math.min(EVENT_BUFFER_LIMIT,
        math.floor(tonumber(AOUA.Session.eventSampleCount) or #source)))
    local rows = {}
    local first = (count >= EVENT_BUFFER_LIMIT) and (AOUA.Session.eventSampleNext or 1) or 1
    for i = 0, count - 1 do
        local index = ((first + i - 1) % EVENT_BUFFER_LIMIT) + 1
        local row = source[index]
        if row ~= nil then rows[#rows + 1] = row end
    end
    return rows
end

local function loadPersistedEventSamples()
    local rows = {}
    pcall(function()
        local section = userMods.GetGlobalConfigSection(common.GetAddonName())
        local count = math.max(0, math.min(EVENT_HISTORY_LIMIT, math.floor(tonumber(section and section.aou_evt_count) or 0)))
        local first = math.max(1, count - EVENT_HISTORY_LIMIT + 1)
        for i = first, count do
            local row = section["aou_evt_" .. i]
            if row ~= nil and tostring(row) ~= "" then rows[#rows + 1] = tostring(row) end
        end
    end)
    return rows
end

local function persistEventSamples()
    local current = currentEventSamples()
    if #current == 0 then return true, 0 end
    local ok = pcall(function()
        local name = common.GetAddonName()
        local section = userMods.GetGlobalConfigSection(name)
        if type(section) ~= "table" then section = {} end
        local oldCount = math.max(0, math.min(100000, math.floor(tonumber(section.aou_evt_count) or 0)))
        local combined = {}
        local currentFirst = math.max(1, #current - EVENT_HISTORY_LIMIT + 1)
        local currentToPersist = #current - currentFirst + 1
        local keepOld = math.max(0, EVENT_HISTORY_LIMIT - currentToPersist)
        local firstOld = math.max(1, oldCount - keepOld + 1)
        for i = firstOld, oldCount do
            local oldRow = section["aou_evt_" .. i]
            if oldRow ~= nil and tostring(oldRow) ~= "" then combined[#combined + 1] = tostring(oldRow) end
        end
        for i = currentFirst, #current do combined[#combined + 1] = current[i] end
        local oldSlots = math.min(EVENT_HISTORY_LIMIT, oldCount)
        for i = 1, #combined do section["aou_evt_" .. i] = combined[i] end
        for i = #combined + 1, oldSlots do section["aou_evt_" .. i] = "" end
        section.aou_evt_count = #combined
        section.aou_evt_schema = "v3"
        section.aou_evt_fight_id = tonumber(AOUA.Session.fightId) or 0
        section.aou_evt_last_dropped = tonumber(AOUA.Session.eventSamplesDropped) or 0
        section.aou_evt_last_seconds = tonumber(AOUA.Session.elapsedSeconds) or 0
        userMods.SetGlobalConfigSection(name, section)
    end)
    return ok, ok and #current or 0
end

function AOUA.OnFightStop()
    ensureSession()
    if not AOUA.Session.started then return true, 0 end
    AOUA.FinalizeWillControl()
    AOUA.Session.started = false
    local ok, count = persistEventSamples()
    AOUA.Session.persistedEvents = ok and count or 0
    return ok, count
end

-- Export only a small page per invocation: bulk chat output can freeze the client.
local EVENT_EXPORT_PAGE_SIZE = 10

function AOUA.EventExport(count, page)
    local rows = loadPersistedEventSamples()
    if AOUA.Session.started then
        local current = currentEventSamples()
        for i = 1, #current do rows[#rows + 1] = current[i] end
    end
    count = math.max(1, math.min(EVENT_HISTORY_LIMIT, math.floor(tonumber(count) or 100)))
    page = math.max(1, math.floor(tonumber(page) or 1))
    if #rows == 0 then
        if type(message) == "function" then message("event export: no stored events") end
        return false, "No event rows to export."
    end

    local first = math.max(1, #rows - count + 1)
    local selected = #rows - first + 1
    local pages = math.max(1, math.ceil(selected / EVENT_EXPORT_PAGE_SIZE))
    if page > pages then
        return false, "Page " .. page .. " does not exist; available pages: 1-" .. pages .. "."
    end
    local pageFirst = first + (page - 1) * EVENT_EXPORT_PAGE_SIZE
    local pageLast = math.min(#rows, pageFirst + EVENT_EXPORT_PAGE_SIZE - 1)
    local rowFirst = pageFirst - first + 1
    local rowLast = pageLast - first + 1

    local function emit(line)
        if type(message) == "function" then pcall(message, line) end
    end
    local function emitChunks(kind, value)
        local size = 58
        local parts = math.max(1, math.ceil(#value / size))
        for part = 1, parts do
            emit("AOUCSV|" .. kind .. "|" .. part .. "|" .. parts .. "|" ..
                string.sub(value, (part - 1) * size + 1, part * size))
        end
    end

    -- Every page repeats the identical header and global row numbering so that
    -- multiple page captures can be concatenated into one OCR text file.
    emit("AOUCSV|BEGIN|3|" .. selected .. "|events")
    emitChunks("H", EVENT_COLUMNS)
    for i = pageFirst, pageLast do
        emitChunks("R" .. (i - first + 1), rows[i])
    end
    emit("AOUCSV|END")

    local summary = "Event export page " .. page .. "/" .. pages ..
        ": rows " .. rowFirst .. "-" .. rowLast .. " of " .. selected ..
        ". Capture this page, then run /aou eventfile " .. count .. " " ..
        (page + 1) .. " for the next page."
    return true, summary
end

local function journalRow(map, key, limit)
    key = eventText(key) or "unknown"
    if #key > 72 then key = string.sub(key, 1, 72) end
    if map[key] then return map[key], key end
    if (map._count or 0) >= (limit or 48) then
        if map["(other)"] then return map["(other)"], "(other)" end
        key = "(other)"
    end
    local row = { events = 0, amount = 0 }
    map[key] = row
    map._count = (map._count or 0) + 1
    return row, key
end

local tagInfoCache = setmetatable({}, { __mode = "k" })

local function tagInfo(tag)
    local tagType = type(tag)
    local cacheable = tagType == "table" or tagType == "userdata"
    if cacheable then
        local cached = tagInfoCache[tag]
        if cached then return cached[1], cached[2] end
    end
    local ok, info = pcall(function() return tag:GetInfo() end)
    if not ok or type(info) ~= "table" then
        if cacheable then tagInfoCache[tag] = { false, nil } end
        return nil, nil
    end
    local name, helpful = eventText(info.shortName) or eventText(info.name), info.isHelpful
    if cacheable then tagInfoCache[tag] = { name or false, helpful } end
    return name, helpful
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

local function recordDamageJournal(activity, params, amount, resolvedAbilityName)
    local j = AOUA.Session.journal
    local sourceType = eventText(params.damageSource) or "unknown"
    local ability = sourceType .. " / " .. abilityLabel(params, resolvedAbilityName)
    local typeMap, abilityMap = j[activity .. "ByType"], j[activity .. "ByAbility"]
    local elementMap = j[activity .. "ByElement"]
    if elementMap then
        local element = eventText(params.sysSubElement or params.subElement or params.element) or "unknown"
        element = string.gsub(element, "^ENUM_SubElement_", "")
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

local function healingJournalDelta(params, amount, effective, overheal, known)
    return {
        amount = amount, effective = effective or 0, overheal = overheal or 0,
        wound = N(params.resisted), runeWound = N(params.runeResisted),
        absorbed = N(params.absorbed), overload = N(params.overload),
        lifeSteal = params.isLifeSteal and 1 or 0,
        crits = params.isCritical and 1 or 0,
        known = known and 1 or 0, unknown = known and 0 or 1
    }
end

local function recordHealingJournal(kind, params, amount, effective, overheal, known, resolvedAbilityName)
    local map = (kind == "receivedHeal") and AOUA.Session.journal.receivedHealByAbility
        or AOUA.Session.journal.outgoingHealByAbility
    local row, key = journalRow(map, abilityLabel(params, resolvedAbilityName), 64)
    local delta = healingJournalDelta(params, amount, effective, overheal, known)
    row.events, row.amount = row.events + 1, row.amount + amount
    row.effective = (row.effective or 0) + delta.effective
    row.overheal = (row.overheal or 0) + delta.overheal
    row.wound = (row.wound or 0) + delta.wound
    row.runeWound = (row.runeWound or 0) + delta.runeWound
    row.absorbed = (row.absorbed or 0) + delta.absorbed
    row.overload = (row.overload or 0) + delta.overload
    row.lifeSteal = (row.lifeSteal or 0) + delta.lifeSteal
    row.crits = (row.crits or 0) + delta.crits
    local lethality = tonumber(params.lethality)
    if lethality ~= nil then
        row.lethalitySum = (row.lethalitySum or 0) + lethality
        row.lethalitySamples = (row.lethalitySamples or 0) + 1
    end
    if known then row.known = (row.known or 0) + 1 else row.unknown = (row.unknown or 0) + 1 end
    return map, key, delta
end

isLocalObject = function(id)
    if not id or not avatar or type(avatar.GetId) ~= "function" then return false end
    local ok, playerId = pcall(avatar.GetId)
    return ok and id == playerId
end

local function recordHealing(kind, params, amount, determination, resolvedAbilityName)
    local b = AOUA.Session[kind]
    local reportedHeal = math.max(0, amount)
    if reportedHeal > 0 then
        addEvent(b, reportedHeal, params)
        -- EVENT_HEALING_RECEIVED reports the heal amount after the recipient's
        -- missing-HP cap. Treat this as the applied amount; the modifier fields
        -- are separate raw counters and must not be subtracted from it.
        b.effective = b.effective + reportedHeal
        b.hpMeasured = b.hpMeasured + 1
        b.overhealUnknown = b.overhealUnknown + 1
        local hpBefore, hpQuality, targetMaxHp = recordHealthPhase(kind, params, reportedHeal, "reported")
        appendEventSample(kind, params, reportedHeal, hpBefore, hpQuality, targetMaxHp, determination, resolvedAbilityName)
    end

    local resisted, runeResisted, absorbed, overload = math.max(0, N(params.resisted)),
        math.max(0, N(params.runeResisted)), math.max(0, N(params.absorbed)),
        math.max(0, N(params.overload))
    b.healResisted = b.healResisted + resisted
    b.runeResisted = b.runeResisted + runeResisted
    b.healAbsorbed = b.healAbsorbed + absorbed
    b.reportedOverload = b.reportedOverload + overload

    return recordHealingJournal(kind, params, reportedHeal, reportedHeal, 0, true, resolvedAbilityName)
end

local function movePendingHealAbility(pending, resolvedName)
    if not pending or not resolvedName or resolvedName == "" or resolvedName == "?" or resolvedName == "unknown" then
        return
    end
    local map, oldKey = pending.map, pending.key
    local newKey = resolvedName
    if not map or oldKey == newKey then return end
    local oldRow = map[oldKey]
    if not oldRow or N(oldRow.events) <= 0 then return end
    local newRow = journalRow(map, newKey, 64)
    local delta = pending.delta or {}
    oldRow.events = oldRow.events - 1
    newRow.events = newRow.events + 1
    for _, field in ipairs({
        "amount", "effective", "overheal", "wound", "runeWound",
        "absorbed", "overload", "lifeSteal", "crits", "known", "unknown"
    }) do
        local value = N(delta[field])
        oldRow[field] = N(oldRow[field]) - value
        newRow[field] = N(newRow[field]) + value
    end
    if oldRow.lethalitySum ~= nil then
        oldRow.lethalitySum = N(oldRow.lethalitySum) - N(pending.lethalitySum)
        newRow.lethalitySum = N(newRow.lethalitySum) + N(pending.lethalitySum)
    end
    if oldRow.lethalitySamples ~= nil then
        oldRow.lethalitySamples = N(oldRow.lethalitySamples) - N(pending.lethalitySamples)
        newRow.lethalitySamples = N(newRow.lethalitySamples) + N(pending.lethalitySamples)
    end
    if oldRow.events <= 0 then map[oldKey] = nil end
end

function AOUA.OnHit(combatant, mode, params, determination, spellInfo)
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
    -- Incoming damage and received healing are counted by raw personal API handlers.
    -- The legacy meter callback supplies a resolved spell name for healing; use it
    -- only to relabel the already-recorded raw event, never to count it a second time.
    if kind == "incoming" then return end
    if kind == "receivedHeal" then
        local pending = AOUA.PendingReceivedHeal and AOUA.PendingReceivedHeal[params]
        local resolvedName = spellInfo and eventText(spellInfo.Name) or nil
        if pending then movePendingHealAbility(pending, resolvedName) end
        if AOUA.PendingReceivedHeal then AOUA.PendingReceivedHeal[params] = nil end
        return
    end

    if kind == "damage" then
        local diag = AOUA.Session.rawDiagnostics
        diag.outgoingHitCallbacks = diag.outgoingHitCallbacks + 1
    end
    if not combatant or not combatant.ID or not avatar or type(avatar.GetId) ~= "function" then
        if kind == "damage" then
            AOUA.Session.rawDiagnostics.outgoingHitRejected =
                AOUA.Session.rawDiagnostics.outgoingHitRejected + 1
        end
        return
    end
    local okId, playerId = pcall(avatar.GetId)
    if not okId or not sameEventObject(combatant.ID, playerId) then
        if kind == "damage" then
            AOUA.Session.rawDiagnostics.outgoingHitOtherCombatant =
                AOUA.Session.rawDiagnostics.outgoingHitOtherCombatant + 1
        end
        return
    end
    if kind == "damage" then
        AOUA.Session.rawDiagnostics.outgoingHitOwnerMatched =
            AOUA.Session.rawDiagnostics.outgoingHitOwnerMatched + 1
    end

    local amount = (kind == "healing") and N(params.heal or params.amount) or N(params.amount)
    if amount <= 0 then
        if kind == "damage" then
            AOUA.Session.rawDiagnostics.outgoingHitRejected =
                AOUA.Session.rawDiagnostics.outgoingHitRejected + 1
        end
        return
    end
    if kind == "damage" then
        local diag = AOUA.Session.rawDiagnostics
        diag.outgoingHitAccepted = diag.outgoingHitAccepted + 1
        diag.lastOutgoingTarget = eventObjectId(params.target) or ""
        diag.lastOutgoingAmount = amount
    end
    local b = AOUA.Session[kind]
    if kind == "damage" then addEvent(b, amount, params) end

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
        local hpBefore, hpQuality, targetMaxHp = recordHealthPhase(kind, params, amount, "estimated")
        appendEventSample(kind, params, amount, hpBefore, hpQuality, targetMaxHp, rawDetermination, spellInfo and spellInfo.Name)
        recordDamageJournal("outgoing", params, amount, spellInfo and spellInfo.Name)
    elseif kind == "healing" then
        recordHealing("healing", params, amount, rawDetermination, spellInfo and spellInfo.Name)
    end
end


function AOUA.OnEventRegistrationStats(damageFilters, healFilters, healthFilters)
    ensureSession()
    local d = AOUA.Session.rawDiagnostics
    d.damageFilters = tonumber(damageFilters) or 0
    d.healFilters = tonumber(healFilters) or 0
    d.healthFilters = tonumber(healthFilters) or 0
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
    local transition = takeHealthTransition(params.target, -1, amount)
    local value, limit, real
    local hpBefore, hpQuality, targetMaxHp
    if transition then
        hpBefore = transition.beforeFrac
        hpQuality = transition.exact and "measured_pre" or "estimated_pre"
        targetMaxHp = transition.limit
    else
        value, limit, real = safeHealth(params.target)
        if value ~= nil and limit and limit > 0 then
            if real then
                hpBefore = math.max(0, math.min(1, (value + amount) / limit))
                hpQuality = "estimated_pre"
            else
                hpBefore = math.max(0, math.min(1, value / limit))
                hpQuality = "post_only"
            end
        else
            hpQuality = "unknown"
        end
        targetMaxHp = real and limit or nil
        if value ~= nil and limit and limit > 0 then
            AOUA.HpCache[params.target] = {
                value = value, limit = limit, real = real,
                second = tonumber(AOUA.Session.elapsedSeconds) or 0
            }
        end
    end
    appendEventSample("incoming", params, amount, hpBefore, hpQuality, targetMaxHp, nil, nil)
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
    local map, key, delta = recordHealing("receivedHeal", params, math.max(0, N(params.heal or params.amount)), params.determination, nil)
    if map and key and delta then
        local lethality = tonumber(params.lethality)
        AOUA.PendingReceivedHeal[params] = {
            map = map, key = key, delta = delta,
            lethalitySum = lethality or 0,
            lethalitySamples = lethality ~= nil and 1 or 0
        }
    end
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
        return label .. ": heal field/applied=" .. fmt(x.amount) .. "/" .. fmt(x.effective) ..
            ", overheal=unknown (" .. fmt(x.overhealUnknown) .. " events)" ..
            ", raw overload/resisted/rune/absorbed=" .. fmt(x.reportedOverload) .. "/" ..
            fmt(x.healResisted) .. "/" .. fmt(x.runeResisted) .. "/" .. fmt(x.healAbsorbed) ..
            ", applied confidence reported/estimated/unknown=" ..
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
        " (" .. fmt(d.totalAbsorbedSamples) .. " samples), net prevented=" ..
        fmt(d.overallPrevented) .. " (" .. fmt(d.totalPreventedSamples) .. " samples; negative means net damage increase)" ..
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
        "Target filter counts damage/heal/health=" .. fmt(rd.damageFilters) .. "/" ..
            fmt(rd.healFilters) .. "/" .. fmt(rd.healthFilters),
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
            " API absorbed/net prevented=" .. fmt(x.absorbed) .. "/" .. fmt(x.prevented) ..
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
            " crits=" .. fmt(x.crits) .. " target absorbed/net prevented=" .. fmt(x.absorbed) .. "/" .. fmt(x.prevented)
    end, 4)
    out[#out + 1] = topJournalRows("Received healing by ability", j.receivedHealByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " heal-field/applied/overheal=" ..
            fmt(x.amount) .. "/" .. fmt(x.effective) .. "/n/a" ..
            " overload/wound/rune/absorbed=" .. fmt(x.overload) .. "/" ..
            fmt(x.wound) .. "/" .. fmt(x.runeWound) .. "/" .. fmt(x.absorbed) ..
            " crits=" .. fmt(x.crits) .. " lifeSteal=" .. fmt(x.lifeSteal) ..
            " lethality avg=" .. (N(x.lethalitySamples) > 0 and string.format("%.1f", N(x.lethalitySum) / N(x.lethalitySamples)) or "n/a") ..
            " (n=" .. fmt(x.lethalitySamples) .. ") unknown=" .. fmt(x.unknown)
    end, 5)
    out[#out + 1] = topJournalRows("Outgoing healing by ability", j.outgoingHealByAbility, "amount", function(k, x)
        return k .. " n=" .. fmt(x.events) .. " heal-field/applied/overheal=" ..
            fmt(x.amount) .. "/" .. fmt(x.effective) .. "/n/a" ..
            " overload/wounds/runes/absorbed=" .. fmt(x.overload) .. "/" ..
            fmt(x.wound) .. "/" .. fmt(x.runeWound) .. "/" .. fmt(x.absorbed)
    end, 4)
    out[#out + 1] = "Negative net prevented values indicate damage amplification by target-side multipliers, not negative absorption."
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
    if cmd == "eventlog" then
        local stored = 0
        pcall(function()
            local section = userMods.GetGlobalConfigSection(common.GetAddonName())
            stored = tonumber(section and section.aou_evt_count) or 0
        end)
        return true, "Event history: stored=" .. fmt(stored) ..
            ", current=" .. fmt(#(AOUA.Session.eventSamples or {})) ..
            ", dropped in current fight=" .. fmt(AOUA.Session.eventSamplesDropped or 0) ..
            ", buffer limit=" .. fmt(EVENT_BUFFER_LIMIT) ..
            ", storage limit=" .. fmt(EVENT_HISTORY_LIMIT)
    end
    if cmd == "eventexport" or cmd == "rawexport" or cmd == "eventfile" then
        local countText, pageText = string.match(rest, "^(%d+)%s*(%d*)")
        local count = tonumber(countText) or 100
        local page = tonumber(pageText) or 1
        local ok, summary = AOUA.EventExport(count, page)
        if not ok then return true, summary or "No event rows to export." end
        if cmd == "eventfile" then
            return true, (summary or "Event export page ready.") ..
                " Save all page captures into one UTF-8 OCR text file; after the last page run tools/aou_ai_companion.py."
        end
        return true, (summary or "Event export page sent.") ..
            " Append this page to the same OCR text file before exporting the next page."
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
