-- Finds encounter sites and connects population decisions to the survivor coordinator.
local DevTools = require "ProjectPeople/DevTools"
local Population = require "ProjectPeople/Population/Rules"
local Body = require "ProjectPeople/PeopleBody"
local Movement = require "ProjectPeople/Pathing/Movement"
local Runtime = {}
local distanceSquared = DevTools.distanceSquared

local function construction(square)
    -- In installed 42.21 getPlayerBuiltFloor returns getFloor for ordinary
    -- outdoor tiles. It is NOT construction provenance. Native building code
    -- creates IsoThumpables and records consumed materials as need:* metadata.
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof and instanceof(object, "IsoThumpable") then
            return true
        end
        if object:hasModData() then
            for key in pairs(object:getModData()) do
                if type(key) == "string" and string.sub(key, 1, 5) == "need:" then
                    return true
                end
            end
        end
    end
    return false
end

function Runtime.spatial(site, players)
    local close = false
    for _, p in ipairs(players) do
        if distanceSquared(site, p) < 24 ^ 2 then
            return false
        end -- includes players on other floors
        if distanceSquared(site, p) <= 80 ^ 2 then
            close = true
        end
    end
    return close
end

function Runtime.players(online)
    local result = {}
    for i = 0, online:size() - 1 do
        local p = online:get(i)
        if p and not p:isDead() then
            result[#result + 1] = { x = p:getX(), y = p:getY(), z = p:getZ(), actor = p }
        end
    end
    return result
end

local function safe(site, players)
    if not Runtime.spatial(site, players) or site.z ~= 0 then
        return false, "player_distance"
    end
    if not SafeHouse or not LosUtil then
        return false, "spatial_api_unavailable"
    end
    local cell = getCell()
    local sq = cell:getGridSquare(math.floor(site.x), math.floor(site.y), 0)
    if not sq then
        return false, "unloaded"
    end
    if
        not sq:TreatAsSolidFloor()
        or not sq:isFree(false)
        or sq:getBuilding()
        or sq:isVehicleIntersecting()
        or sq:getSpecialObjects():size() > 0
    then
        return false, "occupied_site"
    end
    -- Outside buildings only until occupation/renovation claims are implemented.
    -- A loaded buffer excludes claims and nearby player-built floors/objects.
    for dx = -3, 3 do
        for dy = -3, 3 do
            local check = cell:getGridSquare(math.floor(site.x) + dx, math.floor(site.y) + dy, 0)
            if not check then
                return false, "unloaded_buffer"
            end
            if construction(check) then
                return false, "player_build"
            end
            if SafeHouse.isSafeHouse(check, nil, false) then
                return false, "claimed_area"
            end
        end
    end
    for _, p in ipairs(players) do
        if distanceSquared(site, p) <= 100 ^ 2 then
            if not (isServer and isServer()) and p.actor then
                -- Local visibility includes facing and the actual visibility map;
                -- a clear geometric ray alone does not mean a tile is being seen.
                if sq:isCanSee(p.actor:getPlayerNum()) then
                    return false, "visible_site"
                end
            else
                local sight = LosUtil.lineClear(
                    cell,
                    math.floor(p.x),
                    math.floor(p.y),
                    math.floor(p.z),
                    math.floor(site.x),
                    math.floor(site.y),
                    0,
                    false
                )
                if tostring(sight) ~= "Blocked" then
                    return false, "line_of_sight"
                end
            end
        end
    end
    local zombies = cell:getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if
            not z:isDead()
            and (z:getX() - site.x) ^ 2 + (z:getY() - site.y) ^ 2 < 6 ^ 2
            and (not site.groupId or z:getModData().ProjectPeoplePopulationGroup ~= site.groupId)
        then
            return false, "nearby_zombie"
        end
    end
    return true
end
Runtime.validateSite = safe

function Runtime.new(adapters)
    adapters = adapters or {}
    local validateNative = adapters.safe or safe
    local body = adapters.body or Body
    local movement = Movement.new(adapters.movement)
    local self = { nextBoundary = 0, nextStory = 0, playerCursor = 0, candidateCursor = 0, diagnostics = {} }
    local function validate(site, players)
        local ok, reason = validateNative(site, players)
        if not ok then
            reason = reason or "site_rejected"
            self.diagnostics.rejected = self.diagnostics.rejected or {}
            self.diagnostics.rejected[reason] = (self.diagnostics.rejected[reason] or 0) + 1
        end
        return ok
    end
    function self:intent(p, r, records)
        if
            not self.world
            or not p.populationGroup
            or p.recruited
            or p.duty
            or p.jobId
            or p.missionId
            or p.reservationId
            or p.transitionId
            or p.life ~= "alive"
            or r.behaviourResting
            or r.behaviourVisiting
        then
            return nil
        end
        local g = self.world.population and self.world.population.groups[p.populationGroup]
        if not g then
            return nil
        end
        local leader = records[g.members[1]]
        for _, id in ipairs(g.members) do
            local person = self.world.people[id]
            if person and person.life ~= "dead" and not records[id] then
                r.activity = "Waiting for the group"
                return nil
            end
        end
        if leader and leader.personId ~= p.id and not leader.dead and not leader.missing and leader.z == r.z then
            if
                (leader.x - r.x) ^ 2 + (leader.y - r.y) ^ 2 > 25
                and (leader.x - r.x) ^ 2 + (leader.y - r.y) ^ 2 <= 24 ^ 2
            then
                return { x = leader.x + 1, y = leader.y + 1, z = leader.z, activity = "Staying with the group" }
            end
            return nil
        end
        local angle = (g.seed % 8) * math.pi / 4
        local travelling = g.stage == "escaping" or g.stage == "relocating" or g.stage == "seeking_refuge"
        local radius = travelling and 12 or 4
        return {
            x = g.home.x + math.cos(angle) * radius,
            y = g.home.y + math.sin(angle) * radius,
            z = g.home.z,
            activity = travelling and "Looking for a safer route" or "Checking the refuge surroundings",
        }
    end
    function self:group(p)
        return self.world and self.world.population and self.world.population.groups[p.populationGroup]
    end
    function self:flee(p, r, actor, zombies, wall, options)
        local policy = Population.options(options)
        if not policy.enabled or not policy.stories or options and options.IdleAutonomy == false then
            return nil
        end
        return movement:flee(p, r, actor, self:group(p), zombies, wall)
    end
    function self:goal(p, r, records, online, options, actor, wall)
        local policy = Population.options(options)
        if not policy.enabled or not policy.stories or options and options.IdleAutonomy == false then
            movement:clear(p.id)
            return nil
        end
        local players = Runtime.players(online)
        local attended = false
        for _, h in ipairs(players) do
            local distance = distanceSquared({ x = r.x, y = r.y }, h)
            if distance < 80 ^ 2 then
                attended = true
            end
        end
        if not attended then
            return nil
        end
        if not actor then
            return nil
        end
        return movement:goal(p, r, actor, self:group(p), records, self.world, wall)
    end
    function self:advance(service, time, sites, options, elapsedDays)
        local result = service.authority:applySystem("population.observe", {}, {
            evidence = {
                kind = "population_observation",
                validated = true,
                sites = sites or {},
                options = options,
                elapsedDays = elapsedDays,
            },
        })
        if result.ok then
            self.world = service.authority:snapshot()
        else
            self.diagnostics.blocked = result.code
        end
        return result
    end
    function self:step(service, time, options, elapsedDays)
        if time < self.nextStory then
            return
        end
        self.nextStory = time + 1
        local result = self:advance(service, time, {}, options, elapsedDays)
        if not result.ok then
            return result
        end
        local pop = self.world.population
        self.diagnostics.storyBacklog = pop.backlog
        return result
    end
    function self:boundary(service, bodies, records, online, worldId, time, wall, options, elapsedDays)
        if wall < self.nextBoundary then
            return
        end
        self.nextBoundary = wall + 10000
        self.diagnostics.rejected = {}
        local policy = Population.options(options)
        if not policy.enabled then
            return
        end
        local players = Runtime.players(online)
        if #players == 0 then
            return
        end
        local sites, seen = {}, {}
        -- One bounded candidate search per player, shared regions deduplicated.
        -- Rotate candidates between attempts so an obstructed arc cannot starve discovery.
        local offset = math.floor(wall / 10000) % 24
        for pi = 1, math.min(8, #players) do
            local p = players[((pi - 1 + self.playerCursor) % #players) + 1]
            for n = 1, 24 do
                local angle = (n + offset) * math.pi / 12
                local radius = 28 + ((n + math.floor(offset / 3)) % 3) * 8
                local site = {
                    x = math.floor(p.x + math.cos(angle) * radius) + 0.5,
                    y = math.floor(p.y + math.sin(angle) * radius) + 0.5,
                    z = 0,
                    validated = true,
                }
                local rid = Population.region(site.x, site.y)
                if not seen[rid] and validate(site, players) then
                    sites[#sites + 1] = site
                    seen[rid] = true
                    break
                end
            end
        end
        self.playerCursor = (self.playerCursor + math.min(8, #players)) % #players
        self.diagnostics.acceptedSites = #sites
        local result = self:advance(service, time, sites, options, elapsedDays)
        if not result.ok then
            return result
        end
        local world = self.world
        local loaded = 0
        local unknown = 0
        local waiting = 0
        for _, b in pairs(bodies) do
            if b and not b.actor:isDead() then
                loaded = loaded + 1
            end
        end
        local candidates = {}
        for id, p in pairs(world.people) do
            if
                p.populationGroup
                and not p.populationAbsent
                and p.life == "alive"
                and not p.nativeBirth
                and not p.reservationId
                and not p.transitionId
                and not world.population.groups[p.populationGroup].route
            then
                local relevant = false
                for _, h in ipairs(players) do
                    if distanceSquared(p.location, h) <= 80 ^ 2 then
                        relevant = true
                        break
                    end
                end
                if relevant then
                    candidates[#candidates + 1] = id
                end
            end
        end
        table.sort(candidates)
        local born = 0
        local checked = math.min(12, #candidates)
        for i = 1, checked do
            local id = candidates[((i - 1 + self.candidateCursor) % #candidates) + 1]
            local p = world.people[id]
            if p.populationBirth then
                -- A crash may leave an actual tagged actor but no birth ack.
                -- Reconcile it; absence never authorizes another factory call.
                local b, r = body.recover(p, worldId)
                if b then
                    if not bodies[id] then
                        loaded = loaded + 1
                    end
                    bodies[id], records[id] = b, r
                    local ack = service:bindInitial(id)
                    if not ack.ok then
                        self.diagnostics.blocked = ack.code
                        return ack
                    end
                else
                    unknown = unknown + 1
                end
            elseif loaded < policy.physicalLimit and born < 3 then
                local g = world.population.groups[p.populationGroup]
                local index = 1
                for i, member in ipairs(g.members) do
                    if member == id then
                        index = i
                    end
                end
                local site = {
                    x = p.location.x + (index - 1) * 2,
                    y = p.location.y,
                    z = p.location.z,
                    groupId = p.populationGroup,
                }
                -- No moving a known person to a new candidate around a player.
                if validate(site, players) then
                    local ack = service.authority:applySystem(
                        "population.birth",
                        { personId = id },
                        { evidence = { kind = "population_birth", validated = true, personId = id, safe = true } }
                    )
                    if not ack.ok then
                        self.diagnostics.blocked = ack.code
                        return ack
                    end
                    local ok, b, r = pcall(body.create, p, site)
                    if not ok then
                        self.diagnostics.blocked = "native_birth_outcome_unknown"
                        unknown = unknown + 1
                        break
                    end
                    bodies[id], records[id] = b, r
                    r.worldId = worldId
                    b.actor:getModData().ProjectPeopleWorldId = worldId
                    b.actor:getModData().ProjectPeoplePopulationGroup = p.populationGroup
                    ack = service:bindInitial(id)
                    if not ack.ok then
                        self.diagnostics.blocked = ack.code
                        return ack
                    end
                    loaded = loaded + 1
                    born = born + 1
                else
                    waiting = waiting + 1
                end
            else
                waiting = waiting + 1
            end
        end
        if #candidates > 0 then
            self.candidateCursor = (self.candidateCursor + checked) % #candidates
        end
        self.world = service.authority:snapshot()
        self.diagnostics.unknownBirths = unknown
        self.diagnostics.waitingForSafeSite = waiting
        self.diagnostics.loadedBodies = loaded
        self.diagnostics.physicalLimit = policy.physicalLimit
        self.diagnostics.admissionBacklog = math.max(0, #candidates - checked)
        self.diagnostics.admissionBlocked = self.world.population.admissionBlocked
        return result
    end
    return self
end
return Runtime
