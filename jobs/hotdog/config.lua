Hotdog = {}
Hotdog.StandDeposit = 250

Hotdog.Skill = 'cooking'
Hotdog.SaleDistance = 4.0
Hotdog.PrepareXp = { common = 1, rare = 2, exotic = 3 }
Hotdog.SaleXp = { common = 1, rare = 2, exotic = 3 }

function Hotdog.batchSize(level, rarity)
    level = tonumber(level) or 1
    if level >= 90 then return 4 end
    if rarity == 'exotic' and level >= 70 then return 3 end
    if rarity == 'rare' and level >= 30 then return 2 end
    if rarity == 'common' and level >= 15 then return 2 end
    return 1
end

Hotdog.PrepareMinigameKeys = 10

Hotdog.PrepareRewards = {
    { name = 'common', chance = 70 },
    { name = 'rare', chance = 25 },
    { name = 'exotic', chance = 5 },
}

Hotdog.Locations = {
    ['take'] = {
        coords = vector4(39.31, -1005.54, 29.48, 240.57),
    },
    ['spawn'] = {
        coords = vector4(38.15, -1001.65, 29.44, 342.5),
    },
}

Hotdog.Stock = {
    ['exotic'] = {
        Max = {
            [1] = 15,
            [2] = 30,
            [3] = 45,
            [4] = 60,
        },
        Label = Kora.lang('hotdog.info.label_a'),
        Price = {
            [1] = {
                min = 8,
                max = 12,
            },
            [2] = {
                min = 9,
                max = 13,
            },
            [3] = {
                min = 10,
                max = 14,
            },
            [4] = {
                min = 11,
                max = 15,
            },
        }
    },
    ['rare'] = {
        Max = {
            [1] = 15,
            [2] = 30,
            [3] = 45,
            [4] = 60,
        },
        Label = Kora.lang('hotdog.info.label_b'),
        Price = {
            [1] = {
                min = 6,
                max = 9,
            },
            [2] = {
                min = 7,
                max = 10,
            },
            [3] = {
                min = 8,
                max = 11,
            },
            [4] = {
                min = 9,
                max = 12,
            },
        }
    },
    ['common'] = {
        Max = {
            [1] = 15,
            [2] = 30,
            [3] = 45,
            [4] = 60,
        },
        Label = Kora.lang('hotdog.info.label_c'),
        Price = {
            [1] = {
                min = 4,
                max = 6,
            },
            [2] = {
                min = 5,
                max = 7,
            },
            [3] = {
                min = 6,
                max = 9,
            },
            [4] = {
                min = 7,
                max = 9,
            },
        }
    },
}
Globals.Hotdog = Hotdog