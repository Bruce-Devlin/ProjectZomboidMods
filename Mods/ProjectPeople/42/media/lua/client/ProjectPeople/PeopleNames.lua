local Runtime = require "ProjectPeople/SurvivorRuntime"
local Ambient = require "ProjectPeople/Behaviour/AmbientDialogue"
local Clock = require "ProjectPeople/Behaviour/DialogueClock"
local Names = { drawn = 0 }
local chatter
ProjectPeople.Names = Names
-- Same camera projection/zoom as player names. No world markers or map reveal.

function Names.render()
    Names.drawn = 0
    Names.heard = {}
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or not Runtime.active then
        if chatter then
            chatter:reset()
        end
        return
    end
    local now = Clock.now()
    chatter = chatter or Ambient.new(now)
    chatter:begin(now)
    local index = player:getPlayerNum()
    local zoom = getCore():getZoom(index)
    local left, top = getPlayerScreenLeft(index), getPlayerScreenTop(index)
    local width, height = getPlayerScreenWidth(index), getPlayerScreenHeight(index)
    local occupied, speech = {}, {}
    Runtime.eachBody(function(actor, record)
        local sq = actor:getCurrentSquare()
        if
            actor:isDead()
            or not sq
            or math.abs(actor:getZ() - player:getZ()) > 0.2
            or (actor:getX() - player:getX()) ^ 2 + (actor:getY() - player:getY()) ^ 2 > 25 ^ 2
        then
            return
        end
        local x = (IsoUtils.XToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffX()) / zoom + left
        local y = (IsoUtils.YToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffY() - 112) / zoom
            + top
        local text = string.sub(tostring(record.name or "Survivor"), 1, 80)
        local debug = ProjectPeople.Debug
        local visible = sq:getCanSee(index)
            and actor:getAlpha(index) > 0.1
            and x >= left + 30
            and x <= left + width - 30
            and y >= top
            and y <= top + height - 20
        if
            visible and not (debug and debug.covers(x, y, getTextManager():MeasureStringX(UIFont.Small, text) / 2, 18))
        then
            getTextManager():DrawStringCentre(UIFont.Small, x + 1, y + 1, text, 0, 0, 0, 0.9)
            getTextManager():DrawStringCentre(UIFont.Small, x, y, text, 0.9, 0.96, 1, 1)
            occupied[#occupied + 1] = { x = x, y = y, half = getTextManager():MeasureStringX(UIFont.Small, text) / 2 }
            Names.drawn = Names.drawn + 1
        end
        local line
        if record.socialPartner then
            -- Both participants suppress unrelated barks, including the listener.
            chatter:line(record.personId, nil, now)
            if Runtime.dialogueViewAt and now - Runtime.dialogueViewAt <= 3000 and Ambient.category(record, actor) then
                line = record.socialLine
            end
        else
            line = Runtime.playerAlert and Runtime.playerAlert(record.personId)
            if line then
                chatter:line(record.personId, nil, now)
            else
                line = chatter:line(record.personId, Ambient.category(record, actor), now)
            end
        end
        if line then
            local half = getTextManager():MeasureStringX(UIFont.Small, line) / 2
            -- Nearby voices remain audible through walls. Offscreen voices sit
            -- on the corresponding screen edge without revealing hidden names.
            speech[#speech + 1] = {
                x = math.max(left + half + 4, math.min(left + width - half - 4, x)),
                y = math.max(top + 176, math.min(top + height - 24, y - 22)),
                text = line,
                id = record.personId,
            }
        end
    end)
    -- Reserve all visible names first, then lift speech above nearby labels.
    -- Stable ordering prevents paired/ambient text changing lanes every frame.
    table.sort(speech, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    local manager, debug = getTextManager(), ProjectPeople.Debug
    for _, entry in ipairs(speech) do
        local half = manager:MeasureStringX(UIFont.Small, entry.text) / 2
        if entry.x - half >= left + 4 and entry.x + half <= left + width - 4 then
            for offset = 0, 7 do
                local y = entry.y - offset * 22
                if y < top then
                    break
                end
                local covered = debug and debug.covers(entry.x, y, half, 20)
                for _, label in ipairs(occupied) do
                    if math.abs(entry.x - label.x) < half + label.half + 4 and math.abs(y - label.y) < 20 then
                        covered = true
                        break
                    end
                end
                if not covered then
                    manager:DrawStringCentre(UIFont.Small, entry.x + 1, y + 1, entry.text, 0, 0, 0, 0.95)
                    manager:DrawStringCentre(UIFont.Small, entry.x, y, entry.text, 1, 0.94, 0.75, 1)
                    Names.heard[entry.id] = entry.text
                    occupied[#occupied + 1] = { x = entry.x, y = y, half = half }
                    break
                end
            end
        end
    end
end
Events.OnPreUIDraw.Add(Names.render)
return Names
