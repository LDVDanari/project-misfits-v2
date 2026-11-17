-- ─────────────────────────────────────────────────────────────
--  PMv2 HOUSING - server core
--  Properties live in memory (Props) and are saved on every change.
-- ─────────────────────────────────────────────────────────────
Housing = {}
Props = {}                 -- [id] = property
Inside = {}                -- [src] = { id = propertyId, mode = 'access'|'preview'|'guest'|'creator' }
Rings = {}                 -- [propertyId] = { [src] = os.time() }

local STASH_PREFIX = 'pmv2house_'

-- ── Helpers ──────────────────────────────────────────────────
local function decode(s, fallback)
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end

function Housing.DefaultState()
    local util = {}
    for _, k in ipairs(Shared.UtilityKeys) do util[k] = { on = true, due = 0 } end
    return { util = util, taxDue = 0, dirt = 0, used = false, warned = false }
end

local function normalizeState(st)
    st = type(st) == 'table' and st or Housing.DefaultState()
    st.util = st.util or {}
    for _, k in ipairs(Shared.UtilityKeys) do
        st.util[k] = st.util[k] or { on = true, due = 0 }
        st.util[k].due = tonumber(st.util[k].due) or 0
    end
    st.taxDue = tonumber(st.taxDue) or 0
    st.dirt = tonumber(st.dirt) or 0
    return st
end

function Housing.Get(id)
    return Props[tonumber(id) or -1]
end

function Housing.Bucket(id)
    return Config.BucketOffset + id
end

function Housing.StashId(id)
    return STASH_PREFIX .. id
end

function Housing.Coords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

local function v3(t) return t and vector3(t.x, t.y, t.z) or nil end

--- Access level of a character: 'owner' | 'renter' | 'tenant' | 'keyholder' | nil
function Housing.Level(p, citizenid)
    if not p or not citizenid then return nil end
    if p.owner == citizenid then return 'owner' end
    if p.renter == citizenid then return 'renter' end
    local a = p.access[citizenid]
    return a and a.level or nil
end

function Housing.Can(p, citizenid, action)
    local level = Housing.Level(p, citizenid)
    if not level then return false end
    local override = p.access[citizenid] and p.access[citizenid].perms
    if override and override[action] ~= nil then return override[action] == true end
    local perms = Config.Access[level]
    return perms and perms[action] == true or false
end

function Housing.IsOccupied(p)
    return p.owner ~= nil or p.renter ~= nil
end

--- Where you come out / the door you walk up to. Building units use their building's entrance.
function Housing.Entrance(p)
    if p.data.entrance then return p.data.entrance end
    local parent = p.parent_id and Props[p.parent_id]
    return parent and parent.data.entrance or nil
end

--- World position of a point. Shell inside-points are stored relative to the shell origin.
function Housing.PointWorld(p, key)
    local pt = p.data.points and p.data.points[key]
    if not pt then return nil end
    if p.type == 'shell' and not pt.abs then
        local o = Config.ShellOrigin
        return vector3(o.x + pt.x, o.y + pt.y, o.z + pt.z)
    end
    return vector3(pt.x, pt.y, pt.z)
end

--- Every character that should get through the doors / into the garage.
function Housing.AccessList(p, action)
    local list = {}
    if p.owner then list[#list + 1] = p.owner end
    if p.renter then list[#list + 1] = p.renter end
    for cid, a in pairs(p.access) do
        local perms = Config.Access[a.level]
        if perms and perms[action] then list[#list + 1] = cid end
    end
    return list
end

-- ── What clients get to see ─────────────────────────────────
local PRIVATE_DATA = { listedBy = true, sellerListing = true, boughtFor = true, rentAmount = true, createdDoors = true }

function Housing.Public(p)
    local util = {}
    for k, u in pairs(p.state.util) do util[k] = u.on end
    local data = {}
    for k, v in pairs(p.data) do
        if not PRIVATE_DATA[k] then data[k] = v end
    end
    return {
        id = p.id, label = p.label, type = p.type, parent_id = p.parent_id,
        data = data, price = p.price, rent_price = p.rent_price,
        for_sale = p.for_sale, for_rent = p.for_rent,
        occupied = Housing.IsOccupied(p),
        util = util, dirt = math.floor(p.state.dirt),
    }
end

function Housing.AccessFor(citizenid)
    local out = {}
    for id, p in pairs(Props) do
        local level = Housing.Level(p, citizenid)
        if level then out[id] = level end
    end
    return out
end

function Housing.PushAccess(citizenid)
    local src = citizenid and Bridge.GetSource(citizenid)
    if src then TriggerClientEvent('pmv2_housing:access', src, Housing.AccessFor(citizenid)) end
end

function Housing.Broadcast(p)
    TriggerClientEvent('pmv2_housing:update', -1, Housing.Public(p))
end

-- ── Doors (ox_doorlock) ─────────────────────────────────────
function Housing.SyncDoors(p)
    if p.type ~= 'mlo' or not p.data.doors or #p.data.doors == 0 then return end
    if GetResourceState('ox_doorlock') ~= 'started' then return end
    local chars = Housing.AccessList(p, 'enter')
    for _, doorId in ipairs(p.data.doors) do
        local ok, err = pcall(function() exports.ox_doorlock:editDoor(doorId, { characters = chars }) end)
        if not ok then print(('[pmv2_housing] door %s for property %s: %s'):format(doorId, p.id, tostring(err))) end
    end
end

function Housing.LockDoors(p, state)
    if p.type ~= 'mlo' or not p.data.doors then return end
    for _, doorId in ipairs(p.data.doors) do
        pcall(function() exports.ox_doorlock:setDoorState(doorId, state) end)
    end
end

-- ── Garage (jg-advancedgarages) ─────────────────────────────
local JG = 'jg-advancedgarages'

function Housing.SyncGarage(p)
    if GetResourceState(JG) ~= 'started' then return end
    local gid = Housing.StashId(p.id)
    pcall(function() exports[JG]:unregisterGarage(gid) end)
    local entry, spawn = p.data.points and p.data.points.garage, p.data.points and p.data.points.garageSpawn
    if not entry or not spawn then return end
    local access = Housing.AccessList(p, 'garage')
    if #access == 0 then access = { 'pmv2_nobody' } end   -- false would mean "anyone"
    local ok, err = pcall(function()
        exports[JG]:registerGarage({
            id = gid,
            name = p.label .. ' Garage',
            coords = vector3(entry.x, entry.y, entry.z),
            spawnPoints = { vector4(spawn.x, spawn.y, spawn.z, spawn.w or 0.0) },
            access = access,
        })
    end)
    if not ok then print(('[pmv2_housing] garage for property %s: %s'):format(p.id, tostring(err))) end
end

AddEventHandler('onResourceStart', function(res)
    if res ~= JG then return end
    SetTimeout(2000, function()
        for _, p in pairs(Props) do Housing.SyncGarage(p) end
    end)
end)

-- ── Stash (ox_inventory) ────────────────────────────────────
--- Extra stash weight from the Stash Size upgrade.
function Housing.StashBonus(p)
    local level = p.data.upgrades and tonumber(p.data.upgrades.stash) or 0
    return level * Config.Upgrades.stash.weightPerLevel
end

function Housing.SyncStash(p)
    if not (p.data.points and p.data.points.stash) then return end
    local sid = Housing.StashId(p.id)
    local slots = tonumber(p.data.stash and p.data.stash.slots) or Config.Stash.slots
    local weight = (tonumber(p.data.stash and p.data.stash.weight) or Config.Stash.weight) + Housing.StashBonus(p)
    -- owner = false: ONE shared stash per property (per-player stashes are how other housing scripts duped)
    exports.ox_inventory:RegisterStash(sid, p.label .. ' Stash', slots, weight, false)
    pcall(function() exports.ox_inventory:SetSlotCount(sid, slots) end)
    pcall(function() exports.ox_inventory:SetMaxWeight(sid, weight) end)
end

--- Is this player really standing at/inside this property right now?
function Housing.IsAt(src, p, key, maxDist)
    if Shared.HasInterior(p.type) then
        if p.data.points and p.data.points[key] and p.data.points[key].abs then
            local pos = Housing.PointWorld(p, key)
            return pos and #(Housing.Coords(src) - pos) <= (maxDist or 5.0)
        end
        return GetPlayerRoutingBucket(src) == Housing.Bucket(p.id)
    end
    local pos = Housing.PointWorld(p, key)
    return pos ~= nil and #(Housing.Coords(src) - pos) <= (maxDist or 5.0)
end

--- Inside the interior (shell/IPL), inside the MLO zone, or right at the front door.
function Housing.IsAtProperty(src, p)
    if Shared.HasInterior(p.type) and GetPlayerRoutingBucket(src) == Housing.Bucket(p.id) then return true end
    local pos = Housing.Coords(src)
    if p.data.zone and #(pos - vector3(p.data.zone.x, p.data.zone.y, p.data.zone.z)) <= (p.data.zone.r or 20.0) then return true end
    local e = Housing.Entrance(p)
    if e and #(pos - vector3(e.x, e.y, e.z)) <= 10.0 then return true end
    for _, pt in pairs(p.data.points or {}) do
        if (pt.abs or not Shared.HasInterior(p.type)) and #(pos - vector3(pt.x, pt.y, pt.z)) <= 5.0 then return true end
    end
    return false
end

local function registerStashHook()
    exports.ox_inventory:registerHook('openInventory', function(payload)
        if payload.inventoryType ~= 'stash' then return end
        local id = tonumber(tostring(payload.inventoryId):match('^' .. STASH_PREFIX .. '(%d+)$'))
        if not id then return end
        local p = Props[id]
        if not p then return false end
        local cid = Bridge.GetCitizenId(payload.source)
        if not Housing.Can(p, cid, 'stash') then
            Bridge.Notify(payload.source, "You don't have access to this stash.", 'error')
            return false
        end
        if not Housing.IsAt(payload.source, p, 'stash', 5.0) then return false end
    end, { inventoryFilter = { '^' .. STASH_PREFIX .. '%d+$' } })
end

-- ── Loading ──────────────────────────────────────────────────
local loaded = false

function Housing.FromRow(row)
    return {
        id = row.id, label = row.label, type = row.type, parent_id = row.parent_id,
        data = decode(row.data, {}), price = row.price or 0, rent_price = row.rent_price or 0,
        for_sale = row.for_sale == 1 or row.for_sale == true,
        for_rent = row.for_rent == 1 or row.for_rent == true,
        owner = row.owner, owner_name = row.owner_name,
        renter = row.renter, renter_name = row.renter_name,
        rent_due = row.rent_due, rent_missed = row.rent_missed or 0,
        state = normalizeState(decode(row.state, nil)),
        created_by = row.created_by, access = {},
    }
end

CreateThread(function()
    local rows, access = DB.LoadAll()
    for _, row in ipairs(rows) do
        local p = Housing.FromRow(row)
        p.data.points = p.data.points or {}
        Props[p.id] = p
    end
    for _, a in ipairs(access) do
        local p = Props[a.property_id]
        if p then
            p.access[a.citizenid] = { citizenid = a.citizenid, name = a.name, level = a.level, rent = a.rent or 0, rent_due = a.rent_due, rent_missed = a.rent_missed or 0, perms = decode(a.perms, nil) }
        end
    end
    registerStashHook()
    for _, p in pairs(Props) do
        Housing.SyncStash(p)
        Housing.SyncDoors(p)
        Housing.SyncGarage(p)
    end
    loaded = true
    local n = 0
    for _ in pairs(Props) do n = n + 1 end
    print(('[pmv2_housing] loaded %d properties'):format(n))
end)

function Housing.WaitLoaded()
    while not loaded do Wait(50) end
end

--- Save + push everything that depends on a property.
function Housing.Commit(p, opts)
    opts = opts or {}
    DB.Save(p)
    if opts.doors ~= false then Housing.SyncDoors(p) end
    if opts.garage ~= false then Housing.SyncGarage(p) end
    if opts.stash then Housing.SyncStash(p) end
    Housing.Broadcast(p)
    for _, cid in ipairs(opts.notify or {}) do Housing.PushAccess(cid) end
end

-- ── Client init ──────────────────────────────────────────────
lib.callback.register('pmv2_housing:init', function(src)
    Housing.WaitLoaded()
    local list = {}
    for _, p in pairs(Props) do list[#list + 1] = Housing.Public(p) end
    local cid = Bridge.GetCitizenId(src)
    return { props = list, access = cid and Housing.AccessFor(cid) or {}, realtor = Bridge.IsRealtor(src), admin = Bridge.IsAdmin(src) }
end)

lib.callback.register('pmv2_housing:role', function(src)
    return { realtor = Bridge.IsRealtor(src), admin = Bridge.IsAdmin(src) }
end)

-- ── Entering / leaving interiors ────────────────────────────
local function setInside(src, id, mode)
    local cid = Bridge.GetCitizenId(src)
    if id then
        Inside[src] = { id = id, mode = mode }
        SetPlayerRoutingBucket(src, Housing.Bucket(id))
        local p = Props[id]
        if p then p.state.used = true end
    else
        Inside[src] = nil
        SetPlayerRoutingBucket(src, 0)
    end
    if cid and mode ~= 'creator' then DB.SetInside(cid, id) end
end

--- Coordinates + interior info the client needs to go inside.
local function interiorInfo(p)
    if p.type == 'shell' then
        local shell = Shared.ShellByModel(p.data.shell)
        if not shell then return nil end
        local o = Config.ShellOrigin
        return {
            kind = 'shell', model = shell.model, origin = o,
            spawn = vector4(o.x + shell.exit.x, o.y + shell.exit.y, o.z + shell.exit.z, shell.exit.w),
        }
    elseif p.type == 'ipl' then
        local exit = p.data.iplExit
        if not exit then
            local ipl = Shared.IplByKey(p.data.ipl)
            exit = ipl and ipl.exit
        end
        if not exit then return nil end
        return { kind = 'ipl', spawn = vector4(exit.x, exit.y, exit.z, exit.w or 0.0) }
    end
end

function Housing.Enter(src, p, mode)
    local info = interiorInfo(p)
    if not info then return nil, 'This property has no interior set up.' end
    setInside(src, p.id, mode)
    info.id = p.id
    info.mode = mode
    if mode ~= 'creator' and Upgrades then Upgrades.Motion(p, src) end
    return info
end

function Housing.Exit(src, toEntrance)
    local ins = Inside[src]
    local p = ins and Props[ins.id]
    setInside(src, nil)
    if not p then return nil end
    if toEntrance == false then return nil end
    local e = Housing.Entrance(p)
    return e and vector4(e.x, e.y, e.z, e.w or 0.0) or nil
end

--- Kick everyone out of a property's interior (sold, repossessed, deleted...).
function Housing.EmptyInterior(id, msg)
    for src, ins in pairs(Inside) do
        if ins.id == id then
            local out = Housing.Exit(src)
            TriggerClientEvent('pmv2_housing:forceExit', src, out, msg)
        end
    end
end

local function nearEntrance(src, p, dist)
    local e = Housing.Entrance(p)
    return e and #(Housing.Coords(src) - v3(e)) <= (dist or 4.0)
end

lib.callback.register('pmv2_housing:enter', function(src, id)
    local p = Housing.Get(id)
    if not p or not Shared.HasInterior(p.type) then return nil, 'Not available.' end
    if not nearEntrance(src, p) then return nil, 'Get closer to the door.' end
    local cid = Bridge.GetCitizenId(src)
    if not Housing.Can(p, cid, 'enter') then return nil, "You don't have a key." end
    return Housing.Enter(src, p, 'access')
end)

lib.callback.register('pmv2_housing:preview', function(src, id)
    local p = Housing.Get(id)
    if not p or not Shared.HasInterior(p.type) then return nil, 'Not available.' end
    if Housing.IsOccupied(p) or not (p.for_sale or p.for_rent) then return nil, 'This property is not listed.' end
    if not nearEntrance(src, p) then return nil, 'Get closer to the door.' end
    local info, err = Housing.Enter(src, p, 'preview')
    if not info then return nil, err end
    info.previewSeconds = Config.PreviewSeconds
    SetTimeout(Config.PreviewSeconds * 1000, function()
        local ins = Inside[src]
        if ins and ins.id == p.id and ins.mode == 'preview' then
            local out = Housing.Exit(src)
            TriggerClientEvent('pmv2_housing:forceExit', src, out, 'Your viewing has ended.')
        end
    end)
    return info
end)

lib.callback.register('pmv2_housing:exit', function(src)
    if not Inside[src] then return nil end
    return Housing.Exit(src)
end)

-- ── Doorbell ─────────────────────────────────────────────────
lib.callback.register('pmv2_housing:ring', function(src, id)
    local p = Housing.Get(id)
    if not p or not Housing.IsOccupied(p) then return false end
    if not nearEntrance(src, p, 6.0) then return false end
    Rings[p.id] = Rings[p.id] or {}
    Rings[p.id][src] = os.time()
    local knock = not p.state.util.electricity.on
    local who = Bridge.GetName(src)
    local heard = 0
    for target, ins in pairs(Inside) do
        if ins.id == p.id then
            heard = heard + 1
            TriggerClientEvent('pmv2_housing:doorbell', target, p.id, src, who, knock)
        end
    end
    if p.type == 'mlo' and p.data.zone then
        local center = v3(p.data.zone)
        for _, sid in ipairs(GetPlayers()) do
            local t = tonumber(sid)
            if t ~= src and #(Housing.Coords(t) - center) <= (p.data.zone.r or 20.0) then
                heard = heard + 1
                TriggerClientEvent('pmv2_housing:doorbell', t, p.id, src, who, knock)
            end
        end
    end
    return true, knock
end)

lib.callback.register('pmv2_housing:letIn', function(src, id, visitor)
    local p = Housing.Get(id)
    local ins = Inside[src]
    if not p or not ins or ins.id == nil or ins.id ~= p.id then return false end
    local cid = Bridge.GetCitizenId(src)
    if not Housing.Level(p, cid) then return false end
    visitor = tonumber(visitor)
    local rang = Rings[p.id] and Rings[p.id][visitor]
    if not rang or os.time() - rang > Config.DoorbellSeconds then
        Bridge.Notify(src, 'Nobody is waiting at the door.', 'error')
        return false
    end
    if not nearEntrance(visitor, p, 8.0) then
        Bridge.Notify(src, 'They walked away.', 'error')
        return false
    end
    Rings[p.id][visitor] = nil
    local info = Housing.Enter(visitor, p, 'guest')
    if info then TriggerClientEvent('pmv2_housing:goInside', visitor, info) end
    return info ~= nil
end)

-- ── Connect / disconnect ────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    Inside[src] = nil
    for _, list in pairs(Rings) do list[src] = nil end
end)

-- Anyone who logged out inside an interior is put back at the front door.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    local cid = player and player.PlayerData and player.PlayerData.citizenid
    if not src or not cid then return end
    Housing.WaitLoaded()

    for _, row in ipairs(DB.TakePayouts(cid)) do
        Bridge.AddBank(src, row.amount, row.reason or 'Housing')
        Bridge.Notify(src, ('%s received while you were away: %s'):format(Shared.Money(row.amount), row.reason or 'Housing'), 'success')
    end

    local insideId = DB.GetInside(cid)
    if insideId then
        DB.SetInside(cid, nil)
        local p = Props[insideId]
        local e = p and Housing.Entrance(p)
        SetPlayerRoutingBucket(src, 0)
        if e then
            SetTimeout(3000, function()
                TriggerClientEvent('pmv2_housing:forceExit', src, vector4(e.x, e.y, e.z, e.w or 0.0), nil)
            end)
        end
    end

    if Billing then SetTimeout(10000, function() Billing.OnLogin(src, cid) end) end
    Housing.PushAccess(cid)
end)

-- ── Shell offset helper ─────────────────────────────────────
lib.addCommand('houseoffset', {
    help = 'Print your position relative to the shell origin (for Config.Shells exit offsets)',
    restricted = 'group.admin',
}, function(src)
    local pos = Housing.Coords(src)
    local o = Config.ShellOrigin
    local h = GetEntityHeading(GetPlayerPed(src))
    local text = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(pos.x - o.x, pos.y - o.y, pos.z - o.z, h)
    TriggerClientEvent('pmv2_housing:copy', src, text)
end)

-- ── Exports for other scripts ───────────────────────────────
exports('GetProperty', function(id) return Housing.Get(id) end)
exports('GetAccessLevel', function(id, citizenid) return Housing.Level(Housing.Get(id), citizenid) end)
exports('GetPlayerProperties', function(citizenid) return Housing.AccessFor(citizenid) end)
exports('IsInside', function(src) return Inside[src] and Inside[src].id or nil end)
