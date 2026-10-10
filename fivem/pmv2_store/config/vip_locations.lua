-- ─────────────────────────────────────────────────────────────
--  WHERE THE STORE EXISTS IN THE WORLD
--  There is no command to open the shop: players walk up to the ped and use ox_target.
--  Coords are vector4(x, y, z, heading).
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
--  home       : show the home page (balance + link to the webstore) at this store
--  categories : which Config.Categories this store sells (in sidebar order).
--  startPage  : 'home' or a category id. Defaults to the first page.
--  hero       : optional text overrides for this store's landing page (see config/vip_theme.lua)
-- ─────────────────────────────────────────────────────────────
Config.Shops = {
    main = {
        label      = 'Misfits VIP Store',
        coords     = vector4(523.85, -3080.03, 6.06, 331.65),
        ped        = { model = 'a_m_y_business_03', scenario = 'WORLD_HUMAN_CLIPBOARD' },
        target     = { icon = 'fa-solid fa-gem', label = 'Open VIP Store', distance = 2.0, radius = 1.5 },
        blip       = { sprite = 617, color = 27, scale = 0.8, label = 'Misfits VIP Store' },
        home       = true,
        categories = { 'items' },
        startPage  = 'home',
    },

    guns = {
        label      = 'Misfits Gun VIP',
        coords     = vector4(531.68, -3080.14, 6.06, 5.67),
        ped        = { model = 's_m_y_ammucity_01' },
        target     = { icon = 'fa-solid fa-gun', label = 'Open Gun VIP Store', distance = 2.0, radius = 1.5 },
        blip       = false,
        home       = true,
        categories = { 'weapons' },
        startPage  = 'weapons',
        hero = {
            kicker = 'MISFITS GUN VIP',
            title  = { 'Locked.', 'Loaded. Yours.' },
            text   = 'Weapons, paid for with your Misfit Coins.',
        },
    },
}

-- ─────────────────────────────────────────────────────────────
--  VEHICLE SHOWROOM
--  Each slot parks a frozen, locked display car. Walk up to one and a panel
--  slides in on the left with the car's name, stats and price:
--    [G] Buy         -> press G again within a few seconds to confirm. The coins are taken,
--                       the car is saved as yours and you're put in it at `spawns`.
--    [B] Test Drive  -> you're put in a loaner at `spawns` for `testDrive.seconds`,
--                       then it's removed and you're brought back to the showroom.
--  `item` must be an item id from config/vip_shop.lua with a { type = 'vehicle' } reward
--  (its price, limit and specs are used here).
-- ─────────────────────────────────────────────────────────────
Config.Showroom = {
    enabled   = true,
    plateText = 'MISFITS',            -- plate on the display cars
    blip      = false,                -- only the VIP Store has a blip
    interactDistance = 2.6,           -- how close to a display car before its panel shows

    keys = {
        buy  = { control = 47, label = 'G' },   -- 47 = INPUT_DETONATE (G)
        test = { control = 29, label = 'B' },   -- 29 = INPUT_SPECIAL_ABILITY_SECONDARY (B)
    },
    confirmSeconds = 6,               -- how long the "press G again" confirm stays armed

    -- Where bought cars and test drive cars appear (outside). The first clear spot is used.
    -- SET THESE: stand where the car should appear, facing the way it should face, and type
    -- /showroomspot (admin). It copies a ready-to-paste vector4 to your clipboard.
    spawns = {
        vector4(540.20, -3066.50, 5.95, 270.0),   -- PLACEHOLDER: replace with your own spot
    },

    testDrive = {
        enabled  = true,
        seconds  = 90,                -- length of a test drive
        cooldown = 120,               -- seconds before the same player can test drive again
        plate    = 'TESTDRV',
        leaveSeconds = 8,             -- out of the car this long = test drive ends
    },

    vehicles = {
        {
            item   = 'veh_adder',
            coords = vector4(517.28, -3063.96, 5.66, 289.13),
            colors = { 12, 12 },        -- primary, secondary (GTA colour ids). Optional.
            rotate = false,             -- slowly spins on the spot
            rotateSpeed = 0.15,
        },
        {
            item   = 'veh_sultan',
            coords = vector4(517.38, -3069.16, 5.44, 286.30),
            colors = { 145, 145 },
        },
    },
}
