-- Original presentation adapter candidate for Build 42.21.
-- Requires the ProjectPeopleSilent sound definitions and additive AnimSets nodes.
-- This module creates no actors, registers no authority and changes no inventory
-- or bodily condition. The coordinator must configure every client replica.
ProjectPeople = ProjectPeople or {}
local ZombieVisual = { FLAG = "ProjectPeopleActor", VOICE_PREFIX = "ProjectPeopleSilent" }
ProjectPeople.ZombieVisual = ZombieVisual

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
    -- Preserve hair, worn items, bandages, blood, dirt and holes already present.
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
