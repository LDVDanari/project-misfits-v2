# pmv2_housing — Phase 1 (core)

MLOs, shells, IPLs and apartment buildings. Realtors list them, players buy or rent,
owners add tenants and keyholders, and bills / utilities / dirt run on adjustable rates.

Coming next: Phase 2 furniture, Phase 3 crime (raids, burglary, alarms, cameras, fence).

## Needs
`qbx_core`, `ox_lib`, `oxmysql`, `ox_inventory`, `ox_target`, `ox_doorlock`, `jg-advancedgarages`.
For GTA interiors: `bob74_ipl`. For shells: the shell pack you own (streamed by its own resource).

## Install
1. Drop `pmv2_housing` in your resources.
2. `server.cfg` — start it **after** ox_inventory, ox_doorlock and jg-advancedgarages:
   ```
   ensure pmv2_housing
   add_ace group.admin pmv2housing.admin allow
   set pmv2_housing_webhook "https://discord.com/api/webhooks/..."   # optional logs
   ```
3. Make sure a `realestate` job exists in qbx_core (or change `Config.Realtor.jobs`).
4. Tables are created automatically on first start (`sql/pmv2_housing.sql` if you want them by hand).
5. Put your shells in `Config.Shells`. Stand inside one and use `/houseoffset` to get its `exit` offset.
6. Check the IPL `exit` spots in `Config.IPLs`, or use "Custom IPL (I'm standing in it)".

## Setting up a property (realtor: /housing)
- **MLO house:** stand at the front door → *Create a property here* → MLO.
  Then: *Doors* (aim at each door, or link existing ox_doorlock doors), *Property area*
  (stand in the middle, set a radius — lights go out inside it when the power is cut),
  *Points* (stash, wardrobe, garage entry + car spawn, electric box, water valve, router).
- **Shell / IPL:** stand at the front door → Create → Shell or IPL. Set the garage points
  outside, then *Go inside* and place stash, wardrobe and the three utility points.
- **Apartments:** stand at the lobby door → Create → Apartment building → *Apartment units* →
  *Add a unit* (shell or IPL). Each unit has its own price, rent, points and owner.
- Toggle **For sale / For rent**, or *Sell / rent to a player here* to offer it directly.

## Starter apartments
Set up one unit as a template → *Use as starter apartment template* (admin), then in config:
`Config.Starter = { enabled = true, building = <building id> }`.
Give one from your character-creation script with
`exports.pmv2_housing:GiveStarterApartment(source)` or `/givestarter <id>`.

## Rates (config.lua)
- `Config.Rent` — rent interval, missed payments before eviction, tenant rent limits.
- `Config.Utilities` — electricity / water / internet cost per hour, property tax %/day,
  shut-off threshold, final warning and repossession amounts, tick speed.
- `Config.Dirt` — dirt per hour, clean time/amount, whether cleaning needs water.
- `Config.Sale` — sell-back %, dirt penalty, transfer fee.
- `Config.Access` — what owners, renters, tenants and keyholders can each do.

## Notes
- Society money goes through `Bridge.AddSociety` in `server/bridge.lua` (Renewed-Banking or
  qbx_management). Change it there if you use another banking script.
- Wardrobe: `Config.Wardrobe` (`illenium` / `qb-clothing`), or add yours in `client/bridge.lua`.
- Players who log out inside an interior are put back at the front door when they log in.
- Linking an *existing* ox_doorlock door replaces its character list with the property's
  owner, renter, tenants and keyholders.
