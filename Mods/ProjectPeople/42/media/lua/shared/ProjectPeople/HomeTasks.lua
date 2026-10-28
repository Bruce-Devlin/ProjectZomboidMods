-- Loaded-world chore discovery and idempotent native effects. No player timed actions
-- are run on zombie-backed people (many of those cast their character to IsoPlayer).
local Resources = require "ProjectPeople/HomeResources"
local Tasks = {}

local function plantAt(square)
    return SFarmingSystem and SFarmingSystem.instance and SFarmingSystem.instance:getLuaObjectOnSquare(square)
end

function Tasks.key(kind, square, object)
    return kind
        .. ":"
        .. square:getX()
        .. ":"
        .. square:getY()
        .. ":"
        .. square:getZ()
        .. ":"
        .. tostring(object and object:getObjectIndex() or 0)
end

function Tasks.dirty(square)
    return square:haveBloodFloor() or square:haveBloodWall() or square:haveGrimeFloor() or square:haveGrimeWall()
end

local function add(result, kind, square, object, needs, label, pose)
    result[#result + 1] = {
        kind = kind,
        square = square,
        object = object,
        key = Tasks.key(kind, square, object),
        needs = needs or {},
        label = label,
        pose = pose or "work",
    }
end

function Tasks.scan(home, role, owner)
    local result = {}
    for dx = -8, 8 do
        for dy = -8, 8 do
            if dx * dx + dy * dy <= 64 then
                local sq = getCell():getGridSquare(math.floor(home.x) + dx, math.floor(home.y) + dy, home.z)
                if Resources.allowed(sq, owner) then
                    if role == "clean" and Tasks.dirty(sq) then
                        add(
                            result,
                            "clean",
                            sq,
                            nil,
                            { { kind = "cleaner" }, { kind = "cleaning_tool" } },
                            "Cleaning the home",
                            "clean"
                        )
                    end
                    local plant = (role == "supply" or role == "maintain") and plantAt(sq)
                    if plant then
                        if role == "supply" and plant.state == "plow" then
                            add(result, "seed", sq, nil, { { kind = "seed" } }, "Planting seeds")
                        elseif role == "maintain" and plant.state ~= "plow" and plant:isAlive() then
                            local waterTarget = math.min(80, (plant.waterNeededMax or 100) - 5)
                            if (plant.waterLvl or 0) < waterTarget then
                                add(result, "water", sq, nil, { { kind = "water" } }, "Watering crops")
                            elseif (plant.fertilizer or 0) == 0 and not plant.compost then
                                add(result, "fertilize", sq, nil, { { kind = "fertilizer" } }, "Fertilising crops")
                            end
                        end
                    end
                    if role == "supply" or role == "maintain" then
                        local objects = sq:getObjects()
                        for i = 0, objects:size() - 1 do
                            local object = objects:get(i)
                            if
                                role == "supply"
                                and instanceof(object, "IsoGenerator")
                                and not object:isActivated()
                                and object:getFuelPercentage() < 90
                            then
                                add(result, "fuel", sq, object, { { kind = "fuel" } }, "Filling a generator")
                            elseif
                                role == "maintain"
                                and instanceof(object, "IsoThumpable")
                                and object:getHealth() > 0
                                and object:getHealth() < object:getMaxHealth()
                            then
                                local md = object:getModData()
                                local metal = md["use:Base.BlowTorch"] ~= nil
                                    or tostring(object:getThumpSound()):find("Metal", 1, true) ~= nil
                                add(
                                    result,
                                    "repair",
                                    sq,
                                    object,
                                    metal and { { type = "Base.SheetMetal" }, { kind = "hammer" } }
                                        or { { type = "Base.Plank" }, { type = "Base.Nails" }, { kind = "hammer" } },
                                    "Repairing a buildable"
                                )
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

function Tasks.valid(task, actor, owner)
    local sq, object = task.square, task.object
    if not Resources.allowed(sq, owner) or object and (object:getObjectIndex() < 0 or object:getSquare() ~= sq) then
        return false
    end
    if task.kind == "clean" then
        return Tasks.dirty(sq)
    end
    if task.kind == "fuel" then
        return not object:isActivated() and object:getFuelPercentage() < 100
    end
    if task.kind == "repair" then
        return object:getHealth() > 0 and object:getHealth() < object:getMaxHealth()
    end
    local p = plantAt(sq)
    if not p then
        return false
    end
    if task.kind == "seed" then
        return p.state == "plow"
    end
    if p.state == "plow" or not p:isAlive() then
        return false
    end
    if task.kind == "water" then
        return p.waterLvl < math.min(80, (p.waterNeededMax or 100) - 5)
    end
    if task.kind == "fertilize" then
        return (p.fertilizer or 0) == 0 and not p.compost
    end
    return false
end

function Tasks.items(task, actor)
    local found = {}
    for _, need in ipairs(task.needs) do
        local item = Resources.find(actor:getInventory(), need)
        if not item then
            return nil, need
        end
        found[#found + 1] = item
    end
    return found
end

function Tasks.perform(task, actor, owner)
    assert(not isClient(), "home_work_authority_only")
    if not Resources.near(actor, task.square) or not Tasks.valid(task, actor, owner) then
        return false
    end
    local items = Tasks.items(task, actor)
    if not items then
        return false
    end
    if task.kind == "clean" then
        if not Resources.consumeFluid(items[1], ZomboidGlobals.CleanBloodBleachAmount) then
            return false
        end
        task.square:removeBlood(false, false)
        task.square:removeGrime()
    elseif task.kind == "fuel" then
        local generator = task.object
        local amount = math.min(items[1]:getFluidContainer():getAmount(), generator:getMaxFuel() - generator:getFuel())
        if amount <= 0 or not Resources.consumeFluid(items[1], amount) then
            return false
        end
        generator:setFuel(generator:getFuel() + amount)
        generator:sync()
    elseif task.kind == "repair" then
        local object = task.object
        -- One matching material repairs one quarter of the original maximum;
        -- intact objects and destroyed objects are never replaced.
        for i = 1, #items - 1 do
            if not Resources.remove(actor, items[i]) then
                return false
            end
        end
        object:setHealth(
            math.min(object:getMaxHealth(), object:getHealth() + math.max(1, math.floor(object:getMaxHealth() / 4)))
        )
        object:sync()
    else
        local plant = plantAt(task.square)
        if task.kind == "seed" then
            local matches, seed = Resources.matches(items[1], { kind = "seed" })
            if not matches or not Resources.remove(actor, items[1]) then
                return false
            end
            plant:seed(seed, actor:getPerkLevel(Perks.Farming))
        elseif task.kind == "water" then
            if not Resources.consumeFluid(items[1], ZomboidGlobals.farmingFluidContainerMillilitresPerUse / 1000) then
                return false
            end
            plant:water(nil, 1)
        elseif task.kind == "fertilize" then
            local compost = items[1]:hasTag(ItemTag.COMPOST)
            if isServer() and items[1]:getCurrentUses() == 1 then
                -- Vanilla drainable depletion emits an unconditional replacement
                -- packet, whose ContainerID cannot address living zombie bags.
                -- Keep the now-empty original rather than risk losing it.
                items[1]:setCurrentUses(0)
            else
                items[1]:Use(false, false, false)
            end
            plant:fertilize({ compost = compost, skill = actor:getPerkLevel(Perks.Farming) })
        end
    end
    return true
end

function Tasks.randomPoint(home, radius, owner, random)
    for _ = 1, 20 do
        local dx, dy = random(radius * 2 + 1) - radius, random(radius * 2 + 1) - radius
        if dx * dx + dy * dy <= radius * radius then
            local sq = getCell():getGridSquare(math.floor(home.x) + dx, math.floor(home.y) + dy, home.z)
            if Resources.allowed(sq, owner) and not Resources.crop(sq) and sq:isFree(false) then
                return { x = sq:getX() + 0.5, y = sq:getY() + 0.5, z = sq:getZ() }
            end
        end
    end
end

function Tasks.restPlace(home, owner, sleeping, floorOnly)
    if floorOnly then
        return { goal = Tasks.randomPoint(home, 2, owner, ZombRand) or home }
    end
    local best, score
    local center = getCell():getGridSquare(home.x, home.y, home.z)
    local building = center and center:getBuilding()
    for dx = -8, 8 do
        for dy = -8, 8 do
            if dx * dx + dy * dy <= 64 then
                local sq = getCell():getGridSquare(math.floor(home.x) + dx, math.floor(home.y) + dy, home.z)
                if Resources.allowed(sq, owner) and (not building or sq:getBuilding() == building) then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        local props = object:getProperties()
                        local bed = props and props:has "BedType"
                        local seat = props
                            and (
                                props:has "IsSitChair"
                                or props:has "IsLow"
                                or props:has "CustomName"
                                    and tostring(props:get "CustomName"):find("Chair", 1, true)
                            )
                        if bed or not sleeping and seat then
                            local goal = Resources.goal(sq, owner, true)
                            local d = dx * dx + dy * dy + (sleeping and not bed and 100 or 0)
                            if goal and (not score or d < score) then
                                best, score = { goal = goal, furniture = object, bed = bed }, d
                            end
                        end
                    end
                end
            end
        end
    end
    return best or { goal = Tasks.randomPoint(home, 2, owner, ZombRand) or home }
end

return Tasks
