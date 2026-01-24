GettingOldRegistry = {}

-- GOOD TRAITS
GettingOldRegistry.Young = CharacterTrait.register("GettingOld:young")
GettingOldRegistry.Adult = CharacterTrait.register("GettingOld:adult")

-- BAD TRAITS
GettingOldRegistry.Middle = CharacterTrait.register("GettingOld:middle")
GettingOldRegistry.Elderly = CharacterTrait.register("GettingOld:elderly")

require "shared/Tests_GettingOld"
