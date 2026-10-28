# Project People

A standalone NPC mod for **Project Zomboid**, built around people with their own personalities, relationships and reasons to keep going.

Meet survivors, get to know them, share equipment and ask them to travel with you. Some are looking for company. Others have family to look after or a home they would rather defend. Cooperation depends on the person and what has happened between you.

**Target:** Build 42.21 · **Mod ID:** `ProjectPeople` · **Author:** Bruce Devlin

> Project People is in active development. The current build includes survivor encounters, conversation, companions and combat. The wider community, work and succession systems are still being developed.

## Features

### People worth getting to know

- Discover individual survivors and small groups as you explore.
- Learn their backgrounds, current plans and willingness to cooperate.
- Meet households with different histories and priorities: siblings, partners, cousins, neighbours, friends and temporary companions, with individual dialogue and cooperation choices.
- Nearby calm NPCs can pause for short, alternating overhead conversations. There are 32 exchanges, 150 solo self-talk lines and 40 player greetings. Nearby speech can be heard through walls and pauses with the game.
- Build directed trust through travelling together. Repeating a conversation does not earn recruitment rewards.
- See personalities, stress, exertion and concern for family influence their decisions.
- Deal with lasting reactions to help, threats and violence.

### Companions with their own priorities

- Invite willing survivors to travel with you or cooperate at home. Residents return to the Community Home and stay nearby between tasks.
- Give follow, wait and base orders through the same interaction system.
- Travel as a group: available family members must all be willing and ready to join. Missing relatives do not block an invitation.
- Have companions follow your route, catch up when you pull ahead and stay closer during danger.
- Watch survivors take breaks, keep watch and check on companions during quiet moments.

### Equipment and survival

- Offer weapons, clothing and wearable bags as gifts before full trading is available.
- Trade and manage equipment once a survivor trusts you enough.
- Move original items, including bags and their contents, with normal carrying-capacity checks.
- Equip survivors for melee or firearm combat. Guns need real ammunition. Survivors stagger zombies, push at close range and stomp ground targets.
- Let survivors open suitable doors, cross fences and react to nearby threats.
- Control friendly fire for each friendly NPC. Protection from friendly player weapon hits is on by default; enabling friendly fire allows normal damage and relationship consequences.

### A changing population

Survivor encounters reflect the age of the outbreak and your sandbox settings. Groups have recorded identities and histories; revisiting an area does not reroll the people you have already met. Migration introduces different survivors rather than replacing those who died.

## Getting started

1. Install and enable **Project People** for a Build 42.21 world.
2. For a first development playthrough, use a fresh Sandbox world with the default Project People settings.
3. Explore the neighbourhood. Survivor encounters depend on suitable locations and population settings, so people will not appear on every street.
4. Approach a survivor and **right-click them**, or open the **People** button near the top-left of the screen.
5. Start with **Speak**. Ask about their background, household, what matters to them, current plans or trust before proposing cooperation.

If someone refuses, their response should explain why. They may need rest, a safer situation, more trust or time to care for family. Conversation and equipment exchanges can also be unavailable while they are in immediate danger.

### Local installation

For a development package, copy `Contents/mods/ProjectPeople` from the extracted archive into your `Zomboid/mods` directory. On a standard Windows setup, the result should look like this:

```text
%UserProfile%/Zomboid/mods/ProjectPeople/
├── 42/
│   ├── mod.info
│   └── media/
└── common/
```

The `42` and `common` folders must sit directly inside `ProjectPeople`. Enable only one installed copy with mod ID `ProjectPeople`.

The mod has no required external mod framework. PZTools and the test harness are development tools, not player dependencies. This repository does not currently provide a published Workshop link.

## Interactions

The right-click menu and People panel use the same actions.

| Menu | What you can do |
| --- | --- |
| **Speak** | Ask about thoughts, background, household, personal priorities, plans and trust; make small talk, listen, reassure or apologise where available. |
| **Cooperate** | Discuss travelling or helping at home, offer gifts, manage equipment and change friendly-fire preferences. |
| **Commands** | Direct survivors you are allowed to command, including follow, wait and base orders. |
| **Confront** | Threaten a survivor and face the resulting loss of trust. |

Gifts do not buy trust or grant access to someone else's inventory. Existing equipment is retained when a gift would duplicate what they already own. Trading normally requires **10 trust**.

Right-click a nearby floor and choose **Set Community Home** before sending anyone home. Your local home flag marks the return point. **Commands > Return to Community Home** keeps that person recruited while freeing their active party place. Generated household refuges do not count as your home.

Residents receive balanced **Guard**, **Clean**, **Supply** and **Maintain** roles. Choose an individual role under **Commands > Home role**, or return them to automatic balancing. Guards patrol within ten tiles; cleaners remove blood and grime within eight. Suppliers collect real nearby supplies, fuel inactive generators, plant existing furrows and deliver materials to other residents. Maintainers repair surviving buildables and water/fertilise crops. Workers use unlocked, loaded containers on the home's floor within twenty tiles and put unused borrowed supplies away.

Work fills a random two-to-five-hour meter instead of following a schedule. Each full meter chooses one break: **Relax** for 30 game minutes, **Snack** for one hour, or **Sleep** for four hours. Relaxing residents wander, sit or talk; snack breaks use actual safe food. Sleep currently uses the floor pose near a suitable rest location. Orders and danger interrupt breaks; the remaining time resumes after return. Your person's profile shows their role, meter and break time. [Home work details and verification boundaries](.agents/docs/home-roles-and-breaks.md).

The **Party** button below **People** toggles a pinned roster with each active companion's status, health and direction. **Unpin** lets you drag it; **Pin** locks it and **Hide** closes it. Click a row to open that person's profile. The default party limit is **three**, including companions told to wait. A whole family must fit before anyone joins. Returning home frees places; lowering the sandbox limit never dismisses existing companions.

## Sandbox settings

Look for the **Project People** page when configuring your world.

| Setting | Default | Effect |
| --- | --- | --- |
| Maximum active followers per player | `3` | Limits travelling parties, including waiting companions. Whole groups must fit; returning home frees places. Range 1-40. |
| Enable Project People debug tools | Off | Grants the NPC roster, location markers, spawning and saved NPC cheats. On a server, enabling this grants access to every living player. |
| Populate the world with survivors | On | Allows new survivor groups. |
| Survivor population multiplier | `1.0` | Adjusts new population density. |
| Population over time | Modest migration | Choose declining, modest migration or more consistently inhabited population. |
| Days between migration opportunities | `30` | Minimum interval between regional arrival opportunities. |
| New survivor body admission limit | `20` | Pauses new body admission at the loaded-body limit across the world; does not delete existing people. |
| Additional outbreak age | `0` days | Adds to outbreak age when population is first initialised. |
| Continue distant survivor plans | On | Advances recorded escape, refuge, settlement and relocation plans. |
| Personal needs and reactions | On | Enables psychological needs and their effect on cooperation. |
| Quiet moments and companion visits | On | Enables idle breaks, watching and companion visits. |
| Exertion strain rate | `1.0` | Adjusts strain accumulation. |
| Danger stress rate | `1.0` | Adjusts continuous stress from danger. |
| Need for company rate | `1.0` | Adjusts loneliness accumulation. |
| Recovery from strain and stress | `1.0` | Adjusts psychological recovery during safe rest. |

Population changes preserve established people and their histories. Psychological recovery does not heal wounds or cure infection.

## NPC debug tools

Enable **Project People > Enable Project People debug tools** in Sandbox settings, then right-click the world and choose **Project People debug > Spawned NPCs and diagnostics**. Single-player `-debug` mode also grants access. Server roles with the native **Debug Context Menu** or **General Cheats** capability can use the tools while the sandbox switch is off. Multiplayer permissions are checked by the server for every action.

The console lists every currently spawned NPC reported by the authority, including people you have not met. Filter by name or persistent ID, select a person and use **Track selected** or **Show all markers** to locate them through walls or offscreen. The details show coordinates/floor, native ID, health, activity, commander, trust, strain/stress, group/outbreak stage and the normal travel/home decision. The saved-living count also includes people whose bodies are unavailable; those people are not listed as spawned.

Right-click an NPC and open **Project People debug**, or use **NPC actions** in the console, to set trust toward yourself, force recruitment, follow/wait/return home, release recruitment, calm/rest them, set high strain/stress, heal native injuries or set injury health to 25%. These cheats affect the selected NPC individually. Jobs, missions and transfers must finish first. Normal recruitment keeps its existing consent rules.

**Spawn NPCs** offers lone survivors and groups of two or three using the current world age, early outbreak (day 3), aftermath (day 60) or long-term (day 365) backgrounds and equipment. Groups retain the generator's family or companion ties. Console spawning searches near you; the world context menu searches near the clicked tile. Spawning needs loaded, free ground-floor squares within twelve tiles and respects the body admission limit. Debug spawns are new persistent identities with original finite equipment; an uncertain native birth remains reserved rather than being retried automatically.

Debug changes are saved. Health cheats change the native body's overall injury health; they do not model limb wounds or infection. The tools do not require the testing companion.

## Development status

The current development baseline is **Build 42.21**. Build 41 is not supported. Single-player and dedicated multiplayer have feature-specific testing; full multiplayer, hosted co-op and compatibility with other NPC mods are not established.

Work still includes:

- Reliable native body recovery across save/reload and reconnects.
- The complete supply-work and independent expedition journeys.
- Faithful continuation as a surviving group member after player death.
- Longer survival, crowded navigation and performance testing.

The full design aims for communities that outlast the player character. That is the direction of the project, rather than a claim that every part of that experience is finished.

## Working on the mod

See **[CODE.md](CODE.md)** for the code map, editing examples and formatting commands.

```text
42/media/lua/
├── client/ProjectPeople/          Windows, menus and drawing
└── shared/ProjectPeople/
    ├── Content/                  Names, stories, dialogue and households
    ├── Behaviour/                Personality, decisions and social rules
    ├── Pathing/                  Following, routes, detection and avoidance
    ├── Population/               Generation, admission and group progression
    ├── DevTools.lua              Common helpers
    ├── Core.lua                  World records and command transactions
    └── SurvivorRuntime.lua       Game coordination
```

Native body, equipment and persistence adapters also live under `shared/ProjectPeople`. Regression tests are in [`.pztests`](.pztests), and local package tooling is in [`scripts`](scripts).

Keep content edits in `Content`, tune behaviour and pathing in their respective `Settings.lua` files, and keep reusable utilities in `DevTools`. Existing public module paths remain available for compatibility.

## Reporting problems

When reporting a bug, include:

- The Project Zomboid build and Project People package or revision.
- Single-player, hosted co-op or dedicated-server mode.
- Relevant sandbox settings and other enabled mods.
- What you expected, what happened and how to reproduce it.
- Relevant log output, with screenshots or a short recording if the issue is visual.

For movement or encounter issues, include the location and whether you were indoors, near fences or doors, or being pursued. For missing survivors, mention whether the problem followed a save/reload or reconnect.



Trust also grows through conversations, fighting alongside NPCs, completed care and accepted equipment gifts. Set **Project People > Trust gain multiplier** in sandbox settings (default 1, range 0-10) to adjust positive trust gains. Each activity has a per-person/player cooldown; repeated menu clicks do not add more trust. Existing trust, fear and consent remain in place.
