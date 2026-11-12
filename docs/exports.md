---
title: Exports
sidebar_position: 5
---

# Exports

## Server

### getCctvCallouts

Returns the live, in-memory table of CCTV call-outs. Only available when the CCTV job is enabled.

```lua
local callouts = exports.kora_businesses:getCctvCallouts()
```

- Parameters: none.
- Returns: a table keyed by call-out ID (for example `cctv-1762862400-1`). Each value has the fields `id`, `customerType` (`business` or `residential`), `business`, `citizenid`, `issue` (`camera` or `nvr`), `cameraId`, `nvrId`, `coords`, `requester` (server ID), `charge`, `status` (`open`, `pending`, `accepted` or `completed`), `engineer` (server ID or `nil`) and, once completed, `repairPrice`.

The table is returned by reference, so changes made by the caller affect the resource's state. Call-outs are not persisted and are lost on restart. See [CCTV call-outs](./features/cctv.md#emergency-call-outs).

```lua
for id, callout in pairs(exports.kora_businesses:getCctvCallouts()) do
    if callout.status == 'open' then
        print(id, callout.issue, callout.business or callout.citizenid)
    end
end
```

## Client

The resource registers no client exports.

## Callbacks

Other resources integrate with the CCTV job through `Kora.callback` callbacks rather than exports. These are documented in [Events and callbacks](./events.md#cctv-callbacks).
