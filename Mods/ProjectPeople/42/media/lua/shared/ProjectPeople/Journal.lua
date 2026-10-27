-- Two-slot journal for plain world records. File read-back does not make native saves atomic.
local DevTools = require "ProjectPeople/DevTools"
local Codec = require "ProjectPeople/Codec"
local Core = require "ProjectPeople/Core"
local Journal = { VERSION = 1, PROVEN = false }
local verifiedSlots = setmetatable({}, { __mode = "k" })

local function fail(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function fence(self, code, detail)
    self.fenced = code
    return fail(code, detail)
end

local function need(value, why)
    if not value then
        error(why)
    end
end

local function isText(value)
    return DevTools.isText(value, 128)
end

local function fileName(self, slot)
    return "ProjectPeople_" .. self.name .. "_" .. slot .. ".txt"
end

local function nativeIO()
    return {
        exists = function(path)
            return cacheFileExists(path)
        end,
        read = function(path)
            local reader = getFileReader(path, false)
            need(reader, "journal_reader_unavailable")
            local ok, line, extra = pcall(function()
                return reader:readLine(), reader:readLine()
            end)
            reader:close()
            need(ok, line)
            need(extra == nil, "multiple_journal_lines")
            return line
        end,
        write = function(path, line)
            local writer = getFileWriter(path, true, false)
            need(writer, "journal_writer_unavailable")
            local ok, err = pcall(function()
                writer:write(line)
            end)
            writer:close()
            need(ok, err)
        end,
    }
end

function Journal.new(name, worldId, timelineId, ioAdapter)
    if
        not isText(name)
        or #name > 80
        or not name:match "^[A-Za-z0-9_-]+$"
        or not isText(worldId)
        or not isText(timelineId)
    then
        return nil, "restricted_identity_required"
    end
    local self = { name = name, worldId = worldId, timelineId = timelineId, io = ioAdapter or nativeIO() }
    return setmetatable(self, { __index = Journal })
end

local function readSlot(self, slot)
    local ok, result = pcall(function()
        local path = fileName(self, slot)
        if not self.io.exists(path) then
            return { missing = true }
        end
        local line = self.io.read(path)
        need(type(line) == "string" and #line <= Codec.MAX_BYTES + 64, "invalid_journal_size")
        -- Still read and compare the actual stored bytes on every transaction.
        -- Only an identical, previously verified slot can skip decoding again.
        local cache = verifiedSlots[self]
        if cache and cache[slot] and cache[slot].line == line then
            return cache[slot].result
        end
        local checksum, payload = line:match "^PPJ1:(%d+):(.*)$"
        need(payload and Codec.checksum(payload) == checksum, "journal_checksum_mismatch")
        local decoded, err = Codec.decode(payload)
        need(decoded, err)
        need(
            decoded.schema == 1 and decoded.worldId == self.worldId and decoded.timelineId == self.timelineId,
            "journal_world_or_schema_mismatch"
        )
        need(
            type(decoded.generation) == "number"
                and decoded.generation >= 1
                and decoded.generation == math.floor(decoded.generation)
                and decoded.generation < 9007199254740991,
            "invalid_generation"
        )
        need(isText(decoded.stage), "journal_stage_missing")
        local world, why = Core.restore(decoded.snapshot)
        need(world, why)
        need(world.worldId == self.worldId and world.timelineId == self.timelineId, "snapshot_world_mismatch")
        local result = { entry = decoded, payload = payload, slot = slot }
        verifiedSlots[self] = cache or {}
        verifiedSlots[self][slot] = { line = line, result = result }
        return result
    end)
    return ok and result or { error = tostring(result), slot = slot }
end

local function readCurrent(self)
    local a, b = readSlot(self, "a"), readSlot(self, "b")
    -- A corrupt latest dispatch may have preceded an engine effect. Never
    -- silently fall back to an older prepared state and repeat that effect.
    if a.error or b.error then
        return fail("journal_recovery_required", a.error or b.error)
    end
    if a.missing and b.missing then
        return { ok = true, empty = true, generation = 0 }
    end
    local latest = a.missing and b or (b.missing and a or (a.entry.generation > b.entry.generation and a or b))
    if a.entry and b.entry and a.entry.generation == b.entry.generation and a.payload ~= b.payload then
        return fail "journal_generation_conflict"
    end
    return {
        ok = true,
        entry = latest.entry,
        generation = latest.entry.generation,
        slot = latest.slot,
        payload = latest.payload,
    }
end

function Journal:read()
    local observed = Core.snapshot(readCurrent(self))
    observed.payload = nil
    return observed -- Reading alone never arms or un-fences a writer.
end
-- A new writer for existing files must explicitly return the verified world to
-- its authority. Install this world before any further commands, then reconcile
-- native state separately. The old live world must not continue after ambiguity.

function Journal:adopt()
    if isClient and isClient() then
        return fail "authority_only"
    end
    if self.fenced then
        return fail("journal_writer_fenced", self.fenced)
    end
    if self.generation ~= nil then
        return fail "journal_writer_already_active"
    end
    local prior = readCurrent(self)
    if not prior.ok then
        return prior
    end
    if prior.empty then
        return fail "journal_empty"
    end
    local world, why = Core.restore(prior.entry.snapshot)
    if not world then
        return fail("journal_recovery_required", why)
    end
    self.generation, self.payload = prior.generation, prior.payload
    return {
        ok = true,
        world = world,
        generation = prior.generation,
        stage = prior.entry.stage,
        operationId = prior.entry.operationId,
        token = self.name .. ":" .. prior.generation,
        nativeWorldAtomic = false,
        proven = false,
    }
end

function Journal:persist(snapshot, stage, operationId)
    if isClient and isClient() then
        return fail "authority_only"
    end
    if self.fenced then
        return fail("journal_writer_fenced", self.fenced)
    end
    if not isText(stage) or (operationId ~= nil and not isText(operationId)) then
        return fail "invalid_stage"
    end
    local restored, world, why = pcall(Core.restore, snapshot)
    if not restored then
        return fail("invalid_snapshot", tostring(world))
    end
    if not world or world.worldId ~= self.worldId or world.timelineId ~= self.timelineId then
        return fail("invalid_snapshot", why)
    end
    local prior = readCurrent(self)
    if not prior.ok then
        return fence(self, prior.code, prior.detail)
    end
    if self.generation == nil then
        if not prior.empty then
            return fail "journal_adoption_required"
        end
    elseif prior.generation ~= self.generation or prior.payload ~= self.payload then
        return fence(self, "journal_writer_basis_changed")
    end
    if prior.entry and world.revision < prior.entry.snapshot.revision then
        return fail "stale_journal_revision"
    end
    local stableSnapshot = Core.snapshot(world)
    if prior.entry and world.revision == prior.entry.snapshot.revision then
        -- A complete terminal write can survive a failed acknowledgement while
        -- the live authority keeps its previous locked snapshot. A different
        -- reconciliation at that same next revision must not erase the record.
        local previous, previousError = Codec.encode(prior.entry.snapshot)
        if not previous then
            return fail("journal_recovery_required", previousError)
        end
        local proposed, proposedError = Codec.encode(stableSnapshot)
        if not proposed then
            return fail("snapshot_encoding_failed", proposedError)
        end
        if proposed ~= previous then
            return fail "journal_revision_conflict"
        end
    end
    local generation = prior.generation + 1
    local envelope = {
        schema = 1,
        worldId = self.worldId,
        timelineId = self.timelineId,
        generation = generation,
        stage = stage,
        operationId = operationId,
        snapshot = stableSnapshot,
    }
    local payload, err = Codec.encode(envelope)
    if not payload then
        return fail("snapshot_encoding_failed", err)
    end
    local slot = prior.slot == "a" and "b" or "a"
    local line = "PPJ1:" .. Codec.checksum(payload) .. ":" .. payload
    local ok, writeError = pcall(self.io.write, fileName(self, slot), line)
    if not ok then
        return fence(self, "journal_write_unknown", tostring(writeError))
    end
    -- We just validated/restored this snapshot and encoded this envelope. Exact
    -- readback proves these bytes without decoding the same world once more.
    local readOk, readback = pcall(self.io.read, fileName(self, slot))
    if not readOk or readback ~= line then
        return fence(self, "journal_readback_failed")
    end
    verifiedSlots[self] = verifiedSlots[self] or {}
    verifiedSlots[self][slot] = { line = line, result = { entry = envelope, payload = payload, slot = slot } }
    local observed = readCurrent(self)
    if
        not observed.ok
        or observed.empty
        or observed.generation ~= generation
        or observed.slot ~= slot
        or observed.payload ~= payload
    then
        return fence(self, "journal_readback_failed", observed.detail or observed.code)
    end
    self.generation, self.payload = generation, payload
    return {
        ok = true,
        level = self.io.level or "file_readback",
        worldId = self.worldId,
        timelineId = self.timelineId,
        revision = world.revision,
        stage = stage,
        token = self.name .. ":" .. generation,
        generation = generation,
        nativeWorldAtomic = false,
        proven = false,
    }
end
return Journal
