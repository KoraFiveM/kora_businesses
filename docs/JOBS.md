# Job toggles and the taxi / hotdog jobs

Every job is switched on or off in `/config` (kora_lib editor) under `jobs.<name>.enabled`.
The saved value lives in `businesses.config.local.lua`, is read by the server before any job
loads, and needs a `restart kora_businesses` to take effect. The server tells connecting clients
which jobs it loaded, so client and server always agree.

| Key | Default | Notes |
| --- | --- | --- |
| `jobs.{mechanic,taxi,garbage,recycle,tow,cctv}.enabled` | `true` | |
| `jobs.hotdog.enabled` | `false` | Not running on the test server today. |
| `jobs.mechanic.persistCosmetics` | `true` | Store the result of a finished respray/bumper service on the vehicle (applies live). |
| `jobs.taxi.meter.enabled` | `true` | Fare meter screen (`qb-taxi:client:toggleMeter` / `enableMeter`). |
| `jobs.taxi.npcFromOwnTaxi` | `true` | Start an NPC fare from the driver seat of any taxi (`qb-taxi:client:DoTaxiNpc`). |
| `jobs.taxi.farePerMeter` | `0.2` | Cash per metre of an NPC fare. Applies live. |
| `jobs.taxi.minSpeedMps` | `45.0` | An NPC fare is paid only if the trip took at least `distance / minSpeedMps` seconds. |
| `jobs.taxi.requireOnDuty` | `true` | Off-duty taxi employees cannot start or finish NPC fares. |

## Running next to the old standalone resources

`taxi` and `hotdog` replace the standalone `kora_taxi` and `kora_hotdogjob` resources. They use
the same callback and event names, so if one of those resources is already running the job here
logs a message and steps aside. Stop the old resource (and remove it from `server.cfg`) to use
the one in `kora_businesses`.

## Taxi

* The depot taxi is spawned by the server as a networked vehicle (other players see it and its
  driver). Passengers stay client-side props, so only the driver sees the NPC.
* NPC fares are validated on the server: the driver must be at the pickup and the drop-off,
  in a taxi, on duty (if required), and the trip must not be faster than `minSpeedMps`.
* The meter screen is `jobs/taxi/html/meter.html` (`ui_page`), themed through `kora_theme`.

## Mechanic: saved vehicle properties

`qb-mechanicjob:server:SaveVehicleProps` (legacy name, kept) is validated on the server:

* The caller must be within `Mechanic.propsSave.distance` of the vehicle and may save at most once per `cooldown`.
* A vehicle owner can persist wear (dirt, tyres, windows, doors, tank) but never *healthier* than what is
  stored: a burst tyre or broken window stays that way in the database until a mechanic repairs it.
* Tuning is **not** accepted from the client. The only exception is the result of a respray or bumper service
  the player has just completed through the permit flow: that exact colour pair / bumper pair may be saved once,
  within `Mechanic.propsSave.grantLifetime` ms. The mechanic client sends it automatically. Third-party tuning
  menus that used this event need their own server-side authority.
