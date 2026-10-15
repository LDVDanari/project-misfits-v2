-- ─────────────────────────────────────────────────────────────
--  REALTOR CREATOR - /housing
--  Stand where you want something and press E. Inside shells/IPLs,
--  use "Go inside" first, then place the inside points.
-- ─────────────────────────────────────────────────────────────
Creator = {}

local function cb(name, ...)
    return lib.callback.await('pmv2_housing:realtor:' .. name, false, ...)
end

local function result(ok, msg, okText)
    if ok then Bridge.Notify(okText or (type(msg) == 'string' and msg) or 'Saved.', 'success')
    else Bridge.Notify(type(msg) == 'string' and msg or 'That did not work.', 'error') end
    return ok
end

-- ── Placement tool ───────────────────────────────────────────
--- Walk to the spot and press E. Returns vec4 (with heading) or nil.
function Creator.Place(label)
    lib.showTextUI(('[E] Place %s  •  [BACKSPACE] Cancel'):format(label), { position = 'left-center', icon = 'location-dot' })
    local result
    while true do
        Wait(0)
        local ped = cache.ped
        local pos = GetEntityCoords(ped)
        DrawMarker(1, pos.x, pos.y, pos.z - 0.98, 0, 0, 0, 0, 0, 0, 0.8, 0.8, 0.4, 155, 89, 255, 160, false, false, 2, false, nil, nil, false)
        if IsControlJustPressed(0, 38) then
            result = vec4(pos.x, pos.y, pos.z, GetEntityHeading(ped))
            break
        elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then
            break
        end
    end
    lib.hideTextUI()
    return result
end

--- Aim at a door and press E. Returns { model, coords, heading } or nil.
function Creator.AimDoor(label)
    lib.showTextUI(('[E] Select %s  •  [BACKSPACE] Cancel'):format(label), { position = 'left-center', icon = 'door-closed' })
    local picked, last
    while true do
        Wait(0)
        local hit, entity = lib.raycast.cam(1 | 16, 4, 6.0)
        if last and last ~= entity then SetEntityDrawOutline(last, false) end
        local isObj = hit and entity and entity ~= 0 and GetEntityType(entity) == 3
        if isObj then
            SetEntityDrawOutline(entity, true)
            SetEntityDrawOutlineColor(155, 89, 255, 255)
            last = entity
        end
        if IsControlJustPressed(0, 38) and isObj then
            picked = { model = GetEntityModel(entity), coords = GetEntityCoords(entity), heading = GetEntityHeading(entity) }
            break
        elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then
            break
        end
    end
    if last then SetEntityDrawOutline(last, false) end
    lib.hideTextUI()
    return picked
end

--- Converts where the realtor is standing into a stored point for this property.
local function pointFor(p, coords)
    if Current and Current.id == p.id then
        if p.type == 'shell' then
            local o = Config.ShellOrigin
            return vec4(coords.x - o.x, coords.y - o.y, coords.z - o.z, coords.w), false
        end
        return coords, false
    end
    return coords, true   -- outside the interior: absolute world coords
end

-- ── Main menu ────────────────────────────────────────────────
RegisterNetEvent('pmv2_housing:realtorMenu', function() Creator.Main() end)

function Creator.Main()
    lib.registerContext({
        id = 'pmv2h_realtor', title = 'Realtor',
        options = {
            { title = 'Create a property here', description = 'Stand at the front door first', icon = 'plus', onSelect = function() Creator.New() end },
            { title = 'Nearby properties', icon = 'location-crosshairs', onSelect = function() Creator.List(60.0) end },
            { title = 'All properties', icon = 'list', onSelect = function() Creator.List(nil) end },
        },
    })
    lib.showContext('pmv2h_realtor')
end

local function typeOptions(allowBuilding)
    local opts = {
        { value = 'mlo', label = 'MLO (no teleport, uses doorlocks)' },
        { value = 'shell', label = 'Shell (teleports inside)' },
        { value = 'ipl', label = 'GTA interior / IPL' },
    }
    if allowBuilding then opts[#opts + 1] = { value = 'building', label = 'Apartment building (holds units)' } end
    return opts
end

local function interiorChoice(ptype)
    if ptype == 'shell' then
        local opts = {}
        for _, s in ipairs(Config.Shells) do opts[#opts + 1] = { value = s.model, label = s.label } end
        local i = lib.inputDialog('Shell', { { type = 'select', label = 'Shell', options = opts, required = true } })
        return i and i[1]
    elseif ptype == 'ipl' then
        local opts = {}
        for _, s in ipairs(Config.IPLs) do opts[#opts + 1] = { value = s.key, label = s.label } end
        opts[#opts + 1] = { value = 'custom', label = "Custom (I'm standing inside it right now)" }
        local i = lib.inputDialog('Interior', { { type = 'select', label = 'Interior', options = opts, required = true } })
        return i and i[1]
    end
    return true
end

function Creator.New(parentId)
    local input = lib.inputDialog(parentId and 'New apartment unit' or 'New property', {
        { type = 'input', label = 'Name', placeholder = parentId and 'Apt 1' or '123 Grove Street', required = true, max = 60 },
        { type = 'select', label = 'Type', options = typeOptions(not parentId), required = true, default = parentId and 'shell' or 'mlo' },
        { type = 'number', label = 'Sale price', min = 0, default = 0 },
        { type = 'number', label = ('Rent per %dh'):format(Config.Rent.intervalHours), min = 0, default = 0 },
    })
    if not input then return end
    local ptype = input[2]
    if parentId and not Shared.HasInterior(ptype) then return Bridge.Notify('Units must be a shell or IPL.', 'error') end
    local choice = interiorChoice(ptype)
    if not choice then return end

    local id, err = cb('create', {
        label = input[1], type = ptype, price = input[3], rent_price = input[4], parent_id = parentId,
        shell = ptype == 'shell' and choice or nil, ipl = ptype == 'ipl' and choice or nil,
    })
    if not id then return Bridge.Notify(err or 'Could not create it.', 'error') end
    Bridge.Notify(('Created #%d. Now set it up.'):format(id), 'success')
    Wait(300)
    Creator.Edit(id)
end

function Creator.List(radius)
    local list = cb('list') or {}
    local pos = GetEntityCoords(cache.ped)
    local options = {}
    for _, p in ipairs(list) do
        local dist = p.entrance and #(pos - vector3(p.entrance.x, p.entrance.y, p.entrance.z)) or 99999
        if not radius or dist <= radius then
            local status = p.owner and ('Owner: ' .. p.owner) or p.renter and ('Rented: ' .. p.renter)
                or (p.for_sale and 'For sale ' or '') .. (p.for_rent and 'For rent' or '')
            options[#options + 1] = {
                title = ('#%d %s'):format(p.id, p.label),
                description = ('%s • %s%s'):format(Shared.Types[p.type] or p.type, status ~= '' and status or 'Not listed',
                    dist < 99999 and (' • %dm'):format(math.floor(dist)) or ''),
                icon = p.type == 'building' and 'building' or 'house',
                onSelect = function() Creator.Edit(p.id) end,
                _dist = dist,
            }
        end
    end
    table.sort(options, function(a, b) return a._dist < b._dist end)
    for _, o in ipairs(options) do o._dist = nil end
    if #options == 0 then options[1] = { title = 'Nothing found', disabled = true } end
    lib.registerContext({ id = 'pmv2h_rlist', title = radius and 'Nearby properties' or 'All properties', menu = 'pmv2h_realtor', options = options })
    lib.showContext('pmv2h_rlist')
end

-- ── Property editor ──────────────────────────────────────────
function Creator.Edit(id)
    local p = cb('get', id)
    if not p then return Bridge.Notify('Property not found.', 'error') end
    local hasInterior = Shared.HasInterior(p.type)
    local status = p.owner_name and ('Owner: ' .. p.owner_name) or p.renter_name and ('Rented by ' .. p.renter_name) or 'Nobody owns it'

    local options = {
        { title = ('#%d %s'):format(p.id, p.label), description = ('%s • %s'):format(Shared.Types[p.type], status), icon = 'circle-info', disabled = true },
        { title = 'Details & prices', description = ('Sale %s • Rent %s'):format(Shared.Money(p.price), Shared.Money(p.rent_price)), icon = 'pen', onSelect = function() Creator.Details(p) end },
    }

    if p.type ~= 'building' then
        options[#options + 1] = {
            title = p.for_sale and 'For sale: ON' or 'For sale: OFF', icon = 'sign-hanging', disabled = p.occupied and not p.for_sale,
            onSelect = function() result(cb('update', id, { for_sale = not p.for_sale })) Creator.Edit(id) end,
        }
        options[#options + 1] = {
            title = p.for_rent and 'For rent: ON' or 'For rent: OFF', icon = 'key', disabled = p.occupied,
            onSelect = function() result(cb('update', id, { for_rent = not p.for_rent })) Creator.Edit(id) end,
        }
    end

    if not p.parent_id then
        options[#options + 1] = {
            title = 'Set front door here', description = p.data.entrance and 'Move the entrance to where you stand' or 'No entrance yet!',
            icon = 'door-closed', onSelect = function() Creator.SetPoint(p, 'entrance', 'front door') end,
        }
    end

    if p.type ~= 'building' then
        options[#options + 1] = { title = 'Points', description = 'Stash, wardrobe, garage, electric box, water, router', icon = 'location-dot', onSelect = function() Creator.Points(id) end }
    end
    if hasInterior then
        options[#options + 1] = {
            title = 'Go inside', description = 'Place the inside points (stash, wardrobe, utilities)', icon = 'door-open',
            onSelect = function()
                local info, err = cb('enterInterior', id)
                if not info then return Bridge.Notify(err or 'No interior.', 'error') end
                Interior_Enter(info)
                Bridge.Notify('Use the door to leave. "Realtor: place points" is on the door too.')
            end,
        }
        if p.type == 'ipl' and p.data.ipl == 'custom' then
            options[#options + 1] = { title = 'Set IPL arrival spot here', icon = 'person-walking-arrow-right', onSelect = function() Creator.SetPoint(p, 'iplExit', 'arrival spot') end }
        end
    end
    if p.type == 'mlo' then
        options[#options + 1] = { title = 'Doors (ox_doorlock)', description = ('%d door(s)'):format(#(p.data.doors or {})), icon = 'door-closed', onSelect = function() Creator.Doors(p) end }
        options[#options + 1] = {
            title = 'Property area', description = p.data.zone and ('Radius %dm (lights go off inside it)'):format(math.floor(p.data.zone.r)) or 'Stand in the middle of the house',
            icon = 'draw-polygon', onSelect = function() Creator.Zone(p) end,
        }
    end
    if p.type == 'building' then
        options[#options + 1] = { title = 'Apartment units', description = ('%d unit(s)'):format(#(p.units or {})), icon = 'building', onSelect = function() Creator.Units(p) end }
    end
    if p.parent_id and Role.admin then
        options[#options + 1] = {
            title = 'Use as starter apartment template', description = 'New characters get a copy of this unit', icon = 'star',
            onSelect = function() result(cb('setStarterTemplate', id)) end,
        }
    end
    if p.type ~= 'building' and not p.occupied then
        options[#options + 1] = { title = 'Sell / rent to a player here', icon = 'handshake', onSelect = function() Creator.SellTo(p) end }
    end
    local e = p.data.entrance or (p.parent_id and Props[p.parent_id] and Props[p.parent_id].data.entrance)
    if e then
        options[#options + 1] = { title = 'Set GPS', icon = 'map-pin', onSelect = function() SetNewWaypoint(e.x, e.y) end }
    end
    if Role.admin and p.occupied then
        options[#options + 1] = {
            title = 'Reset ownership (admin)', description = 'Removes owner, renter, tenants and keys', icon = 'rotate-left',
            onSelect = function()
                if lib.alertDialog({ header = 'Reset', content = 'Remove everyone from this property?', centered = true, cancel = true }) == 'confirm' then
                    result(cb('reset', id)) Creator.Edit(id)
                end
            end,
        }
    end
    options[#options + 1] = {
        title = 'Delete property', icon = 'trash',
        onSelect = function()
            if lib.alertDialog({ header = 'Delete #' .. id, content = 'This cannot be undone.', centered = true, cancel = true }) == 'confirm' then
                result(cb('delete', id), nil, 'Deleted.')
            end
        end,
    }
    lib.registerContext({ id = 'pmv2h_edit', title = 'Edit property', menu = 'pmv2h_realtor', options = options })
    lib.showContext('pmv2h_edit')
end

function Creator.Details(p)
    local stash = p.data.stash or Config.Stash
    local input = lib.inputDialog('Details', {
        { type = 'input', label = 'Name', default = p.label, required = true, max = 60 },
        { type = 'number', label = 'Sale price', min = 0, default = p.price },
        { type = 'number', label = ('Rent per %dh'):format(Config.Rent.intervalHours), min = 0, default = p.rent_price },
        { type = 'number', label = 'Stash slots', min = 1, max = 500, default = stash.slots },
        { type = 'number', label = 'Stash max weight (grams)', min = 1000, default = stash.weight },
    })
    if not input then return Creator.Edit(p.id) end
    result(cb('update', p.id, { label = input[1], price = input[2], rent_price = input[3], stashSlots = input[4], stashWeight = input[5] }))
    Creator.Edit(p.id)
end

function Creator.SetPoint(p, key, label)
    local c = Creator.Place(label)
    if not c then return end
    local stored, isAbs = pointFor(p, c)
    if key == 'entrance' or key == 'iplExit' then stored, isAbs = c, true end
    result(cb('setPoint', p.id, key, stored, isAbs), nil, label .. ' placed.')
end

-- Points: inside ones are placed inside the interior, garage ones outside.
function Creator.Points(id)
    local p = Props[id]
    if not p then return end
    local inside = Current and Current.id == id
    local hasInterior = Shared.HasInterior(p.type)
    local options = {}
    for _, pt in ipairs(Shared.Points) do
        local set = p.data.points and p.data.points[pt.key]
        local where
        if hasInterior and not pt.outside then
            where = inside and 'Place where you stand (inside)' or 'Place outside, or go inside first'
        else
            where = (hasInterior and inside) and 'Must be placed outside' or 'Place where you stand'
        end
        options[#options + 1] = {
            title = ('%s%s'):format(pt.label, set and '  ✓' or ''), description = where, icon = pt.icon,
            disabled = hasInterior and inside and pt.outside,
            onSelect = function()
                Creator.SetPoint(p, pt.key, pt.label)
                Wait(200)
                Creator.Points(id)
            end,
        }
        if set then
            options[#options + 1] = {
                title = '   Remove ' .. pt.label, icon = 'xmark',
                onSelect = function() result(cb('clearPoint', id, pt.key)) Wait(200) Creator.Points(id) end,
            }
        end
    end
    lib.registerContext({ id = 'pmv2h_points', title = 'Points: ' .. p.label, options = options })
    lib.showContext('pmv2h_points')
end

function Creator.Zone(p)
    local input = lib.inputDialog('Property area', {
        { type = 'number', label = 'Radius (meters) around where you stand', min = 3, max = 80, default = p.data.zone and p.data.zone.r or 20 },
    })
    if not input then return end
    local pos = GetEntityCoords(cache.ped)
    result(cb('setPoint', p.id, 'zone', vec4(pos.x, pos.y, pos.z, 0.0), true, input[1]), nil, 'Area saved.')
end

-- ── MLO doors ────────────────────────────────────────────────
function Creator.Doors(p)
    local options = {
        {
            title = 'Add a door', description = 'Aim at the door', icon = 'door-closed',
            onSelect = function()
                local d = Creator.AimDoor('door')
                if d then result(cb('addDoor', p.id, d), nil, 'Door added.') end
                Creator.Doors(Creator.Fresh(p.id))
            end,
        },
        {
            title = 'Add a double door', description = 'Aim at the left door, then the right one', icon = 'dungeon',
            onSelect = function()
                local a = Creator.AimDoor('first door')
                if not a then return end
                Wait(250)
                local b = Creator.AimDoor('second door')
                if not b then return end
                result(cb('addDoor', p.id, { double = true, doors = { a, b } }), nil, 'Double door added.')
                Creator.Doors(Creator.Fresh(p.id))
            end,
        },
        {
            title = 'Link an existing ox_doorlock door', description = 'Doors within 25m', icon = 'link',
            onSelect = function()
                local list = cb('nearbyDoors') or {}
                if #list == 0 then return Bridge.Notify('No ox_doorlock doors nearby.', 'error') end
                local opts = {}
                for _, d in ipairs(list) do opts[#opts + 1] = { value = tostring(d.id), label = ('#%d %s (%dm)'):format(d.id, d.name or '', math.floor(d.dist)) } end
                local i = lib.inputDialog('Link door', { { type = 'select', label = 'Door', options = opts, required = true } })
                if i then result(cb('linkDoor', p.id, tonumber(i[1])), nil, 'Door linked.') end
                Creator.Doors(Creator.Fresh(p.id))
            end,
        },
    }
    for _, doorId in ipairs(p.data.doors or {}) do
        options[#options + 1] = {
            title = ('Door #%d'):format(doorId), description = 'Remove from this property', icon = 'xmark',
            onSelect = function()
                result(cb('removeDoor', p.id, doorId), nil, 'Door removed.')
                Creator.Doors(Creator.Fresh(p.id))
            end,
        }
    end
    lib.registerContext({ id = 'pmv2h_doors', title = 'Doors', menu = 'pmv2h_edit', options = options })
    lib.showContext('pmv2h_doors')
end

function Creator.Fresh(id)
    Wait(250)
    return cb('get', id) or Props[id]
end

-- ── Buildings ────────────────────────────────────────────────
function Creator.Units(b)
    local options = {
        { title = 'Add a unit', description = 'Shell or IPL apartment inside this building', icon = 'plus', onSelect = function() Creator.New(b.id) end },
    }
    for _, u in ipairs(b.units or {}) do
        options[#options + 1] = {
            title = ('#%d %s'):format(u.id, u.label), description = u.occupied and 'Occupied' or 'Empty',
            icon = 'door-closed', onSelect = function() Creator.Edit(u.id) end,
        }
    end
    lib.registerContext({ id = 'pmv2h_units', title = b.label, menu = 'pmv2h_edit', options = options })
    lib.showContext('pmv2h_units')
end

function Creator.SellTo(p)
    local input = lib.inputDialog('Offer to a player', {
        { type = 'select', label = 'Offer', options = { { value = 'buy', label = 'Sell' }, { value = 'rent', label = ('Rent (per %dh)'):format(Config.Rent.intervalHours) } }, required = true, default = 'buy' },
        { type = 'number', label = 'Price', min = 0, default = p.price, required = true },
    })
    if not input then return end
    local target = Menus.PickPlayer('Offer to')
    if not target then return end
    Bridge.Notify('Offer sent, waiting for them to answer...')
    result(cb('sellTo', p.id, target, input[2], input[1]), nil, 'Deal done!')
end
