local Text = require "ProjectPeople/Content/Dialogue"
local Mind = require "ProjectPeople/Behaviour/Mind"
local Dialogue = require "ProjectPeople/Behaviour/Dialogue"
local Population = require "ProjectPeople/Population/Rules"
local Trust = require "ProjectPeople/Behaviour/Trust"
local Conversation = {}
local chatter = Text.chatter

function Conversation.reply(world, id, visitor, topic, now)
    if
        topic ~= nil
        and topic ~= "thoughts"
        and topic ~= "background"
        and topic ~= "plans"
        and topic ~= "chat"
        and topic ~= "trust"
    then
        return { ok = false, code = "unknown_conversation_topic" }
    end
    local p = world.people[id]
    if not p or p.controller.kind ~= "ai" or p.life == "dead" then
        return { ok = false, code = "person_unavailable" }
    end
    if p.reservationId or p.transitionId then
        return { ok = false, code = "already_committed" }
    end
    local text
    local rel = p.relationships[visitor]
    if p.life == "critical" then
        text = Dialogue.reply(world, id, visitor)
    elseif rel and rel.anchors and rel.anchors["threat:" .. visitor] then
        text = Text.conversation.threatened
    elseif topic == "trust" then
        local summary = Trust.summary(p, visitor)
        text = summary.value < 0 and Text.conversation.wary
            or p.preferences.baseOnly and Text.conversation.home
            or summary.value < Trust.requirement(p, "travel") and Text.conversation.needsTrust
            or summary.value >= Trust.requirement(p, "resident") and summary.value >= 10 and Text.conversation.trusting
            or Text.conversation.trial
    elseif not topic or topic == "thoughts" then
        text = Dialogue.reply(world, id, visitor)
    elseif topic == "background" then
        text = p.background ~= "" and p.background or Dialogue.reply(world, id, visitor)
    elseif topic == "plans" then
        text = Mind.reply(p, visitor)
            or (
                p.jobId and Text.conversation.supplyJob
                or p.duty == "follow" and Text.conversation.follow
                or p.duty == "wait" and Text.conversation.wait
                or Population.plan(world, p)
                or Text.conversation.safeHome
            )
    else
        text = Mind.reply(p, visitor)
        if not text then
            -- Stable for a game hour; no global RNG consumption or click farming.
            local seed = 0
            for i = 1, #id do
                seed = (seed * 31 + string.byte(id, i)) % 65521
            end
            text = chatter[(seed + math.floor(now or 0)) % #chatter + 1]
        end
    end
    return { ok = true, code = "conversation", message = text }
end

function Conversation.threaten(p, visitor, now)
    local m = Mind.ensure(p, now)
    if not m.policy.enabled then
        return { ok = false, code = "living_survivors_disabled" }
    end
    local rel = p.relationships[visitor] or { trust = 0, affection = 0, respect = 0, fear = 0, anchors = {} }
    p.relationships[visitor] = rel
    rel.anchors = rel.anchors or {}
    local key = "threat:" .. visitor
    if not rel.anchors[key] then
        rel.anchors[key] = { event = "threatened", gameTime = now }
        rel.trust = math.max(-100, rel.trust - 30)
        rel.fear = math.min(100, rel.fear + 20)
        m.stress = math.min(100, m.stress + 10)
        Mind.remember(p, "threatened", visitor, key, now)
    end
    -- A verbal threat is not observed assault, loot transfer or attack permission.
    return {
        ok = true,
        code = "conversation",
        message = Text.conversation.threatRefusal,
    }
end
return Conversation
