-- Deterministic new-birth loadouts. Existing bodies and inventories never refill.
local DevTools = require "ProjectPeople/DevTools"
local Equipment = require "ProjectPeople/PeopleEquipment"
local Birth = {}
local basic = { "Base.Hammer", "Base.BaseballBat", "Base.Crowbar", "Base.PipeWrench", "Base.KitchenKnife" }
local advanced = { "Base.HandAxe", "Base.Axe", "Base.HuntingKnife", "Base.Crowbar", "Base.BaseballBat", "Base.Shotgun" }
local tops = { "Base.Tshirt_DefaultTEXTURE_TINT", "Base.Shirt_Denim", "Base.HoodieDOWN_WhiteTINT" }

function Birth.profile(id, days)
    local function roll(key)
        return (DevTools.hash(id .. ":birth:" .. key) % 10000) / 10000
    end
    local function pick(values, key)
        return values[math.floor(roll(key) * #values) + 1]
    end
    local late = days >= 180
    local experienced = days >= 30
    local result = {
        clothes = { pick(tops, "shirt"), "Base.Trousers_Denim", "Base.Shoes_TrainerTINT" },
        condition = 0.55 + roll "condition" * 0.4,
    }
    if roll "armed" < (late and 0.95 or experienced and 0.9 or 0.8) then
        local upgraded = roll "upgrade" < (late and 0.75 or experienced and 0.35 or 0.05)
        result.weapon = pick(upgraded and advanced or basic, "weapon")
        if not experienced and result.weapon == "Base.Shotgun" then
            result.weapon = "Base.Crowbar"
        end
    end
    if roll "bag" < (late and 0.8 or experienced and 0.5 or 0.2) then
        result.clothes[#result.clothes + 1] = late and "Base.Bag_NormalHikingBag" or "Base.Bag_Schoolbag"
    end
    if experienced and roll "jacket" < (late and 0.65 or 0.3) then
        result.clothes[#result.clothes + 1] = "Base.Jacket_ArmyCamoGreen"
    end
    if late and roll "protection" < 0.25 then
        result.clothes[#result.clothes + 1] = "Base.Vest_BulletArmy"
    end
    return result
end

function Birth.initialise(actor, person, days)
    local md = actor:getModData()
    if md.ProjectPeopleBirthEquipmentVersion then
        return
    end
    -- Mark before adding anything: an interrupted birth never authorises refill.
    md.ProjectPeopleBirthEquipmentVersion = 1
    local profile = Birth.profile(person.id, days)
    Equipment.guardPlayerEvents()
    if actor:getWornItems():size() == 0 then
        for _, kind in ipairs(profile.clothes) do
            local item = actor:getInventory():AddItem(kind)
            assert(item, "birth_item_missing:" .. kind)
            local slot = Equipment.slot(item)
            assert(slot, "birth_item_not_wearable:" .. kind)
            actor:setWornItem(slot, item, false)
        end
    end
    if profile.weapon and not actor:getPrimaryHandItem() then
        local item = actor:getInventory():AddItem(profile.weapon)
        assert(item, "birth_weapon_missing:" .. profile.weapon)
        item:setCondition(math.max(1, math.floor(item:getConditionMax() * profile.condition)))
        actor:setPrimaryHandItem(item)
        if item:isTwoHandWeapon() then
            actor:setSecondaryHandItem(item)
        end
        if item:isRanged() then
            item:setCurrentAmmoCount(math.min(6, item:getMaxAmmo()))
            if item:haveChamber() then
                item:setRoundChambered(true)
            end
            for i = 1, 12 do
                actor:getInventory():AddItem "Base.ShotgunShells"
            end
        end
    end
end
return Birth
