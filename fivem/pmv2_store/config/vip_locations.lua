-- ─────────────────────────────────────────────────────────────
--  WHERE THE STORE EXISTS IN THE WORLD
--  There is no command to open the shop: players must walk up and use ox_target.
--  All coords below are PLACEHOLDERS. Replace them with your own (vec4 = x, y, z, heading).
-- ─────────────────────────────────────────────────────────────

Config.Interaction = {
    maxDistance       = 8.0,    -- SERVER check: max distance from the store for open/purchase (anti-exploit)
    autoCloseDistance = 6.0,    -- UI closes itself if the player walks further than this
    spawnDistance     = 60.0,   -- peds / display cars spawn when a player is within this range
}

-- ─────────────────────────────────────────────────────────────
--  STORES
--  key        : unique id (used internally)
--  coords     : vec4 position (ped spawns here, or the target zone is placed here)
--  ped        : spawn a ped to interact with. Set ped = false to use an invisible sphere zone instead.
--  target     : ox_target option shown to the player
--  blip       : map blip, or false
--  home       : show the home page (balance, VIP status, link to the webstore) at this store
--  categories : which Config.Categories this store sells (in sidebar order).
--  startPage  : 'home' or a category id. Defaults to the first page.
--  hero       : optional text overrides for this store's landing page (see config/vip_theme.lua)
-- ─────────────────────────────────────────────────────────────
Config.Shops = {
    main = {
        label      = 'Misfits VIP Store',
        coords     = vec4(195.17, -933.77, 30.69, 144.5),
        ped        = { model = 'a_m_y_business_03', scenario = 'WORLD_HUMAN_CLIPBOARD' },
        target     = { icon = 'fa-solid fa-gem', label = 'Open VIP Store', distance = 2.0, radius = 1.5 },
        blip       = { sprite = 617, color = 27, scale = 0.8, label = 'Misfits VIP Store' },
        home       = true,
        categories = { 'items' },
        startPage  = 'home',
    },

    guns = {
        label      = 'Misfits Gun VIP',
        coords     = vec4(22.09, -1105.33, 29.80, 159.0),
        ped        = { model = 's_m_y_ammucity_01' },
        target     = { icon = 'fa-solid fa-gun', label = 'Open Gun VIP Store', distance = 2.0, radius = 1.5 },
        blip       = { sprite = 110, color = 27, scale = 0.8, label = 'Misfits Gun VIP' },
        home       = true,
        categories = { 'weapons' },
        startPage  = 'weapons',
        hero = {
            kicker = 'MISFITS GUN VIP',
            title  = { 'Locked.', 'Loaded. Yours.' },
            text   = 'VIP-only weapons, paid for with your Misfit Coins.',
        },
    },
}

-- ─────────────────────────────────────────────────────────────
--  VEHICLE SHOWROOM
--  Each slot parks a frozen, locked display car at an exact spot.
--  Players ox_target the car to open its purchase screen.
--  `item` must be an item id from config/vip_shop.lua that has a { type = 'vehicle' } reward.
--  The car the player buys goes to their garage (Config.Vehicles in config/vip.lua).
-- ─────────────────────────────────────────────────────────────
Config.Showroom = {
    enabled   = true,
    plateText = 'MISFITS',
    blip      = { coords = vec3(-44.5, -1097.5, 26.4), sprite = 326, color = 27, scale = 0.8, label = 'Misfits VIP Showroom' },
    target    = { icon = 'fa-solid fa-car', distance = 3.0 },

    vehicles = {
        {
            item   = 'veh_adder',
            coords = vec4(-45.65, -1093.98, 25.44, 70.0),
            colors = { 12, 12 },        -- primary, secondary (GTA colour ids). Optional.
            rotate = true,              -- slowly spins on the spot
            rotateSpeed = 0.15,
        },
        {
            item   = 'veh_sultan',
            coords = vec4(-48.27, -1101.33, 25.44, 300.0),
            colors = { 145, 145 },
        },
    },
}
