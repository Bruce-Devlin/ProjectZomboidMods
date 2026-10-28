local Runtime = require "ProjectPeople/SurvivorRuntime"
local Interface = require "ProjectPeople/Interface"
require "ProjectPeople/EquipmentInterface"
require "ProjectPeople/GiftInterface"
require "ProjectPeople/HealthInterface"
require "ProjectPeople/DebugInterface"
require "ProjectPeople/PartyInterface"
require "ProjectPeople/HomeInterface"
Interface.bind({
    eachBody = Runtime.eachBody,
    snapshot = function()
        local view = Runtime.view()
        return view and view.world
    end,
    localPersonId = function()
        local view = Runtime.view()
        return view and view.personId
    end,
    nearby = function()
        local view = Runtime.view()
        return view and view.nearby or {}
    end,
    status = function()
        local view = Runtime.view()
        if Runtime.error then
            return { ready = false, blocked = Runtime.error }
        end
        return view and view.status or { ready = false, blocked = "Waiting for the world to finish loading." }
    end,
    lastReply = function()
        return Runtime.reply
    end,
    request = Runtime.request,
})
