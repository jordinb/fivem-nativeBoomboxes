fx_version 'cerulean'
game 'gta5'

author 'Infamous Development Studios / Jordin B.'
description 'Persistent boomboxes using GTA V native placed-prop radio emitters'
version '2.2.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/stations.lua'
}

client_scripts {
    'client/placement_editor.lua',
    'client/placement.lua',
    'client/audio.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target'
}
