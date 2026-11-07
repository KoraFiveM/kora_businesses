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
    -- Clients get only client/shared job files; jobs/*/server.lua is read from
    -- disk by the server's Kora.require and must never be listed here.
    'jobs/*/client.lua',
    'jobs/*/shared.lua',
    'jobs/recycle/sales.lua',
    'docs/**.md',
    'init.lua'
}
