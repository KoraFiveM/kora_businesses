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

-- --- AppShell management and editor resume ---------------------------------

H.ok(creator:find("local APP_ID = 'qbbusinesses:management'", 1, true),
    'the management console has one namespaced AppShell id')
H.ok(creator:find('QB.nui.registerApp(definition)', 1, true),
    'business management is registered with AppShell')
H.ok(creator:find("openManagement(state, 'management', 'modules')", 1, true),
    'the console resumes on the selected business module tab after an editor')
H.ok(creator:find("id = 'businesses:add-module'", 1, true)
    and creator:find("id = 'businesses:edit-module'", 1, true),
    'module creation and rebuilding are AppShell actions')
H.ok(creator:find('closeBeforeAction = true', 1, true),
    'world-editor actions release AppShell focus before running')
H.ok(creator:find('state.moduleIndex = position or index', 1, true),
    'editor resume preserves the selected module')
H.ok(creator:find('function Creator.refresh()', 1, true)
    and main:find('Creator.refresh()', 1, true),
    'replicated business and staff changes refresh an open management console')
H.ok(creator:find("QB.callback.trigger('qbbusinesses:server:removeModule'", 1, true)
    and creator:find("QB.callback.trigger('qbbusinesses:server:editBusiness'", 1, true)
    and creator:find("QB.callback.trigger('qbbusinesses:server:deleteBusiness'", 1, true),
    'AppShell actions still submit intent through the authoritative server callbacks')

local crafting = creator:match('fieldsFor%.Crafting = function%(%).-\nend')
H.ok(crafting and crafting:find("type = 'multiselect'", 1, true),
    'crafting benches choose recipes with the shared multiselect field')
H.ok(crafting and crafting:find('recipes = values.recipes', 1, true),
    'the selected recipe ids are forwarded as intent for schema validation')
H.nope(crafting and crafting:find('while true do', 1, true),
    'crafting no longer loops through one recipe picker per selection')

H.finish('client')
