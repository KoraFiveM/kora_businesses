# CCTV — TL;DR

## What it is

CCTV is a `kora_businesses` job for installing and servicing business security
systems. The CCTV company owns the installations it creates, while customer
businesses pay for call-outs and repairs through society accounts.

## Configuration

Configuration lives in `jobs/cctv/shared.lua`:

```lua
Cctv = {
    job = 'cctv',
    laptopItem = 'cctv_laptop',
    requireOnDuty = true,
    minimumEngineerGrade = 0,
    callouts = {
        enabled = true,
        charge = 500,
        requireEngineerOnline = true,
        allowWhenSubscriptionSuspended = true,
    },
    repair = {
        cameraPrice = 250,
        nvrPrice = 750,
    },
}
```

- `job`: engineer job name.
- `laptopItem`: inventory item used by engineers.
- `requireOnDuty`: requires engineers to be clocked in.
- `minimumEngineerGrade`: minimum CCTV grade allowed to use engineer tools.
- `callouts.enabled`: enables emergency call-outs.
- `callouts.charge`: customer society call-out charge.
- `callouts.requireEngineerOnline`: rejects requests when no eligible engineer is online.
- `callouts.allowWhenSubscriptionSuspended`: reserved for subscription-state validation.
- `repair.cameraPrice`: charge for a camera repair.
- `repair.nvrPrice`: charge for an NVR repair.

## Residential customers

CCTV supports homeowners as well as businesses. Residential requests use
`customerType = 'residential'` and the requester's `citizenid`; charges come
from that player's bank account. Business requests use
`customerType = 'business'` and a configured business/job name.

## Hacking

Hacking uses `kora_skills` to adjust kora_lib's `hacking` minigame difficulty. The
server creates the authorization and consumes the proof, so clients cannot
choose an easier puzzle or report a fake success.

When a hack starts, the player is moved into a private routing bucket. The
original bucket is restored on success, failure, timeout, or disconnect.

The current test entry point is:

```text
/cctvhack <camera-or-nvr-id>
```

## Engineer laptop

The `cctv_laptop` item is registered automatically by `kora_businesses`.

When an eligible on-duty CCTV engineer uses it:

1. The server validates the engineer's job, duty state, and grade.
2. The server loads systems installed by the CCTV company.
3. kora_lib AppShell opens `kora_businesses:cctv-laptop`.
4. The engineer can view installed systems and service call-outs.

The laptop uses kora_lib callbacks, notifications, and AppShell. It does not
trust client-supplied job or installation data.

## Emergency call-outs

Businesses request call-outs through:

```lua
Kora.callback.trigger('kora_businesses:cctv:requestCallout', {
    business = 'businessName',
    issue = 'camera', -- or 'nvr'
    cameraId = 'camera-id',
    nvrId = 'nvr-id',
    coords = { x = 0.0, y = 0.0, z = 0.0 },
})
```

The server checks:

- Call-outs are enabled.
- The requester belongs to the requested business.
- The issue is `camera` or `nvr`.
- An engineer is online when `requireEngineerOnline` is enabled.
- The customer society can pay the call-out charge.

Successful requests are assigned a unique call-out ID and begin as `open` or
`pending`. Engineers use these callbacks:

```lua
kora_businesses:cctv:listCallouts
kora_businesses:cctv:acceptCallout
kora_businesses:cctv:declineCallout
kora_businesses:cctv:completeCallout
```

Completing a call-out charges the configured camera or NVR repair price. The
call-out and repair amount are credited to the CCTV society account through
`kora_banking`.

## Data and persistence

The tables are created at startup from the schema in `jobs/cctv/server.lua`
(`KoraBusinessesCctvSchema`, applied with `Kora.sql.ensureTables`). It covers:

- `kora_businesses_cctv_callouts`
- `kora_businesses_cctv_systems`

Call-out data is currently held in memory during runtime and the schema is
ready for full call-out hydration/persistence.

## kora_lib integration

The intended CCTV presentation layer uses:

- `Kora.camera` for live scripted CCTV views.
- kora_lib placement tools for installing cameras.
- kora_lib interactions/target integration for engineer actions.
- `Kora.callback` for server-authoritative requests.
- `Kora.nui.registerApp` and `Kora.nui.openApp` for AppShell.
- kora_lib notifications and progress UI for field work.

## Current status

Implemented:

- CCTV job registration.
- Engineer laptop item and AppShell dashboard.
- Installed-system dashboard query.
- Emergency call-out flow.
- Online-engineer requirement.
- Camera/NVR repair pricing.
- Customer and CCTV society billing.
- CCTV SQL schema.

Not yet implemented:

- Camera placement and world prop synchronisation.
- NVR/camera installation workflow.
- Live camera feeds through `Kora.camera`.
- Damage, destruction smoke, and network outages.
- Motion detection and ANPR.
- Employee-level CCTV permissions.
- Full persistent call-out hydration.
