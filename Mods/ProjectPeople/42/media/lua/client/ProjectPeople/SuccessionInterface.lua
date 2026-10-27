local Runtime = require "ProjectPeople/SurvivorRuntime"
require "ISUI/ISButton"
local attached
local reasons = {
    faithful_native_reconstruction_unproven = "Character transfer is not ready: medical state, skills and equipment must all be preserved.",
    native_body_not_loaded = "This survivor's body is not currently loaded.",
    candidate_state_unresolved = "Finish or reconcile this survivor's assignment or transfer first.",
    critical_transfer_unproven = "This survivor needs intervention; critical-state transfer is not ready.",
    candidate_unavailable = "This survivor is unavailable.",
}
Events.OnTick.Add(function()
    local panel = ISPostDeathUI and ISPostDeathUI.instance and ISPostDeathUI.instance[0]
    if not panel or panel == attached then
        return
    end
    attached = panel
    -- Add space above the vanilla controls and preserve their absolute
    -- positions. Never cover Create New Character or either exit button.
    local existing = { panel.buttonRespawn, panel.buttonExit, panel.buttonQuit }
    local positions = {}
    for i, child in ipairs(existing) do
        positions[i] = child:getY()
    end
    panel:setHeight(panel:getHeight() + 35)
    panel:setY(panel:getY() - 35)
    for i, child in ipairs(existing) do
        child:setY(positions[i] + 35)
    end
    local button = ISButton:new(0, 0, panel:getWidth(), 25, "Project People succession", nil, function()
        local view = Runtime.view()
        local state = view and view.succession
        local menu = ISContextMenu.get(0, getMouseX(), getMouseY())
        if not state or not state.eligible or #state.candidates == 0 then
            local option = menu:addOption "No eligible surviving community member"
            option.notAvailable = true
            return
        end
        for _, candidate in ipairs(state.candidates) do
            local id = candidate.id
            local option = menu:addOption("Continue as " .. candidate.name, nil, function()
                local current = Runtime.view()
                Runtime.request("succession.reserve", { personId = id }, current.world.revision)
            end)
            if not candidate.enabled then
                option.notAvailable = true
                local tip = ISWorldObjectContextMenu.addToolTip()
                tip.description = reasons[candidate.reason] or candidate.reason
                option.toolTip = tip
            end
        end
    end)
    button:initialise()
    panel:addChild(button)
end)
