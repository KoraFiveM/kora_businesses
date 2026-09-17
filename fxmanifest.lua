fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbbusinesses'
author 'qbcore2'
version '1.0.0'
description 'Database-backed, live-editable modular businesses for the qblib framework'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbinventory'
dependency 'qbtarget'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
    'shared/schema.lua',
    'shared/recipes/*.lua',
    'shared/shopitems/*.lua',
    'shared/businesses/*.lua',
    'shared/config_registration.lua',
}

-- Load order is deliberate: `state` owns the registry every other file reads,
-- and `main` runs the boot sequence once the rest have registered themselves.
server_scripts {
    'server/config.lua',
    'server/state.lua',
    'server/logs.lua',
    'server/staff.lua',
    'server/pos.lua',
    'server/crafting.lua',
    'server/payment.lua',
    'server/register.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'client/state.lua',
    'client/business.lua',
    'client/payment.lua',
    'client/creator.lua',
    'client/main.lua',
}

files {
    'sql/001_businesses.sql',
}
