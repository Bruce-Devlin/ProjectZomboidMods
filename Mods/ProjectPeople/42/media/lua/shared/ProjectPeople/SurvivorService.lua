-- Discovery, player requests and filtered survivor views over the saved authority.
local Authority = require "ProjectPeople/Authority"
local Core = require "ProjectPeople/Core"
local Conversation = require "ProjectPeople/Behaviour/Conversation"
local Codec = require "ProjectPeople/Codec"
local Mind = require "ProjectPeople/Behaviour/Mind"
local Trust = require "ProjectPeople/Behaviour/Trust"
local Danger = require "ProjectPeople/InteractionDanger"
local SocialGroup = require "ProjectPeople/Behaviour/Groups"
local FriendlyFire = require "ProjectPeople/FriendlyFire"
local Service = { VERSION = 1 }

function Service.open(config)
    local authority, problem = Authority.open(config)
    if not authority then
        return nil, problem
    end
    local self = { authority = authority, known = {}, receipts = {}, receiptOrder = {}, signatures = {} }
    local function groupReady(caller, target, world)
        for _, id in ipairs(SocialGroup.members(world, target, true)) do
            if
                config.available and not config.available(id)
                or config.groupAvailable and not config.groupAvailable(caller, id)
                or config.interactionDanger and config.interactionDanger(id, world.people[id])
            then
                return false
            end
        end
        return true
    end
    function self:discover(caller)
        local registered = authority:registerPlayer(caller)
        if not registered.ok then
            return registered
        end
        local id = registered.personId
        self.known[id] = self.known[id] or {}
        local nearby = config.nearby(caller) or {}
        local world = authority:snapshot()
        local me = world.people[id]
        local newlyMet = {}
        for known in pairs(me.knowledge) do
            if world.people[known] then
                self.known[id][known] = true
            end
        end
        for _, personId in ipairs(nearby) do
            if not me.knowledge[personId] and #newlyMet < 40 then
                newlyMet[#newlyMet + 1] = personId
            end
        end
        if #newlyMet > 0 then
            local saved = authority:applySystem(
                "person.discover",
                { personId = id },
                { evidence = { kind = "person_discovery", validated = true, personId = id, nearby = newlyMet } }
            )
            if not saved.ok then
                return saved
            end
        end
        for _, personId in ipairs(nearby) do
            self.known[id][personId] = true
        end
        return { ok = true, personId = id, nearby = nearby }
    end
    function self:seed(home)
        return authority:seedHousehold(home)
    end
    function self:bindInitial(personId)
        return authority:observe("person.bind_initial", { personId = personId })
    end
    function self:request(caller, request)
        if type(request) ~= "table" or type(request.id) ~= "string" or #request.id == 0 or #request.id > 128 then
            return { ok = false, code = "invalid_request" }
        end
        local identity = config.authenticate(caller)
        if not identity or not identity.validated or (not identity.alive and request.kind ~= "succession.reserve") then
            return { ok = false, code = "living_character_required" }
        end
        local key = identity.personId .. ":" .. request.id
        local signature = Codec.encode(request)
        if not signature or #signature > 32768 then
            return { ok = false, code = "invalid_request" }
        end
        if self.receipts[key] then
            if self.signatures[key] ~= signature then
                return { ok = false, code = "request_identity_reused" }
            end
            return Core.snapshot(self.receipts[key])
        end
        -- Missions stay unavailable until native departure, cargo and safe-return
        -- adapters are connected. A UI must never acknowledge imaginary work.
        local result
        local target = type(request.fields) == "table" and request.fields.personId
        if request.kind == "succession.reserve" and type(config.succession) == "function" then
            result = config.succession(caller, target)
        elseif target and config.available and not config.available(target) then
            result = { ok = false, code = "person_unavailable" }
        elseif
            target
            and Danger.guards(request.kind)
            and config.interactionDanger
            and config.interactionDanger(target, authority:snapshot().people[target])
        then
            result = Danger.refusal()
        elseif
            (
                request.kind == "inventory.open"
                or request.kind == "inventory.transfer"
                or request.kind == "equipment.set"
                or request.kind == "gift.open"
                or request.kind == "inventory.gift"
            ) and type(config.equipment) == "function"
        then
            result = config.equipment(caller, request.kind, request.fields)
        elseif request.kind == "conversation.talk" then
            local close = false
            for _, id in ipairs(config.nearby(caller) or {}) do
                if id == target then
                    close = true
                end
            end
            if not close then
                result = { ok = false, code = "conversation_unconfirmed" }
            else
                local valid = true
                for field in pairs(request.fields) do
                    if field ~= "personId" and field ~= "topic" then
                        valid = false
                    end
                end
                if not valid then
                    result = { ok = false, code = "invalid_request" }
                else
                    result = Conversation.reply(
                        authority:snapshot(),
                        target,
                        identity.personId,
                        request.fields.topic,
                        config.clock()
                    )
                end
            end
        elseif request.kind == "help.secure_home" and type(config.help) == "function" then
            if request.revision ~= authority:snapshot().revision then
                result = { ok = false, code = "stale_revision" }
            else
                result = config.help(caller, authority)
            end
        elseif
            (
                request.kind == "storage.mark"
                or request.kind == "job.start"
                or request.kind == "job.recall"
                or request.kind == "job.resume"
            ) and type(config.job) == "function"
        then
            if request.revision ~= authority:snapshot().revision then
                result = { ok = false, code = "stale_revision" }
            else
                result = config.job(caller, request.kind, request.fields)
            end
        elseif
            request.kind ~= "cooperation.request"
            and request.kind ~= "duty.set"
            and request.kind ~= "behaviour.interact"
            and request.kind ~= "friendly_fire.set"
        then
            result = { ok = false, code = "request_not_supported" }
        else
            if
                (request.kind == "cooperation.request" or request.kind == "duty.set")
                and not groupReady(caller, target, authority:snapshot())
            then
                result = {
                    ok = false,
                    code = "group_not_ready",
                    message = "We stay together. Everyone needs to be nearby, safe and ready.",
                }
            else
                result = authority:request(caller, request.kind, request.fields, request.revision)
                if result.code == "group_not_ready" then
                    result.message = "We stay together. Not everyone is willing and able to come."
                end
            end
        end
        self.receipts[key] = Core.snapshot(result)
        self.receiptOrder[#self.receiptOrder + 1] = key
        self.signatures[key] = signature
        if #self.receiptOrder > 256 then
            local retired = table.remove(self.receiptOrder, 1)
            self.receipts[retired] = nil
            self.signatures[retired] = nil
        end
        return result
    end
    function self:view(caller)
        local who = config.authenticate(caller)
        local discovered
        if who and who.validated and not who.alive then
            local w = authority:snapshot()
            local dead = w.people[who.personId]
            if dead and dead.life == "dead" and w.controllers[who.controllerId] == dead.id then
                discovered = { ok = true, personId = dead.id, nearby = {} }
                self.known[dead.id] = self.known[dead.id] or {}
            end
        end
        discovered = discovered or self:discover(caller)
        if not discovered.ok then
            return { status = { ready = false, blocked = discovered.code } }
        end
        local world = authority:snapshot()
        local me = world.people[discovered.personId]
        local visible = {}
        visible[me.id] = true
        for id in pairs(self.known[me.id]) do
            visible[id] = true
        end
        for id, p in pairs(world.people) do
            if p.commanderId == me.id then
                visible[id] = true
            end
        end
        local view = {
            schema = world.schema,
            worldId = world.worldId,
            timelineId = world.timelineId,
            revision = world.revision,
            people = {},
            communities = {},
            missions = {},
            parties = {},
        }
        for id in pairs(visible) do
            local p = world.people[id]
            if p then
                local shown = {
                    id = id,
                    name = p.name,
                    background = p.background,
                    life = p.life,
                    controller = Core.snapshot(p.controller),
                    communityId = p.communityId,
                    commanderId = p.commanderId,
                    partyId = p.partyId,
                    duty = p.duty,
                    recruited = p.recruited,
                    family = {},
                    revision = p.revision,
                }
                if id ~= me.id and p.controller.kind == "ai" then
                    shown.trust = Trust.summary(p, me.id)
                end
                if p.controller.kind == "ai" then
                    shown.friendlyFire = p.friendlyFire == true
                    shown.canSetFriendlyFire = FriendlyFire.canSet(world, id, me.id)
                end
                if p.commanderId == me.id or id == me.id then
                    shown.jobId = p.jobId
                    if p.jobId and world.jobs and world.jobs[p.jobId] then
                        shown.job = Core.snapshot(world.jobs[p.jobId])
                    end
                    shown.cargo = {}
                    for itemId, item in pairs(world.items) do
                        if item.owner == "person:" .. id then
                            shown.cargo[#shown.cargo + 1] = { id = itemId, type = item.data.fullType }
                        end
                    end
                end
                for relative, relationship in pairs(p.family) do
                    if visible[relative] then
                        shown.family[relative] = relationship
                    end
                end
                -- Only current nearby observations reveal mood; a roster is not
                -- a live window into somebody's private distant mental state.
                for _, nearId in ipairs(discovered.nearby) do
                    if nearId == id then
                        shown.wellbeing = Mind.summary(p)
                        shown.personalConversations = not p.mind or p.mind.policy.enabled
                        shown.home = p.home and Core.snapshot(p.home) or nil
                        shown.interactionBusy = p.reservationId ~= nil or p.transitionId ~= nil or p.missionId ~= nil
                        shown.interactionDanger = config.interactionDanger and config.interactionDanger(id, p) == true
                            or false
                        local travel, travelReason = Core.decide(world, id, me.id, "travel")
                        local resident, residentReason = Core.decide(world, id, me.id, "resident")
                        if not groupReady(caller, id, world) then
                            travel, travelReason = false, "group_not_ready"
                            resident, residentReason = false, "group_not_ready"
                        end
                        shown.cooperation = {
                            travel = { accepted = travel, reason = travelReason },
                            resident = { accepted = resident, reason = residentReason },
                        }
                        break
                    end
                end
                view.people[id] = shown
                local community = p.communityId and world.communities[p.communityId]
                if community and not view.communities[p.communityId] then
                    view.communities[p.communityId] =
                        { id = community.id, name = community.name, commanders = Core.snapshot(community.commanders) }
                end
            end
        end
        local status = authority:status()
        status.actions = {
            ["conversation.talk"] = true,
            ["behaviour.interact"] = true,
            ["cooperation.request"] = true,
            ["duty.set"] = true,
            ["help.secure_home"] = type(config.help) == "function",
            ["mission.propose"] = { enabled = false, reason = "Independent expeditions are not connected yet." },
            ["mission.authorise"] = false,
            ["mission.recall"] = false,
        }
        status.actions["storage.mark"] = type(config.job) == "function"
        status.actions["friendly_fire.set"] = true
        status.actions["inventory.open"] = type(config.equipment) == "function"
        status.actions["gift.open"] = type(config.equipment) == "function"
        status.actions["job.start"] = type(config.job) == "function"
        status.actions["job.recall"] = type(config.job) == "function"
        status.actions["job.resume"] = type(config.job) == "function"
        return {
            world = view,
            personId = me.id,
            nearby = discovered.nearby,
            status = status,
            succession = not who.alive and type(config.successors) == "function" and config.successors(caller) or nil,
        }
    end
    return self
end
return Service
