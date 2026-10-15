-- ─────────────────────────────────────────────────────────────
--  MENUS - doors, listings, manage, bills, keys, tenants
-- ─────────────────────────────────────────────────────────────
Menus = {}

local function notifyResult(ok, msg, okText)
    if ok then
        Bridge.Notify(okText or msg or 'Done.', 'success')
    else
        Bridge.Notify(msg or 'That did not work.', 'error')
    end
end

local function hours(seconds)
    if not seconds then return '-' end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h <= 0 then return ('%dm'):format(math.max(m, 0)) end
    return ('%dh %dm'):format(h, m)
end

--- Pick a player standing next to you. Returns their server id or nil.
function Menus.PickPlayer(title)
    local list = lib.getNearbyPlayers(GetEntityCoords(cache.ped), 4.0, false)
    if #list == 0 then
        Bridge.Notify('Nobody is close enough.', 'error')
        return nil
    end
    local options = {}
    for _, pl in ipairs(list) do
        local sid = GetPlayerServerId(pl.id)
        options[#options + 1] = { value = tostring(sid), label = ('%s [%d]'):format(GetPlayerName(pl.id), sid) }
    end
    local input = lib.inputDialog(title or 'Choose a player', {
        { type = 'select', label = 'Player', options = options, required = true, default = options[1].value },
    })
    return input and tonumber(input[1]) or nil
end

-- ── Front door / unit options ───────────────────────────────
local function canRing(id)
    local p = Props[id]
    return p and p.occupied and not Housing_Level(id) and Shared.HasInterior(p.type) or (p and p.type == 'mlo' and p.occupied and not Housing_Level(id))
end

local function ring(id)
    local ok, knock = lib.callback.await('pmv2_housing:ring', false, id)
    if ok then Bridge.Notify(knock and 'You knocked on the door.' or 'You rang the doorbell.') end
end

--- Every action you can take at a property's door (also used for units in a building).
function Menus.PropertyOptions(id)
    return {
        {
            name = 'pmv2h_enter', icon = 'fa-solid fa-door-open', label = 'Enter',
            canInteract = function() local p = Props[id] return p and Shared.HasInterior(p.type) and Housing_Can(id, 'enter') end,
            onSelect = function() Housing_Enter(id) end,
        },
        {
            name = 'pmv2h_listing', icon = 'fa-solid fa-sign-hanging', label = 'View listing',
            canInteract = function() local p = Props[id] return p and (p.for_sale or (p.for_rent and not p.occupied)) and Housing_Level(id) ~= 'owner' end,
            onSelect = function() Menus.Listing(id) end,
        },
        {
            name = 'pmv2h_ring', icon = 'fa-solid fa-bell', label = 'Ring doorbell',
            canInteract = function() return canRing(id) end,
            onSelect = function() ring(id) end,
        },
        {
            name = 'pmv2h_manage', icon = 'fa-solid fa-house-user', label = 'Manage property',
            canInteract = function() return Housing_Can(id, 'manage') end,
            onSelect = function() Menus.Manage(id) end,
        },
        {
            name = 'pmv2h_moveout', icon = 'fa-solid fa-person-walking-luggage', label = 'Hand back my key',
            canInteract = function() local l = Housing_Level(id) return l == 'tenant' or l == 'keyholder' end,
            onSelect = function() Menus.MoveOut(id) end,
        },
        {
            name = 'pmv2h_clean', icon = 'fa-solid fa-broom', label = 'Clean up',
            canInteract = function() local p = Props[id] return Config.Dirt.enabled and p and p.type == 'mlo' and Housing_Can(id, 'enter') end,
            onSelect = function() Menus.Clean(id) end,
        },
        {
            name = 'pmv2h_realtor', icon = 'fa-solid fa-pen-ruler', label = 'Realtor: edit',
            canInteract = function() return Role.realtor end,
            onSelect = function() Creator.Edit(id) end,
        },
    }
end

--- The inside of the front door of a shell/IPL.
function Menus.ExitOptions(id)
    return {
        { name = 'pmv2h_leave', icon = 'fa-solid fa-door-open', label = 'Leave', onSelect = Housing_Exit },
        {
            name = 'pmv2h_letin', icon = 'fa-solid fa-bell', label = 'Answer the door',
            canInteract = function() return Housing_Level(id) ~= nil and #Housing_Rings(id) > 0 end,
            onSelect = function() Menus.AnswerDoor(id) end,
        },
        {
            name = 'pmv2h_manage_in', icon = 'fa-solid fa-house-user', label = 'Manage property',
            canInteract = function() return Housing_Can(id, 'manage') end,
            onSelect = function() Menus.Manage(id) end,
        },
        {
            name = 'pmv2h_clean_in', icon = 'fa-solid fa-broom', label = 'Clean up',
            canInteract = function() return Config.Dirt.enabled and Housing_Can(id, 'enter') end,
            onSelect = function() Menus.Clean(id) end,
        },
        {
            name = 'pmv2h_creator_in', icon = 'fa-solid fa-pen-ruler', label = 'Realtor: place points',
            canInteract = function() return Role.realtor and Current and Current.id == id end,
            onSelect = function() Creator.Points(id) end,
        },
    }
end

function Menus.AnswerDoor(id)
    local rings = Housing_Rings(id)
    if #rings == 0 then return Bridge.Notify('Nobody is at the door.') end
    local options = {}
    for _, r in ipairs(rings) do
        options[#options + 1] = {
            title = r.name, description = 'Let them in', icon = 'door-open',
            onSelect = function()
                local ok = lib.callback.await('pmv2_housing:letIn', false, id, r.src)
                if ok then
                    PendingRings[id][r.src] = nil
                    Bridge.Notify(r.name .. ' came in.', 'success')
                end
            end,
        }
    end
    lib.registerContext({ id = 'pmv2h_door', title = 'At the door', options = options })
    lib.showContext('pmv2h_door')
end

-- ── Buildings / apartments ──────────────────────────────────
function Menus.Building(id)
    local b = Props[id]
    if not b then return end
    local options = {}
    for _, u in ipairs(Housing_Units(id)) do
        local level = Housing_Level(u.id)
        local status
        if level then status = 'Yours (' .. level .. ')'
        elseif u.for_sale then status = 'For sale: ' .. Shared.Money(u.price)
        elseif u.for_rent and not u.occupied then status = 'For rent: ' .. Shared.Money(u.rent_price)
        elseif u.occupied then status = 'Occupied'
        else status = 'Not listed' end
        options[#options + 1] = {
            title = u.label, description = status,
            icon = level and 'house-user' or (u.occupied and 'lock' or 'house'),
            onSelect = function() Menus.Unit(u.id) end,
        }
    end
    if #options == 0 then options[1] = { title = 'No apartments set up yet', disabled = true } end
    lib.registerContext({ id = 'pmv2h_building', title = b.label, options = options })
    lib.showContext('pmv2h_building')
end

function Menus.Unit(id)
    local u = Props[id]
    if not u then return end
    local options = {}
    for _, opt in ipairs(Menus.PropertyOptions(id)) do
        if not opt.canInteract or opt.canInteract() then
            options[#options + 1] = { title = opt.label, icon = opt.icon:gsub('fa%-solid fa%-', ''), onSelect = opt.onSelect }
        end
    end
    if #options == 0 then options[1] = { title = 'Nothing you can do here', disabled = true } end
    lib.registerContext({ id = 'pmv2h_unit', title = u.label, menu = 'pmv2h_building', options = options })
    lib.showContext('pmv2h_unit')
end

-- ── Listing (buy / rent / view) ─────────────────────────────
function Menus.Listing(id)
    local p = Props[id]
    if not p then return end
    local options = {
        { title = p.label, description = Shared.Types[p.type] or p.type, icon = 'house', disabled = true },
    }
    if Shared.HasInterior(p.type) and not p.occupied then
        options[#options + 1] = {
            title = 'View inside', description = ('Look around for %ds'):format(Config.PreviewSeconds), icon = 'eye',
            onSelect = function() Housing_Enter(id, true) end,
        }
    end
    if p.for_sale then
        options[#options + 1] = {
            title = 'Buy for ' .. Shared.Money(p.price), description = 'Paid from your bank', icon = 'money-bill',
            onSelect = function()
                local c = lib.alertDialog({ header = 'Buy ' .. p.label, content = ('Buy for **%s**?'):format(Shared.Money(p.price)), centered = true, cancel = true })
                if c ~= 'confirm' then return end
                notifyResult(lib.callback.await('pmv2_housing:buy', false, id))
            end,
        }
    end
    if p.for_rent and not p.occupied then
        options[#options + 1] = {
            title = ('Rent for %s / %dh'):format(Shared.Money(p.rent_price), Config.Rent.intervalHours),
            description = 'First payment now, then from your bank automatically', icon = 'key',
            onSelect = function()
                local c = lib.alertDialog({ header = 'Rent ' .. p.label, content = ('Rent for **%s** every %dh?'):format(Shared.Money(p.rent_price), Config.Rent.intervalHours), centered = true, cancel = true })
                if c ~= 'confirm' then return end
                notifyResult(lib.callback.await('pmv2_housing:rent', false, id))
            end,
        }
    end
    lib.registerContext({ id = 'pmv2h_listing', title = 'Listing', options = options })
    lib.showContext('pmv2h_listing')
end

-- ── Manage ───────────────────────────────────────────────────
function Menus.Manage(id)
    local d = lib.callback.await('pmv2_housing:details', false, id)
    if not d then return Bridge.Notify("You can't manage this property.", 'error') end
    local isOwner, isRenter = d.level == 'owner', d.level == 'renter'
    local totalBills = d.taxDue
    for _, u in pairs(d.util) do totalBills = totalBills + u.due end

    local info = isOwner and ('Owner: %s'):format(d.owner or '?') or ('Rented by %s'):format(d.renter or '?')
    if isRenter and d.rent_due then info = info .. (' • next rent in %s (%s)'):format(hours(d.rent_due - d.now), Shared.Money(d.rentAmount or 0)) end

    local options = {
        { title = d.label, description = info, icon = 'house-user', disabled = true },
        {
            title = 'Bills & utilities', description = ('Owed: %s'):format(Shared.Money(totalBills)), icon = 'file-invoice-dollar',
            onSelect = function() Menus.Bills(id, d) end,
        },
        {
            title = 'Keys & tenants', description = ('%d people'):format(#d.people), icon = 'users',
            onSelect = function() Menus.People(id, d) end,
        },
    }
    if Config.Dirt.enabled then
        options[#options + 1] = {
            title = ('Cleanliness: %d%% dirty'):format(d.dirt), icon = 'broom',
            description = d.dirt >= Config.Dirt.warnAt and 'Needs a clean' or 'Looking good',
            onSelect = function() Menus.Clean(id) end,
        }
    end
    if isOwner then
        options[#options + 1] = { title = 'Sell or transfer', icon = 'handshake', onSelect = function() Menus.Sell(id, d) end }
    end
    if isRenter then
        options[#options + 1] = {
            title = 'End my rental', icon = 'person-walking-luggage',
            onSelect = function()
                local c = lib.alertDialog({ header = 'End rental', content = 'Move out and give the keys back? Your rent stops.', centered = true, cancel = true })
                if c == 'confirm' then notifyResult(lib.callback.await('pmv2_housing:leave', false, id), nil, 'Rental ended.') end
            end,
        }
    end
    lib.registerContext({ id = 'pmv2h_manage', title = 'Manage property', options = options })
    lib.showContext('pmv2h_manage')
end

function Menus.Bills(id, d)
    local options = {}
    local total = d.taxDue
    for _, key in ipairs(Shared.UtilityKeys) do
        local u, cfg = d.util[key], Config.Utilities[key]
        total = total + u.due
        options[#options + 1] = {
            title = ('%s: %s'):format(cfg.label, u.off and 'SHUT OFF' or (u.on and 'On' or 'Off')),
            description = ('Owed %s • %s/h while on'):format(Shared.Money(u.due), Shared.Money(cfg.perHour)),
            icon = cfg.icon, disabled = u.due <= 0,
            onSelect = function() notifyResult(lib.callback.await('pmv2_housing:payBill', false, id, key)) end,
        }
    end
    if d.level == 'owner' then
        options[#options + 1] = {
            title = 'Property tax', description = ('Owed %s'):format(Shared.Money(d.taxDue)), icon = 'landmark',
            disabled = d.taxDue <= 0,
            onSelect = function() notifyResult(lib.callback.await('pmv2_housing:payBill', false, id, 'tax')) end,
        }
    end
    options[#options + 1] = {
        title = 'Pay everything', description = Shared.Money(total), icon = 'money-check-dollar', disabled = total <= 0,
        onSelect = function() notifyResult(lib.callback.await('pmv2_housing:payBill', false, id, 'all')) end,
    }
    options[#options + 1] = { title = 'Switch utilities on/off at the electric box, water valve and router.', disabled = true }
    lib.registerContext({ id = 'pmv2h_bills', title = 'Bills', menu = 'pmv2h_manage', options = options })
    lib.showContext('pmv2h_bills')
end

function Menus.People(id, d)
    local options = {
        {
            title = 'Give a key', description = 'To the player next to you', icon = 'key',
            onSelect = function()
                local target = Menus.PickPlayer('Give a key to')
                if target then notifyResult(lib.callback.await('pmv2_housing:giveKey', false, id, target), nil, 'Key given.') end
            end,
        },
    }
    if d.level == 'owner' then
        options[#options + 1] = {
            title = 'Add a tenant', description = ('They pay you rent every %dh'):format(Config.Rent.intervalHours), icon = 'user-plus',
            onSelect = function()
                local input = lib.inputDialog('Add tenant', {
                    { type = 'number', label = ('Rent every %dh'):format(Config.Rent.intervalHours), min = Config.Rent.tenantMinRent, max = Config.Rent.tenantMaxRent, default = 0, required = true },
                })
                if not input then return end
                local target = Menus.PickPlayer('Who is moving in?')
                if target then notifyResult(lib.callback.await('pmv2_housing:addTenant', false, id, target, input[1]), nil, 'Tenant added.') end
            end,
        }
    end
    options[#options + 1] = {
        title = 'Change the locks', description = 'Every keyholder loses their key (tenants keep theirs)', icon = 'lock',
        onSelect = function()
            local c = lib.alertDialog({ header = 'Change the locks', content = 'All keyholders lose access. Continue?', centered = true, cancel = true })
            if c ~= 'confirm' then return end
            local ok, n = lib.callback.await('pmv2_housing:changeLocks', false, id)
            notifyResult(ok, nil, ('Locks changed. %d keys stopped working.'):format(n or 0))
        end,
    }
    for _, person in ipairs(d.people) do
        local desc = person.level == 'tenant' and ('Tenant • %s every %dh'):format(Shared.Money(person.rent or 0), Config.Rent.intervalHours) or 'Keyholder'
        options[#options + 1] = {
            title = person.name or person.citizenid, description = desc,
            icon = person.level == 'tenant' and 'user' or 'key',
            onSelect = function() Menus.Person(id, d, person) end,
        }
    end
    lib.registerContext({ id = 'pmv2h_people', title = 'Keys & tenants', menu = 'pmv2h_manage', options = options })
    lib.showContext('pmv2h_people')
end

function Menus.Person(id, d, person)
    local options = {}
    if person.level == 'tenant' and d.level == 'owner' then
        options[#options + 1] = {
            title = 'Change rent', icon = 'pen',
            onSelect = function()
                local input = lib.inputDialog('Rent for ' .. (person.name or ''), {
                    { type = 'number', label = 'Rent', min = Config.Rent.tenantMinRent, max = Config.Rent.tenantMaxRent, default = person.rent or 0, required = true },
                })
                if input then notifyResult(lib.callback.await('pmv2_housing:setTenantRent', false, id, person.citizenid, input[1]), nil, 'Rent updated.') end
            end,
        }
    end
    if person.level ~= 'tenant' or d.level == 'owner' then
        options[#options + 1] = {
            title = person.level == 'tenant' and 'Evict' or 'Take key back', icon = 'user-minus',
            onSelect = function()
                local c = lib.alertDialog({ header = 'Remove ' .. (person.name or ''), content = 'They lose access right away.', centered = true, cancel = true })
                if c == 'confirm' then notifyResult(lib.callback.await('pmv2_housing:removeAccess', false, id, person.citizenid), nil, 'Removed.') end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'Nothing to change', disabled = true } end
    lib.registerContext({ id = 'pmv2h_person', title = person.name or 'Person', menu = 'pmv2h_people', options = options })
    lib.showContext('pmv2h_person')
end

function Menus.Sell(id, d)
    local options = {
        d.listed and {
            title = 'Take my listing down', icon = 'ban',
            onSelect = function() notifyResult(lib.callback.await('pmv2_housing:listForSale', false, id, false), nil, 'Listing removed.') end,
        } or {
            title = 'List for sale', description = 'Buyers pay you directly', icon = 'sign-hanging',
            onSelect = function()
                local input = lib.inputDialog('List for sale', { { type = 'number', label = 'Asking price', min = 1, default = d.price, required = true } })
                if input then notifyResult(lib.callback.await('pmv2_housing:listForSale', false, id, input[1]), nil, 'Listed for sale.') end
            end,
        },
        {
            title = 'Transfer to a player', description = ('Fee: %d%% of the value'):format(Config.Sale.transferFee), icon = 'handshake',
            onSelect = function()
                local target = Menus.PickPlayer('Transfer to')
                if target then notifyResult(lib.callback.await('pmv2_housing:transfer', false, id, target), nil, 'Property transferred.') end
            end,
        },
        {
            title = 'Sell to the bank', description = ('About %s (unpaid bills are taken off)'):format(Shared.Money(d.sellBack)), icon = 'building-columns',
            onSelect = function()
                local c = lib.alertDialog({ header = 'Sell to the bank', content = ('Sell %s for about **%s**? Everyone loses access.'):format(d.label, Shared.Money(d.sellBack)), centered = true, cancel = true })
                if c ~= 'confirm' then return end
                local ok, value = lib.callback.await('pmv2_housing:sellBack', false, id)
                notifyResult(ok, nil, ('Sold for %s.'):format(Shared.Money(value or 0)))
            end,
        },
    }
    lib.registerContext({ id = 'pmv2h_sell', title = 'Sell or transfer', menu = 'pmv2h_manage', options = options })
    lib.showContext('pmv2h_sell')
end

function Menus.MoveOut(id)
    local c = lib.alertDialog({ header = 'Hand back key', content = 'You will lose access to this property.', centered = true, cancel = true })
    if c == 'confirm' then notifyResult(lib.callback.await('pmv2_housing:leave', false, id), nil, 'You handed back your key.') end
end

-- ── Utility points ───────────────────────────────────────────
function Menus.Utility(id, key)
    local d = lib.callback.await('pmv2_housing:details', false, id)
    if not d then return end
    local u, cfg = d.util[key], Config.Utilities[key]
    local options = {
        { title = cfg.label, description = ('%s • owed %s • %s/h while on'):format(u.off and 'SHUT OFF' or (u.on and 'On' or 'Off'), Shared.Money(u.due), Shared.Money(cfg.perHour)), icon = cfg.icon, disabled = true },
        {
            title = u.on and 'Switch off' or 'Switch on', icon = 'power-off', disabled = u.off,
            description = u.off and 'Pay the bill to get it reconnected' or nil,
            onSelect = function()
                local ok, on = lib.callback.await('pmv2_housing:toggleUtility', false, id, key)
                notifyResult(ok, on, ('%s switched %s.'):format(cfg.label, on and 'on' or 'off'))
            end,
        },
        {
            title = 'Pay ' .. Shared.Money(u.due), icon = 'money-bill', disabled = u.due <= 0,
            onSelect = function() notifyResult(lib.callback.await('pmv2_housing:payBill', false, id, key)) end,
        },
    }
    lib.registerContext({ id = 'pmv2h_util', title = cfg.label, options = options })
    lib.showContext('pmv2h_util')
end

-- ── Cleaning ─────────────────────────────────────────────────
function Menus.Clean(id)
    local p = Props[id]
    if Config.Dirt.needsWater and p and p.util and p.util.water == false then
        return Bridge.Notify('The water is off.', 'error')
    end
    local done = lib.progressCircle({
        duration = Config.Dirt.cleanSeconds * 1000, label = 'Cleaning up...', position = 'bottom',
        canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    })
    if not done then return end
    local ok, dirt = lib.callback.await('pmv2_housing:clean', false, id)
    if ok then Bridge.Notify(('Cleaned up. Now %d%% dirty.'):format(dirt), 'success') end
end
