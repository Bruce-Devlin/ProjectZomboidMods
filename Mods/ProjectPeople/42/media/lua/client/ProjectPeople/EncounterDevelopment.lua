-- Deliberately labelled development entry. Runs without a testing companion.
require "ISUI/ISPanel"
require "ISUI/ISButton"
local Encounter = require "ProjectPeople/EncounterRuntime"
local Panel = ISPanel:derive "PPEncounterDevelopment"

function Panel:prerender()
    ISPanel.prerender(self)
    self:drawText("Project People | DEVELOPMENT", 10, 8, 1, 0.8, 0.3, 1, UIFont.Small)
    self:drawText("NPC encounter prototype | session only", 10, 26, 1, 1, 1, 1, UIFont.Small)
    local o = Encounter.observe()
    local s = o.state
    self:drawText(
        s and (s.name .. " | " .. s.mode .. " | health " .. s.health) or "Dedicated MP: start near both players",
        10,
        48,
        1,
        1,
        1,
        1,
        UIFont.Small
    )
    self:drawText(
        s and string.format("%s | %.2f, %.2f", s.personId, s.x, s.y) or Encounter.BUILD,
        10,
        66,
        0.8,
        0.8,
        0.8,
        1,
        UIFont.Small
    )
    self:drawText(o.error or self.message or o.reply, 10, 86, 1, 0.7, 0.5, 1, UIFont.Small)
end

function Panel:action(button)
    local ok, why
    if button.internal == "start" then
        ok, why = Encounter.startNearby()
    elseif button.internal == "move" then
        ok, why = Encounter.moveNearby()
    else
        ok, why = Encounter.request(button.internal)
    end
    self.message = not ok and tostring(why) or nil
end

function Encounter.openDevelopment()
    if not isClient() then
        return
    end
    if Encounter.panel then
        Encounter.panel:setVisible(true)
        return
    end
    local panel = Panel:new(20, 180, 400, 176)
    panel:initialise()
    panel.moveWithMouse = true
    panel.backgroundColor = { r = 0.07, g = 0.08, b = 0.1, a = 0.9 }
    for i, entry in ipairs({
        { "Start encounter", "start" },
        { "Move nearby", "move" },
        { "Wait", "wait" },
        { "Damage once", "damage" },
    }) do
        local x = 10 + ((i - 1) % 2) * 195
        local y = 110 + math.floor((i - 1) / 2) * 30
        local b = ISButton:new(x, y, 185, 25, entry[1], panel, Panel.action)
        b.internal = entry[2]
        b:initialise()
        panel:addChild(b)
    end
    panel:addToUIManager()
    Encounter.panel = panel
end
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test or not isClient() then
        return
    end
    context:addOption("Project People [Development]: NPC encounter", nil, function()
        Encounter.openDevelopment()
    end)
end)
