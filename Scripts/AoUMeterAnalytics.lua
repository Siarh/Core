--------------------------------------------------------------------------------
-- File: AoUMeterAnalytics.lua
-- Desc: DPScope build 28 combat analytics for Allods Sunshine 6.0
-- Features: Phase analysis, healing efficiency, stat optimization
--------------------------------------------------------------------------------

Global("AOUA", {})
AOUA.Version = "28"
AOUA.Profile = AOUA.Profile or "pve"
AOUA.Session = AOUA.Session or {}
AOUA.Phases = AOUA.Phases or {
    ["damage_100_75"] = {},
    ["damage_75_50"] = {},
    ["damage_50_25"] = {},
    ["damage_25_0"] = {},
    ["healing_100_75"] = {},
    ["healing_75_50"] = {},
    ["healing_50_25"] = {},
    ["healing_25_0"] = {}
}
AOUA.DeterminationStats = AOUA.DeterminationStats or {
    poolValues = {},
    eventsAbove50 = 0,
    eventsAbove67 = 0,
    eventsAbove90 = 0,
    totalEvents = 0
}

local function num(v)
    if v == nil then return 0 end
    local ok, n = pcall(function() return tonumber(tostring(v)) or 0 end)
    if ok then return n end
    return 0
end

local function newBucket()
    return {events=0, amount=0, crits=0, glancing=0, misses=0, dodges=0,
        resist=0, absorb=0, runeAbsorb=0, block=0, parry=0, barrier=0,
        mount=0, multAbsorb=0, last={}}
end

local function getBucket(name)
    if not AOUA.Session[name] then AOUA.Session[name] = newBucket() end
    return AOUA.Session[name]
end

local function add(b, key, value)
    b[key] = (b[key] or 0) + num(value)
end

function AOUA.OnHit(combatant, mode, params, determination)
    if type(params) ~= "table" then return end
    local name
    if enumMode then
        if mode == enumMode.Dps then name="damage"
        elseif mode == enumMode.Def then name="incoming"
        elseif mode == enumMode.Hps then name="healing"
        elseif mode == enumMode.IHps then name="receivedHeal"
        end
    end
    if not name then return end
    local b=getBucket(name)
    local amount=num(params.amount)
    if name=="healing" or name=="receivedHeal" then amount=num(params.heal or params.amount) end
    b.events=b.events+1
    b.amount=b.amount+amount
    if params.isCritical then add(b,"crits",1) end
    if params.isGlancing then add(b,"glancing",1) end
    if params.isMiss then add(b,"misses",1) end
    if params.isDodge then add(b,"dodges",1) end
    add(b,"resist",params.resist)
    add(b,"absorb",params.absorb)
    add(b,"runeAbsorb",params.runesAbsorb)
    add(b,"block",params.shieldBlock)
    add(b,"parry",params.parry)
    add(b,"barrier",params.barrier)
    add(b,"mount",params.toMount)
    add(b,"multAbsorb",params.multipliersAbsorb)
    local e={amount=amount,crit=params.isCritical and 1 or 0,glancing=params.isGlancing and 1 or 0}
    b.last[#b.last+1]=e
    if #b.last>30 then table.remove(b.last,1) end
end

local function fmt(v) return string.format("%.0f", num(v)) end

local function report(name)
    local b=getBucket(name)
    local pct=0
    if b.events>0 then pct=b.crits*100/b.events end
    return name..": events="..fmt(b.events)..", amount="..fmt(b.amount)..
        ", crit="..string.format("%.1f%%",pct)..", glancing="..fmt(b.glancing)
end

local function getCommand(input)
    local s=""
    if type(input)=="string" then s=input
    elseif type(input)=="table" then
        local parts={}
        for i,v in ipairs(input) do
            if type(v)=="string" or type(v)=="number" then parts[#parts+1]=tostring(v) end
        end
        s=table.concat(parts," ")
    else s=tostring(input or "") end
    s=string.lower(s)
    s=string.gsub(s,"^%s+","")
    s=string.gsub(s,"%s+$","")
    s=string.gsub(s,"^/","")
    s=string.gsub(s,"^aou%s*","")
    s=string.gsub(s,"^dpscope%s*","")
    return s
end

function AOUA.OnSlash(input)
    local command=getCommand(input)
    local cmd,rest=string.match(command,"^(%S+)%s*(.-)$")
    cmd=cmd or ""
    if cmd=="diff" then
        return true,"AOUA build 27\n"..report("damage").."\n"..report("incoming").."\n"..report("healing").."\n"..report("receivedHeal")
    end
    if cmd=="log" then
        local out={"AOUA recent events:"}
        local names={"damage","incoming","healing","receivedHeal"}
        for _,name in ipairs(names) do
            local b=getBucket(name)
            local first=math.max(1,#b.last-4)
            for i=first,#b.last do
                local e=b.last[i]
                out[#out+1]=name.." amount="..fmt(e.amount).." crit="..fmt(e.crit)..
                    " glancing="..fmt(e.glancing)
            end
        end
        if #out==1 then out[#out+1]="No events collected yet." end
        return true,table.concat(out,"\n")
    end
    if cmd=="prof" then
        local profile=string.match(rest,"^(%S+)")
        if not profile or profile=="list" then
            return true,"Profiles: pve, raid, pvp, heal, tank. Current: "..AOUA.Profile
        end
        if profile=="pve" or profile=="raid" or profile=="pvp" or profile=="heal" or profile=="tank" then
            AOUA.Profile=profile
            return true,"AOUA profile: "..profile
        end
        return true,"Unknown profile. Use /aou prof list"
    end
    if cmd=="reset" then AOUA.Session={} return true,"AOUA session statistics reset." end
    return false
end
