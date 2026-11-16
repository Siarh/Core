--------------------------------------------------------------------------------
-- File: AoUMeterGUI.lua
-- Desc: Graphical user interface
--------------------------------------------------------------------------------

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
			TargetInfoPanel = nil,
			TargetInfoText = nil,
			TargetInfoTargetId = nil,
			TargetHealthRegistered = false,
			TargetHealthHandler = nil,

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
		if isResolve then
			-- The old red Resolve bar is replaced by the live target-info row below.
			GlobalInfoPanel.Bar:Hide()
		else
			GlobalInfoPanel.Bar:Show()
			GlobalInfoPanel.Bar:SetColor(HitTypeColors[GlobalInfoData.ID])
			GlobalInfoPanel.Bar:SetPosition(0, 15)
		end

		local averagePool = hasSamples and GlobalInfoData.Avg or currentResolve
		local currentPool = currentResolve ~= nil and currentResolve or averagePool
		local panelWidth = GlobalInfoPanel:GetWidth()
		if type(panelWidth) ~= "number" or panelWidth <= 0 then panelWidth = 356 end
		-- Keep this Resolve strip inside the dedicated 356px row, not the
		-- 396px spell-detail row used by the other lists.
		local barWidth = math.min(panelWidth, 356)
		local percentage = isResolve and currentPool or GlobalInfoData.Percentage
		percentage = math.max(0, math.min(100, tonumber(percentage) or 0))
		if not isResolve then
			GlobalInfoPanel.Bar:SetWidth(barWidth * (percentage / 100))
		end

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
--------------------------------------------------------------------------------
-- Watch only the currently selected target's health changes.
-- RegisterEventHandler's filter activates the personal event for this ObjectId.
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateTargetHealthSubscription(targetId)
	local oldId = self.TargetInfoTargetId
	local sameTarget = oldId and targetId and type(SameObjectId) == "function"
		and SameObjectId(oldId, targetId)
	if sameTarget and self.TargetHealthRegistered then return end

	if oldId and self.TargetHealthRegistered and common
		and type(common.UnRegisterEventHandler) == "function" then
		pcall(common.UnRegisterEventHandler, self.TargetHealthHandler,
			"EVENT_OBJECT_HEALTH_CHANGED", { id = oldId })
	end

	self.TargetInfoTargetId = targetId
	self.TargetHealthRegistered = false
	if targetId and self.TargetHealthHandler and common
		and type(common.RegisterEventHandler) == "function" then
		local ok = pcall(common.RegisterEventHandler, self.TargetHealthHandler,
			"EVENT_OBJECT_HEALTH_CHANGED", { id = targetId })
		self.TargetHealthRegistered = ok
	end
end

--------------------------------------------------------------------------------
-- Draw the live target in the row which replaces the red Resolve separator.
-- Exact HP is displayed only when the API supplies both value and limit.
--------------------------------------------------------------------------------
function TUMeterGUI:UpdateTargetInfo()
	local dp = self.DetailsPanel
	local panel = dp and dp.TargetInfoPanel
	local text = dp and dp.TargetInfoText
	if not panel or not text then return end

	local targetId = nil
	if avatar and type(avatar.GetTarget) == "function" then
		local ok, id = pcall(avatar.GetTarget)
		if ok then targetId = id end
	end

	local exists = false
	if targetId ~= nil and object and type(object.IsExist) == "function" then
		local ok, value = pcall(object.IsExist, targetId)
		exists = ok and value == true
	end

	if not exists then
		self:UpdateTargetHealthSubscription(nil)
		text:SetVal("Name", targetText("Цель не выбрана"))
		panel:Show()
		return
	end

	self:UpdateTargetHealthSubscription(targetId)

	local targetName = "?"
	if object and type(object.GetName) == "function" then
		local ok, value = pcall(object.GetName, targetId)
		if ok then
			local readable = targetReadableName(value)
			if readable ~= "" then targetName = readable end
		end
	end

	local levelText = "?"
	if unit and type(unit.GetLevel) == "function" then
		local ok, value = pcall(unit.GetLevel, targetId)
		if ok and tonumber(value) then
			levelText = string.format("%.0f", tonumber(value))
		end
	end

	local currentText, maximumText, percentText = "?", "?", "?"
	if object and type(object.GetHealthInfo) == "function" then
		local ok, health = pcall(object.GetHealthInfo, targetId)
		if ok and type(health) == "table" then
			local current = tonumber(health.value)
			local maximum = tonumber(health.limit)
			local percent = tonumber(health.valuePercents or health.percents)

			if current ~= nil and maximum ~= nil and maximum > 0 then
				currentText = string.format("%.0f", math.floor(current + 0.5))
				maximumText = string.format("%.0f", math.floor(maximum + 0.5))
				if percent == nil then
					percent = math.floor(current / maximum * 100 + 0.5)
				end
			end

			if percent ~= nil then
				percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
				percentText = string.format("%.0f", percent)
			end
		end
	end

	local line = string.format("%s | ур. %s | HP %s/%s (%s%%)",
		targetName, tostring(levelText), currentText, maximumText, percentText)
	text:SetVal("Name", targetText(line))
	panel:Show()
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
	local height = 826

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

		for i = 1, OPTROWS do
			local row = dp.OptList[i]
			local ln = lines[i]
			if ln then
				row:SetPosition(22, y + 18 + (i - 1) * 18)
				row:Show()
				row.Name:SetVal("Name", Optim.Text(ln[1]))
				row.Count:SetVal("Count", W(""))
				row.Damage:SetVal("Min", cell(ln[2]))
				row.Damage:SetVal("Avg", cell(ln[3]))
				row.Damage:SetVal("Max", cell(ln[4]))
				row.Percent:SetVal("Percentage", W(""))
			end
		end
		height = y + 18 + table.getn(lines) * 18 + 20
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
	self:UpdateTargetInfo()

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
		-- UpdateSpellList hides every child before refreshing the spell bars.
		-- If the pointer remains over a spell, the pointing reaction does not fire
		-- again; restore that spell's Normal/Critical/Glancing rows explicitly.
		if self.Hovering and self.HoveringSpellIndex then
			detailsPanel.SpellDetailsHeaderPanel:Show()
			self:UpdateSpellDetailsList(self.HoveringSpellIndex)
		end
	end

	-- Update the analyzer/target slot even when no combatant row is selected.
	self:UpdateOptim()
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
		if extraIndex == enumGlobalInfo.Determination then
			self.DetailsPanel.GlobalInfoList[extraIndex].Bar:Hide()
		end
	end

	-- Reuse the existing XDB target text row to replace the red Resolve separator.
	local targetInfoOffset = GlobalInfoOffset + EXTRATYPES * 18 + 7
	self.DetailsPanel.TargetInfoPanel = self.DetailsPanel:GetChildByName("TargetInfoPanel")
	self.DetailsPanel.TargetInfoText = self.DetailsPanel.TargetInfoPanel:GetChildByName("TargetInfoTextView").Widget
	self.DetailsPanel.TargetInfoPanel:SetPosition(22, targetInfoOffset)
	self.DetailsPanel.TargetInfoPanel:Hide()

	-- Move the ability table down by exactly one target-info row.
	local spellHeaderOffset = targetInfoOffset + 18
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

	self.TargetHealthHandler = function(params)
		local watchedId = self.TargetInfoTargetId
		if watchedId and params and params.id and type(SameObjectId) == "function"
			and SameObjectId(params.id, watchedId) then
			self:UpdateTargetInfo()
		end
	end
	self:UpdateTargetInfo()
end
