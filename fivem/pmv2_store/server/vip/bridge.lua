-- ─────────────────────────────────────────────────────────────
--  FRAMEWORK BRIDGE (server). Everything framework-specific lives here.
--  Written for Qbox (qbx_core + ox_inventory). To port to another framework,
--  rewrite only this file.
-- ─────────────────────────────────────────────────────────────
Bridge = {}

function Bridge.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

---@return string|nil
function Bridge.GetCitizenId(src)
    local player = Bridge.GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

---@return string|nil license (rockstar license identifier)
function Bridge.GetLicense(src)
    local player = Bridge.GetPlayer(src)
    if player and player.PlayerData.license then return player.PlayerData.license end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.GetCharName(src)
    local player = Bridge.GetPlayer(src)
    if not player then return 'Unknown' end
    local ci = player.PlayerData.charinfo or {}
    return ('%s %s'):format(ci.firstname or '?', ci.lastname or '?')
end

--- Returns the server id of an ONLINE player by citizenid, or nil if offline.
function Bridge.GetSourceByCitizenId(citizenid)
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    return player and player.PlayerData.source or nil
end

function Bridge.Notify(src, description, ntype)
    if not src then return end
    lib.notify(src, { title = 'VIP', description = description, type = ntype or 'inform' })
end

-- ── Inventory ────────────────────────────────────────────────
function Bridge.CanCarry(src, name, count)
    return exports.ox_inventory:CanCarryItem(src, name, count or 1) and true or false
end

function Bridge.AddItem(src, name, count, metadata)
    local ok, res = pcall(exports.ox_inventory.AddItem, exports.ox_inventory, src, name, count or 1, metadata)
    return ok and res and true or false
end

function Bridge.ItemLabel(name)
    local ok, data = pcall(exports.ox_inventory.Items, exports.ox_inventory, name)
    if ok and data and data.label then return data.label end
    return name
end

-- ── Money ────────────────────────────────────────────────────
function Bridge.AddMoney(src, account, amount, reason)
    local ok, res = pcall(exports.qbx_core.AddMoney, exports.qbx_core, src, account or 'bank', amount, reason or 'pmv2_store vip shop')
    return ok and res ~= false
end

-- ── Vehicles ─────────────────────────────────────────────────
local function plateExists(plate)
    return MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) ~= nil
end

local function newPlate()
    for _ = 1, 20 do
        local plate = lib.string.random(Config.Vehicles.plateFormat):upper()
        if not plateExists(plate) then return plate end
    end
    return nil
end

--- Saves an owned vehicle in the player's garage.
---@param props? table extra vehicle props (colors...). The plate is generated here.
---@return boolean ok, string|nil plateOrError, integer|nil vehicleId
function Bridge.AddVehicle(src, model, garage, props)
    local player = Bridge.GetPlayer(src)
    if not player then return false, 'no_player' end
    local citizenid = player.PlayerData.citizenid
    local plate = newPlate()
    if not plate then return false, 'plate' end
    garage = garage or Config.Vehicles.garage
    props = props or {}
    props.plate = plate

    -- Preferred path: qbx_vehicles export
    local ok, id = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model     = model,
            citizenid = citizenid,
            garage    = garage,
            props     = props,
        })
    end)
    if ok and id then return true, plate, id end

    -- Fallback: raw insert into player_vehicles (standard Qbox/QBCore schema)
    local inserted = MySQL.insert.await(
        'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { Bridge.GetLicense(src), citizenid, model, joaat(model), '{}', plate, garage, Config.Vehicles.state }
    )
    if inserted then return true, plate, inserted end
    return false, 'insert_failed'
end

-- ── Discord logs ─────────────────────────────────────────────
-- VIP shop logs go to the same webhook as the rest of the store (Config.LogWebhook in config.lua).
Discord = {}

---@param fields? table[] { { name=, value=, inline? } }
function Discord.Log(title, description, fields, color)
    local list = {}
    for _, f in ipairs(fields or {}) do list[#list + 1] = { f.name, f.value, f.inline } end
    Store.Log(title, color or Store.Colors.spend, list, description)
end

-- ── Spawning (Qbox) ──────────────────────────────────────────
--- Spawns a networked vehicle at `coords` with the player in the driver seat.
---@return integer|nil entity, integer|nil netId
function Bridge.SpawnVehicle(src, model, coords, props)
    local ok, netId, veh = pcall(qbx.spawnVehicle, {
        model       = model,
        spawnSource = coords,
        warp        = GetPlayerPed(src),
        props       = props,
    })
    if not ok then
        print(('[pmv2_store] spawn %s failed: %s'):format(tostring(model), tostring(netId)))
        return nil
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    Entity(veh).state:set('fuel', 100.0, true)
    return veh, netId
end

-- ── Vehicle keys (tgiann-hotwire) ───────────────────────────────
-- tgiann keys are real `car_key` items in ox_inventory. tgiann has no "remove key" export
-- (keys are physical), so taking a key back = removing that car_key item from the player.
local KEYS     = Config.Vehicles.keys or {}
local KEY_RES  = KEYS.resource or 'tgiann-hotwire'
local KEY_ITEM = KEYS.item or 'car_key'

--- Plates come back from GTA padded to 8 chars; compare them trimmed + uppercased.
function Bridge.CleanPlate(plate)
    local p = tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return p:upper()
end

--- Gives the player a key for this plate. isNew = true makes a fresh key id, so any older
--- key for the same plate stops working.
function Bridge.GiveKeys(src, veh, plate, isNew)
    if (not plate or plate == '') and veh and DoesEntityExist(veh) then
        plate = GetVehicleNumberPlateText(veh)
    end
    plate = Bridge.CleanPlate(plate)
    if plate == '' then return false end

    if GetResourceState(KEY_RES) == 'started' then
        local ok, err = pcall(function()
            exports[KEY_RES]:GiveKeyPlate(src, plate, isNew == true)
        end)
        if ok then return true end
        print(('[pmv2_store] %s:GiveKeyPlate failed for %s (%s): %s'):format(KEY_RES, src, plate, tostring(err)))
    end

    -- Fallbacks for other key scripts.
    if GetResourceState('qbx_vehiclekeys') == 'started' and veh then
        local ok = pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
        if ok then return true end
    end
    TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    return false
end

-- A key's plate lives in its metadata. Plates are max 8 chars, so only short strings are
-- checked (skips labels/descriptions) and the field name doesn't matter.
local function keyPlateMatches(metadata, test)
    if type(metadata) ~= 'table' then return false end
    for _, value in pairs(metadata) do
        if type(value) == 'string' and #value <= 8 and test(Bridge.CleanPlate(value)) then
            return true
        end
    end
    return false
end

--- Removes every car_key in the player's inventory whose plate passes `test(plate)`.
--- `test` can also be a plate string for an exact match. Returns how many were removed.
function Bridge.RemoveKeys(src, test)
    if GetResourceState('ox_inventory') ~= 'started' then return 0 end
    if type(test) ~= 'function' then
        local want = Bridge.CleanPlate(test)
        test = function(p) return p == want end
    end

    local ok, items = pcall(function() return exports.ox_inventory:GetInventoryItems(src) end)
    if not ok or type(items) ~= 'table' then return 0 end

    local removed = 0
    for _, item in pairs(items) do
        if item and item.name == KEY_ITEM and keyPlateMatches(item.metadata, test) then
            local count = item.count or 1
            if exports.ox_inventory:RemoveItem(src, KEY_ITEM, count, nil, item.slot) then
                removed = removed + count
            end
        end
    end
    return removed
end

--- Marks a garage vehicle as "out" (it was just spawned) so the garage lets them store it.
function Bridge.SetVehicleOut(veh, vehicleId)
    if not vehicleId then return end
    Entity(veh).state:set('vehicleid', vehicleId, false)
    MySQL.update('UPDATE player_vehicles SET state = 0 WHERE id = ?', { vehicleId })
end
