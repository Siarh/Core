--------------------------------------------------------------------------------
-- File: AoUMeterData.lua
-- Desc: All classes used to store data
--------------------------------------------------------------------------------

-- Redfine the function
group.IsPlayerInGroup = group.IsPlayerInGroup or group.IsCreatureInGroup

--------------------------------------------------------------------------------
-- Type TValueDetails
Global("TValueDetails", {})
--------------------------------------------------------------------------------
function TValueDetails:CreateNewObject(ID)
	return setmetatable({
			ID = ID,			-- ID of the value
			Type = "",			-- Type of the value
			Count = 0,			-- Count how many input
			Percentage = 0,		-- Inner percentage
			Amount = 0,			-- Total amount cumulated
			Min = -1,			-- Minimum input
			Avg = -1,			-- Average
			Max = -1,			-- Maximum input
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Recalc min, max, avg by adding a new value
--------------------------------------------------------------------------------
function TValueDetails:RecalcDetails(value)
	-- Increment the counter
	self.Count = self.Count + 1
	-- Increase the total damage amount
	self.Amount = self.Amount + value
	-- Update the min
	if (value < self.Min) or (self.Min == -1) then self.Min = value; end
	-- Update the max
	if (value > self.Max) or (self.Max == -1) then self.Max = value; end
	-- Update the average
	self.Avg = math.ceil(self.Amount / self.Count) or 0
end
--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------
function TValueDetails:Reset()
	self.Count = 0
	self.Percentage = 0
	self.Amount = 0
	self.Min = -1
	self.Avg = -1
	self.Max = -1
end
--------------------------------------------------------------------------------
-- Type TTimer
Global("TTimer", {})
--------------------------------------------------------------------------------
function TTimer:CreateNewObject()
	return setmetatable({
			Counter = 0,		-- The counter incremeted each seconds
			IsStarted = false,	-- To know if the timer can be incremented
			LastHitTime = 0		-- The time of the last hit to remove the time after this hit		
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Reset the timer
--------------------------------------------------------------------------------
function TTimer:ResetTimer()
	self.Counter = 0
end
--------------------------------------------------------------------------------
-- Increment the timer
--------------------------------------------------------------------------------
function TTimer:IncrementTimer()
	if self.IsStarted then
		self.Counter = self.Counter + 1
	end
end
--------------------------------------------------------------------------------
-- Start the timer
--------------------------------------------------------------------------------
function TTimer:StartTimer()
	self.IsStarted = true
end
--------------------------------------------------------------------------------
-- Reset the timer
--------------------------------------------------------------------------------
function TTimer:StopTimer()
	self.IsStarted = false
	self.Counter = self.LastHitTime
end
--------------------------------------------------------------------------------
-- Set hit to save the last action time
--------------------------------------------------------------------------------
function TTimer:SetLastHit()
	self.LastHitTime = self.Counter
end
--------------------------------------------------------------------------------
-- Get elapsed time (return a value >= 1)
--------------------------------------------------------------------------------
function TTimer:GetElapsedTime()
	return self.Counter
end
--------------------------------------------------------------------------------
-- Type TDamageSpellData
Global("TDamageSpellData", {})
--------------------------------------------------------------------------------
function TDamageSpellData:CreateNewObject()
	return setmetatable({
			Name = "",					-- Name of the spell
			ID = 0,						-- ID of the spell
			DebugName = "",				-- Debug name of the spell
			Count = 0,					-- Count how many spell input
			Hits = 0,					-- Count how many efficient spell input
			Type = "",					-- Damage type of the spell

			Amount = 0,					-- Total damage amount
			AmountPerSec = 0,			-- Damage per second
			Percentage = 0,				-- Percentage of damage regarding all other damages
			DetailsList = {				-- Damage per type of damage
				[enumHit.Normal]	= TValueDetails:CreateNewObject(enumHit.Normal, "Normal"),
				[enumHit.Critical]	= TValueDetails:CreateNewObject(enumHit.Critical, "Critical"),
				[enumHit.Glancing]	= TValueDetails:CreateNewObject(enumHit.Glancing, "Glancing")
			},

			MissList = {
				[enumMiss.Dodge]	= TValueDetails:CreateNewObject(enumMiss.Dodge, "Dodge"),
				[enumMiss.Miss]		= TValueDetails:CreateNewObject(enumMiss.Miss, "Miss"),
			},

			ResistAmount = 0,				-- Total amount of resist
			ResistPercentage = 0,			-- Percentage of damage resisted regarding all damage
			ResistDetailsList = {			-- Blocked damage per type of blocked damage
				[enumHitBlock.Block]		= TValueDetails:CreateNewObject(enumHitBlock.Block, "Block"),
				[enumHitBlock.Parry]		= TValueDetails:CreateNewObject(enumHitBlock.Parry, "Parry"),
				[enumHitBlock.Barrier]		= TValueDetails:CreateNewObject(enumHitBlock.Barrier, "Barrier"),
				[enumHitBlock.Resist]		= TValueDetails:CreateNewObject(enumHitBlock.Resist, "Resist"),
				[enumHitBlock.Absorb]		= TValueDetails:CreateNewObject(enumHitBlock.Absorb, "Absorb"),
				[enumHitBlock.RunesAbsorb]	= TValueDetails:CreateNewObject(enumHitBlock.RunesAbsorb, "RuneAbsorb"),
				[enumHitBlock.MultAbsorb]	= TValueDetails:CreateNewObject(enumHitBlock.MultAbsorb, "MultAbsorb"),
				[enumHitBlock.Mount]		= TValueDetails:CreateNewObject(enumHitBlock.Mount, "Mount"),
			},
			
			
			GlobalInfoList = {
				[enumGlobalInfo.Determination]		= TValueDetails:CreateNewObject(enumGlobalInfo.Determination, "Determination"),
			}
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Update the data by adding a new value
--------------------------------------------------------------------------------
function TDamageSpellData:ReceiveValuesFromParams(params)
	-- Increment the counter
	self.Count = self.Count + 1;

	-- Increase the total damage amount
	self.Amount = self.Amount + params.amount;

	-- Update the corresponding type of hit
	-- If it's a miss
	if params.isMiss then self.MissList[enumMiss.Miss]:RecalcDetails(params.amount) end

	-- If it's a dodge
	if params.isDodge then self.MissList[enumMiss.Dodge]:RecalcDetails(params.amount) end

	-- If it's not a miss nor a dodge
	if not params.isMiss and not params.isDodge then
		-- Increment the hits counter
		self.Hits = self.Hits + 1;

		-- If it's a critical hit
		if params.isCritical then self.DetailsList[enumHit.Critical]:RecalcDetails(params.amount) end

		-- If it's a glancing hit
		if params.isGlancing then self.DetailsList[enumHit.Glancing]:RecalcDetails(params.amount) end

		-- If it's not a critical hit nor a glancing hit
		if not params.isCritical and not params.isGlancing then self.DetailsList[enumHit.Normal]:RecalcDetails(params.amount) end
	end
	
	
	-- If the hit has been blocked by a shield
	if params.shieldBlock > 0 then self.ResistDetailsList[enumHitBlock.Block]:RecalcDetails(params.shieldBlock) end

	-- If the hit has been parried
	if params.parry > 0 then self.ResistDetailsList[enumHitBlock.Parry]:RecalcDetails(params.parry) end

	-- If the hit went in a barrier
	if params.barrier > 0 then self.ResistDetailsList[enumHitBlock.Barrier]:RecalcDetails(params.barrier) end

	-- If the hit has been resisted
	if params.resist > 0 then self.ResistDetailsList[enumHitBlock.Resist]:RecalcDetails(params.resist) end

	-- If the hit has been absorbed
	if params.absorb > 0 then self.ResistDetailsList[enumHitBlock.Absorb]:RecalcDetails(params.absorb) end

	-- If the hit has been absorbed by the defensive runes
	if params.runesAbsorb > 0 then self.ResistDetailsList[enumHitBlock.RunesAbsorb]:RecalcDetails(params.runesAbsorb) end

	-- If the hit has been absorbed by the mount
	if params.toMount > 0 then self.ResistDetailsList[enumHitBlock.Mount]:RecalcDetails(params.toMount) end

	-- If the hit has been absorbed by a multiplier (buff/debuff)
	if params.multipliersAbsorb ~= 0 then
		-- isHitByDuplex - если получится как то определять удар от двойной расчет для него
		local multipliersAbsorb = params.multipliersAbsorb
		if params.DDOut and IsPlayerOrPet(params.target) or params.DDIn and IsPlayerOrPet(params.source) then 
			local koef = Settings.MagicPVPKoef
			if params.isHitByDuplex then
				koef = 1 - (1 - koef) * 0.5
			end
			local magicAbsorb = koef*(params.amount + params.overallAbsorbedDamage + multipliersAbsorb + params.runesAbsorb)
			self.ResistDetailsList[enumHitBlock.MultAbsorb]:RecalcDetails(multipliersAbsorb-magicAbsorb)
		else
			if params.isHitByDuplex then
				multipliersAbsorb = multipliersAbsorb - (params.amount + params.overallAbsorbedDamage + params.runesAbsorb)
			end
			self.ResistDetailsList[enumHitBlock.MultAbsorb]:RecalcDetails(multipliersAbsorb)
		end
	end
	
	
end
--------------------------------------------------------------------------------
-- Get the total blocked damage acount
--------------------------------------------------------------------------------
function TDamageSpellData:GetResistAmount()
	local res = 0
	for i, BlockDmgDetail in pairs( self.ResistDetailsList ) do
		if BlockDmgDetail.Amount > 0 then
			res = res + BlockDmgDetail.Amount
		end 
	end
	return res
end
--------------------------------------------------------------------------------
-- Recalculate the pourcentage for each type of damage
--------------------------------------------------------------------------------
function TDamageSpellData:CalculateSpellDetailsPercentage()
	for i, DamageDetail in pairs( self.DetailsList ) do
		DamageDetail.Percentage = GetPercentageAt(DamageDetail.Count, self.Hits)
	end

	for i, MissDetail in pairs( self.MissList ) do
		MissDetail.Percentage = GetPercentageAt(MissDetail.Count, self.Count)
	end

	local AllDamage = self.Amount + self:GetResistAmount()
	for i, BlockDmgDetail in pairs( self.ResistDetailsList ) do
		BlockDmgDetail.Percentage = GetPercentageAt(BlockDmgDetail.Amount, AllDamage)
	end
end
--------------------------------------------------------------------------------
-- Type THealSpellData
Global("THealSpellData", {})
--------------------------------------------------------------------------------
function THealSpellData:CreateNewObject()
	return setmetatable({
			Name = "",					-- Name of the spell
			ID = 0,						-- ID of the spell
			DebugName = "",				-- Debug name of the spell
			Count = 0,					-- Count how many spell inpu
			Type = "",					-- Type of the heal

			Amount = 0,					-- Total heal amount
			AmountPerSec = 0,			-- Heal per second
			Percentage = 0,				-- Percentage of heal regarding all other heal spells
			DetailsList = {				-- Heal per type of heal
				[enumHit.Normal]	= TValueDetails:CreateNewObject(enumHit.Normal, "Normal"),
				[enumHit.Critical]	= TValueDetails:CreateNewObject(enumHit.Critical, "Critical"),
				[enumHit.Glancing]	= TValueDetails:CreateNewObject(enumHit.Glancing, "Glancing")
			},

			MissList = {
			},

			ResistAmount = 0,			-- Total of resisted heal amount
			ResistPercentage = 0,		-- Percentage of resisted heal regarding the total heal amount
			ResistDetailsList = {		-- Resisted heal per type of resisted
				[enumHealResist.Resisted]		= TValueDetails:CreateNewObject(enumHealResist.Resisted, "Resisted"),
				[enumHealResist.RuneResisted]	= TValueDetails:CreateNewObject(enumHealResist.RuneResisted, "RuneResisted"),
				[enumHealResist.Absorbed]		= TValueDetails:CreateNewObject(enumHealResist.Absorbed, "Absorbed"),
				[enumHealResist.Overload]		= TValueDetails:CreateNewObject(enumHealResist.Overload, "Overload"),
			},

			GlobalInfoList = {
				[enumGlobalInfo.Determination]		= TValueDetails:CreateNewObject(enumGlobalInfo.Determination, "Determination"),
			}
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Update the data by adding a new value
--------------------------------------------------------------------------------
function THealSpellData:ReceiveValuesFromParams(params)
	local HealDetails

	-- Increment the counter
	self.Count = self.Count + 1;

	-- Increase the total heal amount
	self.Amount = self.Amount + params.heal;

	-- Update the corresponding type of heal
	-- If it's a critical hit
	if params.isCritical then self.DetailsList[enumHit.Critical]:RecalcDetails(params.heal) end

	-- If it's a glancing hit
	if params.isGlancing then self.DetailsList[enumHit.Glancing]:RecalcDetails(params.heal) end

	-- If it's not a critical hit nor a glancing hit
	if not params.isCritical and not params.isGlancing then self.DetailsList[enumHit.Normal]:RecalcDetails(params.heal) end

	-- Update the resists
	-- If the heal has been resisted
	if params.resisted > 0 then self.ResistDetailsList[enumHealResist.Resisted]:RecalcDetails(params.resisted) end

	-- If the hit has been parried
	if params.runeResisted > 0 then self.ResistDetailsList[enumHealResist.RuneResisted]:RecalcDetails(params.runeResisted) end

	-- If the hit went in a absorbed
	if params.absorbed > 0 then self.ResistDetailsList[enumHealResist.Absorbed]:RecalcDetails(params.absorbed) end
	
	
	

	-- If the hit went in a overload
	if params.overload > 0 then self.ResistDetailsList[enumHealResist.Overload]:RecalcDetails(params.overload) end

	-- The amount of the wounds
	--if params.lethality > 0 then self.GlobalInfoList[enumGlobalInfo.Lethality]:RecalcDetails(params.lethality) end
end
--------------------------------------------------------------------------------
-- Get the total resisted heal acount
--------------------------------------------------------------------------------
function THealSpellData:GetResistAmount()
	local res = 0
	for i, ResistHealDetail in pairs( self.ResistDetailsList ) do
		res = res + ResistHealDetail.Amount
	end
	return res
end
--------------------------------------------------------------------------------
-- Recalculate the pourcentage for each type of heal
--------------------------------------------------------------------------------
function THealSpellData:CalculateSpellDetailsPercentage()
	for i, HealDetail in pairs( self.DetailsList ) do
		HealDetail.Percentage = GetPercentageAt(HealDetail.Count, self.Count)
	end

	local AllHeal = self.Amount + self:GetResistAmount();
	for i, ResistHealDetail in pairs( self.ResistDetailsList ) do
		ResistHealDetail.Percentage = GetPercentageAt(ResistHealDetail.Amount, AllHeal)
	end
end
--------------------------------------------------------------------------------
-- Type TCombatantData
Global("TCombatantData", {})
--------------------------------------------------------------------------------
function TCombatantData:CreateNewObject()
	return setmetatable({
			Amount = 0,						-- Total amount
			AmoutPerSec = 0,				-- Amount per second
			Percentage = 0,					-- Percentage of amount regarding the rest of the group / raid
			LeaderPercentage = 0,			-- Percentage of amount regarding the top one in the group / raid
			SpellsList = {},				-- List of spells used
			GlobalInfoList = {               -- List of extra info such as Determination, Cruauty
				[enumGlobalInfo.Determination] = TValueDetails:CreateNewObject(enumGlobalInfo.Determination, "Determination"), -- Determination level
			},
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Type TCombatant
Global("TCombatant", {})
--------------------------------------------------------------------------------
function TCombatant:CreateNewObject(member)
	local pet = IsPlayer(member.id) and (group.IsPlayerInGroup(member.id) or member.id == avatar.GetId())
	and unit.GetActivePet(member.id) and object.GetName(unit.GetActivePet(member.id)) or nil
	local isNear = (member.id == avatar.GetId() or member.state and (member.state == GROUP_MEMBER_STATE_NEAR or member.state == GROUP_MEMBER_STATE_MERC or member.state == RAID_MEMBER_STATE_NEAR)) and true or false

	return setmetatable({
			ID = member.id,				-- ID of the combatant
			PersistentID = member.persistentId,			-- ID of the combatant
			Name = member.name,			-- Name of the combatant
			Class = member.className or "UNKNOWN",		-- Class of the combatant
			Pet = pet,					-- Pet of the combatant if any
			IsNear = isNear,			-- To know whether the combatant is near (can retrieve data)
			Range = 0,					-- Range of the combatant according to the avatar
			Data = {					-- Data (Dps, Hps, Def)
				[enumMode.Dps]	= TCombatantData:CreateNewObject(),
				[enumMode.Hps]	= TCombatantData:CreateNewObject(),
				[enumMode.Def]	= TCombatantData:CreateNewObject(),
				[enumMode.IHps]	= TCombatantData:CreateNewObject()
			},
			SortValue = 0,			-- value which can represents damage amount, heal amout, ... for sort purpose
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Get spell by identifier = DebugNameType
--------------------------------------------------------------------------------
function TCombatant:GetSpellByIdentifier(aSpellInfo, Mode, params)
	for i, SpellData in pairs( self.Data[Mode].SpellsList ) do
		if SpellData.Identifier == aSpellInfo.Identifier and SpellData.Element == params.sysSubElement then
			return SpellData
		end
	end
	return nil
end
--------------------------------------------------------------------------------
-- Get extra info by index
--------------------------------------------------------------------------------
function TCombatant:GetGlobalInfoByIndex(index, mode)
	return self.Data[mode].GlobalInfoList[index]
end
--------------------------------------------------------------------------------
-- Get spell by index
--------------------------------------------------------------------------------
function TCombatant:GetSpellByIndex(index, mode)
	return self.Data[mode].SpellsList[index]
end
--------------------------------------------------------------------------------
-- Update Global Info
--------------------------------------------------------------------------------
function TCombatant:UpdateGlobalInfo(params, determination, mode)
	self.Data[mode].GlobalInfoList[enumGlobalInfo.Determination]:RecalcDetails(determination)
	self.Data[mode].GlobalInfoList[enumGlobalInfo.Determination].Percentage = self.Data[mode].GlobalInfoList[enumGlobalInfo.Determination].Avg
end
--------------------------------------------------------------------------------
-- Add a new spell to the list
--------------------------------------------------------------------------------
function TCombatant:AddNewSpell(SpellInfo, Mode, params)
	if SpellInfo then
		local SpellData
		if Mode == enumMode.Dps or Mode == enumMode.Def then
			SpellData = TDamageSpellData:CreateNewObject()
		elseif Mode == enumMode.Hps or Mode == enumMode.IHps  then
			SpellData = THealSpellData:CreateNewObject()
		end
		if SpellData then

			--  * Id: the id of the spell
			--  * Identfier: an identifier composed by Name + Element in order to identify uniquely
			--  * Name: name of the spell (wstring)
			--  * IsPet: to know whether if the spell is coming from the pet
			--  * Element: "ENUM_SubElement_..."
			--  * Type: "Spell", "Attack", "Barrier", "Dot", "Exploit", "mapModifier", "Other"
			--  * Source: "Spell", "Buff", "Ability"
			--  * TextureId: texture Id or nil it not exists

			SpellData.Prefix = SpellInfo.IsPet and userMods.ToWString(StrPet .. " - ") or userMods.ToWString("")
			SpellData.Name = SpellInfo.Name
			SpellData.Suffix = SpellInfo.Suffix
			SpellData.Element = params.sysSubElement
			SpellData.Identifier = SpellInfo.Identifier
			SpellData.ID = SpellInfo.Id
			--SpellData.TextureId = SpellInfo.TextureId

			table.insert(self.Data[Mode].SpellsList, SpellData)
			return SpellData
		end
	end
end
--------------------------------------------------------------------------------
-- Clear the spell list and data
--------------------------------------------------------------------------------
function TCombatant:ClearData()
	for i, Data in pairs( self.Data ) do
		Data.Amount = 0
		Data.AmountPerSec = 0
		Data.Percentage = 0
		Data.LeaderPercentage = 0
		Data.SpellsList = {}
		Data.GlobalInfoList[enumGlobalInfo.Determination]:Reset()
		Data.Opt = nil
	end
end
--------------------------------------------------------------------------------
-- Compare spell by amount
--------------------------------------------------------------------------------
local function CompareSpells(A, B)
	return A.Amount > B.Amount
end
--------------------------------------------------------------------------------
-- Sort the spell list by damage amount
--------------------------------------------------------------------------------
function TCombatant:SortSpellByAmount(Mode)
	table.sort(self.Data[Mode].SpellsList, CompareSpells)
end
--------------------------------------------------------------------------------
-- Calculate the damage, DPS, HPS, according to the fight time
--------------------------------------------------------------------------------
function TCombatant:CalculateSpell(FightTime, Mode)
	if not (FightTime > 0) then FightTime = 1 end
	for i, SpellData in pairs( self.Data[Mode].SpellsList ) do
		SpellData.ResistAmount = SpellData:GetResistAmount()
		SpellData.AmountPerSec = SpellData.Amount / FightTime
		SpellData.Percentage = GetPercentageAt(SpellData.Amount, self.Data[Mode].Amount)
		SpellData:CalculateSpellDetailsPercentage()
		SpellData.ResistPercentage = GetPercentageAt(SpellData.ResistAmount, (SpellData.Amount + SpellData.ResistAmount))
		if Mode == enumMode.Dps or Mode == enumMode.Def then
			SpellData.ResistPercentage = SpellData.ResistPercentage ~= 0 and -1 * SpellData.ResistPercentage or SpellData.ResistPercentage
		end
	end
	self:SortSpellByAmount(Mode)
end
--------------------------------------------------------------------------------
-- Update information of a combatant
--------------------------------------------------------------------------------
function TCombatant:UpdateCombatant(member)
	if member.state then
		self.IsNear = (member.id == avatar.GetId() or (member.state == GROUP_MEMBER_STATE_NEAR or member.state == RAID_MEMBER_STATE_NEAR or member.state == GROUP_MEMBER_STATE_MERC)) and true or false
	end
	if member.id then self.ID = member.id end
	if member.persistentId then self.PersistentID = member.persistentId end
	if member.name then self.Name = member.name end
	if member.className then self.Class = member.className end
	self.Pet = IsPlayer(member.id) and (group.IsPlayerInGroup(member.id) or member.id == avatar.GetId())
	and unit.GetActivePet(member.id) and object.GetName(unit.GetActivePet(member.id)) or nil
end
--------------------------------------------------------------------------------
-- Update the Range attribute according to the avatar
--------------------------------------------------------------------------------
function TCombatant:UpdateRange()	
	if self.ID == avatar.GetId() then
		self.Range = 0
	else
		local pos = nil
		if self.ID and object.IsExist(self.ID) then
			pos = object.GetPos(self.ID)
		end

		self.Range = PosRange(avatar.GetPos(), pos)
	end
end
--------------------------------------------------------------------------------
-- Is the combatant close to the avatar
--------------------------------------------------------------------------------
function TCombatant:IsClose()
	return self.IsNear and self.Range <= Settings.CloseDist
end
--------------------------------------------------------------------------------
-- Type TFightData
Global("TFightData", {})
--------------------------------------------------------------------------------
function TFightData:CreateNewObject()
	return setmetatable({
			Amount = 0,			-- Total amount in the fight
			AmountPerSec = 0	-- Amount per second
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Type TFight
Global("TFight", {})
--------------------------------------------------------------------------------
function TFight:CreateNewObject(ID)
	return setmetatable({
			ID = ID,							-- ID of the fight
			Timer = TTimer:CreateNewObject(),	-- Timer of the fight
			Data = {							-- Data (Dps, Hps, Def)
				[enumMode.Dps]	= TFightData:CreateNewObject(),
				[enumMode.Hps]	= TFightData:CreateNewObject(),
				[enumMode.Def]	= TFightData:CreateNewObject(),
				[enumMode.IHps]	= TFightData:CreateNewObject()
			},
			CombatantsList = {},	-- List of combatants
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Add a new combatant
--------------------------------------------------------------------------------
function TFight:AddNewCombatant(member)
	local Combatant = self:GetCombatant(member)
	if not Combatant then
		table.insert(self.CombatantsList, TCombatant:CreateNewObject(member))
		Combatant = self.CombatantsList[table.getn(self.CombatantsList)]
	end
	return Combatant
end
--------------------------------------------------------------------------------
-- Remove a combatant
--------------------------------------------------------------------------------
function TFight:RemoveCombatant(member)
	local Combatant, index = self:GetCombatant(member)

	if index then
		table.remove(self.CombatantsList, index)
	end
end
--------------------------------------------------------------------------------
-- Update a combatant
--------------------------------------------------------------------------------
function TFight:UpdateCombatant(member)
	local Combatant = self:GetCombatant(member)
	if Combatant then
		Combatant:UpdateCombatant(member)
		return Combatant
	end
end
--------------------------------------------------------------------------------
-- Get a combatant
--------------------------------------------------------------------------------
function TFight:GetCombatant(member)
	if not member then return nil end
	if member.persistentId then
		for i, Combatant in pairs( self.CombatantsList ) do
			if Combatant.PersistentID == member.persistentId then
				return Combatant, i -- Players should fall here (after 5.0.1)
			end
		end
	end
	if member.id then
		for i, Combatant in pairs( self.CombatantsList ) do
			if Combatant.ID == member.id then
				return Combatant, i -- Mercenaries should fall here
			end
		end
	end
	if member.name then
		for i, Combatant in pairs( self.CombatantsList ) do
			if IsThisStringValue(Combatant.Name, member.name) then
				return Combatant, i
			end
		end
	end

	return nil
end
--------------------------------------------------------------------------------
-- Get combatant by index
--------------------------------------------------------------------------------
function TFight:GetCombatantByIndex(Index)
	return self.CombatantsList[Index]
end
--------------------------------------------------------------------------------
-- Get combatant info (id, persistentId & name) by index
--------------------------------------------------------------------------------
function TFight:GetCombatantInfoByIndex(Index)
	local Combatant = self.CombatantsList[Index]
	if Combatant then
		local toReturn = {}
		toReturn.id = Combatant.ID
		toReturn.persistentId = Combatant.PersistentID
		toReturn.name = Combatant.Name
		return toReturn
	end
	return nil
end
--------------------------------------------------------------------------------
-- Get combatant count
--------------------------------------------------------------------------------
function TFight:GetCombatantCount()
	return table.getn(self.CombatantsList) or 0
end
--------------------------------------------------------------------------------
-- Start the fight
--------------------------------------------------------------------------------
function TFight:StartFight()
	self.Timer:StartTimer()
end
--------------------------------------------------------------------------------
-- Stop the fight
--------------------------------------------------------------------------------
function TFight:StopFight()
	self.Timer:StopTimer()
end
--------------------------------------------------------------------------------
-- Clear all data for combatant
--------------------------------------------------------------------------------
function TFight:ResetFight()
	for i, Combatant in pairs( self.CombatantsList ) do
		Combatant:ClearData()
	end
	for i, data in pairs( self.Data ) do
		data.Amount = 0
		data.AmoutPerSec = 0
	end
	self.Timer:ResetTimer()
end
--------------------------------------------------------------------------------
-- Increment the fight time of the fight and the inner fight time for all combatant
--------------------------------------------------------------------------------
function TFight:IncrementFightTime()
	self.Timer:IncrementTimer()
end
--------------------------------------------------------------------------------
-- Compare combatant by damage amount
--------------------------------------------------------------------------------
local function CompareCombatantsBySortValue(A, B)
	if A.SortValue == B.SortValue then
		return common.CompareWString(A.Name, B.Name) == -1 end
	return A.SortValue > B.SortValue
end
--------------------------------------------------------------------------------
-- Sort combatant by SortValue. This value is update in TFight:RecalculateCombatantsData(Mode)
-- It can be damage amount, heal amout, ...
--------------------------------------------------------------------------------
function TFight:SortCombatantsBySortValue(Mode)
	table.sort(self.CombatantsList, CompareCombatantsBySortValue)
	local ImbaCombatant = self.CombatantsList[1]
	if ImbaCombatant then
		local LeaderAmount = ImbaCombatant.Data[Mode].Amount
		for i, Combatant in pairs( self.CombatantsList ) do
			Combatant.Data[Mode].LeaderPercentage = GetPercentageAt(Combatant.Data[Mode].Amount, LeaderAmount)
		end
	end
end
--------------------------------------------------------------------------------
-- Recalculate combatant data according to the inner fight time
--------------------------------------------------------------------------------
function TFight:RecalculateCombatantsData(Mode)
	local FightTime = self.Timer:GetElapsedTime()
	if not (FightTime > 0) then FightTime = 1 end
	-- Calculate the total amount
	self.Data[Mode].Amount = 0
	for i, Combatant in pairs( self.CombatantsList ) do
		self.Data[Mode].Amount = self.Data[Mode].Amount + Combatant.Data[Mode].Amount
		Combatant.SortValue = Combatant.Data[Mode].Amount
	end
	-- Calculate the total amount per second
	self.Data[Mode].AmountPerSec = self.Data[Mode].Amount / FightTime
	-- For each combatant, calculate DPS and damage amount
	for i, Combatant in pairs( self.CombatantsList ) do
		Combatant.Data[Mode].AmountPerSec = Combatant.Data[Mode].Amount / FightTime
		Combatant.Data[Mode].Percentage = GetPercentageAt(Combatant.Data[Mode].Amount, self.Data[Mode].Amount)
	end

	self:SortCombatantsBySortValue(Mode)
end
--------------------------------------------------------------------------------
-- Type TUMeter
Global("TUMeter", {})
--------------------------------------------------------------------------------
function TUMeter:CreateNewObject()
	return setmetatable({
			FightsList = {},			-- List of fight ([1]=Total, [2]=Previous, [3+]=Current)
			bCollectData = false,		-- If we must collect data or not (are we in fight or not)
			Fight = { Total = nil, Current = nil, Previous = nil },	-- index of remarquable fight
			OffBattleTime = 0,          -- Off-time battle allows to retrieve data coming just after the end of the fight (the events seems to not arrive in the correct order)
		}, { __index = self })
end
--------------------------------------------------------------------------------
-- Begin a new fight
--------------------------------------------------------------------------------
function TUMeter:AddNewFight()
	table.insert(self.FightsList, TFight:CreateNewObject(table.getn(self.FightsList) + 1))
	return table.getn(self.FightsList)
end
--------------------------------------------------------------------------------
-- Get fight by ID
--------------------------------------------------------------------------------
function TUMeter:GetFight(ID)
	return self.FightsList[ID]
end
--------------------------------------------------------------------------------
-- Add a new combatant
--------------------------------------------------------------------------------
function TUMeter:AddNewCombatant(member)
	self.FightsList[self.Fight.Current]:AddNewCombatant(member):UpdateRange()
	self.FightsList[self.Fight.Total]:AddNewCombatant(member)
end
--------------------------------------------------------------------------------
-- Remove combatant by name
--------------------------------------------------------------------------------
function TUMeter:RemoveCombatant(member)
	self.FightsList[self.Fight.Current]:RemoveCombatant(member)
	self.FightsList[self.Fight.Total]:RemoveCombatant(member)
end
--------------------------------------------------------------------------------
-- Update combatant by ID
--------------------------------------------------------------------------------
function TUMeter:UpdateCombatant(member)
	self.FightsList[self.Fight.Current]:UpdateCombatant(member):UpdateRange()
	self.FightsList[self.Fight.Total]:UpdateCombatant(member)
end
--------------------------------------------------------------------------------
-- Add or Update combatant
--------------------------------------------------------------------------------
function TUMeter:UpdateOrAddCombatant(member)
	if not self.FightsList[self.Fight.Current]:GetCombatant(member) then
		self:AddNewCombatant(member)
	else
		self:UpdateCombatant(member)
	end
end
--------------------------------------------------------------------------------
-- Regen (add or update) combatant list
--------------------------------------------------------------------------------
function TUMeter:RegenCombatantList()
	-- Add member who are currently in the party
	local member = {}
	member.id = avatar.GetId()
	member.name = object.GetName(member.id)
	member.className = avatar.GetClass()
	self:UpdateOrAddCombatant(member)

	local partyMembersInfoList = GetPartyMembers()
	for i, member in pairs( partyMembersInfoList ) do
		self:UpdateOrAddCombatant(member)
	end
end
--------------------------------------------------------------------------------
-- Update the position of all members
--------------------------------------------------------------------------------
function TUMeter:UpdateCombatantPos()
	local currentFight = DPSMeterGUI.DPSMeter:GetFight(DPSMeterGUI.DPSMeter.Fight.Current)
	for i, member in pairs( GetPartyMembers() ) do
		if member.id then
			local combatant
			combatant = currentFight:GetCombatant(member)
			if combatant then
				combatant:UpdateRange()
			end
		end
	end
end
--------------------------------------------------------------------------------
-- Get source Id and variant of the given ID:
--  If it's player
--------------------------------------------------------------------------------
function TUMeter:GetSourceIdAndVariant(ID)
	if not IsFriend(ID) then return end

	local Variant = nil
	local CombatantID = nil
	-- look for the type of the source
	if unit.IsPlayer(ID) or group.IsCreatureInGroup(ID) then
		for i, C in pairs( self.FightsList[self.Fight.Current].CombatantsList ) do
			if (ID == C.ID) then
				Variant = 1 -- Player or Mercenary.
				CombatantID = C.ID
				break
			end
		end
	elseif unit.GetFollowerMaster(ID) then
		local MasterID = unit.GetFollowerMaster(ID)
		for i, C in pairs( self.FightsList[self.Fight.Current].CombatantsList ) do
			if (MasterID == C.ID) then
				Variant = 2 -- Player's Pet.
				CombatantID = C.ID
				break
			end
		end
	elseif unit.GetRace(ID) and unit.GetRace(ID).creatureRace == 1 then
		for i, C in pairs( self.FightsList[self.Fight.Current].CombatantsList ) do
			if (C.Pet) and (common.CompareWString(object.GetName(ID), C.Pet) == 0) then
				Variant = 3 -- Druid's Minions.
				CombatantID = C.ID
				break
			end
		end
	end

	return CombatantID, Variant
end

local m_buffInfoCache = {}
local m_spellDescCache = {}
local m_abilityInfoCache = {}

function ResetCache()
	m_buffInfoCache = {}
	m_spellDescCache = {}
	m_abilityInfoCache = {}
end

local function GetBuffInfoFromCache(anID)
	if m_buffInfoCache[anID] then
		return m_buffInfoCache[anID]
	end
	m_buffInfoCache[anID] = object.GetBuffInfo(anID)
	return m_buffInfoCache[anID]
end

local function GetSpellDescFromCache(anID)
	if m_spellDescCache[anID] then
		return m_spellDescCache[anID]
	end
	m_spellDescCache[anID] = spellLib.GetDescription(anID)
	return m_spellDescCache[anID]
end

local function GetAbilityInfoFromCache(anID)
	if m_abilityInfoCache[anID] then
		return m_abilityInfoCache[anID]
	end
	m_abilityInfoCache[anID] = avatar.GetAbilityInfo(anID)
	return m_abilityInfoCache[anID]
end

--------------------------------------------------------------------------------
-- Get information of a spell
-- Return SpellInfo, ID
-- SpellInfo:
--  * Id: the id of the spell
--  * Identfier: an identifier composed by Name + Element in order to identify uniquely
--  * Name: name of the spell (wstring)
--  * IsPet: to know whether if the spell is coming from the pet
--  * Element: "ENUM_SubElement_..."
--  * Type: "Spell", "Attack", "Barrier", "Dot", "Exploit", "mapModifier", "Other"
--  * Source: "Spell", "Buff", "Ability"
--  * TextureId: texture Id or nil it not exists
--------------------------------------------------------------------------------
function GetSpellInfoFromParams(params)
	if params then
      
		local spellInfo = {}
		
		-- Name
		spellInfo.Name =
		params.ability and not common.IsEmptyWString(params.ability) and params.ability
		or params.sourceName and not common.IsEmptyWString(params.sourceName) and params.sourceName
		or nil
		-- read info only if spellInfo.Name is nil
		if spellInfo.Name == nil then
			local buffInfo = params.buffId and GetBuffInfoFromCache(params.buffId) or nil
			local spellId = params.spellId or buffInfo and buffInfo.producer.spellId or nil
			local spellDesc = spellId and GetSpellDescFromCache(spellId) or nil
			local abilityInfo = params.abilityId and GetAbilityInfoFromCache(params.abilityId) or nil

			-- Returns if no information found
			if not spellDesc and not buffInfo and not abilityInfo then 
				if params.damageSource ~= "DamageSource_BARRIER" then
					return nil
				end 
			end
			
			spellInfo.Name = buffInfo and not common.IsEmptyWString(buffInfo.name) and buffInfo.name
			or spellDesc and not common.IsEmptyWString(spellDesc.name) and spellDesc.name
			or abilityInfo and not common.IsEmptyWString(abilityInfo.name) and abilityInfo.name
			or userMods.ToWString("?")
		end

		-- Id
		spellInfo.Id =
		params.spellId or params.buffId or params.abilityId

		-- Type
		spellInfo.Type = params.damageSource

		local typeElemForId = ""
		if spellInfo.Type == "DamageSource_DAMAGEPOOL" then
			spellInfo.Suffix = userMods.ToWString(" (" .. StrDamagePool .. ")")
			typeElemForId = "p"
		elseif spellInfo.Type == "DamageSource_BARRIER" then
			spellInfo.Suffix = userMods.ToWString(" (" .. StrFromBarrier .. ")")
			typeElemForId = "b"
		else
			spellInfo.Suffix = userMods.ToWString("")
		end

		local sourceId = params.source or params.healerId or nil

		if sourceId and object.IsExist(sourceId) and object.IsUnit(sourceId) then
			spellInfo.IsPet =  unit.IsPet(sourceId)
			spellInfo.Determination = unit.GetRage(sourceId)
		else
			spellInfo.IsPet = false
			spellInfo.Determination = nil
		end
		params.IsPet = spellInfo.IsPet
		-- Identifier: to sort spells by name + damageSource + isPet
		spellInfo.Identifier = (spellInfo.IsPet and "1" or "0") .. typeElemForId .. userMods.FromWString(spellInfo.Name)

		return spellInfo
	end
end
--------------------------------------------------------------------------------
-- Should we collect data the fight
--	Condition: the avatar is in combat
--------------------------------------------------------------------------------
function TUMeter:ShouldCollectData()
	if object.IsInCombat(avatar.GetId()) then
		return true
	end

	-- Should parse all other fighters ?
	for i, Combatant in pairs( self.FightsList[self.Fight.Current].CombatantsList ) do
		if Combatant.ID and object.IsExist(Combatant.ID) and Combatant:IsClose() and object.IsInCombat(Combatant.ID) then
			return true
		end
	end

	return false
end
--------------------------------------------------------------------------------
-- Collect damage data from event EVENT_UNIT_DAMAGE_RECEIVED
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Collect damage dealed data by someone in the party
--------------------------------------------------------------------------------
function TUMeter:CollectDamageDealedData(params)
	local Variant = nil
	local CombatantID = nil

	-- look for the type of the source
	CombatantID, Variant = self:GetSourceIdAndVariant(params.source)

	-- If the source is not part of the group or the target is an ally
	if (not CombatantID) or (not Settings.FriendlyShot and IsFriend(params.target)) then return end

	-- If we're not collecting data, means we are not currently in fight, then start a new one
	if (not self.bCollectData) and (self:ShouldCollectData() or params.lethal) then
		self:Start()
	end

	if not self.bCollectData then return end

	-- update last hit time
	self.FightsList[self.Fight.Current].Timer:SetLastHit()
	self.FightsList[self.Fight.Total].Timer:SetLastHit()

	-- if collecting dps data
	local SpellInfo = GetSpellInfoFromParams(params)

	if SpellInfo then
		-- Update damage amount in the current fight
		self:UpdateData(self.Fight.Current, CombatantID, enumMode.Dps, params, SpellInfo)

		-- Update damage amount in the overall fight
		self:UpdateData(self.Fight.Total, CombatantID, enumMode.Dps, params, SpellInfo)

		return true
	end
end
--------------------------------------------------------------------------------
-- Collect damage received data by someone in the party
--------------------------------------------------------------------------------
function TUMeter:CollectDamageReceivedData(params)
	local CombatantID = nil
	local Variant = nil

	-- look for the type of the target
	CombatantID, Variant = self:GetSourceIdAndVariant(params.target)

	if not CombatantID or not (Variant == 1) then return end

	if not self.bCollectData and self:ShouldCollectData() then
		self:Start()
	end

	if not self.bCollectData then return end

	local SpellInfo = GetSpellInfoFromParams(params)

	if SpellInfo then
		-- Update damage amount in the current fight
		self:UpdateData(self.Fight.Current, CombatantID, enumMode.Def, params, SpellInfo)

		-- Update damage amount in the overall fight
		self:UpdateData(self.Fight.Total, CombatantID, enumMode.Def, params, SpellInfo)

		return true
	end
end

--------------------------------------------------------------------------------
-- Collect heal data from event EVENT_HEALING_RECEIVED
--------------------------------------------------------------------------------
function TUMeter:CollectHealData(params)
	if not Settings.ModeHPS and not Settings.ModeIHPS or not IsFriend(params.unitId) or params.isFall then
		return
	end

	-- Check that the healer is part of the group
	local CombatantID = nil
	local Variant = nil

	CombatantID, Variant = self:GetSourceIdAndVariant(params.healerId)

	-- if this happen, most probably it's a bloodlust but the heal is coming from the target...
	if not CombatantID then
		CombatantID, Variant = self:GetSourceIdAndVariant(params.unitId)
	end

	if not CombatantID then return end

	if not self.bCollectData and self:ShouldCollectData() then
		self:Start()
	end

	if not self.bCollectData then return end

	-- update last hit time
	self.FightsList[self.Fight.Current].Timer:SetLastHit()

	params.amount = params.heal
	local SpellInfo = GetSpellInfoFromParams(params)

	if SpellInfo then
		-- Update heal amount in the current fight
		self:UpdateData(self.Fight.Current, CombatantID, enumMode.Hps, params, SpellInfo)

		-- Update heal amount in the overall fight
		self:UpdateData(self.Fight.Total, CombatantID, enumMode.Hps, params, SpellInfo)	
		return true
	end
end

function TUMeter:CollectHealDataIN(params)
	if not Settings.ModeHPS and not Settings.ModeIHPS or not IsFriend(params.unitId) or params.isFall then
		return
	end

	-- Check that the healer is part of the group
	local CombatantID = nil
	local Variant = nil

	CombatantID, Variant = self:GetSourceIdAndVariant(params.unitId)

	if not CombatantID then return end

	if not self.bCollectData and self:ShouldCollectData() then
		self:Start()
	end

	if not self.bCollectData then return end

	-- update last hit time
	self.FightsList[self.Fight.Current].Timer:SetLastHit()

	params.amount = params.heal
	local SpellInfo = GetSpellInfoFromParams(params)

	if SpellInfo then
		self:UpdateData(self.Fight.Current, CombatantID, enumMode.IHps, params, SpellInfo)
		self:UpdateData(self.Fight.Total, CombatantID, enumMode.IHps, params, SpellInfo)		
		return true
	end
end
--------------------------------------------------------------------------------
-- Update the data in the given mode
--------------------------------------------------------------------------------
function TUMeter:UpdateData(fightId, combatantID, mode, params, spellInfo)
	local Fight = self.FightsList[fightId]

	local member = {}
	member.id = combatantID
	local Combatant = Fight:GetCombatant(member)

	if Combatant and Combatant:IsClose() then -- don't record data from combatant too far
		-- Analytics runs once per event in the current fight and receives the real combatant.
		if fightId == self.Fight.Current and AOUA and type(AOUA.OnHit) == "function" then
			pcall(AOUA.OnHit, Combatant, mode, params, spellInfo and spellInfo.Determination, spellInfo)
		end
		Combatant.Data[mode].Amount = Combatant.Data[mode].Amount + params.amount

		if spellInfo then
			local SpellData = Combatant:GetSpellByIdentifier(spellInfo, mode, params)
			if not SpellData then
				SpellData = Combatant:AddNewSpell(spellInfo, mode, params)
			end

			if SpellData then
				SpellData:ReceiveValuesFromParams(params)
				Fight.Timer:SetLastHit()
			end

			if spellInfo.Determination then
				Combatant:UpdateGlobalInfo(params, spellInfo.Determination, mode)
			end

			-- Stat optimizer: collect target health and Resolve for each hit
			if Optim and Optim.OnHit then
				pcall(Optim.OnHit, Combatant, mode, params, spellInfo.Determination)
			end
		end
	end
end
--------------------------------------------------------------------------------
-- Start combat
--------------------------------------------------------------------------------
function TUMeter:Start()
	self:CopyFightFromCurrenToPrev()

	self:ResetFight(self.Fight.Current)
    
    if AOUA and type(AOUA.OnFightStart) == "function" then
        pcall(AOUA.OnFightStart)
    end

    self:RegenCombatantList()

	self.FightsList[self.Fight.Current]:StartFight()
	self.FightsList[self.Fight.Total]:StartFight()

	self.bCollectData = true
	self.OffBattleTime = 0
end
--------------------------------------------------------------------------------
-- Stop combat
--------------------------------------------------------------------------------
function TUMeter:Stop()
	self.bCollectData = false
	self.FightsList[self.Fight.Current]:StopFight()
	self.FightsList[self.Fight.Total]:StopFight()
	-- Persist the separate raw-event history without touching the legacy /aou rec store.
	if AOUA and type(AOUA.OnFightStop) == "function" then
		pcall(AOUA.OnFightStop)
	end
end
--------------------------------------------------------------------------------
-- Update the fight time in second (fight time ++)
--------------------------------------------------------------------------------
function TUMeter:UpdateFightsTime()
	-- Update current fight
	self.FightsList[self.Fight.Current]:IncrementFightTime()
	-- Update overall fight
	self.FightsList[self.Fight.Total]:IncrementFightTime()
	-- Reset the offtime battle
	self.OffBattleTime = 0
end
--------------------------------------------------------------------------------
-- Update the off-time battle and return the new value
--------------------------------------------------------------------------------
function TUMeter:UpdateOffBattleTime()
	self.OffBattleTime = self.OffBattleTime + 1
	return self.OffBattleTime
end
--------------------------------------------------------------------------------
-- Reset all fights
--------------------------------------------------------------------------------
function TUMeter:ResetAllFights(fullReset)
	-- Keep track of previous fights
	local prevTotalFight = self:GetFight(self.Fight.Total)
	local prevPrevFight = self:GetFight(self.Fight.Previous)

	-- Delete fights
	self.FightsList = {}

	-- Recreate new ones
	self.Fight.Total = self:AddNewFight()
	self.Fight.Current = self:AddNewFight()
	self.Fight.Previous = self:AddNewFight()
	self:RegenCombatantList()

	-- Restore previous fights
    if not fullReset then
        if prevTotalFight and prevTotalFight.Data[enumMode.Dps].Amount > 0 then
            self.FightsList[self.Fight.Previous] = prevTotalFight
	   else
            self.FightsList[self.Fight.Previous] = prevPrevFight
	   end
    end
    
	self.bCollectData = false
end
--------------------------------------------------------------------------------
-- Reset specific fight
--------------------------------------------------------------------------------
function TUMeter:ResetFight(ID)
	if ID > 0 then
		self.FightsList[ID]:ResetFight()
	end
end
--------------------------------------------------------------------------------
-- Copy the current fight to the previous fight
--------------------------------------------------------------------------------
function TUMeter:CopyFightFromCurrenToPrev()
	self.FightsList[self.Fight.Previous] = DeepCopyObject(self.FightsList[self.Fight.Current])
end
