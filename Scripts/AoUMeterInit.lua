--------------------------------------------------------------------------------
-- File: AoUMeterInit.lua
-- Desc: Initialize the addon
--------------------------------------------------------------------------------

onMyEvent["EVENT_UNKNOWN_SLASH_COMMAND"] = function(params)
        local ok, converted = pcall(function()
                if not params or params.text == nil then return "" end
                return userMods.FromWString(params.text)
        end)

        if not ok then
                message("DPScope: slash text conversion error")
                return
        end

        local cmdText = tostring(converted or "")

        if Optim and Optim.OnSlash then
                local callOK, handled = pcall(Optim.OnSlash, cmdText)
                if not callOK then
                        message("DPScope slash error: " .. tostring(handled))
                        return
                end
                if handled then return end
        end

        if cmdText == "/plouf" then
                local talentInfo = avatar.GetBaseTalentInfo(1,3)
                LogInfo("TALENT")
                LogInfo("RANK")
                LogTable(talentInfo.ranks[0])
                local spell = spellLib.GetDescription(
                        talentInfo.ranks[0].spellId
                )
                LogInfo("SPELL")
                LogTable(spell)
        end
end

function Init()
	if avatar.IsExist() then
		onGenEvent["EVENT_AVATAR_CREATED"]()
	end

	RegisterEventHandlers(onGenEvent)
    -- Register slash handler directly at addon startup.
    if onMyEvent and onMyEvent["EVENT_UNKNOWN_SLASH_COMMAND"] then
        common.RegisterEventHandler(
            onMyEvent["EVENT_UNKNOWN_SLASH_COMMAND"],
            "EVENT_UNKNOWN_SLASH_COMMAND"
        )
    end
end

Init()