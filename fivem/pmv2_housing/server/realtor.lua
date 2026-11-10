-- ─────────────────────────────────────────────────────────────
--  REALTOR / ADMIN  - create, edit, list, sell
-- ─────────────────────────────────────────────────────────────
local MAX_PRICE = 100000000

local function int(v, min, max)
    v = math.floor(tonumber(v) or 0)
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

local function cleanLabel(s)
    s = tostring(s or ''):gsub('[<>]', ''):sub(1, 60)
    return s ~= '' and s or nil
end

local function vec4t(c)
    if type(c) ~= 'table' and type(c) ~= 'vector4' and type(c) ~= 'vector3' then return nil end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not (x and y and z) then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0, w = (tonumber(c.w) or 0.0) + 0.0 }
end

local function guard(src)
    if not Bridge.IsRealtor(src) then
        Bridge.Notify(src, 'Realtors only.', 'error')
        return false
    end
    return true
end

local function realtorLog(src, title, p, extra)
    Bridge.Log(title, ('**%s** (`%s`)\n**Property:** #%d %s (%s)%s'):format(
        Bridge.GetName(src), Bridge.GetCitizenId(src) or '?', p.id, p.label, Shared.Types[p.type] or p.type, extra and ('\n' .. extra) or ''))
end

-- ── Create ───────────────────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:create', function(src, input)
    if not guard(src) or type(input) ~= 'table' then return nil end
    local ptype = input.type
    if not Shared.Types[ptype] then return nil, 'Pick a property type.' end

    local parent
    if input.parent_id then
        parent = Housing.Get(input.parent_id)
        if not parent or parent.type ~= 'building' then return nil, 'That building does not exist.' end
        if not Shared.HasInterior(ptype) then return nil, 'Apartment units must be a shell or IPL.' end
    end

    local data = { points = {}, stash = { slots = Config.Stash.slots, weight = Config.Stash.weight }, doors = {}, createdDoors = {} }
    if ptype == 'shell' then
        if not Shared.ShellByModel(input.shell) then return nil, 'Pick a shell.' end
        data.shell = input.shell
    elseif ptype == 'ipl' then
        if input.ipl == 'custom' then
            local pos = Housing.Coords(src)
            data.ipl = 'custom'
            data.iplExit = { x = pos.x, y = pos.y, z = pos.z, w = GetEntityHeading(GetPlayerPed(src)) }
        elseif Shared.IplByKey(input.ipl) then
            data.ipl = input.ipl
        else
            return nil, 'Pick an interior.'
        end
    end

    -- Stand at the front door when you create it: that's the entrance (not for units / custom IPLs).
    if not parent and not (ptype == 'ipl' and input.ipl == 'custom') then
        local pos = Housing.Coords(src)
        data.entrance = { x = pos.x, y = pos.y, z = pos.z, w = GetEntityHeading(GetPlayerPed(src)) }
    end

    local p = {
        label = cleanLabel(input.label) or 'Property',
        type = ptype,
        parent_id = parent and parent.id or nil,
        data = data,
        price = int(input.price, 0, MAX_PRICE),
        rent_price = int(input.rent_price, 0, MAX_PRICE),
        for_sale = false, for_rent = false,
        state = Housing.DefaultState(),
        created_by = Bridge.GetCitizenId(src),
    }
    local id = DB.Insert(p)
    if not id then return nil, 'Database error.' end
    p.id = id
    p.access = {}
    p.rent_missed = 0
    Props[id] = p
    Housing.Broadcast(p)
    realtorLog(src, '🏠 Property created', p)
    return id
end)

-- ── Edit ─────────────────────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:update', function(src, id, f)
    if not guard(src) or type(f) ~= 'table' then return false end
    local p = Housing.Get(id)
    if not p then return false end
    local stashChanged = false

    if f.label then p.label = cleanLabel(f.label) or p.label end
    if f.price then p.price = int(f.price, 0, MAX_PRICE) end
    if f.rent_price then p.rent_price = int(f.rent_price, 0, MAX_PRICE) end
    if f.for_sale ~= nil or f.for_rent ~= nil then
        if Housing.IsOccupied(p) and (f.for_sale or f.for_rent) then
            return false, 'Someone already owns or rents this property.'
        end
        if f.for_sale ~= nil then p.for_sale = f.for_sale == true end
        if f.for_rent ~= nil then p.for_rent = f.for_rent == true end
        if p.type == 'building' then p.for_sale, p.for_rent = false, false end
        if p.for_sale or p.for_rent then p.data.listedBy = Bridge.GetCitizenId(src) end
        p.data.sellerListing = nil
    end
    if f.stashSlots or f.stashWeight then
        p.data.stash = p.data.stash or {}
        if f.stashSlots then p.data.stash.slots = int(f.stashSlots, 1, 500) end
        if f.stashWeight then p.data.stash.weight = int(f.stashWeight, 1000, 5000000) end
        stashChanged = true
    end
    if f.shell and p.type == 'shell' and Shared.ShellByModel(f.shell) then p.data.shell = f.shell end
    if f.ipl and p.type == 'ipl' and Shared.IplByKey(f.ipl) then p.data.ipl = f.ipl; p.data.iplExit = nil end

    Housing.Commit(p, { stash = stashChanged, doors = false, garage = f.label ~= nil })
    realtorLog(src, '✏️ Property edited', p, ('Price %s • Rent %s • Sale: %s • Rent: %s'):format(
        Shared.Money(p.price), Shared.Money(p.rent_price), tostring(p.for_sale), tostring(p.for_rent)))
    return true
end)

-- Points: entrance, stash, wardrobe, garage, garageSpawn, electricity, water, internet, zone, iplExit
local VALID_POINTS = { entrance = true, zone = true, iplExit = true }
for _, pt in ipairs(Shared.Points) do VALID_POINTS[pt.key] = true end

lib.callback.register('pmv2_housing:realtor:setPoint', function(src, id, key, coords, isAbs, radius)
    if not guard(src) or not VALID_POINTS[key] then return false end
    local p = Housing.Get(id)
    local c = vec4t(coords)
    if not p or not c then return false end

    if key == 'entrance' then
        if p.parent_id then return false, 'Units use their building entrance.' end
        p.data.entrance = c
    elseif key == 'zone' then
        c.r = math.max(3.0, math.min(80.0, tonumber(radius) or 20.0))
        p.data.zone = c
    elseif key == 'iplExit' then
        p.data.iplExit = c
    else
        if isAbs then c.abs = true end
        p.data.points[key] = c
    end

    Housing.Commit(p, { stash = key == 'stash', doors = false, garage = key == 'garage' or key == 'garageSpawn' })
    return true
end)

lib.callback.register('pmv2_housing:realtor:clearPoint', function(src, id, key)
    if not guard(src) then return false end
    local p = Housing.Get(id)
    if not p then return false end
    if key == 'zone' then p.data.zone = nil else p.data.points[key] = nil end
    Housing.Commit(p, { doors = false })
    return true
end)

-- Go inside a shell/IPL to place its inside points (no access needed, nothing is changed).
lib.callback.register('pmv2_housing:realtor:enterInterior', function(src, id)
    if not guard(src) then return nil end
    local p = Housing.Get(id)
    if not p or not Shared.HasInterior(p.type) then return nil, 'Only shells and IPLs have an interior.' end
    return Housing.Enter(src, p, 'creator')
end)

-- ── Doors (MLO) ──────────────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:addDoor', function(src, id, door)
    if not guard(src) or type(door) ~= 'table' then return false end
    local p = Housing.Get(id)
    if not p or p.type ~= 'mlo' then return false, 'Doors are for MLO properties.' end
    if GetResourceState('ox_doorlock') ~= 'started' then return false, 'ox_doorlock is not running.' end

    local n = #p.data.doors + 1
    local data = {
        name = ('pmv2house_%d_%d'):format(p.id, n),
        state = 1,
        maxDistance = 2.0,
        doorRate = 1.0,
        characters = Housing.AccessList(p, 'enter'),
        hideUi = false,
    }
    if door.double and type(door.doors) == 'table' and #door.doors == 2 then
        data.doors = {}
        for i = 1, 2 do
            local d = door.doors[i]
            data.doors[i] = { model = tonumber(d.model), coords = vector3(d.coords.x, d.coords.y, d.coords.z), heading = math.floor(tonumber(d.heading) or 0) }
        end
        data.coords = (data.doors[1].coords + data.doors[2].coords) / 2
    else
        data.model = tonumber(door.model)
        data.coords = vector3(door.coords.x, door.coords.y, door.coords.z)
        data.heading = math.floor(tonumber(door.heading) or 0)
    end

    local ok, doorId = pcall(function() return exports.ox_doorlock:createDoor(data) end)
    if not ok or not doorId then return false, 'ox_doorlock refused the door: ' .. tostring(doorId) end
    p.data.doors[#p.data.doors + 1] = doorId
    p.data.createdDoors[#p.data.createdDoors + 1] = doorId
    Housing.Commit(p, { garage = false })
    return true, doorId
end)

lib.callback.register('pmv2_housing:realtor:nearbyDoors', function(src)
    if not guard(src) then return {} end
    local pos = Housing.Coords(src)
    local out = {}
    local ok, doors = pcall(function() return exports.ox_doorlock:getAllDoors() end)
    if not ok or type(doors) ~= 'table' then return out end
    for _, d in pairs(doors) do
        if d.coords and #(pos - vector3(d.coords.x, d.coords.y, d.coords.z)) <= 25.0 then
            out[#out + 1] = { id = d.id, name = d.name, dist = #(pos - vector3(d.coords.x, d.coords.y, d.coords.z)) }
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end)

lib.callback.register('pmv2_housing:realtor:linkDoor', function(src, id, doorId)
    if not guard(src) then return false end
    local p = Housing.Get(id)
    doorId = tonumber(doorId)
    if not p or p.type ~= 'mlo' or not doorId then return false end
    for _, d in ipairs(p.data.doors) do if d == doorId then return true end end
    p.data.doors[#p.data.doors + 1] = doorId
    Housing.Commit(p, { garage = false })
    return true
end)

lib.callback.register('pmv2_housing:realtor:removeDoor', function(src, id, doorId)
    if not guard(src) then return false end
    local p = Housing.Get(id)
    doorId = tonumber(doorId)
    if not p or not doorId then return false end
    for i, d in ipairs(p.data.doors) do
        if d == doorId then table.remove(p.data.doors, i) break end
    end
    for i, d in ipairs(p.data.createdDoors) do
        if d == doorId then
            table.remove(p.data.createdDoors, i)
            pcall(function() exports.ox_doorlock:removeDoor(doorId) end)
            break
        end
    end
    Housing.Commit(p, { doors = false, garage = false })
    return true
end)

-- ── Lists / info ─────────────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:list', function(src)
    if not guard(src) then return {} end
    local out = {}
    for _, p in pairs(Props) do
        out[#out + 1] = {
            id = p.id, label = p.label, type = p.type, parent_id = p.parent_id,
            price = p.price, rent_price = p.rent_price, for_sale = p.for_sale, for_rent = p.for_rent,
            owner = p.owner_name, renter = p.renter_name,
            entrance = Housing.Entrance(p),
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

lib.callback.register('pmv2_housing:realtor:get', function(src, id)
    if not guard(src) then return nil end
    local p = Housing.Get(id)
    if not p then return nil end
    local units = {}
    if p.type == 'building' then
        for _, u in pairs(Props) do
            if u.parent_id == p.id then units[#units + 1] = { id = u.id, label = u.label, occupied = Housing.IsOccupied(u) } end
        end
        table.sort(units, function(a, b) return a.id < b.id end)
    end
    local pub = Housing.Public(p)
    pub.owner_name, pub.renter_name, pub.units = p.owner_name, p.renter_name, units
    pub.isStarter = Config.Starter.building == p.id
    return pub
end)

-- ── Sell / rent straight to a player ─────────────────────────
lib.callback.register('pmv2_housing:realtor:sellTo', function(src, id, target, price, mode)
    if not guard(src) then return false end
    local p = Housing.Get(id)
    target = tonumber(target)
    if not p or not target or not GetPlayerName(target) then return false, 'Player not found.' end
    if p.type == 'building' then return false, 'Sell the units, not the building.' end
    if Housing.IsOccupied(p) then return false, 'Someone already owns or rents this property.' end
    if #(Housing.Coords(src) - Housing.Coords(target)) > 6.0 then return false, 'They need to be next to you.' end
    mode = mode == 'rent' and 'rent' or 'buy'
    price = int(price, 0, MAX_PRICE)

    local accepted = lib.callback.await('pmv2_housing:offer', target, {
        label = p.label, price = price, mode = mode, from = Bridge.GetName(src),
        interval = Config.Rent.intervalHours,
    })
    if not accepted then return false, 'They declined.' end
    if Housing.IsOccupied(p) then return false, 'Someone got it first.' end

    local ok, err = Owner.Acquire(target, p, mode, price, Bridge.GetCitizenId(src))
    if not ok then return false, err end
    realtorLog(src, mode == 'rent' and '🔑 Property rented (realtor)' or '💰 Property sold (realtor)', p,
        ('**To:** %s • **Price:** %s'):format(Bridge.GetName(target), Shared.Money(price)))
    return true
end)

-- ── Admin: reset / delete ────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:reset', function(src, id)
    if not Bridge.IsAdmin(src) then return false, 'Admins only.' end
    local p = Housing.Get(id)
    if not p then return false end
    Owner.ClearOwnership(p, 'An admin reset this property.')
    realtorLog(src, '♻️ Property reset (admin)', p)
    return true
end)

lib.callback.register('pmv2_housing:realtor:delete', function(src, id)
    local p = Housing.Get(id)
    if not p then return false end
    if not Bridge.IsAdmin(src) and not (Bridge.IsRealtor(src) and not Housing.IsOccupied(p)) then
        return false, 'Only admins can delete an owned property.'
    end
    if p.type == 'building' then
        for _, u in pairs(Props) do
            if u.parent_id == p.id then return false, 'Delete the units inside this building first.' end
        end
    end
    Housing.EmptyInterior(p.id, 'This property no longer exists.')
    for _, doorId in ipairs(p.data.createdDoors or {}) do
        pcall(function() exports.ox_doorlock:removeDoor(doorId) end)
    end
    pcall(function() exports['jg-advancedgarages']:unregisterGarage(Housing.StashId(p.id)) end)
    local cids = {}
    if p.owner then cids[#cids + 1] = p.owner end
    if p.renter then cids[#cids + 1] = p.renter end
    for cid in pairs(p.access) do cids[#cids + 1] = cid end
    Props[p.id] = nil
    DB.Delete(p.id)
    TriggerClientEvent('pmv2_housing:remove', -1, p.id)
    for _, cid in ipairs(cids) do Housing.PushAccess(cid) end
    realtorLog(src, '🗑️ Property deleted', p)
    return true
end)

-- ── Starter apartments ───────────────────────────────────────
lib.callback.register('pmv2_housing:realtor:setStarterTemplate', function(src, unitId)
    if not Bridge.IsAdmin(src) then return false, 'Admins only.' end
    local u = Housing.Get(unitId)
    local b = u and u.parent_id and Housing.Get(u.parent_id)
    if not b then return false, 'Pick a unit inside an apartment building.' end
    b.data.starterUnit = u.id
    Housing.Commit(b, { doors = false, garage = false })
    return true, ('Starter template set. Put `Config.Starter.building = %d` and `enabled = true` in config.lua.'):format(b.id)
end)

--- Gives a character their own unit cloned from the building's starter template.
function Housing.GiveStarter(src)
    if not Config.Starter.enabled then return false, 'disabled' end
    local b = Housing.Get(Config.Starter.building)
    local tpl = b and b.data.starterUnit and Housing.Get(b.data.starterUnit)
    if not tpl then return false, 'no template' end
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'no player' end
    for _, p in pairs(Props) do
        if p.parent_id == b.id and (p.owner == cid or p.renter == cid) then return false, 'already has one' end
    end

    local count = 0
    for _, p in pairs(Props) do if p.parent_id == b.id then count = count + 1 end end
    local data = json.decode(json.encode(tpl.data))
    data.doors, data.createdDoors, data.listedBy, data.sellerListing, data.starterUnit = {}, {}, nil, nil, nil
    local p = {
        label = ('%s #%d'):format(b.label, count + 1), type = tpl.type, parent_id = b.id, data = data,
        price = 0, rent_price = 0, for_sale = false, for_rent = false,
        state = Housing.DefaultState(), created_by = 'starter',
    }
    p.id = DB.Insert(p)
    if not p.id then return false, 'db' end
    p.access, p.rent_missed = {}, 0
    p.owner, p.owner_name = cid, Bridge.GetName(src)
    Props[p.id] = p
    Housing.SyncStash(p)
    Housing.Commit(p, { notify = { cid } })
    Bridge.Notify(src, ('Welcome to the city! Your apartment is %s.'):format(p.label), 'success')
    return true, p.id
end

exports('GiveStarterApartment', function(src) return Housing.GiveStarter(src) end)

lib.addCommand('givestarter', {
    help = 'Give a player a starter apartment',
    params = { { name = 'id', type = 'playerId', help = 'Player server id' } },
    restricted = 'group.admin',
}, function(src, args)
    local ok, res = Housing.GiveStarter(args.id)
    Bridge.Notify(src, ok and ('Starter apartment created (#%s).'):format(res) or ('Could not: %s'):format(res), ok and 'success' or 'error')
end)

lib.addCommand(Config.Realtor.command, { help = 'Realtor menu' }, function(src)
    if not Bridge.IsRealtor(src) then return Bridge.Notify(src, 'Realtors only.', 'error') end
    TriggerClientEvent('pmv2_housing:realtorMenu', src)
end)
