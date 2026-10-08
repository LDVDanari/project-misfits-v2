Config = {}

-- How often (seconds) to check for purchases waiting on players who are online.
-- Players also get checked a few seconds after they load a character.
Config.CheckSeconds = 30

-- Who can use the staff commands (/coinsadd, /coinsremove, /storelookup, /storedone).
Config.StaffGroups = { 'group.admin' }

-- Shown in messages.
Config.CoinName = 'Misfit Coins'
Config.StoreUrl = 'projectmisfitsrp.com'

-- A delivery that keeps failing (e.g. inventory full) is retried this many times,
-- then marked failed so staff can see it in /storelookup.
Config.MaxAttempts = 10

-- Allow 'give_item' deliveries through ox_inventory.
Config.ItemDeliveries = true

-- Extra console logging.
Config.Debug = false
