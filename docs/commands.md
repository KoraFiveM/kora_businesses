---
title: Commands and keybinds
sidebar_position: 4
---

# Commands and keybinds

## Commands

| Command | Side | Arguments | Permission / requirement | Effect |
| --- | --- | --- | --- | --- |
| `/cctvhack` | client (`RegisterCommand`) | `targetId` - CCTV system or device ID (max 80 characters) | none; `Cctv.hacking.enabled` must be `true` | Starts a server-authorised hacking minigame against the target, in a private routing bucket. On success the system's `intrusion_level` is updated. See [CCTV hacking](./features/cctv.md#hacking). |
| `/cctvrepair` | client (`RegisterCommand`) | `targetId` - CCTV system or device ID | on-duty CCTV engineer at or above `Cctv.minimumEngineerGrade`; `Cctv.repairChecks.enabled` must be `true` | Starts a server-authorised circuit minigame. The result is reported as a notification. See [CCTV repair checks](./features/cctv.md#repair-checks). |
| `/removestand` | server (`kora_core` `addCommand`) | none | kora_core permission `admin` | Deletes the nearest hotdog stand prop within 5 m of the admin. Only registered when the hotdog job is loaded, which it is not by default. See [Hotdog](./features/hotdog.md). |

Both CCTV commands do nothing when called without an argument. Chat suggestions for them are sent by the client on load and on `chat:init`, and by the server on `chat:init` and when the resource starts.

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
