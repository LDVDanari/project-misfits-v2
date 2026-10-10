-- ─────────────────────────────────────────────────────────────
--  VIP shop (client): store peds / zones, blips, showroom display cars, NUI.
--  Everything is driven by config/vip_locations.lua.
-- ─────────────────────────────────────────────────────────────
local function notify(description, ntype)
    lib.notify({ title = 'VIP Store', description = description, type = ntype or 'inform' })
end

local isOpen, openCtx, openCoords = false, nil, nil

local function v3(c) return vec3(c.x, c.y, c.z) end

local function closeShop()
    if not isOpen then return end
    isOpen, openCtx, openCoords = false, nil, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openShop(ctx, coords)
    if isOpen or IsPauseMenuActive() then return end

    local data = lib.callback.await('pmv2_store:vip:open', false, ctx)
    if not data or data.error then
        notify(data and data.error or 'The store is not available right now.', 'error')
        return
    end

    isOpen, openCtx, openCoords = true, ctx, coords
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })

    -- auto-close if the player walks away (or is moved / dies)
    CreateThread(function()
        while isOpen do
            Wait(500)
            if openCoords and #(GetEntityCoords(PlayerPedId()) - openCoords) > Config.Interaction.autoCloseDistance then
                closeShop()
            elseif IsEntityDead(PlayerPedId()) then
                closeShop()
            end
        end
    end)
end

-- ── NUI callbacks ────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb)
    closeShop()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    if not openCtx then return cb(false) end
    local data = lib.callback.await('pmv2_store:vip:open', false, openCtx)
    cb((data and not data.error) and data or false)
end)

RegisterNUICallback('purchase', function(data, cb)
    if type(data) ~= 'table' or not openCtx then return cb({ ok = false, results = {} }) end
    cb(lib.callback.await('pmv2_store:vip:purchase', false, openCtx, data.cart, data.method) or { ok = false, results = {} })
end)


-- ── Helpers ──────────────────────────────────────────────────
local function addBlip(coords, b)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, b.sprite or 1)
    SetBlipColour(blip, b.color or 0)
    SetBlipScale(blip, b.scale or 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.label or 'VIP')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function spawnPed(def, coords)
    local model = lib.requestModel(def.model, 10000)
    if not model then return nil end
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if def.scenario then TaskStartScenarioInPlace(ped, def.scenario, 0, true) end
    return ped
end

local function vehicleModelOf(itemId)
    for _, item in ipairs(Config.Items) do
        if item.id == itemId then
            for _, r in ipairs(item.rewards) do
                if r.type == 'vehicle' then return r.model, item.label end
            end
        end
    end
end

-- ── Stores ───────────────────────────────────────────────────
local function setupStore(key, shop)
    local coords = shop.coords
    local options = {{
        name     = 'pmv2_store:vip:' .. key,
        icon     = shop.target.icon,
        label    = shop.target.label,
        distance = shop.target.distance or 2.0,
        onSelect = function() openShop({ shop = key }, v3(coords)) end,
    }}

    if shop.blip then addBlip(coords, shop.blip) end

    if shop.ped then
        lib.points.new({
            coords   = v3(coords),
            distance = Config.Interaction.spawnDistance,
            onEnter  = function(self)
                self.ped = spawnPed(shop.ped, coords)
                if self.ped then exports.ox_target:addLocalEntity(self.ped, options) end
            end,
            onExit   = function(self)
                if self.ped then
                    exports.ox_target:removeLocalEntity(self.ped, options[1].name)
                    DeleteEntity(self.ped)
                    self.ped = nil
                end
            end,
        })
    else
        exports.ox_target:addSphereZone({
            coords  = v3(coords),
            radius  = shop.target.radius or 1.5,
            debug   = Config.Debug,
            options = options,
        })
    end
end

-- ── Showroom ─────────────────────────────────────────────────
local function setupShowroomSlot(i, slot)
    local model, label = vehicleModelOf(slot.item)
    model = slot.model or model
    if not model then
        print(('[pmv2_store] showroom slot %d: item "%s" has no vehicle reward'):format(i, tostring(slot.item)))
        return
    end
    local c = slot.coords
    local optName = 'pmv2_store:showroom:' .. i

    lib.points.new({
        coords   = v3(c),
        distance = Config.Interaction.spawnDistance,
        onEnter  = function(self)
            local hash = lib.requestModel(model, 15000)
            if not hash then return end
            local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w, false, false)
            SetModelAsNoLongerNeeded(hash)
            SetVehicleOnGroundProperly(veh)
            FreezeEntityPosition(veh, true)
            SetEntityInvincible(veh, true)
            SetVehicleDoorsLocked(veh, 2)
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleUndriveable(veh, true)
            SetVehicleNumberPlateText(veh, Config.Showroom.plateText or 'VIP')
            if slot.colors then SetVehicleColours(veh, slot.colors[1] or 0, slot.colors[2] or 0) end
            self.veh = veh

            exports.ox_target:addLocalEntity(veh, {{
                name     = optName,
                icon     = Config.Showroom.target.icon,
                label    = slot.label or ('View ' .. (label or model)),
                distance = Config.Showroom.target.distance or 3.0,
                onSelect = function() openShop({ showroom = i }, v3(c)) end,
            }})

            if slot.rotate then
                CreateThread(function()
                    local speed = slot.rotateSpeed or 0.15
                    while self.veh == veh and DoesEntityExist(veh) do
                        SetEntityHeading(veh, (GetEntityHeading(veh) + speed) % 360.0)
                        Wait(0)
                    end
                end)
            end
        end,
        onExit   = function(self)
            if self.veh then
                exports.ox_target:removeLocalEntity(self.veh, optName)
                DeleteEntity(self.veh)
                self.veh = nil
            end
        end,
    })
end

CreateThread(function()
    for key, shop in pairs(Config.Shops) do setupStore(key, shop) end

    if Config.Showroom.enabled then
        if Config.Showroom.blip then addBlip(Config.Showroom.blip.coords, Config.Showroom.blip) end
        for i, slot in ipairs(Config.Showroom.vehicles) do setupShowroomSlot(i, slot) end
    end
end)

-- ── Server -> client ─────────────────────────────────────────
-- LocalPlayer.state.vipTier is set by the server; this event is for scripts that prefer to listen
RegisterNetEvent('pmv2_store:client:vipTierChanged', function(newTier)
    TriggerEvent('pmv2_store:vipTierChanged', newTier)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
