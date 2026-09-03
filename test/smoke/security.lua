-- Source-contract checks on the server realm.
--
-- These files cannot run outside FXServer, so this asserts the invariants that
-- matter are actually WRITTEN DOWN in the source rather than assumed. Each one
-- corresponds to a way a client could take money, items or control it should
-- not have; a refactor that quietly drops one fails here.

local H = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'), 'missing ' .. path)
    local source = file:read('*a')
    file:close()
    return source
end

local state = read('server/state.lua')
local admin = read('server/admin.lua')
local pos = read('server/pos.lua')
local crafting = read('server/crafting.lua')
local payment = read('server/payment.lua')
local staff = read('server/staff.lua')
local register = read('server/register.lua')
local schema = read('shared/schema.lua')
local manifest = read('fxmanifest.lua')

-- --- authorisation ---------------------------------------------------------

H.ok(admin:find('State.isAdmin(src)', 1, true), 'the creator checks an admin permission')
H.ok(state:find('hasPermission', 1, true), 'admin status comes from qbcore, not from the client')
for _, callback in ipairs({ 'createBusiness', 'editBusiness', 'deleteBusiness', 'saveModule', 'removeModule' }) do
    local body = admin:match("register%('qbbusinesses:server:" .. callback .. "'.-\nend, {")
    H.ok(body ~= nil, ('callback %s exists'):format(callback))
    H.ok(body and (body:find('authorise(src', 1, true) or body:find('State.isAdmin(src)', 1, true)),
        ('callback %s authorises its caller'):format(callback))
end

H.ok(pos:find('requireBoss', 1, true) or pos:find('State.canManage', 1, true),
    'repricing a till is gated on managing the business')
H.ok(pos:find("tillContext(src, shopId, true)", 1, true), 'setTillPrice requires the boss context')

-- --- rate limiting ---------------------------------------------------------
--
-- Every client-callable entry point runs a database read, a dialog or a money
-- move. An unlimited one is a free denial-of-service against the server.
for _, source in ipairs({ admin, pos, crafting, payment, staff, register }) do
    local registrations, limited = 0, 0
    for chunk in source:gmatch("QB%.callback%.register%('qbbusinesses:server:.-\nend[^\n]*") do
        registrations = registrations + 1
        if chunk:find('rateLimit', 1, true) then limited = limited + 1 end
    end
    -- The body pattern is non-greedy and could in principle stop short on a
    -- callback whose body confuses it, quietly skipping the one registration
    -- that was missing a limit. Compare against a plain count of declarations
    -- so a skipped body fails rather than passes.
    local declared = select(2, source:gsub("QB%.callback%.register%('qbbusinesses:server:", ''))
    H.ok(declared > 0, 'the file registers server callbacks')
    H.equal(registrations, declared, 'every registration body was inspected')
    H.equal(limited, registrations, 'every server callback carries a rate limit')
end

-- --- the client never supplies gameplay data -------------------------------

H.ok(crafting:find('Config.recipes[id]', 1, true), 'a recipe is resolved from shared config')
H.ok(crafting:find("if id == recipeId then offered = true", 1, true),
    'a recipe must be offered by the bench being used, not merely exist')
H.ok(crafting:find('QB.distance.player(src, anchor', 1, true), 'crafting revalidates the distance server-side')
H.nope(crafting:find('function(src, recipe)\n', 1, true), 'no callback accepts a client-supplied recipe table')

H.ok(pos:find('Pos.accepts(shopId', 1, true), 'the till decides what it stocks')
H.ok(pos:find('Config.pos.maxPrice', 1, true), 'prices are capped')

-- --- money -----------------------------------------------------------------

H.ok(payment:find('nearEachOther(src, target)', 1, true), 'a card payment is distance-checked')
H.equal(select(2, payment:gsub('if not nearEachOther', '')), 2,
    'the distance is re-checked after the dialogs, not only before them')
H.ok(payment:find('qbbusinesses-card-refund', 1, true),
    'a failed business credit refunds the customer rather than stranding the money')
H.ok(payment:find('approved ~= true', 1, true),
    'a timed-out approval is treated as no consent, not as consent')

H.ok(pos:find("action ~= 'purchase'", 1, true), 'sales are credited from the committed purchase audit')
H.nope(pos:find("RegisterHook('buyItem'", 1, true),
    'sales are NOT credited from a pre-commit buyItem hook')
H.ok(crafting:find('for _, undo in ipairs(removed) do', 1, true),
    'a partial ingredient removal is rolled back')

-- --- validation ------------------------------------------------------------

H.ok(state:find('S.normaliseBusiness(raw)', 1, true), 'every write is validated by the schema')
H.ok(state:find('State.businesses[stamp(business).id] = business', 1, true),
    'the mirror is updated after the write, and stamped with a fingerprint')
H.ok(state:find('business.rev = checksum(', 1, true),
    'the fingerprint is computed server-side, where key ordering is fixed')
local persist = state:match('function State%.persist.-\nend')
H.ok(persist and persist:find('writeErr then return nil', 1, true),
    'a failed database write does not update the live registry')

-- --- luac safety -----------------------------------------------------------
--
-- A BARE backtick outside a string is CFX's GetHashKey sugar and breaks stock
-- lua/luac, which is what these tests run under. Backticks inside quoted SQL
-- identifiers are fine, so they are stripped before scanning.
local function bareBacktick(source)
    local stripped = source:gsub('%-%-%[%[.-%]%]', ''):gsub('%-%-[^\n]*', '')
        :gsub("%[%[.-%]%]", ''):gsub("'[^'\n]*'", ''):gsub('"[^"\n]*"', '')
    return stripped:find('`', 1, true) ~= nil
end
for name, source in pairs({ state = state, admin = admin, pos = pos, crafting = crafting,
    payment = payment, staff = staff, schema = schema, register = register }) do
    H.nope(bareBacktick(source), ('%s has no bare backtick literal'):format(name))
end

-- --- load order ------------------------------------------------------------

local order = {}
for file in manifest:gmatch("'(server/[%w_]+%.lua)'") do order[#order + 1] = file end
H.equal(order[1], 'server/state.lua', 'state loads first: everything else reads its registry')
H.equal(order[#order], 'server/main.lua', 'main boots last, once everything has registered')
local positions = {}
for index, file in ipairs(order) do positions[file] = index end
H.ok(positions['server/pos.lua'] < positions['server/register.lua'],
    'pos registers its shop helpers before register dispatches to them')
H.ok(positions['server/register.lua'] < positions['server/main.lua'],
    'register exists before the boot sequence calls it')

H.finish('security')
