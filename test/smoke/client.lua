-- Client-realm invariants that are easy to regress and impossible to see.
--
-- The hard one is threading. qblib's zone tick and qbtarget's target loop are
-- SHARED across every resource that uses them, and both invoke callbacks this
-- resource supplies. Yielding inside one of those callbacks -- which almost
-- everything here does, since streaming a prop, opening a dialog and calling
-- the server all yield -- stalls every zone or every target in the server, not
-- just ours.

local H = dofile('test/harness.lua')

local function read(path)
    local file = assert(io.open(path, 'r'), 'missing ' .. path)
    local source = file:read('*a')
    file:close()
    return source
end

local business = read('client/business.lua')
local main = read('client/main.lua')
local creator = read('client/creator.lua')
local payment = read('client/payment.lua')
local state = read('client/state.lua')

-- --- yield safety ----------------------------------------------------------

local enter = business:match('function Business:enter%(%).-\nend')
H.ok(enter, 'Business:enter exists')
H.ok(enter:find('self.inside = true', 1, true), 'the re-entry guard is set synchronously')
H.ok(enter:find('CreateThread(function()', 1, true), 'the yielding work runs on its own thread')
H.ok(enter:find('self.generation ~= generation', 1, true),
    'a build finishing after the player left cleans up instead of orphaning props')

local attach = business:match('function Business:attach.-\nend\n')
H.ok(attach and attach:find('option.onSelect = function', 1, true),
    'every target option is wrapped before registration')
H.ok(attach and attach:find('CreateThread(function() select_', 1, true),
    'onSelect never yields on qbtarget\'s own tick thread')

H.ok(main:find("RegisterNetEvent('QBCore:Client:OnJobUpdate'", 1, true), 'job changes are handled')
local jobUpdate = main:match("RegisterNetEvent%('QBCore:Client:OnJobUpdate'.-\nend%)")
H.ok(jobUpdate and jobUpdate:find('CreateThread', 1, true),
    'the job-update handler does not call the server on the event thread')

-- --- no ox_lib in a qblib resource -----------------------------------------
--
-- `cache` and `lib` are ox_lib globals. qblib has neither, and referencing one
-- is a nil index at the worst possible moment rather than a load error.
for name, source in pairs({ business = business, main = main, creator = creator,
    payment = payment, state = state }) do
    local stripped = source:gsub('%-%-[^\n]*', '')
    H.nope(stripped:find('cache%.[%w_]+'), ('%s does not use the ox_lib cache global'):format(name))
    H.nope(stripped:find('[^%w_]lib%.[%w_]+'), ('%s does not use the ox_lib global'):format(name))
end

-- --- teardown --------------------------------------------------------------

H.ok(business:find('local function clearScope', 1, true), 'there is one teardown path')
local clear = business:match('local function clearScope.-\nend')
for _, kind in ipairs({ 'zones', 'blips', 'targets', 'entities' }) do
    H.ok(clear:find('scope.' .. kind, 1, true), ('clearScope releases %s'):format(kind))
end
H.ok(clear:find('pcall(zone.remove)', 1, true),
    'a zone handle exposes a plain remove function, not a method')
-- Entities must go last: a target registration still points at them.
H.ok(clear:find('scope.targets', 1, true) < clear:find('for _, entity in ipairs(scope.entities)', 1, true),
    'targets are removed before the entities they point at')

-- --- the creator writes to the server, never to a file ---------------------

H.nope(creator:find('SaveResourceFile', 1, true), 'the builder never writes a file')
H.nope(creator:find('setClipboard', 1, true), 'the builder never hands back a snippet to paste')
H.ok(creator:find("QB.callback.trigger('qbbusinesses:server:saveModule'", 1, true),
    'a built module goes straight to the server')
H.ok(creator:find('QB.zones.startCreator', 1, true), 'zones are placed in-world')
H.ok(creator:find('QB.placement.start', 1, true), 'props are placed in-world')
H.ok(creator:find('QB.raycast.fromCamera', 1, true), 'an existing object is picked by looking at it')

H.finish('client')
