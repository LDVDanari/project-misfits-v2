fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pmv2_housing'
author 'Project Misfits v2'
description 'PMv2 Housing: MLOs, shells, IPLs and apartment buildings with realtors, rent, tenants, keys, utilities and bills'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared.lua'
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua',
    'client/menus.lua',
    'client/creator.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/main.lua',
    'server/realtor.lua',
    'server/owner.lua',
    'server/billing.lua'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'ox_doorlock'
}
