News = {}

News.UseableItems = true -- Set to false if you want to use commands instead of usable items

News.Locations = {
    main = vector4(-597.89, -929.95, 24.0, 271.5),
    inside = vector4(-77.46, -833.77, 243.38, 67.5),
    outside = vector4(-598.25, -929.86, 23.86, 86.5),
    vehicle = {
        coords = vector4(-552.24, -925.61, 23.86, 242.5),
        vehicles = {
            { name = 'rumpo', label = 'Rumpo', modLivery = 2 },
        },
    },
    heli = {
        coords = vector4(-583.08, -930.55, 36.83, 89.26),
        vehicles = {
            { name = 'conada', label = 'Conada', modLivery = 5 },
        },
    },
    shop = vector4(-595.4, -929.9, 23.86, 90.0),
}

-- Distances the server enforces around the shop and the garages.
News.ShopDistance = 5.0
News.GarageDistance = 5.0     -- spawning a vehicle
News.StoreDistance = 15.0     -- storing one (the player and the vehicle must both be this close to the garage)
News.VehicleDistance = 10.0   -- stocking a spawned vehicle's trunk

News.VehicleItems = {
    { name = 'newscam', amount = 1, info = {} },
    { name = 'newsmic', amount = 1, info = {} },
    { name = 'newsbmic', amount = 1, info = {} },
}

-- The job is configured in config.lua (Config.jobs.news.jobName, default 'reporter').
function News.jobName()
    return Config.jobs.news.jobName
end

Globals.News = News
