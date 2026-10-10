-- ─────────────────────────────────────────────────────────────
--  VIP SHOP + SHOWROOM  (in-city store, paid with Misfit Coins)
--
--  Coins come from the store wallet in config.lua / server/main.lua:
--  the same balance players top up on projectmisfitsrp.com, see with /coins,
--  and staff change with /coinsadd and /coinsremove. There is no separate
--  VIP balance and no /redeem: website purchases land in the wallet on their own.
--
--  Other VIP files:
--    config/vip_shop.lua       categories + everything for sale
--    config/vip_locations.lua  store peds/zones, blips, vehicle showroom (buy / test drive)
--    config/vip_theme.lua      UI branding/colors
--    config/vip_locale.lua     every message
--    config/vip_handlers.lua   custom reward handlers + hooks (server only)
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
--  ECONOMY
--  'credits' : items are bought with Misfit Coins (the store wallet)
--  'voucher' : items are bought with voucher "picks" from named pools
--  'both'    : items can list both `price` (coins) and `pools` (vouchers)
-- ─────────────────────────────────────────────────────────────
Config.Economy = {
    mode        = 'credits',
    creditsName = Config.CoinName or 'Misfit Coins',
}

-- Voucher pools (only used if mode is 'voucher' or 'both')
Config.Pools = {
    monthly_pick = { label = 'Monthly Pick' },
}

-- ─────────────────────────────────────────────────────────────
--  ADMIN  (/vipadmin). Uses ox_lib `restricted` (ACE principal). Console always works.
--  Coins are handled by /coinsadd and /coinsremove now.
-- ─────────────────────────────────────────────────────────────
Config.Admin = {
    command    = 'vipadmin',
    restricted = 'group.admin',
}

-- ─────────────────────────────────────────────────────────────
--  SHOP / DELIVERY
-- ─────────────────────────────────────────────────────────────
Config.Shop = {
    maxCart   = 10,                                -- max total items per checkout
    imageBase = 'nui://ox_inventory/web/images/',  -- used when an item `image` is a bare filename
}

Config.Vehicles = {
    -- Bought vehicles are saved as owned (qbx_vehicles) under this garage. Showroom cars are then
    -- spawned outside with the buyer in them; if that spawn fails the car waits in this garage instead.
    garage      = 'pillboxgarage',       -- must match a garage name in your garage resource
    state       = 1,                     -- 1 = in garage (used by the fallback insert only)
    plateFormat = '1AA111AA',            -- ox_lib pattern: 1 = digit, A = letter, . = any
}

-- ─────────────────────────────────────────────────────────────
--  OLD misfits_vip COIN BALANCES
--  If a character still has coins sitting in the old misfits_vip_players.credits
--  column, they're moved into that player's store wallet the next time they load in
--  (the old column is zeroed first, so it can only happen once). false = leave them.
-- ─────────────────────────────────────────────────────────────
Config.MoveOldVipCoins = true
