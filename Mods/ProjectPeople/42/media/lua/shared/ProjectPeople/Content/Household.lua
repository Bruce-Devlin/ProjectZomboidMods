-- Authored household identity, not evidence of a native actor or medical state.
local Defaults = { HOUSEHOLD_ID = "household:starter", MAX_PARTICIPANTS = 20 }

function Defaults.household(home, characters)
    characters = characters or {}
    return {
        id = Defaults.HOUSEHOLD_ID,
        name = "The household",
        leaderId = "mara",
        home = home,
        people = {
            {
                id = "mara",
                name = "Mara",
                background = "A nurse who prefers a defensible home.",
                personality = {
                    caution = 75,
                    compassion = 90,
                    independence = 65,
                    sociability = 55,
                    conscientiousness = 90,
                    aggression = 10,
                },
                preferences = { baseOnly = true },
                attachment = 85,
                character = characters.mara or {},
            },
            {
                id = "owen",
                name = "Owen",
                background = "Mara's brother, a mechanic who protects his family.",
                personality = {
                    caution = 50,
                    compassion = 75,
                    independence = 50,
                    sociability = 35,
                    conscientiousness = 80,
                    aggression = 20,
                },
                preferences = { travelTrust = 20, protectCommunity = true },
                attachment = 80,
                character = characters.owen or {},
            },
            {
                id = "ellis",
                name = "Ellis",
                background = "A capable stranger with few ties to this household.",
                personality = {
                    caution = 35,
                    compassion = 45,
                    independence = 85,
                    sociability = 70,
                    conscientiousness = 45,
                    aggression = 15,
                },
                preferences = { travelTrust = 0, residentTrust = 15 },
                attachment = 15,
                character = characters.ellis or {},
            },
        },
        family = { firstId = "mara", secondId = "owen", relationship = "adult_sibling" },
    }
end
return Defaults
