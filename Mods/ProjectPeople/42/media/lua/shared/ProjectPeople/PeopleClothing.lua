-- Real authority-owned birth items. Never refill an equipped/looted wardrobe.
local Clothing = {}
local Codec = require "ProjectPeople/Codec"

function Clothing.initialise(actor)
    assert(not isClient or not isClient(), "clothing_authority_only")
    local md = actor:getModData()
    if md.ProjectPeopleClothingVersion then
        return
    end
    if actor:getWornItems():size() == 0 then
        for _, kind in ipairs({ "Base.Tshirt_DefaultTEXTURE_TINT", "Base.Trousers_Denim", "Base.Shoes_TrainerTINT" }) do
            local item = actor:getInventory():AddItem(kind)
            assert(item and item:getBodyLocation(), "birth_clothing_missing:" .. kind)
            actor:setWornItem(item:getBodyLocation(), item)
        end
    end
    actor:setDressInRandomOutfit(false)
    md.ProjectPeopleClothingVersion = 1
end

function Clothing.snapshot(actor)
    local result = {}
    local worn = actor:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        local v = item:getVisual()
        local tint = v:getTint(item:getClothingItem())
        local entry = {
            kind = item:getFullType(),
            id = item:getID(),
            condition = item:getCondition(),
            tint = { r = tint:getRedFloat(), g = tint:getGreenFloat(), b = tint:getBlueFloat() },
            texture = v:getTextureChoice(),
            base = v:getBaseTexture(),
            marks = {},
        }
        for part = 0, BloodBodyPartType.MAX:index() - 1 do
            local p = BloodBodyPartType.FromIndex(part)
            local blood, dirt, hole = v:getBlood(p), v:getDirt(p), v:getHole(p)
            if blood > 0 or dirt > 0 or hole > 0 then
                entry.marks[#entry.marks + 1] = { part = part, blood = blood, dirt = dirt, hole = hole }
            end
        end
        result[#result + 1] = entry
    end
    return result
end

function Clothing.present(actor, items, binding)
    if not isClient or not isClient() or not items then
        return
    end
    if binding.clothingSnapshot == items and actor:getWornItems():size() == #items then
        return
    end
    local signature = Codec.encode(items)
    binding.clothingSnapshot = items
    if binding.clothingSignature == signature and actor:getWornItems():size() == #items then
        return
    end
    -- Presentation replicas only, never added to a client's loot inventory.
    -- Empty snapshots remove clothes too; a removed item is not respawned.
    actor:getWornItems():clear()
    for _, entry in ipairs(items) do
        local item = instanceItem(entry.kind)
        assert(item, "replicated_clothing_missing:" .. entry.kind)
        item:setCondition(entry.condition)
        local v = item:getVisual()
        if entry.tint then
            v:setTint(ImmutableColor.new(entry.tint.r, entry.tint.g, entry.tint.b, 1))
        end
        if entry.texture then
            v:setTextureChoice(entry.texture)
        end
        if entry.base then
            v:setBaseTexture(entry.base)
        end
        for _, mark in ipairs(entry.marks or {}) do
            local part = BloodBodyPartType.FromIndex(mark.part)
            v:setBlood(part, mark.blood)
            v:setDirt(part, mark.dirt)
            if mark.hole > 0 then
                v:setHole(part)
            end
        end
        local slot = instanceof(item, "InventoryContainer") and item:canBeEquipped() or item:getBodyLocation()
        actor:setWornItem(slot, item)
    end
    actor:resetModelNextFrame()
    binding.clothingSignature = signature
end
return Clothing
