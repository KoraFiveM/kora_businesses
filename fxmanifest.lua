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
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
}

server_scripts {
}

client_scripts {
}

files {
    'locales/**.lua',
    'jobs/**/**.lua',
    'sql/**.sql',
    'docs/**.md',
    'init.lua'
}
