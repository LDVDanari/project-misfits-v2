Shared = {}

Shared.Types = {
    mlo = 'MLO',
    shell = 'Shell',
    ipl = 'IPL',
    building = 'Apartment Building',
}

-- Points the creator can place, per property type.
--   inside = placed inside the interior (shell/IPL: stored relative to the interior)
Shared.Points = {
    { key = 'stash',       label = 'Stash',             icon = 'box-archive' },
    { key = 'wardrobe',    label = 'Wardrobe',          icon = 'shirt' },
    { key = 'garage',      label = 'Garage (entry)',    icon = 'warehouse', outside = true },
    { key = 'garageSpawn', label = 'Garage (car spawn)',icon = 'car',       outside = true, heading = true },
    { key = 'electricity', label = 'Electric Box',      icon = 'bolt' },
    { key = 'water',       label = 'Water Valve',       icon = 'droplet' },
    { key = 'internet',    label = 'Internet Router',   icon = 'wifi' },
}

Shared.UtilityKeys = { 'electricity', 'water', 'internet' }

function Shared.ShellByModel(model)
    for _, s in ipairs(Config.Shells) do
        if s.model == model then return s end
    end
end

function Shared.IplByKey(key)
    for _, i in ipairs(Config.IPLs) do
        if i.key == key then return i end
    end
end

function Shared.HasInterior(t)
    return t == 'shell' or t == 'ipl'
end

function Shared.Money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return '$' .. out:gsub('^,', '')
end
