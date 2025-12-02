-- rsg-economy / client.lua
-- District/state region detection + server callback bridge

local RSGCore = exports['rsg-core']:GetCoreObject()

-- client.lua — district-only region detection + command
-- Now self-contained in rsg-economy (no rsg-governor)

-- Exported detector (uses state_region.lua)
local function detect()
    -- state_region.lua in this resource exports getState()
    -- returns: { hash = number, name = string, source = string } or nil
    return exports['rsg-economy']:getState()
end

-- Server callback bridge (so server can ask the client)
-- sv_tax.lua should be calling: lib.callback.await('rsg-economy:getRegionHash', src)
lib.callback.register('rsg-economy:getRegionHash', function()
    local st = detect()
    if st then
        return st.hash, st.name
    end
    return nil, nil
end)

-- Simple local test command
RegisterCommand('checkregion', function()
    local st = detect()
    -- Optional: dump hashes from state_region debug
    exports['rsg-economy']:debugDump()
    if st then
        lib.notify({
            title       = 'Economy',
            description = ('You are in %s region.'):format(st.name, st.hash),
            type        = 'inform'
        })
    else
        lib.notify({
            title       = 'Economy',
            description = 'Unable to detect your State.',
            type        = 'error'
        })
    end
end, false)

-- zonepeek debug (unchanged, just useful)
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
  print(('[zonepeek] @ (%.2f, %.2f, %.2f)'):format(c.x,c.y,c.z))
  for _, t in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12}) do
    local h = q(t)
    if h ~= 0 then print(('[zonepeek] type=%d -> 0x%X'):format(t, h)) end
  end
end)

-- Simple hello command (optional flavor)
RegisterCommand('hello', function()
    lib.notify({
        title       = 'Economy',
        description = 'Howdy, partner! The economy resource is running.',
        type        = 'inform'
    })
    print('Player executed /hello command.')
end, false)
