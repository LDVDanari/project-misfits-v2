# pmv2_store — Install

Everything Misfit Coins in one resource: projectmisfitsrp.com / Tebex purchases, the coin wallet,
and the in-city VIP shop + vehicle showroom. (This replaces `misfits_vip`. See "Moving off misfits_vip" below.)

- Links each player's Discord account to their character
- Hands over anything waiting for them (coin messages, items) while they're online
- One Misfit Coins balance: the webstore, `/coins`, the VIP shop and staff commands all use the same wallet
- In-city VIP shop: store peds (main + guns), purchase limits, and a vehicle showroom with buy + test drive
- `/coins` for players, plus exports so other scripts can spend coins
- Staff tools: `/coinsadd`, `/coinsremove`, `/storelookup`, `/storedone`, `/vipadmin`

Needs: `qbx_core`, `qbx_vehicles`, `ox_lib`, `oxmysql`, `ox_inventory`, `ox_target` (and `qbx_vehiclekeys` for showroom keys).

## Install
1. Run `db/pmv2_store.sql` (in the website repo) on the **same database** your server uses.
2. Copy this `pmv2_store` folder into your resources.
3. In `server.cfg`, after `oxmysql`, `ox_lib`, `qbx_core`, `ox_inventory` and `ox_target`:
   ```
   ensure pmv2_store
   ```
4. Restart. The console should say `[pmv2_store] Ready.`

Players need the **Discord app open** when they launch FiveM. That's how the city knows
which Discord account they bought with. If it can't see Discord, `/coins` tells them how to fix it.

## Tebex (Misfit Coin purchases)
Payments go through Tebex. Tebex runs a console command on the server for each purchase.

1. Link the server to Tebex: add `sv_tebexSecret <your secret>` at the **bottom** of `server.cfg`
   (Tebex control panel -> Integrations -> Game Servers -> FiveM).
2. On **each coin package** in Tebex, add this command and tick **execute even if the player is offline**:
   ```
   pmv2_tebex {id} {transaction} {packageId} {purchaseQuantity} 10
   ```
   Change the last number to the coins in one of that package (10, 25, 50, 100, 250, 500).
3. Under the package's **Chargeback** and **Refund** commands, add the same line with `pmv2_tebex_reverse`:
   ```
   pmv2_tebex_reverse {id} {transaction} {packageId} {purchaseQuantity} 10
   ```

What happens:
- `{id}` is the buyer's FiveM (Cfx.re) account. The coins go to the store wallet of the Discord
  account that FiveM account plays with - right away if they're online, otherwise when they next load in.
- If FiveM can't see their Discord, they're told to open Discord and reconnect; the coins wait.
- Each transaction is only ever credited once, even if Tebex sends the command again.
- A refund/chargeback takes the coins back (balance can go negative if they already spent them).
  A refund that lands before the coins were credited cancels the purchase.
- Every purchase and reversal is posted to `Config.LogWebhook` with the balance before -> after.
- The `pmv2_store_tebex` table is created automatically.

## VIP shop
Players walk up to a store ped and use ox_target. There's no command to open it.
Everything is paid with Misfit Coins from the store wallet. There is **no /redeem**: coins bought on the
website arrive in the wallet on their own (see Tebex above), and the shop just spends them.
Only the main VIP Store has a map blip.

| File | What's in it |
|---|---|
| `config/vip.lua` | Economy mode (coins / vouchers / both), voucher pools, `/vipadmin` permission, garage for bought cars |
| `config/vip_shop.lua` | Categories and every item for sale (price, buy limit, rewards, showroom car specs) |
| `config/vip_locations.lua` | Store peds/blips (main store, gun store) and the vehicle showroom |
| `config/vip_theme.lua` | Logo, colors, webstore button, home page text |
| `config/vip_locale.lua` | Every message |
| `config/vip_handlers.lua` | Custom reward types + the OnPurchase hook |

Item images: a bare filename (`lockpick.png`) loads from ox_inventory; `img/x.png` loads from `web/img/`.

How a purchase works: the server checks the player is standing at that store, the item is sold there,
the buy limit and that they can carry it. Then it takes the coins (only if the balance covers it),
delivers, and if delivery fails the coins go straight back. Coin purchases show up in the Discord log as
"Misfit Coins spent" with the item and balance before → after.

Vouchers and buy limits are saved per **character** (citizenid). Coins are per **Discord account**.

## Vehicle showroom
Display cars sit at `Config.Showroom.vehicles`. Walk up to one and a panel slides in on the left with
the car's name, top speed, acceleration/braking/handling bars, its specs and price.

- **G**: buy. The first press arms it ("Press again to confirm"). Press **G** again within
  `confirmSeconds` and the coins are taken, the car is saved as theirs (qbx_vehicles, garage
  `Config.Vehicles.garage`) and they're put in it outside with the keys and a full tank.
- **B**: test drive. They're put in a loaner outside for `testDrive.seconds`, with a timer at the top of
  the screen. When time's up (or they've been out of it for `leaveSeconds`) the screen fades, the car is
  removed and they're back in the showroom. One test drive at a time, `testDrive.cooldown` between them.

Each showroom car is an item in `config/vip_shop.lua` (category `vehicles`) with a `{ type = 'vehicle', model = '...' }`
reward. Its `price`, `limit` and `specs` are what the panel shows. Add a car = add an item + a slot.

**Set the spawn point before going live.** Stand where bought/test cars should appear, facing the way
they should face, and type `/showroomspot` (admin). It copies a line like `vector4(540.20, -3066.50, 5.95, 270.00),`
to your clipboard: paste it into `Config.Showroom.spawns`. Add 2-3 spots so one parked car doesn't block
purchases (the first clear one is used; if they're all blocked the player isn't charged and is told to move it).

If the car can't be spawned for any reason, the purchase still goes through and the car waits in their garage.

### Moving off misfits_vip
1. Stop it and take it out of `server.cfg`: delete the `ensure misfits_vip` line and the `misfits_vip` folder.
2. Delete these lines from `server.cfg` if you added them: `set misfits_vip:tebex_secret ...` and `set misfits_vip:webhook ...`.
   Tebex keeps using `sv_tebexSecret` and the `pmv2_tebex` package commands above. Remove any old
   misfits_vip package commands in Tebex (the `/redeem` flow is gone).
3. Restart `pmv2_store`. It uses the same `misfits_vip_*` tables, so purchase history (buy limits) carries over.
   VIP tiers are gone, so any tiers people had in misfits_vip no longer do anything.
4. Any coins a character still had in the old misfits_vip balance are moved into that player's store wallet
   the next time they load in (logged as "Moved from old misfits_vip balance"). Turn this off with
   `Config.MoveOldVipCoins = false`.
5. Scripts that used `exports.misfits_vip:GiveVoucher` should use `exports.pmv2_store:GiveVoucher`. The tier exports
   (IsVip, GetTier, HasTier, GetPerk...) were removed with the tiers.

## Discord logs
Put a channel webhook URL in `Config.LogWebhook` (config.lua). It logs:
- **Coins spent** in the city: who, what they bought, cost, balance before → after, which script
- **Coins added / removed**: by staff (with reason) or by a script, balance before → after
- **Store deliveries** received in the city, and any that **failed**
- **Packages set up** with `/storedone`
- **VIP shop**: showroom cars bought (with plate), failed deliveries (with the refund), voucher purchases and `/vipadmin` actions

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
| `/vipadmin info [id or citizenid]` | Admin | Coins, voucher picks and what they've bought |
| `/vipadmin givevoucher [id or citizenid] [pool] [picks] [expiry days]` | Admin | Gives voucher picks |
| `/vipadmin pools` | Admin | Lists voucher pool names |
| `/showroomspot` | Admin | Copies your position as a showroom spawn point |

Staff = `Config.StaffGroups` in `config.lua` (default `group.admin`). Every staff coin change
is saved with who did it and why. `/vipadmin` uses `Config.Admin.restricted` in `config/vip.lua`.

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

-- Voucher picks (only if Config.Economy.mode uses vouchers)
exports.pmv2_store:GiveVoucher(citizenid, 'monthly_pick', 1, 45)

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
