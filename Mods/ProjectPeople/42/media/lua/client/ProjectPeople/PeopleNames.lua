local Runtime = require "ProjectPeople/SurvivorRuntime"
local Names = { drawn = 0 }
ProjectPeople.Names = Names
-- Same camera projection/zoom as player names. No world markers or map reveal.

function Names.render()
    Names.drawn = 0
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or not Runtime.active then
        return
    end
    local index = player:getPlayerNum()
    local zoom = getCore():getZoom(index)
    local left, top = getPlayerScreenLeft(index), getPlayerScreenTop(index)
    local width, height = getPlayerScreenWidth(index), getPlayerScreenHeight(index)
    Runtime.eachBody(function(actor, record)
        local sq = actor:getCurrentSquare()
        if
            actor:isDead()
            or not sq
            or not sq:getCanSee(index)
            or actor:getAlpha(index) <= 0.1
            or math.abs(actor:getZ() - player:getZ()) > 0.2
            or (actor:getX() - player:getX()) ^ 2 + (actor:getY() - player:getY()) ^ 2 > 25 ^ 2
        then
            return
        end
        local x = (IsoUtils.XToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffX()) / zoom + left
        local y = (IsoUtils.YToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffY() - 112) / zoom
            + top
        if x < left + 30 or x > left + width - 30 or y < top or y > top + height - 20 then
            return
        end
        local text = string.sub(tostring(record.name or "Survivor"), 1, 80)
        getTextManager():DrawStringCentre(UIFont.Small, x + 1, y + 1, text, 0, 0, 0, 0.9)
        getTextManager():DrawStringCentre(UIFont.Small, x, y, text, 0.9, 0.96, 1, 1)
        Names.drawn = Names.drawn + 1
    end)
end
Events.OnPostUIDraw.Add(Names.render)
return Names
