-- Authored household identity, not evidence of a native actor or medical state.
local ReedHousehold = { HOUSEHOLD_ID = "household:starter", MAX_PARTICIPANTS = 20 }

function ReedHousehold.household(home, characters)
    characters = characters or {}
    return {
        id = ReedHousehold.HOUSEHOLD_ID,
        name = "The Reed household",
        leaderId = "mara",
        home = home,
        people = {
            {
                id = "mara",
                name = "Mara Reed",
                background = "I was a nurse. I used to come home after a late shift and sit in the kitchen without turning the light on. Owen is my brother; he'd leave the radio low so I could sleep. He thinks we should keep our options open. I want a home with doors we can secure and a reason to unpack. I'm willing to help here, but I'm not leaving with a travelling group.",
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
                name = "Owen Reed",
                background = "I worked in a garage. Mara, my sister, used to bring her car in and tell me the noise had gone away as soon as she turned into the yard. We had Sunday dinner whenever our shifts lined up. Now she wants to make this place home, and I want to know there's a way out. I could travel with someone I trust, but I need to know she'll be safe here first.",
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
                name = "Ellis Walker",
                background = "I delivered furniture before this. I used to spend all day carrying things into other people's homes, then go back to a rented room of my own. I met Mara and Owen after I left the main road. They're decent people, but this isn't my home. I'd rather share the road for a while than promise to settle somewhere I hardly know.",
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
return ReedHousehold
