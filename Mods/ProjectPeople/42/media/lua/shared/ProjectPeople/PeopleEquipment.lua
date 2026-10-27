-- Reads and moves original native equipment. Client views contain descriptions only.
local Equipment = {}
local fishingOriginal, fishingGuard

function Equipment.guardPlayerEvents()
    -- Installed 42.21 Fishing.Handler.onEquipPrimary accepts any local body,
    -- then calls player-only getPlayerNum/getUsername. Keep its normal event
    -- and player behaviour; only our tagged native zombie bodies skip fishing.
    if
        Fishing
        and Fishing.Handler
        and Fishing.Handler.handleFishing
        and Fishing.Handler.handleFishing ~= fishingGuard
    then
        fishingOriginal = Fishing.Handler.handleFishing
        local original = fishingOriginal
        fishingGuard = function(actor, item)
            if instanceof(actor, "IsoZombie") and actor:getModData().ProjectPeoplePersonId then
                return
            end
            return original(actor, item)
        end
        Fishing.Handler.handleFishing = fishingGuard
    end
end

function Equipment.id(item)
    return "native:" .. string.format("%.0f", item:getID())
end

function Equipment.prepareRemoval(item)
    -- Food.OnBeforeRemoveFromContainer calls updateAge() with packet emission.
    -- Vanilla ContainerID has no living-zombie inventory address. Advance the
    -- real food state first using the engine's non-broadcast overload, just as
    -- Food.update does on servers. The subsequent transfer packet contains the
    -- updated original item; no age or freshness is frozen or reset.
    if not isServer() then
        return
    end
    if instanceof(item, "Food") then
        item:updateAge(false)
    end
    if instanceof(item, "InventoryContainer") then
        local items = item:getInventory():getItems()
        for i = 0, items:size() - 1 do
            Equipment.prepareRemoval(items:get(i))
        end
    end
end

function Equipment.scan(actor)
    local result = { items = {}, containers = { root = actor:getInventory() }, order = {} }
    local visited = {}
    local function visit(container, parent, depth)
        assert(depth <= 16 and not visited[container], "inventory_cycle_or_depth")
        visited[container] = true
        local list = container:getItems()
        for i = 0, list:size() - 1 do
            local item = list:get(i)
            local id = Equipment.id(item)
            assert(not result.items[id] and item:getContainer() == container, "inventory_identity_conflict")
            assert(#result.order < 4096, "inventory_too_large")
            local entry = { item = item, container = container, parent = parent, id = id, depth = depth }
            result.items[id] = entry
            result.order[#result.order + 1] = entry
            if instanceof(item, "InventoryContainer") then
                result.containers[id] = item:getInventory()
                visit(item:getInventory(), id, depth + 1)
            end
        end
    end
    visit(actor:getInventory(), "root", 0)
    return result
end

function Equipment.slot(item)
    if instanceof(item, "InventoryContainer") then
        return item:canBeEquipped()
    end
    return item:getBodyLocation()
end

function Equipment.worn(actor, item)
    return actor:getWornItems():getLocation(item) ~= nil
end

function Equipment.giftMode(item)
    if instanceof(item, "HandWeapon") then
        return "weapon"
    end
    if (instanceof(item, "Clothing") or instanceof(item, "InventoryContainer")) and Equipment.slot(item) then
        return "wear"
    end
end

function Equipment.giftEquipMode(scan, item)
    local mode = Equipment.giftMode(item)
    if not mode or item:getCondition() <= 0 then
        return nil
    end
    local bag = instanceof(item, "InventoryContainer")
    local slot = mode == "wear" and Equipment.slot(item)
    local group = slot and BodyLocations.getGroup "Human"
    for _, entry in ipairs(scan.order) do
        local other = entry.item
        if other ~= item then
            if mode == "weapon" and instanceof(other, "HandWeapon") then
                return nil
            end
            if bag and instanceof(other, "InventoryContainer") and Equipment.slot(other) then
                return nil
            end
            local otherSlot = mode == "wear" and Equipment.slot(other)
            if
                slot
                and otherSlot
                and (slot == otherSlot or group:isExclusive(slot, otherSlot) or group:isExclusive(otherSlot, slot))
            then
                return nil
            end
        end
    end
    return mode
end

function Equipment.active(actor, item)
    return actor:getPrimaryHandItem() == item or actor:getSecondaryHandItem() == item or Equipment.worn(actor, item)
end

function Equipment.describe(actor, scan)
    local result = {
        items = {},
        containers = {
            {
                id = "root",
                name = "Main inventory",
                weight = actor:getInventoryWeight(),
                capacity = actor:getMaxWeight(),
            },
        },
        weight = actor:getInventoryWeight(),
        capacity = actor:getMaxWeight(),
    }
    for _, entry in ipairs(scan.order) do
        local item = entry.item
        local weapon = instanceof(item, "HandWeapon")
        local bag = instanceof(item, "InventoryContainer")
        result.items[#result.items + 1] = {
            id = entry.id,
            name = item:getDisplayName(),
            kind = item:getFullType(),
            parent = entry.parent,
            depth = entry.depth,
            weight = item:getUnequippedWeight(),
            condition = item:getCondition(),
            equipped = Equipment.active(actor, item),
            weapon = weapon,
            wearable = Equipment.slot(item) ~= nil,
            ammo = weapon and item:isRanged() and item:getCurrentAmmoCount() + (item:isRoundChambered() and 1 or 0)
                or nil,
            favorite = item:isFavorite(),
        }
        if bag then
            local c = item:getInventory()
            result.containers[#result.containers + 1] = {
                id = entry.id,
                name = item:getDisplayName(),
                weight = c:getCapacityWeight(),
                capacity = c:getEffectiveCapacity(actor),
                reduction = item:getWeightReduction(),
            }
        end
    end
    return result
end

function Equipment.detach(actor, item)
    Equipment.guardPlayerEvents()
    if actor:getPrimaryHandItem() == item then
        actor:setPrimaryHandItem(nil)
    end
    if actor:getSecondaryHandItem() == item then
        actor:setSecondaryHandItem(nil)
    end
    if Equipment.worn(actor, item) then
        actor:removeWornItem(item, false)
    end
end

function Equipment.canMove(actor, entry)
    local item = entry.item
    if item:isFavorite() then
        return false, "Unfavorite the item before trading it."
    end
    if Equipment.active(actor, item) or item:getAttachedSlot() >= 0 then
        return false, "Unequip or detach the item first."
    end
    if item:getIsCraftingConsumed() or item:getJobDelta() > 0 or item:getWorldItem() then
        return false, "That item is currently in use."
    end
    return true
end

function Equipment.capacity(actor, destination, item)
    if destination:isInside(item) then
        return false, "A bag cannot contain itself."
    end
    if not destination:isItemAllowed(item) or not destination:hasRoomFor(actor, item) then
        return false, "There is no room in the selected container."
    end
    -- ItemContainer's zombie capacity is not a human carrying limit. Explicitly
    -- enforce native character encumbrance as well as the bag's own capacity.
    local factor = 1
    local cursor = destination
    while cursor ~= actor:getInventory() do
        local bag = cursor:getContainingItem()
        if not bag then
            return false, "Container ownership changed."
        end
        if Equipment.active(actor, bag) then
            factor = factor * (1 - bag:getWeightReduction() / 100)
        end
        cursor = bag:getContainer()
        if not cursor then
            return false, "Container ownership changed."
        end
    end
    if actor:getInventoryWeight() + item:getUnequippedWeight() * factor > actor:getMaxWeight() + 0.0001 then
        return false, "That would exceed their carrying capacity."
    end
    return true
end

function Equipment.equip(actor, entry, mode)
    Equipment.guardPlayerEvents()
    local item = entry.item
    if item:getIsCraftingConsumed() or item:getJobDelta() > 0 or item:getAttachedSlot() >= 0 then
        return false, "That item is in use or attached."
    end
    if mode == "unequip" then
        if Equipment.worn(actor, item) and instanceof(item, "InventoryContainer") then
            local increase = item:getUnequippedWeight() - item:getEquippedWeight()
            if actor:getInventoryWeight() + increase > actor:getMaxWeight() then
                return false, "Empty the bag before taking it off."
            end
        end
        Equipment.detach(actor, item)
    elseif mode == "weapon" then
        if not instanceof(item, "HandWeapon") or item:getCondition() <= 0 then
            return false, "Choose a usable weapon."
        end
        if entry.container ~= actor:getInventory() then
            return false, "Move the weapon to their main inventory first."
        end
        Equipment.detach(actor, item)
        actor:setSecondaryHandItem(nil)
        actor:setPrimaryHandItem(item)
        if item:isTwoHandWeapon() then
            actor:setSecondaryHandItem(item)
        end
    elseif mode == "wear" then
        local slot = Equipment.slot(item)
        if not slot then
            return false, "This item cannot be worn."
        end
        if entry.container ~= actor:getInventory() then
            return false, "Move the item to their main inventory first."
        end
        -- Test the complete resulting worn set, including mutually exclusive
        -- slots, without dropping or copying any native item.
        local worn = actor:getWornItems()
        local old = {}
        for i = 0, worn:size() - 1 do
            old[#old + 1] = { slot = worn:get(i):getLocation(), item = worn:get(i):getItem() }
        end
        actor:setWornItem(slot, item, false)
        if actor:getInventoryWeight() > actor:getMaxWeight() + 0.0001 then
            actor:clearWornItems()
            for _, previous in ipairs(old) do
                actor:setWornItem(previous.slot, previous.item, false)
            end
            return false, "Changing equipment would exceed their carrying capacity."
        end
    else
        return false, "Unknown equipment order."
    end
    actor:resetModelNextFrame()
    return true
end

function Equipment.hands(actor)
    local item = actor:getPrimaryHandItem()
    if not item or not instanceof(item, "HandWeapon") then
        return false
    end
    return {
        id = Equipment.id(item),
        kind = item:getFullType(),
        condition = item:getCondition(),
        twoHand = item:isTwoHandWeapon(),
        ranged = item:isRanged(),
    }
end

function Equipment.present(actor, record, binding)
    local hand = record.equipment
    actor:setVariable("ProjectPeopleRanged", record.attackRanged == true)
    actor:setVariable("ProjectPeopleTwoHanded", hand and hand.twoHand == true or false)
    if not isClient or not isClient() or hand == nil then
        return
    end
    Equipment.guardPlayerEvents()
    local key = hand and hand.id .. ":" .. hand.kind .. ":" .. hand.condition or "empty"
    if binding.equipmentKey == key then
        return
    end
    local item = hand and instanceItem(hand.kind) or nil
    if item then
        item:setCondition(hand.condition)
    end
    actor:setPrimaryHandItem(item)
    actor:setSecondaryHandItem(hand and hand.twoHand and item or nil)
    binding.equipmentKey = key
end
return Equipment
