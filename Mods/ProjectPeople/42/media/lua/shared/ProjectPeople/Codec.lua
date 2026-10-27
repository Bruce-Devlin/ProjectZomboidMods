-- Deterministic plain-data encoding. Never evaluates saved text as Lua code.
local Codec = { VERSION = 1, MAX_BYTES = 16 * 1024 * 1024, MAX_NODES = 100000, MAX_DEPTH = 32 }
-- Table replacement avoids a Lua callback and string.format for every byte.
local toHex, fromHex = {}, {}
for i = 0, 255 do
    local byte, hex = string.char(i), string.format("%02x", i)
    toHex[byte], fromHex[hex] = hex, byte
end

local function need(ok, why)
    if not ok then
        error(why)
    end
end

local function finite(n)
    return n == n and n ~= math.huge and n ~= -math.huge
end

local function keyOrder(a, b)
    if type(a) ~= type(b) then
        return type(a) < type(b)
    end
    return a < b
end

local function validKey(k)
    return type(k) == "string" or (type(k) == "number" and finite(k) and k == math.floor(k))
end

function Codec.encode(value)
    local parts, seen, nodes, bytes = {}, {}, 0, 0
    local function put(s)
        bytes = bytes + #s
        need(bytes <= Codec.MAX_BYTES, "encoded_data_too_large")
        parts[#parts + 1] = s
    end
    local function visit(v, depth)
        nodes = nodes + 1
        need(nodes <= Codec.MAX_NODES and depth <= Codec.MAX_DEPTH, "data_complexity_limit")
        local kind = type(v)
        if kind == "nil" then
            put "z"
        elseif kind == "boolean" then
            put(v and "t" or "f")
        elseif kind == "number" then
            need(finite(v), "nonfinite_number")
            local number = string.format("%.17g", v)
            put("n" .. #number .. ":" .. number)
        elseif kind == "string" then
            need(#v <= Codec.MAX_BYTES / 2, "string_too_large")
            put("s" .. #v .. ":")
            put((v:gsub(".", toHex)))
        elseif kind == "table" then
            need(not seen[v] and getmetatable(v) == nil, "cyclic_or_metatable_data")
            seen[v] = true
            local keys = {}
            for k in pairs(v) do
                need(validKey(k), "unsupported_table_key")
                keys[#keys + 1] = k
            end
            table.sort(keys, keyOrder)
            put("m" .. #keys .. ":")
            for _, k in ipairs(keys) do
                visit(k, depth + 1)
                visit(v[k], depth + 1)
            end
            seen[v] = nil
        else
            error("unsupported_value_type:" .. kind)
        end
    end
    local ok, err = pcall(visit, value, 0)
    if not ok then
        return nil, tostring(err)
    end
    return table.concat(parts)
end

function Codec.decode(encoded)
    if type(encoded) ~= "string" or #encoded > Codec.MAX_BYTES then
        return nil, "invalid_encoded_size"
    end
    local cursor, nodes = 1, 0
    local function count()
        local ending = encoded:find(":", cursor, true)
        need(ending and ending - cursor <= 9, "invalid_length")
        local raw = encoded:sub(cursor, ending - 1)
        need(raw:match "^%d+$" and (#raw == 1 or raw:sub(1, 1) ~= "0"), "invalid_length")
        local size = tonumber(raw)
        need(size and size <= Codec.MAX_BYTES, "length_limit")
        cursor = ending + 1
        return size
    end
    local function visit(depth)
        nodes = nodes + 1
        need(nodes <= Codec.MAX_NODES and depth <= Codec.MAX_DEPTH, "data_complexity_limit")
        local tag = encoded:sub(cursor, cursor)
        cursor = cursor + 1
        if tag == "z" then
            return nil
        elseif tag == "t" then
            return true
        elseif tag == "f" then
            return false
        elseif tag == "n" then
            local size = count()
            need(size > 0 and size <= 32 and cursor + size - 1 <= #encoded, "invalid_number_length")
            local raw = encoded:sub(cursor, cursor + size - 1)
            cursor = cursor + size
            need(raw:match "^[%+%-%.%deE]+$", "invalid_number_text")
            local n = tonumber(raw)
            need(n and finite(n), "invalid_number")
            return n
        elseif tag == "s" then
            local size = count() * 2
            need(cursor + size - 1 <= #encoded, "truncated_string")
            local raw = encoded:sub(cursor, cursor + size - 1)
            cursor = cursor + size
            need(raw:match "^[0-9a-f]*$", "invalid_string_bytes")
            return (raw:gsub("..", fromHex))
        elseif tag == "m" then
            local size = count()
            need(size <= Codec.MAX_NODES / 2, "table_size_limit")
            local result, keys = {}, {}
            for i = 1, size do
                local k = visit(depth + 1)
                need(validKey(k) and not keys[k], "invalid_or_duplicate_key")
                keys[k] = true
                local v = visit(depth + 1)
                need(v ~= nil, "nil_table_value")
                result[k] = v
            end
            return result
        end
        error "unknown_data_tag"
    end
    local ok, value = pcall(visit, 0)
    if not ok then
        return nil, tostring(value)
    end
    if cursor ~= #encoded + 1 then
        return nil, "trailing_data"
    end
    return value, nil
end
-- Adler32 detects accidental truncation/corruption; this is not authentication.

function Codec.checksum(value)
    local a, b = 1, 0
    for i = 1, #value do
        a = (a + string.byte(value, i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%.0f", b * 65536 + a)
end
return Codec
