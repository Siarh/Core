--------------------------------------------------------------------------------
-- File: AoUMeterAI.lua
-- Desc: DPScope evidence-based combat advisor and AI command bridge.
--
-- The in-game client has no confirmed outbound HTTP API. This module therefore
-- runs a deterministic local advisor. The optional desktop Ollama/Qwen companion is
-- tools/aou_ai_assistant.py and consumes exported calculator JSON.
--------------------------------------------------------------------------------
Global("DPScopeAI", {})

DPScopeAI.Cfg = { enabled = 1 }
DPScopeAI.LastSummary = nil
DPScopeAI.VERSION = "1.0"

local function n(value)
    local valueN = tonumber(value)
    if valueN == nil then return 0 end
    return valueN
end

local function emit(value)
    local text = tostring(value or "")
    if type(sayLong) == "function" then
        sayLong(text)
    elseif type(message) == "function" then
        message(text)
    end
end

local function configSection()
    if not userMods or not common or
        type(userMods.GetGlobalConfigSection) ~= "function" or
        type(common.GetAddonName) ~= "function" then
        return nil
    end
    local ok, section = pcall(function()
        return userMods.GetGlobalConfigSection(common.GetAddonName())
    end)
    if ok and type(section) == "table" then return section end
    return nil
end

function DPScopeAI.Load()
    local section = configSection()
    if section and section.aou_ai_enabled ~= nil then
        DPScopeAI.Cfg.enabled = (tonumber(section.aou_ai_enabled) == 1) and 1 or 0
    else
        DPScopeAI.Cfg.enabled = 1
    end
end

function DPScopeAI.Save()
    if not userMods or not common or
        type(userMods.GetGlobalConfigSection) ~= "function" or
        type(userMods.SetGlobalConfigSection) ~= "function" or
        type(common.GetAddonName) ~= "function" then
        return false
    end
    local ok = pcall(function()
        local name = common.GetAddonName()
        local section = userMods.GetGlobalConfigSection(name) or {}
        section.aou_ai_enabled = DPScopeAI.Cfg.enabled
        userMods.SetGlobalConfigSection(name, section)
    end)
    return ok
end

function DPScopeAI.IsEnabled()
    return DPScopeAI.Cfg.enabled == 1
end

function DPScopeAI.SetEnabled(value)
    DPScopeAI.Cfg.enabled = value and 1 or 0
    DPScopeAI.Save()
    DPScopeAI.LastSummary = nil
    if Optim and Optim.Memo then Optim.Memo.key = nil end
    return DPScopeAI.IsEnabled()
end

local function phaseEventCount(phases)
    local count = 0
    for i = 1, 4 do
        local phase = phases and phases[i]
        if phase then count = count + n(phase.n) end
    end
    return count
end

local function shortText(value, limit)
    value = tostring(value or "")
    limit = limit or 76
    if #value > limit then return string.sub(value, 1, limit - 3) .. "..." end
    return value
end

local function signedStatFocus(current, recommended)
    local labels = { "M", "R", "Б" }
    local best, bestDelta = nil, 0
    for i = 1, 3 do
        local delta = n(recommended and recommended[i]) - n(current and current[i])
        if math.abs(delta) > math.abs(bestDelta) then
            bestDelta = delta
            best = labels[i]
        end
    end
    if not best or math.abs(bestDelta) < 1 then
        return "Распределение близко к текущему оптимуму модели."
    end
    return string.format("Крупнейший сдвиг оптимизатора: %s %s%d очков.", best,
        bestDelta > 0 and "+" or "", (bestDelta >= 0) and math.floor(bestDelta + 0.5) or math.ceil(bestDelta - 0.5))
end

function DPScopeAI.Analyze(context)
    context = context or {}
    local eventCount = n(context.eventCount)
    local hpSamples = n(context.hpSamples)
    local poolSamples = n(context.poolSamples)
    local hpCoverage = eventCount > 0 and hpSamples / eventCount or 0
    local poolCoverage = eventCount > 0 and poolSamples / eventCount or 0
    local confidence, confidenceScore
    if eventCount >= 100 and hpCoverage >= 0.80 and poolCoverage >= 0.70 then
        confidence, confidenceScore = "высокая", 85
    elseif eventCount >= 30 and hpCoverage >= 0.50 and poolCoverage >= 0.40 then
        confidence, confidenceScore = "средняя", 60
    else
        confidence, confidenceScore = "низкая", 30
    end

    local insight, nextStep
    local mode = context.mode or "dps"
    if eventCount < 30 then
        insight = "Пока мало событий для устойчивого вывода; не меняй сборку по короткому фрагменту боя."
        nextStep = "Собери не менее 30 событий в сопоставимой ротации."
    elseif hpCoverage < 0.50 then
        insight = "У значительной части событий нет пригодного снимка HP цели; оценка Беспощадности ненадёжна."
        nextStep = "Проверь чтение HP цели командой /aou hptest и повтори бой."
    elseif poolCoverage < 0.40 then
        insight = "Пул Решимости записан не для всех событий; сравнение Решимости имеет пониженную надёжность."
        nextStep = "Повтори бой и сравни количество сэмплов /aou stats."
    elseif mode == "hps" then
        local selfAmount = n(context.selfAmount)
        local allyAmount = n(context.allyAmount)
        local total = selfAmount + allyAmount
        local allyShare = total > 0 and allyAmount / total or 0
        local selfShare = total > 0 and selfAmount / total or 0
        if total <= 0 then
            insight = "Нет раздельной статистики получателей лечения в этом фрагменте."
            nextStep = "Проведи бой с лечением себя и союзников, затем проверь HPS-блок."
        elseif allyShare >= 0.70 then
            insight = "Большая часть зарегистрированного лечения направлена союзникам (" ..
                string.format("%.0f%%", allyShare * 100) .. ")."
            nextStep = "Сверь строку HPS союзников с полезным лечением: перелечивание пока может быть неизвестно."
        elseif selfShare >= 0.70 then
            insight = "Большая часть зарегистрированного лечения пришлась на самого персонажа (" ..
                string.format("%.0f%%", selfShare * 100) .. ")."
            nextStep = "Повтори тест с лечением союзника, чтобы отдельно проверить обе выборки."
        else
            insight = "Лечение распределено между собой и союзниками; отдельные HPS-выборки можно сравнивать."
            nextStep = "Сравни качество HP-сэмплов для строк лечения себя и союзников."
        end
        if n(context.estimatedHealSamples) > n(context.measuredHealSamples) then
            nextStep = nextStep .. " Значительная часть HP перед лечением оценочная."
        end
    elseif mode == "tank" then
        if n(context.incomingPerSecond) <= 0 then
            insight = "Нет достаточного входящего урона для оценки выживаемости."
            nextStep = "Проведи бой с устойчивым входящим уроном и повтори /aou defstat."
        else
            insight = "Защитный профиль рассчитан по записанному входящему урону; компоненты поглощения не суммируются."
            nextStep = "Сверь школы урона и качество HP-сэмплов; не меняй резисты по одному типу удара."
        end
    else
        insight = signedStatFocus(context.currentStats, context.recommendedStats)
        if n(context.lowHpEvents) < 5 then
            nextStep = "Для оценки Беспощадности добавь бой с большим числом ударов по целям ниже 50% HP."
        elseif n(context.poolSamples) < 50 then
            nextStep = "Собери ещё один сопоставимый бой, чтобы проверить стабильность пула Решимости."
        else
            nextStep = "Проверь рекомендацию на следующем сопоставимом бою; сравнивай DPS за одинаковую ротацию."
        end
    end

    local summary = string.format(
        "AI %s: %s. События=%d, HP=%d/%d (%.0f%%), Решимость=%d/%d (%.0f%%). %s Следующий шаг: %s",
        confidence, mode == "hps" and "HPS" or (mode == "tank" and "защита" or "УВС"),
        eventCount, hpSamples, eventCount, hpCoverage * 100,
        poolSamples, eventCount, poolCoverage * 100, insight, nextStep
    )
    return {
        confidence = confidence,
        confidenceScore = confidenceScore,
        eventCount = eventCount,
        hpCoverage = hpCoverage,
        poolCoverage = poolCoverage,
        insight = insight,
        nextStep = nextStep,
        summary = summary
    }
end

function DPScopeAI.BuildLines(context)
    if not DPScopeAI.IsEnabled() then return {} end
    local result = DPScopeAI.Analyze(context)
    DPScopeAI.LastSummary = result.summary
    -- Keep the in-window AI payload strictly ASCII. The Allods client renders
    -- localized resource strings safely, while arbitrary runtime UTF-8 text
    -- cannot be passed through the optimizer value cells without mojibake.
    local level = (result.confidence == "высокая" and "HIGH")
        or (result.confidence == "средняя" and "MEDIUM")
        or "LOW"
    local hpText = string.format("HP %.0f%%", result.hpCoverage * 100)
    local poolText = string.format("Resolve %.0f%%", result.poolCoverage * 100)
    return {
        { "OptAITitle", "LOCAL", level, tostring(result.confidenceScore) .. "/100" },
        { "OptAIQuality", tostring(result.eventCount), hpText, poolText },
        { "OptAIInsight", "Use /aou ai advice", "", "" },
        { "OptAIFocus", "Use /aou ai advice", "", "" }
    }
end

function DPScopeAI.OnSlash(args)
    local sub = string.lower(args[3] or "status")
    if sub == "on" then
        DPScopeAI.SetEnabled(true)
        emit("DPScope AI advisor = ON. Local advice will appear in the optimizer block.")
        return true
    elseif sub == "off" then
        DPScopeAI.SetEnabled(false)
        emit("DPScope AI advisor = OFF.")
        return true
    elseif sub == "status" then
        emit("DPScope AI advisor = " .. (DPScopeAI.IsEnabled() and "ON" or "OFF") ..
            "; engine=local evidence rules; OpenAI companion=tools/aou_ai_assistant.py (manual desktop run).")
        return true
    elseif sub == "advice" then
        if not DPScopeAI.IsEnabled() then
            emit("AI advisor is OFF. Use /aou ai on.")
        elseif DPScopeAI.LastSummary then
            emit(DPScopeAI.LastSummary)
        else
            emit("No AI analysis yet. Open your character details after collecting combat data.")
        end
        return true
    elseif sub == "export" then
        if not DPScopeAI.IsEnabled() then
            emit("AI advisor is OFF. Use /aou ai on before AI export.")
        elseif AOUA and type(AOUA.EventExport) == "function" then
            local ok, summary = AOUA.EventExport(1000, 1)
            if ok then
                emit((summary or "Event export page 1 is ready.") ..
                    " Capture this page, then continue with /aou eventfile 1000 2, 3, and so on.")
            else
                emit(summary or "Event export is unavailable.")
            end
        else
            emit("Event export is unavailable.")
        end
        return true
    end
    emit("Commands: /aou ai on|off|status|advice|export")
    return true
end

DPScopeAI.Load()
