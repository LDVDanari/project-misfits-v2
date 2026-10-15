-- ─────────────────────────────────────────────────────────────
--  PHONE API - what a phone's Homes app needs (YSeries / TeamsGG, LB...)
--  Names match the common housing-export style (GetKeyHolders, AddKey,
--  RemoveKey, ToggleDoorlock...) so phone bridges are easy to point here.
-- ─────────────────────────────────────────────────────────────
Phone = {}

--- true = locked, false = unlocked, nil = no lockable doors (shells/IPLs are always locked).
local function doorLocked(p)
    if p.type ~= 'mlo' or not p.data.doors or #p.data.doors == 0 then return nil end
    local ok, door = pcall(function() return exports.ox_doorlock:getDoor(p.data.doors[1]) end)
    if not ok or not door then return nil end
    return door.state == 1
end

local function keyholders(p)
    local list = {}
    for cid, a in pairs(p.access) do
        list[#list + 1] = { citizenid = cid, identifier = cid, name = a.name or cid, level = a.level, rent = a.rent }
    end
    table.sort(list, function(a, b) return (a.name or '') < (b.name or '') end)
    return list
end

--- Name of any character, online or not.
local function charName(cid)
    local src = Bridge.GetSource(cid)
    if src then return Bridge.GetName(src) end
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid })
    local ci = row and json.decode(row.charinfo or '{}') or {}
    if ci.firstname then return ('%s %s'):format(ci.firstname, ci.lastname or '') end
    return nil
end

function Phone.Property(p, cid)
    local e = Housing.Entrance(p)
    local level = Housing.Level(p, cid)
    local isManager = level == 'owner' or level == 'renter'
    return {
        id = p.id,
        label = p.label,
        type = p.type,
        typeLabel = Shared.Types[p.type],
        level = level,
        isOwner = level == 'owner',
        coords = e and vector3(e.x, e.y, e.z) or nil,
        locked = doorLocked(p),
        canLock = p.type == 'mlo' and p.data.doors and #p.data.doors > 0 and Housing.Can(p, cid, 'enter') or false,
        rentDue = (level == 'renter' and p.rent_due) or (p.access[cid] and p.access[cid].rent_due) or nil,
        rent = (level == 'renter' and p.data.rentAmount) or (p.access[cid] and p.access[cid].rent) or nil,
        bills = isManager and Billing.TotalDue(p) or nil,
        dirt = math.floor(p.state.dirt),
        utilities = isManager and {
            electricity = p.state.util.electricity.on,
            water = p.state.util.water.on,
            internet = p.state.util.internet.on,
        } or nil,
        keyholders = isManager and keyholders(p) or nil,
    }
end

-- ── Exports ──────────────────────────────────────────────────
--- Every property a character has any access to.
exports('GetOwnedProperties', function(citizenid)
    local out = {}
    for _, p in pairs(Props) do
        if Housing.Level(p, citizenid) then out[#out + 1] = Phone.Property(p, citizenid) end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

exports('GetAllProperties', function()
    local out = {}
    for _, p in pairs(Props) do out[#out + 1] = Housing.Public(p) end
    return out
end)

exports('GetPropertyData', function(id)
    local p = Housing.Get(id)
    if not p then return nil end
    local pub = Housing.Public(p)
    pub.owner, pub.owner_name, pub.renter, pub.renter_name = p.owner, p.owner_name, p.renter, p.renter_name
    pub.keyholders = keyholders(p)
    return pub
end)

exports('GetKeyHolders', function(id)
    local p = Housing.Get(id)
    return p and keyholders(p) or {}
end)

--- byCid = who is doing it (must be owner/renter). Pass nil to skip the check (admin scripts).
exports('AddKey', function(id, byCid, targetCid)
    local p = Housing.Get(id)
    if not p or not targetCid then return false, 'Property not found.' end
    if byCid then
        local level = Housing.Level(p, byCid)
        if level ~= 'owner' and level ~= 'renter' then return false, "You can't give keys here." end
    end
    local name = charName(targetCid)
    if not name then return false, 'That person does not exist.' end
    local ok, err = Owner.Grant(p, targetCid, name, 'keyholder')
    if ok then
        Bridge.Log('🗝️ Key given (phone)', ('**%s** got a key to **#%d %s**'):format(name, p.id, p.label))
        local s = Bridge.GetSource(targetCid)
        if s then Bridge.Notify(s, ('You got a key to %s.'):format(p.label), 'success') end
    end
    return ok, err
end)

exports('RemoveKey', function(id, byCid, targetCid)
    local p = Housing.Get(id)
    if not p or not targetCid or not p.access[targetCid] then return false end
    local a = p.access[targetCid]
    if byCid then
        local level = Housing.Level(p, byCid)
        if level ~= 'owner' and level ~= 'renter' then return false end
        if a.level == 'tenant' and level ~= 'owner' then return false end
    end
    p.access[targetCid] = nil
    DB.RemoveAccess(p.id, targetCid)
    Housing.Commit(p, { notify = { targetCid } })
    local s = Bridge.GetSource(targetCid)
    if s then Bridge.Notify(s, ('You no longer have access to %s.'):format(p.label), 'error') end
    return true
end)

--- Locks/unlocks every door of an MLO property. Returns the new locked state.
exports('ToggleDoorlock', function(id, byCid)
    local p = Housing.Get(id)
    if not p then return nil end
    if byCid and not Housing.Can(p, byCid, 'enter') then return nil end
    local locked = doorLocked(p)
    if locked == nil then return nil end
    Housing.LockDoors(p, locked and 0 or 1)
    return not locked
end)

-- Same actions for phone UIs that talk to us over callbacks instead of exports.
lib.callback.register('pmv2_housing:phone:list', function(src)
    local cid = Bridge.GetCitizenId(src)
    return cid and exports.pmv2_housing:GetOwnedProperties(cid) or {}
end)

lib.callback.register('pmv2_housing:phone:toggleLock', function(src, id)
    return exports.pmv2_housing:ToggleDoorlock(id, Bridge.GetCitizenId(src))
end)

lib.callback.register('pmv2_housing:phone:addKey', function(src, id, targetCid)
    return exports.pmv2_housing:AddKey(id, Bridge.GetCitizenId(src), targetCid)
end)

lib.callback.register('pmv2_housing:phone:removeKey', function(src, id, targetCid)
    return exports.pmv2_housing:RemoveKey(id, Bridge.GetCitizenId(src), targetCid)
end)
