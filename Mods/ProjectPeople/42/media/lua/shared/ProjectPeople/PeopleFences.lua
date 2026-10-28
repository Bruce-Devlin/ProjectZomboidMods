-- Tall outdoor fences for human NPC bodies. Native ClimbOverWallState casts
-- to IsoPlayer; use the zombie-compatible fence state with human high-climb
-- clips instead. No coordinates, collision flags or world tiles are rewritten.
local Fences = {}

function Fences.prepare(actor, record)
    if record.mode ~= "move" or not actor:isLocal() or actor:getVariableBoolean "ClimbingFence" then
        return
    end
    local from = actor:getCurrentSquare()
    if not from or not from.getHoppableTo then
        return
    end
    -- Native running-vault admission reads player BodyDamage (nil on these
    -- bodies). Enter low fences at walking speed, retaining our upright clip.
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local to = getCell():getGridSquare(from:getX() + d[1], from:getY() + d[2], from:getZ())
        if to and from:getHoppableTo(to) then
            actor:setRunning(false)
            actor:setSprinting(false)
            actor:setVariable("VaultOverRun", false)
            actor:setVariable("VaultOverSprint", false)
            return
        end
    end
end

local function ownMotion(actor)
    if not actor:getVariableBoolean "ProjectPeopleTallMotionOwned" then
        actor:setVariable("ProjectPeopleDeferredBeforeTall", actor:isDeferredMovementEnabled())
        actor:setVariable("ProjectPeopleTallMotionOwned", true)
    end
    actor:setDeferredMovementEnabled(false)
end

function Fences.release(actor)
    if actor:getVariableBoolean "ProjectPeopleTallMotionOwned" then
        actor:setDeferredMovementEnabled(actor:getVariableBoolean "ProjectPeopleDeferredBeforeTall")
        actor:setVariable("ProjectPeopleTallMotionOwned", false)
    end
end

local function direction(dir)
    if dir == IsoDirections.N then
        return 0, -1, true
    end
    if dir == IsoDirections.S then
        return 0, 1, true
    end
    if dir == IsoDirections.W then
        return -1, 0, false
    end
    if dir == IsoDirections.E then
        return 1, 0, false
    end
end

function Fences.edge(from, dir)
    if not from then
        return nil
    end
    local dx, dy, north = direction(dir)
    if not dx then
        return nil
    end
    local to = getCell():getGridSquare(from:getX() + dx, from:getY() + dy, from:getZ())
    if not to then
        return nil
    end
    local edge = (dx < 0 or dy < 0) and from or to
    local collide = north and IsoFlagType.collideN or IsoFlagType.collideW
    local low = north and IsoFlagType.HoppableN or IsoFlagType.HoppableW
    if edge:has(IsoFlagType.CantClimb) or edge:has(low) or not edge:has(collide) then
        return nil
    end
    local objects = edge:getObjects()
    local fence
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local props = object:getProperties()
        if
            object:getType() == IsoObjectType.wall
            and props
            and props:has(collide)
            and not props:has(IsoFlagType.CantClimb)
        then
            fence = object
            break
        end
    end
    if not fence then
        return nil
    end
    return to, edge, collide
end

local function opposite(dir)
    if dir == IsoDirections.N then
        return IsoDirections.S
    end
    if dir == IsoDirections.S then
        return IsoDirections.N
    end
    if dir == IsoDirections.W then
        return IsoDirections.E
    end
    if dir == IsoDirections.E then
        return IsoDirections.W
    end
end

local function remoteTallEdge(actor, current)
    if actor:isLocal() then
        return false
    end
    local high = false
    -- Network facing can still describe the preceding path segment. Infer an
    -- unambiguous high crossing from adjacent edges in that case. A nearby low
    -- fence makes this fallback ambiguous, so keep the native low presentation.
    for _, dir in ipairs({ IsoDirections.N, IsoDirections.S, IsoDirections.W, IsoDirections.E }) do
        local dx, dy = direction(dir)
        local other = getCell():getGridSquare(current:getX() + dx, current:getY() + dy, current:getZ())
        if other and current:getHoppableTo(other) then
            return false
        end
        if Fences.edge(current, dir) then
            high = true
        end
    end
    return high
end

function Fences.canCross(actor, dir)
    local from = actor:getCurrentSquare()
    local to, edge, collide = Fences.edge(from, dir)
    if
        not to
        or from:getBuilding()
        or to:getBuilding()
        or not from:isOutside()
        or not to:isOutside()
        or not from:TreatAsSolidFloor()
        or not to:TreatAsSolidFloor()
        or not to:isFree(false)
        or to:isWaterSquare()
        or to:isVehicleIntersecting()
        or not SafeHouse
        or SafeHouse.isSafeHouse(to, nil, false)
    then
        return false
    end
    -- No roofs, upper walls, stairs, unsafe drops, doors or windows.
    if from:HasStairs() or to:HasStairs() or from:getDoorTo(to) or from:getWindowTo(to) then
        return false
    end
    for _, sq in ipairs({ from, to }) do
        local above = getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ() + 1)
        if above and (above:TreatAsSolidFloor() or above:has(collide) or above:HasSlopedRoof()) then
            return false
        end
    end
    local occupants = to:getMovingObjects()
    for i = 0, occupants:size() - 1 do
        if occupants:get(i) ~= actor then
            return false
        end
    end
    return IsoWindow.canClimbThroughHelper(actor, from, to, dir == IsoDirections.N or dir == IsoDirections.S)
end

function Fences.hint(actor, goal)
    if not actor or not goal or not actor:getCurrentSquare() or math.abs(goal.z - actor:getZ()) > 0.2 then
        return nil
    end
    local from = actor:getCurrentSquare()
    local dx, dy = goal.x - actor:getX(), goal.y - actor:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then
        return nil
    end
    local dir
    if math.abs(dx) / length > 0.7 then
        dir = dx > 0 and IsoDirections.E or IsoDirections.W
    elseif math.abs(dy) / length > 0.7 then
        dir = dy > 0 and IsoDirections.S or IsoDirections.N
    end
    if
        dir == IsoDirections.E and goal.x < from:getX() + 1
        or dir == IsoDirections.W and goal.x >= from:getX()
        or dir == IsoDirections.S and goal.y < from:getY() + 1
        or dir == IsoDirections.N and goal.y >= from:getY()
    then
        return nil
    end
    if dir and Fences.canCross(actor, dir) then
        return { x = from:getX() + 0.5, y = from:getY() + 0.5, z = from:getZ() }
    end
end

function Fences.update(binding, record, now)
    local actor = binding.actor
    now = now or getTimestampMs()
    local climbing = actor:getVariableBoolean "ClimbingFence"
    local hint = record.fenceHint
    local hinted = hint
        and math.abs(actor:getZ() - hint.z) < 0.2
        and (actor:getX() - hint.x) ^ 2 + (actor:getY() - hint.y) ^ 2 <= 3 ^ 2
    if climbing then
        -- Remote replicas infer height from the same native edge, then retain
        -- it throughout the animation even after the body crosses that edge.
        if hinted then
            binding.tallFence = true
        end
        if not binding.tallFence and actor:getCurrentSquare() then
            local current, dir = actor:getCurrentSquare(), actor:getDir()
            -- Native replication can place a remote body on the landing tile
            -- before its climbing animation starts. The crossed edge is then
            -- behind it, rather than ahead as on the simulation owner.
            binding.tallFence = Fences.edge(current, dir) ~= nil
                or Fences.edge(current, opposite(dir)) ~= nil
                or remoteTallEdge(actor, current)
        end
        binding.sawTallClimb = binding.tallFence
        actor:setVariable("ProjectPeopleTallFence", binding.tallFence == true)
        if binding.tallFence then
            ownMotion(actor)
        end
        return true
    end
    if binding.tallFence then
        if not binding.sawTallClimb and now - (binding.tallFenceAt or now) < 2000 then
            return true
        end
        binding.tallFence = nil
        binding.sawTallClimb = nil
        binding.tallFenceAt = nil
        binding.epoch = -1 -- Replan from the actual landing, including a queued wait.
        binding.nextFenceCheck = now
    end
    Fences.release(actor)
    -- The authority validates this order's edge before publishing it. Arm the
    -- replica's animation before native network state/position arrives, without
    -- starting or moving a non-owned body.
    actor:setVariable("ProjectPeopleTallFence", hinted == true and record.mode == "move")
    if
        record.mode ~= "move"
        or record.attacking
        or record.transferReserved
        or record.dead
        or not actor:isLocal()
        or not actor:getCurrentSquare()
    then
        return false
    end
    if binding.nextFenceCheck and now < binding.nextFenceCheck then
        return false
    end
    binding.nextFenceCheck = now + 200
    local dx, dy = record.goalX - actor:getX(), record.goalY - actor:getY()
    if math.abs(record.goalZ - actor:getZ()) > 0.2 then
        return false
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then
        return false
    end
    local dir
    if math.abs(dx) / length > 0.7 then
        dir = dx > 0 and IsoDirections.E or IsoDirections.W
    elseif math.abs(dy) / length > 0.7 then
        dir = dy > 0 and IsoDirections.S or IsoDirections.N
    end
    local from = actor:getCurrentSquare()
    if
        dir == IsoDirections.E and record.goalX < from:getX() + 1
        or dir == IsoDirections.W and record.goalX >= from:getX()
        or dir == IsoDirections.S and record.goalY < from:getY() + 1
        or dir == IsoDirections.N and record.goalY >= from:getY()
    then
        return false
    end
    if not dir or not Fences.canCross(actor, dir) then
        return false
    end
    actor:getPathFindBehavior2():cancel()
    actor:setPath2(nil)
    actor:setVariable("bPathfind", false)
    actor:setMoving(false)
    actor:setRunning(false)
    actor:setSprinting(false)
    actor:setSneaking(false)
    actor:setVariable("ProjectPeopleTallFence", true)
    binding.tallFence = true
    binding.tallFenceAt = now
    ownMotion(actor)
    -- The normal low-vault entry rejects non-hoppable walls. Safety above is
    -- the tall-fence equivalent; the native state still owns crossing/cleanup.
    ClimbOverFenceState.instance():setParams(actor, dir)
    actor:reportEvent "EventClimbFence"
    return true
end
return Fences
