-- Single-player succession using the original native actor and trusted authority mappings.
local DevTools = require "ProjectPeople/DevTools"
local Core = require "ProjectPeople/Core"
local State = require "ProjectPeople/CharacterState"
local Native = { VERSION = 1, PROVEN = false }
local panels = {
    "playerInventory",
    "lootInventory",
    "playerHotbar",
    "buttonPrompt",
    "equipped",
    "characterInfo",
    "backButtonWheel",
    "mechanicsUI",
    "vehicleDashboard",
    "radialMenu",
    "miniMap",
    "sleepingUI",
    "zoneUI",
    "contextMenu",
}
local objects = {
    inventory = "getInventory",
    body = "getBodyDamage",
    xp = "getXp",
    stats = "getStats",
    visual = "getHumanVisual",
    descriptor = "getDescriptor",
    traits = "getCharacterTraits",
    nutrition = "getNutrition",
}

local function need(value, why)
    if not value then
        error(why)
    end
end

local function isText(value)
    return DevTools.isText(value, 128)
end
local isFinite = DevTools.isFinite
local same = DevTools.same

local function fail(code, detail, id)
    return {
        ok = false,
        code = code,
        detail = detail,
        operationId = id,
        proven = false,
        durable = false,
        authorityCommitted = false,
    }
end

local function environment()
    need(not isClient() and not isServer(), "singleplayer_only")
    need(getCore():getVersionNumber() == "42.21", "uninspected_build")
    need(getCell() and getCell():isSafeToAdd(), "safe_native_boundary_required")
    for slot = 1, 3 do
        need(getSpecificPlayer(slot) == nil, "single_local_controller_required")
    end
end

local function observeCharacter(actor, id, revision)
    local result = State.capture(actor, id, revision)
    need(result.ok, "native_character_observation_incomplete")
    local s = result.snapshot
    local hours = actor:getHoursSurvived()
    need(isFinite(hours) and hours >= 0, "native_survival_clock_unavailable")
    return s,
        {
            nativeHealth = s.native.health,
            descriptor = s.descriptor,
            appearance = s.appearance,
            traits = s.traits,
            skills = s.skills,
            totalXp = s.totalXp,
            condition = s.condition,
            stats = s.stats,
            nutrition = s.nutrition,
            hoursSurvived = hours,
        }
end
-- Exposes actual observations for the authority's initial person record too.

function Native.observeCharacter(actor, id, revision)
    local ok, snapshot, character = pcall(observeCharacter, actor, id, revision)
    return ok and { ok = true, snapshot = snapshot, character = character, proven = false }
        or fail("native_character_observation_failed", tostring(snapshot))
end

local function refs(actor)
    local result = { actor = actor }
    for key, method in pairs(objects) do
        result[key] = actor[method](actor)
        need(result[key], "native_state_owner_missing:" .. key)
    end
    return result
end

local function inventory(world, resolved, actor, personId)
    need(resolved.complete == true and type(resolved.owners) == "table", "complete_native_owner_mapping_required")
    for owner in pairs(world.inventories) do
        need(resolved.owners[owner], "known_inventory_unresolved:" .. owner)
    end
    local owner = "person:" .. personId
    need(resolved.owners[owner] == actor:getInventory(), "candidate_inventory_mapping_mismatch")
    local seenContainers, seenItems, entries, items, itemOwners = {}, {}, {}, {}, {}
    local total = 0
    local function visit(container, current, depth)
        need(
            container and instanceof(container, "ItemContainer") and not seenContainers[container] and depth <= 16,
            "native_container_alias_or_depth"
        )
        seenContainers[container] = true
        local list = container:getItems()
        need(list:size() <= 4096, "inventory_size_unsupported")
        for index = 0, list:size() - 1 do
            local item = list:get(index)
            need(
                item and instanceof(item, "InventoryItem") and item:getContainer() == container,
                "native_item_owner_mismatch"
            )
            local number = item:getID()
            need(
                isFinite(number) and number == math.floor(number) and number >= -2147483648 and number <= 2147483647,
                "native_item_id_invalid"
            )
            local id = "native:" .. string.format("%.0f", number)
            need(not entries[id] and not seenItems[item], "duplicate_native_item_identity")
            seenItems[item] = true
            total = total + 1
            need(total <= 16384, "native_owner_domain_too_large")
            local data = {
                fullType = item:getFullType(),
                condition = item:getCondition(),
                count = item:getCount(),
                weight = item:getUnequippedWeight(),
            }
            need(
                isText(data.fullType)
                    and isFinite(data.condition)
                    and isFinite(data.count)
                    and data.count > 0
                    and isFinite(data.weight)
                    and data.weight >= 0,
                "native_item_data_unavailable"
            )
            entries[id] = { item = item, container = container, owner = current, data = data }
            if current == owner then
                items[id] = data
                itemOwners[id] = owner
            end
            if instanceof(item, "InventoryContainer") then
                visit(item:getInventory(), current, depth + 1)
            end
        end
    end
    local ownerCount = 0
    for current, container in pairs(resolved.owners) do
        ownerCount = ownerCount + 1
        need(ownerCount <= 128, "native_owner_domain_too_large")
        visit(container, current, 0)
    end
    for id, item in pairs(world.items) do
        if item.owner == owner then
            need(entries[id] and entries[id].owner == owner and not item.lock, "candidate_item_unresolved:" .. id)
        end
    end
    return { entries = entries, items = items, itemOwners = itemOwners }
end

local function context(self, system, proof)
    local a = self.config.authority()
    need(
        type(a) == "table" and a.authority == true and isText(a.issuer) and isText(a.actorId),
        "trusted_authority_required"
    )
    local time = getGameTime():getWorldAgeHours()
    need(isFinite(time) and time >= 0, "native_time_unavailable")
    if proof then
        proof.validated = true
    end
    return {
        authority = true,
        issuer = system and "native_succession_authority" or a.issuer,
        actorId = a.actorId,
        system = system == true,
        gameTime = time,
        evidence = proof,
        capabilities = { succession = true, faithfulState = true, sameNativeSuccession = true },
    },
        a
end

local function apply(self, world, system, kind, fields, proof)
    local ctx = context(self, system, proof)
    return Core.apply(world, Core.command(world, ctx.issuer, kind, fields), ctx)
end

local function publish(self, staged, revision)
    need(self.world.revision == revision, "authority_changed_during_callback")
    for key in pairs(self.world) do
        self.world[key] = nil
    end
    for key, value in pairs(staged) do
        self.world[key] = value
    end
end

local function persist(self, world, stage, id)
    local ok, ack = pcall(self.config.persist, Core.snapshot(world), stage, id)
    if
        not ok
        or type(ack) ~= "table"
        or ack.ok ~= true
        or not isText(ack.token)
        or (ack.level ~= "file_readback" and ack.level ~= "durable_storage")
        or ack.stage ~= stage
        or ack.worldId ~= world.worldId
        or ack.timelineId ~= world.timelineId
        or ack.revision ~= world.revision
    then
        local rejected =
            fail("journal_persistence_unconfirmed", not ok and tostring(ack) or "explicit_matching_ack_required", id)
        if ok and type(ack) == "table" then
            rejected.persistenceCode, rejected.persistenceDetail = ack.code, ack.detail
        end
        return rejected
    end
    return { ok = true, level = ack.level, token = ack.token }
end

local function unchanged(session, actor, snapshot, observed)
    need(actor == session.actor, "original_actor_replaced")
    for key, method in pairs(objects) do
        need(actor[method](actor) == session.refs[key], "original_native_owner_replaced:" .. key)
    end
    need(same(session.before.inventory, snapshot.inventory), "native_inventory_manifest_changed")
    need(
        same(session.before.descriptor, snapshot.descriptor)
            and same(session.before.appearance, snapshot.appearance)
            and same(session.before.traits, snapshot.traits)
            and same(session.before.skills, snapshot.skills)
            and session.before.totalXp == snapshot.totalXp,
        "native_identity_or_skills_changed"
    )
    need(same(session.inventory.items, observed.items), "native_item_data_or_count_changed")
    for id in pairs(session.inventory.items) do
        local before, after = session.inventory.entries[id], observed.entries[id]
        need(
            after and after.item == before.item and after.container == before.container and after.owner == before.owner,
            "original_item_or_ownership_changed:" .. id
        )
    end
    need(actor:getHoursSurvived() >= session.hours, "native_survival_clock_reset")
    if session.before.condition.infected then
        need(
            snapshot.condition.infected
                and snapshot.condition.infectionTime == session.before.condition.infectionTime
                and snapshot.condition.infectionMortalityDuration
                    == session.before.condition.infectionMortalityDuration,
            "native_infection_reset"
        )
    end
end

local function boundary(self, id, session, afterDispatch)
    environment()
    local _, a = context(self, false)
    local p = self.world.people[id]
    need(p and p.life ~= "dead" and not p.protectionHold, "living_unheld_candidate_required")
    local resolved = self.config.resolve(id)
    need(
        type(resolved) == "table"
            and resolved.personRevision == p.revision
            and resolved.dueEventsResolved == true
            and resolved.inventoryReconciled == true,
        "resolved_current_candidate_boundary_required"
    )
    local actor = resolved.actor
    need(
        actor
            and instanceof(actor, "IsoPlayer")
            and not actor:isDead()
            and not actor:isGodMod()
            and not actor:isInvulnerable()
            and not actor:isInvincible(),
        "unmodified_living_native_candidate_required"
    )
    need(
        resolved.actorId == p.representation.actorId
            and isText(resolved.actorId)
            and p.representation.mode == "physical"
            and actor:getModData().ProjectPeoplePersonId == id,
        "native_person_identity_mismatch"
    )
    need(
        actor:getVehicle() == nil
            and actor:getCharacterActions():isEmpty()
            and not actor:isGrappling()
            and not actor:isBeingGrappled()
            and not actor:isPerformingAttackAnimation(),
        "native_activity_requires_resolution"
    )
    local deceased = session and session.deceased or a.character
    local death = self.deaths[deceased]
    need(
        deceased and death and death.count == 1 and deceased:isDead() and deceased:getHealth() <= 0,
        "observed_native_player_death_required"
    )
    local deadId = session and session.deceasedId or a.actorId
    local dead = self.world.people[deadId]
    need(
        dead
            and dead.life == "dead"
            and dead.death
            and dead.death.confirmed
            and dead.controller.id == a.issuer
            and self.world.controllers[a.issuer] == deadId,
        "authority_death_or_controller_mismatch"
    )
    if session then
        need(
            a.issuer == session.issuer and a.actorId == session.deceasedId and a.character == deceased,
            "succession_authority_changed"
        )
        need(p.revision == self.world.operations[session.id].personRevision, "reserved_person_changed")
    end
    if not afterDispatch then
        need(getSpecificPlayer(0) == deceased and IsoPlayer.getInstance() == deceased, "deceased_controller_changed")
        need(actor:isNpc() and not actor:isLocalPlayer(), "uncontrolled_native_survivor_required")
        need(
            actor:getCurrentSquare()
                and getCell():getObjectList():contains(actor)
                and not getCell():getAddList():contains(actor)
                and not getCell():getRemoveList():contains(actor),
            "stable_native_membership_required"
        )
    end
    local snapshot, character = observeCharacter(actor, id, p.revision)
    local observed = inventory(self.world, resolved, actor, id)
    if session then
        unchanged(session, actor, snapshot, observed)
    end
    return {
        actor = actor,
        actorId = resolved.actorId,
        snapshot = snapshot,
        character = character,
        inventory = observed,
        authority = a,
        deceased = deceased,
        death = death,
    }
end

local function unresolved(self, session, code, detail)
    local result = fail(code, detail, session.id)
    local ok, reconciliation = pcall(function()
        local r = apply(
            self,
            self.world,
            true,
            "succession.reconcile",
            { operationId = session.id },
            { kind = "succession_result", operationId = session.id, outcome = "unknown" }
        )
        if r.ok then
            r.persistence = persist(self, self.world, "unresolved", session.id)
        end
        return r
    end)
    result.reconciliation = ok and reconciliation or { ok = false, detail = tostring(reconciliation) }
    result.nativeError = session.nativeError
    return result -- Never release reservation/controller locks here.
end

local function guarded(self, fn)
    if self.closed then
        return fail "succession_adapter_closed"
    end
    if self.busy then
        return fail "succession_adapter_busy"
    end
    self.busy = true
    local ok, result = pcall(fn)
    self.busy = false
    return ok and result or fail("native_succession_precondition_or_observation_failed", tostring(result))
end

function Native.new(world, config)
    if
        type(world) ~= "table"
        or world.schema ~= Core.VERSION
        or type(config) ~= "table"
        or type(config.authority) ~= "function"
        or type(config.resolve) ~= "function"
        or type(config.persist) ~= "function"
    then
        return nil, "authority_resolver_and_persistence_required"
    end
    local self = { world = world, config = config, sessions = {}, deaths = {}, busy = false, count = 0 }
    function self:watchPlayer()
        return guarded(self, function()
            environment()
            local actor = getSpecificPlayer(0)
            need(actor and not actor:isDead() and actor:isLocalPlayer(), "living_local_player_required")
            local data = getPlayerData(0)
            need(data and data.playerInventory and data.lootInventory, "native_player_ui_required")
            local previous = {}
            for _, name in ipairs(panels) do
                if data[name] then
                    previous[#previous + 1] = data[name]
                end
            end
            self.watched = { actor = actor, panels = previous }
            return { ok = true, code = "native_death_observer_armed" }
        end)
    end
    local function onDeath(actor)
        local watched = self.watched
        if watched and actor == watched.actor then
            local record = self.deaths[actor] or { count = 0, panels = watched.panels }
            record.count = record.count + 1
            self.deaths[actor] = record
        end
    end
    local function onCreate(index, actor)
        if index ~= 0 then
            return
        end
        for _, session in pairs(self.sessions) do
            if session.nativeStarted and session.actor == actor then
                session.createCount = session.createCount + 1
                session.createdAt = getTimestampMs()
            end
        end
    end
    local function onTick()
        -- Player panels can be created after startup (maps, mechanics, etc.).
        -- Keep the last living player's actual panel set current before death.
        local actor = getSpecificPlayer(0)
        if actor and not actor:isDead() and not self.busy then
            self:watchPlayer()
        end
    end
    Events.OnPlayerDeath.Add(onDeath)
    Events.OnCreatePlayer.Add(onCreate)
    Events.OnTick.Add(onTick)
    self:watchPlayer() -- If native UI is not ready, authority must explicitly retry while alive.
    function self:prepare(personId)
        return guarded(self, function()
            need(isText(personId) and self.count < 128, "bounded_person_request_required")
            local current = boundary(self, personId)
            local staged, revision = Core.snapshot(self.world), self.world.revision
            local entries = {}
            for id, data in pairs(current.inventory.items) do
                entries[#entries + 1] = { id = id, data = data }
            end
            local scanned = apply(
                self,
                staged,
                true,
                "inventory.observe",
                { owner = "person:" .. personId, items = entries },
                { kind = "inventory_scan", owner = "person:" .. personId, uniqueItems = true }
            )
            if not scanned.ok then
                return scanned
            end
            local result = apply(self, staged, false, "succession.reserve", { personId = personId }, {
                kind = "succession_boundary",
                personId = personId,
                dueEventsResolved = true,
                inventoryReconciled = true,
                candidateAlive = true,
                personRevision = staged.people[personId].revision,
            })
            if not result.ok then
                return result
            end
            local session = {
                id = result.operationId,
                personId = personId,
                actor = current.actor,
                actorId = current.actorId,
                deceased = current.deceased,
                deceasedId = current.authority.actorId,
                issuer = current.authority.issuer,
                refs = refs(current.actor),
                before = current.snapshot,
                inventory = current.inventory,
                hours = current.character.hoursSurvived,
                panels = current.death.panels,
                createCount = 0,
                nativeStarted = false,
            }
            publish(self, staged, revision)
            self.sessions[session.id] = session
            self.count = self.count + 1
            local ack = persist(self, self.world, "prepared", session.id)
            if not ack.ok then
                return ack
            end
            need(self.world.revision == result.revision, "authority_changed_during_callback")
            session.preparedPersisted = true
            result.observation, result.persistenceLevel, result.proven =
                Core.snapshot(current.snapshot), ack.level, false
            return result
        end)
    end
    function self:dispatch(id)
        return guarded(self, function()
            local session, op = self.sessions[id], self.world.operations[id]
            need(
                session
                    and op
                    and op.kind == "succession"
                    and op.state == "prepared"
                    and session.preparedPersisted
                    and not session.nativeStarted,
                "persisted_preparation_required_no_replay"
            )
            boundary(self, op.personId, session, false)
            local result = apply(self, self.world, true, "operation.dispatch", { operationId = id })
            if not result.ok then
                return result
            end
            local revision = self.world.revision
            local ack = persist(self, self.world, "dispatched", id)
            if not ack.ok then
                return ack
            end
            need(self.world.revision == revision, "authority_changed_during_callback")
            boundary(self, op.personId, session, false)
            session.nativeStarted, session.startedAt = true, getTimestampMs()
            local ok, err = pcall(function()
                need(getPlayerData(0) == nil, "vanilla_death_ui_teardown_unconfirmed")
                for _, panel in ipairs(session.panels) do
                    panel:setVisible(false)
                    panel:removeFromUIManager()
                end
                if ISPostDeathUI and ISPostDeathUI.instance[0] then
                    local panel = ISPostDeathUI.instance[0]
                    panel:setVisible(false)
                    panel:removeFromUIManager()
                    ISPostDeathUI.instance[0] = nil
                end
                session.actor:setNpc(false)
                setPlayerMouse(session.actor)
            end)
            if not ok then
                session.nativeError = tostring(err)
                return unresolved(self, session, "native_succession_outcome_unknown", tostring(err))
            end
            return {
                ok = true,
                code = "native_takeover_queued",
                operationId = id,
                pending = true,
                authorityCommitted = false,
                persistenceLevel = ack.level,
                proven = false,
                durable = false,
            }
        end)
    end
    local function inspect(id)
        local session, op = self.sessions[id], self.world.operations[id]
        need(session and op and op.kind == "succession", "session_native_identity_required")
        need(session.nativeStarted, "native_dispatch_not_started")
        local observed = boundary(self, op.personId, session, true)
        local actor = observed.actor
        local player = getSpecificPlayer(0)
        need(player == nil or player == session.deceased or player == actor, "unexpected_native_controller")
        need(session.createCount <= 1, "duplicate_native_create_callback")
        local ready = player == actor
            and IsoPlayer.getInstance() == actor
            and actor:isLocalPlayer()
            and not actor:isNpc()
            and IsoCamera.getCameraCharacter() == actor
            and session.createCount == 1
            and getTimestampMs() - session.createdAt >= 250
        local occurrences, list = 0, getCell():getObjectListForLua()
        for index = 0, list:size() - 1 do
            if list:get(index) == actor then
                occurrences = occurrences + 1
            end
        end
        need(occurrences <= 1, "duplicate_native_actor")
        ready = ready and occurrences == 1 and actor:getCurrentSquare() ~= nil
        local data = getPlayerData(0)
        ready = ready
            and data
            and data.playerInventory
            and data.lootInventory
            and data.playerInventory.inventoryPane.inventory == session.refs.inventory
        for _, panel in ipairs(session.panels) do
            ready = ready and not panel:isVisible() and not UIManager.getUI():contains(panel.javaObject)
        end
        ready = ready and (not ISPostDeathUI or ISPostDeathUI.instance[0] == nil)
        if not ready then
            need(getTimestampMs() - session.startedAt < 20000, "native_controller_or_ui_timeout")
            return {
                ok = true,
                code = "native_takeover_pending",
                pending = true,
                operationId = id,
                observation = observed.snapshot,
                authorityCommitted = false,
                proven = false,
            }
        end
        local proof = {
            kind = "succession_result",
            operationId = id,
            outcome = "applied",
            personId = op.personId,
            controllerId = op.controllerId,
            actorId = session.actorId,
            faithful = true,
            soleController = true,
            soleInventory = true,
            character = observed.character,
            items = observed.inventory.items,
            itemOwners = observed.inventory.itemOwners,
            continuity = {
                kind = "same_native_actor",
                personRevision = op.personRevision,
                confirmedNativeDeath = true,
                currentCharacterObserved = true,
                originalActor = true,
                originalBody = true,
                originalXp = true,
                originalVisual = true,
                originalInventory = true,
                originalItems = true,
                originalDescriptor = true,
                originalStats = true,
                originalTraits = true,
                originalNutrition = true,
            },
        }
        return {
            ok = true,
            code = "original_native_person_observed",
            operationId = id,
            evidence = proof,
            observation = observed.snapshot,
            authorityCommitted = false,
            proven = false,
            durable = false,
        }
    end
    function self:observe(id)
        return guarded(self, function()
            local ok, result = pcall(inspect, id)
            if ok then
                return result
            end
            local session = self.sessions[id]
            return session
                    and session.nativeStarted
                    and unresolved(self, session, "native_succession_observation_unresolved", tostring(result))
                or fail("session_native_identity_required", tostring(result), id)
        end)
    end
    function self:reconcile(id)
        return guarded(self, function()
            local op, session = self.world.operations[id], self.sessions[id]
            if op and op.terminal then
                return { ok = true, code = "operation_already_resolved", operationId = id, authorityCommitted = true }
            end
            need(
                session and not session.terminalPersistenceAttempted,
                "session_or_terminal_persistence_requires_recovery"
            )
            local ok, observed = pcall(inspect, id)
            if not ok then
                return unresolved(self, session, "native_succession_observation_unresolved", tostring(observed))
            end
            if observed.pending then
                return observed
            end
            local staged, revision = Core.snapshot(self.world), self.world.revision
            local result = apply(self, staged, true, "succession.reconcile", { operationId = id }, observed.evidence)
            if not result.ok then
                result.observation = observed.observation
                return result
            end
            session.terminalPersistenceAttempted = true
            local ack = persist(self, staged, "reconciled", id)
            if not ack.ok then
                return ack
            end -- Live authority remains locked until recovery.
            publish(self, staged, revision)
            result.operationId, result.persistenceLevel, result.authorityCommitted = id, ack.level, true
            result.observation, result.evidence, result.proven, result.durable =
                observed.observation, observed.evidence, false, false
            -- The continuing person is now the next possible native death witness.
            local data = getPlayerData(0)
            local currentPanels = {}
            for _, name in ipairs(panels) do
                if data[name] then
                    currentPanels[#currentPanels + 1] = data[name]
                end
            end
            self.watched = { actor = session.actor, panels = currentPanels }
            return result
        end)
    end
    function self:close()
        -- Unsubscribe only. Persisted reservations and uncertain native effects
        -- remain owned by the authority; closing never means cancellation.
        self.closed = true
        Events.OnPlayerDeath.Remove(onDeath)
        Events.OnCreatePlayer.Remove(onCreate)
        Events.OnTick.Remove(onTick)
        return { ok = true, code = "observer_closed_locks_unchanged" }
    end
    return self
end
return Native
