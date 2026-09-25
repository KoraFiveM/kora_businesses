# CCTV — TL;DR

## What it is

CCTV is a `qbbusinesses` job for installing and servicing business security
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

## Engineer laptop

The `cctv_laptop` item is registered automatically by `qbbusinesses`.

When an eligible on-duty CCTV engineer uses it:

1. The server validates the engineer's job, duty state, and grade.
2. The server loads systems installed by the CCTV company.
3. qblib AppShell opens `qbbusinesses:cctv-laptop`.
4. The engineer can view installed systems and service call-outs.

The laptop uses qblib callbacks, notifications, and AppShell. It does not
trust client-supplied job or installation data.

## Emergency call-outs

Businesses request call-outs through:

```lua
QB.callback.trigger('qbbusinesses:cctv:requestCallout', {
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
qbbusinesses:cctv:listCallouts
qbbusinesses:cctv:acceptCallout
qbbusinesses:cctv:declineCallout
qbbusinesses:cctv:completeCallout
```

Completing a call-out charges the configured camera or NVR repair price. The
call-out and repair amount are credited to the CCTV society account through
`qbbanking`.

## Data and persistence

The SQL migration is:

```text
sql/001_cctv_callouts.sql
```

It creates tables for:

- `qbbusinesses_cctv_callouts`
- `qbbusinesses_cctv_systems`

Call-out data is currently held in memory during runtime and the schema is
ready for full call-out hydration/persistence.

## qblib integration

The intended CCTV presentation layer uses:

- `QB.camera` for live scripted CCTV views.
- qblib placement tools for installing cameras.
- qblib interactions/target integration for engineer actions.
- `QB.callback` for server-authoritative requests.
- `QB.nui.registerApp` and `QB.nui.openApp` for AppShell.
- qblib notifications and progress UI for field work.

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
- Live camera feeds through `QB.camera`.
- Damage, destruction smoke, and network outages.
- Motion detection and ANPR.
- Employee-level CCTV permissions.
- Full persistent call-out hydration.
