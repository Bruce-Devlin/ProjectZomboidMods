-- Server-owned target choice, telegraphed strikes and native damage. No client
-- success reports. The household coordinator calls tick and publishes records.
local Policy = require "ProjectPeople/CombatPolicy"
local Body = require "ProjectPeople/PeopleBody"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Weapons = require "ProjectPeople/PeopleWeapons"
local SocialGroup = require "ProjectPeople/Behaviour/Groups"
local Combat = {}

function Combat.applyDamage(actor, target, weapon, damage, kind)
    assert(type(damage) == "number" and damage >= 0 and damage <= 1, "bounded_combat_damage_required")
    if kind == "player" then
        -- IsoPlayer.hitConsequences ignores Hit's damage argument and rolls
        -- DamageFromWeapon again. Use ordinary native body damage for a bounded
        -- unarmed blow; no infection, invented wound or player-control override.
        local body = target:getBodyDamage()
        assert(body, "native_player_body_required")
        target:setAttackedBy(actor)
        body:ReduceGeneralHealth(damage * 100)
        body:calculateOverallHealth()
        target:setHitReaction "HitReaction"
    else
        -- The melee knockback branch awards Strength XP through an IsoPlayer
        -- cast on servers. Suppress only during this NPC hit, then restore the
        -- original weapon property before it can be traded back to a player.
        if weapon.isKnockBackOnNoDeath then
            local knockback = weapon:isKnockBackOnNoDeath()
            weapon:setKnockBackOnNoDeath(false)
            local ok, err = pcall(function()
                target:Hit(weapon, actor, damage, false, 1, false)
            end)
            weapon:setKnockBackOnNoDeath(knockback)
            if not ok then
                error(err)
            end
        else
            target:Hit(weapon, actor, damage, false, 1, false)
        end
    end
end

local function distance(a, b)
    if math.abs(a:getZ() - b:getZ()) > 0.2 then
        return math.huge
    end
    return (a:getX() - b:getX()) ^ 2 + (a:getY() - b:getY()) ^ 2
end

local function clear(a, b)
    local from, to = a:getCurrentSquare(), b:getCurrentSquare()
    if not from or not to or from:isBlockedTo(to) or from:isSomethingTo(to) then
        return false
    end
    return tostring(
        LosUtil.lineClear(getCell(), from:getX(), from:getY(), from:getZ(), to:getX(), to:getY(), to:getZ(), false)
    ) == "Clear"
end

function Combat.new(config)
    local strikes, cooldowns, enemies, approaches = {}, {}, {}, {}
    local fists
    local self = {}
    function self:isEnemy(id, actor)
        return enemies[id] ~= nil and enemies[id][actor] == true
    end
    function self:interrupt(id, record)
        strikes[id] = nil
        approaches[id] = nil
        record.combatActive = false
        record.attacking = false
        record.retreating = false
    end
    function self:provoked(victim, attacker)
        if not victim or not attacker or victim == attacker then
            return
        end
        local id = victim:getModData().ProjectPeoplePersonId
        if id and config.actor and config.actor(id) ~= victim then
            return
        end
        if id then
            enemies[id] = enemies[id] or {}
            enemies[id][attacker] = true
        end
        local world = config.world and config.world()
        if not id or not world or not config.actor then
            return
        end
        -- Sample witnesses now, including a fatal hit. No later proximity scan
        -- teaches distant relatives about an attack they never witnessed.
        for _, member in ipairs(SocialGroup.members(world, id)) do
            local witness = config.actor(member)
            if
                witness
                and witness ~= attacker
                and not witness:isDead()
                and distance(witness, victim) <= Policy.NOTICE_RADIUS ^ 2
                and distance(witness, attacker) <= Policy.NOTICE_RADIUS ^ 2
                and clear(witness, victim)
                and clear(witness, attacker)
            then
                enemies[member] = enemies[member] or {}
                enemies[member][attacker] = true
            end
        end
    end
    function self:hasVisibleEnemy(id, actor, humans)
        for enemy in pairs(enemies[id] or {}) do
            local person = enemy:getModData().ProjectPeoplePersonId ~= nil
            if humans then
                for i = 0, humans:size() - 1 do
                    if humans:get(i) == enemy then
                        person = true
                        break
                    end
                end
            end
            if
                (not humans or person)
                and not enemy:isDead()
                and distance(actor, enemy) <= Policy.NOTICE_RADIUS ^ 2
                and clear(actor, enemy)
            then
                return true
            end
        end
        return false
    end
    local function candidates(actor, id, zombies, humans)
        local result = {}
        local function add(target, kind, key)
            if target == actor or target:isDead() then
                return
            end
            local d = distance(actor, target)
            if d > Policy.NOTICE_RADIUS ^ 2 then
                return
            end
            local enemy = enemies[id] and enemies[id][target] or false
            result[#result + 1] = {
                id = key,
                actor = target,
                kind = kind,
                alive = true,
                distanceSquared = d,
                visible = clear(actor, target),
                enemy = enemy,
            }
        end
        for i = 0, zombies:size() - 1 do
            local target = zombies:get(i)
            local personId = target:getModData().ProjectPeoplePersonId
            add(target, personId and "npc" or "zombie", personId or "zombie:" .. target:getOnlineID())
        end
        for i = 0, humans:size() - 1 do
            local p = humans:get(i)
            add(p, "player", "player:" .. p:getOnlineID())
        end
        return result
    end
    function self:tick(id, binding, record, zombies, humans, now)
        assert(not isClient(), "combat_authority_only")
        local actor = binding.actor
        -- Hostile disposition is not permission to hurt a person. Only an
        -- observed attack creates an enemy; ordinary encounters can warn first.
        local perceived = candidates(actor, id, zombies, humans)
        local target = Policy.choose(perceived)
        local weaponProfile = target
            and Weapons.profile(actor, config.person and config.person(id), math.sqrt(target.distanceSquared))
        local reach = weaponProfile and weaponProfile.range or Policy.MELEE_REACH
        local strike = strikes[id]
        -- Zombies pre-empt even a committed swing against a person.
        if strike and (not target or strike.target ~= target.actor) then
            strikes[id] = nil
            record.attacking = false
            strike = nil
        end
        if not target or actor:isDead() then
            approaches[id] = nil
            if record.combatActive then
                Body.order(record, nil, now)
            end
            record.combatActive = false
            record.retreating = false
            record.attacking = false
            strikes[id] = nil
            return false
        end
        record.combatActive = true
        record.activity = target.kind == "zombie" and "Defending against zombies" or "Confronting an attacker"
        record.attackX = target.actor:getX()
        record.attackY = target.actor:getY()
        record.attackRanged = weaponProfile and weaponProfile.ranged or false
        -- Keep room to finish a swing and recover. Repath only after a useful
        -- step, not every authority tick; blocked exits never teleport the body.
        local recovering = now < (cooldowns[id] or 0)
        if
            target.kind == "zombie"
            and target.distanceSquared < 2.2 ^ 2
            and (target.distanceSquared <= Policy.MELEE_REACH ^ 2 or strike or recovering)
        then
            if not record.retreating or record.mode ~= "move" or now - (record.started or 0) >= 1200 then
                local goal = Space.retreat(actor, target.actor, perceived)
                if goal then
                    Body.order(record, goal, now)
                    record.retreating = true
                else
                    record.retreating = false
                    if record.mode ~= "wait" then
                        Body.order(record, nil, now)
                    end
                end
            end
        elseif record.retreating then
            record.retreating = false
            Body.order(record, nil, now)
        end
        if strike then
            if now < strike.contactAt then
                return true
            end
            strikes[id] = nil
            record.attacking = false
            cooldowns[id] = now + strike.rules.cooldownMs
            if distance(actor, target.actor) > strike.reach ^ 2 or not clear(actor, target.actor) then
                record.combatResult = "Missed: target moved"
                return true
            end
            local hit, damage = Policy.contact(target.kind, config.random(), actor:getHealth())
            local used = strike.weapon
            if used then
                if Weapons.weapon(actor) ~= used then
                    record.combatResult = "Weapon changed"
                    return true
                end
                if strike.profile.ranged then
                    if not Weapons.clearLane(actor, target.actor, perceived) then
                        record.combatResult = "Holding fire: person in the way"
                        return true
                    end
                    if not Weapons.discharge(actor, used) then
                        record.combatResult = "Weapon not ready"
                        return true
                    end
                end
                hit = config.random() < strike.profile.accuracy
                damage = hit and strike.profile.damage or 0
                -- Retain the established player advantage and bounded damage.
                if target.kind == "player" then
                    damage = math.min(0.1, damage * 0.2)
                end
                Weapons.wear(used, config.random())
            end
            record.combatResult = hit and "Strike landed" or "Missed"
            if hit then
                fists = fists or instanceItem "Base.BareHands"
                assert(fists and instanceof(fists, "HandWeapon"), "native_unarmed_weapon_required")
                -- Avoid the vanilla player-only Strength XP cast for NPC fists.
                fists:setKnockBackOnNoDeath(false)
                config.hit(actor, target.actor, used or fists, damage, target.kind)
            end
            return true
        end
        if target.distanceSquared > reach ^ 2 then
            if record.retreating or recovering then
                return true
            end
            if record.mode ~= "move" or now - record.started >= 1500 then
                local reserved = {}
                for other, entry in pairs(approaches) do
                    if other ~= id and entry.target == target.actor and now - entry.at < 2000 then
                        reserved[#reserved + 1] = entry.goal
                    end
                end
                local goal = Space.approach(actor, target.actor, perceived, reserved)
                approaches[id] = goal and { target = target.actor, goal = goal, at = now } or nil
                if goal then
                    Body.order(record, goal, now)
                elseif record.mode ~= "wait" then
                    Body.order(record, nil, now)
                end
            end
            return true
        end
        approaches[id] = nil
        if not record.retreating and record.mode ~= "wait" then
            Body.order(record, nil, now)
        end
        if now < (cooldowns[id] or 0) then
            return true
        end
        local rules = Policy.matchup(target.kind)
        if weaponProfile then
            rules.windupMs = math.max(rules.windupMs, weaponProfile.windupMs)
            rules.cooldownMs = math.max(rules.cooldownMs, weaponProfile.cooldownMs)
            if weaponProfile.ranged then
                if not Weapons.clearLane(actor, target.actor, perceived) then
                    record.combatResult = "Holding fire: person in the way"
                    return true
                end
                local ready, reason = Weapons.ammunition(weaponProfile.weapon)
                if not ready then
                    if Weapons.chamber(weaponProfile.weapon) then
                        record.combatResult = "Chambering a round"
                        cooldowns[id] = now + 1000
                    elseif Weapons.reload(actor, weaponProfile.weapon) then
                        record.combatResult = "Reloading"
                        cooldowns[id] = now + math.max(2000, 5000 - weaponProfile.skill * 250)
                    else
                        record.combatResult = reason
                        cooldowns[id] = now + 2000
                    end
                    return true
                end
            end
        end
        record.attackEpoch = (record.attackEpoch or 0) + 1
        record.attacking = true
        record.attackX = target.actor:getX()
        record.attackY = target.actor:getY()
        record.attackDuration = rules.windupMs
        strikes[id] = {
            target = target.actor,
            contactAt = now + rules.windupMs,
            rules = rules,
            reach = reach,
            weapon = weaponProfile and weaponProfile.weapon,
            profile = weaponProfile,
        }
        return true
    end
    return self
end
return Combat
