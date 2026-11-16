--------------------------------------------------------------------------------
-- File: AoUMeterGUI.lua
-- Desc: Graphical user interface
--------------------------------------------------------------------------------

-- Current-fight opponent summary shown in the selected player's details panel.
local TARGET_INFO_ROWS = 1
local TARGET_INFO_HEIGHT = 0 -- target line is placed at the start of the optimizer rows

-- WString conversions can return either UTF-8 or legacy CP1251 text,
-- depending on the object/API path. Only run UTF-8 through the CP1251 encoder.
local function targetIsUtf8(value)
	local i, n = 1, #value
	while i <= n do
		local b = string.byte(value, i)
		if b <= 127 then
			i = i + 1
		elseif b >= 194 and b <= 223 then
			local b2 = string.byte(value, i + 1)
			if not b2 or b2 < 128 or b2 > 191 then return false end
			i = i + 2
		elseif b >= 224 and b <= 239 then
			local b2, b3 = string.byte(value, i + 1), string.byte(value, i + 2)
			if not b2 or not b3 or b2 < 128 or b2 > 191 or b3 < 128 or b3 > 191 then return false end
			if b == 224 and b2 < 160 then return false end
			if b == 237 and b2 >= 160 then return false end
			i = i + 3
		elseif b >= 240 and b <= 244 then
			local b2, b3, b4 = string.byte(value, i + 1), string.byte(value, i + 2), string.byte(value, i + 3)
			if not b2 or not b3 or not b4 or b2 < 128 or b2 > 191
				or b3 < 128 or b3 > 191 or b4 < 128 or b4 > 191 then return false end
			if b == 240 and b2 < 144 then return false end
			if b == 244 and b2 > 143 then return false end
			i = i + 4
		else
			return false
		end
	end
	return true
end

local function targetText(value)
	local text = tostring(value or "")
	if userMods and type(userMods.ToWString) == "function" then
		if localization == "rus" and Optim and type(Optim.ToWString) == "function"
			and targetIsUtf8(text) then
			return Optim.ToWString(text)
		end
		return userMods.ToWString(text)
	end
	return text
end

local function targetReadableName(value)
	if value ~= nil and common and type(common.IsWString) == "function"
		and userMods and type(userMods.FromWString) == "function" then
		local okWide, isWide = pcall(common.IsWString, value)
		if okWide and isWide then
			local okText, plain = pcall(userMods.FromWString, value)
			if okText and plain ~= nil then value = plain end
		end
	end
	local name = tostring(value or "")
	name = string.gsub(name, "^%s*(.-)%s*$", "%1")
	if name == "" or string.match(name, "^userdata:") or string.match(name, "^table:") then return "" end
	local visible = string.gsub(name, "[%s%?%p]", "")
	local _, questionCount = string.gsub(name, "%?", "")
	if visible == "" or string.find(name, "%?%?") or (questionCount >= 2 and questionCount * 2 >= #name) then return "" end
	return name
end

local function targetCompactNumber(value)
	value = tonumber(value)
	if not value then return "" end
	if math.abs(value) >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif math.abs(value) >= 1000 then
		return string.format("%.1fK", value / 1000)
	end
	return string.format("%.0f", value)
end

local function targetKindLabel(kind)
	local russian = localization == "rus"
	local labels = russian and {
		mob = "моб", player = "игрок", npc = "НПС"
	} or {
		mob = "mob", player = "player", npc = "NPC"
	}
	return labels[kind]
end

local function targetQualityLabel(value)
	if not value or value == "" then return "" end
	local key = tostring(value)
	key = string.gsub(key, "^UNIT_QUALITY_", "")
	key = string.gsub(key, "^ENUM:", "quality#")
	local russian = localization == "rus"
	local labels = russian and {
		COMMON = "обычный", ELITE = "элита", FLAVOR_ELITE = "сюжетный элитный",
		MINI_BOSS = "мини-босс", BOSS = "босс", RAID_BOSS = "рейд-босс",
		RAID_ELITE = "рейд-элита", CRITTER = "существо"
	} or {
		COMMON = "common", ELITE = "elite", FLAVOR_ELITE = "flavor elite",
		MINI_BOSS = "mini-boss", BOSS = "boss", RAID_BOSS = "raid boss",
		RAID_ELITE = "raid elite", CRITTER = "critter"
	}
	if string.match(key, "^ENUM:") then return "" end
	if labels[key] then return labels[key] end
	local numeric = tonumber(key)
	if numeric ~= nil then
		for _, name in ipairs({
			"COMMON", "ELITE", "FLAVOR_ELITE", "MINI_BOSS",
			"BOSS", "RAID_BOSS", "RAID_ELITE", "CRITTER"
		}) do
			local constant = _G and _G["UNIT_QUALITY_" .. name] or nil
			if constant ~= nil and tonumber(constant) == numeric then return labels[name] or "" end
		end
	end
	return ""
end

local function targetSchoolLabel(value)
	local key = tostring(value or "UNKNOWN")
	key = string.gsub(key, "^ENUM_SubElement_", "")
	local russian = localization == "rus"
	local labels = russian and {
		PHYSICAL = "Физ", FIRE = "Огонь", COLD = "Холод", ICE = "Холод",
		ELECTRIC = "Эл-во", ASTRAL = "Астрал", DIVINE = "Бож",
		NATURE = "Природа", LIGHT = "Свет", DARK = "Тьма"
	} or {
		PHYSICAL = "Physical", FIRE = "Fire", COLD = "Cold", ICE = "Ice",
		ELECTRIC = "Electric", ASTRAL = "Astral", DIVINE = "Divine",
		NATURE = "Nature", LIGHT = "Light", DARK = "Dark"
	}
	if labels[key] then return labels[key] end
	return ""
end

local function isAvatarCombatant(combatant)
	if not combatant or not combatant.ID or not avatar or type(avatar.GetId) ~= "function"
		or type(SameObjectId) ~= "function" then return false end
	local ok, avatarId = pcall(avatar.GetId)
	return ok and SameObjectId(combatant.ID, avatarId)
end

--------------------------------------------------------------------------------
-- Type TMainPanelGUI
Global("TMainPanelGUI", {})
--------------------------------------------------------------------------------
function TMainPanelGUI:CreateNewObject(name)
	local widget = TWidget:CreateNewObject(name)
	return setmetatable({
			FightBtn = widget:GetChildByName("FightPanel"),
			FightText = widget:GetChildByName("FightPanel"):GetChildByName("FightNameTextView").Widget, -- Button to switch the active fight
			ModeBtn = widget:GetChildByName("ModePanel"),
			ModeText = widget:GetChildByName("ModePanel"):GetChildByName("ModeNameTextView").Widget, -- Button to switch the active mode       
			TotalPanel = widget:GetChildByName("TotalInfoPanel"), -- Panel to display the total
			PlayerList = {}, -- Panel player list
		}, { __index = widget })
end

--------------------------------------------------------------------------------
-- Type TMainPanelGUI
Global("TDetailsPanelGUI", {})
--------------------------------------------------------------------------------
function TDetailsPanelGUI:CreateNewObject(name)
	local widget = TWidget:CreateNewObject(name)
	return setmetatable({
			CloseButton = widget:GetChildByName("CloseBtn"), -- Close button
			PlayerNameText = widget:GetChildByName("SpellPlayerNameTextViewName").Widget,

			GlobalInfoHeaderPanel = widget:GetChildByName("GlobalInfoHeaderPanel"),
			GlobalInfoHeaderNameText = widget.Widget:GetChildChecked("GlobalInfoHeaderTextViewName", true),
			GlobalInfoHeaderStatsText = widget.Widget:GetChildChecked("GlobalInfoHeaderTextViewStats", true),
			GlobalInfoList = {},     -- Panel extra info list
			OpponentHeader = nil,
			OpponentList = {},

			SpellHeaderPanel = widget:GetChildByName("SpellHeaderPanel"), -- Header panel
			SpellHeaderNameText = widget.Widget:GetChildChecked("SpellHeaderTextViewName", true),
			SpellHeaderStatsText = widget.Widget:GetChildChecked("SpellHeaderTextViewStats", true),
			SpellList = {},         -- Panel spell list

			SpellDetailsHeaderPanel = widget:GetChildByName("SpellDetailHeaderPanel"),
			SpellDetailsHeaderNameText = widget.Widget:GetChildChecked("SpellDetailHeaderTextViewName", true),
			SpellDetailsHeaderStatsText = widget.Widget:GetChildChecked("SpellDetailHeaderTextViewStats", true),  
			SpellInfoList = {},     -- Panel spell info list (normal, critical, glancing)
			SpellMissList = {},     -- Panel miss list
			SpellBlockList = {},    -- Panel block list
		}, { __index = widget })
end
--------------------------------------------------------------------------------
-- Type TTotalPanelGUI
Global("TTotalPanelGUI", {})
--------------------------------------------------------------------------------
function TTotalPanelGUI:CreateNewObjectByDesc(name, desc, owner)
	local widget = TWidget:CreateNewObjectByDesc(name, desc, owner)
	return setmetatable({
			Bar = widget:GetChildByName("PlayerInfoBar"),
			Name = widget:GetChildByName("TotalInfoTextViewName").Widget,
			Value = widget:GetChildByName("PlayerInfoTextViewStats").Widget
		}, { __index = widget })
end
--------------------------------------------------------------------------------
-- Type TPlayerPanelGUI
Global("TPlayerPanelGUI", {})
--------------------------------------------------------------------------------
function TPlayerPanelGUI:CreateNewObjectByDesc(name, desc, owner)
	local widget = TWidget:CreateNewObjectByDesc(name, desc, owner)
	return setmetatable({
			Bar = widget:GetChildByName("PlayerInfoBar"),
			Name = widget:GetChildByName("PlayerInfoTextViewName").Widget,
			Value = widget:GetChildByName("PlayerInfoTextViewStats").Widget,
			Percent = widget:GetChildByName("PlayerInfoTextViewPercentage").Widget,
		}, { __index = widget })
end
--------------------------------------------------------------------------------
-- Type TSpellPanelGUI
Global("TSpellPanelGUI", {})
--------------------------------------------------------------------------------
function TSpellPanelGUI:CreateNewObjectByDesc(name, desc, owner)
	local widget = TWidget:CreateNewObjectByDesc(name, desc, owner)
	return setmetatable({
			Bar = widget:GetChildByName("SpellBar"),
			Name = widget:GetChildByName("SpellTextViewName").Widget,
			Damage = widget:GetChildByName("SpellTextViewStats").Widget,
			Percent = widget:GetChildByName("SpellTextViewPercentage").Widget,
		}, { __index = widget })
end
--------------------------------------------------------------------------------
-- Type TSpellDetailsPanelGUI
Global("TSpellDetailsPanelGUI", {})
--------------------------------------------------------------------------------
function TSpellDetailsPanelGUI:CreateNewObjectByDesc(name, desc, owner)
	local widget = TWidget:CreateNewObjectByDesc(name, desc, owner)
	return setmetatable({
			Bar = widget:GetChildByName("SpellDetailBar"),
			Name = widget:GetChildByName("SpellDetailTextViewName").Widget,
			Count = widget:GetChildByName("SpellDetailTextViewCount").Widget,
			Damage = widget:GetChildByName("SpellDetailTextViewStats").Widget,
			Percent = widget:GetChildByName("SpellDetailTextViewPercentage").Widget,
		}, { __index = widget })
end

--------------------------------------------------------------------------------
-- Type TUMeter
Global("TUMeterGUI", {})
--------------------------------------------------------------------------------
function TUMeterGUI:CreateNewObject(dpsMeter)
	return setmetatable({
			DPSMeter = dpsMeter,   -- the data object
			AoPanelDetected = false, -- true if AoPanel is also installed

			ActiveFight = dpsMeter.Fight.Current,   -- Active fight
			ActiveMode = enumMode.Dps,          -- Active mode
			SelectedCombatant = nil,            -- Selected combatant
			SelectedCombatantInfo = nil,         -- Selected combatant info (id, persistentId, name)
			HoveringSpellIndex = nil,            -- spell row whose Normal/Critical details are currently shown

			ShowHideBtn = nil,      -- "D" button to show/hide the addon
			MainPanel = nil,        -- Main panel with player list
			DetailsPanel = nil,     -- Details panel with spell list / details

			InitialSize = {},       -- Keep trace of original sizes and location of widgets
			MainPanelWidth = 294,   -- MainPanel width, must be >= 294
			BarWidth = 230,         -- Bar width, adjusted automatically
		}, { __index = self })
end
--------------------------------------------------------------------------------
function TUMeterGUI:GetActiveFight()
	return self.DPSMeter.FightsList[self.ActiveFight]
end
--------------------------------------------------------------------------------
function TUMeterGUI:GetActiveFightData()
	return self.DPSMeter.FightsList[self.ActiveFight].Data[self.ActiveMode]
end
--------------------------------------------------------------------------------
function TUMeterGUI:GetCurrentCombatant()
	if self.SelectedCombatant then return self.SelectedCombatant end
end
--------------------------------------------------------------------------------
function TUMeterGUI:SetSelectedCombatant(member)
	self.SelectedCombatant = nil
	self.SelectedCombatantInfo = member
end
--------------------------------------------------------------------------------
function TUMeterGUI:SetAvatarSelectedCombatant()
	self.SelectedCombatant = nil
	self.SelectedCombatantInfo = {}
	self.SelectedCombatantInfo.id = avatar.GetId()
	self.SelectedCombatantInfo.name = object.GetName(avatar.GetId())
end
--==============================================================================
--================= PLAYER LIST ================================================
--==============================================================================

--------------------------------------------------------------------------------
-- Hide player panel in the player list
--------------------------------------------------------------------------------
function TUMeterGUI:HideAllPlayerPanel()
	self.MainPanel.TotalPanel:Hide()
	for i = 1, Settings.MaxCombatants do
		self.MainPanel.PlayerList[i]:Hide()
	end
end

--------------------------------------------------------------------------------
-- Update the panel "Total" in the player list
--------------------------------------------------------------------------------
function TUMeterGUI:DisplayTotal()
	local totalPanel = self.MainPanel.TotalPanel
	totalPanel:Show()

	local minute, second = 0, 0
	local fightTime = self:GetActiveFight().Timer:GetElapsedTime()
	if fightTime > 0 then
		minute, second = GetMinSec(fightTime)
	end

	totalPanel.Bar:SetWidth(self.BarWidth)
	totalPanel.Bar:SetColor(self.DPSMeter.bCollectData and TotalColorInFight or TotalColor)

	-- Total(0:00)
	local total = "Total ("  .. minute .. ":" .. userMods.FromWString(common.FormatInt(second , "%02d")) .. ")"
	totalPanel.Name:SetVal("Name", userMods.ToWString(total))
	totalPanel.Value:SetVal("DamageDone", common.FormatFloat(self:GetActiveFightData().Amount, "%f3K5"))
	totalPanel.Value:SetVal("DPS", common.FormatFloat(self:GetActiveFightData().AmountPerSec, "%f3K5"))
end
--------------------------------------------------------------------------------
-- Update values for a combatant in the player list
--------------------------------------------------------------------------------
function TUMeterGUI:DisplayPlayer(playerIndex)
	local combatant = self:GetActiveFight():GetCombatantByIndex(playerIndex)
	local playerPanel = self.MainPanel.PlayerList[playerIndex]
	if not combatant or not playerPanel then return end

	playerPanel:Show()

	playerPanel.Bar:SetWidth(self.BarWidth * (combatant.Data[self.ActiveMode].LeaderPercentage / 100))
	playerPanel.Bar:SetColor(ClassColors[combatant.Class] or ClassColors["UNKNOWN"])

	playerPanel.Name:SetVal("Index", common.FormatInt(playerIndex , "%d"))
	playerPanel.Name:SetVal("Name", combatant.Name)
	playerPanel.Value:SetVal("DamageDone", common.FormatFloat(combatant.Data[self.ActiveMode].Amount, "%f3K5"))
	playerPanel.Value:SetVal("DPS", common.FormatFloat(combatant.Data[self.ActiveMode].AmountPerSec, "%f3K5"))
	playerPanel.Percent:SetVal("Percentage", common.FormatInt(combatant.Data[self.ActiveMode].Percentage, "%d"))
end
--------------------------------------------------------------------------------
-- Update the whole player list
--------------------------------------------------------------------------------
function TUMeterGUI:UpdatePlayerList()
	local currentFight = self:GetActiveFight()
	if not self.MainPanel.Widget:IsVisible() or not currentFight then return end
	currentFight:RecalculateCombatantsData(self.ActiveMode) -- Important

	local combatantCount = math.min(currentFight:GetCombatantCount(), Settings.MaxCombatants)

	self:HideAllPlayerPanel()
	self.MainPanel:SetHeight(47 + (combatantCount + 1) * 24)

	self:DisplayTotal()
	for playerIndex = 1, combatantCount do
		self:DisplayPlayer(playerIndex)
	end
end

--------------------------------------------------------------------------------
-- The target strip is placed at the start of the optimizer block.
--------------------------------------------------------------------------------
--==============================================================================
--================= SPELL PANEL - Spell list ===================================
--==============================================================================

--------------------------------------------------------------------------------
-- Update a extra info line in the spell panel
--------------------------------------------------------------------------------
function TUMeterGUI:DisplayGlobalInfo(GlobalInfoIndex)
	if not self.SelectedCombatant then return end

	local GlobalInfoData = self.SelectedCombatant:GetGlobalInfoByIndex(GlobalInfoIndex, self.ActiveMode)
	local GlobalInfoPanel = self.DetailsPanel.GlobalInfoList[GlobalInfoIndex]
	if not GlobalInfoData or not GlobalInfoPanel or not GlobalInfoPanel.Bar then return end

	local isResolve = GlobalInfoData.ID == enumGlobalInfo.Determination
	local hasSamples = (GlobalInfoData.Count or 0) > 0
	local currentResolve = nil
	if isResolve and unit and type(unit.GetRage) == "function" then
		local resolveUnitId = self.SelectedCombatant.ID
		if resolveUnitId == nil and avatar and type(avatar.GetId) == "function" then
			local okId, playerId = pcall(avatar.GetId)
			if okId then resolveUnitId = playerId end
		end
		if resolveUnitId ~= nil then
			local okRage, value = pcall(unit.GetRage, resolveUnitId)
			if okRage and type(value) == "number" then currentResolve = value end
		end
	end

	-- Keep the Resolve row visible before its first combat sample.
	if hasSamples or (isResolve and currentResolve ~= nil) then
		GlobalInfoPanel:Show()
		GlobalInfoPanel.Bar:SetColor(HitTypeColors[GlobalInfoData.ID])
		GlobalInfoPanel.Bar:SetPosition(0, 15)

		local averagePool = hasSamples and GlobalInfoData.Avg or currentResolve
		local currentPool = currentResolve ~= nil and currentResolve or averagePool
		local panelWidth = GlobalInfoPanel:GetWidth()
		if type(panelWidth) ~= "number" or panelWidth <= 0 then panelWidth = 356 end
		-- Keep this Resolve strip inside the dedicated 356px row, not the
		-- 396px spell-detail row used by the other lists.
		local barWidth = math.min(panelWidth, 356)
		local percentage = isResolve and currentPool or GlobalInfoData.Percentage
		percentage = math.max(0, math.min(100, tonumber(percentage) or 0))
		GlobalInfoPanel.Bar:SetWidth(barWidth * (percentage / 100))

		GlobalInfoPanel.Name:SetVal("Name", TitleGlobalInfoType[GlobalInfoData.ID])
		if isResolve then
			GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(currentPool, "%d%%"))
			GlobalInfoPanel.Percent:SetVal("Percentage", userMods.ToWString(""))
			if hasSamples then
				GlobalInfoPanel.Damage:SetVal("Min", common.FormatFloat(GlobalInfoData.Min, "%f3K5"))
				GlobalInfoPanel.Damage:SetVal("Avg", common.FormatFloat(GlobalInfoData.Avg, "%f3K5"))
				GlobalInfoPanel.Damage:SetVal("Max", common.FormatFloat(GlobalInfoData.Max, "%f3K5"))
			else
				GlobalInfoPanel.Damage:SetVal("Min", userMods.ToWString("-"))
				GlobalInfoPanel.Damage:SetVal("Avg", common.FormatFloat(averagePool, "%f3K5"))
				GlobalInfoPanel.Damage:SetVal("Max", userMods.ToWString("-"))
			end
		else
			GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(GlobalInfoData.Count, "%d"))
			GlobalInfoPanel.Percent:SetVal("Percentage", common.FormatInt(GlobalInfoData.Percentage, "%d"))
			GlobalInfoPanel.Damage:SetVal("Min", common.FormatFloat(GlobalInfoData.Min, "%f3K5"))
			GlobalInfoPanel.Damage:SetVal("Avg", common.FormatFloat(GlobalInfoData.Avg, "%f3K5"))
			GlobalInfoPanel.Damage:SetVal("Max", common.FormatFloat(GlobalInfoData.Max, "%f3K5"))
		end
	end
end
--------------------------------------------------------------------------------
-- Update a spell line in the spell panel
--------------------------------------------------------------------------------
function TUMeterGUI:DisplaySpell(spellIndex)
	if not self.SelectedCombatant then return end

	local spellData = self.SelectedCombatant:GetSpellByIndex(spellIndex, self.ActiveMode)
	local spellPanel = self.DetailsPanel.SpellList[spellIndex]

	if spellData and spellPanel then
		self.DetailsPanel.SpellList[spellIndex]:Show()
		
		--LogInfo(spellData.Element)
		
		spellPanel.Bar:SetColor(DamageTypeColors[spellData.Element] or { r = 1.0; g = 1.0; b = 1.0; a = 1 } )
		spellPanel.Bar:SetWidth(396 * (spellData.Percentage / 100))

		spellPanel.Name:SetVal("Index", common.FormatInt(spellIndex , "%d"))
		spellPanel.Name:SetVal("Prefix", spellData.Prefix)
		spellPanel.Name:SetVal("Name", spellData.Name)
		spellPanel.Name:SetVal("Suffix", spellData.Suffix)
		--spellPanel.Widget:SetBackgroundTexture(spellData.TextureId)
		spellPanel.Damage:SetVal("DamageDone", common.FormatFloat(spellData.Amount , "%f3K5"))
		spellPanel.Damage:SetVal("DPS", common.FormatFloat(spellData.AmountPerSec , "%f3K5"))
		spellPanel.Damage:SetVal("DamageBlock", common.FormatFloat(spellData.ResistPercentage , "%g"))
		spellPanel.Percent:SetVal("Percentage", common.FormatInt(spellData.Percentage , "%d"))
	end
end
--------------------------------------------------------------------------------
-- Collapse or expand the opponent block to the number of readable rows.
-- All panels below it move together, and the optimizer uses the new top offset.
--------------------------------------------------------------------------------
-- The target row is inserted by UpdateOptim directly after the OptR (Resolve)
-- row. It must not reserve space between the global info section and abilities.
local function updateOpponentSectionLayout(dp, displayedRows)
	dp.OpponentSectionHeight = 0
end

--------------------------------------------------------------------------------
-- Show current-fight opponents for the local player's damage events.
-- All available facts are placed in one full-width, labelled line per target.
-- An unavailable/unreadable name or stat is omitted rather than fabricated.
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateOpponentInfo()
	local dp = self.DetailsPanel
	if not dp.OpponentHeader or not dp.OpponentList then return end

	local activeFight = self:GetActiveFight()
	local isOpponentSummaryFight = self.ActiveFight == self.DPSMeter.Fight.Current
		or self.ActiveFight == self.DPSMeter.Fight.Previous
	local isCurrentPlayerFight = isOpponentSummaryFight and activeFight
		and avatar and avatar.IsExist and avatar.IsExist()
	if not isCurrentPlayerFight then
		dp.OpponentHeader:Hide()
		for i = 1, TARGET_INFO_ROWS do dp.OpponentList[i]:Hide() end
		updateOpponentSectionLayout(dp, 0)
		return
	end

	local rows, total = {}, 0
	local liveCurrentFight = self.ActiveFight == self.DPSMeter.Fight.Current
		and self.DPSMeter.bCollectData == true
	local storedRows = activeFight and activeFight.AOUATargetRows or nil
	if self.ActiveFight == self.DPSMeter.Fight.Previous then
		rows = storedRows or {}
		total = #rows
	elseif storedRows and not liveCurrentFight then
		rows = storedRows
		total = #rows
	elseif AOUA and type(AOUA.GetTargetDisplayRows) == "function" then
		local ok, result, count = pcall(AOUA.GetTargetDisplayRows, TARGET_INFO_ROWS)
		if ok then rows, total = result or {}, tonumber(count) or 0 end
	end

	-- Current prefers the selected live target while collecting (or when no
	-- fight snapshot exists). A completed fight with a saved snapshot remains
	-- historical; Previous never reads today's target.
	local allowCurrentTargetFallback = self.ActiveFight == self.DPSMeter.Fight.Current
		and (liveCurrentFight or not (storedRows and #storedRows > 0))
	if allowCurrentTargetFallback then
		local ev = Optim and Optim.LastEv and Optim.LastEv[enumMode.Dps] or nil
		local eventTarget = ev and ev.target or nil
		local candidates = {}

		local function isUsableUnitTarget(id)
			if id == nil then return false end
			if object and type(object.IsExist) == "function" then
				local ok, exists = pcall(object.IsExist, id)
				if not ok or exists ~= true then return false end
			end
			if object and type(object.IsUnit) == "function" then
				local ok, isUnit = pcall(object.IsUnit, id)
				if not ok or isUnit ~= true then return false end
			end
			return true
		end

		local function addCandidate(id)
			if not isUsableUnitTarget(id) then return end
			for i = 1, #candidates do
				if (type(SameObjectId) == "function" and SameObjectId(candidates[i], id))
					or candidates[i] == id then return end
			end
			candidates[#candidates + 1] = id
		end

		-- Prefer the target currently selected in-game. Use the most recent hit
		-- target only when no live selected target is available.
		if avatar and type(avatar.GetTarget) == "function" then
			local okTarget, currentTarget = pcall(avatar.GetTarget)
			if okTarget then addCandidate(currentTarget) end
		end
		addCandidate(eventTarget)
		if #candidates == 0 and Optim and type(Optim.GetTarget) == "function" then
			local okTarget, currentTarget = pcall(Optim.GetTarget)
			if okTarget then addCandidate(currentTarget) end
		end

		for candidateIndex = 1, #candidates do
			local targetId = candidates[candidateIndex]
			local row = { name = "", kind = "unknown", resistSchools = {} }
			if object and type(object.GetName) == "function" then
				local okName, value = pcall(object.GetName, targetId)
				if okName then row.name = value or "" end
			end
			if object and type(object.IsMob) == "function" then
				local okMob, value = pcall(object.IsMob, targetId)
				if okMob and value == true then row.kind = "mob" end
			end
			if row.kind == "unknown" and object and type(object.IsPlayer) == "function" then
				local okPlayer, value = pcall(object.IsPlayer, targetId)
				if okPlayer and value == true then row.kind = "player" end
			end
			if row.kind == "unknown" and object and type(object.IsUnit) == "function" then
				local okUnit, value = pcall(object.IsUnit, targetId)
				if okUnit and value == true then row.kind = "npc" end
			end
			if unit and type(unit.GetLevel) == "function" then
				local okLevel, value = pcall(unit.GetLevel, targetId)
				if okLevel and tonumber(value) then row.level = tonumber(value) end
			end
			if unit and type(unit.GetQuality) == "function" then
				local okQuality, value = pcall(unit.GetQuality, targetId)
				if okQuality and tonumber(value) then
					row.quality = tonumber(value)
					row.qualityName = tostring(value)
				end
			end
			if Optim and type(Optim.GetHealth) == "function" then
				local okHp, current, maximum, real = pcall(Optim.GetHealth, targetId)
				if okHp and real == true and tonumber(current) and tonumber(maximum) and maximum > 0 then
					row.hpCurrent, row.hpLimit = tonumber(current), tonumber(maximum)
					row.hpPercent = row.hpCurrent / row.hpLimit * 100
				elseif okHp and real == false and tonumber(current) and tonumber(current) >= 0 and tonumber(current) <= 100 then
					row.hpCurrentPercent = tonumber(current)
				end
			end

			-- Resistance belongs to the hit-event target only; never attach an
			-- old hit's mitigation to a different currently selected unit.
			if targetId == eventTarget or (type(SameObjectId) == "function" and SameObjectId(targetId, eventTarget)) then
				local element = targetSchoolLabel(ev and (ev.sysSubElement or ev.subElement or ev.element))
				local resisted = targetCompactNumber(ev and ev.resist)
				if element ~= "" and resisted ~= "" and tonumber(ev and ev.resist) and tonumber(ev.resist) > 0 then
					row.resistSchools[1] = {
						element = ev.sysSubElement or ev.subElement or ev.element,
						amount = tonumber(ev.resist), samples = 1
					}
				end
			end

			if targetReadableName(row.name) ~= "" or row.kind ~= "unknown" or tonumber(row.level)
				or targetQualityLabel(row.qualityName or row.quality) ~= ""
				or row.hpCurrent or row.hpCurrentPercent or #row.resistSchools > 0 then
				rows[1], total = row, 1
				break
			end
		end
	end

	local russian = localization == "rus"
	local W = targetText
	-- No separate heading: the full-width target line belongs at the start
	-- of the optimizer block, directly below its title.
	dp.OpponentHeader:Hide()

	local displayedRows = 0
	for i = 1, math.min(#rows, TARGET_INFO_ROWS) do
		local data = rows[i]
		local parts = {}
		local name = targetReadableName(data.name)
		if name ~= "" then parts[#parts + 1] = name end

		local kind = targetKindLabel(data.kind)
		if kind and kind ~= "" then parts[#parts + 1] = kind end
		if tonumber(data.level) then
			parts[#parts + 1] = (russian and "ур. " or "Lv ") .. tostring(math.floor(data.level))
		end

		local hpText = ""
		if tonumber(data.hpCurrent) and tonumber(data.hpLimit) and data.hpLimit > 0 then
			hpText = "HP " .. targetCompactNumber(data.hpCurrent) .. "/"
				.. targetCompactNumber(data.hpLimit) .. " ("
				.. string.format("%.0f", tonumber(data.hpPercent) or 0) .. "%)"
		elseif tonumber(data.hpCurrentPercent) then
			-- The game exposes enemy health as valuePercents on a 0..100 scale.
			-- Show that normalized scale explicitly instead of marking it unknown.
			local hp = math.max(0, math.min(100, tonumber(data.hpCurrentPercent)))
			hpText = "HP " .. string.format("%.0f", hp) .. "/100 ("
				.. string.format("%.0f", hp) .. "%)"
		elseif tonumber(data.hpBeforePercent) then
			local hp = math.max(0, math.min(100, tonumber(data.hpBeforePercent)))
			hpText = "HP ~" .. string.format("%.0f", hp) .. "/100 (~"
				.. string.format("%.0f", hp) .. "%)"
		end
		if hpText ~= "" then parts[#parts + 1] = hpText end

		local line = table.concat(parts, " | ")
		if line ~= "" then
			displayedRows = displayedRows + 1
			local panel = dp.OpponentList[displayedRows]
			panel:Show()
			panel.Line:SetVal("Name", W(line))
		end
	end
	if displayedRows == 0 then
		displayedRows = 1
		dp.OpponentList[1]:Show()
		dp.OpponentList[1].Line:SetVal("Name",
			W(russian and "Цель не определена" or "Target not identified"))
	end
	for i = displayedRows + 1, TARGET_INFO_ROWS do dp.OpponentList[i]:Hide() end
	updateOpponentSectionLayout(dp, displayedRows)
end

--------------------------------------------------------------------------------
-- Stat optimizer block (bottom of the details panel, only for the player)
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateOptim()
	local dp = self.DetailsPanel
	if not dp.OptList then return end

	-- hide the block and restore the original panel height
	dp.OptHeader:Hide()
	for i = 1, OPTROWS do
		dp.OptList[i]:Hide()
	end
	local height = 826 + (dp.OpponentSectionHeight or TARGET_INFO_HEIGHT)
	local targetPanel = dp.OpponentList and dp.OpponentList[1]
	local hasTargetLine = targetPanel and targetPanel:IsVisible()
	if targetPanel then targetPanel:Hide() end

	local c = self.SelectedCombatant
	local fight = self:GetActiveFight()
	local lines = nil
	-- only for the player, and not while a spell is pointed (its details use the lower part of the panel)
	if c and fight and not self.Hovering and avatar.IsExist() and isAvatarCombatant(c) then
		local ok, res = pcall(Optim.BuildLines, c, fight.Timer:GetElapsedTime(), self.ActiveMode)
		if ok then
			lines = res
		else
			local msg = Optim.ReportError(res)
			lines = { { "OptErr", string.sub(msg, -30), "", "" } }
		end
	end

	if lines then
		-- put the block right after the last displayed spell
		local n = 0
		for i = 1, MAXSPELLS do
			if c:GetSpellByIndex(i, self.ActiveMode) then n = i else break end
		end
		local gap = Settings.OptGap or 36
		local y = dp.OptSpellTop + n * 18 + gap

		-- A normal optimizer value is ASCII/numeric, but AI rows can contain
		-- Russian UTF-8 generated at runtime. Use the optimizer's safe converter.
		local W = Optim.ToWString or userMods.ToWString
		-- a cell starting with "@" is the key of a localized text
		local function cell(v)
			if string.sub(v, 1, 1) == "@" then return Optim.Text(string.sub(v, 2)) end
			return W(v)
		end
		dp.OptHeader:SetPosition(22, y)
		dp.OptHeader:Show()
		dp.OptHeaderName:SetVal("Name", Optim.Text("OptTitle"))
		dp.OptHeaderStats:SetVal("Min", Optim.Text("OptNow"))
		dp.OptHeaderStats:SetVal("Avg", Optim.Text("OptOpt"))
		dp.OptHeaderStats:SetVal("Max", Optim.Text("OptDiff"))

		-- Put the target line at the beginning of the analyzer, immediately
		-- below its title. Shift every stat row by one slot so Resolve and
		-- Ruthlessness keep their original adjacent spacing.
		local targetRowOffset = hasTargetLine and 1 or 0

		for i = 1, OPTROWS do
			local row = dp.OptList[i]
			local ln = lines[i]
			if ln then
				local slotIndex = i + targetRowOffset
				row:SetPosition(22, y + 18 + (slotIndex - 1) * 18)
				row:Show()
				row.Name:SetVal("Name", Optim.Text(ln[1]))
				row.Count:SetVal("Count", W(""))
				row.Damage:SetVal("Min", cell(ln[2]))
				row.Damage:SetVal("Avg", cell(ln[3]))
				row.Damage:SetVal("Max", cell(ln[4]))
				row.Percent:SetVal("Percentage", W(""))
			end
		end

		local displayRowCount = #lines + targetRowOffset
		if targetRowOffset > 0 then
			targetPanel:SetPosition(22, y + 18)
			targetPanel:Show()
		end
		height = y + 18 + displayRowCount * 18 + 20
	end

	if dp.OptHeight ~= height then
		dp.OptHeight = height
		dp:SetHeight(height)
	end
end
--------------------------------------------------------------------------------
-- Fill the spell panel
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateSpellList()
	local detailsPanel = self.DetailsPanel
	if not detailsPanel:IsVisible() or not self:GetActiveFight() then return end

	detailsPanel:HideAllChild()

	detailsPanel.CloseButton:Show()
	self:UpdateOpponentInfo()

	if self.SelectedCombatant then
		self.SelectedCombatant:CalculateSpell(self:GetActiveFight().Timer:GetElapsedTime(), self.ActiveMode) -- Important.

		detailsPanel.PlayerNameText:SetVal("Name", self.SelectedCombatant.Name)
		detailsPanel.PlayerNameText:Show(true)

		if self.SelectedCombatant.Data[self.ActiveMode].Amount > 0 then
			detailsPanel.SpellHeaderPanel:Show()
			detailsPanel.GlobalInfoHeaderPanel:Show()
		end
		for GlobalInfoIndex = 1, EXTRATYPES do
			self:DisplayGlobalInfo(GlobalInfoIndex)
		end
		for spellIndex = 1, MAXSPELLS do
			self:DisplaySpell(spellIndex)
		end
		self:UpdateOptim()

		-- UpdateSpellList hides every child before refreshing the spell bars.
		-- If the pointer remains over a spell, the pointing reaction does not fire
		-- again; restore that spell's Normal/Critical/Glancing rows explicitly.
		if self.Hovering and self.HoveringSpellIndex then
			detailsPanel.SpellDetailsHeaderPanel:Show()
			self:UpdateSpellDetailsList(self.HoveringSpellIndex)
		end
	end
end

--------------------------------------------------------------------------------
-- Update values in both player list & spell panel
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateValues()
	if not avatar.IsExist() then return end
	if not self.SelectedCombatant and self.SelectedCombatantInfo and self:GetActiveFight()then
		self.SelectedCombatant = self:GetActiveFight():GetCombatant(self.SelectedCombatantInfo)
		if not self.SelectedCombatant then
			self:SetAvatarSelectedCombatant()
			self.SelectedCombatant = self:GetActiveFight():GetCombatant(self.SelectedCombatantInfo)
		end
	end
	self:UpdatePlayerList()
	self:UpdateSpellList()
end

--==============================================================================
--================= SPELL PANEL - details list + details resist list ===========
--==============================================================================

--------------------------------------------------------------------------------
-- Display a spell details line in the spell info panel
--------------------------------------------------------------------------------
function TUMeterGUI:DisplaySpellDetails(spellInfoData, spellInfoPanel, title)
	if spellInfoData and spellInfoData.Count > 0 then
		spellInfoPanel:Show()

		spellInfoPanel.Bar:SetColor(HitTypeColors[spellInfoData.ID])
		spellInfoPanel.Bar:SetWidth(396 * (math.abs(spellInfoData.Percentage) / 100))

		spellInfoPanel.Name:SetVal("Name", title[spellInfoData.ID])
		spellInfoPanel.Count:SetVal("Count", common.FormatInt(spellInfoData.Count , "%d"))
		spellInfoPanel.Damage:SetVal("Min", common.FormatFloat(spellInfoData.Min , "%f3K5"))
		spellInfoPanel.Damage:SetVal("Avg", common.FormatFloat(spellInfoData.Avg , "%f3K5"))
		spellInfoPanel.Damage:SetVal("Max", common.FormatFloat(spellInfoData.Max , "%f3K5"))
		spellInfoPanel.Percent:SetVal("Percentage", common.FormatInt(spellInfoData.Percentage , "%d"))
	end
end
--------------------------------------------------------------------------------
-- Fill the spell panel
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateSpellDetailsList(spellIndex)
	if (self.SelectedCombatant) then
		local index
		local spellData = self.SelectedCombatant:GetSpellByIndex(spellIndex, self.ActiveMode)

		if spellData then
			index = 1
			for dmgtype in SortSpellDetailsByCount(spellData.DetailsList) do
				self:DisplaySpellDetails(spellData.DetailsList[dmgtype], self.DetailsPanel.SpellInfoList[index], TitleDmgType)
				index = index + 1
			end

			index = 1
			for misstype in SortSpellDetailsByCount(spellData.MissList) do
				self:DisplaySpellDetails(spellData.MissList[misstype], self.DetailsPanel.SpellMissList[index], TitleMissType)
				index = index + 1
			end

			index = 1
			for blockdmgtype in SortSpellDetailsByAmount(spellData.ResistDetailsList) do
				local originList = spellData.ResistDetailsList[blockdmgtype]
				local list = originList
				if self.ActiveMode == enumMode.Dps or self.ActiveMode == enumMode.Def then
					list = DeepCopyObject(originList)
					list.Percentage = -1 * originList.Percentage 
					list.Min = -1 * originList.Max
					list.Avg = -1 * originList.Avg
					list.Max = -1 * originList.Min
				end
				self:DisplaySpellDetails(
				list, 
				self.DetailsPanel.SpellBlockList[index], 
				(self.ActiveMode == enumMode.Hps or self.ActiveMode == enumMode.IHps) and TitleHealResistType or TitleHitBlockType)
				index = index + 1
			end

			index = 1
			--            for GlobalInfotype in SortSpellDetailsByAmount(spellData.GlobalInfoList) do
			--                self:DisplaySpellDetails(spellData.GlobalInfoList[GlobalInfotype], self.DetailsPanel.SpellExtraList[index], TitleGlobalInfoType)
			--                index = index + 1
			--            end
		end
	end
end
--------------------------------------------------------------------------------
-- Hide all spell info line
--------------------------------------------------------------------------------
function TUMeterGUI:HideAllSpellDetailsPanel()
	for i = 1, DMGTYPES do
		self.DetailsPanel.SpellInfoList[i]:Hide()
	end
	for i = 1, MISSTYPES do
		self.DetailsPanel.SpellMissList[i]:Hide()
	end
	for i = 1, BLOCKDMGTYPES do
		self.DetailsPanel.SpellBlockList[i]:Hide()
	end
	--    for i = 1, EXTRATYPES do
	--        self.DetailsPanel.SpellExtraList[i]:Hide()
	--    end
end

--==============================================================================
--================= Event implementation =======================================
--==============================================================================

--------------------------------------------------------------------------------
-- Swap to the next fight
--------------------------------------------------------------------------------
function TUMeterGUI:SwapFight()
	local rotateFight = {
		[self.DPSMeter.Fight.Total] = self.DPSMeter.Fight.Current,
		[self.DPSMeter.Fight.Current] = self.DPSMeter.Fight.Previous,
		[self.DPSMeter.Fight.Previous] = self.DPSMeter.Fight.Total
	}
	self.ActiveFight = rotateFight[self.ActiveFight]
	self.SelectedCombatant = nil -- invalidate the current combatant

	-- DPSMeter.Fight.x indices can change during the execution
	local title = {
		[self.DPSMeter.Fight.Previous] = TitleFight[enumFight.Previous],
		[self.DPSMeter.Fight.Current] = TitleFight[enumFight.Current],
		[self.DPSMeter.Fight.Total] = TitleFight[enumFight.Total]
	}

	-- Update the fight in the fight panel (at the top of the player list)
	self.MainPanel.FightText:SetVal("Name", title[self.ActiveFight])

	-- Update the fight in the title of the spell panel
	self.DetailsPanel.PlayerNameText:SetVal("Fight", title[self.ActiveFight])

	self:UpdateValues()
end

--------------------------------------------------------------------------------
-- Swap to the next mode
--------------------------------------------------------------------------------
function TUMeterGUI:SwapMode()
	local rotateMode = {
		[enumMode.Dps] = Settings.ModeHPS and enumMode.Hps or Settings.ModeDEF and enumMode.Def or Settings.ModeIHPS and enumMode.IHps or enumMode.Dps,
		[enumMode.Hps] = Settings.ModeDEF and enumMode.Def or Settings.ModeIHPS and enumMode.IHps or Settings.ModeDPS and enumMode.Dps or enumMode.Hps,
		[enumMode.Def] = Settings.ModeIHPS and enumMode.IHps or Settings.ModeDPS and enumMode.Dps or Settings.ModeHPS and enumMode.Hps or enumMode.Def,
		[enumMode.IHps]= Settings.ModeDPS and enumMode.Dps or Settings.ModeHPS and enumMode.Hps or Settings.ModeDEF and enumMode.Def or enumMode.IHps
	}
	self.ActiveMode = rotateMode[self.ActiveMode]
	self.SelectedCombatant = nil -- invalidate the current combatant

	-- Update the mode in the fight panel (at the top of the player list)
	self.MainPanel.ModeText:SetVal("Name", TitleMode[self.ActiveMode])

	-- Update the mode in the title of the spell panel
	self.DetailsPanel.PlayerNameText:SetVal("Mode", TitleMode[self.ActiveMode])

	-- Update the mode in the header of the spell panel
	self.DetailsPanel.SpellHeaderStatsText:SetVal("DPS", TitleMode[self.ActiveMode])

	self:UpdateValues()
end

--------------------------------------------------------------------------------
-- Swap to the next mode
--------------------------------------------------------------------------------
function TUMeterGUI:Reset(fullReset)
	self.DPSMeter:ResetAllFights(fullReset)
	self.ActiveFight = self.DPSMeter.Fight.Current
	self:SetAvatarSelectedCombatant()
	self:UpdateValues()
end

--==============================================================================
--================= INIT =======================================================
--==============================================================================
function TUMeterGUI:Init()
	-- The Data
	self.DPSMeter = TUMeter:CreateNewObject()

	-- Default mode
	self.ActiveMode = Settings.DefaultMode
	self.ActiveFight = self.DPSMeter.Fight.Current

	-- The "D" button to show or hide the main panels
	self.ShowHideBtn = TWidget:CreateNewObject("ShowHideBtn")
	self.ShowHideBtn:DragNDrop(true, 687, nil, true)

	-- Main panel with player list
	self.MainPanel = TMainPanelGUI:CreateNewObject("MainPanel")
	self.MainPanel:DragNDrop(true, 686, nil, true, false)

	-- Retrieve initial sizes of the main panel and its children in order to tweak the width
	local posX, posY
	self.InitialSize["MainPanelWidth"] = self.MainPanel:GetWidth()
	self.InitialSize["FightBtnWidth"] = self.MainPanel.FightBtn:GetWidth()
	self.InitialSize["ModeBtnWidth"] = self.MainPanel.ModeBtn:GetWidth()
	posX, posY = self.MainPanel.FightBtn:GetPosition()
	self.InitialSize["FightBtnPosX"] = posX

	-- Secondary panel with spell list / details
	self.DetailsPanel = TDetailsPanelGUI:CreateNewObject("SpellInfoPanel")
	self.DetailsPanel:DragNDrop(true, 688, nil, true)

	-------------------------------------------------------------------------------
	-- Widget description
	-------------------------------------------------------------------------------
	local totalPanelDesc = self.MainPanel.TotalPanel:GetDesc()
	local playerPanelDesc = self.MainPanel:GetChildByName("PlayerInfoPanel"):GetDesc()
	local spellPanelDesc = self.DetailsPanel:GetChildByName("SpellPanel"):GetDesc()
	local spellInfoPanelDesc = self.DetailsPanel:GetChildByName("SpellDetailPanel"):GetDesc()
	local globalInfoPanelDesc = self.DetailsPanel:GetChildByName("GlobalInfoPanel"):GetDesc()
	local opponentPanelDesc = self.DetailsPanel:GetChildByName("OpponentPanel"):GetDesc()

	-------------------------------------------------------------------------------
	-- Main Panel
	-------------------------------------------------------------------------------

	-- Total panel
	self.MainPanel.TotalPanel:Destroy()
	self.MainPanel.TotalPanel = TTotalPanelGUI:CreateNewObjectByDesc("TotalPanel", totalPanelDesc, self.MainPanel)
	self.MainPanel.TotalPanel:SetPosition(20, 47)
	self.InitialSize["TotalPanelWidth"] = self.MainPanel.TotalPanel:GetWidth()

	-- Player list
	self.MainPanel:GetChildByName("PlayerInfoPanel"):Destroy()
	for playerIndex = 1, Settings.MaxCombatants do
		local wtName = "PlayerPanel" .. playerIndex
		self.MainPanel.PlayerList[playerIndex] = TPlayerPanelGUI:CreateNewObjectByDesc(wtName, playerPanelDesc, self.MainPanel)
		self.MainPanel.PlayerList[playerIndex]:SetPosition(20, 47 + playerIndex * 24)
	end

	-------------------------------------------------------------------------------
	-- Spell Panel
	-------------------------------------------------------------------------------

	local origY = 36

	-- GlobalInfoHeader
	local GlobalInfoHeaderOffset = origY
	self.DetailsPanel.GlobalInfoHeaderPanel:SetPosition(22, GlobalInfoHeaderOffset)

	-- GlobalInfo list
	local GlobalInfoOffset = GlobalInfoHeaderOffset + 18
	for extraIndex = 1, EXTRATYPES do
		local wtName = "GlobalInfoPanel" .. extraIndex
		self.DetailsPanel.GlobalInfoList[extraIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, globalInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.GlobalInfoList[extraIndex]:SetPosition(22, GlobalInfoOffset + (extraIndex-1) * 18)
	end

	-- Opponent profiles (four highest-damage targets from the current fight).
	local opponentHeaderOffset = GlobalInfoOffset + EXTRATYPES * 18 + 7
	self.DetailsPanel:GetChildByName("OpponentPanel"):Destroy()
	local headerWidget = TWidget:CreateNewObjectByDesc(
		"OpponentHeaderPanel", opponentPanelDesc, self.DetailsPanel)
	self.DetailsPanel.OpponentHeader = setmetatable({
		Line = headerWidget:GetChildByName("OpponentLineTextViewName").Widget
	}, { __index = headerWidget })
	self.DetailsPanel.OpponentHeader:SetPosition(22, opponentHeaderOffset)
	self.DetailsPanel.OpponentHeader:Hide()
	self.DetailsPanel.OpponentSectionHeight = 0
	local opponentRowsOffset = opponentHeaderOffset + 18
	for opponentIndex = 1, TARGET_INFO_ROWS do
		local wtName = "OpponentPanel" .. opponentIndex
		local widget = TWidget:CreateNewObjectByDesc(wtName, opponentPanelDesc, self.DetailsPanel)
		self.DetailsPanel.OpponentList[opponentIndex] = setmetatable({
			Line = widget:GetChildByName("OpponentLineTextViewName").Widget
		}, { __index = widget })
		self.DetailsPanel.OpponentList[opponentIndex]:SetPosition(
			22, opponentRowsOffset + (opponentIndex - 1) * 18)
		self.DetailsPanel.OpponentList[opponentIndex]:Hide()
	end

	-- SpellHeader: no blank target block is reserved here; the target row is
	-- rendered inside the optimizer immediately after its Resolve row.
	local spellHeaderOffset = opponentHeaderOffset
	self.DetailsPanel.SpellHeaderPanel:SetPosition(22, spellHeaderOffset)

	-- Spell list
	self.DetailsPanel:GetChildByName("SpellPanel"):Destroy()
	local spellListOffset = spellHeaderOffset + 18
	for spellIndex = 1, MAXSPELLS do
		local wtName = "SpellPanel" .. spellIndex
		self.DetailsPanel.SpellList[spellIndex] = TSpellPanelGUI:CreateNewObjectByDesc(wtName, spellPanelDesc, self.DetailsPanel)
		self.DetailsPanel.SpellList[spellIndex]:SetPosition(22, spellListOffset + (spellIndex-1) * 18)
	end

	-- SpellDetailsHeader
	local spellDetailsHeaderOffset = spellListOffset + MAXSPELLS * 18 + 7
	self.DetailsPanel.SpellDetailsHeaderPanel:SetPosition(22, spellDetailsHeaderOffset)

	-- Spell info
	self.DetailsPanel:GetChildByName("SpellDetailPanel"):Destroy()
	local damageOffset = spellDetailsHeaderOffset + 18
	for infoIndex = 1, DMGTYPES do
		local wtName = "SpellInfoPanel" .. infoIndex
		self.DetailsPanel.SpellInfoList[infoIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.SpellInfoList[infoIndex]:SetPosition(22, damageOffset + (infoIndex-1) * 18)
	end

	-- Spell miss
	local missOffset = damageOffset + DMGTYPES * 18 + 5
	for missIndex = 1, MISSTYPES do
		local wtName = "SpellMissPanel" .. missIndex
		self.DetailsPanel.SpellMissList[missIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.SpellMissList[missIndex]:SetPosition(22, missOffset + (missIndex-1) * 18)
	end

	-- Spell block
	local blockDamageOffset = missOffset + MISSTYPES * 18 + 5
	for blockIndex = 1, BLOCKDMGTYPES do
		local wtName = "SpellBlckPanel" .. blockIndex
		self.DetailsPanel.SpellBlockList[blockIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.SpellBlockList[blockIndex]:SetPosition(22, blockDamageOffset + (blockIndex-1) * 18)
	end

	-- Stat optimizer block (below the block list): header + rows
	local optOffset = blockDamageOffset + BLOCKDMGTYPES * 18 + 14
	local optHeaderDesc = self.DetailsPanel.GlobalInfoHeaderPanel:GetDesc()
	self.DetailsPanel.OptHeader = TWidget:CreateNewObjectByDesc("OptHeaderPanel", optHeaderDesc, self.DetailsPanel)
	self.DetailsPanel.OptHeader:SetPosition(22, optOffset)
	self.DetailsPanel.OptHeaderName = self.DetailsPanel.OptHeader.Widget:GetChildChecked("GlobalInfoHeaderTextViewName", true)
	self.DetailsPanel.OptHeaderStats = self.DetailsPanel.OptHeader.Widget:GetChildChecked("GlobalInfoHeaderTextViewStats", true)
	self.DetailsPanel.OptList = {}
	for optIndex = 1, OPTROWS do
		local wtName = "OptPanel" .. optIndex
		self.DetailsPanel.OptList[optIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.OptList[optIndex]:SetPosition(22, optOffset + 18 + (optIndex-1) * 18)
		self.DetailsPanel.OptList[optIndex].Bar:Hide()
	end
	self.DetailsPanel.OptSpellTop = spellListOffset -- the block is moved right after the last spell in UpdateOptim

end
