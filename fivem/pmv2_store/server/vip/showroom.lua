-- ─────────────────────────────────────────────────────────────
--  VEHICLE SHOWROOM (server)
--  Buy: coins are taken, the car is saved as owned and spawned at Config.Showroom.spawns
--       with the buyer in it. Test drive: a loaner for a set time, then removed.
--  Every request re-checks the player is standing at that display car.
-- ─────────────────────────────────────────────────────────────
local SR = Config.Showroom
local testDrives = {}   -- [src] = { veh, endsAt (ms), back = vector4 }
local lastTest = {}     -- [src] = os.time() of their last test drive

local function slotInfo(src, idx)
    if not SR.enabled then return nil, 'bad_store' end
    local slot = SR.vehicles[tonumber(idx) or -1]
    if not slot then return nil, 'bad_store' end
    local c = slot.coords
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(c.x, c.y, c.z)) > Config.Interaction.maxDistance then return nil, 'too_far' end
    local item = Shop.Item(slot.item)
    if not item then return nil, 'item_not_found' end
    local model
    for _, r in ipairs(item.rewards or {}) do
        if r.type == 'vehicle' then model = r.model end
    end
    if not model then return nil, 'item_not_found' end
    return slot, item, model
end

-- First spawn point with no vehicle parked on it.
local function freeSpawn()
    local vehicles = GetAllVehicles()
    for _, c in ipairs(SR.spawns or {}) do
        local pos, clear = vec3(c.x, c.y, c.z), true
        for i = 1, #vehicles do
            if #(GetEntityCoords(vehicles[i]) - pos) < 3.5 then clear = false break end
        end
        if clear then return c end
    end
end

local function colorProps(slot)
    if not slot.colors then return {} end
    return { color1 = slot.colors[1], color2 = slot.colors[2] }
end

-- ── Panel info ───────────────────────────────────────────────
lib.callback.register('pmv2_store:showroom:info', function(src, idx)
    local slot, item, model = slotInfo(src, idx)
    if not slot then return { error = L(item) } end
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return { error = L('no_player') } end
    local coins, coinErr = Store.GetCoins(src)
    local owned = DB.CountPurchases(citizenid, item.id)
    return {
        idx = tonumber(idx),
        model = model,
        label = item.label,
        description = item.description,
        specs = item.specs,
        price = item.price,
        coins = coins,
        noDiscord = coinErr == 'no_discord',
        owned = owned,
        soldOut = item.limit ~= nil and owned >= item.limit,
        creditsName = Config.Economy.creditsName,
        testDrive = SR.testDrive.enabled,
    }
end)

-- ── Buy ──────────────────────────────────────────────────────
lib.callback.register('pmv2_store:showroom:buy', function(src, idx)
    local fail = function(msg) return { ok = false, message = msg } end
    local slot, item, model = slotInfo(src, idx)
    if not slot then return fail(L(item)) end
    if not item.price then return fail(L('no_payment')) end

    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail(L('no_player')) end
    if Shop.busy[citizenid] then return fail(L('busy')) end
    if testDrives[src] then return fail(L('test_busy')) end
    if item.limit and DB.CountPurchases(citizenid, item.id) >= item.limit then return fail(L('limit_reached')) end
    local spawnAt = freeSpawn()
    if not spawnAt then return fail(L('spawn_blocked')) end

    Shop.busy[citizenid] = true
    local ran, result = pcall(function()
        local spent, why = Store.SpendCoins(src, item.price, ('Showroom: %s'):format(item.label))
        if not spent then return fail(Shop.SpendError(why)) end

        local ok, plate, vehicleId = Bridge.AddVehicle(src, model, Config.Vehicles.garage, colorProps(slot))
        if not ok then
            local refunded = Store.GiveCoins(src, item.price, ('Refund: %s (could not save the car)'):format(item.label))
            if not refunded then
                print(('[pmv2_store] REFUND FAILED showroom %s for %s (%d coins) - give them back by hand'):format(item.id, citizenid, item.price))
            end
            Discord.Log('Showroom purchase FAILED (refunded)', ('`%s` / `%s`: %s'):format(citizenid, item.id, tostring(plate)), nil, Store.Colors.fail)
            return fail(L('delivery_failed'))
        end

        DB.LogPurchase(citizenid, item.id, 'coins', item.price)
        if Config.Hooks.OnPurchase then pcall(Config.Hooks.OnPurchase, citizenid, src, item, 'coins') end

        local props = colorProps(slot)
        props.plate = plate
        local veh = Bridge.SpawnVehicle(src, model, spawnAt, props)
        if veh then
            Bridge.SetVehicleOut(veh, vehicleId)
            Bridge.GiveKeys(src, veh, plate)
        end
        Discord.Log('Showroom car bought', ('**%s** (`%s`) bought **%s**'):format(Bridge.GetCharName(src), citizenid, item.label), {
            { name = 'Plate', value = plate, inline = true },
            { name = 'Cost', value = tostring(item.price), inline = true },
            { name = 'Delivered', value = veh and 'Spawned outside' or ('In garage: ' .. Config.Vehicles.garage), inline = true },
        })
        return {
            ok = true,
            spawned = veh ~= nil,
            message = veh and L('car_bought', item.label) or L('car_bought_garage', item.label, Config.Vehicles.garage),
        }
    end)
    Shop.busy[citizenid] = nil
    if not ran then
        print(('[pmv2_store] showroom buy error for %s (%s): %s - check their coins/garage by hand'):format(citizenid, item.id, tostring(result)))
        return fail(L('delivery_failed'))
    end
    return result
end)

-- ── Test drive ───────────────────────────────────────────────
local function endTest(src, reason)
    local t = testDrives[src]
    if not t then return end
    testDrives[src] = nil
    lastTest[src] = os.time()
    if GetPlayerName(src) then TriggerClientEvent('pmv2_store:showroom:testEnded', src, t.back, reason) end
    -- give the client a moment to fade out and step back into the showroom before the car goes
    SetTimeout(1500, function()
        if DoesEntityExist(t.veh) then DeleteEntity(t.veh) end
    end)
end

lib.callback.register('pmv2_store:showroom:test', function(src, idx)
    local fail = function(msg) return { ok = false, message = msg } end
    if not SR.testDrive.enabled then return fail(L('bad_store')) end
    local slot, item, model = slotInfo(src, idx)
    if not slot then return fail(L(item)) end
    if testDrives[src] then return fail(L('test_busy')) end
    local wait = (lastTest[src] or 0) + (SR.testDrive.cooldown or 0) - os.time()
    if wait > 0 then return fail(L('test_cooldown', wait)) end
    local spawnAt = freeSpawn()
    if not spawnAt then return fail(L('spawn_blocked')) end

    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    local back = vector4(pos.x, pos.y, pos.z, GetEntityHeading(ped))

    local props = colorProps(slot)
    props.plate = SR.testDrive.plate or 'TESTDRV'
    local veh, netId = Bridge.SpawnVehicle(src, model, spawnAt, props)
    if not veh then return fail(L('test_failed')) end
    Bridge.GiveKeys(src, veh, props.plate)

    local seconds = SR.testDrive.seconds or 90
    testDrives[src] = { veh = veh, endsAt = GetGameTimer() + seconds * 1000, back = back }
    return { ok = true, netId = netId, seconds = seconds, label = item.label }
end)

RegisterNetEvent('pmv2_store:showroom:endTest', function()
    endTest(source, 'ended')
end)

-- Server-side clock, so a test car is always taken back even if the client stops talking.
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for src, t in pairs(testDrives) do
            if now >= t.endsAt + 3000 or not DoesEntityExist(t.veh) then endTest(src, 'timeout') end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local t = testDrives[source]
    testDrives[source], lastTest[source] = nil, nil
    if t and DoesEntityExist(t.veh) then DeleteEntity(t.veh) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, t in pairs(testDrives) do
        if DoesEntityExist(t.veh) then DeleteEntity(t.veh) end
    end
end)

-- /showroomspot: copy a ready-to-paste vector4 of where you're standing (for Config.Showroom.spawns)
lib.addCommand('showroomspot', {
    help = 'Copy your position as a showroom spawn point (vector4)',
    restricted = Config.Admin.restricted,
}, function(src)
    if src == 0 then return end
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = veh ~= 0 and veh or ped
    local p, h = GetEntityCoords(ent), GetEntityHeading(ent)
    TriggerClientEvent('pmv2_store:showroom:copySpot', src, ('vector4(%.2f, %.2f, %.2f, %.2f),'):format(p.x, p.y, p.z, h))
end)
