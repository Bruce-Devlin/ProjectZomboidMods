require "AgeConfig"

local DANGER_THRESHOLD = 0.80
local BASE_CHANCE_PER_TEN_MINUTES = 0.02
local MAX_EXTRA_DANGER_CHANCE = 0.06
local CHANCE_PER_YEAR_OVER_DEADLY_AGE = 0.01
local MAX_CHANCE_PER_TEN_MINUTES = 0.30
local HEART_ATTACK_DURATION_MS = 8000

local function forEachPlayer(callback)
    if isServer() then
        local players = getOnlinePlayers()
        for index = 0, players:size() - 1 do
            callback(players:get(index))
        end
        return
    end

    for index = 0, getNumActivePlayers() - 1 do
        callback(getSpecificPlayer(index))
    end
end

local function heartAttackChance(age, deadlyAge, danger)
    local dangerRange = math.max(1 - DANGER_THRESHOLD, 0.01)
    local dangerFactor = math.max(0, math.min((danger - DANGER_THRESHOLD) / dangerRange, 1))
    local extraAge = math.max(age - deadlyAge, 0)

    return math.min(
        BASE_CHANCE_PER_TEN_MINUTES
            + (MAX_EXTRA_DANGER_CHANCE * dangerFactor)
            + (CHANCE_PER_YEAR_OVER_DEADLY_AGE * extraAge),
        MAX_CHANCE_PER_TEN_MINUTES
    )
end

local function startHeartAttack(player, md, age, stress, panic, chance)
    md._GettingOldHeartAttackStartedAt = getTimestampMs()
    md._GettingOldDeathCause = "HeartAttack"
    player:transmitModData()
    if not isServer() then DevTools.saySafe(player, getText("UI_GettingOld_HeartAttack_Speech")) end

    DevTools.debugLog(
        "Getting Old",
        string.format(
            "Heart attack started | Age: %d | Stress: %.3f | Panic: %.3f | Chance: %.3f",
            age,
            stress,
            panic,
            chance
        )
    )
end

local function checkForHeartAttack(player)
    if not player or not player:isAlive() then return end
    if not AgeConfig.areDeadlyAgeHeartAttacksEnabled() then return end

    local deadlyAge = AgeConfig.getDeadlyAge()
    if deadlyAge <= 0 then return end

    local md = player:getModData()
    local age = tonumber(md.Age)
    if not age or age < deadlyAge then return end
    if md._GettingOldHeartAttackStartedAt then return end

    local stats = player:getStats()
    local stress = stats:get(CharacterStat.STRESS)
    -- Panic uses a 0-100 scale while stress uses 0-1. Horde terror raises
    -- panic, so consider whichever danger signal is currently stronger.
    local panic = stats:get(CharacterStat.PANIC) / 100
    local danger = math.max(stress, panic)
    if danger < DANGER_THRESHOLD then return end

    local chance = heartAttackChance(age, deadlyAge, danger)
    if ZombRandFloat(0, 1) < chance then
        startHeartAttack(player, md, age, stress, panic, chance)
    end
end

local function finishHeartAttack(player)
    if not player or not player:isAlive() then return end

    local md = player:getModData()
    local startedAt = tonumber(md._GettingOldHeartAttackStartedAt)
    if not startedAt or getTimestampMs() - startedAt < HEART_ATTACK_DURATION_MS then return end

    md._GettingOldHeartAttackFatal = true
    player:transmitModData()

    local bodyDamage = player:getBodyDamage()
    bodyDamage:setOverallBodyHealth(0)
    player:setHealth(0)

    DevTools.debugLog("Getting Old", "Player died from a heart attack")
end

Events.EveryTenMinutes.Add(function()
    forEachPlayer(checkForHeartAttack)
end)

Events.OnTick.Add(function()
    forEachPlayer(finishHeartAttack)
end)

DevTools.debugLog("Getting Old", "Deadly age heart attacks hooked")
