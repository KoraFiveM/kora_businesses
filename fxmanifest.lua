fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_businesses'
author 'qbcore2'
version '0.2.1'

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
    -- Listed explicitly: FiveM globs do not expand `*` in a directory segment.
    'jobs/mechanic/client.lua',
    'jobs/mechanic/shared.lua',
    'jobs/taxi/client.lua',
    'jobs/taxi/shared.lua',
    'jobs/garbage/client.lua',
    'jobs/garbage/shared.lua',
    'jobs/recycle/client.lua',
    'jobs/recycle/shared.lua',
    'jobs/recycle/sales.lua',
    'jobs/tow/client.lua',
    'jobs/tow/shared.lua',
    'jobs/cctv/client.lua',
    'jobs/cctv/shared.lua',
    'docs/**.md',
    'init.lua'
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
