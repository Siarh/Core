--------------------------------------------------------------------------------
-- File: AoUMeterOptim.lua
-- Desc: Optimal stat distribution from combat data (Allods Online 7.0 formulas)
--       Mastery / Resolve / Ruthlessness / Luck, Fortitude / Will / Bloodthirst
--------------------------------------------------------------------------------
Global("Optim", {})

Optim.Cfg = {
	mode = "pve",   -- "pve" / "pvp"
	role = "auto",  -- "auto" / "dd" / "heal"
	flag = 1,       -- 1: redistribute the free points, 0: keep the current ones
	tw = 4,         -- wanted seconds of control until immunity (PvP Will)
	hp = 0,         -- max health, used only if the game API does not give it
	auto = 1,       -- 1: the addon reads the character stats itself (then only /aou fix is needed)
	font = 1,       -- how Russian texts are produced: 1 = locale files, 2 = cp1251 conversion, 3 = raw UTF-8
	fM = 0, fR = 0, fU = 0, L = 0, eM = 0, eR = 0, eU = 0, -- offense: fixed (milestones), Luck total, free within the group (equipment + effects)
	fS = 0, fW = 0, fB = 0, eS = 0, eW = 0, eB = 0,        -- defense: fixed (milestones), free within the group (equipment + effects)
	bM = 0, bR = 0, bU = 0, bS = 0, bW = 0, bB = 0,        -- free points (base, e.g. 370 in total): can go to ANY stat
	on = 1,          -- 1: optimizer enabled, 0: switched off (/aou off): no event hook and no calculation at all
	caut = 0,       -- Caution points (0 = read from the game: ENUM_InnateStats_Endurance); damage taken below 40% health x(1 - s/1000), cap 350
	eq = 1,         -- 1 (default): equipment bonuses can be switched with insignias inside their group (offense / defense); 0: only the free points move
	thp = 50,       -- average target health %, used only when the game does not give it
	free = 0,       -- total free points to place (e.g. 370); 0 = use the sum of bM..bB
	bal = 1,        -- weight of defense when splitting the free points: damage x (survival ^ bal); 0 = only damage
}
Optim.Memo = { key = nil, lines = nil }

local CFGKEYS = { "mode", "role", "flag", "tw", "hp", "font", "auto", "fM", "fR", "fU", "L", "eM", "eR", "eU", "fS", "fW", "fB", "eS", "eW", "eB", "bM", "bR", "bU", "bS", "bW", "bB", "free", "bal", "thp", "eq", "caut", "on" }


local function N(x)
        if x == nil then return 0 end
        if type(x) == "number" then return x end

        local ok, v = pcall(tonumber, x)
        if ok and type(v) == "number" then return v end

        local okText, txt = pcall(tostring, x)
        if okText then
                local okN, n = pcall(tonumber, txt)
                if okN and type(n) == "number" then return n end
        end

        local methods = {
                "GetValue", "GetNumber", "GetAmount",
                "GetInt", "ToNumber"
        }

        for i = 1, #methods do
                local okFn, fn = pcall(function()
                        return x[methods[i]]
                end)

                if okFn and type(fn) == "function" then
                        local okV, value = pcall(fn, x)
                        if not okV then okV, value = pcall(fn) end

                        if okV then
                                if type(value) == "number" then return value end
                                local okS, st = pcall(tostring, value)
                                if okS then
                                        local okT, number = pcall(tonumber, st)
                                        if okT and type(number) == "number" then
                                                return number
                                        end
                                end
                        end
                end
        end

        Optim.NumConversionFailed = (Optim.NumConversionFailed or 0) + 1
        Optim.NumLastBadValue = okText and txt or type(x)
        return 0
end

local function I(x)
        return string.format("%d", math.floor(N(x) + 0.5))
end

local function S(x)
        x = math.floor(N(x) + 0.5)
        if x > 0 then return "+" .. x end
        return tostring(x)
end

local function F1(x) return string.format("%.1f", N(x)) end
local function F2(x) return string.format("%.2f", N(x)) end
local function clamp(x, a, b)
        return math.min(N(b), math.max(N(a), N(x)))
end
local function say(txt) message(txt) end

-- Russian texts (used only by the font modes 2 and 3)
Optim.RU = {
	OptTitle = "Оптимизация статов",
	OptNow = "Сейчас",
	OptOpt = "Оптим.",
	OptDiff = "Разн.",
	OptNoData = "Нет данных боя",
	OptHelpRow = "Справка: /aou help",
	OptSet = "Задайте статы: /aou help",
	OptPool = "Ср. решимость, %",
	OptTHP = "Ср. HP цели, %",
	OptM = "Мастерство",
	OptR = "Решимость",
	OptU = "Беспощадность",
	OptL = "Удача",
	OptMult = "Множитель урона",
	OptS = "Стойкость",
	OptW = "Воля",
	OptB = "Кровожадность",
	OptHP = "Здоровье",
	OptTTL = "Время жизни",
	OptHpNeed = "Здоровье: /aou hp N",
	OptSavedAtk = "Атакующие статы сохранены",
	OptSavedDef = "Защитные статы сохранены",
	OptUsageAtk = "Формат: /aou atk fM fR fU L eM eR eU",
	OptUsageDef = "Формат: /aou def fS fW fB eS eW eB",
	OptModeD = "Анализ: урон",
	OptModeH = "Анализ: лечение",
	OptSavedFix = "Закреплённые значения сохранены",
	OptUsageFix = "Формат: /aou fix fM fR fU fS fW fB",
	OptFree = "Своб. очки А/З",
	OptSavedBase = "Свободные очки сохранены",
	OptUsageBase = "Формат: /aou base bM bR bU bS bW bB",
	OptMitHdrD = "Срез урона целью",
	OptMitHdrH = "Потери лечения",
	OptMitVal = "% от удара/лечения",
	OptSchHdr = "Входящий по типам",
	OptSchA = "Броня (физ.)",
	OptSchE = "Стихии",
	OptSchN = "Природа",
	OptSchL = "Свет",
	OptColRes = "резист",
	OptColAbs = "погл.",
	OptColBlk = "блок",
	OptColShare = "доля",
	OptColRune = "руны",
	OptColWound = "раны",
	OptColOver = "перелеч.",
	OptPhi = "Раны (погл. лечения)",
	OptCaut = "Осторожность / здор. x",
	OptErr = "Ошибка расчёта",
	OptMarg = "Прирост за +50 очков, %",
	OptHealSplit = "HP до лечения: союзн./себя/доля",
	OptPoolFb = "Пул Решимости: сейчас/после",
	OptMultFb = "Множитель с учётом пула",
	OptReset = "Настройки сброшены",
	OptHelp1 = "Характеристики и свободные очки аддон читает из игры сам. /aou thp N - ср. HP цели, если не определилось; /aou hp N - здоровье",
	OptHelp2 = "Ручной ввод, если авто не сработало: /aou fix, free, base, atk, def (см. README)",
	OptHelp3 = "/aou caut N, mark имя, rec list|clear|export [N], eq on|off, bal 0-3, auto, probe, hptest, mode pve|pvp, role dd|heal|auto, flag on|off, hp N, tw 1-10, font 1-3, show, reset",
}

-- UTF-8 (Cyrillic) -> Windows-1251 bytes
local function utf8to1251(str)
	local out = {}
	local i, n = 1, #str
	while i <= n do
		local b = string.byte(str, i)
		if b < 128 then
			out[#out + 1] = string.char(b)
			i = i + 1
		elseif (b == 208 or b == 209) and i < n then
			local b2 = string.byte(str, i + 1)
			local cp = (b % 32) * 64 + (b2 % 64)
			local c
			if cp >= 1040 and cp <= 1103 then c = cp - 848
			elseif cp == 1025 then c = 168
			elseif cp == 1105 then c = 184
			else c = 63 end
			out[#out + 1] = string.char(c)
			i = i + 2
		else
			out[#out + 1] = "?"
			i = i + 1
		end
	end
	return table.concat(out)
end

-- Text by key. font 1: locale files (default); 2: ToWString of cp1251 bytes; 3: ToWString of raw UTF-8
function Optim.Text(key)
	local mode = Optim.Cfg.font
	if localization == "rus" and Optim.RU[key] and (mode == 2 or mode == 3) then
		local str = Optim.RU[key]
		if mode == 2 then str = utf8to1251(str) end
		return userMods.ToWString(str)
	end
	return GetTextLocalized(key)
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
-- defaults snapshot (used by reset)
Optim.Defaults = {}
for k, v in pairs(Optim.Cfg) do Optim.Defaults[k] = v end
Optim.Dirty = {} -- keys changed from the chat (only they are saved in the game config)

local function normalize(k, v)
	if v == nil then return nil end
	if k == "flag" and type(v) == "boolean" then return v and 1 or 0 end
	if type(Optim.Defaults[k]) == "number" then return tonumber(v) end
	return v
end

-- values from the settings file (AoUMeterSettings.txt, Settings.Opt)
function Optim.ApplyFile()
	local f = Settings and Settings.Opt
	if type(f) ~= "table" then return end
	for i = 1, #CFGKEYS do
		local k = CFGKEYS[i]
		local v = normalize(k, f[k])
		if v ~= nil then Optim.Cfg[k] = v end
	end
end

-- defaults -> settings file -> values saved from the chat (they override the file)
function Optim.LoadCfg()
	Optim.MyId = nil
	for k, v in pairs(Optim.Defaults) do Optim.Cfg[k] = v end
	Optim.Dirty = {}
	Optim.ApplyFile()
	local ok, sec = pcall(function() return userMods.GetGlobalConfigSection(common.GetAddonName()) end)
	if ok and sec then
		for i = 1, #CFGKEYS do
			local k = CFGKEYS[i]
			local v = normalize(k, sec["opt_" .. k])
			if v ~= nil then
				Optim.Cfg[k] = v
				Optim.Dirty[k] = true
			end
		end
	end
	Optim.Memo.key = nil
end

function Optim.SaveCfg()
	pcall(function()
		local name = common.GetAddonName()
		local sec = userMods.GetGlobalConfigSection(name) or {}
		for i = 1, #CFGKEYS do
			local k = CFGKEYS[i]
			if Optim.Dirty[k] then sec["opt_" .. k] = Optim.Cfg[k] end
		end
		userMods.SetGlobalConfigSection(name, sec)
	end)
end

-- drop everything saved from the chat, go back to the settings file values
function Optim.ResetCfg()
	for k, v in pairs(Optim.Defaults) do Optim.Cfg[k] = v end
	Optim.Dirty = {}
	Optim.ApplyFile()
	pcall(function()
		local name = common.GetAddonName()
		local sec = userMods.GetGlobalConfigSection(name) or {}
		for i = 1, #CFGKEYS do sec["opt_" .. CFGKEYS[i]] = nil end
		userMods.SetGlobalConfigSection(name, sec)
	end)
	Optim.Memo.key = nil
end

--------------------------------------------------------------------------------
-- Health of a unit (value, limit), nil if the API is not available
--------------------------------------------------------------------------------
Optim.Hp = { ok = 0, fail = 0, last = "" } -- diagnostics: how many target health reads worked

function Optim.GetHealth(id)
	if not id then
		Optim.Hp.fail = Optim.Hp.fail + 1
		Optim.Hp.last = "id=nil"
		return nil
	end
	local fn = Optim.HealthFn
	if fn == nil then
		fn = (object and object.GetHealthInfo) or (unit and unit.GetHealthInfo) or false
		Optim.HealthFn = fn
	end
	if not fn then
		Optim.Hp.fail = Optim.Hp.fail + 1
		Optim.Hp.last = "no health function"
		return nil
	end
	local ok, hi = pcall(fn, id)
	if not ok then
		Optim.Hp.fail = Optim.Hp.fail + 1
		Optim.Hp.last = "error " .. tostring(hi)
		return nil
	end
	if hi and hi.limit and hi.limit > 0 then
		Optim.Hp.ok = Optim.Hp.ok + 1
		return hi.value or 0, hi.limit, true
	end
	-- enemies: the game gives only the percentage (valuePercents, 0..100), no value / limit
	if hi and type(hi.valuePercents) == "number" then
		Optim.Hp.ok = Optim.Hp.ok + 1
		return hi.valuePercents, 100, false
	end
	Optim.Hp.fail = Optim.Hp.fail + 1
	Optim.Hp.last = hi and ("limit=" .. tostring(hi.limit)) or "nil result"
	return nil
end


-- current target of the player (used when the target of a hit cannot be read)
function Optim.GetTarget()
	local ok, t = pcall(function()
		if unit and unit.GetTarget then return unit.GetTarget(avatar.GetId()) end
		if avatar and avatar.GetTarget then return avatar.GetTarget() end
		return nil
	end)
	if ok then return t end
	return nil
end

--------------------------------------------------------------------------------
-- Data tracker: damage-weighted target health and Resolve for each hit
--------------------------------------------------------------------------------
Optim.Perf = { calls = 0, recalcs = 0 }   -- how many times the model was recalculated
Optim.HealTrace = {}      -- last heal events: { mine, heal, value, limit, real, pre, same }
Optim.HealStat = { n = 0, same = 0 }
Optim.LastEv = {}         -- last raw event parameters per mode (for /aou lastev)

function Optim.OnHit(combatant, mode, params, rage)
	if mode ~= enumMode.Dps and mode ~= enumMode.Hps then return end
	if Optim.Cfg.on ~= 1 then return end
	-- only the player's own events are analysed: for everybody else this hook would read the health of every target
	-- of every hit of the whole group, which is what made the game disable the addon for its performance
	local me = Optim.MyId
	if not me then
		if not avatar.IsExist() then return end
		me = avatar.GetId()
		Optim.MyId = me
	end
	if combatant.ID ~= me then return end
	-- the same event is processed twice (current and total fight): read the health only once
	local second = (Optim.CacheParams == params)
	Optim.LastEv[mode] = params
	local d = combatant.Data[mode]
	if not d then return end
	local amount = params.amount
	if not amount or amount <= 0 then return end

	local o = d.Opt
	if not o then
		o = { hw = 0, hs = 0, pw = 0, ps = 0, hpSamples = 0, poolSamples = 0, amount = 0 }
		d.Opt = o
	end

	o.amount = (o.amount or 0) + amount
	local tid
	if mode == enumMode.Dps then tid = params.target else tid = params.unitId end
	local v, lim, real
	if second then
		v, lim, real = Optim.CacheV, Optim.CacheLim, Optim.CacheReal
	else
		v, lim, real = Optim.GetHealth(tid)
		if not v and mode == enumMode.Dps then
			-- the target of the hit is gone or unreadable: use the current target of the player
			local tg = Optim.GetTarget()
			if tg and tg ~= tid then v, lim = Optim.GetHealth(tg) end
		end
		Optim.CacheParams, Optim.CacheV, Optim.CacheLim, Optim.CacheReal = params, v, lim, real
	end
	if v then
		local frac = v / lim
		if mode == enumMode.Hps then
			-- the heal event arrives AFTER the heal landed, but Ruthlessness works on the health BEFORE it:
			-- with a real limit the health before the heal is value - heal; with percent-only data it stays post-heal (flagged)
			if real then
				frac = clamp((v - amount) / lim, 0, 1)
				o.preSamples = (o.preSamples or 0) + 1
			end
			-- trace for diagnostics: do several heals of one unit share the same health read (processed in one batch)?
			if not second then
				local tr = Optim.HealTrace
				local last = tr[#tr]
				local same = (last ~= nil and last.tid == tid and last.value == v)
				Optim.HealStat.n = Optim.HealStat.n + 1
				if same then Optim.HealStat.same = Optim.HealStat.same + 1 end
				tr[#tr + 1] = { tid = tid, mine = (tid == me), heal = amount, value = v, limit = lim, real = real, pre = frac, same = same }
				if #tr > 14 then table.remove(tr, 1) end
			end
			if tid == me then
				o.sw = (o.sw or 0) + amount
				o.shs = (o.shs or 0) + amount * frac
			else
				o.aw = (o.aw or 0) + amount
				o.ahs = (o.ahs or 0) + amount * frac
			end
		end
		o.hw = o.hw + amount
		o.hs = o.hs + amount * frac
		o.hpSamples = (o.hpSamples or 0) + 1
		-- histogram of the damage / healing by target health (10 bins), used to remove the Ruthlessness bias
		local bin = math.floor(frac * 10) + 1
		if bin > 10 then bin = 10 end
		if bin < 1 then bin = 1 end
		if not o.hist then o.hist = {} end
		o.hist[bin] = (o.hist[bin] or 0) + amount
	end
	if rage then
		o.pw = o.pw + amount
		o.ps = o.ps + amount * rage
		o.poolSamples = (o.poolSamples or 0) + 1
	end
end

--------------------------------------------------------------------------------
-- Formulas
--------------------------------------------------------------------------------
-- m(x): m / ln(1 + m) = 1 + x   (Ruthlessness)
local MFC = {}
local function mf(x)
	if x <= 0 then return 0 end
	local k = math.floor(x * 1000 + 0.5)
	local v = MFC[k]
	if v ~= nil then return v end
	local g, lo, hi = 1 + k / 1000, 0, 1e6
	for i = 1, 60 do
		local m = (lo + hi) / 2
		if m / math.log(1 + m) < g then lo = m else hi = m end
	end
	MFC[k] = lo
	return lo
end


-- Luck: effective points f(s), 0.1% crit per point, cap 850
local function fcrit(s)
	if s <= 500 then return s end
	local r = 500 / s
	return math.min(850, 500 + (s - 500) * 0.7 * (r + 0.25 * r ^ 5 - 0.5 * r ^ 3))
end

local function masteryMult(s)
	if s >= 0 then return 1 + s / 1000 end
	return 1 / (1 + math.abs(s) / 1000)
end

local function lnF(M, R, U, L, pool, h, mm)
	local c = math.min(1, fcrit(L) / 1000)
	local m = masteryMult(M)
	local r = 1 + R / 1000 * pool * 0.015
	local u = 1 + mm(U) * (1 - h)
	return math.log(math.max(m, 1e-12)) + math.log(math.max(r, 1e-12))
		+ math.log(math.max(u, 1e-12)) + math.log(1 + c)
end

-- Whole-fight DD objective: give equal weight to the four target-HP quarters.
-- Ruthlessness contributes progressively as target HP falls; Mastery and Resolve
-- contribute throughout. Equal phase weighting prevents the final execute window
-- from dominating the recommendation merely because its hits are unusually large.
local HP_CURVE = { 0.875, 0.625, 0.375, 0.125 }
local function lnCurveF(M, R, U, L, pool, mm)
	local total = 0
	for i = 1, #HP_CURVE do
		total = total + lnF(M, R, U, L, pool, HP_CURVE[i], mm)
	end
	return total / #HP_CURVE
end

local function multA(M, R, U, L, pool, h)
	local m = mf(U / 1000)
	-- h is retained in the signature for compatibility with existing callers;
	-- recommendations and displayed multipliers use the full 100-to-0% curve.
	return math.exp(lnCurveF(M, R, U, L, pool, function() return m end))
end

-- Split Tp points between Mastery / Resolve / Ruthlessness (Luck is fixed).
-- The objective is the equal-weight geometric mean across four target HP phases,
-- not a snapshot at the current target HP.
local function optA(fx, Tp, pool, h)
	Tp = math.floor(Tp + 0.5)
	local memo = {}
	local function mm(u)
		local k = math.floor(u + 0.5)
		local v = memo[k]
		if v == nil then
			v = mf(k / 1000)
			memo[k] = v
		end
		return v
	end
	local function f(x, u)
		local r = Tp - x - u
		if r < 0 then return -1e18 end
		return lnCurveF(fx[1] + x, fx[2] + r, fx[3] + u, fx[4], pool, mm)
	end
	if Tp <= 0 then return 0, 0, 0, f(0, 0) end
	local s = math.max(1, math.ceil(Tp / 20))
	local best, bx, bu = -1e18, 0, 0
	local x = 0
	while x <= Tp do
		local u = 0
		while x + u <= Tp do
			local v = f(x, u)
			if v > best then best = v; bx = x; bu = u end
			u = u + s
		end
		x = x + s
	end
	while s > 1 do
		local n = math.max(1, math.ceil(s / 5))
		local cx, cu = bx, bu
		local x2 = math.max(0, cx - s)
		while x2 <= cx + s do
			local u2 = math.max(0, cu - s)
			while u2 <= cu + s do
				local v = f(x2, u2)
				if v > best then best = v; bx = x2; bu = u2 end
				u2 = u2 + n
			end
			x2 = x2 + n
		end
		s = n
	end
	return bx, Tp - bx - bu, bu, best
end

-- Will: seconds of control until immunity
local function willSec(W)
	if W <= 0 then return nil end
	local p = math.min(900, 1.6 * W / (1 + W ^ 1.05 / 1000)) / 1000
	local t = (p / 0.05) ^ 0.75
	local d = t / p - t
	if d <= 0 then return 1 end
	return math.ceil(100 / math.ceil(150 / d))
end

local wneedMemo = {}
local function wNeed(sec)
	if wneedMemo[sec] then return wneedMemo[sec] end
	local res = 3000
	for W = 1, 3000 do
		local s = willSec(W)
		if s and s <= sec then res = W break end
	end
	wneedMemo[sec] = res
	return res
end

local function share(B)
	local x = B / 1000
	return x / (x + 1.8)
end

-- survivability: health / (incoming - Bloodthirst return)
-- Resolve pool growth (formula from the data): pool += round(416.7 * damage / max health / c * k), k by pool, x0.9 per second.
-- The divisor c is not given; it is calibrated from the pool measured in the fight (it was ~2 for a dummy, ~1 for healing).
local function kpool(p)
	if p < 50 then return 0.35 elseif p < 60 then return 0.3 elseif p < 70 then return 0.18 elseif p < 80 then return 0.15 end
	return 0.1
end
local function poolSim(rate, c, T)
	local p, sum = 0, 0
	for i = 1, T do
		p = math.min(100, p + math.floor(416.7 * rate / c * kpool(p) + 0.5))
		sum = sum + p
		p = math.floor(p * 0.9)
	end
	return sum / T
end
local function calibrateC(rate, measured, T)
	local lo, hi = 0.05, 50
	for i = 1, 24 do
		local mid = math.sqrt(lo * hi)
		if poolSim(rate, mid, T) > measured then lo = mid else hi = mid end
	end
	return math.sqrt(lo * hi)
end

local function score(o, St, Bl)
	local hp = o.hp0 * (1 + St / 1000)
	if o.inc <= 0 then return hp end
	local sus = share(Bl) * o.out * o.rf * (1 - (o.phi or 0))
	local c = o.c or 0
	-- Caution: below 40% health the damage taken is multiplied by (1 - c); the sustain (lifesteal) is not
	local d1 = math.max(o.inc - sus, o.inc * 0.05)
	local d2 = math.max(o.inc * (1 - c) - sus, o.inc * (1 - c) * 0.05)
	return hp * (0.6 / d1 + 0.4 / d2)
end

-- split P points between Fortitude / Will / Bloodthirst; also returns the best survivability score
local function optD(fx, P, o)
	P = math.floor(P + 0.5)
	local addW = 0
	if o.pvp then addW = math.min(P, math.max(0, wNeed(o.tw) - fx[2])) end
	local rest = P - addW
	local step = math.max(1, math.ceil(rest / 100))
	local best, bs = -1, 0
	for s = 0, rest, step do
		local sc = score(o, fx[1] + s, fx[3] + rest - s)
		if sc > best then best = sc; bs = s end
	end
	for s = math.max(0, bs - step), math.min(rest, bs + step) do
		local sc = score(o, fx[1] + s, fx[3] + rest - s)
		if sc > best then best = sc; bs = s end
	end
	return bs, addW, rest - bs, best
end

-- joint split: the free (base) points F can go to ANY stat, Ea / Ed are the equipment+effects pools of each group.
-- Maximizes ln(damage multiplier) + bal * ln(survivability). Returns {M,R,U} {S,W,B} increments and the points given to offense.
local function optJ(fxA, Ea, fxD, Ed, F, pool, h, o, bal)
	F = math.floor(F + 0.5)
	local function ev(fa)
		local a1, a2, a3, abest = optA(fxA, Ea + fa, pool, h)
		local d1, d2, d3, dbest = optD(fxD, Ed + F - fa, o)
		local obj = abest
		if bal > 0 then obj = obj + bal * math.log(math.max(dbest, 1e-9)) end
		return obj, { a1, a2, a3 }, { d1, d2, d3 }
	end
	local bestObj, bestA, bestD, bestFa = nil, nil, nil, 0
	local function try(fa)
		if fa < 0 or fa > F then return end
		local obj, A, D = ev(fa)
		if bestObj == nil or obj > bestObj then bestObj, bestA, bestD, bestFa = obj, A, D, fa end
	end
	-- three stages (coarse, medium, exact) instead of one fine scan: about 40 evaluations instead of 120
	local step = math.max(1, math.ceil(F / 8))
	local fa = 0
	while fa <= F do
		try(fa)
		fa = fa + step
	end
	try(F)
	while step > 1 do
		local n = math.max(1, math.ceil(step / 4))
		local c = bestFa
		for f2 = c - step, c + step, n do try(f2) end
		step = n
	end
	return bestA, bestD, bestFa
end


--------------------------------------------------------------------------------
-- Character stats read by the addon (best effort: the API names are not verified for 7.0)
--------------------------------------------------------------------------------
local function getStatList()
	local list = nil
	pcall(function()
		if avatar and avatar.GetInnateStats then
			list = avatar.GetInnateStats()
		elseif unit and unit.GetInnateStats then
			list = unit.GetInnateStats(avatar.GetId())
		end
	end)
	return list
end

local function toText(v)
	local tv = type(v)
	if tv == "string" then return v end
	if tv == "number" or tv == "boolean" then return tostring(v) end
	local ok, r = pcall(function()
		if common.IsWString and common.IsWString(v) then return userMods.FromWString(v) end
		return nil
	end)
	if ok then return r end
	return nil
end

-- avatar.GetInnateStats() entries (keys start at 0): { sysName = "ENUM_InnateStats_Plain", base, talents, equipment,
-- buffs, enchants, fairyBonus, effective, ... }.  base = free points placed by the player, talents = development milestones;
-- fixed = talents + fairy + buffs (effects) + enchants, equipment = what insignias can switch inside a group
local SYSNAMES = { Plain = "M", Rage = "R", Finisher = "U", CritChance = "L", Vitality = "S", Will = "W", Lifesteal = "B", Endurance = "C" }

function Optim.ReadStats()
	local list = getStatList()
	if not list then return nil end
	local out, found = {}, 0
	pcall(function()
		for _, e in pairs(list) do
			if type(e) == "table" and type(e.sysName) == "string" then
				local nm = (string.gsub(e.sysName, "^ENUM_InnateStats_", ""))
				local code = SYSNAMES[nm]
				local eff = tonumber(e.effective)
				if code and eff then
					out[code] = {
						total = eff,
						base = tonumber(e.base) or 0,
						fixed = (tonumber(e.talents) or 0) + (tonumber(e.fairyBonus) or 0) + (tonumber(e.buffs) or 0) + (tonumber(e.enchants) or 0),
					}
					found = found + 1
				end
			end
		end
	end)
	if found < 3 then return nil end
	return out
end

local function sayLong(txt)
	while #txt > 110 do
		say(string.sub(txt, 1, 110))
		txt = string.sub(txt, 111)
	end
	say(txt)
end

local function fmtVal(v)
	local t = toText(v)
	if t then return t end
	if type(v) == "table" then return "<table>" end
	return "<" .. type(v) .. ">"
end

local function fmtTable(tbl, maxFields)
	local parts, n = {}, 0
	for k, v in pairs(tbl) do
		n = n + 1
		if n <= maxFields then parts[#parts + 1] = tostring(k) .. "=" .. fmtVal(v) end
	end
	if n > maxFields then parts[#parts + 1] = "...(" .. n .. ")" end
	return "{" .. table.concat(parts, " ") .. "}"
end

local function summarize(label, ok, r)
	if not ok then
		say(label .. ": error")
		return
	end
	if r == nil then
		say(label .. ": nil")
		return
	end
	if type(r) ~= "table" then
		sayLong(label .. " = " .. fmtVal(r))
		return
	end
	local n = 0
	for _ in pairs(r) do n = n + 1 end
	sayLong(label .. ": table(" .. n .. ") " .. fmtTable(r, 8))
	local shown = 0
	for k, v in pairs(r) do
		if type(v) == "table" and shown < 12 then
			shown = shown + 1
			sayLong("  [" .. tostring(k) .. "] " .. fmtTable(v, 10))
		end
	end
end

-- /aou scan [word]: list the API functions about stats / points and show what their getters return
function Optim.Scan(word)
	local kws = { "stat", "innate", "point", "free", "alloc", "charact", "bonus" }
	if word then kws = { string.lower(word) } end
	local function match(name)
		local ln = string.lower(name)
		for i = 1, #kws do
			if string.find(ln, kws[i], 1, true) then return true end
		end
		return false
	end
	local spaces = { { "avatar", avatar }, { "unit", unit }, { "object", object } }
	local calls = 0
	for i = 1, #spaces do
		local label, tbl = spaces[i][1], spaces[i][2]
		local names = {}
		pcall(function()
			for k, v in pairs(tbl) do
				if type(k) == "string" and match(k) then names[#names + 1] = k end
			end
		end)
		table.sort(names)
		sayLong(label .. " (" .. #names .. "): " .. table.concat(names, ", "))
		if label ~= "object" then
			for j = 1, #names do
				local nm = names[j]
				if string.sub(nm, 1, 3) == "Get" and calls < 30 then
					calls = calls + 1
					local fn = tbl[nm]
					local ok, r = pcall(fn)
					if not ok or r == nil then ok, r = pcall(fn, avatar.GetId()) end
					summarize(label .. "." .. nm, ok, r)
				end
			end
		end
	end
	say("scan done")
end

-- /aou probe: the API tables cannot be listed, so try likely function names one by one
function Optim.Probe()
	say("types: avatar=" .. type(avatar) .. " unit=" .. type(unit) .. " object=" .. type(object) .. " common=" .. type(common))
	local spaces = { { "avatar", avatar }, { "unit", unit } }
	for i = 1, #spaces do
		local label, tbl = spaces[i][1], spaces[i][2]
		local ok, cnt = pcall(function()
			local n = 0
			for k in pairs(tbl) do n = n + 1 end
			return n
		end)
		say(label .. " pairs: " .. (ok and tostring(cnt) or ("error " .. tostring(cnt))))
	end

	local bases = { "InnateStats", "InnateStat", "InnateStatsInfo", "InnateStatInfo", "InnateStatsPoints", "InnateStatPoints",
		"FreeInnateStatPoints", "Stats", "StatsInfo", "StatInfo", "StatPoints", "FreeStatPoints", "UnspentStatPoints",
		"AvailableStatPoints", "StatsPoints", "BonusStats", "SpecStats", "SpecialStats", "TotalStats", "CharacterStats",
		"Characteristics", "Properties", "Params", "FreePoints", "Points", "StatsDistribution", "StatsAllocation",
		"CurrentStats", "InsigniaStats", "StatBonus", "StatsBonus" }
	local calls = 0
	for i = 1, #spaces do
		local label, tbl = spaces[i][1], spaces[i][2]
		local found = {}
		for j = 1, #bases do
			local name = "Get" .. bases[j]
			local ok, fn = pcall(function() return tbl[name] end)
			if ok and fn ~= nil then found[#found + 1] = name end
		end
		sayLong(label .. " found (" .. #found .. "): " .. table.concat(found, ", "))
		for j = 1, #found do
			if calls < 24 then
				calls = calls + 1
				local fn = tbl[found[j]]
				local ok, r = pcall(fn)
				if not ok or r == nil then ok, r = pcall(fn, avatar.GetId()) end
				summarize(label .. "." .. found[j], ok, r)
			end
		end
	end

	-- health / level / class / target functions
	local hn = { "GetHealthInfo", "GetHealth", "GetHealthPercentage", "GetHealthPercent", "GetMaxHealth", "GetHP",
		"GetHealthLimit", "GetLevel", "GetClass", "GetTarget", "GetPrimaryTarget", "GetCurrentLevel" }
	local spaces2 = { { "avatar", avatar }, { "unit", unit }, { "object", object } }
	for i = 1, #spaces2 do
		local label, tbl = spaces2[i][1], spaces2[i][2]
		local found = {}
		for j = 1, #hn do
			local ok, fn = pcall(function() return tbl[hn[j]] end)
			if ok and fn ~= nil then found[#found + 1] = hn[j] end
		end
		sayLong(label .. " health/level (" .. #found .. "): " .. table.concat(found, ", "))
		for j = 1, #found do
			if calls < 60 then
				calls = calls + 1
				local fn = tbl[found[j]]
				local ok, r = pcall(fn, avatar.GetId())
				if not ok or r == nil then ok, r = pcall(fn) end
				summarize(label .. "." .. found[j], ok, r)
			end
		end
	end

	-- global tables that may hold stat functions
	local gnames = { "stats", "stat", "innateStats", "avatarStats", "charStats", "statistics", "characteristics" }
	local gfound = {}
	for i = 1, #gnames do
		local ok, v = pcall(function()
			if _G then return _G[gnames[i]] end
			return getfenv(0)[gnames[i]]
		end)
		if ok and v ~= nil then gfound[#gfound + 1] = gnames[i] .. "=" .. type(v) end
	end
	say("globals: " .. table.concat(gfound, ", "))
	say("probe done")
end

--------------------------------------------------------------------------------
-- Mitigation of damage / healing measured by the meter (resists, rune absorption, blocks, wounds)
--------------------------------------------------------------------------------
-- 1 armor (physical), 2 elements, 3 nature, 4 light
local SCHOOLS = { PHYSICAL = 1, FIRE = 2, COLD = 2, LIGHTNING = 2, POISON = 3, DISEASE = 3, ACID = 3, HOLY = 4, SHADOW = 4, ASTRAL = 4 }

local function detailAmount(list, key)
	local d = list and list[key]
	if d and type(d.Amount) == "number" then return d.Amount end
	return 0
end

function Optim.Mitigation(c, mode)
	local data = c.Data[mode]
	if not data or not data.SpellsList then return nil end
	local r = { net = 0, resist = 0, absorb = 0, block = 0, wound = 0, over = 0, sch = {} }
	for i = 1, 4 do r.sch[i] = { gross = 0, resist = 0, rune = 0 } end
	local isHeal = (mode == enumMode.Hps or mode == enumMode.IHps)
	for _, sp in pairs(data.SpellsList) do
		local rl = sp.ResistDetailsList
		local net = sp.Amount or 0
		r.net = r.net + net
		if isHeal then
			r.wound = r.wound + detailAmount(rl, enumHealResist.Absorbed) + detailAmount(rl, enumHealResist.Resisted)
				+ detailAmount(rl, enumHealResist.RuneResisted)
			r.over = r.over + detailAmount(rl, enumHealResist.Overload)
		else
			local res = detailAmount(rl, enumHitBlock.Resist)
			local rune = detailAmount(rl, enumHitBlock.RunesAbsorb)
			local ab = detailAmount(rl, enumHitBlock.Absorb) + detailAmount(rl, enumHitBlock.Mount)
			local bl = detailAmount(rl, enumHitBlock.Block) + detailAmount(rl, enumHitBlock.Parry) + detailAmount(rl, enumHitBlock.Barrier)
			r.resist = r.resist + res
			r.absorb = r.absorb + ab + rune
			r.block = r.block + bl
			local el = sp.Element
			if type(el) == "string" then
				local nm = (string.gsub(el, "^ENUM_SubElement_", ""))
				local idx = SCHOOLS[nm]
				if idx then
					local sc = r.sch[idx]
					sc.gross = sc.gross + net + res + rune + ab + bl
					sc.resist = sc.resist + res
					sc.rune = sc.rune + rune
				end
			end
		end
	end
	return r
end

-- share of the healing taken by wounds (Fury) / resists, measured on the heals received by the player
function Optim.HealAbsorbFrac(c)
	local m = Optim.Mitigation(c, enumMode.IHps)
	if not m then return 0 end
	local tot = m.net + m.wound
	if tot <= 0 then return 0 end
	return clamp(m.wound / tot, 0, 0.95)
end

-- info rows (not cached): what the targets / the player mitigate
function Optim.MitLines(c, activeMode)
	local rows = {}
	local function addR(n, a, b, d) rows[#rows + 1] = { n, a or "", b or "", d or "" } end
	local function pct(x, tot)
		if tot > 0 then return F1(x / tot * 100) .. "%" end
		return "-"
	end
	if activeMode == enumMode.Dps then
		local m = Optim.Mitigation(c, enumMode.Dps)
		if m then
			local gross = m.net + m.resist + m.absorb + m.block
			if gross > 0 then
				addR("OptMitHdrD", "@OptColRes", "@OptColAbs", "@OptColBlk")
				addR("OptMitVal", pct(m.resist, gross), pct(m.absorb, gross), pct(m.block, gross))
			end
		end
	elseif activeMode == enumMode.Hps or activeMode == enumMode.IHps then
		if activeMode == enumMode.Hps then
			local ho = c.Data[enumMode.Hps] and c.Data[enumMode.Hps].Opt
			if ho then
				local aw, sw = ho.aw or 0, ho.sw or 0
				if aw + sw > 0 then
					addR("OptHealSplit", (aw > 0 and F1(ho.ahs / aw * 100) or "-") .. "%", (sw > 0 and F1(ho.shs / sw * 100) or "-") .. "%", F1(sw / (aw + sw) * 100) .. "%")
				end
			end
		end
		local m = Optim.Mitigation(c, activeMode)
		if m then
			local gross = m.net + m.wound + m.over
			if gross > 0 then
				addR("OptMitHdrH", "@OptColWound", "@OptColOver", "")
				addR("OptMitVal", pct(m.wound, gross), pct(m.over, gross), "")
			end
		end
	elseif activeMode == enumMode.Def then
		local m = Optim.Mitigation(c, enumMode.Def)
		if m then
			local gross = m.net + m.resist + m.absorb + m.block
			if gross > 0 then
				addR("OptSchHdr", "@OptColShare", "@OptColRes", "@OptColRune")
				local names = { "OptSchA", "OptSchE", "OptSchN", "OptSchL" }
				for i = 1, 4 do
					local sc = m.sch[i]
					addR(names[i], pct(sc.gross, gross), pct(sc.resist, sc.gross), pct(sc.rune, sc.gross))
				end
			end
		end
	end
	return rows
end

--------------------------------------------------------------------------------
-- Is something configured?
--------------------------------------------------------------------------------
function Optim.OffConfigured()
	local c = Optim.Cfg
	return (c.fM + c.fR + c.fU + c.eM + c.eR + c.eU) > 0
end
function Optim.DefConfigured()
	local c = Optim.Cfg
	return (c.fS + c.fW + c.fB + c.eS + c.eW + c.eB) > 0
end

--------------------------------------------------------------------------------
-- Build the lines shown in the details panel for the given combatant (the avatar)
-- Each line: { text key, now, optimal, delta }
-- activeMode: the mode shown in the window (Dps = damage, Hps = healing, else the role)
--------------------------------------------------------------------------------
function Optim.BuildLines(c, fightTime, activeMode)
	local cfg = Optim.Cfg
	if cfg.on ~= 1 then return nil end
	local dd, hl, df = c.Data[enumMode.Dps], c.Data[enumMode.Hps], c.Data[enumMode.Def]
	if not dd or not hl then return nil end

	local lines = {}
	local function add(n, a, b, d) lines[#lines + 1] = { n, a or "", b or "", d or "" } end

	local heal
	if activeMode == enumMode.Hps then
		heal = true
	elseif activeMode == enumMode.Dps then
		heal = false
	else
		heal = (cfg.role == "heal") or (cfg.role == "auto" and hl.Amount > dd.Amount)
	end
	local main = heal and hl or dd
	local o = main.Opt

	-- character stats: read by the addon, or typed by hand
	local tot = nil
	if cfg.auto == 1 then tot = Optim.ReadStats() end
	add(heal and "OptModeH" or "OptModeD", tot and "auto" or "manual")

	if not o or o.pw <= 0 then
		add("OptNoData")
		add("OptHelpRow")
		return lines
	end

	local pool = o.ps / o.pw
	local hKnown = o.hw > 0
	local h = hKnown and (o.hs / o.hw) or (cfg.thp / 100)
	add("OptPool", F1(pool))
	add("OptTHP", F1(h * 100) .. (hKnown and ((heal and (o.preSamples or 0) == 0) and " ~" or "") or " ?"))

	-- f = fixed (milestones, fairy bonus, effects, enchants), b = free points (base), e = equipment (insignias switch it inside its group).
	-- Auto: everything comes from avatar.GetInnateStats (b = base, f = talents + fairy, e = effective - f - b)
	local function pick(t, f, b, e)
		if t then
			local total = math.floor(t.total)
			local f2 = math.min(math.floor(t.fixed + 0.5), total)
			local b2 = math.min(math.floor(t.base + 0.5), total - f2)
			return f2, b2, total - f2 - b2
		end
		return f, b, e
	end
	local fM, bM, eM = pick(tot and tot.M, cfg.fM, cfg.bM, cfg.eM)
	local fR, bR, eR = pick(tot and tot.R, cfg.fR, cfg.bR, cfg.eR)
	local fU, bU, eU = pick(tot and tot.U, cfg.fU, cfg.bU, cfg.eU)
	local L = cfg.L
	if tot and tot.L then L = math.floor(tot.L.total) end
	local fS, bS, eS = pick(tot and tot.S, cfg.fS, cfg.bS, cfg.eS)
	local fW, bW, eW = pick(tot and tot.W, cfg.fW, cfg.bW, cfg.eW)
	local fB, bB, eB = pick(tot and tot.B, cfg.fB, cfg.bB, cfg.eB)
	local nowA = { fM + bM + eM, fR + bR + eR, fU + bU + eU }
	local nowD = { fS + bS + eS, fW + bW + eW, fB + bB + eB }
	-- target health without the Ruthlessness bias: weights n / (1 + m0 * (1 - h)) (the measured damage already contains the
	-- bonus, and also the Caution of the targets, so Caution needs no extra input here)
	if o.hist and hKnown then
		local m0 = mf(nowA[3] / 1000)
		local num, den = 0, 0
		for k = 1, 10 do
			local n = o.hist[k] or 0
			if n > 0 then
				local hk = (k - 0.5) / 10
				local w = n / (1 + m0 * (1 - hk))
				num = num + w * hk
				den = den + w
			end
		end
		if den > 0 then
			h = num / den
			lines[3][2] = F1(h * 100)
		end
	end
	-- own Caution: read from the game or typed
	local cau = cfg.caut
	if cau <= 0 and tot and tot.C then cau = math.floor(tot.C.total) end
	local cc = math.min(cau, 350) / 1000
	local offOK = (nowA[1] + nowA[2] + nowA[3]) > 0
	local defOK = (nowD[1] + nowD[2] + nowD[3]) > 0

	if not offOK and not defOK then
		add("OptSet")
		return lines
	end

	if fightTime <= 0 then fightTime = 1 end
	local out = main.Amount / fightTime
	local inc = (df and df.Amount or 0) / fightTime
	local hv, hlim, hreal = Optim.GetHealth(avatar.GetId())
	local hpMax = (hreal and hlim) or cfg.hp

	local phi = Optim.HealAbsorbFrac(c)   -- wounds / resists take this share of the healing (Bloodthirst returns less)

	-- cache: recompute only when the inputs change noticeably
	local function lg(x) return math.floor(math.log(x + 1) * 8) end
	local statKey = table.concat({ cfg.mode, cfg.flag, cfg.tw, cfg.bal, cfg.free, cfg.eq, fM, fR, fU, L, bM, bR, bU, eM, eR, eU,
		fS, fW, fB, bS, bW, bB, eS, eW, eB, heal and 1 or 0, cau }, "|")
	-- the dynamic inputs (pool, target health, damage per second ...) change every second: coarse buckets, and a recalculation
	-- at most once per 4 calls unless the stats themselves changed
	local dynKey = table.concat({ math.floor(pool / 3), math.floor(h * 20), lg(out), lg(inc), lg(hpMax), math.floor(phi * 10) }, "|")
	local memo = Optim.Memo
	Optim.Perf.calls = Optim.Perf.calls + 1
	Optim.SinceCalc = (Optim.SinceCalc or 0) + 1
	if memo.key == statKey and memo.lines and (memo.dynKey == dynKey or Optim.SinceCalc < 4) then
		local cached = memo.lines
		local res = { lines[1], lines[2], lines[3] }
		for i = 1, #cached do res[#res + 1] = cached[i] end
		local extra = Optim.MitLines(c, activeMode)
		for i = 1, #extra do res[#res + 1] = extra[i] end
		return res
	end
	Optim.SinceCalc = 0
	Optim.Perf.recalcs = Optim.Perf.recalcs + 1

	local baseAt, baseDt = bM + bR + bU, bS + bW + bB   -- how the free points are placed now (0 right after a reset)
	local F = (cfg.free > 0) and cfg.free or (baseAt + baseDt)   -- free points to place (can go to ANY stat)
	local Ea, Ed = eM + eR + eU, eS + eW + eB      -- equipment + effects pools of each group
	local haveDef = defOK and hpMax > 0
	local o2 = nil
	if haveDef then
		o2 = { hp0 = hpMax / (1 + nowD[1] / 1000), out = out, inc = inc, rf = heal and (1 / 3) or 1,
			pvp = (cfg.mode == "pvp"), tw = clamp(math.floor(cfg.tw + 0.5), 1, 10), phi = phi, c = cc }
	end

	local optA3, optD3, faOpt = nowA, nowD, baseAt
	if cfg.flag == 1 then
		-- eq = 1: bonuses of equipment / effects can move inside their group; eq = 0: only the free points move
		local fxA, fxD, poolA, poolD
		if cfg.eq == 1 then
			fxA, fxD, poolA, poolD = { fM + 0, fR + 0, fU + 0, L }, { fS + 0, fW + 0, fB + 0 }, Ea, Ed
		else
			fxA, fxD, poolA, poolD = { fM + eM, fR + eR, fU + eU, L }, { fS + eS, fW + eW, fB + eB }, 0, 0
		end
		if offOK and haveDef then
			local A, D, fa = optJ(fxA, poolA, fxD, poolD, F, pool, h, o2, cfg.bal)
			optA3 = { fxA[1] + A[1], fxA[2] + A[2], fxA[3] + A[3] }
			optD3 = { fxD[1] + D[1], fxD[2] + D[2], fxD[3] + D[3] }
			faOpt = fa
		elseif offOK then
			local pa = poolA + (defOK and baseAt or F)
			local a1, b1, u1 = optA(fxA, pa, pool, h)
			optA3 = { fxA[1] + a1, fxA[2] + b1, fxA[3] + u1 }
			faOpt = baseAt
		end
	end

	local tail = {}
	local function addT(n, a, b, d) tail[#tail + 1] = { n, a or "", b or "", d or "" } end

	if offOK then
		addT("OptM", I(nowA[1]), I(optA3[1]), S(optA3[1] - nowA[1]))
		addT("OptR", I(nowA[2]), I(optA3[2]), S(optA3[2] - nowA[2]))
		addT("OptU", I(nowA[3]), I(optA3[3]), S(optA3[3] - nowA[3]))
		addT("OptL", I(L), I(L), "0")
		local m0 = multA(nowA[1], nowA[2], nowA[3], L, pool, h)
		local m1 = multA(optA3[1], optA3[2], optA3[3], L, pool, h)
		addT("OptMult", "x" .. F2(m0), "x" .. F2(m1), string.format("%+.1f", (m1 / m0 - 1) * 100) .. "%")
		-- Marginal gains are measured against the same whole-fight HP curve, not one target-HP snapshot.
		local function gain(M, R, U) return (multA(M, R, U, L, pool, h) / m0 - 1) * 100 end
		addT("OptMarg", string.format("M%+.1f", gain(nowA[1] + 50, nowA[2], nowA[3])),
			string.format("R%+.1f", gain(nowA[1], nowA[2] + 50, nowA[3])), string.format("B%+.1f", gain(nowA[1], nowA[2], nowA[3] + 50)))
		-- feedback: the new multiplier changes the damage (healing), therefore the pool; calibrate c from the measured pool
		local gi = main.GlobalInfoList and main.GlobalInfoList[enumGlobalInfo.Determination]
		local poolc = (gi and tonumber(gi.Avg)) or 0
		if hpMax > 0 and poolc > 0 and out > 0 then
			local okp, cfit, pnew = pcall(function()
				local T = clamp(math.floor(fightTime), 10, 120)
				local rate = out / hpMax
				local c2 = calibrateC(rate, poolc, T)
				return c2, poolSim(rate * (m1 / m0), c2, T)
			end)
			if okp and cfit and pnew then
				local pAdj = clamp(pool + (pnew - poolc), 0, 100)
				local m1c = multA(optA3[1], optA3[2], optA3[3], L, pAdj, h)
				addT("OptPoolFb", F1(poolc), F1(pnew), "c=" .. F2(cfit))
				addT("OptMultFb", "x" .. F2(m0), "x" .. F2(m1c), string.format("%+.1f", (m1c / m0 - 1) * 100) .. "%")
			end
		end
	end

	if F > 0 and offOK and haveDef then
		addT("OptFree", I(baseAt) .. "/" .. I(baseDt), I(faOpt) .. "/" .. I(F - faOpt), S(faOpt - baseAt))
	end

	if defOK then
		if haveDef then
			addT("OptS", I(nowD[1]), I(optD3[1]), S(optD3[1] - nowD[1]))
			addT("OptW", I(nowD[2]), I(optD3[2]), S(optD3[2] - nowD[2]))
			addT("OptB", I(nowD[3]), I(optD3[3]), S(optD3[3] - nowD[3]))
			addT("OptHP", I(o2.hp0 * (1 + nowD[1] / 1000)), I(o2.hp0 * (1 + optD3[1] / 1000)), "")
			local sN, sO = score(o2, nowD[1], nowD[3]), score(o2, optD3[1], optD3[3])
			addT("OptTTL", "x1.00", "x" .. F2(sN > 0 and sO / sN or 1), "")
			if phi > 0.005 then addT("OptPhi", F1(phi * 100) .. "%") end
			if cau > 0 then addT("OptCaut", I(cau), "x" .. F2(0.6 + 0.4 / (1 - cc)), "") end
		else
			addT("OptHpNeed")
		end
	end

	Optim.Memo.key = statKey
	Optim.Memo.dynKey = dynKey
	Optim.Memo.lines = tail
	for i = 1, #tail do lines[#lines + 1] = tail[i] end
	local extra = Optim.MitLines(c, activeMode)
	for i = 1, #extra do lines[#lines + 1] = extra[i] end
	return lines
end

--------------------------------------------------------------------------------
-- Test records: /aou mark <label>, /aou rec list|clear|export [N]
-- Records remain in the game's addon config. Export is emitted as numbered chat chunks;
-- the companion converter reconstructs a CSV file from a copied chat log.
local RECCOLS = "n|label|mode|sec|dmg|dps|hits|crits|pool|poolc|thp|heal|hps|M|R|U|L|S|W|B|bM|bR|bU|bS|bW|bB|hp|inc|hpSamples|poolSamples|outResist|outAbsorb|outBlock|inResist|inAbsorb|inBlock|inPhysical|inElements|inNature|inLight|healWound|healOver|healPool|healTHP|healSamples|healPoolSamples|inHeal|oHealWound|oHealOver|topDmg|topHeal"

function Optim.MakeRecord(label)
        Optim.NumConversionFailed = 0
        Optim.NumLastBadValue = nil
	local gui = DPSMeterGUI
	if not gui or not gui.GetActiveFight then return nil end
	local fight = gui:GetActiveFight()
	if not fight then return nil end
	local me = avatar.GetId()
	local c = nil
	for _, cb in pairs(fight.CombatantsList) do
		if cb.ID == me then c = cb end
	end
	if not c then return nil end

	local sec = N(fight.Timer:GetElapsedTime())
	if sec <= 0 then sec = 1 end
	local dd, hl, df = c.Data[enumMode.Dps], c.Data[enumMode.Hps], c.Data[enumMode.Def]
	local hits, crits = 0, 0
	if dd and dd.SpellsList then
		for _, sp in pairs(dd.SpellsList) do
			hits = hits + N(sp.Hits or sp.Count or 0)
			local cr = sp.DetailsList and sp.DetailsList[enumHit.Critical]
			if cr and cr.Count then crits = crits + N(cr.Count) end
		end
	end
	local o = dd and dd.Opt
	local ho = hl and hl.Opt
	local pool = (o and N(o.pw) > 0) and (N(o.ps) / N(o.pw)) or 0
	local thp = (o and N(o.hw) > 0) and (N(o.hs) / N(o.hw) * 100) or -1
	local healPool = (ho and N(ho.pw) > 0) and (N(ho.ps) / N(ho.pw)) or 0
	local healThp = (ho and N(ho.hw) > 0) and (N(ho.hs) / N(ho.hw) * 100) or -1
	local poolc = 0
	if dd and dd.GlobalInfoList and dd.GlobalInfoList[enumGlobalInfo.Determination] then
		poolc = N(dd.GlobalInfoList[enumGlobalInfo.Determination].Avg or 0)
	end
	local tot = Optim.ReadStats()
	local function tv(k) return N((tot and tot[k]) and tot[k].total or 0) end
	local function bv(k) return N((tot and tot[k]) and tot[k].base or 0) end
	local hv, hlim, hreal = Optim.GetHealth(me)
	local hpMax = N((hreal and hlim) or Optim.Cfg.hp)
	local dmg = N(dd and dd.Amount or 0)
	local heal = N(hl and hl.Amount or 0)
	local inc = N(df and df.Amount or 0)
	local outMit = Optim.Mitigation(c, enumMode.Dps) or {}
	local inMit = Optim.Mitigation(c, enumMode.Def) or {}
	local healMit = Optim.Mitigation(c, enumMode.IHps) or {}
	local sch = inMit.sch or {}
	local function school(i, k) return N(sch[i] and sch[i][k] or 0) end
	local lab = (string.gsub(label, "[|%s]", "_"))
	local outHealMit = Optim.Mitigation(c, enumMode.Hps) or {}
	local ihd = c.Data[enumMode.IHps]
	local inHeal = N(ihd and ihd.Amount or 0)
	-- top abilities: id:hits:crits:amount (damage) and id:count:amount (healing)
	local function top(mode, withCrit, count)
		local data = c.Data[mode]
		local list = {}
		if data and data.SpellsList then
			for _, sp in pairs(data.SpellsList) do
				local cr = sp.DetailsList and sp.DetailsList[enumHit.Critical]
				list[#list + 1] = { id = N(sp.ID or 0), hits = N(sp.Hits or sp.Count or 0), crits = N((cr and cr.Count) or 0), amount = N(sp.Amount or 0) }
			end
		end
		table.sort(list, function(x, y) return x.amount > y.amount end)
		local parts = {}
		for i = 1, math.min(count, #list) do
			local e = list[i]
			if withCrit then
				parts[#parts + 1] = I(e.id) .. ":" .. I(e.hits) .. ":" .. I(e.crits) .. ":" .. I(e.amount)
			else
				parts[#parts + 1] = I(e.id) .. ":" .. I(e.hits) .. ":" .. I(e.amount)
			end
		end
		if #parts == 0 then return "-" end
		return table.concat(parts, ";")
	end
	return {
		lab, Optim.Cfg.mode, F1(sec), I(dmg), I(dmg / sec), I(hits), I(crits), F1(pool), F1(poolc), F1(thp),
		I(heal), I(heal / sec), math.floor(tv("M")), math.floor(tv("R")), math.floor(tv("U")), math.floor(tv("L")), math.floor(tv("S")), math.floor(tv("W")), math.floor(tv("B")),
		math.floor(bv("M")), math.floor(bv("R")), math.floor(bv("U")), math.floor(bv("S")), math.floor(bv("W")), math.floor(bv("B")), I(hpMax), I(inc / sec),
		I(o and o.hpSamples or 0), I(o and o.poolSamples or 0),
		I(outMit.resist or 0), I(outMit.absorb or 0), I(outMit.block or 0),
		I(inMit.resist or 0), I(inMit.absorb or 0), I(inMit.block or 0),
		I(school(1, "gross")), I(school(2, "gross")), I(school(3, "gross")), I(school(4, "gross")),
		I(healMit.wound or 0), I(healMit.over or 0),
		F1(healPool), F1(healThp), I(ho and ho.hpSamples or 0), I(ho and ho.poolSamples or 0),
		I(inHeal), I(outHealMit.wound or 0), I(outHealMit.over or 0), top(enumMode.Dps, true, 6), top(enumMode.Hps, false, 4),
	}
end

-- All records live in memory (Optim.RecStore) and are written to the config as a whole every time, because reading the
-- config section back can return an older copy and a read-modify-write of the counter then overwrites earlier records.
Optim.RecStore = nil

-- Record storage: persist rows and explicitly blank removed keys.
Optim.RecStore = nil

local function recLoad()
    if Optim.RecStore then return Optim.RecStore end

    local st = {}
    pcall(function()
        local sec = userMods.GetGlobalConfigSection(common.GetAddonName())
        if type(sec) == "table" then
            local total = tonumber(sec.aou_rec_count) or 0
            total = math.max(0, math.min(5000, math.floor(total)))

            for i = 1, total do
                local value = sec["aou_rec_" .. i]
                if value ~= nil and tostring(value) ~= "" then
                    st[#st + 1] = tostring(value)
                end
            end
        end
    end)

    Optim.RecStore = st
    return st
end

local function recWrite(st)
    if type(st) ~= "table" then return false, false end

    local name = common.GetAddonName()
    local ok = pcall(function()
        local sec = userMods.GetGlobalConfigSection(name)
        if type(sec) ~= "table" then sec = {} end

        local old = tonumber(sec.aou_rec_count) or 0
        old = math.max(0, math.min(5000, math.floor(old)))

        -- Empty strings explicitly overwrite old records.
        local limit = math.max(old, #st)
        for i = 1, limit do
            if st[i] ~= nil then
                sec["aou_rec_" .. i] = tostring(st[i])
            else
                sec["aou_rec_" .. i] = ""
            end
        end

        sec.aou_rec_count = #st
        userMods.SetGlobalConfigSection(name, sec)
    end)

    local verified = false
    if ok then
        pcall(function()
            local sec = userMods.GetGlobalConfigSection(name)
            if type(sec) == "table"
                and tonumber(sec.aou_rec_count) == #st then

                verified = true
                for i = 1, #st do
                    if tostring(sec["aou_rec_" .. i] or "") ~= tostring(st[i]) then
                        verified = false
                        break
                    end
                end
            end
        end)
    end

    if ok then Optim.RecStore = st end
    return ok, verified
end

function Optim.SaveRecord(fields)
	local st = recLoad()
	local n = #st + 1
	st[n] = n .. "|" .. table.concat(fields, "|")
	local ok, verified = recWrite(st)
	return ok, n, verified
end


function Optim.RecList(count)
	local st = recLoad()
	say("records: " .. #st .. "   columns: " .. RECCOLS)
	local from = math.max(1, #st - count + 1)
	for i = from, #st do
		if st[i] then sayLong(st[i]) end
	end
end


-- Export format: AOUCSV|type|part|parts|payload. Keep each chat line below 110 chars.
local function exportChunks(kind, text)
	local chunkSize = 62
	local total = math.max(1, math.ceil(#text / chunkSize))
	for part = 1, total do
		local chunk = string.sub(text, (part - 1) * chunkSize + 1, part * chunkSize)
		say("AOUCSV|" .. kind .. "|" .. part .. "|" .. total .. "|" .. chunk)
	end
end

function Optim.RecExport(count)
	local st = recLoad()
	local total = #st
	if total <= 0 then say("export: no records"); return end
	count = clamp(math.floor(tonumber(count) or 100), 1, 500)
	local first = math.max(1, total - count + 1)
	say("AOUCSV|BEGIN|2|" .. (total - first + 1) .. "|records")
	exportChunks("H", RECCOLS)
	for i = first, total do
		local line = st[i]
		if line then exportChunks("R" .. i, line) end
	end
	say("AOUCSV|END")
	say("Export ready: copy AOUCSV lines from chat to a text file, then run AoU_ChatLog_To_CSV.py")
end

function Optim.RecClear()
    local st = {}
    Optim.RecStore = st
    local ok, verified = recWrite(st)
    return ok, verified
end


-- show a calculation error once in the chat (and in the block), instead of an empty block
Optim.LastErr = nil
function Optim.ReportError(e)
	local msg = tostring(e)
	if msg ~= Optim.LastErr then
		Optim.LastErr = msg
		sayLong("calc error: " .. msg)
	end
	return msg
end

--------------------------------------------------------------------------------
-- Slash command: /aou ...
--------------------------------------------------------------------------------

function Optim.OnSlash(text)
        text = tostring(text or "")
        text = string.gsub(text, "^%s+", "")

        local rawFirst = string.match(text, "^%S+") or ""
        local first = string.lower(rawFirst)

        if first == "/aou" then
                text = "/aou" .. string.sub(text, #rawFirst + 1)
        elseif first == "/dpscope" then
                text = "/dpscope" .. string.sub(text, #rawFirst + 1)
        elseif first == "aou" then
                text = "/aou" .. string.sub(text, #rawFirst + 1)
        elseif first == "dpscope" then
                text = "/dpscope" .. string.sub(text, #rawFirst + 1)
        else
                local bare = {
                        help=true, show=true, mark=true, rec=true,
                        fix=true, free=true, base=true, atk=true,
                        def=true, caut=true, eq=true, thp=true,
                        bal=true, auto=true, off=true, on=true,
                        probe=true, scan=true, mode=true, role=true,
                        flag=true, hp=true, tw=true, font=true,
                        lastev=true, hptest=true, reset=true,
                        ping=true, adiag=true, stats=true, phase=true,
                        heal=true, defstat=true, diff=true, log=true,
                        prof=true
                }
                if not bare[first] then return false end
                text = "/aou " .. text
        end

        local args = {}
        local pos = 1
        while true do
                local s, e = string.find(text, "%S+", pos)
                if not s then break end
                args[#args + 1] = string.sub(text, s, e)
                pos = e + 1
        end

        if args[1] ~= "/aou" and args[1] ~= "/dpscope" then
                return false
        end

        local cfg = Optim.Cfg
        local cmd = string.lower(args[2] or "help")

        if cmd == "adiag" then
                local moduleOK = (AOUA ~= nil)
                local slashOK = moduleOK and (type(AOUA.OnSlash) == "function")
                local argText = table.concat(args, "|")
                say("AOUA module=" .. tostring(moduleOK) ..
                    " OnSlash=" .. tostring(slashOK) ..
                    " args=" .. argText)
                return true
        end

        if AOUA and AOUA.OnSlash then
                local handled, message = AOUA.OnSlash(table.concat(args, " ", 2))
                if handled then
                        if message then say(message) end
                        return true
                end
        end

        if cmd == "ping" then
                say("DPScope ping OK")
                return true
        end

	local function setk(k, v)
		cfg[k] = v
		Optim.Dirty[k] = true
	end
	local function nums(n)
		local t = {}
		for i = 1, n do
			local v = tonumber(args[2 + i])
			if not v then return nil end
			t[i] = math.max(0, math.floor(v + 0.5))
		end
		return t
	end

	if cmd == "atk" then
		local t = nums(7)
		if not t then
			say(Optim.Text("OptUsageAtk"))
		else
			setk("fM", t[1]) setk("fR", t[2]) setk("fU", t[3]) setk("L", t[4])
			setk("eM", t[5]) setk("eR", t[6]) setk("eU", t[7])
			say(Optim.Text("OptSavedAtk"))
		end
	elseif cmd == "def" then
		local t = nums(6)
		if not t then
			say(Optim.Text("OptUsageDef"))
		else
			setk("fS", t[1]) setk("fW", t[2]) setk("fB", t[3])
			setk("eS", t[4]) setk("eW", t[5]) setk("eB", t[6])
			say(Optim.Text("OptSavedDef"))
		end
	elseif cmd == "fix" then
		local t = nums(6)
		if not t then
			say(Optim.Text("OptUsageFix"))
		else
			setk("fM", t[1]) setk("fR", t[2]) setk("fU", t[3])
			setk("fS", t[4]) setk("fW", t[5]) setk("fB", t[6])
			say(Optim.Text("OptSavedFix"))
		end
	elseif cmd == "base" then
		local t = nums(6)
		if not t then
			say(Optim.Text("OptUsageBase"))
		else
			setk("bM", t[1]) setk("bR", t[2]) setk("bU", t[3])
			setk("bS", t[4]) setk("bW", t[5]) setk("bB", t[6])
			say(Optim.Text("OptSavedBase"))
		end
	elseif cmd == "off" or cmd == "on" then
		setk("on", (cmd == "on") and 1 or 0)
		say("optimizer = " .. (cfg.on == 1 and "on" or "off"))
	elseif cmd == "caut" then
		local v = tonumber(args[3])
		if v then
			setk("caut", math.max(0, math.floor(v + 0.5)))
			say("caut = " .. cfg.caut)
		else
			say("/aou caut N (0 = read from the game)")
		end
	elseif cmd == "eq" then
		setk("eq", (args[3] == "on") and 1 or 0)
		say("equipment redistribution = " .. (cfg.eq == 1 and "on" or "off"))
	elseif cmd == "thp" then
		local v = tonumber(args[3])
		if v then
			setk("thp", clamp(math.floor(v + 0.5), 0, 100))
			say("thp = " .. cfg.thp)
		else
			say("/aou thp 0..100")
		end
	elseif cmd == "free" then
		local v = tonumber(args[3])
		if v then
			setk("free", math.max(0, math.floor(v + 0.5)))
			say("free = " .. cfg.free)
		else
			say("/aou free N")
		end
	elseif cmd == "bal" then
		local v = tonumber(args[3])
		if v then
			setk("bal", clamp(v, 0, 3))
			say("bal = " .. cfg.bal)
		else
			say("/aou bal 0..3")
		end
	elseif cmd == "auto" then
		setk("auto", (args[3] == "off") and 0 or 1)
		say("auto = " .. (cfg.auto == 1 and "on" or "off"))
	elseif cmd == "hptest" then
		local tg = Optim.GetTarget()
		say("target id: " .. tostring(tg))
		if tg then
			local ok, r = pcall(function() return object.GetHealthInfo(tg) end)
			summarize("GetHealthInfo(target)", ok, r)
		end
		say("hp reads: ok=" .. Optim.Hp.ok .. " fail=" .. Optim.Hp.fail .. " last=" .. Optim.Hp.last)
	elseif cmd == "healtrace" then
		local tr = Optim.HealTrace
		say("heal events: " .. Optim.HealStat.n .. ", same health read as the previous event: " .. Optim.HealStat.same
			.. " (" .. F1(Optim.HealStat.n > 0 and Optim.HealStat.same / Optim.HealStat.n * 100 or 0) .. "%)")
		for i = 1, #tr do
			local e = tr[i]
			sayLong(i .. ": " .. (e.mine and "self" or "ally") .. " heal=" .. I(e.heal) .. " hp=" .. I(e.value) .. "/" .. I(e.limit)
				.. (e.real and "" or " (percent only)") .. " pre=" .. F1(e.pre * 100) .. "%" .. (e.same and " same-read" or ""))
		end
	elseif cmd == "lastev" then
		local mode = (args[3] == "dmg") and enumMode.Dps or enumMode.Hps
		local ev = Optim.LastEv[mode]
		if not ev then
			say("no event captured yet (hit or heal something first)")
		else
			summarize(mode == enumMode.Dps and "last damage event" or "last heal event", true, ev)
		end
	elseif cmd == "mark" then
        say("mark: handler reached")

        local label = "x"
        if #args >= 3 then
                label = table.concat(args, "_", 3)
        end

        local makeOK, fields = pcall(function()
                return Optim.MakeRecord(label)
        end)

        if not makeOK then
                sayLong("mark: MakeRecord failed: " .. tostring(fields))
        elseif not fields then
                say("mark: no fight data (fight or player not found)")
        else
                say("mark: snapshot created; columns=" .. tostring(#fields))

                local saveCallOK, saveOK, n, verified = pcall(function()
                        return Optim.SaveRecord(fields)
                end)

                if not saveCallOK then
                        sayLong("mark: SaveRecord failed: " .. tostring(saveOK))
                else
                        say("mark save: ok=" .. tostring(saveOK) ..
                            " number=" .. tostring(n) ..
                            " verified=" .. tostring(verified))
                end
        end

        elseif cmd == "rec" then
		local sub = args[3] or "list"
		if sub == "clear" then
    local ok, verified = Optim.RecClear()
    if ok and verified then
        say("records cleared (verified)")
    elseif ok then
        say("clear written, but read-back not confirmed")
    else
        say("ERROR: records clear write failed")
    end
		elseif sub == "export" then
			Optim.RecExport(tonumber(args[4]) or 100)
		else
			Optim.RecList(tonumber(args[4]) or 10)
		end
	elseif cmd == "probe" then
		Optim.Probe()
	elseif cmd == "scan" then
		Optim.Scan(args[3])
	elseif cmd == "mode" then
		if args[3] == "pvp" or args[3] == "pve" then
			setk("mode", args[3])
			say("mode = " .. cfg.mode)
		else
			say("/aou mode pve|pvp")
		end
	elseif cmd == "role" then
		if args[3] == "dd" or args[3] == "heal" or args[3] == "auto" then
			setk("role", args[3])
			say("role = " .. cfg.role)
		else
			say("/aou role dd|heal|auto")
		end
	elseif cmd == "flag" then
		setk("flag", (args[3] == "off") and 0 or 1)
		say("redistribute = " .. (cfg.flag == 1 and "on" or "off"))
	elseif cmd == "hp" then
		local v = tonumber(args[3])
		if v then
			setk("hp", math.max(0, math.floor(v + 0.5)))
			say("hp = " .. cfg.hp)
		else
			say("/aou hp N")
		end
	elseif cmd == "tw" then
		local v = tonumber(args[3])
		if v then
			setk("tw", clamp(math.floor(v + 0.5), 1, 10))
			say("tw = " .. cfg.tw)
		else
			say("/aou tw 1..10")
		end
	elseif cmd == "font" then
		local v = tonumber(args[3])
		if v and v >= 1 and v <= 3 then
			setk("font", math.floor(v))
			say("font = " .. cfg.font)
		else
			say("/aou font 1|2|3")
		end
	elseif cmd == "ver" then
		say("DPScope build 25, recalcs " .. Optim.Perf.recalcs .. "/" .. Optim.Perf.calls .. ", font = " .. cfg.font .. ", localization = " .. tostring(localization))
	elseif cmd == "reset" then
		Optim.ResetCfg()
		say(Optim.Text("OptReset"))
	elseif cmd == "show" then
		say("mode=" .. cfg.mode .. " role=" .. cfg.role .. " flag=" .. cfg.flag .. " tw=" .. cfg.tw .. " hp=" .. cfg.hp)
		say("atk fM=" .. cfg.fM .. " fR=" .. cfg.fR .. " fU=" .. cfg.fU .. " L=" .. cfg.L .. " eM=" .. cfg.eM .. " eR=" .. cfg.eR .. " eU=" .. cfg.eU)
		say("hp reads: ok=" .. Optim.Hp.ok .. " fail=" .. Optim.Hp.fail .. " last=" .. Optim.Hp.last)
		say("def fS=" .. cfg.fS .. " fW=" .. cfg.fW .. " fB=" .. cfg.fB .. " eS=" .. cfg.eS .. " eW=" .. cfg.eW .. " eB=" .. cfg.eB)
		say("base bM=" .. cfg.bM .. " bR=" .. cfg.bR .. " bU=" .. cfg.bU .. " bS=" .. cfg.bS .. " bW=" .. cfg.bW .. " bB=" .. cfg.bB .. " caut=" .. cfg.caut .. " eq=" .. cfg.eq .. " thp=" .. cfg.thp .. " free=" .. cfg.free .. " bal=" .. cfg.bal .. " auto=" .. cfg.auto)
	else
		say(Optim.Text("OptHelp1"))
		say(Optim.Text("OptHelp2"))
		say(Optim.Text("OptHelp3"))
	end

	Optim.Memo.key = nil
	Optim.SaveCfg()
	return true
end
