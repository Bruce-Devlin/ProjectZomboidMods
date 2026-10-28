local Policy = require "ProjectPeople/EquipmentPolicy"
local Equipment = require "ProjectPeople/PeopleEquipment"
local Weapons = {}

function Weapons.weapon(actor)
    if not actor.getPrimaryHandItem then
        return nil
    end
    local item = actor:getPrimaryHandItem()
    if
        item
        and instanceof(item, "HandWeapon")
        and item:getCondition() > 0
        and item:getContainer() == actor:getInventory()
    then
        return item
    end
end

function Weapons.profile(actor, person, distance)
    local weapon = Weapons.weapon(actor)
    if not weapon then
        return nil
    end
    local ranged = weapon:isRanged()
    local range = math.max(0.7, math.min(ranged and 12 or 2.5, weapon:getMaxRange()))
    local category = "Blunt"
    if WeaponCategory then
        for _, key in ipairs({ "Axe", "SmallBlade", "LongBlade", "Spear", "SmallBlunt" }) do
            local native = {
                Axe = "AXE",
                SmallBlade = "SMALL_BLADE",
                LongBlade = "LONG_BLADE",
                Spear = "SPEAR",
                SmallBlunt = "SMALL_BLUNT",
            }
            if WeaponCategory[native[key]] and weapon:isOfWeaponCategory(WeaponCategory[native[key]]) then
                category = key
                break
            end
        end
    end
    local stats = Policy.proficiency(person or { id = "unknown" }, ranged, actor:getHealth(), distance, range, category)
    stats.weapon = weapon
    stats.ranged = ranged
    stats.range = range
    -- The installed weapon definition owns its minimum usable reach. Keep a
    -- small body-contact floor, rather than treating every weapon like fists.
    stats.minRange = math.max(0.35, math.min(range, weapon.getMinRange and weapon:getMinRange() or 0.61))
    local meanDamage = (weapon:getMinDamage() + weapon:getMaxDamage()) * 0.5
    -- Zombie hits approach the weapon's base damage, retaining proficiency and
    -- the native-contact safety cap. Human victims keep their existing balance.
    stats.zombieDamage = math.max(0.05, math.min(0.9, meanDamage * 0.9 * stats.damage))
    stats.damage = math.max(0.05, math.min(0.9, meanDamage * 0.5 * stats.damage))
    return stats
end

function Weapons.ammunition(weapon)
    if weapon:isJammed() then
        return false, "Weapon jammed"
    end
    if weapon:haveChamber() then
        return weapon:isRoundChambered(), "Needs chambering or ammunition"
    end
    return weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot(), "Out of ammunition"
end

function Weapons.chamber(weapon)
    if weapon:isJammed() then
        return false
    end
    if
        weapon:haveChamber()
        and not weapon:isRoundChambered()
        and weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot()
    then
        weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() - weapon:getAmmoPerShoot())
        weapon:setRoundChambered(true)
        weapon:setSpentRoundChambered(false)
        return true
    end
    return false
end
-- Reload from actual loose ammunition. A detachable-magazine gun must already
-- contain its native magazine; empty magazines are never invented by this code.

function Weapons.reload(actor, weapon)
    if weapon:isJammed() or weapon:usesExternalMagazine() and not weapon:isContainsClip() then
        return false
    end
    local ammo = weapon:getAmmoType()
    if not ammo then
        return false
    end
    local kind = ammo:getItemKey()
    local needed = weapon:getMaxAmmo() - weapon:getCurrentAmmoCount()
    if needed <= 0 then
        return Weapons.chamber(weapon)
    end
    local count = 0
    for _, entry in ipairs(Equipment.scan(actor).order) do
        local item = entry.item
        if
            item:getFullType() == kind
            and not item:isFavorite()
            and item:getJobDelta() == 0
            and not item:getIsCraftingConsumed()
        then
            entry.container:DoRemoveItem(item)
            assert(item:getContainer() == nil, "ammunition_remove_unconfirmed")
            count = count + 1
            weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() + 1)
            if count >= needed then
                break
            end
        end
    end
    if count > 0 then
        Weapons.chamber(weapon)
    end
    return count > 0
end

function Weapons.clearLane(actor, target, people)
    local dx, dy = target:getX() - actor:getX(), target:getY() - actor:getY()
    local length = dx * dx + dy * dy
    for _, candidate in ipairs(people) do
        local other = candidate.actor
        if
            other ~= actor
            and other ~= target
            and candidate.kind ~= "zombie"
            and not other:isDead()
            and math.abs(other:getZ() - actor:getZ()) < 0.3
        then
            local x, y = other:getX() - actor:getX(), other:getY() - actor:getY()
            local t = length > 0 and (x * dx + y * dy) / length or 0
            if t > 0 and t < 1.1 and (x - t * dx) ^ 2 + (y - t * dy) ^ 2 < 0.75 ^ 2 then
                return false
            end
        end
    end
    return true
end

function Weapons.discharge(actor, weapon)
    local ready = Weapons.ammunition(weapon)
    if not ready then
        return false
    end
    if weapon:haveChamber() then
        weapon:setRoundChambered(false)
        weapon:setSpentRoundChambered(true)
    else
        weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() - weapon:getAmmoPerShoot())
    end
    -- World sound wakes nearby zombies even when the shot misses.
    addSound(actor, actor:getX(), actor:getY(), actor:getZ(), weapon:getSoundRadius(), weapon:getSoundVolume())
    local sound = weapon:getSwingSound()
    if sound then
        actor:playSound(sound)
    end
    return true
end

function Weapons.wear(weapon, roll)
    if roll < 1 / math.max(1, weapon:getConditionLowerChance()) then
        weapon:setCondition(math.max(0, weapon:getCondition() - 1))
    end
end
return Weapons
