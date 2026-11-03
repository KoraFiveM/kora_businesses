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
dependency 'kora_theme'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
    '@kora_core/init.lua',
    'config.lua',
}

server_scripts {
}

client_scripts {
    '@kora_theme/client/bridge.lua',
}

-- Taxi fare meter screen (jobs/taxi/meter.lua).
ui_page 'jobs/taxi/html/meter.html'

files {
    'locales/**.lua',
    'jobs/**/**.lua',
    'jobs/hotdog/icon.png',
    'jobs/taxi/html/meter.html',
    'jobs/taxi/html/meter.css',
    'jobs/taxi/html/meter.js',
    'sql/**.sql',
    'docs/**.md',
    'init.lua'
}
