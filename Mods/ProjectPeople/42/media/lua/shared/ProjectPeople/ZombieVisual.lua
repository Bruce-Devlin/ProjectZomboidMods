-- Original presentation adapter candidate for Build 42.21.
-- Requires the ProjectPeopleSilent sound definitions and additive AnimSets nodes.
-- This module creates no actors, registers no authority and changes no inventory
-- or bodily condition. The coordinator must configure every client replica.
ProjectPeople = ProjectPeople or {}
local ZombieVisual = { FLAG = "ProjectPeopleActor", VOICE_PREFIX = "ProjectPeopleSilent" }
ProjectPeople.ZombieVisual = ZombieVisual
local cleaned = setmetatable({}, { __mode = "k" })
local embedded = {
    "Axe Back",
    "Knife Stomach",
    "Knife Shoulder",
    "MeatCleaver in Back",
    "JawStab",
    "Stomach",
    "Knife in Back",
    "Knife Left Leg",
    "Knife Right Leg",
}

function ZombieVisual.sanitize(actor)
    if cleaned[actor] or not actor.getHumanVisual then
        return
    end
    local visual, md = actor:getHumanVisual(), actor:getModData()
    -- Factory zombie wounds are independent model layers, not the human skin.
    local layers = visual:getBodyVisuals()
    for i = layers:size() - 1, 0, -1 do
        local name = tostring(layers:get(i):getItemType())
        if name:find("ZedDmg", 1, true) or name:find("Bandage", 1, true) then
            -- Kahlua may choose ArrayList.remove(Object) for a numeric index.
            visual:removeBodyVisualFromItemType(name)
        end
    end
    for _, slot in ipairs(embedded) do
        local item = actor:getAttachedItem(slot)
        if item then
            actor:setAttachedItem(slot, nil)
            -- Retain original items as carried inventory; do not destroy or copy them.
            if not (isClient and isClient()) and not item:getContainer() then
                actor:getInventory():AddItem(item)
            end
        end
    end
    if not md.ProjectPeopleHumanAppearanceVersion or isClient and isClient() then
        visual:removeBlood()
    end
    if not (isClient and isClient()) then
        md.ProjectPeopleHumanAppearanceVersion = 1
    end
    actor:resetModelNextFrame()
    cleaned[actor] = true
end

local function applyHumanSkin(actor, skin)
    -- A SurvivorDesc is a human visual owner even when the actor is IsoZombie.
    -- Pin that human texture name: a numeric index alone selects zombie skin.
    local visual = actor:getHumanVisual()
    local descriptorVisual = actor:getDescriptor():getHumanVisual()
    local humanSkin = skin or descriptorVisual:getSkinTexture()
    if not humanSkin or humanSkin == "" then
        error "descriptor_has_no_human_skin"
    end
    actor:setSkeleton(false)
    visual:setSkinTextureName(humanSkin)
    actor:resetModel()
    return humanSkin
end

function ZombieVisual.configure(actor, skin)
    if not actor or not instanceof(actor, "IsoZombie") then
        return { ok = false, code = "isozombie_required" }
    end

    -- Required candidate behavior is intentionally not hidden by pcall.
    actor:setVariable(ZombieVisual.FLAG, true)
    actor:setUseless(true)
    actor:setNoTeeth(true)
    actor:setTarget(nil)

    local descriptor = actor:getDescriptor()
    local emitter = actor:getEmitter()
    local oldVoice, oldBite, oldHurt = actor:getVoiceSoundName(), actor:getBiteSoundName(), actor:getHurtSound()
    descriptor:setVoicePrefix(ZombieVisual.VOICE_PREFIX)
    actor:setHurtSound(ZombieVisual.VOICE_PREFIX .. "Hurt")
    emitter:stopSoundByName(oldVoice)
    emitter:stopSoundByName(oldBite)
    if oldHurt then
        emitter:stopSoundByName(oldHurt)
    end

    -- Appearance is optional to actor mechanics; expose failure to diagnostics.
    -- Preserve hair, worn equipment and genuine later combat marks.
    local appearanceOk, skinOrError = pcall(applyHumanSkin, actor, skin)
    return {
        ok = true,
        code = "visual_candidate_configured",
        runtimeVerified = false,
        flag = ZombieVisual.FLAG,
        wanderingSuppressed = actor:isUseless(),
        nativeBiteSuppressed = actor:isNoTeeth(),
        voiceSound = actor:getVoiceSoundName(),
        appearanceApplied = appearanceOk,
        skinTexture = appearanceOk and skinOrError or nil,
        appearanceError = not appearanceOk and tostring(skinOrError) or nil,
    }
end

return ZombieVisual
