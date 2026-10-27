-- Shared local geometry. Native navigation remains responsible for movement.
local Space = {}

function Space.distance(a, b)
    if math.abs(a:getZ() - b:getZ()) > 0.2 then
        return math.huge
    end
    return (a:getX() - b:getX()) ^ 2 + (a:getY() - b:getY()) ^ 2
end

function Space.clear(a, b)
    local from, to = a:getCurrentSquare(), b:getCurrentSquare()
    if not from or not to or from:isBlockedTo(to) or from:isSomethingTo(to) then
        return false
    end
    return tostring(
        LosUtil.lineClear(getCell(), from:getX(), from:getY(), from:getZ(), to:getX(), to:getY(), to:getZ(), false)
    ) == "Clear"
end
-- Stop at striking distance instead of pathing into the victim's centre.
-- Reserve distinct approach points when several survivors share one target.

function Space.approach(actor, target, people, reserved)
    local dx, dy = actor:getX() - target:getX(), actor:getY() - target:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then
        dx, dy, length = 1, 0, 1
    end
    dx, dy = dx / length, dy / length
    local from = actor:getCurrentSquare()
    local victim = target:getCurrentSquare()
    if not from or not victim then
        return nil
    end
    local best, score
    for _, angle in ipairs({ 0, 0.9, -0.9, 1.8, -1.8, math.pi }) do
        local c, s = math.cos(angle), math.sin(angle)
        local x, y = target:getX() + dx * c - dy * s, target:getY() + dy * c + dx * s
        local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(actor:getZ()))
        local occupied = false
        for _, p in ipairs(people) do
            if
                p.actor ~= target
                and p.kind ~= "zombie"
                and (x - p.actor:getX()) ^ 2 + (y - p.actor:getY()) ^ 2 < 0.75 ^ 2
            then
                occupied = true
            end
        end
        for _, goal in ipairs(reserved or {}) do
            if (x - goal.x) ^ 2 + (y - goal.y) ^ 2 < 0.8 ^ 2 then
                occupied = true
            end
        end
        if
            not occupied
            and sq
            and sq:isFree(false)
            and sq:TreatAsSolidFloor()
            and not sq:isWaterSquare()
            and not from:isSomethingTo(sq)
            and not from:isBlockedTo(sq)
            and not victim:isSomethingTo(sq)
            and not victim:isBlockedTo(sq)
            and tostring(
                    LosUtil.lineClear(
                        getCell(),
                        from:getX(),
                        from:getY(),
                        from:getZ(),
                        sq:getX(),
                        sq:getY(),
                        sq:getZ(),
                        false
                    )
                )
                == "Clear"
        then
            local cost = (actor:getX() - x) ^ 2 + (actor:getY() - y) ^ 2
            if not score or cost < score then
                best = { x = x, y = y, z = actor:getZ() }
                score = cost
            end
        end
    end
    return best
end

function Space.retreat(actor, target, threats)
    local dx, dy = actor:getX() - target:getX(), actor:getY() - target:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then
        dx, dy, length = 1, 0, 1
    end
    dx, dy = dx / length, dy / length
    local from = actor:getCurrentSquare()
    if not from then
        return nil
    end
    local best, score
    for _, side in ipairs({ 0, 0.65, -0.65 }) do
        local x = actor:getX() + (dx - dy * side) * 1.4
        local y = actor:getY() + (dy + dx * side) * 1.4
        local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(actor:getZ()))
        if
            sq
            and sq:isFree(false)
            and sq:TreatAsSolidFloor()
            and not sq:isWaterSquare()
            and not from:isBlockedTo(sq)
            and not from:isSomethingTo(sq)
            and tostring(
                    LosUtil.lineClear(
                        getCell(),
                        from:getX(),
                        from:getY(),
                        from:getZ(),
                        sq:getX(),
                        sq:getY(),
                        sq:getZ(),
                        false
                    )
                )
                == "Clear"
        then
            local nearest = math.huge
            for _, c in ipairs(threats) do
                if c.visible and c.kind == "zombie" then
                    nearest = math.min(nearest, (x - c.actor:getX()) ^ 2 + (y - c.actor:getY()) ^ 2)
                end
            end
            if nearest > 0.8 and (not score or nearest > score) then
                best = { x = x, y = y, z = actor:getZ() }
                score = nearest
            end
        end
    end
    return best
end
return Space
