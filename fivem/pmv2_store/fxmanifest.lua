fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pmv2_store'
author 'Project Misfits v2'
description 'Delivers projectmisfitsrp.com purchases in the city: Misfit Coins, deliveries, staff tools'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql'
}
