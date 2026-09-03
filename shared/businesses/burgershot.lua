-- A worked example, and the seed mechanism's own documentation.
--
-- Seeds are FIRST-BOOT ONLY. The row is inserted if no business with this id
-- exists yet, and is never written again -- so anything an admin changes or
-- deletes in-game stays changed or deleted across restarts. Delete this file if
-- you would rather build everything from scratch with `/business`.
--
-- Nothing here needs to be hand-written on your own server: `/business` builds
-- the same structure in-world, with the zone creator and the prop placer doing
-- the coordinates for you. This file exists so you can see the shape.

Config.seeds[#Config.seeds + 1] = {
    id = 'burgershot',
    label = 'Burger Shot',
    job = 'burgershot',
    modules = {
        {
            -- The perimeter. Entering it builds every module below and clocks
            -- staff on; leaving tears them down again.
            moduleType = 'Zone',
            label = 'Burger Shot',
            controlDuty = true,
            zoneType = 'sphere',
            coords = { x = -1193.0, y = -893.0, z = 13.9 },
            radius = 22.0,
        },
        {
            moduleType = 'Blip',
            label = 'Burger Shot',
            coords = { x = -1193.0, y = -893.0, z = 13.9 },
            sprite = 106,
            color = 1,
            scale = 0.7,
        },
        {
            moduleType = 'POS',
            label = 'Front Till',
            id = 'burgershot_till',
            items = { 'burgershot' },
            commission = 5,
            tax = 10,
            hideWhenStaffed = true,
            panicButton = true,
            zoneType = 'box',
            coords = { x = -1194.1, y = -899.4, z = 13.9 },
            size = { x = 2.0, y = 1.2, z = 1.5 },
            rotation = 34.0,
        },
        {
            moduleType = 'Stash',
            label = 'Walk-in Fridge',
            id = 'burgershot_fridge',
            slots = 80,
            weight = 400000,
            zoneType = 'box',
            coords = { x = -1198.5, y = -896.0, z = 13.9 },
            size = { x = 1.5, y = 1.5, z = 2.0 },
            rotation = 34.0,
        },
        {
            moduleType = 'Crafting',
            label = 'Grill',
            recipes = { 'bs_beef', 'bs_slicedonion', 'bs_slicedpotato', 'bs_burger', 'bs_fries' },
            zoneType = 'box',
            coords = { x = -1197.0, y = -900.5, z = 13.9 },
            size = { x = 2.5, y = 1.2, z = 1.5 },
            rotation = 34.0,
        },
        {
            moduleType = 'BossMenu',
            label = 'Manager Desk',
            zoneType = 'sphere',
            coords = { x = -1200.5, y = -894.0, z = 13.9 },
            radius = 1.0,
        },
    },
}
