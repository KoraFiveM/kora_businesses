-- Wiring contract: the manifest, the exports other resources call, and the
-- events the two realms agree on. A rename on one side of a boundary and not
-- the other is invisible at load time and only shows up as a dead till in-game.

local H = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'), 'missing ' .. path)
    local source = file:read('*a')
    file:close()
    return source
end

local manifest = read('fxmanifest.lua')
local serverFiles, clientFiles = {}, {}
for file in manifest:gmatch("'(server/[%w_]+%.lua)'") do serverFiles[#serverFiles + 1] = file end
for file in manifest:gmatch("'(client/[%w_]+%.lua)'") do clientFiles[#clientFiles + 1] = file end

local server, client = '', ''
for _, file in ipairs(serverFiles) do server = server .. read(file) end
for _, file in ipairs(clientFiles) do client = client .. read(file) end

-- --- manifest --------------------------------------------------------------

for _, dependency in ipairs({ 'qblib', 'qbsql', 'qbcore', 'qbinventory', 'qbtarget' }) do
    H.ok(manifest:find(("dependency '%s'"):format(dependency), 1, true), 'depends on ' .. dependency)
end
H.ok(manifest:find("'@qblib/init.lua'", 1, true), 'loads the qblib mirror')
H.ok(manifest:find("'@qbcore/init.lua'", 1, true), 'loads the qbcore mirror')
H.ok(manifest:find("'shared/schema.lua'", 1, true), 'the schema is shared by both realms')
H.ok(manifest:find("'config.lua',", 1, true), 'config loads before the shared files that append to it')
H.ok(manifest:find('sql/001_businesses.sql', 1, true), 'the migration is a packaged file')
H.ok(client:find('QB.blips.getCategoryIds()', 1, true),
    'the creator category select comes from qblib instead of free text')
H.ok(client:find("type = 'select'", 1, true) and client:find("default = 'Business'", 1, true),
    'the creator offers a safe category selection with a Business fallback')
H.nope(client:find('label = values.name or values.category', 1, true),
    'new blips do not preformat or override qblib category/name labels')

-- Webhook URLs are credentials. The shared config bundle is fetched by every
-- client, so webhook policy must be loaded by the server alone.
H.ok(manifest:find("'server/config.lua'", 1, true), 'server-only config is loaded')
H.nope(read('config.lua'):find('webhooks', 1, true), 'shared config contains no webhook settings')
H.ok(read('server/config.lua'):find('Config.webhooks', 1, true), 'webhook settings live in server config')

-- Config must load before anything that writes into it, or `Config.recipes`
-- is nil at the moment a recipe file tries to append to it.
local configAt = manifest:find("'config.lua'", 1, true)
for _, path in ipairs({ 'shared/schema.lua', 'shared/recipes/%*%.lua', 'shared/businesses/%*%.lua' }) do
    local at = manifest:find(("'%s'"):format(path))
    H.ok(at and at > configAt, ('%s loads after config'):format(path))
end

-- --- callbacks agree across the boundary -----------------------------------

local registered, triggered = {}, {}
for name in server:gmatch("QB%.callback%.register%('(qbbusinesses:server:[%w:]+)'") do registered[name] = true end
for name in client:gmatch("QB%.callback%.trigger%('(qbbusinesses:server:[%w:]+)'") do triggered[name] = true end

local triggerCount = 0
for name in pairs(triggered) do
    triggerCount = triggerCount + 1
    H.ok(registered[name], ('the client calls %s and the server registers it'):format(name))
end
H.ok(triggerCount >= 10, 'the client actually exercises the server surface')

local clientRegistered, serverTriggered = {}, {}
for name in client:gmatch("QB%.callback%.register%('(qbbusinesses:client:[%w:]+)'") do clientRegistered[name] = true end
for name in server:gmatch("QB%.callback%.trigger%(%w+, '(qbbusinesses:client:[%w:]+)'") do serverTriggered[name] = true end
for name in pairs(serverTriggered) do
    H.ok(clientRegistered[name], ('the server asks %s and the client answers it'):format(name))
end
H.equal(next(serverTriggered) ~= nil, true, 'the server does ask the client things')

-- --- net events agree ------------------------------------------------------

for event in server:gmatch("TriggerClientEvent%('(qbbusinesses:client:[%w:]+)'") do
    H.ok(client:find(("RegisterNetEvent('%s'"):format(event), 1, true), ('the client handles %s'):format(event))
end

-- --- exports ---------------------------------------------------------------

for _, name in ipairs({ 'getBusinesses', 'getBusiness', 'getBusinessesByJob', 'getStaffCounts', 'recordBusinessLog' }) do
    H.ok(server:find(("exports('%s'"):format(name), 1, true), ('server export %s'):format(name))
end
for _, name in ipairs({ 'getBusinesses', 'openBusinessMenu' }) do
    H.ok(client:find(("exports('%s'"):format(name), 1, true), ('client export %s'):format(name))
end

-- qbbossmenu is optional at runtime, but every method invoked through its
-- dynamic export proxy must still exist in the corresponding realm. Read the
-- sibling source so a provider rename fails this consumer's suite immediately.
local bossMenuClient = read('../qbbossmenu/client/main.lua')
local bossMenuServer = read('../qbbossmenu/server/main.lua')
for _, name in ipairs({ 'openBossMenu' }) do
    H.ok(client:find(('bossMenu:%s('):format(name), 1, true), ('client calls qbbossmenu:%s'):format(name))
    H.ok(bossMenuClient:find(("exports('%s'"):format(name), 1, true),
        ('qbbossmenu declares client export %s'):format(name))
end
for _, name in ipairs({ 'addBusinessMoney', 'removeBusinessMoney', 'getBusinessBalance' }) do
    H.ok(server:find(('bossMenu:%s('):format(name), 1, true), ('server calls qbbossmenu:%s'):format(name))
    H.ok(bossMenuServer:find(("exports('%s'"):format(name), 1, true),
        ('qbbossmenu declares server export %s'):format(name))
end
H.ok(client:find('---@type QBBossMenuClientExports', 1, true), 'client boss-menu proxy has a LuaLS contract')
H.ok(server:find('---@type QBBossMenuLedgerExports', 1, true), 'ledger proxy has a LuaLS contract')
H.ok(server:find('---@type QBBossMenuBalanceExports', 1, true), 'balance proxy has a LuaLS contract')

-- --- integration seams -----------------------------------------------------
--
-- Every optional dependency must be probed before use: this resource has to
-- start on a server that runs neither a boss menu nor a dispatch system.
for _, resource in ipairs({ 'qbbossmenu', 'qbdispatch' }) do
    H.nope(manifest:find(("dependency '%s'"):format(resource), 1, true), resource .. ' is optional')
    H.ok(server:find(("GetResourceState('%s')"):format(resource), 1, true),
        ('%s is probed before it is called'):format(resource))
end

-- Shop stock lives in qbinventory, not in a second table here: two records of
-- the same shelf is exactly the bug this design exists to avoid.
H.ok(server:find('GetShopItems', 1, true) and server:find('SetShopItems', 1, true),
    'shop stock is read and written through qbinventory')
local tables = {}
for name in read('sql/001_businesses.sql'):gmatch('CREATE TABLE IF NOT EXISTS `([%w_]+)`') do tables[#tables + 1] = name end
H.equal(#tables, 3, 'the migration creates exactly the three tables this resource owns')
for _, name in ipairs(tables) do
    H.nope(name:find('stock', 1, true), ('%s is not a second record of the shelf'):format(name))
end

-- --- qbcore call shapes ----------------------------------------------------
--
-- Two of qbcore's reads take shapes that fail SILENTLY when you get them wrong:
-- `getPlayerData`'s path is an array of keys (a bare string walks a string and
-- resolves to nil), and `QB.shared.all` returns a dense array of records whose
-- key lives on the record as `.name` (pairs() over it yields integers).
for realm, source in pairs({ client = client, server = server }) do
    for call in source:gmatch("getPlayerData%(([^)]*)%)") do
        H.nope(call:find("^'") or call:find('^"'),
            ('%s passes getPlayerData an array path, not a string'):format(realm))
    end
end
-- The leading space matters: 'ipairs(' contains 'pairs(' as a substring.
H.nope(server:find(' pairs(QB.shared.all', 1, true), 'QB.shared.all is never iterated with pairs')
H.ok(server:find('ipairs(QB.shared.all', 1, true), 'the job list reads the dense array')

-- --- teardown --------------------------------------------------------------

H.ok(client:find('onClientResourceStop', 1, true), 'the client cleans up when the resource stops')
H.ok(client:find('Business.destroy(business)', 1, true), 'every live business is destroyed on stop')
H.ok(client:find('QB.entities.remove', 1, true), 'spawned props are removed')
H.ok(client:find('QB.blips.remove', 1, true), 'blips are removed')
H.ok(client:find('removeZone', 1, true) and client:find('removeEntity', 1, true),
    'target registrations are removed')

H.finish('contract')
