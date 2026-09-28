local HEARTBEAT_SOUND = "HeartBeat"
local BEAT_INTERVALS_MS = { 900, 750, 600, 475, 350, 275, 225 }
local activeAttacks = {}

local function stopHeartbeat(player, state)
    if state and state.sound then
        player:getEmitter():stopSound(state.sound)
        state.sound = nil
    end
end

local function startEffects(player, playerIndex, attackId)
    local state = {
        attackId = attackId,
        startedAt = getTimestampMs(),
        beatIndex = 1,
        nextBeatAt = 0,
    }
    activeAttacks[playerIndex] = state

    if isClient() then
        DevTools.saySafe(player, getText("UI_GettingOld_HeartAttack_Speech"))
    end

    if HaloTextHelper then
        HaloTextHelper.addBadText(player, getText("UI_GettingOld_HeartAttack_Warning"))
    end

    return state
end

local function updateEffects(player, playerIndex)
    if not player then return end

    local md = player:getModData()
    local attackId = md._GettingOldHeartAttackStartedAt
    local state = activeAttacks[playerIndex]

    if not attackId or not player:isAlive() or md._GettingOldHeartAttackFatal then
        stopHeartbeat(player, state)
        activeAttacks[playerIndex] = nil
        return
    end

    if not state or state.attackId ~= attackId then
        stopHeartbeat(player, state)
        state = startEffects(player, playerIndex, attackId)
    end

    local now = getTimestampMs()
    if now < state.nextBeatAt then return end

    stopHeartbeat(player, state)
    state.sound = player:getEmitter():playSound(HEARTBEAT_SOUND)

    local interval = BEAT_INTERVALS_MS[math.min(state.beatIndex, #BEAT_INTERVALS_MS)]
    state.beatIndex = state.beatIndex + 1
    state.nextBeatAt = now + interval
end

Events.OnTick.Add(function()
    for playerIndex = 0, getNumActivePlayers() - 1 do
        updateEffects(getSpecificPlayer(playerIndex), playerIndex)
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "GettingOld" or not args then return end
    for index = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(index)
        if player and player:getOnlineID() == args.onlineID then
            if command == "AgeWarning" and args.textKey == "UI_GettingOld_OldAge_Cause" and HaloTextHelper then
                HaloTextHelper.addBadText(player, getText(args.textKey))
            elseif command == "Speech" and type(args.text) == "string" then
                player:addLineChatElement(args.text)
            end
        end
    end
end)
