# pmv2_store — Install

Delivers projectmisfitsrp.com purchases in the city.

- Links each player's Discord account to their character
- Hands over anything waiting for them (coin messages, items) while they're online
- `/coins` for players, plus exports so other scripts (like a VIP shop) can spend coins
- Staff tools: `/coinsadd`, `/coinsremove`, `/storelookup`, `/storedone`

Needs: `qbx_core`, `ox_lib`, `oxmysql` (and `ox_inventory` for item deliveries).

## Install
1. Run `db/pmv2_store.sql` (in the website repo) on the **same database** your server uses.
2. Copy this `pmv2_store` folder into your resources.
3. In `server.cfg`, after `oxmysql`, `ox_lib` and `qbx_core`:
   ```
   ensure pmv2_store
   ```
4. Restart. The console should say `[pmv2_store] Ready.`

Players need the **Discord app open** when they launch FiveM. That's how the city knows
which Discord account they bought with. If it can't see Discord, `/coins` tells them how to fix it.

## Discord logs
Put a channel webhook URL in `Config.LogWebhook` (config.lua). It logs:
- **Coins spent** in the city: who, what they bought, cost, balance before → after, which script
- **Coins added / removed**: by staff (with reason) or by a script, balance before → after
- **Store deliveries** received in the city, and any that **failed**
- **Packages set up** with `/storedone`

Use the same webhook as the website's `STORE_ORDERS_WEBHOOK_URL` to keep everything in one channel
(website purchases also show the balance before → after).

## Commands
| Command | Who | What it does |
|---|---|---|
| `/coins` | Everyone | Shows your Misfit Coin balance |
| `/coinsadd [id or Discord ID] [amount] [reason]` | Staff | Gives coins (offline players by Discord ID if they already have a store account) |
| `/coinsremove [id or Discord ID] [amount] [reason]` | Staff | Takes coins (never below 0) |
| `/storelookup [id, Discord ID or order code]` | Staff | Orders, coins, packages waiting on setup, stuck deliveries (prints to F8) |
| `/storedone [order code]` | Staff | Marks a package order as set up and tells the buyer |

Staff = `Config.StaffGroups` in `config.lua` (default `group.admin`). Every staff coin change
is saved with who did it and why.

## For other scripts
```lua
-- Balance
local coins = exports.pmv2_store:GetCoins(source)

-- Spend (only goes through if they have enough)
local ok, result = exports.pmv2_store:SpendCoins(source, 25, 'VIP shop: neon kit')
if ok then
    -- result = new balance, give them the thing
else
    -- result = 'not_enough_coins', 'no_discord', 'busy', 'invalid_amount' or 'error'
end

-- Give coins (event prizes etc.). Target = server ID or Discord ID
exports.pmv2_store:AddCoins(source, 10, 'Car meet winner')

-- Add a new delivery type, e.g. vehicles from a future store item
exports.pmv2_store:RegisterDeliveryHandler('give_vehicle', function(source, payload, row)
    -- give payload.model to the player...
    return true -- or: return false, 'reason'
end)
```

## How deliveries work
The website adds rows to `pmv2_store_deliveries`. Every 30 seconds (and right after a player
loads in) this resource looks for rows for online players, claims each one so it can't be
handed out twice, delivers it, and marks it delivered. If the player is offline or the server
was down, it waits. If a delivery keeps failing (full inventory, etc.) it's retried up to
`Config.MaxAttempts` times, and staff can see why in `/storelookup`.
