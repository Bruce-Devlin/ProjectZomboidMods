-- Installed 42.21 candidate. Original actors are submitted during the ordinary
-- world-render event; no player slots/maps, model admission or body state change.
-- A successful native call is a draw submission, never proof of visible pixels.
ProjectPeople = ProjectPeople or {}
local Rendering = { VERSION = 1, PROVEN = false, RECENT_MS = 500 }
ProjectPeople.NativeRendering = Rendering
local entries = {}

local function fail(code, detail)
    return { ok = false, code = code, detail = detail, proven = false, pixelVisibilityProven = false }
end

local function uncontrolled(actor)
    if not actor or not instanceof(actor, "IsoPlayer") or not actor:isNpc() or actor:isLocalPlayer() then
        return false
    end
    for index = 0, 3 do
        if getSpecificPlayer(index) == actor then
            return false
        end
    end
    return true
end

local function snapshot(entry, playerIndex)
    local times, owners = {}, 0
    for slot, time in pairs(entry.renderedAt) do
        times[slot] = time
    end
    for _ in pairs(entry.owners) do
        owners = owners + 1
    end
    local last = playerIndex ~= nil and entry.renderedAt[playerIndex] or nil
    return {
        ok = true,
        code = "native_draw_candidate_observed",
        actor = entry.actor,
        ownerCount = owners,
        renderSubmissions = entry.submissions,
        renderedAt = times,
        renderError = entry.error,
        renderEvents = entry.events,
        lastSkip = entry.lastSkip,
        submittedRecently = last ~= nil and getTimestampMs() - last <= Rendering.RECENT_MS,
        proven = false,
        pixelVisibilityProven = false,
    }
end

-- ownerKey is a stable caller-owned string. Multiple owners share one draw;
-- removing one owner's enrollment never removes another owner's enrollment.

function Rendering.add(actor, ownerKey)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return fail "render_owner_required"
    end
    if isServer() then
        return fail "client_render_context_required"
    end
    local ok, valid = pcall(function()
        return getCore():getVersionNumber() == "42.21" and uncontrolled(actor)
    end)
    if not ok or not valid then
        return fail("uncontrolled_native_player_required", not ok and tostring(valid) or nil)
    end
    local entry = entries[actor]
    if not entry then
        entry = { actor = actor, owners = {}, renderedAt = {}, submissions = 0, events = 0 }
        entries[actor] = entry
    end
    entry.owners[ownerKey] = true
    return snapshot(entry)
end

function Rendering.remove(actor, ownerKey)
    local entry = entries[actor]
    if not entry or not entry.owners[ownerKey] then
        return fail "render_enrollment_not_found"
    end
    entry.owners[ownerKey] = nil
    local answer = snapshot(entry)
    if answer.ownerCount == 0 then
        entries[actor] = nil
    end
    answer.code = "render_owner_removed"
    return answer
end

function Rendering.observe(actor, playerIndex)
    local entry = entries[actor]
    if not entry then
        return fail "render_enrollment_not_found"
    end
    return snapshot(entry, playerIndex)
end

-- FBORenderCell.renderPlayers only visits actual player slots/network mappings;
-- renderMovingObject skips exact IsoPlayer. Vanilla fishing/building Lua uses
-- this world event. It can be absent when no valid world tile is picked, so the
-- per-viewport timestamps must be checked by any response-opportunity policy.
Events.RenderOpaqueObjectsInWorld.Add(function(playerIndex)
    for _, entry in pairs(entries) do
        if not entry.error then
            entry.events = entry.events + 1
            local ok, err = pcall(function()
                local actor = entry.actor
                if not uncontrolled(actor) then
                    entry.lastSkip = "actor_control_changed"
                    return
                end
                local square = actor:getCurrentSquare()
                if not square then
                    entry.lastSkip = "no_current_square"
                    return
                end
                if not square:isCouldSee(playerIndex) then
                    entry.lastSkip = "square_not_visible"
                    return
                end
                if not actor:isOnScreen() then
                    entry.lastSkip = "off_screen"
                    return
                end
                if not actor:getDoRender() or actor:isSpriteInvisible() then
                    entry.lastSkip = "render_disabled"
                    return
                end
                if actor:getAlpha(playerIndex) <= 0.05 then
                    entry.lastSkip = "alpha_hidden"
                    return
                end
                if not actor:hasActiveModel() then
                    entry.lastSkip = "no_active_model"
                    return
                end
                local light = square:getLightInfo(playerIndex)
                if not light then
                    entry.lastSkip = "no_square_light"
                    return
                end
                actor:render(actor:getX(), actor:getY(), actor:getZ(), light, true, false, nil)
                entry.renderedAt[playerIndex] = getTimestampMs()
                entry.submissions = entry.submissions + 1
                entry.lastSkip = nil
            end)
            if not ok then
                entry.error = tostring(err)
            end
        end
    end
end)

return Rendering
