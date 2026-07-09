AgeSystem = AgeSystem or {}

AgeSystem.AgeTraits = {
    Zoomer = {
        CharacterTrait.DEXTROUS,
        CharacterTrait.FIT,
        CharacterTrait.GRACEFUL,
        CharacterTrait.FAST_LEARNER,
        CharacterTrait.JOGGER,
        CharacterTrait.NEEDS_MORE_SLEEP,
    },

    Young = {
        CharacterTrait.DEXTROUS,
        CharacterTrait.FIT,
        CharacterTrait.GRACEFUL,
        CharacterTrait.FAST_LEARNER,
        CharacterTrait.JOGGER,
        CharacterTrait.NEEDS_MORE_SLEEP,
    },

    Adult = {
        CharacterTrait.ORGANIZED,
        CharacterTrait.LOW_THIRST,
        CharacterTrait.HANDY,
        CharacterTrait.RESILIENT,
    },

    Middle = {
        CharacterTrait.SHORT_SIGHTED,
        CharacterTrait.HARD_OF_HEARING,
        CharacterTrait.SLOW_LEARNER,
        CharacterTrait.BRAVE,
        CharacterTrait.DESENSITIZED,
        CharacterTrait.NEEDS_LESS_SLEEP,
        CharacterTrait.WEIGHT_GAIN,
    },

    Elderly = {
        CharacterTrait.PRONE_TO_ILLNESS,
        CharacterTrait.SLOW_HEALER,
        CharacterTrait.DESENSITIZED,
        CharacterTrait.THIN_SKINNED,
        CharacterTrait.FAST_READER,
    },
}

function AgeSystem.getRandomAgeTrait(ageGroup)
    local traits = AgeSystem.AgeTraits[ageGroup]
    if not traits or #traits == 0 then
        return nil
    end

    return traits[ZombRand(#traits) + 1]
end

function AgeSystem.addRandomAgeTrait(player, ageGroup)
 DevTools.debugLog("Getting Old", "Adding random age trait...")
    if not player then
        DevTools.debugLog("Getting Old", "addRandomAgeTrait: player was nil")
        return
    end
    if not ageGroup then
        DevTools.debugLog("Getting Old", "addRandomAgeTrait: ageGroup was nil")
        return
    end

    local traits = player:getCharacterTraits()
    if not traits then
        DevTools.debugLog("Getting Old", "addRandomAgeTrait: character traits container was nil")
        return
    end

    local randAgeTrait = AgeSystem.getRandomAgeTrait(ageGroup)
    if not randAgeTrait then
        DevTools.debugLog(
            "Getting Old",
            "No age traits defined for group: " .. tostring(ageGroup)
        )
        return
    end

    if player:hasTrait(randAgeTrait) then
        DevTools.debugLog(
            "Getting Old",
            "Player already has age trait: " .. tostring(randAgeTrait)
        )
        return
    end

    traits:add(randAgeTrait)

    DevTools.debugLog(
        "Getting Old",
        "Added age trait: " .. tostring(randAgeTrait)
    )
end

function AgeSystem.removeNonFittingAgeTraits(player, ageGroup)
    DevTools.debugLog("Getting Old", "Removing inappropriate age traits...")

    if not player then 
        DevTools.debugLog("Getting Old", "Player was nil?")
        return 
    end

    if ageGroup == "Zoomer" or ageGroup == "Young" or ageGroup == "Adult" then return end

    local traits = player:getCharacterTraits()

    local groupsToRemove = {
        AgeSystem.AgeTraits.Zoomer,
        AgeSystem.AgeTraits.Young,
        AgeSystem.AgeTraits.Adult,
    }

    for _, groupTraits in ipairs(groupsToRemove) do
        for _, trait in ipairs(groupTraits) do
            if player:hasTrait(trait) then
                traits:remove(trait)
                DevTools.debugLog(
                    "Getting Old",
                    "Removed early-life trait: " .. tostring(trait)
                )
            end
        end
    end
end



