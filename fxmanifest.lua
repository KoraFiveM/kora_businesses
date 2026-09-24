fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbbusinesses'
author 'qbcore2'
version '1.0.0'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
}

server_scripts {
}

client_scripts {
}

files {
    'sql/001_businesses.sql',
    'jobs/*/*.lua',
}
