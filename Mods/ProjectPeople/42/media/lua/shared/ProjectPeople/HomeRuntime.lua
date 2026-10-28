-- Called by SurvivorRuntime only. Transient targets are rebuilt from the loaded
-- world after interruptions/recovery; original resources remain on their owner.
local Roles = require "ProjectPeople/HomeRoles"
local Resources = require "ProjectPeople/HomeResources"
local Tasks = require "ProjectPeople/HomeTasks"
local Home = {}

local function distance(actor, point)
    return (actor:getX() - point.x) ^ 2 + (actor:getY() - point.y) ^ 2
end

function Home.new()
    local self = { states = {}, claims = {}, deliveries = {}, stock = {}, lastClock = nil }
    function self:releaseDelivery(id)
        for target, delivery in pairs(self.deliveries) do
            if target == id or delivery.id == id then
                self.deliveries[target] = nil
            end
        end
    end
    function self:release(id)
        self:releaseDelivery(id)
        for key, who in pairs(self.claims) do
            if who == id then
                self.claims[key] = nil
            end
        end
        self.states[id] = nil
    end
    function self:clock(authority, records, hour)
        local stamp = getTimestampMs()
        local continuous = self.lastTick and stamp >= self.lastTick and stamp - self.lastTick <= 5000
        self.lastTick = stamp
        -- Fast-forward may cover many game minutes between coordinator ticks.
        -- Only a continuously observed native simulation can credit that span.
        if not continuous then
            self.clockInterrupted = true
        end
        if self.lastClock and hour >= self.lastClock and hour - self.lastClock < 1 / 60 then
            return authority:snapshot()
        end
        local world = authority:snapshot()
        for id in pairs(self.states) do
            if not records[id] or not Roles.resident(world.people[id]) then
                self:release(id)
            end
        end
        for key, entry in pairs(self.stock) do
            if getTimestampMs() - entry.at > 60000 then
                self.stock[key] = nil
            end
        end
        local seen = {}
        for id, p in pairs(world.people) do
            if p.homeWork or Roles.resident(p) then
                local r = records[id]
                local safe = not self.clockInterrupted
                    and r
                    and not r.dead
                    and not r.missing
                    and not r.combatActive
                    and not r.fleeing
                    and not r.attacking
                seen[id] = {
                    working = safe and r.homeWorking == true or false,
                    resting = safe and r.homeResting == true or false,
                    continuous = not self.clockInterrupted,
                }
            end
        end
        local any = false
        for _ in pairs(seen) do
            any = true
            break
        end
        if any then
            local result = authority:applySystem(
                "home.observe",
                {},
                { evidence = { kind = "home_observation", validated = true, people = seen } }
            )
            assert(result.ok, result.code)
        end
        self.lastClock = hour
        self.clockInterrupted = nil
        return authority:snapshot()
    end
    function self:begin(p, r, actor, now)
        r.homeWorking, r.homeResting, r.homePose, r.homeGuard = false, false, nil, false
        if not Roles.resident(p) or not p.homeWork or p.jobId or p.missionId or p.reservationId or p.transitionId then
            self:release(p.id)
            r.homeActive = false
            return
        end
        local signature = p.commanderId
            .. ":"
            .. p.home.x
            .. ":"
            .. p.home.y
            .. ":"
            .. p.home.z
            .. ":"
            .. p.homeWork.role
            .. ":"
            .. tostring(p.homeWork.breakKind)
            .. ":"
            .. p.homeWork.cycle
        local state = self.states[p.id]
        if not state or state.signature ~= signature then
            local active = state
                and state.homeX == p.home.x
                and state.homeY == p.home.y
                and state.homeZ == p.home.z
                and state.active
            self:release(p.id)
            state = {
                signature = signature,
                homeX = p.home.x,
                homeY = p.home.y,
                homeZ = p.home.z,
                failed = {},
                active = active,
            }
            self.states[p.id] = state
            r.homeOrderChanged = true
        end
        if not state.active then
            local sq = getCell():getGridSquare(p.home.x, p.home.y, p.home.z)
            local current = actor:getCurrentSquare()
            state.active = math.abs(actor:getZ() - p.home.z) < 0.2
                and distance(actor, p.home) <= 4
                and current
                and (not sq or not sq:getBuilding() or current:getBuilding() == sq:getBuilding())
        end
        -- Home work never becomes an unbounded expedition.
        if math.abs(actor:getZ() - p.home.z) > 0.2 or distance(actor, p.home) > 22 ^ 2 then
            state.active = false
        end
        r.homeActive = state.active == true
        r.homeGuard = r.homeActive and p.homeWork.role == "guard" and not p.homeWork.breakKind or false
        r.homeGuardX, r.homeGuardY, r.homeGuardZ = p.home.x, p.home.y, p.home.z
    end
    function self:interrupt(id, r)
        self:releaseDelivery(id)
        local s = self.states[id]
        if s then
            if s.task then
                self.claims[s.task.key] = nil
            end
            s.task, s.pickup, s.delivery, s.need, s.goal, s.workAt = nil, nil, nil, nil, nil, nil
        end
        r.homeWorking, r.homeResting, r.homePose = false, false, nil
    end
    function self:containers(p, owner, now)
        local key = p.commanderId .. ":" .. p.home.x .. ":" .. p.home.y .. ":" .. p.home.z
        local cached = self.stock[key]
        if not cached or now - cached.at > 15000 then
            cached = { at = now, entries = Resources.containers(p.home, owner) }
            self.stock[key] = cached
        end
        return cached.entries
    end
    local function travel(s, actor, goal, now)
        if not goal then
            return nil, "blocked"
        end
        if
            not s.goal
            or distance(actor, s.goal) < 0.5 ^ 2
            or s.goal.x ~= goal.x
            or s.goal.y ~= goal.y
            or s.goal.z ~= goal.z
        then
            s.goal, s.pathAt, s.progressAt = goal, now, now
            s.lastX, s.lastY = actor:getX(), actor:getY()
        end
        if (actor:getX() - s.lastX) ^ 2 + (actor:getY() - s.lastY) ^ 2 > 0.2 ^ 2 then
            s.lastX, s.lastY, s.progressAt = actor:getX(), actor:getY(), now
        end
        if now - s.pathAt > 30000 or now - s.progressAt > 7000 then
            return nil, "blocked"
        end
        return goal
    end
    function self:step(p, r, actor, owner, bodies, world, now)
        Resources.setWorld(world)
        local s = self.states[p.id]
        if not s or not s.active then
            return nil, false
        end
        local work = p.homeWork
        r.homeWorking = not work.breakKind
        local function walk(goal, label)
            r.activity, r.homePose = label, nil
            if goal then
                local key = goal.x .. ":" .. goal.y .. ":" .. goal.z
                if s.cropGoal ~= key then
                    s.cropGoal, s.cropPath = key, Resources.cropRoute(actor, goal, owner, p.home)
                end
                if s.cropPath == false then
                    goal = nil
                elseif s.cropPath and #s.cropPath > 0 then
                    while #s.cropPath > 0 and distance(actor, s.cropPath[1]) <= 0.5 ^ 2 do
                        table.remove(s.cropPath, 1)
                    end
                    goal = s.cropPath[1] or goal
                end
            end
            local result, failure = travel(s, actor, goal, now)
            if failure then
                if s.rest then
                    s.rest, s.restFloor = nil, true
                end
                self:releaseDelivery(p.id)
                if s.task then
                    s.failed[s.task.key] = now + 30000
                    self.claims[s.task.key] = nil
                end
                s.task, s.pickup, s.delivery, s.need, s.goal, s.workAt = nil, nil, nil, nil, nil, nil
                s.nextScan = now + 5000
                s.cropGoal, s.cropPath = nil, nil
                r.activity = "Home route blocked; trying another task"
            end
            return result, true
        end
        local function putAway(needs)
            if now < (s.returnAfter or 0) then
                return nil, false
            end
            local item = Resources.surplus(actor, needs)
            if not item then
                return nil, false
            end
            local storage = Resources.storage(self:containers(p, owner, now), actor, item, owner)
            if not storage then
                s.returnAfter = now + 15000
                return nil, false
            end
            if not Resources.near(actor, storage.entry.square) then
                return walk(storage.goal, "Putting unused home supplies away")
            end
            if not Resources.store(actor, item, storage.entry, owner) then
                s.returnAfter = now + 15000
            end
            r.activity = "Putting unused home supplies away"
            return nil, true
        end
        if work.breakKind or work.role == "guard" then
            local goal, returning = putAway(work.breakKind == "snack" and { { kind = "food" } } or {})
            if returning then
                return goal, true
            end
        end
        if work.breakKind then
            r.behaviourResting = true
            if work.breakKind == "relax" then
                r.homeResting = true
                r.activity = "Relax break"
                if not s.relaxAt or now >= s.relaxAt then
                    s.relaxAt = now + 12000 + ZombRand(18000)
                    s.restGoal = ZombRand(3) > 0 and Tasks.randomPoint(p.home, 6, owner, ZombRand) or nil
                end
                if s.restGoal and distance(actor, s.restGoal) > 0.5 ^ 2 then
                    return walk(s.restGoal, "Relax break: wandering home")
                end
                s.restGoal = nil
                r.homePose = "sit"
                return nil, true
            end
            if work.breakKind == "snack" then
                local md = actor:getModData()
                local token = p.commanderId .. ":" .. work.cycle
                if md.ProjectPeopleHomeSnack ~= token then
                    local food = Resources.find(actor:getInventory(), { kind = "food" })
                    if not food then
                        local source = Resources.source(self:containers(p, owner, now), { kind = "food" }, actor, owner)
                        if source then
                            if not Resources.near(actor, source.square) then
                                return walk(source.goal, "Snack break: finding food")
                            end
                            if Resources.move(source.item, actor, source.square, owner) then
                                food = source.item
                            end
                        end
                    end
                    s.food = food
                end
            end
            s.rest = s.rest or Tasks.restPlace(p.home, owner, work.breakKind == "sleep", s.restFloor)
            if distance(actor, s.rest.goal) > 0.5 ^ 2 then
                return walk(
                    s.rest.goal,
                    work.breakKind == "sleep" and "Sleep break: finding a place to sleep"
                        or "Snack break: finding a seat"
                )
            end
            r.homeResting = true
            r.homePose = work.breakKind == "sleep" and "sleep" or "sit"
            r.activity = work.breakKind == "sleep" and "Sleep break" or "Snack break"
            if s.food and Resources.inInventory(actor, s.food) and Resources.matches(s.food, { kind = "food" }) then
                r.homePose = "eat"
                s.eatAt = s.eatAt or now
                if now - s.eatAt >= 5000 then
                    if Resources.eat(actor, s.food) then
                        actor:getModData().ProjectPeopleHomeSnack = p.commanderId .. ":" .. work.cycle
                        s.food = nil
                    end
                end
            elseif
                work.breakKind == "snack"
                and actor:getModData().ProjectPeopleHomeSnack ~= p.commanderId .. ":" .. work.cycle
            then
                r.activity = "Snack break: no safe food found"
            end
            return nil, true
        end
        if work.role == "guard" then
            if not s.patrol or distance(actor, s.patrol) < 0.6 ^ 2 then
                s.patrol = Tasks.randomPoint(p.home, 10, owner, ZombRand)
                s.goal = nil
            end
            local goal, handled = walk(s.patrol, "Guarding the home")
            if not goal then
                s.patrol = nil
            end
            return goal, handled
        end
        -- Suppliers also answer a resident's outstanding material request.
        if work.role == "supply" and not s.task and not s.delivery then
            for id, other in pairs(self.states) do
                local person = world.people[id]
                if
                    id ~= p.id
                    and other.need
                    and not self.deliveries[id]
                    and person
                    and person.commanderId == p.commanderId
                    and Roles.resident(person)
                    and bodies[id]
                then
                    local item = Resources.find(actor:getInventory(), other.need)
                    local source = not item
                        and Resources.source(self:containers(p, owner, now), other.need, actor, owner)
                    if item or source then
                        s.delivery = { id = id, item = item, source = source }
                        self.deliveries[id] = { id = p.id, at = now, need = other.need }
                        break
                    end
                end
            end
        end
        if s.delivery then
            local delivery = s.delivery
            local target = bodies[delivery.id] and bodies[delivery.id].actor
            local person = world.people[delivery.id]
            local claim = self.deliveries[delivery.id]
            local recipient = self.states[delivery.id]
            if
                not target
                or not Roles.resident(person)
                or person.commanderId ~= p.commanderId
                or not claim
                or claim.id ~= p.id
                or not recipient
                or not recipient.need
                or recipient.need.kind ~= claim.need.kind
                or recipient.need.type ~= claim.need.type
                or Resources.find(target:getInventory(), claim.need)
            then
                self:releaseDelivery(p.id)
                s.delivery = nil
                return nil, true
            end
            if not delivery.item then
                local source = delivery.source
                if not Resources.near(actor, source.square) then
                    return walk(source.goal, "Collecting supplies for a resident")
                end
                if Resources.move(source.item, actor, source.square, owner) then
                    delivery.item = source.item
                else
                    self:releaseDelivery(p.id)
                    s.delivery = nil
                end
            elseif Resources.inInventory(actor, delivery.item) then
                local sq = target:getCurrentSquare()
                if not Resources.near(actor, sq) then
                    return walk(Resources.goal(sq, owner), "Bringing supplies to a resident")
                end
                Resources.move(delivery.item, actor, sq, owner, target)
                self:releaseDelivery(p.id)
                s.delivery = nil
            else
                self:releaseDelivery(p.id)
                s.delivery = nil
            end
            return nil, true
        end
        if s.task and not Tasks.valid(s.task, actor, owner) then
            self.claims[s.task.key] = nil
            s.task = nil
            s.need = nil
        end
        if not s.task and now >= (s.nextScan or 0) then
            s.nextScan = now + 5000
            local tasks = Tasks.scan(p.home, work.role, owner)
            table.sort(tasks, function(a, b)
                return distance(actor, { x = a.square:getX(), y = a.square:getY() })
                    < distance(actor, { x = b.square:getX(), y = b.square:getY() })
            end)
            for _, task in ipairs(tasks) do
                if not self.claims[task.key] and now >= (s.failed[task.key] or 0) then
                    task.goal = Resources.goal(task.square, owner)
                    if task.goal then
                        s.task = task
                        self.claims[task.key] = p.id
                        s.goal = nil
                        break
                    end
                end
            end
        end
        local returnGoal, returning = putAway(s.task and s.task.needs or {})
        if returning then
            return returnGoal, true
        end
        if not s.task then
            r.activity = Roles.labels[work.role] .. ": checking the home"
            return nil, true
        end
        local task = s.task
        local items, need = Tasks.items(task, actor)
        if not items then
            s.need = need
            s.workAt = nil
            local delivery = self.deliveries[p.id]
            if delivery then
                if now - delivery.at <= 30000 then
                    r.activity = "Waiting for a supplier to bring " .. Resources.needLabel(need)
                    return nil, true
                end
                self.deliveries[p.id] = nil
            end
            local source = Resources.source(self:containers(p, owner, now), need, actor, owner)
            if source then
                if not Resources.near(actor, source.square) then
                    return walk(source.goal, "Collecting supplies for " .. work.role)
                end
                if not Resources.move(source.item, actor, source.square, owner) then
                    self.claims[task.key] = nil
                    s.failed[task.key] = now + 30000
                    s.task, s.need, s.goal = nil, nil, nil
                    r.activity = "Cannot carry these supplies; checking another task"
                end
            else
                r.activity = Roles.labels[work.role] .. ": waiting for " .. Resources.needLabel(need)
                s.needSince = s.needSince or now
                if now - s.needSince > 8000 then
                    self.claims[task.key] = nil
                    s.failed[task.key] = now + 30000
                    s.task, s.needSince, s.goal = nil, nil, nil
                end
            end
            return nil, true
        end
        s.need = nil
        s.needSince = nil
        if not Resources.near(actor, task.square) then
            return walk(task.goal, task.label)
        end
        r.activity, r.homePose = task.label, task.pose
        r.faceX, r.faceY = task.square:getX() + 0.5, task.square:getY() + 0.5
        s.workAt = s.workAt or now
        if now - s.workAt >= 5000 then
            local ok = Tasks.perform(task, actor, owner)
            if ok and Tasks.valid(task, actor, owner) then
                -- Finish this crop/repair with the remaining original supplies
                -- before returning tools or competing for another task.
                s.workAt = nil
                r.homePose = nil
                return nil, true
            end
            self.claims[task.key] = nil
            s.failed[task.key] = now + (ok and 2000 or 30000)
            s.task, s.workAt, s.goal = nil, nil, nil
            r.homePose = nil
            r.activity = ok and task.label .. ": done" or "Supplies or target changed; checking again"
        end
        return nil, true
    end
    return self
end
return Home
