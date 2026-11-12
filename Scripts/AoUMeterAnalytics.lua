--------------------------------------------------------------------------------
-- File: AoUMeterAnalytics.lua
-- DPScope build 28 analytics for Allods Sunshine 6.0
-- Event-driven measurements. Unknown / unavailable values are not fabricated.
--------------------------------------------------------------------------------

AOUA = AOUA or {}
AOUA.Version = "28"
AOUA.HpCache = AOUA.HpCache or {}
AOUA.Profile = AOUA.Profile or "pve"
AOUA.Session = AOUA.Session or {}

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
        hpMeasured = 0, hpEstimated = 0, hpUnknown = 0,
        determinationSum = 0, determinationSamples = 0,
        last = {}
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
            totalAbsorbedSamples = 0, totalPreventedSamples = 0
        },
        determination = { sum = 0, min = nil, max = nil, samples = 0,
            above50 = 0, above67 = 0, above90 = 0 },
        targetHealth = { samples = 0, estimated = 0, unknown = 0 },
        started = false
    }
end

AOUA.Session = AOUA.Session or freshSession()
local function ensureSession()
    if not AOUA.Session.damage or not AOUA.Session.phases then
        AOUA.Session = freshSession()
    end
end
ensureSession()

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

local function addDetermination(value)
    value = tonumber(value)
    if value == nil or value <= 0 then return end
    local d = AOUA.Session.determination
    d.samples = d.samples + 1
    d.sum = d.sum + value
    if d.min == nil or value < d.min then d.min = value end
    if d.max == nil or value > d.max then d.max = value end
    if value >= 50 then d.above50 = d.above50 + 1 end
    if value >= 67 then d.above67 = d.above67 + 1 end
    if value >= 90 then d.above90 = d.above90 + 1 end
end

local function recordHealthPhase(kind, params, amount, confidence)
    local id
    if kind == "damage" then id = params.target
    elseif kind == "healing" or kind == "receivedHeal" then id = params.unitId end
    if not id and kind == "damage" and Optim and Optim.GetTarget then
        local ok, target = pcall(Optim.GetTarget)
        if ok then id = target end
    end
    local value, limit, real = safeHealth(id)
    if value == nil then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return
    end
    -- A percentage-only post-heal sample cannot reconstruct pre-heal HP.
    if (kind == "healing" or kind == "receivedHeal") and not real then
        AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        return
    end

    AOUA.HpCache[id] = { value = value, limit = limit, real = real }
    local frac = value / limit
    if kind == "damage" then
        if real then
            -- HP is sampled after the hit; adding event damage estimates pre-hit HP.
            frac = math.min(1, math.max(0, (value + amount) / limit))
        else
            -- valuePercents is already a percentage. Never add raw damage to it.
            AOUA.Session.targetHealth.estimated = AOUA.Session.targetHealth.estimated + 1
        end
    elseif kind == "healing" or kind == "receivedHeal" then
        if real then
            -- amount is effective healing; reported overload gives stronger confidence.
            frac = math.min(1, math.max(0, (value - amount) / limit))
        else
            AOUA.Session.targetHealth.estimated = AOUA.Session.targetHealth.estimated + 1
        end
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

    -- The data pipeline supplies the resolved combatant; keep analytics personal.
    if not combatant or not combatant.ID or not avatar or not avatar.GetId then return end
    local okId, playerId = pcall(avatar.GetId)
    if not okId or combatant.ID ~= playerId then return end

    local amount
    if kind == "healing" or kind == "receivedHeal" then
        amount = N(params.heal or params.amount)
    else
        amount = N(params.amount)
    end
    if amount <= 0 then return end

    local b = AOUA.Session[kind]
    addEvent(b, amount, params)

    if kind == "damage" then
        addDetermination(determination or params.determination)
        if determination ~= nil or params.determination ~= nil then
            local dv = N(determination or params.determination)
            b.determinationSum = b.determinationSum + dv
            b.determinationSamples = b.determinationSamples + 1
        end
        recordHealthPhase(kind, params, amount, "estimated")
    elseif kind == "healing" or kind == "receivedHeal" then
        local reported = tonumber(params.overload)
        local effective, overheal, method
        if reported ~= nil then
            overheal = math.max(0, math.min(amount, reported))
            effective = math.max(0, amount - overheal)
            method = "reported"
        else
            -- A post-heal HP read alone cannot reveal overheal. Estimate only
            -- when a previous real HP snapshot for this recipient is available.
            local hp, maxHp, real = safeHealth(params.unitId)
            local previous = params.unitId and AOUA.HpCache[params.unitId] or nil
            if hp ~= nil and real and previous and previous.real and previous.limit == maxHp then
                local gained = math.max(0, hp - previous.value)
                effective = math.min(amount, gained)
                overheal = math.max(0, amount - effective)
                method = "hp-estimate"
            end
        end
        if effective ~= nil then
            b.effective = b.effective + effective
            b.overheal = b.overheal + overheal
            if method == "reported" then b.hpMeasured = b.hpMeasured + 1
            else b.hpEstimated = b.hpEstimated + 1 end
            -- Phase attribution must use the HP actually restored, never the nominal heal.
            recordHealthPhase(kind, params, effective, method)
        else
            b.hpUnknown = b.hpUnknown + 1
            -- Without effective healing, pre-heal target HP cannot be reconstructed safely.
            AOUA.Session.targetHealth.unknown = AOUA.Session.targetHealth.unknown + 1
        end
        if reported ~= nil then b.reportedOverheal = b.reportedOverheal + reported end
    elseif kind == "incoming" then
        local d = AOUA.Session.defense
        d.events = d.events + 1
        d.amount = d.amount + amount
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
    return table.concat(out, "\n")
end

local function healingReport()
    local a, b = AOUA.Session.healing, AOUA.Session.receivedHeal
    local function one(label, x)
        return label .. ": nominal=" .. fmt(x.amount) ..
            ", effective=" .. fmt(x.effective) ..
            ", overheal=" .. fmt(x.overheal) ..
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
        fmt(d.overallPrevented) .. " (" .. fmt(d.totalPreventedSamples) .. " samples)"
end

local function determinationReport()
    local d = AOUA.Session.determination
    if d.samples == 0 then return "Determination: no numeric pool samples received from combat events." end
    return "Determination pool: n=" .. fmt(d.samples) ..
        ", avg=" .. string.format("%.1f", d.sum / d.samples) ..
        ", min/max=" .. fmt(d.min) .. "/" .. fmt(d.max) ..
        ", >=50/67/90=" .. pct(d.above50, d.samples) .. "/" ..
        pct(d.above67, d.samples) .. "/" .. pct(d.above90, d.samples)
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
    if cmd == "stats" then
        return true, determinationReport() ..
            "\nMastery/Ruthlessness: no isolated causal coefficient is inferred from these event fields."
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
    if cmd == "reset" then
        AOUA.Session = freshSession()
        return true, "AOUA session statistics reset."
    end
    return false
end
