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
-- Display cars are local (only you see your copy). Walk up to one and a panel slides in on the
-- left. G = buy (press twice), B = test drive. All checks happen again on the server.
local SR = Config.Showroom
local near = nil          -- { idx, info, confirmUntil, working }
local testDrive = nil     -- { veh, endsAt, outSince }

local function srUi(data) SendNUIMessage(data) end

local function modelStats(model)
    local hash = joaat(model)
    local function pct(v, max) return math.floor(math.max(0.04, math.min(1.0, v / max)) * 100) end
    local speed = GetVehicleModelEstimatedMaxSpeed(hash)          -- m/s
    local accel = GetVehicleModelAcceleration(hash)
    local brake = GetVehicleModelMaxBraking(hash)
    local grip  = GetVehicleModelMaxTraction(hash)
    return {
        topMph = math.floor(speed * 2.236936 + 0.5),
        topKmh = math.floor(speed * 3.6 + 0.5),
        bars = {
            { key = 'sr_top_speed', value = pct(speed, 62.0) },
            { key = 'sr_accel',     value = pct(accel, 0.42) },
            { key = 'sr_braking',   value = pct(brake, 1.35) },
            { key = 'sr_handling',  value = pct(grip, 3.0) },
        },
    }
end

local function hidePanel()
    if near then near = nil srUi({ action = 'showroomHide' }) end
end

local function showPanel(idx)
    near = { idx = idx, loading = true }
    local info = lib.callback.await('pmv2_store:showroom:info', false, idx)
    if not near or near.idx ~= idx then return end
    if not info or info.error then
        near.loading = false
        near.info = nil
        return
    end
    info.stats = modelStats(info.model)
    info.keys = { buy = SR.keys.buy.label, test = SR.keys.test.label }
    info.ui = Locale.ui
    near.info, near.loading = info, false
    srUi({ action = 'showroom', data = info })
end

local function refreshPanel()
    if near then local idx = near.idx near = nil showPanel(idx) end
end

local function setState(state, extra)
    local msg = { action = 'showroomState', state = state }
    if extra then for k, v in pairs(extra) do msg[k] = v end end
    srUi(msg)
end

local function startTestDrive(res)
    hidePanel()
    local veh = NetToVeh(res.netId)
    testDrive = { veh = veh, netId = res.netId, endsAt = GetGameTimer() + res.seconds * 1000, outSince = nil }
    srUi({ action = 'testdrive', seconds = res.seconds, label = res.label, ui = Locale.ui })
    CreateThread(function()
        local leaveMs = (SR.testDrive.leaveSeconds or 8) * 1000
        while testDrive do
            Wait(250)
            local ped = PlayerPedId()
            local current = NetToVeh(testDrive.netId)
            local inCar = current ~= 0 and GetVehiclePedIsIn(ped, false) == current
            if inCar then
                testDrive.outSince = nil
            elseif not testDrive.outSince then
                testDrive.outSince = GetGameTimer()
            end
            if GetGameTimer() >= testDrive.endsAt
                or (testDrive.outSince and GetGameTimer() - testDrive.outSince > leaveMs)
                or IsEntityDead(ped) then
                TriggerServerEvent('pmv2_store:showroom:endTest')
                Wait(3000) -- wait for the server to answer with testEnded
            end
        end
    end)
end

RegisterNetEvent('pmv2_store:showroom:testEnded', function(back)
    if not testDrive then return end
    testDrive = nil
    srUi({ action = 'testdriveEnd' })
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(10) end
    local ped = PlayerPedId()
    if back then
        SetEntityCoords(ped, back.x, back.y, back.z - 0.95, false, false, false, false)
        SetEntityHeading(ped, back.w)
    end
    Wait(300)
    DoScreenFadeIn(500)
    notify(Locale.server.test_over, 'inform')
end)

RegisterNetEvent('pmv2_store:showroom:copySpot', function(text)
    lib.setClipboard(text)
    print(('[pmv2_store] showroom spawn: %s'):format(text))
    notify(('Copied %s - paste it into Config.Showroom.spawns'):format(text), 'success')
end)

local function onBuyPressed()
    local info = near and near.info
    if not info or near.working then return end
    if info.soldOut or info.noDiscord or (info.price or 0) > (info.coins or 0) then
        setState('blocked')
        return
    end
    local now = GetGameTimer()
    if not near.confirmUntil or now > near.confirmUntil then
        near.confirmUntil = now + (SR.confirmSeconds or 6) * 1000
        setState('confirm', { ms = (SR.confirmSeconds or 6) * 1000 })
        return
    end
    -- second press: buy
    near.confirmUntil, near.working = nil, true
    setState('working')
    local res = lib.callback.await('pmv2_store:showroom:buy', false, near.idx)
    if near then near.working = false end
    notify(res and res.message or 'No response from the server.', res and res.ok and 'success' or 'error')
    if res and res.ok then hidePanel() else refreshPanel() end
end

local function onTestPressed()
    if not near or not near.info or near.working or not near.info.testDrive then return end
    near.confirmUntil, near.working = nil, true
    setState('working')
    local res = lib.callback.await('pmv2_store:showroom:test', false, near.idx)
    if near then near.working = false end
    if res and res.ok then
        startTestDrive(res)
    else
        notify(res and res.message or 'No response from the server.', 'error')
        setState('idle')
    end
end

-- nearest display car within reach (or nil)
local function nearestSlot()
    local ped = PlayerPedId()
    if testDrive or isOpen or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return nil end
    local pos, best, bestDist = GetEntityCoords(ped), nil, SR.interactDistance or 2.6
    for i, slot in ipairs(SR.vehicles) do
        local d = #(pos - v3(slot.coords))
        if d <= bestDist then best, bestDist = i, d end
    end
    return best
end

local function showroomLoop()
    local buyKey, testKey = SR.keys.buy.control, SR.keys.test.control
    local first = v3(SR.vehicles[1].coords)
    while true do
        local idx = nil
        -- only look closely when we're anywhere near the showroom
        if #(GetEntityCoords(PlayerPedId()) - first) < 60.0 then idx = nearestSlot() end
        if idx then
            if not near or near.idx ~= idx then hidePanel() CreateThread(function() showPanel(idx) end) Wait(50) end
            DisableControlAction(0, buyKey, true)
            DisableControlAction(0, testKey, true)
            DisableControlAction(0, 58, true)  -- G also throws weapons
            if near and near.confirmUntil and GetGameTimer() > near.confirmUntil then
                near.confirmUntil = nil
                setState('idle')
            end
            if IsDisabledControlJustReleased(0, buyKey) then CreateThread(onBuyPressed) end
            if IsDisabledControlJustReleased(0, testKey) then CreateThread(onTestPressed) end
            Wait(0)
        else
            hidePanel()
            Wait(400)
        end
    end
end

local function setupShowroomSlot(i, slot)
    local model = vehicleModelOf(slot.item)
    model = slot.model or model
    if not model then
        print(('[pmv2_store] showroom slot %d: item "%s" has no vehicle reward'):format(i, tostring(slot.item)))
        return
    end
    local c = slot.coords

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
            SetVehicleNumberPlateText(veh, SR.plateText or 'VIP')
            if slot.colors then SetVehicleColours(veh, slot.colors[1] or 0, slot.colors[2] or 0) end
            self.veh = veh

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
                DeleteEntity(self.veh)
                self.veh = nil
            end
        end,
    })
end

CreateThread(function()
    for key, shop in pairs(Config.Shops) do setupStore(key, shop) end

    if SR.enabled and #SR.vehicles > 0 then
        if SR.blip then addBlip(SR.blip.coords, SR.blip) end
        for i, slot in ipairs(SR.vehicles) do setupShowroomSlot(i, slot) end
        showroomLoop()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    if testDrive then DoScreenFadeIn(0) end
end)
