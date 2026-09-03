-- Everything this resource ships must survive its own validator. A seed that
-- fails validation is silently skipped at boot, so it would otherwise ship
-- broken and nobody would find out until someone went looking for a business
-- that never appeared.

local H = dofile('test/harness.lua')

Config = {
    stash = { slots = 50, weight = 1000000 },
    pos = { shopSlots = 50, stockSlots = 50, currency = 'cash' },
    recipes = {}, shopItems = {}, seeds = {},
}

local S = dofile('shared/schema.lua')

local function loadAll(directory)
    local handle = io.popen(('ls %s/*.lua 2>/dev/null'):format(directory))
    local files = {}
    for line in handle:lines() do files[#files + 1] = line end
    handle:close()
    table.sort(files)
    for _, file in ipairs(files) do dofile(file) end
    return #files
end

H.ok(loadAll('shared/recipes') > 0, 'at least one recipe file ships')
H.ok(loadAll('shared/shopitems') > 0, 'at least one shop-item file ships')
H.ok(loadAll('shared/businesses') > 0, 'at least one seed file ships')

-- --- recipes ---------------------------------------------------------------

local recipeCount = 0
for id, recipe in pairs(Config.recipes) do
    recipeCount = recipeCount + 1
    H.equal(type(id), 'string', 'a recipe id is a string')
    H.ok(type(recipe.label) == 'string' and recipe.label ~= '', ('recipe %s has a label'):format(id))
    H.ok(type(recipe.give) == 'table' and #recipe.give > 0, ('recipe %s produces something'):format(id))
    for _, entry in ipairs(recipe.give) do
        H.ok(type(entry.item) == 'string', ('recipe %s names what it gives'):format(id))
    end
    for _, entry in ipairs(recipe.ingredients or {}) do
        H.ok(type(entry.item) == 'string', ('recipe %s names its ingredients'):format(id))
        H.ok((tonumber(entry.amount) or 0) > 0, ('recipe %s uses a positive amount'):format(id))
    end
    if recipe.anim then
        H.ok(type(recipe.anim.dict) == 'string' and type(recipe.anim.clip) == 'string',
            ('recipe %s has a complete animation'):format(id))
    end
end
H.ok(recipeCount > 0, 'recipes were registered')

-- --- shop item lists -------------------------------------------------------

for name, list in pairs(Config.shopItems) do
    H.ok(#list > 0, ('shop list %s is not empty'):format(name))
    for _, entry in ipairs(list) do
        H.ok(type(entry.item) == 'string', ('shop list %s names its items'):format(name))
        if entry.price ~= nil then
            H.ok((tonumber(entry.price) or -1) >= 0, ('shop list %s has a sane price'):format(name))
        end
    end
end

-- --- seeds -----------------------------------------------------------------

H.ok(#Config.seeds > 0, 'seeds were registered')

for _, seed in ipairs(Config.seeds) do
    local business, err = S.normaliseBusiness(seed)
    H.ok(business, ('seed %s validates: %s'):format(tostring(seed.id), tostring(err)))
    H.equal(#business.rejected, 0, ('seed %s has no rejected modules'):format(business.id))
    H.ok(#business.modules > 0, ('seed %s has modules'):format(business.id))

    -- Every recipe and shop list a seed refers to must actually exist, or the
    -- bench renders empty and the till silently accepts nothing.
    for _, module in ipairs(business.modules) do
        for _, recipeId in ipairs(module.recipes or {}) do
            H.ok(Config.recipes[recipeId], ('seed %s references recipe %s'):format(business.id, recipeId))
        end
        for _, listName in ipairs(module.items or {}) do
            H.ok(Config.shopItems[listName], ('seed %s references shop list %s'):format(business.id, listName))
        end
    end
end

H.finish('seeds')
