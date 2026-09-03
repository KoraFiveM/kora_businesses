-- The schema is the only thing standing between a hand-edited database row (or
-- a forged creator payload) and every client in the server, so it is tested for
-- real rather than by reading its source.

local H = dofile('test/harness.lua')

Config = {
    stash = { slots = 50, weight = 1000000 },
    pos = { shopSlots = 50, stockSlots = 50, currency = 'cash' },
    recipes = {}, shopItems = {}, seeds = {},
}

local S = dofile('shared/schema.lua')

-- `normaliseModule` returns (nil, err). A call in a non-final argument slot is
-- truncated to one value, so the reason would be lost -- these helpers capture
-- both before asserting.
local function refuses(message, payload)
    local module, err = S.normaliseModule(payload)
    H.rejects(module, err, message)
end

local function refusesBusiness(message, payload)
    local business, err = S.normaliseBusiness(payload)
    H.rejects(business, err, message)
end

-- --- slugs -----------------------------------------------------------------

H.equal(S.slug('Burger Shot'), 'burger_shot', 'a label becomes a slug')
H.equal(S.slug('  Bean   Machine!! '), 'bean_machine', 'punctuation and padding are stripped')
H.equal(S.slug('***'), nil, 'a slug with no word characters is refused')
H.equal(S.slug(''), nil, 'an empty label has no slug')
H.equal(S.slug(42), nil, 'a non-string has no slug')

-- --- coordinates -----------------------------------------------------------

local coords = S.coords({ x = 1.5, y = -2.5, z = 3.0, w = 450.0 })
H.equal(coords.x, 1.5, 'x survives')
H.equal(coords.w, 90.0, 'heading is normalised into 0-360')
H.equal(S.coords({ 10, 20, 30 })[3] == nil and S.coords({ 10, 20, 30 }).z, 30.0, 'an array form is accepted')
H.equal(S.coords({ x = 1, y = 2 }), nil, 'a coordinate missing z is refused')
H.equal(S.coords('here'), nil, 'a string is not a coordinate')

-- --- anchors ---------------------------------------------------------------

local sphere = S.normaliseModule({
    moduleType = 'Stash', id = 'test', label = 'Test',
    zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 }, radius = 3.0,
})
H.equal(sphere.radius, 3.0, 'a sphere keeps its radius')
H.equal(sphere.distance, 2.0, 'a module gets a default interaction distance')

refuses('a box without a size is refused', { moduleType = 'Stash', id = 'test', zoneType = 'box',
    coords = { x = 0, y = 0, z = 0 } })

local box = S.normaliseModule({
    moduleType = 'Stash', id = 'test', zoneType = 'box',
    coords = { x = 0, y = 0, z = 0 }, size = { 2, 2, 2 }, rotation = 34.0,
})
H.equal(box.size.y, 2.0, 'a box keeps its size')
H.equal(box.rotation, 34.0, 'a box keeps its rotation')

refuses('a poly needs three points', { moduleType = 'Stash', id = 'test', zoneType = 'poly',
    coords = { x = 0, y = 0, z = 0 }, points = { { 0, 0, 0 }, { 1, 1, 0 } } })

local poly = S.normaliseModule({
    moduleType = 'Stash', id = 'test', zoneType = 'poly', coords = { x = 0, y = 0, z = 0 },
    points = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 } },
})
H.equal(#poly.points, 3, 'a poly keeps its points')

refuses('an unknown zone type is refused', { moduleType = 'Stash', id = 'test', zoneType = 'cylinder',
    coords = { x = 0, y = 0, z = 0 } })

-- A single coordinate may be given unwrapped; the schema always stores a list,
-- so the client never has to branch on which form it received.
local entity = S.normaliseModule({
    moduleType = 'StaticEntity', model = { model = 'prop_bin_08', modelType = 'object' },
    coords = { x = 1, y = 2, z = 3, w = 90 },
})
H.equal(#entity.coords, 1, 'a lone coordinate is wrapped into a list')
H.equal(entity.coords[1].w, 90.0, 'the entity heading survives')
H.equal(entity.model.modelType, 'object', 'the model type survives')

refuses('an unknown model type is refused', { moduleType = 'StaticEntity',
    model = { model = 'prop_bin_08', modelType = 'helicopter' }, coords = { x = 1, y = 2, z = 3 } })

refuses('a model-only module refuses a zone anchor', { moduleType = 'StaticEntity',
    zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } })

refuses('a zone-only module refuses an entity anchor', { moduleType = 'Zone',
    model = { model = 'prop_bin_08', modelType = 'object' }, coords = { x = 0, y = 0, z = 0 } })

-- --- per-type payloads -----------------------------------------------------

refuses('an unknown module type is refused', { moduleType = 'Nonsense' })
refuses('a till without an id is refused', { moduleType = 'POS', zoneType = 'sphere',
    coords = { x = 0, y = 0, z = 0 } })
refuses('a bench with no recipes is refused', { moduleType = 'Crafting', recipes = {},
    zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } })
refuses('a reward item with an empty pool is refused', { moduleType = 'UseableItem', item = 'box',
    useType = 'reward', rewards = {} })

local till = S.normaliseModule({
    moduleType = 'POS', id = 'shop', items = { 'burgershot' }, commission = 5, tax = 10,
    currency = 'CASH', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 },
})
H.equal(till.currency, 'cash', 'currency is case-insensitive')
H.equal(till.commission, 5.0, 'commission survives')
H.equal(till.tax, 10.0, 'tax survives')
H.equal(#till.items, 1, 'the stock list survives')

-- A mistyped percentage is rejected rather than silently read as zero, which
-- would leave a business quietly collecting no tax at all.
refuses('an out-of-range tax is refused', { moduleType = 'POS', id = 'shop', tax = 200,
    zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } })
refuses('a negative commission is refused', { moduleType = 'POS', id = 'shop', commission = -5,
    zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } })

refuses('an unsupported till currency is refused', { moduleType = 'POS', id = 'shop',
    currency = 'crypto', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } })

local useable = S.normaliseModule({
    moduleType = 'UseableItem', item = 'MYSTERY_BOX', useType = 'reward',
    rewards = { { item = 'Water', amount = 2, chance = 5 }, { item = 'burger' } },
})
H.equal(useable.item, 'mystery_box', 'item names are lowercased')
H.equal(useable.rewards[1].chance, 5.0, 'a reward weight survives')
H.equal(useable.rewards[2].amount, 1, 'a reward amount defaults to one')

-- --- business assembly -----------------------------------------------------

local business, err = S.normaliseBusiness({
    label = 'Burger Shot', job = 'BurgerShot',
    modules = {
        { moduleType = 'Zone', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 }, radius = 20.0 },
        { moduleType = 'Stash', id = 'fridge', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } },
        { moduleType = 'Nonsense' },
    },
})
H.ok(business, err or 'the business assembled')
H.equal(business.id, 'burger_shot', 'the id is derived from the label')
H.equal(business.job, 'burgershot', 'the job is lowercased')
H.equal(#business.modules, 2, 'valid modules are kept')
H.equal(#business.rejected, 1, 'one bad module is dropped, not the whole business')
H.equal(business.rejected[1].index, 3, 'the rejection reports its original position')

refusesBusiness('a business without a job is refused', { label = 'No Job' })
refusesBusiness('a non-table is not a business', 'nope')

-- --- startup vs dynamic ----------------------------------------------------

H.ok(S.hasPerimeter(business), 'a business with a Zone module has a perimeter')
H.ok(S.isStartupModule(business, business.modules[1]), 'the perimeter itself is a startup module')
H.nope(S.isStartupModule(business, business.modules[2]), 'a stash waits for the player to arrive')

local flat = S.normaliseBusiness({
    label = 'Kiosk', job = 'kiosk',
    modules = { { moduleType = 'Stash', id = 'k', zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 } } },
})
H.nope(S.hasPerimeter(flat), 'a business may have no perimeter')
H.ok(S.isStartupModule(flat, flat.modules[1]),
    'with no perimeter to trigger it, every module is built eagerly')

H.finish('schema')
