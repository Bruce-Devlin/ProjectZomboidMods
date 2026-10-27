-- Journal slots belong to the native world save, never the global Lua cache.
-- Native save and engine objects are still separate writes: recovery reconciles
-- bodies/items before effects. This adapter does not claim crash atomicity.
local Store = { VERSION = 1 }

function Store.io(metadata)
    assert(type(metadata) == "table", "world_metadata_required")
    metadata.journalSlots = metadata.journalSlots or {}
    return {
        level = "world_save_memory",
        exists = function(name)
            return metadata.journalSlots[name] ~= nil
        end,
        read = function(name)
            local value = metadata.journalSlots[name]
            if type(value) == "string" then
                return value
            end
            assert(
                type(value) == "table"
                    and value.version == 1
                    and type(value.parts) == "table"
                    and type(value.count) == "number"
                    and value.count >= 1
                    and value.count <= 4097
                    and value.count % 1 == 0,
                "invalid_world_journal_chunks"
            )
            local parts = {}
            for i = 1, value.count do
                assert(type(value.parts[i]) == "string" and #value.parts[i] <= 4096, "invalid_world_journal_chunk")
                parts[i] = value.parts[i]
            end
            local joined = table.concat(parts)
            assert(#joined == value.bytes, "incomplete_world_journal_chunks")
            return joined
        end,
        write = function(name, value)
            -- Installed native table strings have a short length field. A
            -- snapshot can exceed it even for three people and two containers.
            -- Codec output is ASCII; bounded chunks also avoid UTF byte growth.
            assert(type(value) == "string" and #value <= 16 * 1024 * 1024 + 64, "invalid_world_journal_value")
            local parts = {}
            for first = 1, #value, 4096 do
                parts[#parts + 1] = value:sub(first, first + 4095)
            end
            metadata.journalSlots[name] = { version = 1, parts = parts, count = #parts, bytes = #value }
        end,
    }
end

function Store.recover(world, binding)
    if world.worldId ~= binding.worldId or world.timelineId ~= binding.timelineId then
        return nil
    end
    -- Adopts records only. Missing bodies/items stay unavailable until the
    -- coordinator independently observes their native owners after chunk load.
    return { validated = true, worldId = world.worldId, timelineId = world.timelineId, revision = world.revision }
end
return Store
