---
title: Jobs and permissions
sidebar_position: 3
---

# Jobs and permissions

`kora_businesses` does not create any jobs. Every job name below must exist in your job configuration (kora_core shared jobs or a job creator). Checks are done on the server unless noted.

| Feature | Job check | Duty | Grade |
| --- | --- | --- | --- |
| Mechanic full repair | job name equals `Mechanic.roles.fullRepairJob` (`mechanic`) or job type equals `Mechanic.roles.automotiveType` (`automotive`), and the job is not in `Mechanic.roles.roadsideJobs` | required when `Mechanic.roles.requireOnDuty` is `true` | none |
| Mechanic roadside stabilisation | job name equals `mechanic` or job type equals `automotive` | as above | none |
| Mechanic respray and bumpers | job name in `Mechanic.roles.bodyshopJobs` (`bodyshop`) or job type in `Mechanic.roles.bodyshopTypes` (`bodyshop`) | as above | none |
| Taxi | job name equals `Taxi.jobRequired` (`taxi`) | not checked | none |
| Garbage | job name `garbage` (hard-coded) | not checked | none |
| Recycle | none - any player can work in the warehouse | client-side "Toggle Duty" only, not kora_core duty | none |
| Tow | job name `tow` (hard-coded), checked when pulling out the flatbed | not checked | none |
| CCTV engineer actions | job name equals `Cctv.job` (`cctv`) | required when `Cctv.requireOnDuty` is `true` | at least `Cctv.minimumEngineerGrade` (`0`) |
| CCTV call-out request (business) | requester's job name equals the `business` they request for | not checked | none |
| CCTV call-out request (residential) | `citizenid` must be the requester's own | not applicable | none |
| CCTV hacking | none - any player can start a hack | not applicable | none |
| Hotdog (not loaded) | job name `hotdog` | not checked | none |

## Role notes

- A `roadside` job can only stabilise vehicles if it also qualifies as automotive (job type `automotive` or name `mechanic`); being listed in `roadsideJobs` only blocks full repairs.
- With the default role settings, the `mechanic` job can do full repairs and roadside stabilisation but not cosmetic work. Cosmetic work needs a `bodyshop` job name or type, or you can add `mechanic` to `Mechanic.roles.bodyshopJobs`.
- The default kora_core `mechanic` job has the type `mechanic`, so it qualifies through `fullRepairJob`, not through `automotiveType`.

## Admin permissions

The only permission-gated command is `/removestand` (kora_core permission `admin`), which belongs to the hotdog job and is therefore not registered unless hotdog is loaded. See [Commands](./commands.md).
