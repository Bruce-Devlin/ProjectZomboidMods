-- Original-item access for local home chores, only on the simulation authority.
local Equipment = require "ProjectPeople/PeopleEquipment"
local Resources = {}

function Resources.needLabel(need)
    local labels = {
        ["Base.Plank"] = "planks",
        ["Base.Nails"] = "nails",
        ["Base.SheetMetal"] = "sheet metal",
        fuel = "petrol",
        water = "water",
        cleaner = "cleaning liquid",
        cleaning_tool = "a cleaning tool",
        fertilizer = "fertiliser",
        hammer = "a hammer",
        food = "safe food",
        seed = "seeds",
    }
    return labels[need.type or need.kind] or "supplies"
end

function Resources.setWorld(world)
    Resources.reservedItems = world and world.items or {}
end

function Resources.unlocked(object)
    return not (instanceof(object, "IsoThumpable") and (object:isLockedByPadlock() or object:isLockedByKey()))
end

function Resources.fluid(item, fluid, minimum)
    local f = item.getFluidContainer and item:getFluidContainer()
    return f and f:getAmount() >= (minimum or 0.01) and f:contains(fluid) and f:getPrimaryFluid() == fluid and f or nil
end

function Resources.matches(item, need)
    -- Journalled mission/transfer cargo keeps its existing reconciliation path.
    -- Ordinary native inventory is free to use; home chores never silently edit
    -- an unrelated job's ownership ledger or consume its reserved originals.
    if Resources.reservedItems and Resources.reservedItems[Equipment.id(item)] then
        return false
    end
    if need.type then
        return item:getFullType() == need.type
    end
    if need.kind == "fuel" then
        return Resources.fluid(item, Fluid.Petrol) ~= nil
    end
    if need.kind == "water" then
        return Resources.fluid(item, Fluid.Water, ZomboidGlobals.farmingFluidContainerMillilitresPerUse / 1000) ~= nil
    end
    if need.kind == "cleaner" then
        return Resources.fluid(item, Fluid.Bleach, ZomboidGlobals.CleanBloodBleachAmount) ~= nil
            or Resources.fluid(item, Fluid.CleaningLiquid, ZomboidGlobals.CleanBloodBleachAmount) ~= nil
    end
    if need.kind == "cleaning_tool" then
        return item:hasTag(ItemTag.CLEAN_STAINS) and not item:isBroken()
    end
    if need.kind == "fertilizer" then
        return (item:getFullType() == "Base.Fertilizer" or item:hasTag(ItemTag.COMPOST))
            and item:IsDrainable()
            and item:getCurrentUsesFloat() > 0
    end
    if need.kind == "hammer" then
        return item:hasTag(ItemTag.HAMMER) and not item:isBroken()
    end
    if need.kind == "food" then
        return instanceof(item, "Food")
            and item:getHungerChange() < 0
            and not item:isRotten()
            and not item:isBurnt()
            and item:getPoisonPower() <= 0
            and not item:isTainted()
            and not (item:isbDangerousUncooked() and not item:isCooked())
    end
    if need.kind == "seed" then
        if not farming_vegetableconf then
            return false
        end
        local names = {}
        for name in pairs(farming_vegetableconf.props) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local props = farming_vegetableconf.props[name]
            for _, fullType in ipairs(props.seedTypes or { props.seedName }) do
                if item:getFullType() == fullType then
                    return true, name
                end
            end
        end
    end
    return false
end

function Resources.find(container, need, depth)
    if not container or (depth or 0) > 4 then
        return nil
    end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Resources.matches(item, need) then
            return item
        end
        if instanceof(item, "InventoryContainer") then
            local nested = Resources.find(item:getInventory(), need, (depth or 0) + 1)
            if nested then
                return nested
            end
        end
    end
end

function Resources.inInventory(actor, item)
    local container = item and item:getContainer()
    for _ = 1, 6 do
        if not container then
            return false
        end
        if container == actor:getInventory() then
            return true
        end
        local bag = container:getContainingItem()
        container = bag and bag:getContainer()
    end
    return false
end

function Resources.allowed(square, owner)
    if not square or not square:TreatAsSolidFloor() or square:isWaterSquare() then
        return false
    end
    if square.haveFire and square:haveFire() then
        return false
    end
    local username = owner and owner.getUsername and owner:getUsername()
    return not SafeHouse or not SafeHouse.isSafeHouse(square, username, true)
end

function Resources.near(actor, square)
    local from = actor:getCurrentSquare()
    return from
        and square
        and math.abs(actor:getZ() - square:getZ()) < 0.2
        and math.abs(from:getX() - square:getX()) <= 1
        and math.abs(from:getY() - square:getY()) <= 1
        and not from:isBlockedTo(square)
        and not from:isSomethingTo(square)
end

function Resources.crop(square)
    return square and square:hasFarmingPlant()
end

function Resources.goal(square, owner, adjacentOnly)
    if not square then
        return nil
    end
    for _, offset in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local near = getCell():getGridSquare(square:getX() + offset[1], square:getY() + offset[2], square:getZ())
        if
            Resources.allowed(near, owner)
            and (not adjacentOnly or offset[1] ~= 0 or offset[2] ~= 0)
            and not Resources.crop(near)
            and near:isFree(false)
            and not near:isBlockedTo(square)
            and not near:isSomethingTo(square)
        then
            return { x = near:getX() + 0.5, y = near:getY() + 0.5, z = near:getZ() }
        end
    end
end

-- Native zombie-backed bodies trample plants. Commit to cardinal waypoints only
-- when a direct leg crosses farmland; ordinary native door navigation stays intact.
function Resources.cropRoute(actor, goal, owner, home)
    local start = actor:getCurrentSquare()
    if not start or not goal then
        return nil
    end
    local gx, gy = math.floor(goal.x), math.floor(goal.y)
    local sx, sy, z = start:getX(), start:getY(), start:getZ()
    local steps = math.max(math.abs(gx - sx), math.abs(gy - sy)) * 4
    local crossed = false
    for i = 1, steps do
        local sq = getCell():getGridSquare(
            math.floor(sx + 0.5 + (gx - sx) * i / steps),
            math.floor(sy + 0.5 + (gy - sy) * i / steps),
            z
        )
        if Resources.crop(sq) then
            crossed = true
            break
        end
    end
    if not crossed then
        return nil
    end
    local queue, seen, at = { { square = start } }, { [sx .. ":" .. sy] = true }, 1
    while queue[at] and at <= 2048 do
        local node = queue[at]
        local sq = node.square
        if sq:getX() == gx and sq:getY() == gy then
            local path = {}
            while node.parent do
                table.insert(path, 1, { x = node.square:getX() + 0.5, y = node.square:getY() + 0.5, z = z })
                node = node.parent
            end
            -- Keep the bends, not every tile. Tiny stop/start paths can be
            -- cancelled by native state exits before their next leg starts.
            local bends, previous = {}, { x = sx + 0.5, y = sy + 0.5 }
            for i, point in ipairs(path) do
                local nextPoint = path[i + 1]
                if
                    not nextPoint
                    or (point.x - previous.x) * (nextPoint.y - point.y)
                        ~= (point.y - previous.y) * (nextPoint.x - point.x)
                then
                    bends[#bends + 1] = point
                end
                previous = point
            end
            return bends
        end
        for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
            local x, y = sq:getX() + d[1], sq:getY() + d[2]
            local key = x .. ":" .. y
            if not seen[key] and (x + 0.5 - home.x) ^ 2 + (y + 0.5 - home.y) ^ 2 <= 22 ^ 2 then
                seen[key] = true
                local nextSquare = getCell():getGridSquare(x, y, z)
                if
                    Resources.allowed(nextSquare, owner)
                    and not Resources.crop(nextSquare)
                    and nextSquare:isFree(false)
                    and not sq:isBlockedTo(nextSquare)
                    and not sq:isSomethingTo(nextSquare)
                then
                    queue[#queue + 1] = { square = nextSquare, parent = node }
                end
            end
        end
        at = at + 1
    end
    return false
end

-- Scans are cached by HomeRuntime; unloaded chunks and other safehouses are excluded.
function Resources.containers(home, owner)
    local result = {}
    for dx = -20, 20 do
        for dy = -20, 20 do
            if dx * dx + dy * dy <= 400 then
                local square = getCell():getGridSquare(math.floor(home.x) + dx, math.floor(home.y) + dy, home.z)
                if Resources.allowed(square, owner) then
                    local objects = square:getObjects()
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        for index = 0, object:getContainerCount() - 1 do
                            local container = object:getContainerByIndex(index)
                            if container then
                                result[#result + 1] = { container = container, square = square, object = object }
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

function Resources.source(containers, need, actor, owner)
    local best, score
    for _, entry in ipairs(containers) do
        if
            entry.object:getObjectIndex() >= 0
            and Resources.unlocked(entry.object)
            and Resources.allowed(entry.square, owner)
        then
            local item = Resources.find(entry.container, need)
            local d = (actor:getX() - entry.square:getX()) ^ 2 + (actor:getY() - entry.square:getY()) ^ 2
            if item and (not score or d < score) and entry.container:isRemoveItemAllowed(item) then
                local goal = Resources.goal(entry.square, owner)
                if goal then
                    best, score = { item = item, square = entry.square, object = entry.object, goal = goal }, d
                end
            end
        end
    end
    return best
end

function Resources.move(item, actor, sourceSquare, owner, destinationActor)
    assert(not isClient(), "home_resources_authority_only")
    if not Resources.near(actor, sourceSquare) or not Resources.allowed(sourceSquare, owner) then
        return false
    end
    local source, destination = item:getContainer(), (destinationActor or actor):getInventory()
    if not source or not source:getItems():contains(item) or not source:isRemoveItemAllowed(item) then
        return false
    end
    if destinationActor then
        if not Resources.inInventory(actor, item) or not Resources.near(destinationActor, sourceSquare) then
            return false
        end
    else
        local root = source
        for _ = 1, 6 do
            local bag = root and root:getContainingItem()
            if not bag then
                break
            end
            root = bag:getContainer()
        end
        local object = root and root:getParent()
        if
            not object
            or instanceof(object, "IsoGameCharacter")
            or object:getSquare() ~= sourceSquare
            or object:getObjectIndex() < 0
            or not Resources.unlocked(object)
        then
            return false
        end
    end
    if not Equipment.capacity(destinationActor or actor, destination, item) then
        return false
    end
    local ok = pcall(function()
        Equipment.prepareRemoval(item)
        source:DoRemoveItem(item)
        assert(item:getContainer() == nil, "home_item_remove_unconfirmed")
        assert(destination:AddItem(item) == item and item:getContainer() == destination, "home_item_add_unconfirmed")
    end)
    if not ok and item:getContainer() == nil then
        source:AddItem(item)
    end
    if item:getContainer() ~= destination then
        return false
    end
    local holder = (destinationActor or actor):getModData()
    holder.ProjectPeopleHomeCargo = holder.ProjectPeopleHomeCargo or {}
    holder.ProjectPeopleHomeCargo[Equipment.id(item)] = true
    if destinationActor and actor:getModData().ProjectPeopleHomeCargo then
        actor:getModData().ProjectPeopleHomeCargo[Equipment.id(item)] = nil
    end
    if isServer() then
        if not destinationActor then
            sendRemoveItemFromContainer(source, item)
        end
    end
    return true
end

function Resources.surplus(actor, needs)
    local cargo = actor:getModData().ProjectPeopleHomeCargo
    if not cargo then
        return nil
    end
    local any = false
    for _ in pairs(cargo) do
        any = true
        break
    end
    if not any then
        return nil
    end
    local inventory = Equipment.scan(actor)
    for id in pairs(cargo) do
        local entry = inventory.items[id]
        if not entry then
            cargo[id] = nil
        elseif
            not (Resources.reservedItems and Resources.reservedItems[id]) and not Equipment.active(actor, entry.item)
        then
            local needed = false
            for _, need in ipairs(needs or {}) do
                if Resources.matches(entry.item, need) then
                    needed = true
                    break
                end
            end
            if not needed then
                return entry.item
            end
        end
    end
end

function Resources.storage(containers, actor, item, owner)
    local best, score
    for _, entry in ipairs(containers) do
        local d = (actor:getX() - entry.square:getX()) ^ 2 + (actor:getY() - entry.square:getY()) ^ 2
        if
            entry.object:getObjectIndex() >= 0
            and Resources.unlocked(entry.object)
            and Resources.allowed(entry.square, owner)
            and entry.container:isItemAllowed(item)
            and entry.container:hasRoomFor(actor, item)
            and (not score or d < score)
        then
            local goal = Resources.goal(entry.square, owner)
            if goal then
                best, score = { entry = entry, goal = goal }, d
            end
        end
    end
    return best
end

function Resources.store(actor, item, entry, owner)
    assert(not isClient(), "home_resources_authority_only")
    local destination = entry.container
    if
        not Resources.inInventory(actor, item)
        or not Resources.near(actor, entry.square)
        or not Resources.allowed(entry.square, owner)
        or entry.object:getObjectIndex() < 0
        or entry.object:getSquare() ~= entry.square
        or destination:getParent() ~= entry.object
        or not Resources.unlocked(entry.object)
        or not destination:isItemAllowed(item)
        or not destination:hasRoomFor(actor, item)
    then
        return false
    end
    local source = item:getContainer()
    local ok = pcall(function()
        Equipment.prepareRemoval(item)
        source:DoRemoveItem(item)
        assert(item:getContainer() == nil, "home_return_remove_unconfirmed")
        assert(destination:AddItem(item) == item and item:getContainer() == destination, "home_return_add_unconfirmed")
    end)
    if not ok and item:getContainer() == nil then
        source:AddItem(item)
    end
    if item:getContainer() ~= destination then
        return false
    end
    actor:getModData().ProjectPeopleHomeCargo[Equipment.id(item)] = nil
    if isServer() then
        sendAddItemToContainer(destination, item)
    end
    return true
end

function Resources.remove(actor, item)
    assert(not isClient(), "home_resources_authority_only")
    if not Resources.inInventory(actor, item) then
        return false
    end
    local container = item:getContainer()
    Equipment.prepareRemoval(item)
    container:DoRemoveItem(item)
    if item:getContainer() ~= nil then
        return false
    end
    return true
end

function Resources.consumeFluid(item, amount)
    local fluid = item:getFluidContainer()
    if not fluid or fluid:getAmount() + 0.00001 < amount then
        return false
    end
    fluid:adjustAmount(math.max(0, fluid:getAmount() - amount))
    if not isServer() then
        item:syncItemFields()
    end
    return true
end

function Resources.eat(actor, item)
    assert(not isClient(), "home_resources_authority_only")
    if not Resources.inInventory(actor, item) or not Resources.matches(item, { kind = "food" }) then
        return false
    end
    -- IsoGameCharacter.Eat dereferences BodyDamage, which IsoZombie does not own.
    -- Apply the safe native stats and consume the original food through its normal
    -- item-use path. Never construct replacement food or a second hunger model.
    local stats = actor:getStats()
    stats:add(CharacterStat.HUNGER, item:getHungerChange())
    stats:add(CharacterStat.THIRST, item:getThirstChange())
    stats:add(CharacterStat.ENDURANCE, item:getEnduranceChange())
    stats:add(CharacterStat.STRESS, item:getStressChange())
    stats:add(CharacterStat.FATIGUE, item:getFatigueChange())
    Equipment.prepareRemoval(item)
    -- Native Eat zeroes the consumed food before Use (including containers with
    -- replacement items). A retained empty original must never feed twice.
    item:setHungChange(0)
    item:Use(false, false, false)
    return true
end

return Resources
