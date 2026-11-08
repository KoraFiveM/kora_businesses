fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_businesses'
-- Keep the legacy resource name resolvable for exports['qbbusinesses'] callers.
provide 'qbbusinesses'
author 'qbcore2'
version '1.0.0'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'
dependency 'kora_inventory'
dependency 'kora_banking'
dependency 'kora_skills'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_core/init.lua',
    'config.lua',
}

server_scripts {
    '@kora_sql/init.lua',
}

client_scripts {
}

files {
    'locales/**.lua',
    -- List job files explicitly so FiveM includes them in the client packfile.
    -- The server loads server.lua from disk through Kora.require.
    'jobs/cctv/client.lua',
    'jobs/cctv/shared.lua',
    'jobs/garbage/client.lua',
    'jobs/garbage/shared.lua',
    'jobs/hotdog/client.lua',
    'jobs/mechanic/client.lua',
    'jobs/mechanic/shared.lua',
    'jobs/recycle/client.lua',
    'jobs/recycle/sales.lua',
    'jobs/recycle/shared.lua',
    'jobs/taxi/client.lua',
    'jobs/taxi/shared.lua',
    'jobs/tow/client.lua',
    'jobs/tow/shared.lua',
    'docs/**.md',
    'init.lua'
}
