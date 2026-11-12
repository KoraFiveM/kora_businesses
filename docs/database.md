---
title: Database
sidebar_position: 7
---

# Database

Only the CCTV job uses the database. There are no `.sql` files: on server start (when CCTV is enabled) the schema `KoraBusinessesCctvSchema` from `jobs/cctv/server.lua` is applied with `Kora.sql.ensureTables`, which creates missing tables and columns. The server waits up to 60 seconds for kora_sql; if it is not ready, or the schema fails, an error is printed and the tables are not created. Schema warnings are printed per table.

The other jobs keep all state in memory and lose it on restart.

## `kora_businesses_cctv_callouts`

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `varchar(40)` | no | | Primary key, for example `cctv-1762862400-1`. |
| `business` | `varchar(50)` | yes | | Customer business (job name); null for residential customers. |
| `customer_type` | `varchar(20)` | no | `business` | `business` or `residential`. |
| `citizenid` | `varchar(50)` | yes | | Residential customer. |
| `issue` | `enum('camera','nvr')` | no | | |
| `camera_id` | `varchar(80)` | yes | | |
| `nvr_id` | `varchar(80)` | yes | | |
| `requester` | `int` | no | | Requesting player's server ID. |
| `engineer` | `int` | yes | | Assigned engineer's server ID. |
| `charge` | `int` | no | `0` | Call-out charge. |
| `repair_price` | `int` | yes | | Repair charge. |
| `status` | `varchar(20)` | no | | |
| `coords` | `text` | yes | | |
| `created_at` | `timestamp` | no | `CURRENT_TIMESTAMP` | |
| `completed_at` | `timestamp` | yes | | |

Indexes: `kora_businesses_cctv_callouts_business` (`business`), `kora_businesses_cctv_callouts_status` (`status`).

The table is created but nothing reads from or writes to it yet: call-outs are held in memory only (see [CCTV](./features/cctv.md#emergency-call-outs)).

## `kora_businesses_cctv_systems`

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `varchar(80)` | no | | Primary key; the target ID used by `/cctvhack` and `/cctvrepair`. |
| `installer_business` | `varchar(50)` | no | | Company that installed the system. The laptop lists rows where this equals `Cctv.job`. |
| `business` | `varchar(50)` | no | | Customer business. |
| `business_label` | `varchar(100)` | yes | | Display label. |
| `camera_count` | `int` | no | `0` | |
| `status` | `varchar(20)` | no | `online` | |
| `security_level` | `int` | no | `1` | Base security level. |
| `intrusion_level` | `int` | no | `0` | Set by successful hacks. |
| `created_at` | `timestamp` | no | `CURRENT_TIMESTAMP` | |

Index: `kora_businesses_cctv_systems_installer` (`installer_business`).

Queries used:

- Engineer laptop: `SELECT id, business, business_label, camera_count, status FROM kora_businesses_cctv_systems WHERE installer_business = ?` (with `Cctv.job`).
- Hack and repair difficulty: reads `security_level` and `intrusion_level` for the target ID. The effective level is `security_level + intrusion_level`, clamped to 1-10; it is 1 if no row exists.
- Successful hack: `UPDATE ... SET intrusion_level = LEAST(10, ?) WHERE id = ?`.

This resource never inserts rows into `kora_businesses_cctv_systems`; installed systems must be added by another tool or resource.
