-- Durable home responsibilities and work/rest clocks. No native objects in saves.
local Roles = {
    order = { "guard", "clean", "supply", "maintain" },
    labels = { guard = "Guard", clean = "Clean", supply = "Supply", maintain = "Maintain" },
    breaks = { relax = 30, snack = 60, sleep = 240 },
}

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function roll(person, cycle, salt, limit)
    local n = 5381
    local key = person.id .. ":" .. tostring(cycle) .. ":" .. salt
    for i = 1, #key do
        n = (n * 33 + key:byte(i)) % 2147483647
    end
    return n % limit
end

local function committed(p)
    return p.reservationId or p.transitionId or p.jobId or p.missionId
end

function Roles.resident(p)
    return p
        and p.controller.kind == "ai"
        and p.life == "alive"
        and p.recruited == true
        and p.commanderId ~= nil
        and p.duty == "base"
        and p.home ~= nil
end

function Roles.valid(s)
    return s == nil
        or type(s) == "table"
            and Roles.labels[s.role] ~= nil
            and (s.override == nil or Roles.labels[s.override] ~= nil)
            and finite(s.worked)
            and s.worked >= 0
            and finite(s.threshold)
            and s.threshold >= 120
            and s.threshold <= 300
            and finite(s.cycle)
            and s.cycle >= 0
            and s.cycle % 1 == 0
            and (s.lastAt == nil or finite(s.lastAt))
            and (s.breakKind == nil and s.remaining == nil or Roles.breaks[s.breakKind] ~= nil and finite(s.remaining) and s.remaining >= 0 and s.remaining <= Roles.breaks[s.breakKind])
end

function Roles.ensure(p)
    if not p.homeWork then
        p.homeWork = { role = "guard", worked = 0, threshold = 120 + roll(p, 0, "work", 181), cycle = 0 }
    end
    return p.homeWork
end

-- Fixed choices count toward the balance. Preserve an automatic role on ties.
function Roles.balance(world)
    local owners = {}
    for id, p in pairs(world.people) do
        if Roles.resident(p) and (not committed(p) or p.homeWork) then
            local group = owners[p.commanderId] or {}
            owners[p.commanderId] = group
            group[#group + 1] = id
        end
    end
    for _, ids in pairs(owners) do
        table.sort(ids)
        local counts = { guard = 0, clean = 0, supply = 0, maintain = 0 }
        for _, id in ipairs(ids) do
            local s = Roles.ensure(world.people[id])
            if s.override or committed(world.people[id]) then
                s.role = s.override or s.role
                counts[s.role] = counts[s.role] + 1
            end
        end
        for _, id in ipairs(ids) do
            local p = world.people[id]
            local s = p.homeWork
            if not s.override and not committed(p) then
                local chosen = s.role
                for _, role in ipairs(Roles.order) do
                    if counts[role] < counts[chosen] then
                        chosen = role
                    end
                end
                if s.role ~= chosen then
                    p.revision = p.revision + 1
                end
                s.role = chosen
                counts[chosen] = counts[chosen] + 1
            end
        end
    end
end

function Roles.assign(world, command, context)
    local p, owner = world.people[command.personId], world.people[context.actorId]
    if
        not Roles.resident(p)
        or not owner
        or owner.life ~= "alive"
        or owner.controller.kind ~= "player"
        or p.commanderId ~= owner.id
    then
        return { ok = false, code = "not_authorised" }
    end
    if command.role ~= "auto" and not Roles.labels[command.role] then
        return { ok = false, code = "invalid_home_role" }
    end
    if p.reservationId or p.transitionId or p.jobId or p.missionId then
        return { ok = false, code = "already_committed" }
    end
    local s = Roles.ensure(p)
    s.override = command.role ~= "auto" and command.role or nil
    p.revision = p.revision + 1
    Roles.balance(world)
    return {
        ok = true,
        code = "home_role_set",
        message = "Home role: " .. Roles.labels[s.role] .. (s.override and " (your choice)." or " (automatic)."),
    }
end

function Roles.advance(p, now, seen)
    local s = Roles.ensure(p)
    -- No unloaded/offline catch-up, travel credit or catch-up after a clock reset.
    local elapsed = s.lastAt and math.max(0, (now - s.lastAt) * 60) or 0
    if seen.continuous ~= true then
        elapsed = math.min(2, elapsed)
    end
    s.lastAt = now
    if not Roles.resident(p) or p.jobId or p.missionId or p.reservationId or p.transitionId then
        return
    end
    if s.breakKind then
        if seen.resting then
            s.remaining = math.max(0, s.remaining - elapsed)
        end
        if s.remaining <= 0 then
            s.breakKind, s.remaining, s.snacked = nil, nil, nil
            s.worked, s.cycle = 0, s.cycle + 1
            s.threshold = 120 + roll(p, s.cycle, "work", 181)
        end
    elseif seen.working then
        s.worked = s.worked + elapsed
        if s.worked >= s.threshold then
            s.breakKind = ({ "relax", "snack", "sleep" })[1 + roll(p, s.cycle, "break", 3)]
            s.remaining = Roles.breaks[s.breakKind]
        end
    end
end

function Roles.observe(world, command, context)
    local proof = context.evidence
    if
        not context.system
        or not proof
        or proof.validated ~= true
        or proof.kind ~= "home_observation"
        or type(proof.people) ~= "table"
    then
        return { ok = false, code = "home_observation_required" }
    end
    Roles.balance(world)
    for id, seen in pairs(proof.people) do
        local p = world.people[id]
        if p and p.life == "alive" and p.homeWork and not committed(p) and type(seen) == "table" then
            Roles.advance(p, context.gameTime, seen)
            p.revision = p.revision + 1
        end
    end
    return { ok = true, code = "home_observed" }
end

function Roles.summary(s)
    if not s then
        return nil
    end
    local title = Roles.labels[s.role] .. (s.override and " (your choice)" or " (automatic)")
    if s.breakKind then
        return title .. " - " .. s.breakKind .. " break, " .. math.ceil(s.remaining) .. " game minutes left"
    end
    return title .. " - work meter " .. math.min(100, math.floor(s.worked / s.threshold * 100)) .. "%"
end

return Roles
