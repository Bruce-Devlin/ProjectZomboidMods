# Project People

A standalone NPC mod for **Project Zomboid**, built around people with their own personalities, relationships and reasons to keep going.

Meet survivors, get to know them, share equipment and ask them to travel with you. Some are looking for company. Others have family to look after or a home they would rather defend. Cooperation depends on the person and what has happened between you.

**Target:** Build 42.21 · **Mod ID:** `ProjectPeople` · **Author:** Bruce Devlin

> Project People is in active development. The current build includes survivor encounters, conversation, companions and combat. The wider community, work and succession systems are still being developed.

## Features

### People worth getting to know

- Discover individual survivors and small groups as you explore.
- Learn their backgrounds, current plans and willingness to cooperate.
- Build directed trust through travelling together. Repeating a conversation does not earn recruitment rewards.
- See personalities, stress, exertion and concern for family influence their decisions.
- Deal with lasting reactions to help, threats and violence.

### Companions with their own priorities

- Invite willing survivors to travel with you or cooperate at home.
- Give follow, wait and base orders through the same interaction system.
- Travel as a group: available family members must all be willing and ready to join. Missing relatives do not block an invitation.
- Have companions follow your route, catch up when you pull ahead and stay closer during danger.
- Watch survivors take breaks, keep watch and check on companions during quiet moments.

### Equipment and survival

- Offer weapons, clothing and wearable bags as gifts before full trading is available.
- Trade and manage equipment once a survivor trusts you enough.
- Move original items, including bags and their contents, with normal carrying-capacity checks.
- Equip survivors for melee or firearm combat. Guns need real ammunition.
- Let survivors open suitable doors, cross fences and react to nearby threats.
- Control friendly fire for each friendly NPC. Protection from friendly player weapon hits is on by default; enabling friendly fire allows normal damage and relationship consequences.

### A changing population

Survivor encounters reflect the age of the outbreak and your sandbox settings. Groups have recorded identities and histories; revisiting an area does not reroll the people you have already met. Migration introduces different survivors rather than replacing those who died.

## Getting started

1. Install and enable **Project People** for a Build 42.21 world.
2. For a first development playthrough, use a fresh Sandbox world with the default Project People settings.
3. Explore the neighbourhood. Survivor encounters depend on suitable locations and population settings, so people will not appear on every street.
4. Approach a survivor and **right-click them**, or open the **People** button near the top-left of the screen.
5. Start with **Speak**. Ask about their thoughts, background, plans or trust before proposing cooperation.

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
| **Speak** | Ask about thoughts, background, plans and trust; listen, reassure or apologise where available. |
| **Cooperate** | Discuss travelling or helping at home, offer gifts, manage equipment and change friendly-fire preferences. |
| **Commands** | Direct survivors you are allowed to command, including follow, wait and base orders. |
| **Confront** | Threaten a survivor and face the resulting loss of trust. |

Gifts do not buy trust or grant access to someone else's inventory. Existing equipment is retained when a gift would duplicate what they already own. Trading normally requires **10 trust**.

## Sandbox settings

Look for the **Project People** page when configuring your world.

| Setting | Default | Effect |
| --- | --- | --- |
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
