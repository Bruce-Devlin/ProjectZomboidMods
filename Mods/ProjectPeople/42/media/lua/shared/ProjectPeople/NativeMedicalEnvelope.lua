-- Preserves medical fields omitted by native saves, including nil and empty strings.
local DevTools = require "ProjectPeople/DevTools"
local Codec = require "ProjectPeople/Codec"
local Medical = { VERSION = 1, PROVEN = false, KEY = "ProjectPeopleNativeMedicalEnvelopeV1" }
local candidates, candidateCount = {}, 0
local receiptFields = { "worldId", "timelineId", "personId", "operationId", "username", "revision" }

local function fail(code, detail)
    return { ok = false, code = code, detail = detail, proven = false, authorityCommitted = false }
end

local function need(value, why)
    if not value then
        error(why)
    end
end

local function isText(value)
    return DevTools.isText(value, 128)
end

local function validReceipt(receipt)
    if type(receipt) ~= "table" then
        return false
    end
    for _, key in ipairs(receiptFields) do
        if key ~= "revision" and not isText(receipt[key]) then
            return false
        end
    end
    return type(receipt.revision) == "number"
        and receipt.revision >= 0
        and receipt.revision <= 2147483647
        and receipt.revision == math.floor(receipt.revision)
end

local function sameReceipt(a, b)
    if not validReceipt(a) or not validReceipt(b) then
        return false
    end
    for _, key in ipairs(receiptFields) do
        if a[key] ~= b[key] then
            return false
        end
    end
    return true
end

local function optional(value)
    need(value == nil or type(value) == "string" and #value <= 256, "unsupported_medical_string")
    return value == nil and { present = false } or { present = true, value = value }
end

local function validOptional(value)
    return type(value) == "table"
        and (
            value.present == false and value.value == nil
            or value.present == true and type(value.value) == "string" and #value.value <= 256
        )
end

local function unwrap(value)
    if value.present then
        return value.value
    end
end

local function validateBody(body)
    if
        type(body) ~= "table"
        or type(body.infected) ~= "boolean"
        or type(body.fakeInfected) ~= "boolean"
        or type(body.firstPartFakeInfected) ~= "boolean"
        or type(body.parts) ~= "table"
        or #body.parts ~= 17
    then
        return false
    end
    local count = 0
    for index, part in pairs(body.parts) do
        if
            type(index) ~= "number"
            or index < 1
            or index > 17
            or index ~= math.floor(index)
            or type(part) ~= "table"
            or not validOptional(part.splintItem)
            or not validOptional(part.bandageType)
        then
            return false
        end
        count = count + 1
    end
    return count == 17
end

local function observe(actor)
    local body = actor:getBodyDamage()
    local parts = body:getBodyParts()
    need(parts:size() == 17, "uninspected_body_part_layout")
    local result = {
        infected = body:isInfected(),
        fakeInfected = body:isIsFakeInfected(),
        firstPartFakeInfected = parts:get(0):IsFakeInfected(),
        parts = {},
    }
    for index = 0, 16 do
        local part = parts:get(index)
        result.parts[index + 1] =
            { splintItem = optional(part:getSplintItem()), bandageType = optional(part:getBandageType()) }
    end
    need(validateBody(result), "medical_observation_incomplete")
    return result
end

function Medical.observe(actor)
    local ok, body = pcall(observe, actor)
    return ok and { ok = true, body = body, proven = false } or fail("medical_observation_failed", tostring(body))
end

function Medical.pack(actor, receipt)
    if not validReceipt(receipt) then
        return fail "medical_receipt_required"
    end
    local read = Medical.observe(actor)
    if not read.ok then
        return read
    end
    local identity = {}
    for _, key in ipairs(receiptFields) do
        identity[key] = receipt[key]
    end
    local payload, err = Codec.encode({ schema = Medical.VERSION, receipt = identity, body = read.body })
    if not payload or #payload > 32768 then
        return fail("medical_encoding_failed", err)
    end
    return { ok = true, payload = payload, proven = false, authorityCommitted = false }
end

-- Evidence must be produced by the authority adapter after actual journal
-- read-back and an authenticated client acknowledgement. It is never accepted
-- directly from a client request. File read-back is NOT atomic with players.db.

function Medical.bindCandidate(payload, expectedReceipt, evidence)
    if type(payload) ~= "string" or #payload > 32768 or not validReceipt(expectedReceipt) then
        return fail "medical_envelope_required"
    end
    local envelope, err = Codec.decode(payload)
    if
        type(envelope) ~= "table"
        or envelope.schema ~= Medical.VERSION
        or not sameReceipt(envelope.receipt, expectedReceipt)
        or not validateBody(envelope.body)
        or Codec.encode(envelope) ~= payload
    then
        return fail("medical_envelope_mismatch", err)
    end
    if type(evidence) ~= "table" then
        return fail "medical_journal_readback_required"
    end
    local receipt = evidence and evidence.journalReceipt
    local read = evidence and evidence.journalReadback
    local ack = evidence and evidence.clientAcknowledgement
    if
        type(receipt) ~= "table"
        or receipt.ok ~= true
        or receipt.level ~= "file_readback"
        or receipt.stage ~= "medical_prepared"
        or receipt.worldId ~= expectedReceipt.worldId
        or receipt.timelineId ~= expectedReceipt.timelineId
        or not isText(receipt.token)
        or type(receipt.generation) ~= "number"
        or receipt.generation < 1
        or receipt.generation ~= math.floor(receipt.generation)
        or type(receipt.revision) ~= "number"
        or type(read) ~= "table"
        or read.ok ~= true
        or type(read.entry) ~= "table"
        or read.generation ~= receipt.generation
        or read.entry.generation ~= receipt.generation
        or read.entry.stage ~= receipt.stage
        or read.entry.operationId ~= expectedReceipt.operationId
        or type(read.entry.snapshot) ~= "table"
        or read.entry.snapshot.revision ~= receipt.revision
        or read.entry.snapshot.medicalEnvelope ~= payload
        or read.entry.worldId ~= expectedReceipt.worldId
        or read.entry.timelineId ~= expectedReceipt.timelineId
    then
        return fail "medical_journal_readback_required"
    end
    if
        type(ack) ~= "table"
        or ack.payload ~= payload
        or ack.journalToken ~= receipt.token
        or ack.username ~= expectedReceipt.username
        or ack.operationId ~= expectedReceipt.operationId
    then
        return fail "medical_authenticated_ack_required"
    end
    if candidateCount >= 16 then
        return fail "medical_candidate_session_limit"
    end
    local handle = {}
    candidates[handle] = { envelope = envelope, payload = payload, used = {} }
    candidateCount = candidateCount + 1
    return { ok = true, handle = handle, proven = false, authorityCommitted = false }
end

local function controlledActor(actor, username)
    if
        not actor
        or not instanceof(actor, "IsoPlayer")
        or actor:isDead()
        or actor:isNpc()
        or actor:getUsername() ~= username
    then
        return false
    end
    if isServer() then
        local found, count = false, 0
        local players = getOnlinePlayers()
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            if player:getUsername() == username then
                count = count + 1
                found = player == actor
            end
        end
        return found and count == 1
    end
    return isClient() and getSpecificPlayer(0) == actor and actor:isLocalPlayer()
end

function Medical.applyCandidate(actor, handle)
    local candidate = candidates[handle]
    if not candidate then
        return fail "medical_candidate_not_authorized"
    end
    if candidate.used[actor] then
        return fail "medical_application_already_dispatched"
    end
    local ok, ready = pcall(function()
        return getCore():getVersionNumber() == "42.21"
            and controlledActor(actor, candidate.envelope.receipt.username)
            and actor:getModData()[Medical.KEY] == candidate.payload
    end)
    if not ok or not ready then
        return fail "medical_actor_or_receipt_mismatch"
    end
    local before = Medical.observe(actor)
    if not before.ok then
        return before
    end
    -- Record dispatch before any setter. Partial native failure is unknown and
    -- cannot be replayed against this object, even if some values look correct.
    candidate.used[actor] = "dispatching"
    local applied, after = pcall(function()
        local expected = candidate.envelope.body
        local body = actor:getBodyDamage()
        local parts = body:getBodyParts()
        body:setInfected(expected.infected)
        body:setIsFakeInfected(expected.fakeInfected)
        parts:get(0):SetFakeInfected(expected.firstPartFakeInfected)
        for index = 0, 16 do
            parts:get(index):setSplintItem(unwrap(expected.parts[index + 1].splintItem))
            parts:get(index):setBandageType(unwrap(expected.parts[index + 1].bandageType))
        end
        local result = observe(actor)
        need(Codec.encode(result) == Codec.encode(expected), "medical_native_readback_mismatch")
        return result
    end)
    if not applied then
        candidate.used[actor] = "unknown"
        return fail("medical_application_unknown", tostring(after))
    end
    candidate.used[actor] = "applied"
    return { ok = true, before = before.body, after = after, proven = false, authorityCommitted = false }
end

function Medical.closeCandidate(handle)
    candidates[handle] = nil
end
return Medical
