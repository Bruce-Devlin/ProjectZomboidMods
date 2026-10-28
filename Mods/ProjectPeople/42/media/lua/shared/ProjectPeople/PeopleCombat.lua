-- Server-owned target choice, telegraphed strikes and native damage. No client
-- success reports. The household coordinator calls tick and publishes records.
local Policy = require "ProjectPeople/CombatPolicy"
local Body = require "ProjectPeople/PeopleBody"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Weapons = require "ProjectPeople/PeopleWeapons"
local SocialGroup = require "ProjectPeople/Behaviour/Groups"
local Settings = require "ProjectPeople/Pathing/Settings"
local Party = require "ProjectPeople/Party"
local Combat = {}

function Combat.applyDamage(actor, target, weapon, damage, kind, action, knockdown)
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
                target:Hit(weapon, actor, damage, action == "shove", 1, false)
            end)
            weapon:setKnockBackOnNoDeath(knockback)
            if not ok then
                error(err)
            end
        else
            target:Hit(weapon, actor, damage, action == "shove", 1, false)
        end
        if kind == "zombie" and not target:isDead() then
            local dx, dy = target:getX() - actor:getX(), target:getY() - actor:getY()
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0.001 then
                target:getHitDir():set(dx / length, dy / length)
            end
            target:setHitForce(action == "shove" and 0.8 or 0.35)
            target:setStaggerBack(action ~= "stomp")
            if knockdown then
                target:setKnockedDown(true)
            end
            target:setHitReaction(action == "stomp" and "Floor" or "HeadLeft")
            target:reportEvent "wasHit"
        end
    end
end

function Combat.grounded(target)
    return target.isOnFloor and target:isOnFloor() or target.isCrawling and target:isCrawling() or false
end

function Combat.action(target, profile)
    if target and target.kind == "zombie" then
        if Combat.grounded(target.actor) then
            return "stomp"
        end
        local minimum = profile and profile.minRange or 0.9
        if target.distanceSquared < minimum ^ 2 then
            return "shove"
        end
    end
    return "swing"
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
    local function allied(id, actor)
        local other = actor and actor:getModData().ProjectPeoplePersonId
        if other and config.person then
            return Party.alliedPeople(config.person(id), config.person(other))
        end
        return other and config.world and Party.allied(config.world(), id, other) or false
    end
    function self:isEnemy(id, actor)
        return not allied(id, actor) and enemies[id] ~= nil and enemies[id][actor] == true
    end
    function self:interrupt(id, record)
        strikes[id] = nil
        approaches[id] = nil
        record.combatActive = false
        record.attacking = false
        record.attackAction = nil
        record.retreating = false
    end
    function self:provoked(victim, attacker)
        if not victim or not attacker or victim == attacker then
            return
        end
        local id = victim:getModData().ProjectPeoplePersonId
        if id and allied(id, attacker) then
            return
        end
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
                and not allied(member, attacker)
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
                not allied(id, enemy)
                and (not humans or person)
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
            local enemy = self:isEnemy(id, target)
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
        if record.homeGuard then
            local localThreats = {}
            for _, candidate in ipairs(perceived) do
                local target = candidate.actor
                if
                    math.abs(target:getZ() - record.homeGuardZ) < 0.2
                    and (target:getX() - record.homeGuardX) ^ 2 + (target:getY() - record.homeGuardY) ^ 2 <= 100
                then
                    localThreats[#localThreats + 1] = candidate
                end
            end
            perceived = localThreats
        end
        if record.companionCombat then
            local nearby = {}
            for _, candidate in ipairs(perceived) do
                local target = candidate.actor
                if
                    candidate.kind == "zombie"
                    and math.abs(target:getZ() - record.leaderZ) < 0.2
                    and (target:getX() - record.leaderX) ^ 2 + (target:getY() - record.leaderY) ^ 2 <= Settings.follow.assistLeash ^ 2
                then
                    nearby[#nearby + 1] = candidate
                end
            end
            perceived = nearby
        end
        local target = Policy.choose(perceived)
        local weaponProfile = target
            and Weapons.profile(actor, config.person and config.person(id), math.sqrt(target.distanceSquared))
        local action = Combat.action(target, weaponProfile)
        local shoveReach = math.max(0.9, weaponProfile and weaponProfile.minRange or 0.9)
        if action ~= "swing" then
            weaponProfile = nil
        end
        local reach = action == "shove" and shoveReach or weaponProfile and weaponProfile.range or Policy.MELEE_REACH
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
            and not strike
            and (action == "swing" or action == "shove" and recovering)
            and target.distanceSquared < 2.2 ^ 2
            and (target.distanceSquared <= Policy.MELEE_REACH ^ 2 or recovering)
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
            if (strike.action == "stomp") ~= Combat.grounded(target.actor) and target.kind == "zombie" then
                record.combatResult = "Target changed stance"
                return true
            end
            local hit, damage = Policy.contact(target.kind, config.random(), actor:getHealth())
            local used = strike.weapon
            if used then
                if target.kind == "zombie" and distance(actor, target.actor) < strike.profile.minRange ^ 2 then
                    record.combatResult = "Crowded: making room"
                    cooldowns[id] = now + 150
                    return true
                end
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
            if strike.action == "shove" then
                damage = 0
            end
            record.combatResult = hit
                    and (strike.action == "shove" and "Shoved zombie" or strike.action == "stomp" and "Stomp landed" or "Strike landed")
                or "Missed"
            if hit then
                fists = fists or instanceItem "Base.BareHands"
                assert(fists and instanceof(fists, "HandWeapon"), "native_unarmed_weapon_required")
                -- Avoid the vanilla player-only Strength XP cast for NPC fists.
                fists:setKnockBackOnNoDeath(false)
                config.hit(
                    actor,
                    target.actor,
                    used or fists,
                    damage,
                    target.kind,
                    strike.action,
                    strike.action == "shove" and config.random() < 0.3
                )
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
                local goal = Space.approach(
                    actor,
                    target.actor,
                    perceived,
                    reserved,
                    weaponProfile and math.max(0.8, reach * 0.85)
                )
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
        -- Finish the committed strike before making space. Retreating through
        -- its whole wind-up can move the attacker outside its own weapon reach
        -- on every swing, even against a stationary zombie.
        if record.retreating then
            record.retreating = false
            Body.order(record, nil, now)
        end
        local rules = Policy.matchup(target.kind)
        if action == "shove" then
            rules.windupMs, rules.cooldownMs = 350, 1000
        elseif action == "stomp" then
            rules.windupMs, rules.cooldownMs = 650, 1200
        end
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
        record.attackAction = action
        record.attackX = target.actor:getX()
        record.attackY = target.actor:getY()
        record.attackDuration = rules.windupMs
        strikes[id] = {
            target = target.actor,
            action = action,
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
