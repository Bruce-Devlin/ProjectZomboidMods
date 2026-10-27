-- Shared helpers. No game state or event handlers belong here.
local DevTools = {}

function DevTools.isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function DevTools.isText(value, maxLength)
    return type(value) == "string" and #value > 0 and #value <= maxLength
end

function DevTools.isSafeId(value)
    return DevTools.isText(value, 64) and value:match "^[A-Za-z0-9_-]+$" ~= nil
end

function DevTools.count(values)
    local total = 0
    for _ in pairs(values) do
        total = total + 1
    end
    return total
end

function DevTools.same(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not DevTools.same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Save data must contain plain values. Repeated tables are copied separately;
-- cycles and native objects are rejected.

function DevTools.copy(value, seen)
    if type(value) ~= "table" then
        if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
            error "plain_values_required"
        end
        if type(value) == "number" and not DevTools.isFinite(value) then
            error "finite_values_required"
        end
        return value
    end
    seen = seen or {}
    if seen[value] then
        error "cyclic_values_not_supported"
    end
    seen[value] = true
    local result = {}
    for key, entry in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            error "plain_keys_required"
        end
        result[key] = DevTools.copy(entry, seen)
    end
    seen[value] = nil
    return result
end

-- Stable text for command signatures and comparisons. This is not the save codec.

function DevTools.canonical(value)
    if type(value) == "table" then
        local keys, parts = {}, {}
        for key in pairs(value) do
            table.insert(keys, key)
        end
        table.sort(keys, function(a, b)
            return type(a) .. tostring(a) < type(b) .. tostring(b)
        end)
        for _, key in ipairs(keys) do
            table.insert(parts, DevTools.canonical(key) .. "=" .. DevTools.canonical(value[key]))
        end
        return "{" .. table.concat(parts, ";") .. "}"
    end
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return type(value) .. ":" .. tostring(value)
end

function DevTools.position(actor)
    return { x = actor:getX(), y = actor:getY(), z = actor:getZ() }
end

-- Plain coordinates; callers decide whether different floors are allowed.

function DevTools.distanceSquared(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

function DevTools.hash(id)
    local n = 17
    for i = 1, #id do
        n = (n * 31 + string.byte(id, i)) % 65521
    end
    return n
end

return DevTools
