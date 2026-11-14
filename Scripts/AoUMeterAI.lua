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

local function statFocus(current, recommended)
    local labels = { "М", "Р", "Бесп." }
    local best, bestDelta = nil, 0
    for i = 1, 3 do
        local delta = n(recommended and recommended[i]) - n(current and current[i])
        if math.abs(delta) > math.abs(bestDelta) then
            bestDelta, best = delta, labels[i]
        end
    end
    if not best or math.abs(bestDelta) < 1 then
        return "Распределение почти оптимально по модели."
    end
    local points = bestDelta > 0 and math.floor(bestDelta + 0.5) or math.ceil(bestDelta - 0.5)
    return "Сдвиг " .. best .. " " .. (points > 0 and "+" or "") .. tostring(points) .. " оч."
end

local function appendSentence(base, extra)
    if not extra or extra == "" then return base end
    if not base or base == "" then return extra end
    return base .. "; " .. extra
end

function DPScopeAI.Analyze(context)
    context = context or {}
    local eventCount = math.max(0, math.floor(n(context.eventCount)))
    local hpSamples = math.max(0, math.floor(n(context.hpSamples)))
    local poolSamples = math.max(0, math.floor(n(context.poolSamples)))
    local hpCoverage = eventCount > 0 and math.min(1, hpSamples / eventCount) or 0
    local poolCoverage = eventCount > 0 and math.min(1, poolSamples / eventCount) or 0
    local mode = context.mode or "dps"

    local confidence, confidenceScore
    if eventCount >= 100 and hpCoverage >= 0.80 and poolCoverage >= 0.70 then
        confidence, confidenceScore = "высокая", 85
    elseif eventCount >= 30 and hpCoverage >= 0.50 and poolCoverage >= 0.40 then
        confidence, confidenceScore = "средняя", 60
    else
        confidence, confidenceScore = "низкая", 30
    end

    local qualityStep
    if eventCount < 30 then
        qualityStep = "Собери 30+ событий в сопоставимом бою."
    elseif hpCoverage < 0.50 then
        qualityStep = "Мало HP-сэмплов: проверь /aou hptest."
    elseif poolCoverage < 0.40 then
        qualityStep = "Мало замеров Решимости: повтори бой."
    end

    local incoming = math.max(0, n(context.incomingPerSecond))
    local selfRate = math.max(0, n(context.selfHealPerSecond))
    local allyRate = math.max(0, n(context.allyHealPerSecond))
    local selfAmount = math.max(0, n(context.selfAmount))
    local allyAmount = math.max(0, n(context.allyAmount))
    local healTotal = selfAmount + allyAmount
    local allyShare = healTotal > 0 and allyAmount / healTotal or 0
    local survivalDelta = tonumber(context.survivalDeltaPct)
    local offenseDelta = tonumber(context.offenseDeltaPct)

    local insight, nextStep
    if mode == "hps" then
        if incoming > 0 and selfRate <= 0 then
            insight = "Входящий урон есть; личный HPS не записан."
        elseif incoming > 0 then
            local coverage = selfRate / incoming
            if coverage < 0.30 then
                insight = "Личный HPS заметно ниже входящего урона."
            elseif coverage < 0.75 then
                insight = "Личное лечение частично покрывает входящий урон."
            else
                insight = "Личный HPS близок к входящему урону."
            end
        elseif healTotal > 0 then
            insight = "Лечение зарегистрировано; входящий урон не обнаружен."
        elseif n(context.totalHealAmount) > 0 then
            insight = "HPS есть, но получатели лечения не определены."
        else
            insight = "В этом фрагменте нет данных о лечении."
        end
        if allyShare >= 0.70 then
            insight = appendSentence(insight, "основной объём HPS уходит союзникам")
        elseif healTotal > 0 and allyShare <= 0.30 then
            insight = appendSentence(insight, "значительная часть HPS направлена себе")
        end
        if offenseDelta then
            insight = appendSentence(insight,
                string.format("HPS-множитель %+.1f%%", offenseDelta))
        end
        if survivalDelta then
            insight = appendSentence(insight,
                string.format("модель живучести %+.1f%%", survivalDelta))
        end
        if qualityStep then
            nextStep = qualityStep
        elseif incoming > 0 and n(context.hpMax) <= 0 then
            nextStep = "Укажи максимум HP: /aou hp N."
        else
            nextStep = "Сверь личный HPS и защиту ещё в двух боях."
        end
    elseif mode == "tank" then
        if incoming <= 0 then
            insight = "Входящий урон не зарегистрирован; защита не оценивается."
        elseif survivalDelta then
            insight = string.format("По модели живучесть изменится на %+.1f%%.", survivalDelta)
        elseif n(context.hpMax) <= 0 then
            insight = "Входящий урон есть, но максимум HP неизвестен."
        else
            insight = "Входящий урон записан; оценка защиты предварительная."
        end
        nextStep = qualityStep or
            ((n(context.hpMax) <= 0) and "Укажи максимум HP: /aou hp N." or
                "Проверь распределение защиты на следующем бою.")
    else
        if eventCount < 30 then
            insight = "Мало событий: надёжный вывод пока невозможен."
        else
            insight = statFocus(context.currentStats, context.recommendedStats)
            if offenseDelta then
                insight = appendSentence(insight,
                    string.format("множитель модели %+.1f%%", offenseDelta))
            end
            if survivalDelta and survivalDelta < -0.5 then
                insight = appendSentence(insight,
                    string.format("живучесть снизится на %.1f%%", math.abs(survivalDelta)))
            end
        end
        if qualityStep then
            nextStep = qualityStep
        elseif n(context.lowHpEvents) < 5 then
            nextStep = "Для U собери больше ударов по целям ниже 50% HP."
        else
            nextStep = "Проверь результат на следующем сопоставимом бою."
        end
    end

    if n(context.estimatedHealSamples) > n(context.measuredHealSamples) and mode == "hps" then
        nextStep = appendSentence(nextStep, "Часть HP до лечения оценочная.")
    end

    local modeName = mode == "hps" and "HPS" or (mode == "tank" and "защита" or "УВС")
    local detail = ""
    if mode == "hps" then
        detail = string.format(" Входящий=%.0f/с, себе=%.0f/с, союзникам=%.0f/с.",
            incoming, selfRate, allyRate)
    elseif mode == "tank" then
        detail = string.format(" Входящий урон=%.0f/с.", incoming)
    end
    local summary = string.format(
        "AI %s (%d/100): %s. Режим=%s, событий=%d, HP=%d/%d (%.0f%%), Решимость=%d/%d (%.0f%%).%s Следующий шаг: %s",
        confidence, confidenceScore, insight, modeName, eventCount,
        hpSamples, eventCount, hpCoverage * 100,
        poolSamples, eventCount, poolCoverage * 100, detail, nextStep or "Собери ещё один сопоставимый бой."
    )

    return {
        confidence = confidence,
        confidenceScore = confidenceScore,
        eventCount = eventCount,
        hpCoverage = hpCoverage,
        poolCoverage = poolCoverage,
        insight = insight,
        nextStep = nextStep or "Собери ещё один сопоставимый бой.",
        summary = summary
    }
end

local function splitCells(value)
    local rest = tostring(value or "")
    local cells = { "", "", "" }
    for slot = 1, 3 do
        rest = string.gsub(rest, "^%s+", "")
        if rest == "" then break end
        if #rest <= 20 then
            cells[slot] = rest
            rest = ""
            break
        end
        local cut = 20
        while cut > 0 do
            local byte = string.byte(rest, cut + 1)
            if not byte or byte < 128 or byte >= 192 then break end
            cut = cut - 1
        end
        local space = nil
        for i = 1, cut do
            if string.byte(rest, i) == 32 then space = i end
        end
        if space and space > 1 then cut = space - 1 end
        if cut < 1 then cut = math.min(#rest, 20) end
        cells[slot] = string.sub(rest, 1, cut)
        rest = string.sub(rest, cut + 1)
    end
    if rest ~= "" then
        cells[3] = string.sub(cells[3], 1, math.max(1, #cells[3] - 3)) .. "..."
    end
    return cells[1], cells[2], cells[3]
end

function DPScopeAI.BuildLines(context)
    if not DPScopeAI.IsEnabled() then return {} end
    local result = DPScopeAI.Analyze(context)
    DPScopeAI.LastSummary = result.summary

    local confidence = result.confidence
    local i1, i2, i3 = splitCells(result.insight)
    local n1, n2, n3 = splitCells(result.nextStep)
    return {
        { "OptAITitle", "LOCAL", confidence, tostring(result.confidenceScore) .. "/100" },
        { "OptAIQuality", tostring(result.eventCount), string.format("HP %.0f%%", result.hpCoverage * 100),
            string.format("RES %.0f%%", result.poolCoverage * 100) },
        { "OptAIInsight", i1, i2, i3 },
        { "OptAIFocus", n1, n2, n3 }
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
            "; engine=local evidence rules; desktop Ollama companion=tools/aou_ai_assistant.py (manual local run).")
        return true
    elseif sub == "advice" then
        if not DPScopeAI.IsEnabled() then
            emit("AI advisor is OFF. Use /aou ai on.")
        elseif DPScopeAI.LastSummary then
            emit(DPScopeAI.LastSummary)
        else
            emit("No AI analysis yet. Open the DPScope details panel after collecting combat data.")
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
