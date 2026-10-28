require "ISUI/ISUI3DModel"
local Portraits = {}

-- Resolve only IDs already admitted by the owner's filtered party view.
-- eachBody checks the original native binding; no world scan or actor creation.
function Portraits.resolve(runtime, rows)
    local wanted, actors = {}, {}
    for _, row in ipairs(rows) do
        if not row.missing then
            wanted[row.id] = true
        end
    end
    if runtime.eachBody then
        runtime.eachBody(function(actor, record)
            if wanted[record.personId] then
                actors[record.personId] = actor
            end
        end)
    end
    return actors
end

function Portraits.clear(panel)
    for _, model in pairs(panel.portraits or {}) do
        model:setVisible(false)
        panel:removeChild(model)
    end
    panel.portraits, panel.portraitRows = {}, {}
end

function Portraits.sync(panel, enabled, openPerson)
    panel.portraits, panel.portraitRows = panel.portraits or {}, {}
    if not enabled or not ISUI3DModel or not panel:getIsVisible() then
        Portraits.clear(panel)
        return
    end
    local list, used = panel.list, {}
    local scroll = list:getYScroll()
    local slot = 0
    for index, row in ipairs(panel.rows or {}) do
        local y = (index - 1) * list.itemheight + scroll
        local actor = panel.portraitActors and panel.portraitActors[row.id]
        -- Partially clipped rows keep their initials; native models must never
        -- escape the list viewport or overlap its header/footer.
        if actor and not row.missing and y >= 0 and y + list.itemheight <= list.height and slot < 4 then
            slot = slot + 1
            used[slot] = true
            local model = panel.portraits[slot]
            if not model then
                model = ISUI3DModel:new(list.x + 10, list.y + y + 8, 64, 78)
                model:initialise()
                panel:addChild(model)
                model:setIsometric(false)
                model:setDirection(IsoDirections.S)
                model:setZoom(12)
                model:setYOffset(-0.8)
                model:setAnimateWhilePaused(false)
                model:setDoRandomExtAnimations(false)
                model.onMouseDown = function()
                    return true
                end
                model.onMouseUp = function(self)
                    openPerson(self.personId)
                    return true
                end
                panel.portraits[slot] = model
            end
            if model.actor ~= actor or getTimestampMs() >= (model.refreshAt or 0) then
                model:setCharacter(actor)
                -- Presentation animation only: UI3DModel owns its model state.
                model:setAnimSetName "player"
                model:setState "idle"
                model.actor, model.refreshAt = actor, getTimestampMs() + 5000
            end
            model.personId = row.id
            model:setY(list.y + y + 8)
            model:setVisible(true)
            panel.portraitRows[row.id] = true
        end
    end
    for index, model in pairs(panel.portraits) do
        if not used[index] then
            model:setVisible(false)
            panel:removeChild(model)
            panel.portraits[index] = nil
        end
    end
end

return Portraits
