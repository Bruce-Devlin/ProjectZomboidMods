-- Reads native character state for transfer checks. This is not a restorable save.
local DevTools = require "ProjectPeople/DevTools"
ProjectPeople = ProjectPeople or {}
local State = { VERSION = 1, INSPECTED_BUILD = "42.21" }
ProjectPeople.CharacterState = State
local unpackArgs = unpack or table.unpack

local isFinite = DevTools.isFinite

local function issue(snapshot, path, code)
    snapshot.missing[#snapshot.missing + 1] = { path = path, code = code }
end

local function invoke(snapshot, object, method, path, ...)
    local args = { ... }
    local ok, value = pcall(function()
        if object == nil or object[method] == nil then
            error "unavailable"
        end
        return object[method](object, unpackArgs(args))
    end)
    if not ok then
        issue(snapshot, path, "unavailable_or_failed:" .. method)
        return nil
    end
    return value
end

local function scalar(snapshot, value, path, expected, nullable)
    if value == nil and nullable then
        return nil
    end
    if type(value) ~= expected or expected == "number" and not isFinite(value) then
        issue(snapshot, path, "invalid_" .. expected)
        return nil
    end
    return value
end

local function read(snapshot, object, method, path, expected, nullable, ...)
    return scalar(snapshot, invoke(snapshot, object, method, path, ...), path, expected, nullable)
end

local function fields(snapshot, object, path, definitions)
    local result = {}
    for _, definition in ipairs(definitions) do
        local key, method, kind, nullable = unpackArgs(definition)
        result[key] = read(snapshot, object, method, path .. "." .. key, kind, nullable)
    end
    return result
end

local function each(snapshot, list, path, maximum, visit)
    local count = read(snapshot, list, "size", path .. ".size", "number")
    if not count then
        return
    end
    if count < 0 or count ~= math.floor(count) or count > maximum then
        issue(snapshot, path, "unsupported_list_size")
        return
    end
    for index = 0, count - 1 do
        local item = invoke(snapshot, list, "get", path .. "." .. index, index)
        if item == nil then
            issue(snapshot, path .. "." .. index, "missing_list_entry")
        else
            visit(item, index)
        end
    end
end

-- Native BodyDamage.save/load (42.21) provides this saved wound field list.
-- Additional read-only injury flags are retained too. Setter side effects mean
-- that matching names alone do not establish an equivalent restore sequence.
local partFields = {
    { "index", "getIndex", "number" },
    { "health", "getHealth", "number" },
    { "cut", "isCut", "boolean" },
    { "bitten", "bitten", "boolean" },
    { "scratched", "scratched", "boolean" },
    { "bandaged", "bandaged", "boolean" },
    { "bleeding", "bleeding", "boolean" },
    { "deepWounded", "deepWounded", "boolean" },
    { "fakeInfected", "IsFakeInfected", "boolean" },
    { "infected", "IsInfected", "boolean" },
    { "bandageLife", "getBandageLife", "number" },
    { "infectedWound", "isInfectedWound", "boolean" },
    { "woundInfectionLevel", "getWoundInfectionLevel", "number" },
    { "cutTime", "getCutTime", "number" },
    { "biteTime", "getBiteTime", "number" },
    { "scratchTime", "getScratchTime", "number" },
    { "bleedingTime", "getBleedingTime", "number" },
    { "alcoholLevel", "getAlcoholLevel", "number" },
    { "additionalPain", "getAdditionalPain", "number" },
    { "deepWoundTime", "getDeepWoundTime", "number" },
    { "glass", "haveGlass", "boolean" },
    { "bandageXp", "isGetBandageXp", "boolean" },
    { "stitched", "stitched", "boolean" },
    { "stitchTime", "getStitchTime", "number" },
    { "stitchXp", "isGetStitchXp", "boolean" },
    { "splintXp", "isGetSplintXp", "boolean" },
    { "fractureTime", "getFractureTime", "number" },
    { "splint", "isSplint", "boolean" },
    { "splintFactor", "getSplintFactor", "number" },
    { "bullet", "haveBullet", "boolean" },
    { "burnTime", "getBurnTime", "number" },
    { "needBurnWash", "isNeedBurnWash", "boolean" },
    { "lastBurnWash", "getLastTimeBurnWash", "number" },
    { "splintItem", "getSplintItem", "string", true },
    { "bandageType", "getBandageType", "string", true },
    { "wetness", "getWetness", "number" },
    { "stiffness", "getStiffness", "number" },
    { "comfrey", "getComfreyFactor", "number" },
    { "garlic", "getGarlicFactor", "number" },
    { "plantain", "getPlantainFactor", "number" },
    { "bleedingStemmed", "IsBleedingStemmed", "boolean" },
    { "cauterized", "IsCauterized", "boolean" },
}
local bodyFields = {
    { "health", "getOverallBodyHealth", "number" },
    { "infected", "isInfected", "boolean" },
    { "fakeInfected", "isIsFakeInfected", "boolean" },
    { "infectionTime", "getInfectionTime", "number" },
    { "infectionMortalityDuration", "getInfectionMortalityDuration", "number" },
    { "catchACold", "getCatchACold", "number" },
    { "hasCold", "isHasACold", "boolean" },
    { "coldStrength", "getColdStrength", "number" },
    { "sneezeTime", "getTimeToSneezeOrCough", "number" },
    { "reduceFakeInfection", "isReduceFakeInfection", "boolean" },
    { "healthFromFoodTimer", "getHealthFromFoodTimer", "number" },
    { "painReduction", "getPainReduction", "number" },
    { "coldReduction", "getColdReduction", "number" },
    { "coldDamageStage", "getColdDamageStage", "number" },
    { "onFire", "isIsOnFire", "boolean" },
}
local statNames = {
    "ANGER",
    "BOREDOM",
    "DISCOMFORT",
    "ENDURANCE",
    "FATIGUE",
    "FITNESS",
    "FOOD_SICKNESS",
    "HUNGER",
    "IDLENESS",
    "INTOXICATION",
    "MORALE",
    "NICOTINE_WITHDRAWAL",
    "PAIN",
    "PANIC",
    "POISON",
    "SANITY",
    "SICKNESS",
    "STRESS",
    "TEMPERATURE",
    "THIRST",
    "UNHAPPINESS",
    "WETNESS",
    "ZOMBIE_FEVER",
    "ZOMBIE_INFECTION",
}

local function captureCondition(snapshot, actor)
    local body = invoke(snapshot, actor, "getBodyDamage", "condition")
    snapshot.condition = fields(snapshot, body, "condition", bodyFields)
    snapshot.condition.parts = {}
    local parts = invoke(snapshot, body, "getBodyParts", "condition.parts")
    each(snapshot, parts, "condition.parts", 64, function(part, index)
        snapshot.condition.parts[index + 1] = fields(snapshot, part, "condition.parts." .. index, partFields)
    end)
    if #snapshot.condition.parts == 0 then
        issue(snapshot, "condition.parts", "no_body_parts")
    end
    snapshot.stats = {}
    local stats = invoke(snapshot, actor, "getStats", "stats")
    for _, name in ipairs(statNames) do
        local key = CharacterStat and CharacterStat[name]
        if key == nil then
            issue(snapshot, "stats." .. name, "stat_unavailable")
        else
            snapshot.stats[name] = read(snapshot, stats, "get", "stats." .. name, "number", false, key)
        end
    end
    local nutrition = invoke(snapshot, actor, "getNutrition", "nutrition")
    snapshot.nutrition = fields(snapshot, nutrition, "nutrition", {
        { "calories", "getCalories", "number" },
        { "carbohydrates", "getCarbohydrates", "number" },
        { "proteins", "getProteins", "number" },
        { "lipids", "getLipids", "number" },
        { "weight", "getWeight", "number" },
    })
end

local function captureIdentity(snapshot, actor)
    local descriptor = invoke(snapshot, actor, "getDescriptor", "descriptor")
    snapshot.descriptor = fields(snapshot, descriptor, "descriptor", {
        { "forename", "getForename", "string" },
        { "surname", "getSurname", "string" },
        { "female", "isFemale", "boolean" },
        { "voicePrefix", "getVoicePrefix", "string", true },
        { "voiceType", "getVoiceType", "number" },
        { "voicePitch", "getVoicePitch", "number" },
    })
    local profession = invoke(snapshot, descriptor, "getCharacterProfession", "descriptor.profession")
    snapshot.descriptor.profession = read(snapshot, profession, "getName", "descriptor.profession", "string")
    local visual = invoke(snapshot, actor, "getHumanVisual", "appearance")
    snapshot.appearance = {
        lastStand = read(snapshot, visual, "getLastStandString", "appearance.lastStand", "string"),
        nonAttachedHair = read(snapshot, visual, "getNonAttachedHair", "appearance.nonAttachedHair", "string", true),
        complete = false,
    }
    local traits = invoke(snapshot, actor, "getCharacterTraits", "traits")
    local known = invoke(snapshot, traits, "getKnownTraits", "traits.known")
    snapshot.traits = {}
    each(snapshot, known, "traits", 512, function(trait)
        local name = read(snapshot, trait, "getName", "traits.name", "string")
        if name then
            snapshot.traits[#snapshot.traits + 1] = name
        end
    end)
    snapshot.skills = {}
    local xp = invoke(snapshot, actor, "getXp", "skills")
    snapshot.totalXp = read(snapshot, xp, "getTotalXp", "totalXp", "number")
    each(snapshot, PerkFactory and PerkFactory.PerkList, "skills", 512, function(perk, index)
        local key = invoke(snapshot, perk, "getType", "skills." .. index .. ".type")
        local id = read(snapshot, perk, "getId", "skills." .. index .. ".id", "string")
        if key and id then
            snapshot.skills[#snapshot.skills + 1] = {
                id = id,
                level = read(snapshot, actor, "getPerkLevel", "skills." .. id .. ".level", "number", false, key),
                xp = read(snapshot, xp, "getXP", "skills." .. id .. ".xp", "number", false, key),
                boost = read(snapshot, xp, "getPerkBoost", "skills." .. id .. ".boost", "number", false, key),
                multiplier = read(
                    snapshot,
                    xp,
                    "getMultiplier",
                    "skills." .. id .. ".multiplier",
                    "number",
                    false,
                    key
                ),
            }
        end
    end)
end

-- Item IDs and nesting are witnesses only. The live engine containers remain
-- sole owners. This manifest never supplies enough data to recreate an item.

local function captureInventory(snapshot, actor)
    local result = { kind = "metadata-only", items = {}, worn = {}, attached = {}, complete = false }
    snapshot.inventory = result
    local seenObjects, seenIds, seenContainers = {}, {}, {}
    local count = 0
    local function itemId(item, path)
        local id = read(snapshot, item, "getID", path .. ".id", "number")
        if id and id ~= math.floor(id) then
            issue(snapshot, path, "invalid_item_id")
            return nil
        end
        return id
    end
    local function visitContainer(container, parentId, depth)
        if depth > 16 or seenContainers[container] then
            issue(snapshot, "inventory", "cyclic_or_deep_container")
            return
        end
        seenContainers[container] = true
        local items = invoke(snapshot, container, "getItems", "inventory.items")
        each(snapshot, items, "inventory.items", 4096, function(item)
            count = count + 1
            if count > 4096 then
                issue(snapshot, "inventory", "item_limit_exceeded")
                return
            end
            local path = "inventory.items." .. count
            local id = itemId(item, path)
            if seenObjects[item] or id and seenIds[id] then
                issue(snapshot, path, "duplicate_item")
                return
            end
            seenObjects[item] = true
            if id then
                seenIds[id] = true
            end
            local owner = invoke(snapshot, item, "getContainer", path .. ".owner")
            local ownerMatches = owner == container
            if not ownerMatches then
                issue(snapshot, path, "container_ownership_mismatch")
            end
            result.items[#result.items + 1] = {
                id = id,
                parentItemId = parentId,
                ownerMatches = ownerMatches,
                fullType = read(snapshot, item, "getFullType", path .. ".fullType", "string"),
            }
            local ok, bag = pcall(function()
                return instanceof(item, "InventoryContainer")
            end)
            if not ok then
                issue(snapshot, path, "container_type_unavailable")
            elseif bag then
                local nested = invoke(snapshot, item, "getInventory", path .. ".inventory")
                if nested and id then
                    visitContainer(nested, id, depth + 1)
                end
            end
        end)
    end
    local inventory = invoke(snapshot, actor, "getInventory", "inventory")
    if inventory then
        visitContainer(inventory, nil, 0)
    end
    local function equipped(item, path)
        if item == nil then
            return nil
        end
        local id = itemId(item, path)
        if not seenObjects[item] then
            issue(snapshot, path, "equipped_item_outside_inventory")
        end
        return id
    end
    result.primary = equipped(invoke(snapshot, actor, "getPrimaryHandItem", "inventory.primary"), "inventory.primary")
    result.secondary =
        equipped(invoke(snapshot, actor, "getSecondaryHandItem", "inventory.secondary"), "inventory.secondary")
    for _, slot in ipairs({ { "worn", "getWornItems" }, { "attached", "getAttachedItems" } }) do
        each(
            snapshot,
            invoke(snapshot, actor, slot[2], "inventory." .. slot[1]),
            "inventory." .. slot[1],
            128,
            function(entry, index)
                local path = "inventory." .. slot[1] .. "." .. index
                result[slot[1]][#result[slot[1]] + 1] = {
                    id = equipped(invoke(snapshot, entry, "getItem", path), path),
                }
                -- Worn locations are typed ItemBodyLocation in 42.21; capture
                -- no guessed string conversion. Slot restoration remains blocked.
            end
        )
    end
end

function State.capture(actor, personId, revision)
    if
        type(personId) ~= "string"
        or personId == ""
        or not isFinite(revision)
        or revision < 0
        or revision ~= math.floor(revision)
    then
        return { ok = false, code = "person_id_and_revision_required" }
    end
    local snapshot = {
        schema = State.VERSION,
        inspectedBuild = State.INSPECTED_BUILD,
        personId = personId,
        revision = revision,
        purpose = "diagnostic_observation",
        reconstructable = false,
        missing = {},
        unsupported = {
            "native_appearance_body_visuals_blood_dirt_holes",
            "typed_registry_restore_and_descriptor_extras",
            "xp_multiplier_bounds_and_exact_fractional_xp_restore",
            "thermoregulator_and_medication_history",
            "private_alcoholic_bandage_state",
            "body_part_restore_side_effects_and_critical_handover",
            "inventory_payload_and_live_transfer_transaction",
            "typed_equipment_slots_and_native_item_extensions",
            "controller_ownership_and_multiplayer_authority",
        },
    }
    snapshot.native = fields(snapshot, actor, "native", {
        { "health", "getHealth", "number" },
        { "dead", "isDead", "boolean" },
        { "npc", "isNpc", "boolean" },
        { "onlineId", "getOnlineID", "number" },
    })
    captureIdentity(snapshot, actor)
    captureCondition(snapshot, actor)
    captureInventory(snapshot, actor)
    return { ok = #snapshot.missing == 0, code = "diagnostic_observation_only", snapshot = snapshot }
end

-- Deliberately not an opt-in flag on a snapshot: callers cannot remove a list
-- entry or set reconstructable=true to authorize an unproved engine mutation.

function State.canReconstruct(_snapshot)
    return { ok = false, code = "faithful_native_reconstruction_unproven" }
end

return State
