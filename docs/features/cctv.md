---
title: CCTV
sidebar_position: 6
---

# CCTV

CCTV is a job for installing and servicing security systems. The CCTV company (the `Cctv.job` society) owns the installations recorded in the database, while customer businesses or homeowners pay for call-outs and repairs. The job also provides skill-check based hacking and repair checks against system IDs.

Files: `jobs/cctv/shared.lua` (config), `jobs/cctv/client.lua`, `jobs/cctv/server.lua`. Enabled by `Config.Cctv`. The CCTV client has no authority of its own: every action goes through server callbacks, which phone or management resources can also call (see [Events and callbacks](../events.md#cctv-callbacks)).

## Requirements

- A job named `cctv` (or whatever `Cctv.job` is set to) must exist in your job configuration. This resource does not create it.
- A society account for that job in kora_banking, and one for every customer business that requests call-outs.
- The CCTV tables are created automatically. See [Database](../database.md).

An "eligible engineer" has the `Cctv.job` job, is on duty when `requireOnDuty` is set, and has a grade of at least `minimumEngineerGrade`.

## Engineer laptop

The `cctv_laptop` item (name from `Cctv.laptopItem`) is registered automatically if it does not already exist, and made usable through kora_inventory.

When it is used:

1. The server checks the player is an eligible engineer. Otherwise the use fails with "You must be an on-duty CCTV engineer to use this laptop."
2. The server sends `kora_businesses:cctv:openLaptop` to the client.
3. The client fetches `kora_businesses:cctv:laptopData`, which re-checks eligibility and returns the systems from `kora_businesses_cctv_systems` whose `installer_business` is `Cctv.job`, plus all in-memory call-outs.
4. A kora_lib AppShell app (`kora_businesses:cctv-laptop`) opens with two searchable card lists: **Installed systems** and **Call-outs** (with a badge showing the number of call-outs).

The laptop is read-only: it lists systems and call-outs but has no buttons to accept or complete call-outs. Those actions are only available through the callbacks.

## Emergency call-outs

Customers request a call-out with the `kora_businesses:cctv:requestCallout` callback:

```lua
-- business customer
Kora.callback.trigger('kora_businesses:cctv:requestCallout', {
    customerType = 'business',
    business = 'businessName',
    issue = 'camera', -- or 'nvr'
    cameraId = 'camera-id',
    nvrId = 'nvr-id',
    coords = { x = 0.0, y = 0.0, z = 0.0 },
})

-- residential customer
Kora.callback.trigger('kora_businesses:cctv:requestCallout', {
    customerType = 'residential',
    citizenid = playerCitizenId, -- must be the requester's own citizenid
    issue = 'nvr',
})
```

The server checks, in order:

- Call-outs are enabled (`callouts.enabled`).
- `issue` is `camera` or `nvr`.
- The customer: for `business`, the requester's job name must equal `business` (max 50 characters); for `residential`, `citizenid` must be the requester's own.
- An eligible engineer is online, when `callouts.requireEngineerOnline` is set.
- The call-out charge (`callouts.charge`) can be taken: from the business society account through kora_banking, or from the homeowner's bank account.

The callback is rate-limited to 3 calls per 60 seconds. A successful request returns the new call-out with an ID like `cctv-<os.time>-<counter>` and status `open` (an engineer is online) or `pending` (none online; only possible when `requireEngineerOnline` is `false`).

Engineer actions:

| Callback | Effect |
| --- | --- |
| `kora_businesses:cctv:listCallouts` | Lists every call-out, including completed ones. |
| `kora_businesses:cctv:acceptCallout` | Assigns an `open` or `pending` call-out to the engineer (`accepted`). |
| `kora_businesses:cctv:declineCallout` | The assigned engineer hands it back (`open`). |
| `kora_businesses:cctv:completeCallout` | The assigned engineer completes it. The repair price (`repair.cameraPrice` or `repair.nvrPrice`) is charged to the customer's account, then the call-out charge plus the repair price are credited to the `Cctv.job` society. If the credit fails, the repair charge is refunded. Status becomes `completed`. |

Call-outs are kept in memory only. They are lost on restart, completed call-outs are never removed, and the `kora_businesses_cctv_callouts` table is not used yet. Use the `getCctvCallouts` [export](../exports.md) to read them from another server resource.

## Hacking

`/cctvhack <targetId>` (client command) or the `beginHack`/`finishHack` callbacks:

1. `kora_businesses:cctv:beginHack` checks that hacking is enabled, the target ID is a string of at most 80 characters, and the player has no hack in progress. No job is required.
2. The difficulty is based on the target's effective security level (`security_level + intrusion_level` from `kora_businesses_cctv_systems`, clamped to 1-10, or 1 if no row exists): `solutionsize` is `hacking.options.solutionsize + level - 1`.
3. The server authorises a `Kora.minigames` skill check for `hacking.skill` and `hacking.game` with those options, and moves the player to the private routing bucket `privateBucketBase + serverId`.
4. The client plays the minigame and sends the resulting proof to `kora_businesses:cctv:finishHack`.
5. The server restores the original routing bucket and verifies the proof with `Kora.minigames.consumeProof`, so the client cannot pick an easier puzzle or fake a success.
6. On success, `intrusion_level` of the target is set to `max(1, floor(skill level / 10))` (capped at 10), using the player's `hacking.skill` level from `Kora.skills.get`. The player is notified "Access granted".

The original bucket is restored on success, failure, expiry (`hacking.duration`, checked every 10 seconds) and disconnect. Each bucket change fires `kora_voice:server:bucketChanged`.

## Repair checks

`/cctvrepair <targetId>` (client command) or the `beginRepairCheck`/`finishRepairCheck` callbacks:

1. The player must be an eligible engineer and `repairChecks.enabled` must be set.
2. The server authorises a `repairChecks.game` (`circuit`) skill check for `repairChecks.skill` with `nodeCount = baseNodes + (level - 1) * nodesPerSecurityLevel` and a 30 second time limit, where `level` is the target's effective security level.
3. The client plays the minigame and sends the proof; the server verifies it and reports "Repair check passed". The session expires after `repairChecks.duration`.

A passed repair check does not change any data, complete a call-out or charge anyone; it only reports the result.

## Configuration

`Cctv` in `jobs/cctv/shared.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `job` | string | `'cctv'` | Engineer job name and the society account credited for work. |
| `laptopItem` | string | `'cctv_laptop'` | Engineer laptop item. |
| `requireOnDuty` | boolean | `true` | Engineers must be on duty. |
| `minimumEngineerGrade` | integer | `0` | Minimum job grade for engineer actions. |
| `hacking.enabled` | boolean | `true` | Allow hacking. |
| `hacking.skill` | string | `'crafting'` | kora_skills skill used for the skill check and the intrusion level. |
| `hacking.game` | string | `'hacking'` | kora_lib minigame. |
| `hacking.options` | table | `{ solutionsize = 4, timeLimit = 30000 }` | Minigame options; `solutionsize` grows with security level. |
| `hacking.privateBucketBase` | integer | `7000` | Private bucket is this plus the player's server ID. |
| `hacking.duration` | number (ms) | `120000` | Hack session lifetime. |
| `repairChecks.enabled` | boolean | `true` | Allow repair checks. |
| `repairChecks.skill` | string | `'computing'` | kora_skills skill used for the skill check. |
| `repairChecks.game` | string | `'circuit'` | kora_lib minigame. |
| `repairChecks.baseNodes` | integer | `4` | Circuit nodes at security level 1. |
| `repairChecks.nodesPerSecurityLevel` | integer | `1` | Extra nodes per security level above 1. |
| `repairChecks.duration` | number (ms) | `120000` | Repair check session lifetime. |
| `callouts.enabled` | boolean | `true` | Allow emergency call-outs. |
| `callouts.charge` | integer | `500` | Call-out charge taken from the customer at request time. |
| `callouts.requireEngineerOnline` | boolean | `true` | Reject requests when no eligible engineer is online. |
| `callouts.allowWhenSubscriptionSuspended` | boolean | `true` | Unused; reserved for subscription-state validation. |
| `repair.cameraPrice` | integer | `250` | Charge for completing a camera call-out. |
| `repair.nvrPrice` | integer | `750` | Charge for completing an NVR call-out. |

Amounts must be whole numbers from 0 to 1,000,000,000; an invalid charge or price makes the request or completion fail.

## Not implemented

The following are not part of the current code:

- Camera placement, world props and an installation workflow (nothing inserts into `kora_businesses_cctv_systems`).
- Live camera feeds.
- Damage, outages, motion detection and ANPR.
- Employee-level CCTV permissions beyond job, duty and grade.
- Persisting call-outs to the database.
- Accept, decline or complete buttons in the laptop UI.

## Known issues

- The laptop maps systems using `businessLabel` and `cameraCount`, but the query returns `business_label` and `camera_count`, so the business name is shown instead of the label and the camera count shows 0.
- The call-out charge is taken at request time and is not refunded if the call-out is never completed.
- For residential call-outs, the repair price is charged to the requester's server ID at completion; if that player has disconnected, the charge (and therefore the completion) is expected to fail.
