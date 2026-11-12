---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora Businesses has no shared UI or menu of its own: each job is a separate gameplay loop built from `kora_target`/`kora_lib` interact zones, server callbacks (`Kora.callback.register`) and, for cctv/recycle, a `kora_lib` NUI app. Players join a job the normal kora_core way (job assigned elsewhere); this resource only reacts to the job name on `getJob`/`getPlayerData`.

## CCTV engineer

- Job name `cctv` (`Cctv.job`). On-duty staff (`Cctv.requireOnDuty = true` by default) of at least `Cctv.minimumEngineerGrade` (0) can use the `cctv_laptop` item, which the resource self-registers if it does not already exist (`Kora.shared.register('items', ...)`).
- Any player can request an emergency call-out from home (residential, verified by citizen ID) or from their own business (verified by job name matching the business name) through `kora_businesses:cctv:requestCallout`, paying `Cctv.callouts.charge` (500) up front if `Cctv.callouts.requireEngineerOnline` finds an eligible on-duty engineer online.
- An online engineer accepts the call-out (`acceptCallout`) and completes it (`completeCallout`), which charges the repair price (`Cctv.repair.cameraPrice` 250 or `nvrPrice` 750) to the same customer account and pays the call-out charge plus the repair price into the `cctv` job's bank account via `exports.kora_banking:AddMoney`. If crediting the company fails, the customer is refunded.
- `/cctvhack <targetId>` and `/cctvrepair <targetId>` are client commands engineers (or anyone who knows a system id) type to run the hacking minigame (`Cctv.hacking`, skill `crafting`) or the repair-check minigame (`Cctv.repairChecks`, skill `computing`) against an installed system, using `Kora.minigames` for server-authorised proof. A successful hack raises the target system's `intrusion_level`; there is no documented reader of `intrusion_level` on the player side in the files read for this page beyond `systemSecurity`, which feeds difficulty back into later hacks and repair checks.
- Persistence: `kora_businesses_cctv_callouts` and `kora_businesses_cctv_systems` are created with `Kora.sql.ensureTables` on boot (additive only). No seed data is written for `kora_businesses_cctv_systems`; another resource (an installer/business feature) is expected to insert rows there.

## Garbage collector

- Job name `garbage`. A ped at `Garbage.Peds` offers `Start Garbage Route` to on-duty-less-checked players whose job is `garbage` and who have no truck out. The server (`qb-garbagejob:spawnTruck`) builds a randomised route of `Garbage.MinStops`-`Garbage.MaxStops` (5–6) trashcan stops out of `Garbage.Locations.trashcan`, each with `Garbage.MinBagsPerStop`-`Garbage.MaxBagsPerStop` (1–4) bags.
- The client spawns a `Garbage.Vehicle` (`trash2`) truck at a random `Garbage.Locations.vehicle` spawn and registers its network id with the server (`setTruck`), which checks the model, that it is within 30 m of the depot NPC, and that no truck is already registered for that player; `exports.kora_vehiclekeys:giveKeys(source, 'GARBAGE')` is then called (wrapped in `pcall`, so a missing `kora_vehiclekeys` export degrades silently).
- At each stop the player grabs a bag (`collectBag`, must be within 4 m of the trashcan) and throws it in the truck (`depositBag`, must be within 6 m of the truck); a stop completes (`completeStop`) once picked-up and deposited bag counts both equal that stop's bag count, advancing `routeIndex`.
- Returning the truck within `Garbage.ReturnDistance` (10 m) of both the truck and the depot (`returnTruck`) pays `stops * 50` to the player's bank via `exports.kora_core:addMoney`, then deletes the truck server-side and clears the job state. If the payment call fails the truck is not deleted and the route is not cleared.
- `Config.GarbageDepotRoute` (true) draws a GPS waypoint back to the depot once every stop is finished; it only affects the client-side blip routing, not payment.

## Hotdog vendor (inactive by default — see Installation)

- Job name `hotdog`. Starting work (`qb-hotdogjob:startWorking`) charges a `Hotdog.StandDeposit` (250) deposit from the player's bank, refunded in full on `stopWorking`.
- Preparing a hot dog runs a server-authorised proof (`Kora.minigames.authorizeProof(src, 'keys', { amount = Hotdog.PrepareMinigameKeys })`, 10 key presses) then rolls a quality (`common`/`rare`/`exotic`) by `Hotdog.PrepareRewards` chance (70/25/5) and grants `Hotdog.batchSize(level, rarity)` hot dogs of that quality, capped by that quality's per-level stock cap (`Hotdog.Stock[quality].Max`), and awards `cooking` skill XP (`Hotdog.PrepareXp`).
- Selling (`qb-hotdogjob:sell`) requires the buyer NPC within `Hotdog.SaleDistance` (4.0 m), consumes stock of the chosen quality/amount, and pays cash at a random per-unit price inside that quality/level's `Hotdog.Stock[quality].Price` range, again awarding `cooking` XP (`Hotdog.SaleXp`).
- `/removestand` is registered via `exports.kora_core:addCommand('removestand', ..., {}, false, ...)` and triggers `qb-hotdogjob:staff:DeletStand` on the target client. The exact permission level this grants is set by kora_core's command system and was not verified against kora_core's source for this page — unclear whether it is admin-only or open to every player; the locale label (`Delete Stand (Admin Only)`) suggests intent but is not itself an access check.

## Mechanic / bodyshop

- No job name is hard-coded except `Mechanic.roles.fullRepairJob = 'mechanic'`. Any job whose name is `mechanic` or whose job `type` equals `Mechanic.roles.automotiveType` (`automotive`) can repair; `Mechanic.roles.roadsideJobs` (`{ roadside = true }`) names jobs limited to roadside stabilisation only; `Mechanic.roles.bodyshopJobs`/`bodyshopTypes` (`{ bodyshop = true }`) gate paint and bumper work. Staff must be on duty (`Mechanic.roles.requireOnDuty`).
- Flow: target a vehicle, the client asks the server for a time-limited permit (`kora_businesses:mechanic:permit`, action + vehicle network id) which re-checks role, proximity (`Mechanic.interaction.distance`, 3.0 m) and, for a full repair, that the vehicle is within `Mechanic.fullRepair.garageRadius` (12 m) of one of `Mechanic.fullRepair.garages`. The client then runs a progress bar and, on completion, sends the permit id back (`kora_businesses:server:serviceCompleted`); the server re-validates everything (permit not expired/reused, role, vehicle, payload shape) before telling the client to apply the result.
- Full repair sets the vehicle to fully fixed (health, deformation, fuel, undriveable flag). Roadside stabilisation only raises engine/body health to a floor (`engineHealthFloor` 650, `bodyHealthFloor` 500) and optionally fixes one burst tyre — it is explicitly never a full repair. Paint and bumper actions read player-entered values from an input dialog, clamped server-side to `Mechanic.cosmetics` ranges.
- No money changes hands anywhere in this job's own code: there is no price, invoice or `kora_banking`/`kora_core` payment call in `jobs/mechanic/server.lua`. `Mechanic.fullRepair.consume`/`roadsideRepair.consume`/`cosmetics.consume` can each name an item to be consumed instead (`nil` by default, meaning free).
- `Mechanic.damage` runs client-side only, independent of job membership: passive vehicle wear while driving (distance wear off by default, collision wear on), random tyre bursts at speed, and an engine "limp mode" below a health threshold. This is general vehicle realism, not part of the mechanic job's pay loop.

## Recycling centre

- No job membership check anywhere in `jobs/recycle/` — any player can clock in and work it. `Recycle.OutsideLocation`/`InsideLocation` fade the player in and out of an interior; `Recycle.DutyLocation` toggles on/off duty.
- While on duty, the client highlights one random pallet from `Recycle.PickupLocations`. Picking it up asks the server for authorisation (`kora_businesses:recycle:pickupPackage`, must be within 3 m of that pallet and have no live/unexpired pickup already), plays a progress bar, and attaches a carry prop to the player (optionally networked, falling back to a local prop under strict entity lockdown or if the networked object does not survive).
- Carrying the box to the drop-off (`Recycle.DropLocation`, the configured `HandInZone`, or optionally the sell ped if `Recycle.HandInAtSellPed`) and hand-in (`kora_businesses:recycle:getItem`) grants 1–5 random stacks of `metalscrap`/`plastic`/`copper`/`rubber`/`iron`/`aluminum`/`steel`/`glass` (1–5 units each) plus a `Recycle.LuckyItemChance`% (20%) chance of one `cryptostick`. A per-player cooldown equal to `Recycle.DeliveryActionDuration` (or the hand-in bar's own duration) blocks redeeming the same authorisation twice.
- If `Recycle.LimitedMaterials` is true, each material has a shared server-side stock pool (3000 each by default) that is depleted on hand-in and restocked when a player sells materials back.
- Selling (`jobs/recycle/sales.lua`, a separate NUI app at the sell ped) lists the current `Sales` price table (all materials 2 ⁄ unit by default, only present if `Recycle.SellMaterials`), shows what the player owns, and sells up to `Recycle.MaxSellPerRequest` (500) per request; `Recycle.SellOverAmount` controls whether an over-limit request is clamped or rejected outright.

## Tow truck driver

- Job name `tow`. A box zone at `Tow.Locations.vehicle.coords` lets a player with job `tow` pull out a `Tow.Vehicles` (`flatbed`) truck (`qb-tow:server:TakeOutVehicle`, one truck per player, must be within 10 m of the yard) and spawns a random broken-down vehicle to recover at a `Tow.Locations.towspots` entry.
- Picking up the marked vehicle (`qb-tow:server:pickUp`, within 10 m) attaches it to the flatbed client-side; placing it (via `Kora.raycast`) and dropping off at the yard (`qb-tow:server:DropOff`, within 10 m) increments a per-player `droppedOff` counter and immediately rolls a new pickup location.
- Returning the flatbed at the yard (`qb-tow:server:ReturnVehicle`) pays `droppedOff * Tow.payPerVehicle` ($100/vehicle) to the player's bank, clears job state and revokes the flatbed keys (`exports.kora_vehiclekeys:removeKeys`).
- The client's `Detach Vehicle` option calls a `qb-tow:server:CheckDistance` callback that is not registered anywhere in `jobs/tow/server.lua` — as shipped, selecting it will time out / fail every time. Unclear whether this is intentionally dead (detaching is otherwise done through `Place Vehicle`) or a missing handler; it was not changed for this page.
- `jobs/tow/server.lua` never checks `job.onduty`, only `job.name == 'tow'` — unlike mechanic and cctv, there is no on-duty gate on taking out a truck.

## Taxi driver

- A box zone at `Taxi.parkLocation` spawns/returns a `taxi` model vehicle for anyone (no job check client-side on spawning the vehicle itself; the fare loop is what actually requires the job).
- Spawning a trip (`qb-taxi:getPickupLocation`) is refused server-side unless the player's job name equals `Taxi.jobRequired` (`taxi`); it then picks a random pickup/drop-off pair from `Taxi.PickUp`/`Taxi.DropOffs` and records the straight-line distance for pay.
- A passenger NPC (random model from `Taxi.Peds`) spawns at the pickup; entering its zone gets it into the vehicle and tells the server the pickup happened (`qb-taxi:pickup`, must be within 5 m of the recorded pickup point). Reaching the drop-off zone makes the NPC leave and tells the server (`qb-taxi:dropOff`, within 5 m of the recorded drop-off, pickup must already be marked complete).
- Pay is `floor(distance * 0.2)` cash, added directly to the driver with `exports.kora_core:addMoney`. `Taxi.Management` is labelled unused in its own config description: "Current trips always pay the driver cash" regardless of its value — there is no society/company payout path in this job.
- `Taxi.jobRequired` itself is also labelled unused beyond that one check's own field name — its kora_lib config description states changing it does not alter which job is accepted beyond the literal comparison already written into `server.lua`.
