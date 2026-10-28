-- The native NPC's aggregate health is authoritative. No parallel wound model.
local Trust = require "ProjectPeople/Behaviour/Trust"
local Equipment = require "ProjectPeople/PeopleEquipment"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Service = { TREAT_MS = 8000, RECOVERY_MS = 60000 }
local function fail(message, code)
    return { ok = false, code = code or "treatment_refused", message = message }
end

function Service.new(config)
    local self = { pending = {} }
    local function access(caller, id, treating)
        if isClient() then
            return nil, fail "Only the world authority can provide care."
        end
        local who = config.identity(caller)
        local world = config.authority:snapshot()
        local p = world.people[id]
        if
            not who
            or not who.validated
            or not who.alive
            or world.controllers[who.controllerId] ~= who.personId
            or not p
            or p.controller.kind ~= "ai"
            or p.commanderId ~= who.personId
            or not p.partyId
            or p.life == "dead"
            or p.reservationId
            or p.transitionId
            or p.jobId
            or p.missionId
        then
            return nil, fail("You can provide care to your nearby travelling companions.", "not_authorised")
        end
        local actor, record = config.actor(id)
        if
            not actor
            or not record
            or actor:isDead()
            or Space.distance(caller, actor) > 3 ^ 2
            or not Space.clear(caller, actor)
        then
            return nil, fail "Move within three tiles with a clear path to your companion."
        end
        if treating then
            if config.danger(id, p) or caller:isOnFire() or caller:isKnockedDown() then
                return nil, fail "Get both of you somewhere safe before providing care."
            elseif not caller:getCharacterActions():isEmpty() then
                return nil, fail "Finish your current action before providing care."
            elseif caller:getVehicle() or actor:getVehicle() then
                return nil, fail "Get out of the vehicle before providing care."
            end
            -- Native bMoving can outlive an arrived path. Actual position is
            -- checked throughout care; any movement cancels before consumption.
        end
        return { actor = actor, record = record, person = p, world = world, who = who, md = actor:getModData() }
    end
    local function version(a)
        return string.format("%.6f:%d", a.actor:getHealth(), a.md.ProjectPeopleHealthRevision or 0)
    end
    local function supplies(caller, world)
        local result = {}
        for _, entry in ipairs(Equipment.scan(caller).order) do
            local item = entry.item
            local registered = world.items[entry.id]
            if
                item:getBandagePower() > 0
                and not item:getType():find("Dirty", 1, true)
                and not item:isFavorite()
                and item:getJobDelta() == 0
                and not item:getIsCraftingConsumed()
                and not Equipment.active(caller, item)
                and not (registered and registered.lock)
            then
                result[#result + 1] = entry
            end
        end
        return result
    end
    local function describe(caller, a)
        local items = {}
        for _, entry in ipairs(supplies(caller, a.world)) do
            items[#items + 1] = { id = entry.id, name = entry.item:getDisplayName() }
        end
        local pending = self.pending[a.person.id]
        return {
            personId = a.person.id,
            name = a.person.name,
            version = version(a),
            health = math.max(0, math.min(100, a.actor:getHealth() * 100)),
            onFire = a.actor:isOnFire(),
            knockedDown = a.actor:isKnockedDown(),
            supplies = items,
            treating = pending ~= nil,
            remaining = pending and math.max(0, math.ceil((pending.finish - config.now()) / 1000)) or 0,
            cooldown = math.max(0, math.ceil(((a.md.ProjectPeopleNextCare or 0) - config.now()) / 1000)),
            message = a.md.ProjectPeopleCareMessage,
        }
    end
    function self:request(caller, kind, fields)
        if type(fields) ~= "table" or type(fields.personId) ~= "string" then
            return fail "Invalid health request."
        end
        for key in pairs(fields) do
            if key ~= "personId" and key ~= "version" and key ~= "itemId" then
                return fail "Invalid health request."
            end
        end
        local a, problem = access(caller, fields.personId, kind == "health.treat")
        if not a then
            return problem
        end
        if kind == "health.open" then
            return { ok = true, code = "health_view", health = describe(caller, a) }
        end
        if kind ~= "health.treat" then
            return fail "Unknown health action."
        end
        if self.pending[a.person.id] then
            return fail "Care is already in progress. Keep still."
        end
        if fields.version ~= version(a) then
            return fail("Their condition changed. Refresh before treating them.", "stale_health")
        end
        if a.actor:getHealth() >= 0.999 then
            return fail "They have no combat injuries to treat."
        end
        if config.now() < (a.md.ProjectPeopleNextCare or 0) then
            return fail "Give the last treatment time to settle before providing more care."
        end
        local chosen = nil
        for _, entry in ipairs(supplies(caller, a.world)) do
            if entry.id == fields.itemId then
                chosen = entry
            end
        end
        if not chosen then
            return fail "Choose a clean, available bandage or ripped sheet from your inventory."
        end
        self.pending[a.person.id] = {
            caller = caller,
            actor = a.actor,
            item = chosen.item,
            itemId = chosen.id,
            x = caller:getX(),
            y = caller:getY(),
            z = caller:getZ(),
            version = version(a),
            duty = a.person.duty,
            finish = config.now() + Service.TREAT_MS,
        }
        a.md.ProjectPeopleCareMessage = "Providing care. Both of you must stay still and safe for eight seconds."
        return {
            ok = true,
            code = "treatment_started",
            health = describe(caller, a),
            message = a.md.ProjectPeopleCareMessage,
        }
    end
    function self:busy(id)
        return self.pending[id] ~= nil
    end
    function self:step()
        for id, task in pairs(self.pending) do
            local a = access(task.caller, id, true)
            local moved = (task.caller:getX() - task.x) ^ 2 + (task.caller:getY() - task.y) ^ 2 > 0.35 ^ 2
                or math.abs(task.caller:getZ() - task.z) > 0.2
            local chosen = nil
            if a then
                for _, entry in ipairs(supplies(task.caller, a.world)) do
                    if entry.id == task.itemId and entry.item == task.item then
                        chosen = entry
                    end
                end
            end
            if
                not a
                or a.actor ~= task.actor
                or moved
                or a.person.duty ~= task.duty
                or version(a) ~= task.version
                or not chosen
            then
                task.actor:getModData().ProjectPeopleCareMessage =
                    "Care interrupted. No supplies were used. Refresh and try again when safe."
                self.pending[id] = nil
            elseif config.now() >= task.finish then
                -- Remove the original supply before applying any benefit. Native
                -- ModData stores the resulting health on this same body for recovery.
                chosen.container:DoRemoveItem(chosen.item)
                assert(chosen.item:getContainer() == nil, "medical_supply_remove_unconfirmed")
                a.actor:setHealth(math.min(1, a.actor:getHealth() + 0.15))
                a.md.ProjectPeopleNativeHealth = a.actor:getHealth()
                a.record.health = a.actor:getHealth() * 100
                a.md.ProjectPeopleHealthRevision = (a.md.ProjectPeopleHealthRevision or 0) + 1
                a.md.ProjectPeopleNextCare = config.now() + Service.RECOVERY_MS
                a.md.ProjectPeopleCareMessage = "Injuries treated with "
                    .. chosen.item:getDisplayName()
                    .. ". Give it a minute before providing more care."
                self.pending[id] = nil
                local reward = Trust.record(config.authority, id, a.who.personId, "healing")
                assert(reward.ok, reward.code)
                if isServer() then
                    sendRemoveItemFromContainer(chosen.container, chosen.item)
                end
            end
        end
    end
    return self
end
return Service
