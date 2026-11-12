---
title: "Commands"
sidebar_position: 4
---


# Commands

Only two chat/console commands are registered directly by this resource's loaded jobs (both from the CCTV job); the hotdog job registers a third (`/removestand`) but is not loaded by default — see Installation.

## Built-in commands

### `/cctvhack <targetId>`

Starts the CCTV intrusion minigame against the installed system with that id. Difficulty scales with the target system's combined security/intrusion level.

| Field | Details |
| --- | --- |
| Context | In-game · client command (RegisterCommand) |
| Arguments | targetId — required, the CCTV system's id string (as shown in the engineer laptop app or known out of band). |
| Access | No client-side restriction beyond knowing a valid id; the server only requires `Cctv.hacking.enabled` to be true. There is no job or duty check on who may attempt a hack. |

**Example**

```text
/cctvhack kora_businesses_system_12
```

**Result**

Runs the configured minigame (`Cctv.hacking.game`, default `hacking`) and reports success/failure as a CCTV notification.

### `/cctvrepair <targetId>`

Starts the CCTV repair-check minigame against a system. Unlike completing a call-out, this does not charge or pay anyone and does not change call-out status by itself.

| Field | Details |
| --- | --- |
| Context | In-game · client command (RegisterCommand) |
| Arguments | targetId — required, the CCTV system's id string. |
| Access | No client-side restriction. The server callback `kora_businesses:cctv:beginRepairCheck` requires an on-duty CCTV engineer (`playerJob`, at or above `Cctv.minimumEngineerGrade`) and `Cctv.repairChecks.enabled`. |

**Example**

```text
/cctvrepair kora_businesses_system_12
```

**Result**

Runs the configured minigame (`Cctv.repairChecks.game`, default `circuit`) and reports pass/fail.

## /removestand (hotdog, not loaded by default)

`jobs/hotdog/server.lua` registers `/removestand` through `exports.kora_core:addCommand('removestand', 'Delete Stand (Admin Only)', {}, false, handler)`. Since the hotdog job is not required by `config.lua` in a stock install (see Installation), this command does not exist unless you wire the job up yourself. The access level implied by kora_core's `addCommand` signature was not verified here — check kora_core's own documentation before relying on the "Admin Only" label.

The registration passes the kora_core permission `admin` as its last argument (`jobs/hotdog/server.lua:134`). The command deletes the nearest hotdog stand prop within 5 m of the admin. See [Hotdog](./features/hotdog.md).

## Additional details

Both CCTV commands do nothing when called without an argument, and `targetId` is limited to 80 characters. Chat suggestions for them are sent by the client on load and on `chat:init`, and by the server on `chat:init` and when the resource starts. Hacking runs in a private routing bucket; see [CCTV hacking](./features/cctv.md#hacking) and [CCTV repair checks](./features/cctv.md#repair-checks).

## Keybinds

| Name | Default key | Effect |
| --- | --- | --- |
| `letgostand` | `G` | Let go of the hotdog stand while pushing it. Registered with `Kora.keybind.add`; only exists when the hotdog job is loaded. |

## Interactions

Most jobs are driven by target or interaction options rather than commands. These are listed on each feature page:

- [Mechanic](./features/mechanic.md#usage) - vehicle options via `kora_target`.
- [Taxi](./features/taxi.md#usage) - depot box zone via `Kora.interact`.
- [Garbage](./features/garbage.md#usage) - depot ped, bins and truck via `kora_target`.
- [Recycle](./features/recycle.md#usage) - warehouse zones, pallets and sell ped via `kora_target`.
- [Tow](./features/tow.md#usage) - tow yard zone via `Kora.interact`, towed vehicle via `kora_target`.
- [CCTV](./features/cctv.md#engineer-laptop) - the usable `cctv_laptop` item.
