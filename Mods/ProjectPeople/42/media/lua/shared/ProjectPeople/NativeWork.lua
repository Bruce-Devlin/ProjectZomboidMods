-- Bounded actual-resource work. Callers own durable jobs, native owner maps and
-- authority; this module owns locomotion/transfer sequencing, never item creation.
local Navigation = require "ProjectPeople/NativeNavigation"
ProjectPeople = ProjectPeople or {}
local Work = { PROVEN = false }
ProjectPeople.NativeWork = Work

function Work.new(config)
    assert(
        type(config) == "table"
            and type(config.resolve) == "function"
            and type(config.authorise) == "function"
            and type(config.checkpoint) == "function"
            and type(config.transfers) == "function"
            and type(config.safeReturn) == "function",
        "trusted_work_callbacks_required"
    )
    local jobs, workers = {}, {}
    local service = {}
    local function record(job)
        return {
            id = job.id,
            personId = job.personId,
            source = job.source,
            destination = job.destination,
            items = job.items,
            pickup = job.pickup,
            home = job.home,
            phase = job.phase,
            reason = job.reason,
            transferId = job.transferId,
            recall = job.recall == true,
            safeReturned = job.safeReturned == true,
        }
    end
    local function stop(job, phase, reason)
        if job.navigation then
            Navigation.cancel(job.navigation)
            job.navigation = nil
        end
        job.phase, job.reason = phase, reason
        workers[job.personId] = nil
        local ok, ack = pcall(config.checkpoint, record(job))
        if not ok or type(ack) ~= "table" or ack.ok ~= true then
            job.phase, job.reason = "unknown", "job_checkpoint_unconfirmed"
        end
        return record(job)
    end
    local function checkpoint(job, phase)
        job.phase = phase
        local ack = config.checkpoint(record(job))
        if type(ack) ~= "table" or ack.ok ~= true then
            stop(job, "unknown", "job_checkpoint_unconfirmed")
            return false
        end
        return true
    end
    local function walk(job, goal, phase)
        if not checkpoint(job, phase) then
            return
        end
        local started = Navigation.start(job.actor, goal, job.id .. ":" .. phase)
        if not started.ok then
            stop(job, "blocked", started.code)
            return
        end
        job.navigation = started.operation
    end
    local function transfer(job, source, destination, phase)
        if not checkpoint(job, phase) then
            return
        end
        local adapter = config.transfers(job.personId)
        assert(adapter, "native_transfer_adapter_required")
        local prepared = adapter:prepare({ source = source, destination = destination, items = job.items })
        if not prepared.ok then
            stop(job, "blocked", prepared.code)
            return
        end
        job.transferId = prepared.operationId
        if not checkpoint(job, phase .. "_prepared") then
            return
        end
        local dispatched = adapter:dispatch(job.transferId)
        if not dispatched.ok then
            stop(job, "unknown", dispatched.code)
            return
        end
        local observed = adapter:reconcile(job.transferId)
        if not observed.ok then
            stop(job, "unknown", observed.code)
            return
        end
        job.transferId = nil
        if phase == "collecting" then
            job.carrying = true
            walk(job, job.home, "returning")
        else
            stop(job, "completed", "original_items_delivered")
        end
    end
    function service:start(spec)
        if isClient() or isServer() then
            return { ok = false, code = "singleplayer_candidate_only" }
        end
        if
            type(spec) ~= "table"
            or type(spec.id) ~= "string"
            or jobs[spec.id]
            or type(spec.personId) ~= "string"
            or workers[spec.personId]
            or type(spec.items) ~= "table"
            or #spec.items == 0
            or #spec.items > 64
            or type(spec.home) ~= "table"
            or type(spec.pickup) ~= "table"
        then
            return { ok = false, code = "bounded_available_job_required" }
        end
        local allowed = config.authorise(spec)
        if type(allowed) ~= "table" or not allowed.ok then
            return { ok = false, code = "job_not_authorised" }
        end
        local actor = config.resolve(spec.personId)
        if not actor or actor:isDead() or not actor:isNpc() or actor:isLocalPlayer() then
            return { ok = false, code = "living_native_worker_required" }
        end
        local job = {
            id = spec.id,
            personId = spec.personId,
            actor = actor,
            items = {},
            source = spec.source,
            destination = spec.destination,
            pickup = { x = spec.pickup.x, y = spec.pickup.y, z = spec.pickup.z },
            home = { x = spec.home.x, y = spec.home.y, z = spec.home.z },
            phase = "prepared",
        }
        for i, id in ipairs(spec.items) do
            job.items[i] = id
        end
        jobs[job.id], workers[job.personId] = job, job.id
        local ok, err = pcall(function()
            if job.source == "person:" .. job.personId then
                job.carrying = true
                walk(job, job.home, "returning")
            else
                walk(job, job.pickup, "outward")
            end
        end)
        if not ok then
            stop(job, "unknown", tostring(err))
        end
        return { ok = job.phase == "outward" or job.phase == "returning", job = record(job), code = job.reason }
    end
    function service:tick(id)
        local job = jobs[id]
        if not job then
            return { ok = false, code = "job_not_found" }
        end
        if job.phase ~= "outward" and job.phase ~= "returning" then
            return record(job)
        end
        local ok, err = pcall(function()
            local result = Navigation.tick(job.navigation)
            if result.state == "moving" then
                return
            end
            job.navigation = nil
            if result.state ~= "arrived" then
                stop(job, "blocked", result.reason)
                return
            end
            if job.phase == "outward" then
                transfer(job, job.source, "person:" .. job.personId, "collecting")
            else
                -- Close accepted background death permission at independently
                -- validated home arrival BEFORE any cargo/storage operation.
                local returned = config.safeReturn(record(job), job.actor)
                if type(returned) ~= "table" or not returned.ok then
                    stop(job, "unknown", "safe_return_unconfirmed")
                    return
                end
                job.safeReturned = true
                if not checkpoint(job, "home") then
                    return
                end
                if job.carrying then
                    transfer(job, "person:" .. job.personId, job.destination, "storing")
                else
                    stop(job, "recalled", "returned_without_collection")
                end
            end
        end)
        if not ok then
            stop(job, "unknown", tostring(err))
        end
        return record(job)
    end
    function service:recall(id)
        local job = jobs[id]
        if not job then
            return { ok = false, code = "job_not_found" }
        end
        if job.phase == "outward" then
            if job.navigation then
                Navigation.cancel(job.navigation)
                job.navigation = nil
            end
            job.recall = true
            local ok, err = pcall(function()
                walk(job, job.home, "returning")
            end)
            if not ok then
                stop(job, "unknown", tostring(err))
            end
        elseif job.phase == "returning" then
            job.recall = true
        else
            return { ok = false, code = "job_outcome_requires_reconciliation" }
        end
        return record(job)
    end
    function service:observe(id)
        return jobs[id] and record(jobs[id]) or { ok = false, code = "job_not_found" }
    end
    return service
end
return Work
