-- Session-only native save/load checks. Loading a body does not establish item conservation.
local DevTools = require "ProjectPeople/DevTools"
ProjectPeople = ProjectPeople or {}
local Native = { VERSION = 1, PROVEN = false }
ProjectPeople.NativeSnapshot = Native

-- Session-only guards deliberately cannot authorize recovery after a restart.
local operations, activePeople, usedTargets = {}, {}, {}
local operationCount = 0

local function fail(code, detail)
    return { ok = false, code = code, detail = detail, proven = false }
end

local isSafeId = DevTools.isSafeId

local function context()
    local ok, result = pcall(function()
        if isClient() then
            return fail "client_snapshot_authority_rejected"
        end
        local build = getCore():getVersionNumber()
        -- Live 42.21.0 reports "42.21" through getVersionNumber(). The console
        -- carries the patch component; root verified that installed pairing.
        if build ~= "42.21" and build ~= "42.21.0" and not build:match "^42%.21%.0[^%d%.]" then
            return fail("uninspected_game_build", build)
        end
        local root, separator = getCurrentSaveName(), getFileSeparator()
        if type(root) ~= "string" or root == "" or separator ~= "/" and separator ~= "\\" then
            return fail "current_save_path_unavailable"
        end
        return {
            ok = true,
            root = root,
            separator = separator,
            build = build,
            mode = isServer() and "server_candidate" or "singleplayer_candidate",
        }
    end)
    return ok and result or fail "native_environment_unavailable"
end

local function npc(actor)
    local ok, valid = pcall(function()
        return actor ~= nil
            and instanceof(actor, "IsoPlayer")
            and actor:isNpc()
            and not actor:isDead()
            and not actor:isLocalPlayer()
            and not actor:isSaveFileInUse()
    end)
    return ok and valid == true
end

local function detached(actor)
    local ok, valid = pcall(function()
        local cell = getCell()
        return actor:getCurrentSquare() == nil
            and not cell:getObjectList():contains(actor)
            and not cell:getAddList():contains(actor)
            and not cell:getRemoveList():contains(actor)
    end)
    return ok and valid == true
end

local function emptyTarget(actor)
    local ok, valid = pcall(function()
        return actor:getInventory():getItems():size() == 0
            and actor:getWornItems():size() == 0
            and actor:getAttachedItems():size() == 0
            and actor:getPrimaryHandItem() == nil
            and actor:getSecondaryHandItem() == nil
            and actor:getKnownRecipes():size() == 0
            and actor:getAlreadyReadBook():size() == 0
            and actor:getReadLiterature():size() == 0
            and actor:getReadPrintMedia():size() == 0
    end)
    return ok and valid == true
end

local function exists(basename)
    local ok, found = pcall(checkSaveFileExists, basename)
    if not ok or type(found) ~= "boolean" then
        return nil
    end
    return found
end

-- Native BodyDamage.save omits aggregate infection flags and native strings
-- collapse null to empty. Lua medical actions distinguish nil from empty, so
-- retain exact optional item strings instead of normalizing observations.
-- These setters are direct assignments, except setIsFakeInfected also writes
-- part zero; preserve that part's independent flag. All data is session-only.

local function bodySupplement(actor)
    local ok, value = pcall(function()
        local body = actor:getBodyDamage()
        local parts = body:getBodyParts()
        local count = parts:size()
        assert(count >= 1 and count <= 64, "unsupported_body_part_count")
        local saved = {
            infected = body:isInfected(),
            fakeInfected = body:isIsFakeInfected(),
            firstPartFakeInfected = parts:get(0):IsFakeInfected(),
            parts = {},
        }
        for index = 0, count - 1 do
            local part = parts:get(index)
            local splint, bandage = part:getSplintItem(), part:getBandageType()
            assert(splint == nil or type(splint) == "string", "invalid_splint_item")
            assert(bandage == nil or type(bandage) == "string", "invalid_bandage_type")
            saved.parts[index + 1] = { splintItem = splint, bandageType = bandage }
        end
        return saved
    end)
    if
        not ok
        or type(value.infected) ~= "boolean"
        or type(value.fakeInfected) ~= "boolean"
        or type(value.firstPartFakeInfected) ~= "boolean"
    then
        return nil
    end
    return value
end

local function restoreBodySupplement(actor, value)
    local body = actor:getBodyDamage()
    body:setInfected(value.infected)
    body:setIsFakeInfected(value.fakeInfected)
    local parts = body:getBodyParts()
    parts:get(0):SetFakeInfected(value.firstPartFakeInfected)
    assert(parts:size() == #value.parts, "body_supplement_part_count_mismatch")
    for index = 0, parts:size() - 1 do
        parts:get(index):setSplintItem(value.parts[index + 1].splintItem)
        parts:get(index):setBandageType(value.parts[index + 1].bandageType)
    end
    local observed = bodySupplement(actor)
    assert(
        observed
            and observed.infected == value.infected
            and observed.fakeInfected == value.fakeInfected
            and observed.firstPartFakeInfected == value.firstPartFakeInfected,
        "infection_supplement_mismatch"
    )
    for index, part in ipairs(value.parts) do
        assert(
            observed.parts[index].splintItem == part.splintItem
                and observed.parts[index].bandageType == part.bandageType,
            "medical_item_supplement_mismatch"
        )
    end
end

local receiptFields = { "schema", "personId", "revision", "operationId", "basename", "saveRoot", "build", "mode" }

local function receipt(operation)
    local result = {}
    for _, key in ipairs(receiptFields) do
        result[key] = operation[key]
    end
    return result
end

-- Every filename is derived here. There is no path, prefix or overwrite input.

function Native.writeCandidate(actor, personId, revision, operationId)
    if
        not isSafeId(personId)
        or not isSafeId(operationId)
        or type(revision) ~= "number"
        or revision ~= revision
        or revision < 0
        or revision > 2147483647
        or revision ~= math.floor(revision)
    then
        return fail "restricted_ids_and_revision_required"
    end
    local env = context()
    if not env.ok then
        return env
    end
    if not npc(actor) then
        return fail "living_uncontrolled_native_npc_required"
    end
    local previous = activePeople[personId]
    if previous and (previous.state ~= "loaded" or previous.target ~= actor) then
        return fail "previous_person_operation_unresolved"
    end
    local basename = "projectpeople_n1_p"
        .. #personId
        .. "_"
        .. personId
        .. "_r"
        .. revision
        .. "_o"
        .. #operationId
        .. "_"
        .. operationId
        .. ".bin"
    local path = env.root .. env.separator .. basename
    if operations[path] then
        return fail "operation_already_dispatched"
    end
    local found = exists(basename)
    if found == nil then
        return fail "snapshot_existence_check_unavailable"
    end
    if found then
        return fail "snapshot_already_exists"
    end
    if operationCount >= 128 then
        return fail "candidate_session_operation_limit"
    end
    local supplement = bodySupplement(actor)
    if not supplement then
        return fail "body_supplement_unavailable"
    end
    local operation = {
        schema = Native.VERSION,
        personId = personId,
        revision = revision,
        operationId = operationId,
        basename = basename,
        saveRoot = env.root,
        build = env.build,
        mode = env.mode,
        source = actor,
        state = "writing",
        path = path,
        supplement = supplement,
    }
    operations[path], activePeople[personId] = operation, operation
    operationCount = operationCount + 1
    -- Dispatch is recorded before calling native code. A partial file or thrown
    -- save leaves an unknown operation; no automatic overwrite/replay is allowed.
    local ok, errorMessage = pcall(function()
        actor:save(path)
    end)
    if not ok or exists(basename) ~= true then
        operation.state = "unknown"
        return fail("native_save_outcome_unknown", ok and "file_not_observed" or tostring(errorMessage))
    end
    operation.state = "written"
    return { ok = true, code = "candidate_file_written", proven = false, receipt = receipt(operation) }
end

-- The caller must supply a NEWLY CONSTRUCTED actor. Empty public collections
-- cannot prove every private history field is fresh. Never use an existing
-- person/player as target. Root engine proofs own that construction lifecycle.

function Native.loadIntoFreshNpc(target, suppliedReceipt)
    if type(suppliedReceipt) ~= "table" then
        return fail "receipt_required"
    end
    local env = context()
    if not env.ok then
        return env
    end
    if suppliedReceipt.saveRoot ~= env.root or suppliedReceipt.build ~= env.build then
        return fail "snapshot_save_or_build_mismatch"
    end
    -- The supplied basename is used only as a lookup key. Native I/O uses the
    -- original internal path after all receipt fields match the saved operation.
    if type(suppliedReceipt.basename) ~= "string" then
        return fail "receipt_required"
    end
    local operation = operations[env.root .. env.separator .. suppliedReceipt.basename]
    if not operation then
        return fail "restart_reconciliation_unproven"
    end
    for _, key in ipairs(receiptFields) do
        if suppliedReceipt[key] ~= operation[key] then
            return fail "receipt_mismatch"
        end
    end
    if activePeople[operation.personId] ~= operation or operation.state ~= "written" then
        return fail "operation_not_loadable"
    end
    if target == operation.source or usedTargets[target] then
        return fail "target_already_used"
    end
    if not npc(target) or not detached(target) or not emptyTarget(target) then
        return fail "fresh_empty_detached_npc_required"
    end
    if not detached(operation.source) or not npc(operation.source) then
        return fail "source_not_detached_and_uncontrolled"
    end
    if exists(operation.basename) ~= true then
        return fail "snapshot_missing_or_unreadable"
    end
    -- The authority must keep the old source quarantined. We do not clear its
    -- items or destroy it to manufacture a conservation assertion.
    operation.state, operation.target, usedTargets[target] = "loading", target, true
    local nativeBodyReadback
    local ok, errorMessage = pcall(function()
        target:load(operation.path)
        nativeBodyReadback = bodySupplement(target)
        assert(nativeBodyReadback, "native_body_readback_unavailable")
        restoreBodySupplement(target, operation.supplement)
    end)
    if not ok then
        operation.state = "unknown"
        return fail("native_load_outcome_unknown", tostring(errorMessage))
    end
    operation.state = "loaded"
    return {
        ok = true,
        code = "candidate_loaded_requires_reconciliation",
        proven = false,
        receipt = receipt(operation),
        authorityCommitted = false,
        nativeBodyReadback = nativeBodyReadback,
    }
end

return Native
