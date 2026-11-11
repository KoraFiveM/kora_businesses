---
title: Events and callbacks
sidebar_position: 6
---

# Events and callbacks

The jobs communicate through `Kora.callback` callbacks (triggered from the client with `Kora.callback.trigger`) and a few net events. Unless a section says otherwise, these are internal to the job flows: the server validates the player's job, distance and session state, so triggering them from other resources has no useful effect and should not be done.

Several jobs keep their legacy `qb-` names for callbacks and events.

## CCTV callbacks

These server callbacks are the integration surface for phone, management or business resources. The CCTV client file states that other resources consume them. All are triggered from client code.

| Callback | Arguments | Returns | Who may call |
| --- | --- | --- | --- |
| `kora_businesses:cctv:requestCallout` | `data` table: `customerType` (`business` or `residential`), `business` (business customers), `citizenid` (residential customers), `issue` (`camera` or `nvr`), optional `cameraId`, `nvrId`, `coords` | `true, callout` or `false, message` | a member of the business (job name equals `business`) or the homeowner (own `citizenid`); rate-limited to 3 calls per 60 seconds |
| `kora_businesses:cctv:listCallouts` | none | list of all call-outs, or an empty list | eligible CCTV engineers |
| `kora_businesses:cctv:laptopData` | none | `{ systems, callouts, company }` or `nil, message` | eligible CCTV engineers |
| `kora_businesses:cctv:acceptCallout` | call-out ID | `true, callout` or `false, message` | eligible CCTV engineers; call-out must be `open` or `pending` |
| `kora_businesses:cctv:declineCallout` | call-out ID | `true, callout` or `false, message` | the engineer who accepted it; sets it back to `open` |
| `kora_businesses:cctv:completeCallout` | call-out ID | `true, callout` or `false, message` | the engineer who accepted it; charges the repair and pays the CCTV society |
| `kora_businesses:cctv:beginHack` | `{ targetId }` | `true, { authorization, bucket }` or `false, message` | any player |
| `kora_businesses:cctv:finishHack` | `{ proof }` | `true, { targetId }` or `false, message` | the player who began the hack |
| `kora_businesses:cctv:beginRepairCheck` | `{ targetId }` | `true, { authorization }` or `false, message` | eligible CCTV engineers |
| `kora_businesses:cctv:finishRepairCheck` | `{ proof }` | `true, { targetId }` or `false, message` | the player who began the check |

"Eligible CCTV engineer" means job `Cctv.job`, on duty when `Cctv.requireOnDuty` is set, and grade at least `Cctv.minimumEngineerGrade`.

Example (client):

```lua
local ok, result = Kora.callback.trigger('kora_businesses:cctv:requestCallout', {
    customerType = 'business',
    business = 'burgershot',
    issue = 'camera',
    cameraId = 'burgershot-cam-1',
    coords = GetEntityCoords(PlayerPedId()),
})
if not ok then
    print(result) -- error message
end
```

The begin and finish hack/repair callbacks must be used together with `Kora.minigames.play` and the returned `authorization`, as `/cctvhack` and `/cctvrepair` do; see [CCTV](./features/cctv.md).

### CCTV net events

| Event | Direction | Payload | Notes |
| --- | --- | --- | --- |
| `kora_businesses:cctv:openLaptop` | server to client | none | Sent when an eligible engineer uses the `cctv_laptop` item. Opens the laptop app. |

## Mechanic

| Name | Type | Direction | Payload | Notes |
| --- | --- | --- | --- | --- |
| `kora_businesses:mechanic:permit` | callback | client to server | `action` (`fullRepair`, `roadsideRepair`, `paint`, `bumpers`), vehicle `netId` | Returns `true, permitId` or `false, reason`. Rate-limited by `Mechanic.interaction.permitRateLimit`. Internal. |
| `kora_businesses:server:serviceCompleted` | net event | client to server | `permitId`, `payload` | Consumes the single-use permit, re-validates and removes the configured item. Internal. |
| `kora_businesses:client:serviceApplied` | net event | server to client | `action`, `netId`, `payload` | Applies the repair or cosmetic change on the client. Internal. |

## Taxi

| Name | Type | Direction | Payload | Notes |
| --- | --- | --- | --- | --- |
| `qb-taxi:getPickupLocation` | callback | client to server | none | Returns `{ pickup, dropoff }` for a taxi-job player, otherwise `nil`. Internal. |
| `qb-taxi:pickup` | net event | client to server | none | Marks the pickup complete (player within 5 m of the pickup). Internal. |
| `qb-taxi:dropOff` | net event | client to server | none | Pays the fare (player within 5 m of the destination, pickup completed). Internal. |
| `qb-taxi:client:spawnPickup` | net event | server to client | none | Starts the next fare. Ignored unless sent by the server. |

## Garbage

All internal; triggered by the garbage client.

| Callback | Arguments | Purpose |
| --- | --- | --- |
| `qb-garbagejob:spawnTruck` | none | Starts a route for a `garbage` player and returns it (list of `{ stop, bags }`). |
| `qb-garbagejob:setTruck` | vehicle `netId` | Registers the spawned truck (model `Garbage.Vehicle`, within 30 m) and gives `GARBAGE` keys. |
| `qb-garbagejob:collectBag` | stop ID | Counts a bag picked up at the current stop (within 4 m of the bin). |
| `qb-garbagejob:depositBag` | stop ID | Counts a bag thrown into the truck (within 6 m of the truck). |
| `qb-garbagejob:completeStop` | route index | Advances the route once all bags were collected and deposited. |
| `qb-garbagejob:returnTruck` | vehicle `netId` | Pays the route and deletes the truck when all stops are done and the truck is back at the depot. |
| `qb-garbagejob:cancel` | none | Cancels the route and deletes the truck. |

## Recycle

All internal; triggered by the recycle client.

| Name | Type | Direction | Payload | Purpose |
| --- | --- | --- | --- | --- |
| `kora_businesses:recycle:getPriceList` | callback | client to server | none | Returns the item-to-price map when within 5 m of the sell ped, else `false`. |
| `kora_businesses:recycle:pickupPackage` | callback | client to server | pickup index | Authorises carrying a package (within 3 m of the pallet); returns `{ networked }`. |
| `kora_businesses:recycle:cancelPickup` | net event | client to server | none | Releases the pending package authorisation. |
| `kora_businesses:recycle:getItem` | net event | client to server | none | Redeems a carried package for materials at the hand-in point. |
| `kora_businesses:recycle:sellItem` | net event | client to server | `item`, `amount` | Sells materials at the sell ped. |

## Tow

All internal; triggered by the tow client.

| Callback | Purpose |
| --- | --- |
| `qb-tow:server:TakeOutVehicle` | Starts a tow shift for a `tow` player at the yard, gives `TOW` keys and returns `{ location, droppedOff, hasPickedUp }`. |
| `qb-tow:server:pickUp` | Confirms the player is within 10 m of the current tow spot. |
| `qb-tow:server:DropOff` | Counts a delivered vehicle at the yard and returns the next location. |
| `qb-tow:server:ReturnVehicle` | Pays `droppedOff * Tow.payPerVehicle` to the bank, ends the shift and removes the keys. |

The tow client also triggers `qb-tow:server:CheckDistance`, which is not registered by the server. See [Tow known issues](./features/tow.md#known-issues).

## Hotdog (not loaded)

These are only registered when the hotdog job is loaded. See [Hotdog](./features/hotdog.md).

| Name | Type | Direction | Notes |
| --- | --- | --- | --- |
| `qb-hotdogjob:startWorking` | callback | client to server | Takes the stand deposit. Internal. |
| `qb-hotdogjob:stopWorking` | callback | client to server | Refunds the deposit. Internal. |
| `qb-hotdogjob:beginPreparing` | callback | client to server | Authorises the `keys` minigame. Internal. |
| `qb-hotdogjob:finishPreparing` | callback | client to server | Verifies the proof and adds stock. Internal. |
| `qb-hotdogjob:sell` | callback | client to server | Sells stock to a nearby ped. Internal. |
| `qb-hotdogjob:client:ToggleSell` | net event | to client | Toggles selling mode. |
| `qb-hotdogjob:client:UpdateReputation` | net event | to client | Stores `jobRep` in the cached player metadata and refreshes the UI. |
| `qb-hotdogjob:staff:DeletStand` | net event | server to client | Sent by `/removestand`; deletes the nearest stand. |

## Events this resource listens to

| Event | Side | Used by |
| --- | --- | --- |
| `QBCore:Client:OnPlayerLoaded` | client | garbage, tow, hotdog (blips and cached player data) |
| `QBCore:Client:OnJobUpdate` | client | garbage (cancels the route when leaving the job), tow (blip) |
| `QBCore:Client:OnPlayerUpdated` | client | hotdog |
| `QBCore:Server:OnPlayerUnload` | server | taxi, recycle (clear session state) |
| `playerDropped` | server | all jobs (clear session state; CCTV restores the routing bucket) |
| `chat:init` | client and server | CCTV command suggestions |

## Events this resource fires

| Event | Side | Payload | Notes |
| --- | --- | --- | --- |
| `kora_voice:server:bucketChanged` | server (local `TriggerEvent`) | player server ID | Fired whenever the CCTV hack moves a player into or out of a private routing bucket. |
| `chat:addSuggestion` | client and server | command, help, params | Suggestions for `/cctvhack` and `/cctvrepair`. |
