-- Recipe library. A recipe is written ONCE here and referenced by id from any
-- number of crafting benches, so two restaurants that both grill beef share one
-- definition instead of two copies that drift apart.
--
-- Fields:
--   label          shown in the bench menu
--   icon           optional lucide icon name
--   time           progress bar duration in ms; omit for an instant craft
--   progressLabel  text shown on the bar
--   completeLabel  success message; a default is generated when omitted
--   anim           { dict, clip, flag } played for the duration
--   ingredients    { { item, amount } } consumed
--   give           { { item, amount } } produced
--   levelRequired  { { skill, level } } -- only enforced when Config.skills.enabled
--   xpGained       { { skill, xp } }    -- only awarded when Config.skills.enabled

local grill = { dict = 'amb@prop_human_bbq@male@base', clip = 'base', flag = 1 }
local prep = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 1 }

Config.recipes['bs_beef'] = {
    label = 'Grilled beef',
    time = 8000,
    progressLabel = 'Grilling beef',
    completeLabel = 'You grilled a beef patty.',
    anim = grill,
    ingredients = { { item = 'burgermeat', amount = 1 } },
    give = { { item = 'beef', amount = 1 } },
    levelRequired = { { skill = 'cooking', level = 1 } },
    xpGained = { { skill = 'cooking', xp = 5 } },
}

Config.recipes['bs_slicedonion'] = {
    label = 'Sliced onion',
    time = 5000,
    progressLabel = 'Slicing onions',
    anim = prep,
    ingredients = { { item = 'onion', amount = 1 } },
    give = { { item = 'slicedonion', amount = 10 } },
}

Config.recipes['bs_slicedpotato'] = {
    label = 'Sliced potato',
    time = 5000,
    progressLabel = 'Slicing potatoes',
    anim = prep,
    ingredients = { { item = 'potato', amount = 1 } },
    give = { { item = 'slicedpotato', amount = 10 } },
}

Config.recipes['bs_burger'] = {
    label = 'Bleeder burger',
    time = 6000,
    progressLabel = 'Building a burger',
    completeLabel = 'One Bleeder, ready to go.',
    anim = prep,
    ingredients = {
        { item = 'beef', amount = 1 },
        { item = 'slicedonion', amount = 1 },
        { item = 'bun', amount = 1 },
    },
    give = { { item = 'burger', amount = 1 } },
    levelRequired = { { skill = 'cooking', level = 2 } },
    xpGained = { { skill = 'cooking', xp = 10 } },
}

Config.recipes['bs_fries'] = {
    label = 'Fries',
    time = 6000,
    progressLabel = 'Frying',
    anim = grill,
    ingredients = { { item = 'slicedpotato', amount = 4 } },
    give = { { item = 'fries', amount = 1 } },
}
