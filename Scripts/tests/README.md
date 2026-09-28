# Getting Old regression checks

Run from the repository root with Lua 5.1 or newer:

```text
lua Scripts/tests/getting_old_regression.lua
```

The harness runs production Lua with mocked game APIs. It covers calendar anniversaries,
leap years, custom aging intervals, changes to custom year length, legacy progress,
NPC exclusion, per-character birthday dialogs, retry/acknowledgement handling,
server validation, reload greying, server player enumeration, hat replication and
warning ownership. It does not establish game-engine or mod compatibility.

## Timing contract

- With 365 days, birthdays use the selected calendar date. February 29 uses February
  28 in non-leap years. Starting age includes a birthday on the creation date.
- Other lengths override the calendar: the first birthday comes after a full
  configured interval of survived time, then repeats at that interval.
- Changes between custom lengths preserve partial progress and current age.
- Switching to 365 schedules the next calendar anniversary without changing age.
  Switching from 365 to a custom length starts a full custom interval.
- Existing accelerated saves retain their age and partial progress. Legacy saves
  entering calendar mode start with the next anniversary, without retroactive aging.
- Aging is checked hourly; a threshold is handled at the next hourly callback.

## In-game acceptance still required

- New and existing characters: select once, save/reload and reconnect without a repeat prompt.
- Week One: spawn NPCs before and after selection; only local human players get dialogs.
- Two clients and split-screen: independent choices, correct age/Health panel and recipient warnings.
- Verify visible hair/beard greying at ages 30, 55 and 80, including reload and remote visuals.
- With heart attacks enabled, verify speech, cause text and heartbeat before fatal damage.
  Verify separate old-age warnings with heart attacks disabled.

The reported stuck hat has not been reproduced; the change is preventive inventory
replication hardening, not a claim that its reported cause has been established.
