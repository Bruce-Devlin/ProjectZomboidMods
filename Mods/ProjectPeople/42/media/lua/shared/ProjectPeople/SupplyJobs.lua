-- Local, original-item supply work. Storage selection and all effects are
-- authority-owned. No loot generation, abstract rewards or offscreen travel.
local Core = require "ProjectPeople/Core"
local Inventory = require "ProjectPeople/NativeInventory"
local Jobs = { VERSION = 1 }
local supported = { ["Base.Bandage"] = true, ["Base.RippedSheets"] = true }

local function fail(code)
    return { ok = false, code = code }
end

local function canCommand(w, p, who)
    local c = p and p.communityId and w.communities[p.communityId]
    local actor = w.people[who.personId]
    return actor
        and actor.life ~= "dead"
        and p
        and p.recruited
        and p.controller.kind == "ai"
        and (
            p.commanderId == who.personId
            or c and actor.communityId == p.communityId and c.commanders[who.personId] == true
        )
end

local function near(actor, square)
    local current = actor:getCurrentSquare()
    return current
        and square
        and math.floor(actor:getZ()) == square:getZ()
        and math.abs(current:getX() - square:getX()) <= 1
        and math.abs(current:getY() - square:getY()) <= 1
        and (current == square or current:canReachTo(square))
end

local function approach(actor, square)
    -- Furniture squares are commonly solid. Path to reachable floor beside
    -- the container; the transfer adapter still checks the actual container.
    local best, bestDistance
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local at = getCell():getGridSquare(square:getX() + d[1], square:getY() + d[2], square:getZ())
        if
            at
            and at:getRoom() == square:getRoom()
            and at:TreatAsSolidFloor()
            and at:isFree(false)
            and at:canReachTo(square)
        then
            local distance = (at:getX() + 0.5 - actor:getX()) ^ 2 + (at:getY() + 0.5 - actor:getY()) ^ 2
            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                best = { x = at:getX() + 0.5, y = at:getY() + 0.5, z = at:getZ() }
            end
        end
    end
    return best
end

function Jobs.new(config)
    local auth, md = config.authority, config.metadata
    md.storage = md.storage or {}
    md.storageChoices = md.storageChoices or {}
    local adapters, dispatching, progress = {}, {}, {}
    local self = {}
    local function resolveStorage(id)
        local r = md.storage[id]
        if not r then
            return nil
        end
        local sq = getCell():getGridSquare(r.x, r.y, r.z)
        if not sq then
            return nil
        end
        local objects = sq:getObjects()
        local found
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            if o:getModData().ProjectPeopleStorageId == id then
                assert(not found, "duplicate_storage_identity")
                found = o
            end
        end
        if not found then
            return nil
        end
        return found:getContainerByIndex(r.containerIndex), found, sq
    end
    local function owners()
        local map = {}
        local world = auth:snapshot()
        for id, p in pairs(world.people) do
            local a = config.actor(id)
            if a and not a:isDead() then
                map["person:" .. id] = a:getInventory()
            end
        end
        for id in pairs(md.storage) do
            map[id] = resolveStorage(id)
        end
        return { complete = true, owners = map }
    end
    local function adapter(personId)
        if not adapters[personId] then
            local context = auth:adapterContext()
            adapters[personId] = assert(Inventory.new(context.world, {
                persistentZombieWorkers = true,
                authority = function()
                    return {
                        authority = true,
                        system = true,
                        issuer = "supply-runtime",
                        actorId = personId,
                        character = config.actor(personId),
                    }
                end,
                resolve = owners,
                persist = context.persist,
            }))
        end
        return adapters[personId]
    end
    local function checkpoint(job, phase, reason)
        job.phase, job.reason = phase, reason
        local result = auth:checkpointJob(job, {
            evidence = {
                kind = "job_progress",
                validated = true,
                jobId = job.id,
                personId = job.personId,
                phase = phase,
                safeReturnValidated = job.safeReturned,
            },
        })
        assert(result.ok, result.code)
        return result
    end
    local function stopped(job, reason)
        config.order(job.personId, nil)
        return checkpoint(job, "blocked", reason)
    end
    function self:reconcile(job)
        if job.phase ~= "blocked" and job.phase ~= "unknown" then
            return fail "job_must_be_paused_for_reconciliation"
        end
        local worker = config.actor(job.personId)
        if not worker or worker:isDead() then
            return fail "person_unavailable"
        end
        config.order(job.personId, nil)
        if worker:isMoving() or worker:isBehaviourMoving() or worker:getPath2() ~= nil then
            return fail "wait_for_worker_to_stop"
        end
        if job.transferId then
            local result = auth:runAdapter(adapter(job.personId), "reconcile", job.transferId)
            if not result.ok then
                return result
            end
        end
        local resolved = owners().owners
        local world = auth:snapshot()
        for _, item in pairs(world.items) do
            if not resolved[item.owner] then
                return fail "known_inventory_not_loaded"
            end
        end
        local wanted, seen, byOwner = {}, {}, {}
        for _, id in ipairs(job.items) do
            wanted[id] = true
        end
        for owner, container in pairs(resolved) do
            local list = container:getItems()
            for i = 0, list:size() - 1 do
                local item = list:get(i)
                local id = Inventory.itemId(item)
                if wanted[id] then
                    if seen[id] then
                        return fail "duplicate_native_item_identity"
                    end
                    seen[id] = owner
                    byOwner[owner] = byOwner[owner] or {}
                    byOwner[owner][#byOwner[owner] + 1] = {
                        id = id,
                        data = {
                            fullType = item:getFullType(),
                            condition = item:getCondition(),
                            count = item:getCount(),
                            weight = item:getUnequippedWeight(),
                        },
                    }
                end
            end
        end
        for _, id in ipairs(job.items) do
            if not seen[id] then
                return fail "native_item_not_found"
            end
        end
        for owner, items in pairs(byOwner) do
            local observed = auth:applySystem(
                "inventory.observe",
                { owner = owner, inventoryKind = md.storage[owner] and "container" or nil, items = items },
                { evidence = { kind = "inventory_scan", validated = true, owner = owner, uniqueItems = true } }
            )
            if not observed.ok then
                return observed
            end
        end
        local _, _, destination = resolveStorage(job.destination)
        return auth:applySystem("job.resume", { jobId = job.id }, {
            evidence = {
                kind = "job_resume",
                validated = true,
                jobId = job.id,
                uniqueItems = true,
                owners = seen,
                workerStopped = true,
                atSafeEndpoint = near(worker, destination),
            },
        })
    end
    function self:request(caller, kind, fields)
        local who = config.identity(caller)
        local world = auth:snapshot()
        if not who or not who.alive then
            return fail "living_character_required"
        end
        if type(fields) ~= "table" then
            return fail "invalid_request"
        end
        if kind == "storage.mark" then
            if fields.role ~= "source" and fields.role ~= "destination" then
                return fail "storage_role_required"
            end
            for _, key in ipairs({ "x", "y", "z", "objectIndex", "containerIndex" }) do
                local n = fields[key]
                if type(n) ~= "number" or n ~= n or math.abs(n) > 1000000 or n % 1 ~= 0 then
                    return fail "invalid_storage_locator"
                end
            end
            local sq = getCell():getGridSquare(fields.x, fields.y, fields.z)
            if not sq or not sq:getRoom() or not near(caller, sq) then
                return fail "storage_out_of_reach"
            end
            local list = sq:getObjects()
            if fields.objectIndex < 0 or fields.objectIndex >= list:size() or fields.containerIndex < 0 then
                return fail "storage_changed"
            end
            local obj = list:get(fields.objectIndex)
            local container = obj:getContainerByIndex(fields.containerIndex)
            if
                not container
                or instanceof(obj, "IsoGameCharacter")
                or instanceof(obj, "IsoDeadBody")
                or instanceof(obj, "BaseVehicle")
                or container:getContainingItem()
            then
                return fail "existing_building_storage_required"
            end
            local data = obj:getModData()
            local id = data.ProjectPeopleStorageId
            if not id then
                id = "container:" .. md.worldId .. ":" .. tostring(world.revision) .. ":" .. ZombRand(1000000)
                data.ProjectPeopleStorageId = id
                obj:transmitModData()
            end
            if md.storage[id] and md.storage[id].containerIndex ~= fields.containerIndex then
                return fail "one_storage_compartment_supported"
            end
            md.storage[id] = { x = fields.x, y = fields.y, z = fields.z, containerIndex = fields.containerIndex }
            md.storageChoices[who.personId] = md.storageChoices[who.personId] or {}
            md.storageChoices[who.personId][fields.role] = id
            return { ok = true, code = "storage_marked", role = fields.role }
        end
        local p = world.people[fields.personId]
        if not canCommand(world, p, who) then
            return fail "not_authorised"
        end
        if kind == "job.resume" then
            local job = p.jobId and Core.snapshot(world.jobs[p.jobId])
            return job and self:reconcile(job) or fail "no_active_job"
        end
        if kind == "job.recall" then
            local job = p.jobId and Core.snapshot(world.jobs[p.jobId])
            if not job then
                return fail "no_active_job"
            end
            if job.phase ~= "outward" and job.phase ~= "returning" then
                return fail "job_outcome_requires_reconciliation"
            end
            job.recall = true
            checkpoint(job, "returning")
            config.order(p.id, nil)
            return { ok = true, code = "job_return_requested" }
        end
        if kind ~= "job.start" then
            return fail "request_not_supported"
        end
        local worker = config.actor(p.id)
        if
            not worker
            or worker:isDead()
            or p.jobId
            or p.missionId
            or p.reservationId
            or p.protectionHold
            or not p.available
        then
            return fail "person_unavailable"
        end
        local choice = md.storageChoices[who.personId] or {}
        if not choice.source or not choice.destination or choice.source == choice.destination then
            return fail "mark_two_storage_containers"
        end
        local source, sourceObject, pickup = resolveStorage(choice.source)
        local destination, destinationObject, home = resolveStorage(choice.destination)
        if not source or not destination or not near(caller, home) then
            return fail "storage_out_of_reach"
        end
        if
            not pickup:getRoom()
            or not home:getRoom()
            or pickup:getRoom():getBuilding() ~= home:getRoom():getBuilding()
            or (pickup:getX() - home:getX()) ^ 2 + (pickup:getY() - home:getY()) ^ 2 > 256
        then
            return fail "local_building_job_required"
        end
        local items = {}
        local list = source:getItems()
        for i = 0, list:size() - 1 do
            local item = list:get(i)
            if #items < 8 and supported[item:getFullType()] and not item:isFavorite() and item:getCount() == 1 then
                items[#items + 1] = Inventory.itemId(item)
            end
        end
        if #items == 0 then
            return fail "no_supported_supplies"
        end
        local job = {
            id = "haul:" .. world.revision .. ":" .. p.id,
            personId = p.id,
            source = choice.source,
            destination = choice.destination,
            items = items,
            pickup = { x = pickup:getX() + 0.5, y = pickup:getY() + 0.5, z = pickup:getZ() },
            home = { x = home:getX() + 0.5, y = home:getY() + 0.5, z = home:getZ() },
            recall = false,
            safeReturned = false,
            phase = "outward",
        }
        checkpoint(job, "outward")
        return { ok = true, code = "supply_job_started", jobId = job.id }
    end
    local function transfer(job, source, destination, phase)
        checkpoint(job, phase)
        local ad = adapter(job.personId)
        local prepared =
            auth:runAdapter(ad, "prepare", { source = source, destination = destination, items = job.items })
        if not prepared.ok then
            return stopped(job, prepared.code .. ":" .. tostring(prepared.detail))
        end
        job.transferId = prepared.operationId
        checkpoint(job, phase .. "_prepared")
        dispatching[job.id] = true
        local sent = auth:runAdapter(ad, "dispatch", job.transferId)
        if not sent.ok then
            return stopped(job, sent.code .. ":" .. tostring(sent.detail))
        end
        local result = auth:runAdapter(ad, "reconcile", job.transferId)
        if not result.ok then
            return stopped(job, result.code .. ":" .. tostring(result.detail))
        end
        job.transferId = nil
        dispatching[job.id] = nil
        if phase == "collecting" then
            checkpoint(job, "returning")
            config.order(job.personId, nil)
        else
            checkpoint(job, "completed")
            config.order(job.personId, nil)
        end
    end
    function self:tick(personId, activeEncounter)
        local world = auth:snapshot()
        local p = world.people[personId]
        local job = p and p.jobId and Core.snapshot(world.jobs[p.jobId])
        if not job then
            return false
        end
        local actor = config.actor(personId)
        if not actor or actor:isDead() then
            return true, "Worker unavailable"
        end
        if job.phase == "blocked" or job.phase == "unknown" then
            return true, "Job paused: " .. tostring(job.reason)
        end
        if not activeEncounter then
            progress[job.id] = nil
            config.order(personId, nil)
            return true, "Waiting for a safe local encounter"
        end
        if job.phase ~= "outward" and job.phase ~= "returning" then
            -- Prepared/dispatched work restored from a save must be reconciled,
            -- never replayed merely because its in-memory callback disappeared.
            stopped(job, "saved_transfer_requires_reconciliation")
            return true, "Job needs reconciliation"
        end
        local goal = job.phase == "outward" and job.pickup or job.home
        local sq = getCell():getGridSquare(math.floor(goal.x), math.floor(goal.y), goal.z)
        if not sq then
            stopped(job, "storage_chunk_not_loaded")
            return true, "Storage unavailable"
        end
        if not near(actor, sq) then
            local target = approach(actor, sq)
            if not target then
                stopped(job, "storage_access_blocked")
                return true, "Storage access blocked"
            end
            local previous = progress[job.id]
            local now = getTimestampMs()
            if
                not previous
                or previous.phase ~= job.phase
                or (actor:getX() - previous.x) ^ 2 + (actor:getY() - previous.y) ^ 2 > 0.04
            then
                progress[job.id] = { x = actor:getX(), y = actor:getY(), phase = job.phase, at = now }
            elseif now - previous.at > 20000 then
                progress[job.id] = nil
                stopped(job, "storage_path_blocked")
                return true, "Path blocked; supplies retained"
            end
            config.order(personId, target)
            return true, job.phase == "outward" and "Collecting supplies" or "Returning supplies"
        end
        progress[job.id] = nil
        config.order(personId, nil)
        if job.phase == "outward" then
            transfer(job, job.source, "person:" .. personId, "collecting")
        else
            job.safeReturned = true
            checkpoint(job, "home")
            if job.recall and not world.operations[job.transferId or ""] then
                local allSource = true
                for _, id in ipairs(job.items) do
                    if world.items[id] and world.items[id].owner ~= job.source then
                        allSource = false
                    end
                end
                if allSource then
                    checkpoint(job, "recalled")
                    return true, "Returned without collection"
                end
            end
            transfer(job, "person:" .. personId, job.destination, "storing")
        end
        return true, "Supply job updated"
    end
    function self:storage()
        return Core.snapshot(md.storageChoices)
    end
    return self
end
return Jobs
