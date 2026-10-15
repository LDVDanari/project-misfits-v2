-- ─────────────────────────────────────────────────────────────
--  PMv2 HOUSING - client core: sync, zones, interiors, lights
-- ─────────────────────────────────────────────────────────────
Props = {}            -- [id] = public property data
MyAccess = {}         -- [id] = 'owner' | 'renter' | 'tenant' | 'keyholder'
Role = { realtor = false, admin = false }
Current = nil         -- interior we're in: { id, kind, mode, origin, shell, zones = {} }
PendingRings = {}     -- [propertyId] = { [visitorSrc] = { name, at } }

local points = {}     -- [id] = lib.point
local zones = {}      -- [id] = { ox_target zone ids }
local blips = {}

-- ── Helpers ──────────────────────────────────────────────────
function Housing_Level(id) return MyAccess[id] end

function Housing_Can(id, action)
    local level = MyAccess[id]
    local perms = level and Config.Access[level]
    return perms and perms[action] == true or false
end

function Housing_Entrance(p)
    if p.data.entrance then return p.data.entrance end
    local parent = p.parent_id and Props[p.parent_id]
    return parent and parent.data.entrance or nil
end

--- World position of a stored point (shell inside-points are relative to the shell origin).
function Housing_PointWorld(p, pt)
    if not pt then return nil end
    if p.type == 'shell' and not pt.abs then
        local o = Config.ShellOrigin
        return vector3(o.x + pt.x, o.y + pt.y, o.z + pt.z)
    end
    return vector3(pt.x, pt.y, pt.z)
end

function Housing_Units(buildingId)
    local list = {}
    for _, p in pairs(Props) do
        if p.parent_id == buildingId then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function teleport(coords)
    local ped = cache.ped
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(10) end
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    if coords.w then SetEntityHeading(ped, coords.w) end
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 3000 do Wait(10) end
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(400)
end

-- ── Zones ────────────────────────────────────────────────────
local function addZone(list, coords, radius, options)
    list[#list + 1] = exports.ox_target:addSphereZone({
        coords = coords, radius = radius or 1.2, debug = Config.Debug, options = options,
    })
end

local function clearZones(list)
    for _, z in ipairs(list or {}) do exports.ox_target:removeZone(z) end
end

--- Options for the stash / wardrobe / utility points of a property.
function Housing_PointZones(p, list)
    local pts = p.data.points or {}
    local inside = Shared.HasInterior(p.type)
    local function want(pt) return pt and ((inside and not pt.abs and Current and Current.id == p.id) or (not inside) or pt.abs) end

    if want(pts.stash) then
        addZone(list, Housing_PointWorld(p, pts.stash), 1.0, { {
            name = 'pmv2h_stash', icon = 'fa-solid fa-box-archive', label = 'Open stash',
            canInteract = function() return Housing_Can(p.id, 'stash') end,
            onSelect = function() Bridge.OpenStash('pmv2house_' .. p.id) end,
        } })
    end
    if want(pts.wardrobe) then
        addZone(list, Housing_PointWorld(p, pts.wardrobe), 1.0, { {
            name = 'pmv2h_wardrobe', icon = 'fa-solid fa-shirt', label = 'Wardrobe',
            canInteract = function() return Housing_Can(p.id, 'wardrobe') end,
            onSelect = Bridge.OpenWardrobe,
        } })
    end
    for _, key in ipairs(Shared.UtilityKeys) do
        if want(pts[key]) then
            local cfg = Config.Utilities[key]
            addZone(list, Housing_PointWorld(p, pts[key]), 0.9, { {
                name = 'pmv2h_util_' .. key, icon = 'fa-solid fa-' .. cfg.icon, label = cfg.label,
                canInteract = function() return Config.Utilities.enabled and Housing_Can(p.id, 'utilities') end,
                onSelect = function() Menus.Utility(p.id, key) end,
            } })
        end
    end
end

--- Front door options. Buildings open the unit list instead.
local function entranceOptions(p)
    local id = p.id
    if p.type == 'building' then
        return { {
            name = 'pmv2h_building', icon = 'fa-solid fa-building', label = p.label,
            onSelect = function() Menus.Building(id) end,
        }, {
            name = 'pmv2h_realtor', icon = 'fa-solid fa-pen-ruler', label = 'Realtor: edit building',
            canInteract = function() return Role.realtor end,
            onSelect = function() Creator.Edit(id) end,
        } }
    end
    return Menus.PropertyOptions(id)
end

local function buildPoint(p)
    if points[p.id] then points[p.id]:remove(); points[p.id] = nil end
    clearZones(zones[p.id]); zones[p.id] = nil
    if p.parent_id or not p.data.entrance then return end
    local e = p.data.entrance

    points[p.id] = lib.points.new({
        coords = vector3(e.x, e.y, e.z),
        distance = Config.ZoneDistance,
        onEnter = function()
            local live = Props[p.id]
            if not live then return end
            local list = {}
            addZone(list, vector3(e.x, e.y, e.z), 1.3, entranceOptions(live))
            if live.type == 'mlo' then Housing_PointZones(live, list) end
            -- outside points of shells/IPLs (stash/garage placed outside) are created here too
            if Shared.HasInterior(live.type) then
                for key, pt in pairs(live.data.points or {}) do
                    if pt.abs and key ~= 'garage' and key ~= 'garageSpawn' then Housing_PointZones(live, list) break end
                end
            end
            zones[p.id] = list
        end,
        onExit = function()
            clearZones(zones[p.id]); zones[p.id] = nil
        end,
    })
end

-- ── Blips ────────────────────────────────────────────────────
local function refreshBlips()
    for _, b in pairs(blips) do RemoveBlip(b) end
    blips = {}
    for id, p in pairs(Props) do
        if not p.parent_id and p.data.entrance then
            local style
            local mine = MyAccess[id] == 'owner' or MyAccess[id] == 'renter'
            local forSale, forRent = p.for_sale and not p.occupied or false, p.for_rent and not p.occupied or false
            if p.type == 'building' then
                for _, u in ipairs(Housing_Units(id)) do
                    if MyAccess[u.id] == 'owner' or MyAccess[u.id] == 'renter' then mine = true end
                    if u.for_sale then forSale = true end
                    if u.for_rent and not u.occupied then forRent = true end
                end
            end
            if p.for_sale and p.occupied then forSale = true end   -- player listing
            if mine then style = Config.Blips.owned
            elseif forSale then style = Config.Blips.forSale
            elseif forRent then style = Config.Blips.forRent end
            if style then
                local e = p.data.entrance
                local b = AddBlipForCoord(e.x, e.y, e.z)
                SetBlipSprite(b, style.sprite)
                SetBlipColour(b, style.color)
                SetBlipScale(b, style.scale)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(mine and p.label or style.label)
                EndTextCommandSetBlipName(b)
                blips[#blips + 1] = b
            end
        end
    end
end

local blipTimer
local function queueBlips()
    if blipTimer then return end
    blipTimer = SetTimeout(500, function() blipTimer = nil; refreshBlips() end)
end

-- ── Sync from server ─────────────────────────────────────────
local function rebuild(p)
    buildPoint(p)
    -- refresh the interior zones if we're standing in it
    if Current and Current.id == p.id and Current.mode ~= 'creator' then
        clearZones(Current.zones)
        Current.zones = {}
        Interior_Zones(p)
    end
end

local function init()
    local data = lib.callback.await('pmv2_housing:init', false)
    if not data then return end
    for id, pt in pairs(points) do pt:remove() points[id] = nil end
    for id, z in pairs(zones) do clearZones(z) zones[id] = nil end
    Props, MyAccess = {}, {}
    for _, p in ipairs(data.props) do Props[p.id] = p end
    for id, level in pairs(data.access or {}) do MyAccess[tonumber(id)] = level end
    Role.realtor, Role.admin = data.realtor, data.admin
    for _, p in pairs(Props) do buildPoint(p) end
    refreshBlips()
end

RegisterNetEvent('pmv2_housing:update', function(p)
    local old = Props[p.id]
    Props[p.id] = p
    local changed = not old or old.label ~= p.label or json.encode(old.data) ~= json.encode(p.data)
        or old.type ~= p.type or old.parent_id ~= p.parent_id
    if changed then rebuild(p) end
    if not old or old.for_sale ~= p.for_sale or old.for_rent ~= p.for_rent or old.occupied ~= p.occupied or old.label ~= p.label then
        queueBlips()
    end
end)

RegisterNetEvent('pmv2_housing:remove', function(id)
    Props[id] = nil
    MyAccess[id] = nil
    if points[id] then points[id]:remove() points[id] = nil end
    clearZones(zones[id]); zones[id] = nil
    queueBlips()
end)

RegisterNetEvent('pmv2_housing:access', function(access)
    MyAccess = {}
    for id, level in pairs(access or {}) do MyAccess[tonumber(id)] = level end
    queueBlips()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() SetTimeout(1000, init) end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    local r = lib.callback.await('pmv2_housing:role', false)
    if r then Role.realtor, Role.admin = r.realtor, r.admin end
end)
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if Current then Interior_Leave(nil) end
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() and LocalPlayer.state.isLoggedIn then SetTimeout(1000, init) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Current and Current.shell and DoesEntityExist(Current.shell) then DeleteEntity(Current.shell) end
    SetArtificialLightsState(false)
end)

-- ── Interiors ────────────────────────────────────────────────
function Interior_Zones(p)
    local spawn = Current.spawn
    -- the inside of the front door
    addZone(Current.zones, vector3(spawn.x, spawn.y, spawn.z), 1.4, Menus.ExitOptions(p.id))
    Housing_PointZones(p, Current.zones)
end

--- Called with the info the server returns from enter / preview / creator / letIn.
function Interior_Enter(info)
    if not info then return end
    if Current then Interior_Leave(nil) end
    local p = Props[info.id]
    Current = { id = info.id, kind = info.kind, mode = info.mode, origin = info.origin, spawn = info.spawn, zones = {} }

    if info.kind == 'shell' then
        local model = joaat(info.model)
        if not lib.requestModel(model, 10000) then
            Bridge.Notify('Shell model failed to load: ' .. info.model, 'error')
        else
            local o = info.origin
            Current.shell = CreateObjectNoOffset(model, o.x, o.y, o.z, false, false, false)
            FreezeEntityPosition(Current.shell, true)
            SetModelAsNoLongerNeeded(model)
        end
    end

    teleport(info.spawn)
    if p and info.mode ~= 'creator' then Interior_Zones(p) end
    if info.mode == 'creator' then
        addZone(Current.zones, vector3(info.spawn.x, info.spawn.y, info.spawn.z), 1.4, Menus.ExitOptions(info.id))
    end

    if info.mode == 'preview' then
        Bridge.Notify(('Viewing for %d seconds. Leave by the front door any time.'):format(info.previewSeconds or Config.PreviewSeconds))
    elseif p and Config.Dirt.enabled and (p.dirt or 0) >= Config.Dirt.warnAt then
        Bridge.Notify(('This place is filthy (%d%%). Time to clean.'):format(p.dirt), 'warning')
    end
end

function Interior_Leave(coords)
    if not Current then return end
    clearZones(Current.zones)
    if Current.shell and DoesEntityExist(Current.shell) then DeleteEntity(Current.shell) end
    Current = nil
    if coords then teleport(coords) end
end

function Housing_Enter(id, preview)
    local info, err = lib.callback.await(preview and 'pmv2_housing:preview' or 'pmv2_housing:enter', false, id)
    if not info then return Bridge.Notify(err or "Can't go in.", 'error') end
    Interior_Enter(info)
end

function Housing_Exit()
    local out = lib.callback.await('pmv2_housing:exit', false)
    Interior_Leave(out)
end

RegisterNetEvent('pmv2_housing:forceExit', function(coords, msg)
    if Current then
        Interior_Leave(coords)
    elseif coords then
        teleport(coords)
    end
    if msg then Bridge.Notify(msg, 'inform') end
end)

RegisterNetEvent('pmv2_housing:goInside', function(info)
    Interior_Enter(info)
    Bridge.Notify('You were let in.', 'success')
end)

-- ── Doorbell ─────────────────────────────────────────────────
RegisterNetEvent('pmv2_housing:doorbell', function(id, visitor, name, knock)
    PendingRings[id] = PendingRings[id] or {}
    PendingRings[id][visitor] = { name = name, at = GetGameTimer() }
    if knock then
        PlaySoundFrontend(-1, 'Door_Open', 'Lowrider_Super_Mod_Garage_Sounds', true)
    else
        PlaySoundFrontend(-1, 'DOOR_BUZZ', 'MP_PLAYER_APARTMENT', true)
    end
    local p = Props[id]
    Bridge.Notify(('%s is %s at %s.'):format(name, knock and 'knocking' or 'ringing the bell', p and p.label or 'the door'), 'inform', 'Doorbell')
end)

function Housing_Rings(id)
    local out = {}
    local list = PendingRings[id] or {}
    for visitor, r in pairs(list) do
        if GetGameTimer() - r.at <= Config.DoorbellSeconds * 1000 then
            out[#out + 1] = { src = visitor, name = r.name }
        else
            list[visitor] = nil
        end
    end
    return out
end

-- ── Lights off when the electricity is off ──────────────────
CreateThread(function()
    local dark = false
    while true do
        Wait(750)
        local want = false
        if Current then
            local p = Props[Current.id]
            want = p ~= nil and p.util and p.util.electricity == false and Current.mode ~= 'creator'
        else
            local pos = GetEntityCoords(cache.ped)
            for _, p in pairs(Props) do
                local z = p.type == 'mlo' and p.data.zone
                if z and p.util and p.util.electricity == false and #(pos - vector3(z.x, z.y, z.z)) <= (z.r or 20.0) then
                    want = true
                    break
                end
            end
        end
        if want ~= dark then
            dark = want
            SetArtificialLightsState(dark)
            SetArtificialLightsStateAffectsVehicles(false)
        end
    end
end)

-- ── Misc ─────────────────────────────────────────────────────
RegisterNetEvent('pmv2_housing:copy', function(text)
    lib.setClipboard(text)
    Bridge.Notify('Copied: ' .. text, 'success')
end)

lib.callback.register('pmv2_housing:offer', function(data)
    local text
    if data.mode == 'rent' then
        text = ('%s is offering you **%s** for **%s** every %dh.'):format(data.from, data.label, Shared.Money(data.price), data.interval)
    elseif data.mode == 'tenant' then
        text = ('%s wants you as a tenant at **%s** for **%s** every %dh (first payment now).'):format(data.from, data.label, Shared.Money(data.price), data.interval)
    elseif data.mode == 'transfer' then
        text = ('%s wants to give you **%s** for free.'):format(data.from, data.label)
    else
        text = ('%s is selling you **%s** for **%s** (from your bank).'):format(data.from, data.label, Shared.Money(data.price))
    end
    local res = lib.alertDialog({ header = 'Property offer', content = text, centered = true, cancel = true, labels = { confirm = 'Accept', cancel = 'Decline' } })
    return res == 'confirm'
end)
