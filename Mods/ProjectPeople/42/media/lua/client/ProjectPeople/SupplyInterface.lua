local Runtime = require "ProjectPeople/SurvivorRuntime"
-- Ordinary world-context entry: no testing companion or developer console.
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test then
        return
    end
    local view = Runtime.view()
    if not view or not view.world or not view.personId then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then
        return
    end
    local found
    for _, object in ipairs(worldObjects) do
        if
            object:getContainer()
            and object:getSquare()
            and object:getSquare():getRoom()
            and not instanceof(object, "IsoGameCharacter")
            and not instanceof(object, "IsoDeadBody")
        then
            found = object
            break
        end
    end
    if not found then
        return
    end
    local sq = found:getSquare()
    local function mark(role)
        local v = Runtime.view()
        Runtime.request("storage.mark", {
            role = role,
            x = sq:getX(),
            y = sq:getY(),
            z = sq:getZ(),
            objectIndex = found:getObjectIndex(),
            containerIndex = found:getContainerIndex(found:getContainer()),
        }, v.world.revision)
    end
    local option = context:addOption "Project People supplies (bandages / ripped sheets)"
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(option, menu)
    menu:addOption("Mark supply source", nil, function()
        mark "source"
    end)
    menu:addOption("Mark delivery storage", nil, function()
        mark "destination"
    end)
    for id, p in pairs(view.world.people) do
        if p.commanderId == view.personId and p.controller.kind == "ai" and p.life ~= "dead" then
            local personId, recall = id, p.jobId ~= nil
            if p.jobId and p.job then
                local status = menu:addOption(
                    p.name
                        .. ": "
                        .. p.job.phase:gsub("_", " ")
                        .. " | carrying "
                        .. tostring(#(p.cargo or {}))
                        .. " tracked items"
                )
                status.notAvailable = true
            end
            if p.job and (p.job.phase == "blocked" or p.job.phase == "unknown") then
                menu:addOption("Reconcile " .. p.name .. "'s supply job", nil, function()
                    local v = Runtime.view()
                    Runtime.request("job.resume", { personId = personId }, v.world.revision)
                end)
            end
            menu:addOption(
                recall and "Recall " .. p.name .. " from supply work" or "Ask " .. p.name .. " to haul supplies",
                nil,
                function()
                    local v = Runtime.view()
                    Runtime.request(recall and "job.recall" or "job.start", { personId = personId }, v.world.revision)
                end
            )
        end
    end
end)
