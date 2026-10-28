-- Menu policy uses the filtered view only. The authority rechecks every request.
local Interaction = {}
local Danger = require "ProjectPeople/InteractionDanger"
local reasons = {
    travel_agreed = "Open to travelling together",
    cooperation_agreed = "Ready to cooperate at home",
    group_not_ready = "We stay together; everyone must be willing, nearby and ready",
    needs_trust = "Wants to know you better before travelling",
    prefers_home = "Prefers to stay at home",
    prefers_temporary_cooperation = "Travel together first; home cooperation needs more trust",
    trust_broken = "Broken trust or fear prevents agreement",
    needs_rest = "Needs a safe rest first",
    too_shaken = "Needs time somewhere safe",
    family_needs_care = "An injured relative needs care",
    needs_safer_plan = "Needs a safer plan",
    needs_encouragement = "Needs company and achievable work",
    another_commander = "Already follows someone else",
    already_committed = "Has another commitment",
    committed_to_community = "Will not abandon community commitments",
    home_required = "Right-click a location and choose Set Community Home first",
    follower_limit = "Your active party is full; send someone home before inviting the whole group",
    needs_help = "Needs help first",
    person_unavailable = "Unavailable right now",
}

function Interaction.reason(code)
    return reasons[code] or tostring(code or "Speak with them nearby"):gsub("_", " ")
end

local function enabled(view, kind)
    local status = view.status or {}
    local value = (status.actions or {})[kind]
    return status.ready == true and (value == true or type(value) == "table" and value.enabled == true)
end

function Interaction.canCommand(view, p)
    if p.commanderId == view.personId then
        return true
    end
    local me = view.world.people[view.personId]
    local community = p.communityId and view.world.communities[p.communityId]
    return me
            and me.communityId == p.communityId
            and community
            and community.commanders
            and community.commanders[view.personId] == true
        or false
end

function Interaction.options(view, id, nearHome)
    local result = {}
    local p = view and view.world and view.world.people[id]
    local me = view and view.world and view.world.people[view.personId]
    local home = me and me.communityHome
    if not p or not p.controller or p.controller.kind ~= "ai" or p.life == "dead" then
        return result
    end
    local near = false
    for _, personId in ipairs(view.nearby or {}) do
        if id == personId then
            near = true
        end
    end
    if not near then
        return result
    end
    local function add(group, label, kind, fields, confirm)
        if enabled(view, kind) then
            fields.personId = id
            result[#result + 1] = { group = group, label = label, kind = kind, fields = fields, confirm = confirm }
        end
    end
    -- This is a player safety preference, not a conversation or group order.
    -- It remains available during danger and only changes this person.
    if p.canSetFriendlyFire then
        add(
            "Cooperate",
            p.friendlyFire and "Friendly fire: ON - disable" or "Friendly fire: OFF - enable",
            "friendly_fire.set",
            { enabled = p.friendlyFire ~= true },
            p.friendlyFire ~= true and "Enable friendly fire (attacks damage trust)" or nil
        )
    end
    if p.interactionDanger then
        if p.commanderId == view.personId and p.partyId then
            add("Cooperate", "View health and provide care", "health.open", {})
        end
        add("Speak", Danger.MESSAGE, "conversation.talk", { topic = "thoughts" })
        return result
    end
    if p.commanderId == view.personId and p.partyId then
        add("Cooperate", "View health and provide care", "health.open", {})
    end
    add("Speak", "What's on your mind?", "conversation.talk", { topic = "thoughts" })
    if p.life ~= "alive" or p.interactionBusy then
        return result
    end
    add("Speak", "Tell me about yourself", "conversation.talk", { topic = "background" })
    add("Speak", "Tell me about your household", "conversation.talk", { topic = "household" })
    add("Speak", "What matters to you?", "conversation.talk", { topic = "outlook" })
    add("Speak", "What should we focus on?", "conversation.talk", { topic = "plans" })
    add("Speak", "Make small talk", "conversation.talk", { topic = "chat" })
    add("Speak", "How are we getting along?", "conversation.talk", { topic = "trust" })
    if p.personalConversations ~= false then
        add("Speak", "Listen", "behaviour.interact", { topic = "listen" })
        add("Speak", "Reassure", "behaviour.interact", { topic = "reassure" })
        add("Speak", "Apologise", "behaviour.interact", { topic = "apologise" })
    end
    if not p.commanderId or p.commanderId == view.personId then
        add("Cooperate", "Trade and equipment", "inventory.open", {})
        add("Cooperate", "Offer a gift", "gift.open", {})
        if not p.partyId then
            add("Cooperate", "Ask to travel together", "cooperation.request", { request = "travel" })
        end
        if home and (not p.recruited or p.partyId) then
            add("Cooperate", "Ask to work together at home", "cooperation.request", { request = "resident" })
        end
    end
    if Interaction.canCommand(view, p) then
        if p.commanderId == view.personId and p.duty == "base" then
            local roles = require "ProjectPeople/HomeRoles"
            add("Commands", "Home role: balance automatically", "home.role.set", { role = "auto" })
            for _, role in ipairs(roles.order) do
                add("Commands", "Home role: " .. roles.labels[role], "home.role.set", { role = role })
            end
        end
        if p.jobId then
            add("Commands", "Recall from supply work", "job.recall", {})
            add("Commands", "Check interrupted supply job", "job.resume", {})
        else
            if p.partyId and p.duty ~= "follow" then
                add("Commands", "Follow me", "duty.set", { duty = "follow" })
            end
            if p.duty ~= "wait" then
                add("Commands", "Wait here / take a break", "duty.set", { duty = "wait" })
            end
            if home and p.duty ~= "base" and (not p.cooperation or p.cooperation.resident.accepted) then
                add("Commands", "Return to Community Home", "duty.set", { duty = "base" })
            end
        end
    end
    if nearHome and id == "mara" then
        add("At home", "Help secure an open door", "help.secure_home", {})
    end
    if p.personalConversations ~= false then
        add("Confront", "Threaten", "behaviour.interact", { topic = "threaten" }, "Threaten them (damages trust)")
    end
    return result
end
return Interaction
