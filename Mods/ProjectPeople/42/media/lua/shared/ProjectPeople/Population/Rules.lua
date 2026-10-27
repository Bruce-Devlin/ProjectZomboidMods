-- Persistent regional families, encounters and population rules. No native bodies or loot.
local Stories = require "ProjectPeople/Content/Stories"
local Names = require "ProjectPeople/Content/Names"
local DevTools = require "ProjectPeople/DevTools"
local Population = { VERSION = 1, REGION_SIZE = 300, EVENT_BUDGET = 8, RECORD_LIMIT = 1200 }
local isFinite = DevTools.isFinite

local function bounded(n, default, lo, hi)
    if not isFinite(n) then
        return default
    end
    return math.max(lo, math.min(hi, n))
end

local function fail(code)
    return { ok = false, code = code }
end

local function good(code)
    return { ok = true, code = code }
end
local count = DevTools.count

function Population.options(s)
    s = s or {}
    return {
        enabled = s.PopulationEnabled ~= false,
        density = bounded(s.PopulationDensity, 1, 0, 4),
        mode = math.floor(bounded(s.PopulationMode, 2, 1, 3)),
        migrationDays = bounded(s.MigrationDays, 30, 1, 365),
        physicalLimit = math.floor(bounded(s.PhysicalPopulationLimit, 20, 1, 40)),
        startDays = bounded(s.OutbreakAgeDays, 0, 0, 3650),
        stories = s.PopulationStories ~= false,
    }
end

function Population.hash(value)
    local h = 5381
    for i = 1, #value do
        h = (h * 33 + string.byte(value, i)) % 2147483647
    end
    for _ = 1, 3 do
        h = (h * 48271) % 2147483647
    end
    return h
end

local function roll(seed, key)
    return Population.hash(tostring(seed) .. ":" .. key) / 2147483647
end

function Population.region(x, y)
    return math.floor(x / Population.REGION_SIZE) .. ":" .. math.floor(y / Population.REGION_SIZE)
end

function Population.age(population, now)
    return population.startDays + math.max(0, now - population.startedAt) / 24
end

function Population.era(days)
    if days < 14 then
        return "outbreak"
    elseif days < 180 then
        return "aftermath"
    else
        return "long_term"
    end
end
local stages = { escaping = true, seeking_refuge = true, settling = true, established = true, relocating = true }
local plans = Stories.plans

function Population.plan(world, person)
    local group = person.populationGroup and world.population and world.population.groups[person.populationGroup]
    return group and plans[group.stage] or nil
end

local function entry(group, at, kind)
    group.events = group.events + 1
    group.history[#group.history + 1] = { sequence = group.events, at = at, kind = kind }
    if #group.history > 16 then
        table.remove(group.history, 1)
    end
end
local names = Names.firstNames
local surnames = Names.surnames

local function addGroup(world, population, region, site, now, origin, makePerson)
    if count(world.people) + 3 > Population.RECORD_LIMIT then
        population.admissionBlocked = "record_budget"
        return false
    end
    region.serial = region.serial + 1
    local id = "population:" .. region.id .. ":" .. region.serial
    assert(not population.groups[id], "population_identity_conflict")
    local seed = Population.hash(tostring(population.seed) .. ":" .. id)
    local era = Population.era(Population.age(population, now))
    local family = roll(seed, "family") < (era == "outbreak" and 0.7 or 0.35)
    local size = family and 2 + (roll(seed, "third") < 0.4 and 1 or 0) or 1
    local encounterRoll = roll(seed, "encounter-size")
    local present = math.min(size, encounterRoll < 0.65 and 1 or encounterRoll < 0.95 and 2 or 3)
    local stage = era == "outbreak" and "escaping" or era == "aftermath" and "seeking_refuge" or "established"
    local home = { x = site.x, y = site.y, z = site.z }
    local group = {
        id = id,
        region = region.id,
        members = {},
        absentMembers = {},
        seed = seed,
        origin = origin,
        era = era,
        stage = stage,
        createdAt = now,
        nextEvent = now + 12,
        events = 0,
        history = {},
        home = home,
        pressure = 0,
    }
    local surname = surnames[math.floor(roll(seed, "surname") * #surnames) + 1]
    for i = 1, size do
        local pid = id .. ":" .. i
        assert(not world.people[pid], "population_identity_conflict")
        local name = names[(math.floor(roll(seed, "name") * #names) + i - 1) % #names + 1] .. " " .. surname
        local background = Stories.background(era, family)
        local person = makePerson({
            id = pid,
            name = name,
            background = background,
            location = home,
            attachment = family and 75 or 25,
            preferences = { travelTrust = family and 20 or 5 },
            personality = {
                caution = 30 + math.floor(roll(seed, "caution" .. i) * 55),
                compassion = 35 + math.floor(roll(seed, "care" .. i) * 55),
                independence = 30 + math.floor(roll(seed, "independence" .. i) * 60),
                sociability = 25 + math.floor(roll(seed, "social" .. i) * 60),
                conscientiousness = era == "long_term" and 80 or 55,
                aggression = 10,
            },
        })
        person.populationGroup = id
        person.communityId = id
        person.home = { x = home.x, y = home.y, z = home.z }
        if i > present then
            person.populationAbsent = true
            person.available = false
            person.location = {}
            person.background = Stories.absentRelative
        elseif family and present < size then
            person.background = Stories.separatedFamily
        end
        world.people[pid] = person
        world.inventories["person:" .. pid] = { kind = "person", personId = pid }
        local cohort = i <= present and group.members or group.absentMembers
        cohort[#cohort + 1] = pid
    end
    local members = {}
    local relatives = {}
    for i = 1, size do
        relatives[i] = id .. ":" .. i
    end
    for _, pid in ipairs(relatives) do
        members[pid] = true
        if family then
            for _, relative in ipairs(relatives) do
                if pid ~= relative then
                    world.people[pid].family[relative] = "adult_relative"
                end
            end
        end
    end
    world.communities[id] = {
        id = id,
        name = family and surname .. " family" or surname .. " refuge",
        home = home,
        members = members,
        commanders = { [group.members[1]] = true },
        revision = 0,
    }
    entry(group, now, origin == "migration" and "arrived_in_region" or stage)
    population.groups[id] = group
    region.groups[#region.groups + 1] = id
    population.admissionBlocked = nil
    return true
end

local function frozen(world, group)
    for _, id in ipairs(group.members) do
        local person = world.people[id]
        if
            person.reservationId
            or person.transitionId
            or person.jobId
            or person.missionId
            or person.populationBirth and not person.nativeBirth
        then
            return true
        end
    end
    return false
end

local function abstractTravelAllowed(world, group)
    for _, id in ipairs(group.members) do
        local person = world.people[id]
        if
            person.life ~= "alive"
            or person.nativeBirth
            or person.populationBirth
            or person.recruited
            or person.representation.owner ~= "record"
            or person.representation.mode ~= "abstract"
        then
            return false
        end
    end
    return not frozen(world, group)
end

local function progress(world, population, group, at)
    -- These are decisions, not fabricated successful scavenges or construction.
    local alive = false
    for _, id in ipairs(group.members) do
        if world.people[id].life ~= "dead" then
            alive = true
        end
    end
    if not alive then
        group.historical = true
        return
    end
    if frozen(world, group) then
        entry(group, at, "commitment_continues")
        return
    end
    if group.route then
        if not abstractTravelAllowed(world, group) then
            entry(group, at, "travel_reconciliation_required")
            return
        end
        if at < group.route.arriveAt then
            return
        end
        local dest = group.route.destination
        group.home = { x = dest.x, y = dest.y, z = dest.z }
        group.currentRegion = group.route.region
        for _, id in ipairs(group.members) do
            local person = world.people[id]
            person.location = { x = dest.x, y = dest.y, z = dest.z }
            person.home = { x = dest.x, y = dest.y, z = dest.z }
            person.revision = person.revision + 1
        end
        world.communities[group.id].home = { x = dest.x, y = dest.y, z = dest.z }
        group.route = nil
        group.stage = "seeking_refuge"
        entry(group, at, "arrived_at_refuge_area")
        return
    end
    if (group.stage == "escaping" or group.stage == "relocating") and abstractTravelAllowed(world, group) then
        local regions = {}
        for id, region in pairs(population.regions) do
            if region.anchor and id ~= (group.currentRegion or group.region) then
                regions[#regions + 1] = id
            end
        end
        table.sort(regions)
        if #regions > 0 then
            local id = regions[math.floor(roll(group.seed, "route:" .. group.events) * #regions) + 1]
            local dest = population.regions[id].anchor
            local distance = math.sqrt((dest.x - group.home.x) ^ 2 + (dest.y - group.home.y) ^ 2)
            group.route = {
                region = id,
                destination = { x = dest.x, y = dest.y, z = dest.z },
                departedAt = at,
                arriveAt = at + math.max(1, distance / 48),
            }
            entry(group, at, "travel_departed")
            return
        end
    end
    local previous = group.stage
    if group.stage == "escaping" then
        group.stage = "seeking_refuge"
    elseif group.stage == "seeking_refuge" then
        group.stage = "settling"
    elseif group.stage == "settling" then
        group.stage = "established"
    elseif group.stage == "relocating" then
        group.stage = "seeking_refuge"
    elseif group.pressure >= 4 or roll(group.seed, "event:" .. group.events) < 0.15 then
        group.stage = "relocating"
    end
    entry(group, at, group.stage == previous and "routine_continues" or group.stage)
    for _, id in ipairs(group.members) do
        local person = world.people[id]
        if person.life ~= "dead" then
            person.revision = person.revision + 1
        end
    end
end
-- Optional schema: existing worlds retain every record when population is added.

function Population.valid(world)
    local population = world.population
    if population == nil then
        return true
    end
    if
        type(population) ~= "table"
        or population.version ~= Population.VERSION
        or not isFinite(population.seed)
        or not isFinite(population.startedAt)
        or not isFinite(population.startDays)
        or population.startDays < 0
        or not isFinite(population.lastAt)
        or population.lastAt < population.startedAt
        or type(population.regions) ~= "table"
        or type(population.groups) ~= "table"
    then
        return false
    end
    for id, region in pairs(population.regions) do
        if
            type(region) ~= "table"
            or region.id ~= id
            or not isFinite(region.serial)
            or region.serial < 0
            or region.serial % 1 ~= 0
            or not isFinite(region.remaining)
            or region.remaining < 0
            or region.remaining % 1 ~= 0
            or not isFinite(region.nextMigration)
            or type(region.groups) ~= "table"
            or region.serial ~= #region.groups
            or type(region.anchor) ~= "table"
            or not isFinite(region.anchor.x)
            or not isFinite(region.anchor.y)
            or region.anchor.z ~= 0
        then
            return false
        end
        for _, gid in ipairs(region.groups) do
            if not population.groups[gid] or population.groups[gid].region ~= id then
                return false
            end
        end
    end
    for id, group in pairs(population.groups) do
        if
            type(group) ~= "table"
            or group.id ~= id
            or not population.regions[group.region]
            or not stages[group.stage]
            or not isFinite(group.nextEvent)
            or not isFinite(group.events)
            or group.events < 1
            or group.events % 1 ~= 0
            or not isFinite(group.seed)
            or type(group.home) ~= "table"
            or not isFinite(group.home.x)
            or not isFinite(group.home.y)
            or group.home.z ~= 0
            or type(group.history) ~= "table"
            or #group.history > 16
            or type(group.members) ~= "table"
            or #group.members < 1
            or #group.members > 3
        then
            return false
        end
        local seen = {}
        for _, pid in ipairs(group.members) do
            if
                seen[pid]
                or type(world.people[pid]) ~= "table"
                or world.people[pid].populationGroup ~= id
                or world.people[pid].populationAbsent
            then
                return false
            end
            seen[pid] = true
        end
        if group.absentMembers ~= nil and type(group.absentMembers) ~= "table" then
            return false
        end
        if #group.members + #(group.absentMembers or {}) > 3 then
            return false
        end
        for _, pid in ipairs(group.absentMembers or {}) do
            local person = world.people[pid]
            if
                seen[pid]
                or not person
                or person.populationGroup ~= id
                or person.populationAbsent ~= true
                or person.available ~= false
                or person.nativeBirth
                or person.populationBirth
                or person.representation.mode ~= "abstract"
                or person.representation.owner ~= "record"
            then
                return false
            end
            seen[pid] = true
        end
        if
            group.route
            and (
                type(group.route) ~= "table"
                or not population.regions[group.route.region]
                or not isFinite(group.route.departedAt)
                or not isFinite(group.route.arriveAt)
                or group.route.arriveAt <= group.route.departedAt
                or type(group.route.destination) ~= "table"
                or not isFinite(group.route.destination.x)
                or not isFinite(group.route.destination.y)
                or group.route.destination.z ~= 0
            )
        then
            return false
        end
    end
    for _, person in pairs(world.people) do
        if type(person) ~= "table" then
            return false
        end
        if person.populationGroup and not population.groups[person.populationGroup] then
            return false
        end
        if
            person.populationBirth
            and (
                type(person.populationBirth) ~= "table"
                or person.populationBirth.state ~= "dispatched"
                or not isFinite(person.populationBirth.at)
            )
        then
            return false
        end
    end
    return true
end

function Population.install(handlers, makePerson)
    handlers["person.discover"] = function(world, command, context)
        local person = world.people[command.personId]
        local e = context.evidence
        if
            not context.system
            or not person
            or person.controller.kind ~= "player"
            or not e
            or not e.validated
            or e.kind ~= "person_discovery"
            or e.personId ~= person.id
            or type(e.nearby) ~= "table"
            or #e.nearby > 40
        then
            return fail "person_discovery_unconfirmed"
        end
        for _, id in ipairs(e.nearby) do
            local other = world.people[id]
            if other and other.controller.kind == "ai" and not person.knowledge[id] then
                person.knowledge[id] = { metAt = context.gameTime }
            end
        end
        person.revision = person.revision + 1
        return good "people_remembered"
    end
    handlers["population.observe"] = function(world, command, context)
        local e = context.evidence
        if not context.system or not e or e.kind ~= "population_observation" or e.validated ~= true then
            return fail "population_observation_required"
        end
        local options = Population.options(e.options)
        local now = context.gameTime
        if not world.population then
            world.population = {
                version = Population.VERSION,
                seed = Population.hash(world.worldId),
                startedAt = now,
                startDays = options.startDays + (isFinite(e.elapsedDays) and math.max(0, e.elapsedDays) or 0),
                lastAt = now,
                regions = {},
                groups = {},
                backlog = 0,
            }
        end
        local population = world.population
        if now < population.lastAt then
            return fail "population_clock_reversed"
        end
        population.lastAt = now
        if not options.enabled then
            return good "population_paused"
        end
        local sites = e.sites or {}
        if type(sites) ~= "table" or #sites > 8 then
            return fail "bounded_population_sites_required"
        end
        for _, site in ipairs(sites) do
            if site.validated ~= true or not isFinite(site.x) or not isFinite(site.y) or site.z ~= 0 then
                return fail "population_site_unconfirmed"
            end
            local rid = Population.region(site.x, site.y)
            local region = population.regions[rid]
            if not region then
                local potential = 4
                    * options.density
                    * (options.mode == 3 and 1 or math.max(0.15, 0.5 ^ (Population.age(population, now) / 180)))
                local target = math.floor(potential)
                    + (roll(population.seed, "region:" .. rid) < potential % 1 and 1 or 0)
                region = {
                    id = rid,
                    serial = 0,
                    remaining = target,
                    groups = {},
                    anchor = { x = site.x, y = site.y, z = site.z },
                    discoveredAt = now,
                    nextMigration = now + options.migrationDays * 24,
                }
                population.regions[rid] = region
            end
            if region.remaining > 0 and options.density > 0 then
                if addGroup(world, population, region, site, now, "initial", makePerson) then
                    region.remaining = region.remaining - 1
                end
            elseif now >= region.nextMigration then
                -- Missed intervals are opportunities, never a catch-up spawn debt.
                region.nextMigration = now + options.migrationDays * 24
                local capacity = math.ceil(4 * options.density * (options.mode == 3 and 4 or 2))
                if options.mode ~= 1 and options.density > 0 and #region.groups < capacity then
                    addGroup(world, population, region, site, now, "migration", makePerson)
                end
            end
        end
        local due = {}
        if options.stories then
            for id, group in pairs(population.groups) do
                if not group.historical and group.nextEvent <= now then
                    due[#due + 1] = id
                end
            end
            table.sort(due, function(a, b)
                local x, y = population.groups[a], population.groups[b]
                return x.nextEvent < y.nextEvent or x.nextEvent == y.nextEvent and a < b
            end)
            for i = 1, math.min(Population.EVENT_BUDGET, #due) do
                local group = population.groups[due[i]]
                progress(world, population, group, group.nextEvent)
                -- Resolve one meaningful decision; compress uneventful missed days.
                group.nextEvent = group.route and math.max(group.route.arriveAt, group.nextEvent + 1) or now + 12
            end
        end
        population.backlog = 0
        if options.stories then
            for _, group in pairs(population.groups) do
                if not group.historical and group.nextEvent <= now then
                    population.backlog = population.backlog + 1
                end
            end
        end
        return good "population_advanced"
    end
    handlers["population.birth"] = function(world, command, context)
        local person = world.people[command.personId]
        local e = context.evidence
        if
            not context.system
            or not person
            or not person.populationGroup
            or person.nativeBirth
            or person.populationBirth
            or person.populationAbsent
            or person.life ~= "alive"
            or person.representation.mode ~= "abstract"
            or person.representation.owner ~= "record"
            or person.reservationId
            or person.transitionId
            or person.jobId
            or person.missionId
        then
            return fail "new_population_person_required"
        end
        if world.population.groups[person.populationGroup].route then
            return fail "population_travelling"
        end
        if
            not e
            or e.kind ~= "population_birth"
            or e.validated ~= true
            or e.personId ~= person.id
            or e.safe ~= true
        then
            return fail "population_birth_unconfirmed"
        end
        person.populationBirth = { state = "dispatched", at = context.gameTime }
        person.revision = person.revision + 1
        return good "population_birth_dispatched"
    end
end
return Population
