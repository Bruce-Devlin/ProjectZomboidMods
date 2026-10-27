-- Session-only development encounter. One server record; clients cannot author
-- health or identity. Native replication supplies physical locomotion.
local State = { ID = "pp-dev-encounter-ellis", BUILD = "encounter-20261022-z3" }

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1000000
end

function State.new(owner, x, y, z)
    return {
        personId = State.ID,
        name = "Ellis",
        owner = owner,
        x = x,
        y = y,
        z = z,
        health = 100,
        revision = 1,
        epoch = 0,
        mode = "wait",
        damageCount = 0,
        reportSeq = 0,
        lastReport = 0,
        build = State.BUILD,
    }
end

function State.copy(s)
    local c = {}
    for k, v in pairs(s) do
        c[k] = v
    end
    return c
end

function State.command(s, kind, a)
    if kind == "move" then
        if
            not finite(a.x)
            or not finite(a.y)
            or not finite(a.z)
            or a.z ~= s.z
            or (a.x - s.x) ^ 2 + (a.y - s.y) ^ 2 > 64
        then
            return false, "destination_out_of_range"
        end
        s.goalX, s.goalY, s.goalZ = a.x, a.y, a.z
        s.mode = "move"
    elseif kind == "wait" then
        s.mode = "wait"
    elseif kind == "damage" then
        if s.damageCount ~= 0 then
            return false, "damage_already_applied"
        end
        s.health = 90
        s.damageCount = 1
    else
        return false, "unknown_command"
    end
    if kind ~= "damage" then
        s.epoch = s.epoch + 1
        s.reportSeq = 0
    end
    s.revision = s.revision + 1
    return true, "accepted"
end

function State.report(s, caller, a, now)
    if caller ~= s.owner then
        return false, "not_simulator"
    end
    if a.personId ~= s.personId or a.epoch ~= s.epoch then
        return false, "stale_assignment"
    end
    if not finite(a.seq) or a.seq <= s.reportSeq then
        return false, "stale_report"
    end
    if not finite(a.x) or not finite(a.y) or not finite(a.z) or a.z ~= s.z then
        return false, "invalid_position"
    end
    local allowance = math.min(1.5, 0.35 + math.max(0, now - s.lastReport) / 1000 * 3)
    if (a.x - s.x) ^ 2 + (a.y - s.y) ^ 2 > allowance ^ 2 then
        return false, "position_discontinuity"
    end
    if s.mode ~= "move" and (a.x - s.x) ^ 2 + (a.y - s.y) ^ 2 > 0.04 then
        return false, "movement_while_waiting"
    end
    if s.mode == "move" and a.result == "arrived" and (a.x - s.goalX) ^ 2 + (a.y - s.goalY) ^ 2 > 0.36 then
        return false, "arrival_not_observed"
    end
    s.x, s.y, s.z = a.x, a.y, a.z
    s.reportSeq = a.seq
    s.lastReport = now
    if s.mode == "move" then
        if a.result == "arrived" then
            s.mode = "wait"
        elseif a.result == "blocked" or a.result == "unknown" or a.result == "interrupted" then
            s.mode = "blocked"
        end
    end
    s.revision = s.revision + 1
    return true, "observed"
end
return State
