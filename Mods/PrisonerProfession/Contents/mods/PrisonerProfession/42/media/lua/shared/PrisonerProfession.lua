--------------------------------------------------
-- Prisoner Profession (Build 42.13)
-- Single-file, MP-safe, server-authoritative
--------------------------------------------------

require "shared/PrisonSpawns"
require "shared/Tests_PrisonerProfession"

local MOD_ID = "PrisonerProfession"
local MODDATA_KEY = "PrisonerProfessionData"
local MODDATA_VERSION = 1
local LOG_TAG = "Prisoner Profession"

--------------------------------------------------
-- Utilities
--------------------------------------------------

local function log(msg)
    DevTools.debugLog(LOG_TAG, msg)
end

local function isServerContext()
    local server = isServer() or not isMultiplayer()
    return server
end

local function getPlayerKey(player)
    if player:getSteamID() then
        return tostring(player:getSteamID())
    end
    return "offline_" .. tostring(player:getUsername())
end

--------------------------------------------------
-- Global ModData (SERVER ONLY)
--------------------------------------------------

local PrisonerData = nil

Events.OnInitGlobalModData.Add(function()
    if not isServerContext() then
        log("Skipping ModData init (not server context)")
        return
    end

    log("Initializing global ModData...")

    local data = ModData.getOrCreate(MODDATA_KEY)

    if not data.version then
        log("Creating new ModData schema")
        data.version = MODDATA_VERSION
        data.players = {}
    elseif data.version < MODDATA_VERSION then
        log("Migrating ModData from version " .. tostring(data.version))
        data.version = MODDATA_VERSION
    end

    PrisonerData = data
    log("ModData ready (version=" .. tostring(data.version) .. ")")
end)

--------------------------------------------------
-- SERVER: Core spawn logic
--------------------------------------------------

local function givePrisonerItems(player)
    log("Giving prisoner starter items")

    local inv = player:getInventory()

    if not inv:containsType("Base.CrudeKnife") then
        local knife = inv:AddItem("Base.CrudeKnife")
        if knife then
            knife:setName("Prison Shank")
            knife:setTooltip("Glad I kept a hold of this, it's not great but it's better than nothing...")
            log("Added Prison Shank")
        end
    end

    if not inv:containsType("Base.Soap2") then
        local soap = inv:AddItem("Base.Soap2")
        if soap then
            soap:setName("Prison Key Molded Soap")
            soap:setTooltip("Used to clean and/or create a prison key. Don't drop...")
        end
        log("Added Soap")
    end

    if not inv:containsType("Base.Flashlight_Crafted") then
        local flashlight = inv:AddItem("Base.Flashlight_Crafted")
        if flashlight then
            flashlight:setName("Table lamp")
            flashlight:setTooltip("Pulled out of my cell. It has a battery in it, I wonder how long it will last...")
        end
        log("Added flashlight")
    end
end

local function giveBuildingKey(player, square)
    if not square then
        log("giveBuildingKey: square is nil")
        return
    end

    local building = getWorld():getMetaGrid():getBuildingAt(square:getX(), square:getY())
    if not building then
        log("giveBuildingKey: no building at spawn square")
        return
    end

    local keyId = building:getKeyId()
    if keyId <= 0 then
        keyId = ZombRand(1000000, 9000000)
        building:setKeyId(keyId)
        log("Generated new building keyId: " .. tostring(keyId))
    end

    local key = player:getInventory():AddItem("Base.Key1")
    if key then
        key:setKeyId(keyId)
        key:setName("Prison Key")
        key:setTooltip("Luckily I was already planning a break-out, molded from a bar of soap but I really hope it works...")
        log("Gave Prison Key to player")
    end
end

local function cleanupZombie(zombie)
    if not zombie then return false end

    local killed, killErr = pcall(function()
        zombie:Kill(nil)
    end)

    if killed then
        return true
    end

    log("Zombie Kill failed, falling back to direct removal: " .. tostring(killErr))

    local removed, removeErr = pcall(function()
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end)

    if not removed then
        log("Zombie removal failed: " .. tostring(removeErr))
    end

    return removed
end

local function lightZombieCleanup(centerSq, safeRadius, killRadiusMultiplier)
    log("Performing light zombie cleanup (radius=" .. tostring(safeRadius) .. ")")

    local cx, cy, cz = centerSq:getX(), centerSq:getY(), centerSq:getZ() 
    log(string.format( "Attempting to remove zombies with radius of: %d around: X: %d Y: %d Z: %d", safeRadius, cx, cy, cz ) ) 
    local r1 = safeRadius 
    local r2 = safeRadius * killRadiusMultiplier
    local cell = getCell()
    local removed = 0
    
    for dx = -r2, r2 do 
        for dy = -r2, r2 do 
            for dz = -1, 1 do 
                local sq = cell:getOrCreateGridSquare(cx + dx, cy + dy, cz + dz) 
                if sq then 
                    local moving = sq:getMovingObjects() 
                    for i = moving:size() - 1, 0, -1 do 
                        local obj = moving:get(i) 
                        if instanceof(obj, "IsoZombie") then 
                            local zx = obj:getX() 
                            local zy = obj:getY() 
                            local dist2 = (zx - cx)^2 + (zy - cy)^2 
                            if dist2 <= (r1 * r1) then 
                                if cleanupZombie(obj) then
                                    removed = removed + 1
                                end
                            elseif dist2 <= (r2 * r2) then 
                                if ZombRand(10) < 5 then 
                                    if cleanupZombie(obj) then
                                        removed = removed + 1
                                    end
                                end 
                            end 
                        end 
                    end 
                end 
            end 
        end 
    end

    log("Zombie cleanup removed " .. tostring(removed) .. " zombies")
    return removed
end

local function spawnPrisoner(player)
    if not PrisonerData then
        log("spawnPrisoner aborted: ModData not initialized")
        return
    end

    local key = getPlayerKey(player)

    if PrisonerData.players[key] then
        log("Player already spawned as prisoner: " .. key)
        return
    end

    local prof = player:getDescriptor():getCharacterProfession()
    if tostring(prof) ~= "prisonerprofession:prisoner" then
        log("spawnPrisoner ignored: profession is " .. tostring(prof))
        return
    end

    local spawn = PRISON_SPAWNS[ZombRand(#PRISON_SPAWNS) + 1]
    log(string.format("Selected spawn point (%d,%d,%d)", spawn.x, spawn.y, spawn.z))

    local sq = getCell():getOrCreateGridSquare(spawn.x, spawn.y, spawn.z)

    player:setX(spawn.x)
    player:setY(spawn.y)
    player:setZ(spawn.z)

    player:setLastX(spawn.x)
    player:setLastY(spawn.y)
    player:setLastZ(spawn.z)

    if isMultiplayer() then
        sendServerCommand(player, MOD_ID, "ApplySpawn", {
            x = spawn.x,
            y = spawn.y,
            z = spawn.z
        })
        log("Sent ApplySpawn command to client")
    end

    log("Teleported player to prison spawn")

    givePrisonerItems(player)
    giveBuildingKey(player, sq)

    PrisonerData.players[key] = true
    ModData.transmit(MODDATA_KEY)

    DevTools.waitSeconds(2, function()
        lightZombieCleanup(sq, 30, 2)
    end, "ZombieCleanup")

    local md = player:getModData()
    md.PrisonerSpawned = true

    log("Prisoner spawn complete for player key=" .. key)
end

--------------------------------------------------
-- SERVER: Client command handler
--------------------------------------------------

local function onClientCommand(module, command, player, args)
    if not isServerContext() then return end

    if module ~= MOD_ID then return end
    if command ~= "RequestSpawn" then return end

    if not player or not player:isAlive() then
        log("RequestSpawn rejected: invalid or dead player")
        return
    end

    log("Received RequestSpawn from player " .. getPlayerKey(player))
    local onlineID = player:getOnlineID()
    DevTools.waitSeconds(2, function()
        local freshPlayer = getPlayerByOnlineID(onlineID)
        
        if not player or not player:isAlive() then
            log("RequestSpawn rejected: invalid or dead player")
            return
        end

        spawnPrisoner(freshPlayer)
    end, "SpawningPlayer")
end

Events.OnClientCommand.Add(onClientCommand)

--------------------------------------------------
-- SERVER: Cleanup on death
--------------------------------------------------
Events.OnCharacterDeath.Add(function(character)
    if not isServerContext() then return end
    if not character then return end
    if not instanceof(character, "IsoPlayer") then return end

    local player = character
    if not PrisonerData then return end

    local key = getPlayerKey(player)

    log("Player died (server authoritative), clearing prisoner spawn flag: " .. key)

    PrisonerData.players[key] = nil
    ModData.transmit(MODDATA_KEY)

    local md = player:getModData()
    if md then
        md.PrisonerSpawned = nil
        md.PrisonerSpawnRequested = nil
    end
end)


--------------------------------------------------
-- SERVER: Init zombie de-spawn (one-time per server start)
--------------------------------------------------

local InitCleanupDone = false

Events.OnGameStart.Add(function()
    if not isServerContext() then return end
    if InitCleanupDone then
        log("Init zombie cleanup already performed, skipping")
        return
    end

    InitCleanupDone = true

    log("Scheduling initial prison zombie cleanup...")

    DevTools.waitSeconds(5, function()
        if not PRISON_SPAWNS or #PRISON_SPAWNS == 0 then
            log("No prison spawns defined, skipping init cleanup")
            return
        end

        log("Running initial zombie cleanup for prison spawns (" .. tostring(#PRISON_SPAWNS) .. " locations)")

        local cell = getCell()
        local totalRemoved = 0

        for index, spawn in ipairs(PRISON_SPAWNS) do
            if spawn.x and spawn.y and spawn.z then
                local sq = cell:getOrCreateGridSquare(spawn.x, spawn.y, spawn.z)

                if sq then
                    log(string.format(
                        "Init cleanup at spawn #%d (%d,%d,%d)",
                        index, spawn.x, spawn.y, spawn.z
                    ))

                    totalRemoved = totalRemoved + lightZombieCleanup(sq, 5, 2)

                else
                    log(string.format(
                        "Init cleanup skipped: grid square not loaded for spawn #%d (%d,%d,%d)",
                        index, spawn.x, spawn.y, spawn.z
                    ))
                end
            else
                log("Invalid spawn entry at index " .. tostring(index))
            end
        end

        log("Initial zombie cleanup finished, removed " .. tostring(totalRemoved) .. " zombies")

    end, "InitZombieCleanup")

end)


--------------------------------------------------
-- CLIENT: One-time spawn request
--------------------------------------------------
local function locallyTeleportToLocation(x, y, z)
    local player = getPlayer()
    if not player then return end

    player:setX(x)
    player:setY(y)
    player:setZ(z)

    player:setLastX(x)
    player:setLastY(y)
    player:setLastZ(z)

    player:setLx(x)
    player:setLy(y)
    player:setLz(z)

    log(string.format("Client teleported to (%d,%d,%d)", x, y, z))
end

local function onServerCommand(module, command, args)
    if module ~= MOD_ID then return end
    if command ~= "ApplySpawn" then return end

    if not args or not args.x then
        log("ApplySpawn received with invalid args")
        return
    end

    locallyTeleportToLocation(args.x, args.y, args.z)
end

Events.OnServerCommand.Add(onServerCommand)

Events.OnCreatePlayer.Add(function(playerIndex, player)
    local onlineID = player:getOnlineID()

    DevTools.waitSeconds(2, function()
        local delayPlayer = getPlayer()

        local prof = player:getDescriptor():getCharacterProfession()
        if tostring(prof) ~= "prisonerprofession:prisoner" then
            log("Player profession: ".. tostring(prof))
            return
        end

        log("Attempting to spawn prisoner...")

        local md = delayPlayer:getModData()
        if md.PrisonerSpawnRequested then
            log("Spawn already requested (client-side guard)")
            return
        end

        md.PrisonerSpawnRequested = true

        if not isMultiplayer() then
            if isServerContext() then
                log("Singleplayer: spawning prisoner directly")
                spawnPrisoner(delayPlayer)
            end
            return
        end

        log("Sending RequestSpawn to server")

        sendClientCommand(MOD_ID, "RequestSpawn", {})
    end, "RequestPrisonerSpawn")
end)
