-- cl_main.lua
-- rsg-economy / client/cl_main.lua
-- District/state region detection + server callback bridge (FIXED)

local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

-- Convert "New Hanover" -> "new_hanover"
local function toAlias(name)
    name = tostring(name or ''):lower()
    name = name:gsub('[%s%-]+', '_')
    name = name:gsub('^_+', ''):gsub('_+$', '')
    return name
end

-- Exported detector (uses sh_state_region_helper.lua export getState())
local function detectState()
    -- returns: { hash = number, name = string, source = string } or nil
    return exports['rsg-economy']:getState()
end

-- Bridge: server asks client for region hash + alias
-- IMPORTANT: other server scripts call this as:
--   lib.callback.await('rsg-economy:getRegionHash', src)
-- We return: hash, alias
lib.callback.register('rsg-economy:getRegionHash', function()
    local st = detectState()
    if st and st.hash and st.name then
        local alias = toAlias(st.name) -- "new_hanover"
        return st.hash, alias
    end
    return nil, nil
end)

-- Optional: if you want a separate callback returning pretty name too
lib.callback.register('rsg-economy:getRegionInfo', function()
    local st = detectState()
    if st and st.hash and st.name then
        return st.hash, toAlias(st.name), st.name
    end
    return nil, nil, nil
end)

-- Test command
RegisterCommand('checkregion', function()
    local st = detectState()
    exports['rsg-economy']:debugDump()

    if not lib or not lib.notify then
        return print('[rsg-economy] ox_lib notify missing; cannot show UI message.')
    end

    if st then
        lib.notify({
            title       = locale('economy') or 'Economy',
            description = (locale('economy_description') or 'State: %s | Alias: %s | Hash: 0x%X'):format(st.name, toAlias(st.name), st.hash),
            type        = 'inform'
        })
    else
        lib.notify({
            title       = locale('economy') or 'Economy',
            description = locale('unable_to_detect_state') or 'Unable to detect your State.',
            type        = 'error'
        })
    end
end, false)

-- zonepeek debug
RegisterCommand('zonepeek', function()
    local p = PlayerPedId()
    local c = GetEntityCoords(p)
    local native = 0x43AD8FC02B429D33

    local function q(t)
        local ok, ret = pcall(Citizen.InvokeNative, native, c.x, c.y, c.z, t, Citizen.ResultAsInteger())
        if ok and ret then return ret end
        ok, ret = pcall(Citizen.InvokeNative, native, c.x, c.y, c.z, t)
        return ok and ret or 0
    end

    print(('[zonepeek] @ (%.2f, %.2f, %.2f)'):format(c.x, c.y, c.z))
    for _, t in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12}) do
        local h = q(t)
        if h ~= 0 then print(('[zonepeek] type=%d -> 0x%X'):format(t, h)) end
    end
end, false)

RegisterCommand('hello', function()
    if lib and lib.notify then
        lib.notify({
            title       = locale('economy') or 'Economy',
            description = locale('hello_description') or 'Howdy, partner! The economy resource is running.',
            type        = 'inform'
        })
    end
    print('Player executed /hello command.')
end, false)
