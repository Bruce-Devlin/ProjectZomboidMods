local Runtime = require "ProjectPeople/SurvivorRuntime"
local Home = {}
ProjectPeople.HomeUI = Home
local pending

function Home.atMouse(player)
    local z, zoom = math.floor(player:getZ()), getCore():getZoom(0)
    return {
        x = math.floor(IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z)) + 0.5,
        y = math.floor(IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z)) + 0.5,
        z = z,
    }
end

Events.OnFillWorldObjectContextMenu.Add(function(index, context, objects, testOnly)
    local player, view = getSpecificPlayer(0), Runtime.view()
    if
        index ~= 0
        or testOnly
        or not player
        or player:isDead()
        or not view
        or not view.world
        or not view.status
        or not view.status.ready
    then
        return
    end
    local point = Home.atMouse(player)
    context:addOption("Set Community Home", nil, function()
        local result = Runtime.request("community.home.set", point, view.world.revision)
        pending = result.requestId
        Home.message = result.message or result.pending and "Setting community home..." or tostring(result.code)
        Home.messageUntil = getTimestampMs() + 8000
    end)
end)

Events.OnTick.Add(function()
    local reply = Runtime.reply
    if pending and reply and reply.requestId == pending then
        Home.message = reply.message or tostring(reply.code):gsub("_", " ")
        Home.messageUntil = getTimestampMs() + 8000
        pending = nil
    end
end)

function Home.render()
    local player, view = getSpecificPlayer(0), Runtime.view()
    if Home.message and getTimestampMs() < (Home.messageUntil or 0) then
        getTextManager():DrawString(
            UIFont.Small,
            getPlayerScreenLeft(0) + 164,
            getPlayerScreenTop(0) + 49,
            Home.message,
            0.8,
            0.96,
            0.9,
            1
        )
    end
    local me = view and view.world and view.world.people[view.personId]
    local point = me and me.communityHome
    if not player or player:isDead() or not point or math.abs(player:getZ() - point.z) > 0.2 then
        return
    end
    local zoom = getCore():getZoom(0)
    local left, top, width, height =
        getPlayerScreenLeft(0), getPlayerScreenTop(0), getPlayerScreenWidth(0), getPlayerScreenHeight(0)
    local x = (IsoUtils.XToScreen(point.x, point.y, point.z, 0) - IsoCamera.getOffX()) / zoom + left
    local y = (IsoUtils.YToScreen(point.x, point.y, point.z, 0) - IsoCamera.getOffY()) / zoom + top
    if x < left + 80 or x > left + width - 80 or y < top + 80 or y > top + height - 10 then
        return
    end
    -- A local projected flag has no world object, collision, inventory or network entity.
    local tm = getTextManager()
    tm:DrawStringCentre(UIFont.Large, x, y - 59, "|>", 0.35, 0.85, 0.75, 1)
    tm:DrawStringCentre(UIFont.Small, x - 4, y - 34, "|", 0.8, 0.88, 0.87, 1)
    tm:DrawStringCentre(UIFont.Small, x, y - 18, "Community Home", 0.7, 0.96, 0.88, 1)
end
Events.OnPreUIDraw.Add(Home.render)
return Home
