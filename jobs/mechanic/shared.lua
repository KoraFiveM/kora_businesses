
Mechanic = {}

Mechanic.roles = {
    requireOnDuty = true,             -- staff must clock in before using their job actions
    fullRepairJob = 'mechanic',       -- this named job may perform a full repair
    automotiveType = 'automotive',    -- other specialist repair jobs may use this type
    roadsideJobs = { roadside = true }, -- automotive jobs limited to roadside actions
    bodyshopJobs = { bodyshop = true }, -- cosmetic-only job names
    bodyshopTypes = { bodyshop = true }, -- cosmetic-only job types
}

Mechanic.interaction = {
    distance = 3.0,                   -- maximum player-to-vehicle range, checked server-side
    permitLifetime = 45000,           -- ms; an approved action must be completed within this time
    permitRateLimit = { max = 8, window = 10000 },
}

Mechanic.fullRepair = {
    label = 'Perform full repair',
    duration = 18000,
    requireGarage = true,
    -- Full repairs are intentionally station-only. Add, remove, or relocate
    -- bays here; the server checks the vehicle's position, not client UI state.
    garages = {
        vector3(-211.60, -1324.31, 30.89), -- LS Customs, Burton
        vector3(731.68, -1088.78, 22.17),  -- LS Customs, La Mesa
        vector3(1174.76, 2640.15, 37.75),  -- Route 68
    },
    garageRadius = 12.0,
    consume = nil,                    -- e.g. { item = 'repairkit', amount = 1 }; nil = no item cost
}

Mechanic.roadsideRepair = {
    label = 'Stabilise vehicle',
    duration = 9000,
    engineHealthFloor = 650.0,        -- never a full repair: enough to limp to a garage
    bodyHealthFloor = 500.0,
    repairOneTyre = true,
    consume = nil,                    -- e.g. { item = 'roadsidekit', amount = 1 }
}

Mechanic.cosmetics = {
    duration = 12000,
    paintColourMin = 0,
    paintColourMax = 160,             -- GTA paint palette indices
    bumperModMax = 50,                -- client also clamps this to the model's actual mod count
    consume = nil,                    -- e.g. { item = 'spraycan', amount = 1 }
}

-- Passive wear is local to the current driver. It uses native vehicle health,
-- so standard GTA collision damage and this additional RP wear coexist.
Mechanic.damage = {
    enabled = true,
    interval = 1500,                  -- ms; does no work when the player is not driving
    excludedClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true }, -- bikes, cycles, boats, helis, planes
    distanceWear = {
        enabled = false,              -- opt in: this deliberately damages vehicles without a collision
        enginePerKm = 0.65,
        bodyPerKm = 0.18,
        minSpeed = 4.0,               -- m/s; idling/crawling causes no wear
    },
    collision = {
        enabled = true,
        minSpeedLoss = 7.0,           -- m/s lost between samples before extra collision wear applies
        minNativeHealthLoss = 1.0,     -- ignore health jitter; braking alone must never count as a collision
        engineDamagePerSpeedLoss = 4.0,
        bodyDamagePerSpeedLoss = 7.0,
        maxEngineDamage = 140.0,
        maxBodyDamage = 190.0,
    },
    tyres = {
        enabled = true,
        checkInterval = 30000,        -- each driver vehicle gets one roll this often
        chance = 0.003,               -- 0.3% per check while qualifying
        minSpeed = 22.0,              -- m/s (~49 mph)
        minEngineHealth = 250.0,      -- very healthy vehicles do not randomly burst tyres
        burstOnRims = false,
    },
    limpMode = {
        enabled = true,
        engineHealthThreshold = 300.0,
        torqueMultiplier = 0.58,
        stallChance = 0.08,           -- roll each damage interval under the threshold
        stallMinSpeed = 2.0,
    },
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Mechanic = QB.config.adopt(Mechanic) end
