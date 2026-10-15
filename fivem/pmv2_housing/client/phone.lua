-- Phone helpers (client)
exports('SetWaypointToProperty', function(id)
    local p = Props[tonumber(id) or -1]
    local e = p and Housing_Entrance(p)
    if not e then return false end
    SetNewWaypoint(e.x, e.y)
    Bridge.Notify('GPS set to ' .. p.label)
    return true
end)

exports('GetCurrentPropertyId', function()
    return Current and Current.id or nil
end)

exports('GetEntryCoordinates', function(id)
    local p = Props[tonumber(id) or -1]
    local e = p and Housing_Entrance(p)
    return e and vector3(e.x, e.y, e.z) or nil
end)
