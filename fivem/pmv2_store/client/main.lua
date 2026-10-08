-- Prints staff lookups to the F8 console (long text doesn't fit in a notification).
RegisterNetEvent('pmv2_store:print', function(lines)
    if type(lines) ~= 'table' then return end
    for _, line in ipairs(lines) do
        print(line)
    end
end)
