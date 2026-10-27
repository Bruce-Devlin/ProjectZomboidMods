-- Personality, strain and social memories. Does not change native health or inventory.
local Settings = require "ProjectPeople/Behaviour/Settings"
local Plans = require "ProjectPeople/Behaviour/Plans"
local Text = require "ProjectPeople/Content/Dialogue"
local DevTools = require "ProjectPeople/DevTools"
local Mind = { VERSION = 1, MAX_MEMORIES = 24, MAX_CONTACTS = 32 }
local axes = Settings.axes
local isFinite = DevTools.isFinite

local function clamp(v, lo, hi)
    return math.max(lo or 0, math.min(hi or 100, v))
end

local function number(v, default, lo, hi)
    return isFinite(v) and clamp(v, lo, hi) or default
end

local hash = DevTools.hash

local function traits(person)
    local result = {}
    for k, v in pairs(person.character and person.character.traits or {}) do
        if type(v) == "string" then
            result[v] = true
        elseif v == true then
            result[k] = true
        end
    end
    return result
end

function Mind.options(raw)
    raw = raw or {}
    return {
        enabled = raw.LivingSurvivors ~= false,
        strainRate = number(raw.StrainRate, 1, 0, 3),
        stressRate = number(raw.StressRate, 1, 0, 3),
        socialRate = number(raw.SocialRate, 1, 0, 3),
        recoveryRate = number(raw.RecoveryRate, 1, 0.25, 3),
        autonomy = raw.IdleAutonomy ~= false,
    }
end

function Mind.personality(person)
    local result = {}
    local seed = hash(person.id)
    for i, key in ipairs(axes) do
        result[key] = number((person.personality or {})[key], 30 + (seed * i * 13) % 41, 0, 100)
    end
    local t = traits(person)
    if t.Brave and not t.Cowardly then
        result.caution = math.min(result.caution, 25)
    elseif t.Cowardly then
        result.caution = math.max(result.caution, 80)
    end
    return result
end

function Mind.ensure(person, now)
    if not person.mind then
        person.mind = {
            version = 1,
            lastAt = now,
            strain = 0,
            stress = 0,
            loneliness = 0,
            morale = 60,
            memories = {},
            contacts = {},
            concerns = {},
            personality = Mind.personality(person),
            policy = Mind.options(),
        }
    end
    return person.mind
end

function Mind.valid(mind)
    if mind == nil then
        return true
    end
    if type(mind) ~= "table" or mind.version ~= 1 or not isFinite(mind.lastAt) or mind.lastAt < 0 then
        return false
    end
    for _, key in ipairs({ "strain", "stress", "loneliness", "morale" }) do
        if not isFinite(mind[key]) or mind[key] < 0 or mind[key] > 100 then
            return false
        end
    end
    if
        type(mind.memories) ~= "table"
        or #mind.memories > Mind.MAX_MEMORIES
        or type(mind.contacts) ~= "table"
        or type(mind.concerns) ~= "table"
        or type(mind.personality) ~= "table"
        or type(mind.policy) ~= "table"
    then
        return false
    end
    for _, key in ipairs(axes) do
        if not isFinite(mind.personality[key]) or mind.personality[key] < 0 or mind.personality[key] > 100 then
            return false
        end
    end
    local count = 0
    for _, c in pairs(mind.contacts) do
        count = count + 1
        if type(c) ~= "table" or not isFinite(c.at) or type(c.topic) ~= "string" then
            return false
        end
    end
    if count > Mind.MAX_CONTACTS then
        return false
    end
    if mind.lastConversationAt ~= nil and (not isFinite(mind.lastConversationAt) or mind.lastConversationAt < 0) then
        return false
    end
    if mind.unobservedHours ~= nil and (not isFinite(mind.unobservedHours) or mind.unobservedHours < 0) then
        return false
    end
    if type(mind.policy.enabled) ~= "boolean" or type(mind.policy.autonomy) ~= "boolean" then
        return false
    end
    for _, key in ipairs({ "strainRate", "stressRate", "socialRate", "recoveryRate" }) do
        if not isFinite(mind.policy[key]) or mind.policy[key] < 0 or mind.policy[key] > 3 then
            return false
        end
    end
    for _, memory in ipairs(mind.memories) do
        if
            type(memory) ~= "table"
            or type(memory.id) ~= "string"
            or type(memory.kind) ~= "string"
            or not isFinite(memory.at)
            or not isFinite(memory.weight)
        then
            return false
        end
    end
    for _, c in pairs(mind.concerns) do
        if type(c) ~= "table" or not isFinite(c.at) or (c.kind ~= "hurt" and c.kind ~= "dead") then
            return false
        end
    end
    return true
end
-- Major existing relationship anchors remain in Core, even when the short
-- conversational memory list is compressed. Never erase family links.

function Mind.remember(person, kind, actorId, eventId, now, relatedId)
    local mind = Mind.ensure(person, now)
    for _, entry in ipairs(mind.memories) do
        if entry.id == eventId then
            return false
        end
    end
    local important = kind == "betrayed" or kind == "attacked" or kind == "bereavement" or kind == "helped_family"
    mind.memories[#mind.memories + 1] = {
        id = eventId,
        kind = kind,
        actorId = actorId,
        relatedId = relatedId,
        at = now,
        weight = important and 100 or 10,
    }
    if #mind.memories > Mind.MAX_MEMORIES then
        local remove = 1
        for i, entry in ipairs(mind.memories) do
            if entry.weight < mind.memories[remove].weight then
                remove = i
            end
        end
        table.remove(mind.memories, remove)
    end
    return true
end

function Mind.advance(person, now, seen, raw)
    local mind = Mind.ensure(person, now)
    local options = Mind.options(raw)
    mind.policy = options
    if now < mind.lastAt then
        return false, "behaviour_clock_reversed"
    end
    local elapsed = now - mind.lastAt
    mind.lastAt = now
    -- Only a short continuous observation interval supports an activity claim.
    -- A long save gap is not retroactive work, isolation, starvation or rest.
    if elapsed > 0.5 then
        mind.unobservedHours = (mind.unobservedHours or 0) + elapsed
        elapsed = 0
    end
    if not options.enabled then
        return true
    end
    mind.personality = Mind.personality(person)
    local dt = elapsed
    local personality = mind.personality
    local danger = seen.threat == true
    local resting = seen.resting == true and not danger and seen.moving ~= true
    mind.strain = clamp(
        mind.strain
            + dt
                * (resting and -24 * options.recoveryRate or (danger and 18 or seen.moving and 8 or -2 * options.recoveryRate) * options.strainRate)
    )
    mind.stress = clamp(
        mind.stress
            + dt
                * (danger and (18 + personality.caution * 0.16 - personality.aggression * 0.06) * options.stressRate or -12 * options.recoveryRate)
    )
    mind.loneliness = clamp(
        mind.loneliness
            + dt
                * (seen.company and -10 * options.recoveryRate or (2 + personality.sociability * 0.04) * options.socialRate)
    )
    if seen.hurt then
        mind.stress = math.max(mind.stress, 35)
    end
    mind.morale = clamp(mind.morale + dt * ((seen.company and 2 or 0) - mind.stress * 0.04 - mind.loneliness * 0.015))
    for id, condition in pairs(seen.family or {}) do
        if person.family[id] then
            if condition == "dead" then
                if not mind.concerns[id] or mind.concerns[id].kind ~= "dead" then
                    mind.concerns[id] = { kind = "dead", at = now }
                    mind.morale = clamp(mind.morale - 25)
                    mind.stress = clamp(mind.stress + 25)
                    Mind.remember(person, "bereavement", nil, "loss:" .. id, now, id)
                end
            elseif condition == "hurt" then
                mind.concerns[id] = { kind = "hurt", at = now }
            elseif condition == "well" and mind.concerns[id] and mind.concerns[id].kind ~= "dead" then
                mind.concerns[id] = nil
            end
        end
    end
    return true
end

function Mind.refusal(person, actorId, request, risk)
    local mind = person.mind
    if not mind or not mind.policy.enabled then
        return nil
    end
    if request == "travel" or request == "mission" then
        if mind.strain >= Settings.refusal.strain then
            return "needs_rest"
        end
        if mind.stress >= Settings.refusal.stress then
            return "too_shaken"
        end
        for _, concern in pairs(mind.concerns) do
            if
                concern.kind == "hurt"
                and mind.lastAt - concern.at <= Settings.refusal.familyHours
                and mind.personality.compassion >= Settings.refusal.familyCompassion
            then
                return "family_needs_care"
            end
        end
        local rel = person.relationships[actorId] or {}
        if mind.morale < Settings.refusal.lowMorale and (rel.trust or 0) < Settings.refusal.encouragementTrust then
            return "needs_encouragement"
        end
        local confidence = (rel.trust or 0) + (rel.respect or 0) * (0.5 + mind.personality.independence / 100)
        if
            risk
            and mind.personality.caution >= Settings.refusal.riskCaution
            and confidence < Settings.refusal.riskConfidence
        then
            return "needs_safer_plan"
        end
    end
    return nil
end

local function recent(person, actorId)
    for i = #person.mind.memories, 1, -1 do
        local entry = person.mind.memories[i]
        if entry.actorId == actorId then
            return entry
        end
    end
end

function Mind.summary(person)
    local mind = person.mind
    if not mind or not mind.policy.enabled then
        return nil
    end
    if mind.strain >= 65 then
        return Text.mind.tiredSummary
    end
    if mind.stress >= 65 then
        return Text.mind.stressSummary
    end
    for _, c in pairs(mind.concerns) do
        if c.kind == "dead" then
            return Text.mind.griefSummary
        end
        if mind.lastAt - c.at <= 2 then
            return Text.mind.familySummary
        end
    end
    if mind.loneliness >= 65 then
        return Text.mind.lonelySummary
    end
    if mind.morale < 30 then
        return Text.mind.moraleSummary
    end
    return Text.mind.calmSummary
end

function Mind.reply(person, visitorId)
    local mind = person.mind
    if not mind or not mind.policy.enabled then
        return nil
    end
    local rel = person.relationships[visitorId] or {}
    if (rel.fear or 0) >= 60 or (rel.trust or 0) < -20 then
        return Text.mind.distrust
    end
    local memory = recent(person, visitorId)
    if memory and (memory.kind == "attacked" or memory.kind == "betrayed") then
        return Text.mind.violence
    end
    if mind.strain >= 65 then
        return Text.mind.tired
    end
    if mind.stress >= 65 then
        return Text.mind.shaken
    end
    local ids = {}
    for id in pairs(mind.concerns) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local c = mind.concerns[id]
        if c.kind == "dead" then
            return Text.mind.grieving
        end
        if mind.lastAt - c.at <= 2 then
            return Text.mind.familyHurt
        end
    end
    if memory and memory.kind == "helped_family" then
        return Text.mind.familyHelped
    end
    if mind.loneliness >= 65 then
        return Text.mind.lonely
    end
    if mind.morale < 20 then
        return Text.mind.hopeless
    end
    return nil
end

function Mind.interact(person, actorId, topic, now)
    if topic ~= "listen" and topic ~= "reassure" and topic ~= "apologise" then
        return { ok = false, code = "unknown_conversation_topic" }
    end
    local mind = Mind.ensure(person, now)
    if not mind.policy.enabled then
        return { ok = false, code = "living_survivors_disabled" }
    end
    local rel = person.relationships[actorId] or { trust = 0, fear = 0 }
    if rel.trust < -20 or rel.fear >= 60 then
        return {
            ok = true,
            code = "conversation",
            message = Text.mind.space,
        }
    end
    -- One shared cooldown, not one per topic: rotating buttons cannot farm relief.
    if mind.lastConversationAt and now - mind.lastConversationAt < Settings.conversation.cooldownHours then
        return { ok = true, code = "conversation", message = Text.mind.cooldown }
    end
    mind.lastConversationAt = now
    mind.contacts[actorId] = { at = now, topic = topic }
    local count, oldest = 0, nil
    for id, c in pairs(mind.contacts) do
        count = count + 1
        if not oldest or c.at < mind.contacts[oldest].at or c.at == mind.contacts[oldest].at and id < oldest then
            oldest = id
        end
    end
    if count > Mind.MAX_CONTACTS then
        mind.contacts[oldest] = nil
    end
    if topic == "apologise" then
        return {
            ok = true,
            code = "conversation",
            message = Text.mind.apology,
        }
    end
    mind.loneliness = clamp(mind.loneliness - Settings.conversation.lonelinessRelief)
    if topic == "reassure" then
        mind.stress = clamp(
            mind.stress
                - (
                    rel.trust >= Settings.conversation.reassuranceTrust
                        and Settings.conversation.trustedStressRelief
                    or Settings.conversation.strangerStressRelief
                )
        )
        return {
            ok = true,
            code = "conversation",
            message = rel.trust >= Settings.conversation.reassuranceTrust and Text.mind.reassured or Text.mind.cautious,
        }
    end
    mind.morale = clamp(mind.morale + Settings.conversation.listeningMorale)
    return {
        ok = true,
        code = "conversation",
        message = Mind.reply(person, actorId)
            or (mind.personality.sociability >= 55 and Text.mind.talkative or Text.mind.quiet),
    }
end

function Mind.attacked(person, actorId, eventId, now)
    if not Mind.remember(person, "attacked", actorId, eventId, now) then
        return false
    end
    local mind = person.mind
    if not mind.policy.enabled then
        return false
    end
    local rel = person.relationships[actorId] or { trust = 0, affection = 0, respect = 0, fear = 0, anchors = {} }
    person.relationships[actorId] = rel
    -- Compress repeated violence to one enduring grievance per attacker.
    local key = "violence:" .. actorId
    if not rel.anchors[key] then
        rel.trust = clamp(rel.trust - 35, -100, 100)
        rel.affection = clamp(rel.affection - 20, -100, 100)
        rel.fear = clamp(rel.fear + 35, -100, 100)
        rel.anchors[key] = { event = "attacked", gameTime = now }
    end
    mind.stress = clamp(mind.stress + 20)
    mind.morale = clamp(mind.morale - 8)
    return true
end

function Mind.social(person, kind, actorId, eventId, now, relatedId)
    if not Mind.remember(person, kind, actorId, eventId, now, relatedId) then
        return
    end
    local mind = person.mind
    if not mind.policy.enabled then
        return
    end
    if kind == "betrayed" then
        mind.morale = clamp(mind.morale - 20)
        mind.stress = clamp(mind.stress + 20)
    elseif kind == "helped_family" then
        mind.morale = clamp(mind.morale + 8)
        mind.stress = clamp(mind.stress - 8)
    elseif kind == "kept_promise" then
        mind.morale = clamp(mind.morale + 3)
    end
end
-- Plans are intentions only. Native coordinator validates each destination and
-- owns movement; these never complete a job, heal somebody or consume supplies.

Mind.plan = Plans.choose
return Mind
