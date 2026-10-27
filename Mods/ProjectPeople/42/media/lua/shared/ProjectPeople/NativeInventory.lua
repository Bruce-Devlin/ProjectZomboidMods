-- Transfers original native items using trusted ownership, authority and persistence callbacks.
local DevTools = require "ProjectPeople/DevTools"
local Core = require "ProjectPeople/Core"
ProjectPeople = ProjectPeople or {}
local Native = { VERSION = 1, PROVEN = false }
ProjectPeople.NativeInventory = Native
local supported = { ["Base.Bandage"] = true, ["Base.RippedSheets"] = true }

local function fail(code, detail, operationId)
    return {
        ok = false,
        code = code,
        detail = detail,
        operationId = operationId,
        proven = false,
        durable = false,
    }
end
local isFinite = DevTools.isFinite

local function isText(value)
    return DevTools.isText(value, 128)
end
local same = DevTools.same

local function need(value, code)
    if not value then
        error(code)
    end
end

function Native.itemId(item)
    local id = item:getID()
    need(
        isFinite(id) and id == math.floor(id) and id >= -2147483648 and id <= 2147483647,
        "native_item_identity_unavailable"
    )
    return "native:" .. string.format("%.0f", id)
end

local function itemData(item)
    local result = {
        fullType = item:getFullType(),
        condition = item:getCondition(),
        count = item:getCount(),
        weight = item:getUnequippedWeight(),
    }
    need(
        isText(result.fullType)
            and isFinite(result.condition)
            and isFinite(result.count)
            and isFinite(result.weight)
            and result.count > 0
            and result.weight >= 0,
        "native_item_data_unavailable"
    )
    return result
end

local function environment(self)
    need(
        not isClient() and (not isServer() or self.config.persistentZombieWorkers == true),
        "authority_worker_adapter_required"
    )
    local build = getCore():getVersionNumber()
    need(build == "42.21" or build == "42.21.0", "uninspected_game_build")
    need(getCell() and getCell():isSafeToAdd(), "safe_native_boundary_required")
end

local function authority(self)
    environment(self)
    local a = self.config.authority()
    need(
        type(a) == "table" and a.authority == true and isText(a.issuer) and (a.system == true or a.system == false),
        "explicit_authority_context_required"
    )
    local actor = a.character
    local zombie = self.config.persistentZombieWorkers == true
        and actor
        and instanceof(actor, "IsoZombie")
        and actor:isReanimatedPlayer()
        and actor:getModData().ProjectPeoplePersonId == a.actorId
    need(
        actor
            and (instanceof(actor, "IsoPlayer") or zombie)
            and not actor:isDead()
            and actor:getCurrentSquare()
            and getCell():getObjectList():contains(actor),
        "living_native_worker_required"
    )
    need(
        actor:getVehicle() == nil
            and actor:getCharacterActions():isEmpty()
            and not actor:isGrappling()
            and not actor:isBeingGrappled(),
        "worker_activity_requires_resolution"
    )
    if not a.system then
        need(isText(a.actorId) and actor:isLocalPlayer(), "authenticated_native_player_required")
        local person = self.world.people[a.actorId]
        need(
            person
                and person.controller.kind == "player"
                and person.controller.id == a.issuer
                and self.world.controllers[a.issuer] == a.actorId,
            "authenticated_character_required"
        )
    end
    a.gameTime = getGameTime():getWorldAgeHours()
    need(isFinite(a.gameTime) and a.gameTime >= 0, "native_game_time_required")
    return a
end

local function context(a, system, proof)
    return {
        authority = true,
        issuer = system and "native_inventory_authority" or a.issuer,
        actorId = a.actorId,
        system = system or a.system,
        gameTime = a.gameTime,
        evidence = proof,
    }
end

local function apply(world, a, system, kind, fields, proof)
    if proof then
        proof.validated = true
    end
    local ctx = context(a, system, proof)
    local command = Core.command(world, ctx.issuer, kind, fields)
    return Core.apply(world, command, ctx)
end

local function publish(world, staged, expectedRevision)
    need(world.revision == expectedRevision, "authority_world_changed_during_callback")
    for key in pairs(world) do
        world[key] = nil
    end
    for key, value in pairs(staged) do
        world[key] = value
    end
end

-- Acknowledgment is deliberately explicit and revision-bound. The module does
-- not invent durable success from a truthy callback or an in-memory snapshot.
-- Even accepted file read-back does not prove atomic native-world + journal save.

local function persist(self, snapshot, stage, operationId)
    local ok, ack = pcall(self.config.persist, Core.snapshot(snapshot), stage, operationId)
    if
        not ok
        or type(ack) ~= "table"
        or ack.ok ~= true
        or not isText(ack.token)
        or (ack.level ~= "file_readback" and ack.level ~= "durable_storage" and ack.level ~= "world_save_memory")
        or ack.worldId ~= snapshot.worldId
        or ack.timelineId ~= snapshot.timelineId
        or ack.revision ~= snapshot.revision
        or ack.stage ~= stage
    then
        return fail(
            "journal_persistence_unconfirmed",
            ok and "explicit_matching_ack_required" or tostring(ack),
            operationId
        )
    end
    return { ok = true, level = ack.level, token = ack.token }
end

local function registeredContainer(self, owner, container)
    need(isText(owner) and container and instanceof(container, "ItemContainer"), "real_named_container_required")
    need(
        container:getContainingItem() == nil
            and container:getVehiclePart() == nil
            and container:getType() ~= "floor"
            and container:getType() ~= "TradeUI",
        "unsupported_container_kind"
    )
    local parent = container:getParent()
    need(parent ~= nil, "native_container_parent_missing")
    local record = self.world.inventories[owner]
    if record and record.personId then
        local zombie = self.config.persistentZombieWorkers == true
            and parent
            and instanceof(parent, "IsoZombie")
            and parent:isReanimatedPlayer()
            and parent:getModData().ProjectPeoplePersonId == record.personId
        need(
            owner == "person:" .. record.personId
                and (instanceof(parent, "IsoPlayer") or zombie)
                and parent:getInventory() == container
                and not parent:isDead()
                and parent:getCurrentSquare()
                and getCell():getObjectList():contains(parent),
            "person_inventory_mapping_invalid"
        )
        return { container = container, parent = parent, square = parent:getCurrentSquare(), kind = "person" }
    end
    need(owner:match "^container:" and (not record or record.kind == "container"), "registered_storage_owner_required")
    need(
        not instanceof(parent, "IsoGameCharacter")
            and not instanceof(parent, "IsoDeadBody")
            and not instanceof(parent, "BaseVehicle")
            and not instanceof(parent, "IsoMannequin")
            and not instanceof(parent, "IsoFeedingTrough"),
        "unsupported_native_storage"
    )
    local square = parent:getSquare()
    need(
        square
            and square:getRoom()
            and square:getObjects():contains(parent)
            and parent:getContainerIndex(container) >= 0
            and container:isExistYet(),
        "existing_building_storage_required"
    )
    return { container = container, parent = parent, square = square, kind = "container" }
end

-- The resolver enumerates the COMPLETE authority-owned native owner domain.
-- Every known Core inventory must be represented. Unknown/unloaded ownership
-- cannot be certified by this bounded adapter and must remain unresolved.

local function scan(self)
    local resolved = self.config.resolve()
    need(
        type(resolved) == "table" and resolved.complete == true and type(resolved.owners) == "table",
        "complete_native_owner_resolver_required"
    )
    for owner in pairs(self.world.inventories) do
        need(resolved.owners[owner], "known_inventory_not_resolved:" .. owner)
    end
    local result = { owners = {}, entries = {}, byOwner = {}, count = 0 }
    local containers, handles = {}, {}
    local function visit(container, owner, depth, root)
        need(depth <= 16 and not containers[container], "aliased_or_cyclic_native_containers")
        containers[container] = true
        local list = container:getItems()
        need(list:size() <= 4096, "native_inventory_size_unsupported")
        for index = 0, list:size() - 1 do
            local item = list:get(index)
            need(
                item and instanceof(item, "InventoryItem") and item:getContainer() == container,
                "native_item_owner_mismatch"
            )
            local id, data = Native.itemId(item), itemData(item)
            need(not result.entries[id] and not handles[item], "duplicate_native_item_identity")
            handles[item], result.count = true, result.count + 1
            need(result.count <= 16384, "native_owner_domain_too_large")
            result.entries[id] = { item = item, owner = owner, container = container, root = root, data = data }
            result.byOwner[owner][#result.byOwner[owner] + 1] = { id = id, data = data }
            if instanceof(item, "InventoryContainer") then
                visit(item:getInventory(), owner, depth + 1, root)
            end
        end
    end
    local ownerCount = 0
    for owner, container in pairs(resolved.owners) do
        ownerCount = ownerCount + 1
        need(ownerCount <= 128, "native_owner_domain_too_large")
        result.owners[owner], result.byOwner[owner] = registeredContainer(self, owner, container), {}
        visit(container, owner, 0, container)
    end
    return result
end

local function inReach(actor, record)
    local current, square = actor:getCurrentSquare(), record.square
    if record.kind == "person" then
        return record.parent == actor
    end
    if
        math.floor(actor:getZ()) ~= square:getZ()
        or math.abs(current:getX() - square:getX()) > 1
        or math.abs(current:getY() - square:getY()) > 1
    then
        return false
    end
    if current ~= square and not current:canReachTo(square) then
        return false
    end
    if instanceof(record.parent, "IsoThumpable") and record.parent:isLockedToCharacter(actor) then
        return false
    end
    return true
end

local function allowedItem(entry)
    local item = entry.item
    need(
        supported[entry.data.fullType] == true and entry.data.count == 1 and entry.container == entry.root,
        "unsupported_transfer_item"
    )
    need(
        not instanceof(item, "Food")
            and not instanceof(item, "DrainableComboItem")
            and not instanceof(item, "InventoryContainer")
            and not instanceof(item, "Clothing")
            and not instanceof(item, "HandWeapon")
            and item:getWorldItem() == nil
            and not item:isEquipped()
            and item:getAttachedSlot() < 0
            and not item:isFavorite()
            and not item:getIsCraftingConsumed()
            and item:getJobDelta() == 0,
        "equipped_or_active_item_unsupported"
    )
end

local function access(observed, a, source, destination, ids)
    if a.actorId then
        local worker = observed.owners["person:" .. a.actorId]
        need(
            worker and worker.parent == a.character and worker.container == a.character:getInventory(),
            "worker_native_inventory_mapping_invalid"
        )
    end
    local src, dst = observed.owners[source], observed.owners[destination]
    need(
        src and dst and source ~= destination and src.container ~= dst.container,
        "distinct_native_containers_required"
    )
    need(inReach(a.character, src) and inReach(a.character, dst), "native_container_out_of_reach")
    local total, seen = 0, {}
    for _, id in ipairs(ids) do
        local entry = observed.entries[id]
        need(isText(id) and not seen[id] and entry and entry.owner == source, "native_source_item_missing_or_duplicate")
        seen[id] = true
        allowedItem(entry)
        need(
            src.container:isRemoveItemAllowed(entry.item) and dst.container:isItemAllowed(entry.item),
            "native_container_access_denied"
        )
        need(dst.container:hasRoomFor(a.character, entry.item), "native_destination_capacity_missing")
        total = total + entry.data.weight
    end
    need(dst.container:hasRoomFor(a.character, total), "native_destination_batch_capacity_missing")
    return src, dst
end

local function baselineUnchanged(before, after, op, transferred)
    for owner, record in pairs(before.owners) do
        need(after.owners[owner] and after.owners[owner].container == record.container, "resolved_owner_changed")
    end
    need(before.count == after.count, "native_item_count_changed")
    local moving = {}
    for _, id in ipairs(op.items) do
        moving[id] = true
    end
    for id, original in pairs(before.entries) do
        local actual = after.entries[id]
        need(
            actual and actual.item == original.item and same(actual.data, original.data),
            "native_item_identity_or_data_changed"
        )
        local expected = transferred and moving[id] and op.destination or original.owner
        need(actual.owner == expected, "native_item_owner_changed")
        if not moving[id] then
            need(actual.container == original.container, "unmoved_item_container_changed")
        end
    end
end

local function guarded(self, fn)
    if self.busy then
        return fail "native_inventory_adapter_busy"
    end
    self.busy = true
    local ok, result = pcall(fn)
    self.busy = false
    return ok and result or fail("native_inventory_precondition_or_observation_failed", tostring(result))
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
        return nil, "authority_resolver_and_persist_required"
    end
    local self = { world = world, config = config, sessions = {}, busy = false }

    function self:prepare(request)
        return guarded(self, function()
            need(
                type(request) == "table"
                    and isText(request.source)
                    and isText(request.destination)
                    and type(request.items) == "table"
                    and #request.items >= 1
                    and #request.items <= 32,
                "bounded_native_transfer_request_required"
            )
            local a, observed = authority(self), scan(self)
            local ids = Core.snapshot(request.items)
            for key in pairs(ids) do
                need(
                    type(key) == "number" and key >= 1 and key <= #ids and key == math.floor(key),
                    "dense_item_list_required"
                )
            end
            access(observed, a, request.source, request.destination, ids)
            for id, old in pairs(self.world.items) do
                local actual = observed.entries[id]
                need(actual and actual.owner == old.owner and not old.lock, "known_item_requires_reconciliation:" .. id)
            end
            local staged, revision = Core.snapshot(self.world), self.world.revision
            for owner, entries in pairs(observed.byOwner) do
                local result = apply(staged, a, true, "inventory.observe", {
                    owner = owner,
                    inventoryKind = observed.owners[owner].kind == "container" and "container" or nil,
                    items = entries,
                }, { kind = "inventory_scan", owner = owner, uniqueItems = true })
                if not result.ok then
                    return result
                end
            end
            local result = apply(staged, a, false, "transfer.prepare", {
                source = request.source,
                destination = request.destination,
                items = ids,
                missionId = request.missionId,
            }, {
                kind = "transfer_access",
                source = request.source,
                destination = request.destination,
                allowed = true,
            })
            if not result.ok then
                return result
            end
            publish(self.world, staged, revision)
            local session = {
                before = observed,
                issuer = a.issuer,
                actorId = a.actorId,
                actor = a.character,
                preparedPersisted = false,
                nativeStarted = false,
            }
            self.sessions[result.operationId] = session
            local ack = persist(self, self.world, "prepared", result.operationId)
            if not ack.ok then
                return ack
            end -- Published Core locks remain held.
            need(self.world.revision == result.revision, "authority_world_changed_during_callback")
            session.preparedPersisted = true
            result.persistenceLevel, result.proven, result.durable = ack.level, false, false
            return result
        end)
    end

    function self:dispatch(operationId)
        return guarded(self, function()
            local op, session = self.world.operations[operationId], self.sessions[operationId]
            if not op or op.kind ~= "transfer" or op.state ~= "prepared" then
                return fail("prepared_operation_required", nil, operationId)
            end
            if not session or not session.preparedPersisted or session.nativeStarted then
                return fail("session_preparation_or_persistence_unconfirmed", nil, operationId)
            end
            local a, observed = authority(self), scan(self)
            need(
                a.issuer == session.issuer and a.actorId == session.actorId and a.character == session.actor,
                "transfer_authority_changed"
            )
            baselineUnchanged(session.before, observed, op, false)
            local src, dst = access(observed, a, op.source, op.destination, op.items)
            local result = apply(self.world, a, true, "operation.dispatch", { operationId = operationId })
            if not result.ok then
                return result
            end
            local revision = self.world.revision
            local ack = persist(self, self.world, "dispatched", operationId)
            if not ack.ok then
                return ack
            end -- No native call, but never redispatch.
            need(self.world.revision == revision, "authority_world_changed_during_callback")
            -- Persistence callbacks may touch the world. Re-read actual access,
            -- originals and every known owner before the first native mutation.
            local current = scan(self)
            baselineUnchanged(session.before, current, op, false)
            local currentAuthority = authority(self)
            need(
                currentAuthority.issuer == session.issuer
                    and currentAuthority.actorId == session.actorId
                    and currentAuthority.character == session.actor,
                "transfer_authority_changed"
            )
            access(current, currentAuthority, op.source, op.destination, op.items)
            session.nativeStarted = true -- Before the first potentially partial call.
            local moved, detail = pcall(function()
                for _, id in ipairs(op.items) do
                    local item = current.entries[id].item
                    src.container:DoRemoveItem(item)
                    need(
                        not src.container:getItems():contains(item) and item:getContainer() == nil,
                        "native_remove_unconfirmed"
                    )
                    local returned = dst.container:AddItem(item)
                    need(
                        returned == item
                            and item:getContainer() == dst.container
                            and dst.container:getItems():contains(item),
                        "native_add_unconfirmed"
                    )
                    if isServer() then
                        -- NPC cargo is authoritative on the native zombie and
                        -- exposed through our filtered view. World storage and
                        -- playable characters use vanilla item packets.
                        if not instanceof(src.parent, "IsoZombie") then
                            sendRemoveItemFromContainer(src.container, item)
                        end
                        if not instanceof(dst.parent, "IsoZombie") then
                            sendAddItemToContainer(dst.container, item)
                        end
                    end
                end
                baselineUnchanged(session.before, scan(self), op, true)
            end)
            if not moved then
                local unresolved = apply(
                    self.world,
                    a,
                    true,
                    "transfer.reconcile",
                    { operationId = operationId },
                    { kind = "transfer_result", operationId = operationId, outcome = "unknown" }
                )
                if unresolved.ok then
                    persist(self, self.world, "unresolved", operationId)
                end
                return fail("native_transfer_outcome_unknown", tostring(detail), operationId)
            end
            return {
                ok = true,
                code = "original_items_moved_requires_reconciliation",
                operationId = operationId,
                persistenceLevel = ack.level,
                proven = false,
                durable = false,
                authorityCommitted = false,
            }
        end)
    end

    function self:reconcile(operationId)
        return guarded(self, function()
            local op = self.world.operations[operationId]
            if not op or op.kind ~= "transfer" then
                return fail("transfer_operation_required", nil, operationId)
            end
            if op.terminal then
                return {
                    ok = true,
                    code = "operation_already_resolved",
                    operationId = operationId,
                    proven = false,
                    durable = false,
                }
            end
            local a, observed = authority(self), scan(self)
            local session = self.sessions[operationId]
            -- Original object identity cannot be certified from a restarted Lua
            -- session. Recovery needs a separate persisted native-identity proof.
            if not session and not self.config.persistentZombieWorkers then
                return fail("restart_native_identity_reconciliation_unproven", nil, operationId)
            end
            local owners, allSource, allDestination = {}, true, true
            for _, id in ipairs(op.items) do
                local actual = observed.entries[id]
                local original = session and session.before.entries[id] or self.world.items[id]
                -- On restart, compare native persistent IDs and the supported
                -- item payload in the complete observed owner domain. There is
                -- no claim that a Java object handle survives a process restart.
                if
                    not actual
                    or not original
                    or session and actual.item ~= original.item
                    or not same(actual.data, original.data)
                then
                    allSource, allDestination = false, false
                else
                    owners[id] = actual.owner
                    if actual.owner ~= op.source then
                        allSource = false
                    end
                    if actual.owner ~= op.destination then
                        allDestination = false
                    end
                end
            end
            local outcome = allDestination and "applied" or allSource and "not_applied" or "unknown"
            if outcome ~= "unknown" and session then
                baselineUnchanged(session.before, observed, op, outcome == "applied")
            end
            local staged, revision = Core.snapshot(self.world), self.world.revision
            local result = apply(staged, a, true, "transfer.reconcile", { operationId = operationId }, {
                kind = "transfer_result",
                operationId = operationId,
                outcome = outcome,
                uniqueItems = true,
                owners = owners,
            })
            if not result.ok then
                return result
            end
            if outcome == "unknown" then
                publish(self.world, staged, revision) -- Keep unresolved locks even if persistence fails.
                local ack = persist(self, self.world, "unresolved", operationId)
                return ack.ok and fail("native_transfer_still_unresolved", nil, operationId) or ack
            end
            -- Releasing Core locks waits for the terminal snapshot acknowledgment.
            local ack = persist(self, staged, "reconciled", operationId)
            if not ack.ok then
                return ack
            end
            publish(self.world, staged, revision)
            result.operationId, result.persistenceLevel, result.proven, result.durable =
                operationId, ack.level, false, false
            return result
        end)
    end

    return self
end

return Native
