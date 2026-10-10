fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pmv2_store'
author 'Project Misfits v2'
description 'projectmisfitsrp.com in the city: Misfit Coins wallet, Tebex + website deliveries, VIP shop, vehicle showroom, staff tools'
version '2.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
    'config/vip.lua',
    'config/vip_shop.lua',
    'config/vip_locations.lua',
    'config/vip_theme.lua',
    'config/vip_locale.lua'
}

client_scripts {
    'client/main.lua',
    'client/vip.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',          -- wallet, deliveries, Tebex, staff commands (defines Store for the VIP files)
    'config/vip_handlers.lua',
    'server/vip/bridge.lua',
    'server/vip/database.lua',
    'server/vip/vouchers.lua',
    'server/vip/rewards.lua',
    'server/vip/shop.lua',
    'server/vip/showroom.lua',
    'server/vip/admin.lua',
    'server/vip/init.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/img/*'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target'
}
