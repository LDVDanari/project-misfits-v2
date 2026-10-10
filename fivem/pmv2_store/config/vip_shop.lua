-- ─────────────────────────────────────────────────────────────
--  CATEGORIES
--  Which store shows which category is set in config/vip_locations.lua.
--  icon: one of  home | box | target | gear | car | gift | bag | star | coin
-- ─────────────────────────────────────────────────────────────
Config.Categories = {
    { id = 'items',    label = 'Items & Bundles', icon = 'box' },
    { id = 'weapons',  label = 'Weapons',         icon = 'target' },
    { id = 'vehicles', label = 'Vehicles',        icon = 'car' },   -- sold at the showroom cars (config/vip_locations.lua)
}

-- ─────────────────────────────────────────────────────────────
--  ITEMS
--  Required : id (unique), category, label, rewards
--  Optional : description, image
--             price    = cost in Misfit Coins (taken from the store wallet)
--             pools    = { 'monthly_pick' } / pickCost   (voucher mode)
--             limit    = max times one player can ever buy it
--             stackable = true, maxQty = 5   lets the basket buy several at once
--             specs    = { { 'Label', 'Value' }, ... }   shown on the showroom panel (vehicles)
--
--  image: bare filename -> ox_inventory images, 'img/x.png' -> web/img/, or a full https:// URL
--
--  rewards = list, every entry has a `type`:
--    { type = 'item',    name = 'lockpick', count = 5, metadata = {} }   (weapons are ox_inventory items too)
--    { type = 'money',   account = 'bank', amount = 25000 }
--    { type = 'vehicle', model = 'adder' }
--    { type = 'credits', amount = 500 }                          adds Misfit Coins to their wallet
--    { type = 'voucher', pool = 'monthly_pick', picks = 1 }
--    { type = 'custom',  handler = 'chat_color', color = 'red' }   -> config/vip_handlers.lua
--  Any reward may add `label = '...'` to control how it is described in the UI.
-- ─────────────────────────────────────────────────────────────
Config.Items = {
    -- ── Items & Bundles (main store) ──
    {
        id = 'itm_starter', category = 'items', label = 'Starter Bundle',
        description = 'Phone, radio, lockpicks and $10,000 cash to get rolling.',
        image = 'phone.png', price = 150, limit = 1,
        rewards = {
            { type = 'item', name = 'phone', count = 1 },
            { type = 'item', name = 'radio', count = 1 },
            { type = 'item', name = 'lockpick', count = 5 },
            { type = 'money', account = 'cash', amount = 10000 },
        },
    },
    {
        id = 'itm_lockpicks', category = 'items', label = 'Lockpick Kit x5',
        description = 'Five lockpicks.',
        image = 'lockpick.png', price = 25, stackable = true, maxQty = 5,
        rewards = { { type = 'item', name = 'lockpick', count = 5 } },
    },
    {
        id = 'itm_cash_25k', category = 'items', label = '$25,000 Bank Deposit',
        description = 'Deposited straight into your bank account.',
        image = 'money.png', price = 100, stackable = true, maxQty = 4,
        rewards = { { type = 'money', account = 'bank', amount = 25000 } },
    },

    -- ── Weapons (Gun VIP store) ──
    {
        id = 'wpn_pistol', category = 'weapons', label = 'Pistol',
        description = 'Reliable sidearm with 60 rounds.',
        image = 'WEAPON_PISTOL.png', price = 120,
        rewards = { { type = 'item', name = 'WEAPON_PISTOL', count = 1 }, { type = 'item', name = 'ammo-9', count = 60 } },
    },
    {
        id = 'wpn_smg', category = 'weapons', label = 'SMG',
        description = 'Compact SMG with 120 rounds. Silver VIP and up.',
        image = 'WEAPON_SMG.png', price = 450,
        rewards = { { type = 'item', name = 'WEAPON_SMG', count = 1 }, { type = 'item', name = 'ammo-9', count = 120 } },
    },
    {
        id = 'wpn_ammo', category = 'weapons', label = '9mm Ammo x120',
        description = 'Two boxes of 9mm.',
        image = 'ammo-9.png', price = 30, stackable = true, maxQty = 5,
        rewards = { { type = 'item', name = 'ammo-9', count = 120 } },
    },

    -- ── Vehicles (showroom) ──
    {
        id = 'veh_adder', category = 'vehicles', label = 'Truffade Adder',
        description = 'Hypercar. Delivered straight to your garage.',
        image = 'img/adder.png', price = 25, limit = 1,
        specs = { { 'Class', 'Super' }, { 'Seats', '2' }, { 'Drive', 'AWD' } },
        rewards = { { type = 'vehicle', model = 'adder', label = 'Truffade Adder' } },
    },
    {
        id = 'veh_sultan', category = 'vehicles', label = 'Karin Sultan RS',
        description = 'Tuner favorite. Delivered straight to your garage.',
        image = 'img/sultan.png', price = 25, limit = 1,
        specs = { { 'Class', 'Sports' }, { 'Seats', '4' }, { 'Drive', 'AWD' } },
        rewards = { { type = 'vehicle', model = 'sultanrs', label = 'Karin Sultan RS' } },
    },
}
