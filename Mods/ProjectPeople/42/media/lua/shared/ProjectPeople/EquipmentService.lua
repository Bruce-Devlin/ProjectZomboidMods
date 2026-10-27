local Core = require "ProjectPeople/Core"
local Policy = require "ProjectPeople/EquipmentPolicy"
local Equipment = require "ProjectPeople/PeopleEquipment"
local Service = {}

local function fail(message, code)
    return { ok = false, code = code or "equipment_refused", message = message }
end

function Service.new(config)
    local self = { unresolved = {} }
    local function access(caller, fields, gift)
        if isClient() then
            return nil, fail "Only the world authority can change inventory."
        end
        local who = config.identity(caller)
        local world = config.authority:snapshot()
        local p = type(fields) == "table" and world.people[fields.personId]
        local actor, record
        if p then
            actor, record = config.actor(p.id)
        end
        if
            not who
            or not who.validated
            or not who.alive
            or not world.people[who.personId]
            or world.controllers[who.controllerId] ~= who.personId
        then
            return nil, fail "A living player is required."
        end
        if
            not actor
            or actor:isDead()
            or not actor:getCurrentSquare()
            or not caller:getCurrentSquare()
            or math.abs(actor:getZ() - caller:getZ()) > 0.2
            or (actor:getX() - caller:getX()) ^ 2 + (actor:getY() - caller:getY()) ^ 2 > 9
            or caller:getCurrentSquare():isBlockedTo(actor:getCurrentSquare())
            or caller:getCurrentSquare():isSomethingTo(actor:getCurrentSquare())
            or tostring(
                    LosUtil.lineClear(
                        getCell(),
                        caller:getX(),
                        caller:getY(),
                        caller:getZ(),
                        actor:getX(),
                        actor:getY(),
                        actor:getZ(),
                        false
                    )
                )
                ~= "Clear"
        then
            return nil, fail "Move within three tiles with a clear path to them."
        end
        local allowed, reason = Policy.access(p, who.personId, record, gift)
        if not allowed then
            return nil, fail(reason)
        end
        if
            not caller:getCharacterActions():isEmpty()
            or caller:getVehicle()
            or actor:getVehicle()
            or caller:isGrappling()
            or caller:isBeingGrappled()
        then
            return nil, fail "Finish your current action first."
        end
        local md = actor:getModData()
        if md.ProjectPeopleEquipmentFault then
            return nil, fail("An earlier inventory change needs reconciliation.", "equipment_reconciliation_required")
        end
        for _, op in pairs(world.operations) do
            if
                op.kind == "transfer"
                and not op.terminal
                and (op.source == "person:" .. p.id or op.destination == "person:" .. p.id)
            then
                return nil, fail "An earlier item transfer needs reconciliation."
            end
        end
        return {
            actor = actor,
            record = record,
            person = p,
            who = who,
            world = world,
            md = md,
            version = md.ProjectPeopleEquipmentRevision or 0,
        }
    end
    function self:request(caller, kind, fields)
        local gift = kind == "gift.open" or kind == "inventory.gift"
        local a, problem = access(caller, fields, gift)
        if not a then
            return problem
        end
        local allowed = gift and { personId = true, version = true, itemId = true }
            or { personId = true, version = true, itemId = true, destination = true, direction = true, mode = true }
        for k in pairs(fields) do
            if not allowed[k] then
                return fail "Invalid inventory request."
            end
        end
        local npc, player = Equipment.scan(a.actor), Equipment.scan(caller)
        for id in pairs(npc.items) do
            if player.items[id] then
                return fail "Inventory identity needs reconciliation."
            end
        end
        if kind == "gift.open" then
            local description = Equipment.describe(caller, player)
            local offers = {}
            for _, entry in ipairs(description.items) do
                if Equipment.giftMode(player.items[entry.id].item) then
                    offers[#offers + 1] = entry
                end
            end
            return {
                ok = true,
                code = "gift_view",
                gift = { personId = a.person.id, name = a.person.name, version = a.version, items = offers },
            }
        end
        if kind == "inventory.open" then
            return {
                ok = true,
                code = "inventory_view",
                personId = a.person.id,
                inventory = {
                    personId = a.person.id,
                    name = a.person.name,
                    version = a.version,
                    npc = Equipment.describe(a.actor, npc),
                    player = Equipment.describe(caller, player),
                },
            }
        end
        if fields.version ~= a.version then
            return fail("Inventory changed. Refresh and try again.", "stale_inventory")
        end
        if kind == "equipment.set" then
            local entry = npc.items[fields.itemId]
            if not entry then
                return fail "That item is no longer in their inventory."
            end
            local registered = a.world.items[entry.id]
            if registered and registered.lock then
                return fail "That item is reserved for another transfer."
            end
            local ok, reason = Equipment.equip(a.actor, entry, fields.mode)
            if not ok then
                return fail(reason)
            end
            a.md.ProjectPeopleEquipmentRevision = a.version + 1
            return { ok = true, code = "equipment_changed", message = "Equipment updated." }
        end
        if kind ~= "inventory.transfer" and kind ~= "inventory.gift" then
            return fail "Unknown inventory action."
        end
        local giving = gift or fields.direction == "give"
        local taking = not gift and fields.direction == "take"
        local stowing = not gift and fields.direction == "stow"
        if not giving and not taking and not stowing then
            return fail "Choose a transfer direction."
        end
        local sourceActor = giving and caller or a.actor
        local destActor = taking and caller or a.actor
        local source = giving and player or npc
        local dest = taking and player or npc
        local entry = source.items[fields.itemId]
        local destination = dest.containers[fields.destination or "root"]
        if not entry or not destination or entry.container == destination then
            return fail "The item or destination has changed."
        end
        if gift and not Equipment.giftMode(entry.item) then
            return fail "Choose a weapon, clothing or wearable bag to gift."
        end
        local giftEquip = gift and Equipment.giftEquipMode(npc, entry.item)
        local ok, reason = Equipment.canMove(sourceActor, entry)
        if not ok then
            return fail(reason)
        end
        if not entry.container:isRemoveItemAllowed(entry.item) then
            return fail "That item cannot be removed."
        end
        if stowing then
            if
                destination:isInside(entry.item)
                or not destination:isItemAllowed(entry.item)
                or not destination:hasRoomFor(destActor, entry.item)
            then
                return fail "There is no room in that container."
            end
        else
            ok, reason = Equipment.capacity(destActor, destination, entry.item)
            if not ok then
                return fail(reason)
            end
        end
        local entries = { entry }
        local descendants = { [entry.id] = true }
        for _, child in ipairs(source.order) do
            if descendants[child.parent] then
                local movable, why = Equipment.canMove(sourceActor, child)
                if not movable then
                    return fail(why)
                end
                descendants[child.id] = true
                entries[#entries + 1] = child
            end
        end
        for _, child in ipairs(entries) do
            local registered = a.world.items[child.id]
            if registered and registered.lock then
                return fail "An item in this transfer is already reserved."
            end
        end
        local context = config.authority:adapterContext()
        local unresolved = self.unresolved
        local adapter = {}
        function adapter:observe()
            local world = context.world
            local ctx = {
                authority = true,
                system = true,
                issuer = "equipment_authority",
                gameTime = getGameTime():getWorldAgeHours(),
            }
            local function apply(command, data, evidence)
                ctx.evidence = evidence
                if evidence then
                    evidence.validated = true
                end
                local r = Core.apply(world, Core.command(world, ctx.issuer, command, data), ctx)
                assert(r.ok, r.code)
                return r
            end
            local function save(stage, operation)
                local ack = context.persist(Core.snapshot(world), stage, operation)
                assert(ack and ack.ok, "inventory_journal_unconfirmed")
            end
            local sourceOwner = "person:" .. (giving and a.who.personId or a.person.id)
            local destOwner = "person:" .. (taking and a.who.personId or a.person.id)
            local ids, observed, newIds = {}, {}, {}
            for _, child in ipairs(entries) do
                ids[#ids + 1] = child.id
                if not world.items[child.id] then
                    newIds[#newIds + 1] = child.id
                end
                observed[#observed + 1] = {
                    id = child.id,
                    data = {
                        fullType = child.item:getFullType(),
                        condition = child.item:getCondition(),
                        count = child.item:getCount(),
                        weight = child.item:getUnequippedWeight(),
                    },
                }
            end
            local operation
            if not stowing then
                apply(
                    "inventory.observe",
                    { owner = sourceOwner, items = observed },
                    { kind = "inventory_scan", owner = sourceOwner, uniqueItems = true }
                )
                operation = apply(
                    "transfer.prepare",
                    { source = sourceOwner, destination = destOwner, items = ids },
                    { kind = "transfer_access", source = sourceOwner, destination = destOwner, allowed = true }
                ).operationId
                save("prepared", operation)
                apply("operation.dispatch", { operationId = operation })
                save("dispatched", operation)
            end
            a.md.ProjectPeopleEquipmentRevision = a.version + 1
            a.md.ProjectPeopleEquipmentFault = operation or "container_move"
            -- One synchronous native move retains food, fluids, attachments,
            -- custom mod data, loaded ammunition and all nested original items.
            local item = entry.item
            local original = entry.container
            local moved = pcall(function()
                Equipment.prepareRemoval(item)
                original:DoRemoveItem(item)
                assert(
                    item:getContainer() == nil and not original:getItems():contains(item),
                    "native_remove_unconfirmed"
                )
                assert(
                    destination:AddItem(item) == item and item:getContainer() == destination,
                    "native_add_unconfirmed"
                )
            end)
            if not moved and not (item:getContainer() == destination and destination:getItems():contains(item)) then
                -- Retain the exact object and try restoring its original owner.
                -- Never compensate by creating a replacement item.
                unresolved[a.person.id] = entry
                if item:getContainer() == nil then
                    pcall(function()
                        original:AddItem(item)
                    end)
                end
                if item:getContainer() == original and original:getItems():contains(item) then
                    if operation then
                        local owners = {}
                        for _, id in ipairs(ids) do
                            owners[id] = sourceOwner
                        end
                        apply("transfer.reconcile", { operationId = operation }, {
                            kind = "transfer_result",
                            operationId = operation,
                            outcome = "not_applied",
                            uniqueItems = true,
                            owners = owners,
                        })
                        if #newIds > 0 then
                            apply("inventory.release_native", { operationId = operation, items = newIds }, {
                                kind = "native_inventory_release",
                                operationId = operation,
                                uniqueItems = true,
                                owners = owners,
                            })
                        end
                        save("cancelled", operation)
                    end
                    unresolved[a.person.id] = nil
                    a.md.ProjectPeopleEquipmentFault = nil
                    return fail "Transfer stopped; the original item remains in its original inventory."
                end
                return fail(
                    "Transfer interrupted. The original item is held for reconciliation.",
                    "equipment_reconciliation_required"
                )
            end
            if stowing and destActor:getInventoryWeight() > destActor:getMaxWeight() + 0.0001 then
                Equipment.prepareRemoval(item)
                destination:DoRemoveItem(item)
                assert(original:AddItem(item) == item, "capacity_rollback_failed")
                a.md.ProjectPeopleEquipmentFault = nil
                return fail "That move would exceed their carrying capacity."
            end
            local actual = Equipment.scan(destActor)
            for _, child in ipairs(entries) do
                assert(actual.items[child.id] and actual.items[child.id].item == child.item, "original_item_missing")
            end
            if isServer() then
                if giving then
                    sendRemoveItemFromContainer(original, item)
                end
                if taking then
                    sendAddItemToContainer(destination, item)
                end
            end
            if operation then
                local owners = {}
                for _, id in ipairs(ids) do
                    owners[id] = destOwner
                end
                apply("transfer.reconcile", { operationId = operation }, {
                    kind = "transfer_result",
                    operationId = operation,
                    outcome = "applied",
                    uniqueItems = true,
                    owners = owners,
                })
                if #newIds > 0 then
                    apply("inventory.release_native", { operationId = operation, items = newIds }, {
                        kind = "native_inventory_release",
                        operationId = operation,
                        uniqueItems = true,
                        owners = owners,
                    })
                end
                save("reconciled", operation)
            end
            a.md.ProjectPeopleEquipmentFault = nil
            original:setDrawDirty(true)
            destination:setDrawDirty(true)
            if gift then
                local equipped = false
                local message = "Gift accepted and kept in their inventory; they already have similar equipment."
                if giftEquip then
                    local completed, ok = pcall(Equipment.equip, a.actor, actual.items[entry.id], giftEquip)
                    equipped = completed and ok == true
                    message = equipped and "Gift accepted and equipped."
                        or "Gift accepted and kept in their inventory; it could not be equipped."
                elseif item:getCondition() <= 0 then
                    message = "Gift accepted and kept in their inventory; it needs repair before use."
                end
                return {
                    ok = true,
                    code = "gift_accepted",
                    message = message,
                    equipped = equipped,
                    operationId = operation,
                }
            end
            return { ok = true, code = "items_transferred", message = "Item transferred.", operationId = operation }
        end
        return config.authority:runAdapter(adapter, "observe")
    end
    return self
end
return Service
