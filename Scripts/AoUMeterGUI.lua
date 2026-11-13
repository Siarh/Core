--------------------------------------------------------------------------------
-- File: AoUMeterGUI.lua
-- Desc: Graphical user interface
--------------------------------------------------------------------------------

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

	if GlobalInfoData and GlobalInfoData.Count > 0 then
		GlobalInfoPanel:Show()

		GlobalInfoPanel.Bar:SetColor(HitTypeColors[GlobalInfoData.ID])
		GlobalInfoPanel.Bar:SetWidth(396 * (GlobalInfoData.Percentage / 100))

		GlobalInfoPanel.Name:SetVal("Name", TitleGlobalInfoType[GlobalInfoData.ID])
		GlobalInfoPanel.Count:SetVal("Count", common.FormatInt(GlobalInfoData.Count , "%d"))
		GlobalInfoPanel.Damage:SetVal("Min", common.FormatFloat(GlobalInfoData.Min , "%f3K5"))
		GlobalInfoPanel.Damage:SetVal("Avg", common.FormatFloat(GlobalInfoData.Avg , "%f3K5"))
		GlobalInfoPanel.Damage:SetVal("Max", common.FormatFloat(GlobalInfoData.Max , "%f3K5"))
		GlobalInfoPanel.Percent:SetVal("Percentage", common.FormatInt(GlobalInfoData.Percentage , "%d"))
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
	if c and fight and not self.Hovering and avatar.IsExist() and c.ID == avatar.GetId() then
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
		height = y + 18 + #lines * 18 + 20
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
		self.DetailsPanel.GlobalInfoList[extraIndex] = TSpellDetailsPanelGUI:CreateNewObjectByDesc(wtName, spellInfoPanelDesc, self.DetailsPanel)
		self.DetailsPanel.GlobalInfoList[extraIndex]:SetPosition(22, GlobalInfoOffset + (extraIndex-1) * 18)
	end

	-- SpellHeader
	local spellHeaderOffset = GlobalInfoOffset + EXTRATYPES * 18 + 7
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
