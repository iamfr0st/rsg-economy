-- sh_state_region_helper.lua
--==============================================================
-- state_region.lua — district→state (config-driven)
-- Uses Config.StateDistricts (string "STATE_*" or numeric hashes)
-- Exports:
--   getState(coords?) -> { hash:number, name:string, source:string } | nil
--   debugDump(coords?)
--==============================================================

local J = GetHashKey
local UINT32 = 4294967296

--==============================================================
-- Helpers
--==============================================================
local function v3(x, y, z)
    if type(vec3) == "function" then return vec3(x, y, z) end
    if type(vector3) == "function" then return vector3(x, y, z) end
    return { x = x, y = y, z = z }
end

local function norm(v)
    if v == nil then return 0 end
    local t = type(v)
    if t == "string" then
        local s = v:lower()
        if s:sub(1,2) == "0x" then
            v = tonumber(s) or 0
        elseif s:find("^state_") then
            v = J(s:upper())
        else
            v = J(("STATE_%s"):format(s:gsub("%s+", "_"):upper()))
        end
    elseif t ~= "number" then
        return 0
    end
    if v < 0 then v = (v % UINT32 + UINT32) % UINT32 else v = v % UINT32 end
    return v
end

--==============================================================
-- Canonical fallback names
--==============================================================
local CANON_STATES = {
    { hash = J("STATE_AMBARINO"),        name = "Ambarino" },
    { hash = J("STATE_LEMOYNE"),         name = "Lemoyne" },
    { hash = J("STATE_NEW_HANOVER"),     name = "New Hanover" },
    { hash = J("STATE_WEST_ELIZABETH"),  name = "West Elizabeth" },
    { hash = J("STATE_NEW_AUSTIN"),      name = "New Austin" },
    { hash = J("STATE_GUARMA"),          name = "Guarma" },
}
local CANON_NAME_BY_HASH = {}; for _, s in ipairs(CANON_STATES) do CANON_NAME_BY_HASH[s.hash] = s.name end

--==============================================================
-- Reverse map (district → state)
--==============================================================
local D2S, NAME_BY_HASH, built_ok = {}, {}, false
local function clear(t) for k in pairs(t) do t[k] = nil end end
local function ensureConfig() return rawget(_G, 'Config') and type(Config.StateDistricts) == 'table' end

local function buildReverse()
    clear(D2S); clear(NAME_BY_HASH)
    built_ok = false

    if not ensureConfig() then
        return false
    end

    for stateKey, arr in pairs(Config.StateDistricts) do
        local sHash = norm(stateKey)
        if sHash ~= 0 and type(arr) == 'table' then
            if not NAME_BY_HASH[sHash] and type(stateKey) == "string" then
                local k = stateKey
                if not k:find("^STATE_") then k = "STATE_" .. k end
                NAME_BY_HASH[sHash] =
                    k:gsub("^STATE_", ""):gsub("_", " "):gsub("(%a)([%w_]*)", function(a,b) return a:upper()..b:lower() end)
            end
            for _, d in ipairs(arr) do
                local dHash = norm(d)
                if dHash ~= 0 then D2S[dHash] = sHash end
            end
        end
    end

    built_ok = next(D2S) ~= nil
    return built_ok
end

local function ensureBuilt()
    if built_ok and next(D2S) ~= nil then return true end
    return buildReverse()
end

-- Background gentle rebuild attempt (handles Config arriving late)
CreateThread(function()
    for _ = 1, 30 do
        if ensureBuilt() then return end
        Wait(500)
    end
end)

--==============================================================
-- Native wrapper
--==============================================================
local N_GET_MAP_ZONE_AT_COORDS = 0x43AD8FC02B429D33
local function zoneHashAt(coords, typeId)
    local ok, ret = pcall(Citizen.InvokeNative, N_GET_MAP_ZONE_AT_COORDS,
        coords.x, coords.y, coords.z, typeId, Citizen.ResultAsInteger())
    if ok and ret then return norm(ret) end

    ok, ret = pcall(Citizen.InvokeNative, N_GET_MAP_ZONE_AT_COORDS,
        coords.x, coords.y, coords.z, typeId)
    if ok and ret then return norm(ret) end

    return 0
end

--==============================================================
-- Detector (district-only)
--==============================================================
local function detectState(coords)
    if not ensureBuilt() then return nil end
    local dHash = zoneHashAt(coords, 10) -- district
    local sHash = D2S[dHash]

    if not sHash and buildReverse() then sHash = D2S[dHash] end
    if not sHash then
        return nil
    end

    local name = NAME_BY_HASH[sHash] or CANON_NAME_BY_HASH[sHash] or 'Unknown State'
    return { hash = sHash, name = name, source = ("district(0x%X)"):format(dHash) }
end

--==============================================================
-- Exports
--==============================================================
exports('getState', function(coords)
    if not coords and not IsDuplicityVersion() then
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            coords = v3(c.x or c[1], c.y or c[2], c.z or c[3])
        end
    end
    if not coords then return nil end
    if coords.x == nil and type(coords[1]) == "number" then
        coords = v3(coords[1], coords[2], coords[3] or 0.0)
    end
    return detectState(coords)
end)

exports('debugDump', function(coords)
    if not coords and not IsDuplicityVersion() then
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            coords = v3(c.x or c[1], c.y or c[2], c.z or c[3])
        end
    end
    if not coords then print("[state_region] debugDump: no coords") return end

    local function fmt(h) return ("0x%X"):format(h or 0) end
    local stateH    = zoneHashAt(coords, 0)
    local districtH = zoneHashAt(coords, 10)
    print(("[state_region] --- debugDump @ (%.2f, %.2f, %.2f) ---"):format(coords.x, coords.y, coords.z))
    print(("[state_region] type=STATE    id=0  hash=%s"):format(fmt(stateH)))
    print(("[state_region] type=DISTRICT id=10 hash=%s"):format(fmt(districtH)))
    local st = detectState(coords)
    if st then
        print(("[state_region] DETECTED STATE: %s (%s) via %s"):format(st.name, fmt(st.hash), st.source))
    else
        print("[state_region] DETECTED STATE: <nil>")
    end
end)
