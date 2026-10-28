# Working on Project People

Runtime code lives in `42/media/lua`. The client folder contains windows, menus and drawing. Shared code contains the rules, content and game adapters.

## Where to make changes

Paths below are relative to `42/media/lua/shared/ProjectPeople`.

| Change | File |
| --- | --- |
| Generated first names and surnames | `Content/Names.lua` |
| Backgrounds and group story lines | `Content/Stories.lua` |
| Spoken replies, chatter and wellbeing labels | `Content/Dialogue.lua` |
| Mara, Owen and Ellis | `Content/ReedHousehold.lua` |
| Generated household setups and individual resident dialogue/preferences | `Content/HouseholdTemplates.lua` |
| Household selection, saved dialogue and record validation | `Population/Households.lua` |
| What an idle person chooses to do, and in what order | `Behaviour/Plans.lua` |
| Rest, family concern, refusal and conversation thresholds | `Behaviour/Settings.lua` |
| Personality, strain, memories and social effects | `Behaviour/Mind.lua` |
| Conversation topics and reply selection | `Behaviour/Conversation.lua`, `Behaviour/Dialogue.lua` |
| Cooperation and trust progression | `Behaviour/Trust.lua`, `Behaviour/Groups.lua`, `Core.lua` |
| Follow spacing, trail size, catch-up and danger timers | `Pathing/Settings.lua` |
| Following, attention, group travel and storage-search routes | `Pathing/Movement.lua` |
| Detection, detours, risky approaches and escape | `Pathing/Locomotion.lua` |
| Combat approach positions and visibility | `Pathing/CombatSpace.lua` |
| Population stages, generation and story progression | `Population/Rules.lua` |
| Native encounter sites and population admission | `Population/Runtime.lua` |
| Doors, fences and actual body movement | `PeopleDoors.lua`, `PeopleFences.lua`, `PeopleBody.lua` |
| Weapons, clothing and original equipment | `PeopleWeapons.lua`, `PeopleClothing.lua`, `PeopleEquipment.lua` |
| First-strike follower assistance | `Behaviour/CompanionCombat.lua` |
| Companion health and care | `HealthService.lua`, client `HealthInterface.lua` |
| Building inspection destinations | `Pathing/Scavenging.lua` |
| New population birth equipment by outbreak age | `Population/Equipment.lua` |
| Window traversal order deferral | `PeopleWindows.lua` |
| Shared validation, plain tables, coordinates and stable hashing | `DevTools.lua` |
| Debug access, journalled cheats and native roster/spawning | `DebugAccess.lua`, `DebugRules.lua`, `DebugService.lua` |
| Debug console, location overlay and contextual cheats | client `DebugInterface.lua`, `InteractionMenu.lua` |
| Community home, active party capacity and allied NPC identity | `Party.lua`, `Core.lua`, `SurvivorService.lua`, `SurvivorRuntime.lua` |
| Resident roles, work/break clocks and original-item home chores | `HomeRoles.lua`, `HomeRuntime.lua`, `HomeResources.lua`, `HomeTasks.lua` |
| Per-player friendly NPC Alarmed/panic exemption | `PeopleAlarm.lua`, `SurvivorRuntime.lua` |
| Pinned party HUD and owner-visible home flag/placement | client `PartyInterface.lua`, `HomeInterface.lua` |

For example, change `Pathing/Settings.follow.gap` to tune ordinary follower spacing. Change `Behaviour/Settings.plans.restStrain` to tune when an idle person takes a break. To change the priority of checking on family versus resting, edit the explicit branches in `Behaviour/Plans.lua`. Keep the existing life, assignment and threat guards ahead of idle choices.

## How it fits together

`SurvivorRuntime` coordinates the game. It observes native bodies and players, asks behaviour and pathing for intentions, and sends validated decisions through the existing services. `PeopleBody` owns physical movement; plans never teleport or create people.

`SurvivorService` handles discovery, player requests and filtered views. `Authority` authenticates requests and journals accepted commands. `Core` owns persistent world records and command transactions. `Journal`, `SaveStore` and `Codec` handle storage. Native adapters keep engine objects and original items outside plain save records.

Content modules contain names and text. Behaviour modules choose actions and replies. Pathing modules choose routes and movement intentions. `DevTools` contains small reusable helpers and has no game events or dependencies. Keep feature rules out of the toolbox.

The old paths, such as `ProjectPeople/SurvivorMind`, forward to the new modules. Existing callers get the same module table. Edit the implementation in its folder; the forwarding files are only for compatibility. New code should require the folder path directly.

## Content and saves

Names are selected using stable seeds and list order. Adding or reordering names changes future generated names. Already saved people keep their identities and backgrounds. Story stage keys, person IDs, memory kinds and command names are persistent identifiers; changing their spelling needs a separate migration.

`Content/Stories.lua` contains 32 former-life cards. Keep each card's `before` line and its `details` together so a person's memories fit their former life. `incidents` holds separate solo/family accounts for outbreak, aftermath and long-term starts. Population chooses a personal card/detail and a shared group account using separate stable seed keys, then saves the complete background as text. Separation adds a final line instead of discarding that person's history. These memories do not grant professions, perks, equipment, map knowledge or quests.

`plans` describes one traveller; `familyPlans` applies when more than one living, available group member is present. Missing relatives stay unknown. Names use familiar unisex names/nicknames because native appearance is generated independently. Content changes load in a fresh game session and affect newly generated people; they do not rewrite old saved backgrounds. Shared small talk and Plans replies use the updated text when loaded. See [.agents/docs/npc-content.md](.agents/docs/npc-content.md) for the content pass and evidence limits.

New groups additionally use the sixteen setups in `Content/HouseholdTemplates.lua`, with shared histories/tensions, five stage plans and thirty-two individual adult roles. Resident entries hold thoughts, outlook, personal chatter, personality and real travel/residence preferences. Kin links belong only to family templates; non-family companions retain directed relationships and group membership. Keep wording consistent with the cooperation settings. For example, a person declining all travel needs a usable residence alternative. The `authoredCooperation` flag applies these new explicit thresholds; legacy generated people keep their previous trial-travel policy.

`Population/Households.lua` copies selected text into `group.household` at creation and reads that saved copy for conversations. Editing or removing a template affects future groups only. Do not recreate missing content from today's catalog, rewrite an old biography, or infer a missing person's whereabouts. Legacy groups without this optional record keep generic plans/dialogue. Speak actions are shared by the People panel and right-click menus. See [.agents/docs/households-and-dialogue.md](.agents/docs/households-and-dialogue.md) for the catalog and save rules.

Edit the content or settings, then start a fresh game session to load the changes. These files are not a hot-reload or client-settings system. Sandbox options still control each world's existing rates and population choices.

## Style and checks

Use four spaces, double quotes and blank lines between functions. Prefer descriptive local names and straightforward functions. Comments should explain a reason or an engine quirk. Preserve native authority checks, error codes, packet fields, save formats and random selection order during refactors.

The project uses [StyLua](https://github.com/JohnnyMorganz/StyLua) with `.stylua.toml` and Lua 5.1 syntax. With StyLua 2.6.0 or later on PATH:

```powershell
pwsh -File scripts/Format-Lua.ps1
pwsh -File scripts/Format-Lua.ps1 -Check
```

Pass `-StyLua <path-to-stylua.exe>` to use a local copy. The script formats runtime Lua only and verifies the parsed output before saving. It does not reorder requires.

Regression tests live in `.pztests`. `dev-tools.unit.lua` checks shared helper boundaries; `organisation.unit.lua` checks compatibility paths and that editing content/settings reaches the real selection code. Existing behaviour, pathing, population, equipment and authority suites remain the main regression coverage. Offline checks and syntax compilation do not replace native gameplay checks.

UI presentation: client `UITheme.lua` centralises native game colours and text fitting; `UIPortraits.lua` owns the bounded original-body animated model widgets used by `PartyInterface.lua`. Replaceable empty-party artwork is `42/media/textures/ProjectPeople/UI/party-camp.png`. See `.agents/docs/ui-style-and-portraits.md`.

Ambient overhead NPC chatter: edit `42/media/lua/shared/ProjectPeople/Content/AmbientDialogue.lua` (five pools). `Behaviour/AmbientDialogue.lua` schedules cosmetic local messages; `client/ProjectPeople/PeopleNames.lua` displays them above names. See `.agents/docs/ambient-dialogue.md` for selection, timing and verification limits.

Paired conversations: edit `42/media/lua/shared/ProjectPeople/Content/Conversations.lua` for complete ordered exchanges. `Behaviour/PairConversation.lua` selects passive nearby pairs and manages authority-owned turns/holds; `SurvivorRuntime.lua` integrates movement priority and replicates paired text through existing body records. See `.agents/docs/paired-conversations.md`.

Player-directed notice lines: `Content/PlayerAlerts.lua` is separate from self-talk and paired exchanges. `Behaviour/PlayerAlerts.lua` owns the authority's per-NPC/player-character approach/cooldown state. See `.agents/docs/player-notice-dialogue.md` for radius, timing and recipient-specific delivery.

`Behaviour/DialogueClock.lua` excludes simulation pauses from dialogue timing. `Runtime.dialogueViewAt` uses that clock; general `Runtime.viewAt` retains wall time for party/debug freshness. `PeopleNames.lua` separates visible names from nearby audible speech. Native shove/stomp selection and reactions remain in `PeopleCombat.lua`, with presentation in `PeopleBody.lua` and zombie/idle animation nodes. See `.agents/docs/npc-dialogue-navigation-combat-fixes.md`.

Trust awards use Behaviour/Trust through the authority-only Core `trust.reward` command. SurvivorService validates successful Speak requests; Behaviour/Commands shares their cooldown; EquipmentService records gifts inside its transfer adapter; HealthService records completed native treatment; SurvivorRuntime observes real player hits near active original NPC combat. Sandbox `TrustGainMultiplier` scales positive awards, including travel and helpful social events, while persisted relationship anchors bound repeats.
