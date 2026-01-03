-- sh_region_helper.lua
-- regions.lua (drop-in)
-- Lightweight zone/region resolver for RedM / RDR2
-- Covers States, Districts, Towns and common Water zones.
-- Uses joaat(GetHashKey) so you don't need to paste raw hex hashes.

local J = GetHashKey
local Regions = {}

-- Zone type enum (we will USE typeIds for native calls)
Regions.ZONE_TYPE = {
  STATE    = 0,
  TOWN     = 1,
  LAKE     = 2,
  RIVER    = 3,
  OIL      = 4,
  SWAMP    = 5,
  OCEAN    = 6,
  CREEK    = 7,
  POND     = 8,
  DISTRICT = 10,
}

-- Helpers
local function title_from_key(key)
  return (key:gsub("_", " ")
             :lower()
             :gsub("(%l)(%w*)", function(a,b) return a:upper()..b end))
end

local function name_from_map(tbl, hash)
  for k,v in pairs(tbl) do
    if v == hash then return title_from_key(k) end
  end
  return nil
end

-- =========================
-- Hash Tables (joaat keys)
-- =========================

Regions.STATE = {
  AMBARINO        = J("STATE_AMBARINO"),
  LEMOYNE         = J("STATE_LEMOYNE"),
  NEW_HANOVER     = J("STATE_NEW_HANOVER"),
  WEST_ELIZABETH  = J("STATE_WEST_ELIZABETH"),
  NEW_AUSTIN      = J("STATE_NEW_AUSTIN"),
  GUARMA          = J("STATE_GUARMA"),
}

Regions.DISTRICT = {
  GRIZZLIES_WEST     = J("DISTRICT_GRIZZLIES_WEST"),
  GRIZZLIES_EAST     = J("DISTRICT_GRIZZLIES_EAST"),
  THE_HEARTLANDS     = J("DISTRICT_THE_HEARTLANDS"),
  ROANOKE_RIDGE      = J("DISTRICT_ROANOKE_RIDGE"),
  BAYOU_NWA          = J("DISTRICT_BAYOU_NWA"),
  SCARLETT_MEADOWS   = J("DISTRICT_SCARLETT_MEADOWS"),
  BLUEGILL_MARSH     = J("DISTRICT_BLUEGILL_MARSH"),
  BIG_VALLEY         = J("DISTRICT_BIG_VALLEY"),
  GREAT_PLAINS       = J("DISTRICT_GREAT_PLAINS"),
  TALL_TREES         = J("DISTRICT_TALL_TREES"),
  RIO_BRAVO          = J("DISTRICT_RIO_BRAVO"),
  CHOLLA_SPRINGS     = J("DISTRICT_CHOLLA_SPRINGS"),
  HENNIGANS_STEAD    = J("DISTRICT_HENNIGANS_STEAD"),
}

Regions.TOWN = {
  VALENTINE     = J("TOWN_VALENTINE"),
  RHODES        = J("TOWN_RHODES"),
  STRAWBERRY    = J("TOWN_STRAWBERRY"),
  BLACKWATER    = J("TOWN_BLACKWATER"),
  SAINT_DENIS   = J("TOWN_SAINT_DENIS"),
  VAN_HORN      = J("TOWN_VAN_HORN"),
  ANNENSBURG    = J("TOWN_ANNESBURG"),
  EMERALD_RANCH = J("TOWN_EMERALD_RANCH"),
  ARMADILLO     = J("TOWN_ARMADILLO"),
  TUMBLEWEED    = J("TOWN_TUMBLEWEED"),
  LAGRAS        = J("TOWN_LAGRAS"),
  WAPITI        = J("TOWN_WAPITI"),
  MANZANITA     = J("TOWN_MANZANITA"),
}

Regions.WATER = {
  FLAT_IRON_LAKE      = J("WATER_FLAT_IRON"),
  KAMASSA_RIVER       = J("WATER_KAMASSA"),
  DAKOTA_RIVER        = J("WATER_DAKOTA"),
  UPPER_MONTANA_RIVER = J("WATER_UPPER_MONTANA"),
  LOWER_MONTANA_RIVER = J("WATER_LOWER_MONTANA"),
  SAN_LUIS_RIVER      = J("WATER_SAN_LUIS"),
  LANAHECHEE_RIVER    = J("WATER_LANAHECHEE"),
  OWANJILA            = J("WATER_OWANJILA"),
  ELYSIAN_POOL        = J("WATER_ELYSIAN_POOL"),
  LAGRAS_SWAMP        = J("WATER_BAYOU_NWA"),
}

-- =========================
-- Configurable coloring for STATES
-- =========================
Regions.Config = {
  Zones = {
    { Hash = Regions.STATE.AMBARINO,       Name = "Ambarino",       Color = "BLIP_MODIFIER_MP_COLOR_1" },
    { Hash = Regions.STATE.LEMOYNE,        Name = "Lemoyne",        Color = "BLIP_MODIFIER_MP_COLOR_3" },
    { Hash = Regions.STATE.NEW_HANOVER,    Name = "New Hanover",    Color = "BLIP_MODIFIER_MP_COLOR_2" },
    { Hash = Regions.STATE.WEST_ELIZABETH, Name = "West Elizabeth", Color = "BLIP_MODIFIER_MP_COLOR_4" },
    { Hash = Regions.STATE.NEW_AUSTIN,     Name = "New Austin",     Color = "BLIP_MODIFIER_MP_COLOR_5" },
    { Hash = Regions.STATE.GUARMA,         Name = "Guarma",         Color = "BLIP_MODIFIER_MP_COLOR_6" },
  },
  DefaultColor = "BLIP_MODIFIER_MP_COLOR_9",
}

local _stateIndex = {}
for _, row in ipairs(Regions.Config.Zones) do _stateIndex[row.Hash] = row end

-- =========================
-- Core: correct native wrapper
-- =========================

local N_GET_MAP_ZONE_AT_COORDS = 0x43AD8FC02B429D33

---Return zone hash for a given zone typeId (0=STATE, 10=DISTRICT, 1=TOWN, etc)
local function getZoneHash(coords, typeId)
  local ok, ret = pcall(Citizen.InvokeNative, N_GET_MAP_ZONE_AT_COORDS,
    coords.x, coords.y, coords.z, typeId, Citizen.ResultAsInteger())
  if ok and ret then return ret end

  ok, ret = pcall(Citizen.InvokeNative, N_GET_MAP_ZONE_AT_COORDS,
    coords.x, coords.y, coords.z, typeId)
  if ok and ret then return ret end

  return 0
end

---Returns hashes for common layers
function Regions.getZoneLayers(coords)
  return {
    state    = getZoneHash(coords, Regions.ZONE_TYPE.STATE),
    town     = getZoneHash(coords, Regions.ZONE_TYPE.TOWN),
    district = getZoneHash(coords, Regions.ZONE_TYPE.DISTRICT),
    lake     = getZoneHash(coords, Regions.ZONE_TYPE.LAKE),
    river    = getZoneHash(coords, Regions.ZONE_TYPE.RIVER),
    ocean    = getZoneHash(coords, Regions.ZONE_TYPE.OCEAN),
    swamp    = getZoneHash(coords, Regions.ZONE_TYPE.SWAMP),
    creek    = getZoneHash(coords, Regions.ZONE_TYPE.CREEK),
    pond     = getZoneHash(coords, Regions.ZONE_TYPE.POND),
  }
end

---Try state name/color (always best-effort)
function Regions.getStateInfo(coords)
  local layers = Regions.getZoneLayers(coords)
  local sHash  = layers.state

  if sHash and sHash ~= 0 and _stateIndex[sHash] then
    local row = _stateIndex[sHash]
    return row.Name, row.Color, sHash
  end

  return nil, Regions.Config.DefaultColor, nil
end

-- =========================
-- Public: resolve() main API
-- =========================

function Regions.resolve(coords)
  local layers = Regions.getZoneLayers(coords)

  local stateName, stateColor, stateHash = Regions.getStateInfo(coords)

  -- Determine primary “local name”
  local scope, name, hash, ztype = "unknown", nil, 0, -1

  if layers.town and layers.town ~= 0 then
    name = name_from_map(Regions.TOWN, layers.town)
    if name then
      scope, hash, ztype = "town", layers.town, Regions.ZONE_TYPE.TOWN
    end
  end

  if not name and layers.district and layers.district ~= 0 then
    name = name_from_map(Regions.DISTRICT, layers.district)
    if name then
      scope, hash, ztype = "district", layers.district, Regions.ZONE_TYPE.DISTRICT
    end
  end

  if not name then
    -- water layers (first hit wins)
    local waterOrder = {
      { key="lake",  typeId=Regions.ZONE_TYPE.LAKE },
      { key="river", typeId=Regions.ZONE_TYPE.RIVER },
      { key="ocean", typeId=Regions.ZONE_TYPE.OCEAN },
      { key="swamp", typeId=Regions.ZONE_TYPE.SWAMP },
      { key="creek", typeId=Regions.ZONE_TYPE.CREEK },
      { key="pond",  typeId=Regions.ZONE_TYPE.POND },
    }
    for _, w in ipairs(waterOrder) do
      local h = layers[w.key]
      if h and h ~= 0 then
        local wn = name_from_map(Regions.WATER, h)
        if wn then
          name = wn
          scope, hash, ztype = "water", h, w.typeId
          break
        end
      end
    end
  end

  if not name and stateName and stateHash and stateHash ~= 0 then
    name  = stateName
    scope = "state"
    hash  = stateHash
    ztype = Regions.ZONE_TYPE.STATE
  end

  return {
    name       = name or "Unknown Area",
    color      = stateColor or Regions.Config.DefaultColor,
    hash       = hash,
    type       = ztype,
    scope      = scope,
    state_hash = stateHash,
    state_name = stateName,
    layers     = layers,
  }
end

function Regions.debugPrintHere(coords)
  local info = Regions.resolve(coords)
  local function hx(n) return ("0x%X"):format(tonumber(n or 0) or 0) end
  print(("[regions] %s | scope=%s type=%s hash=%s | state=%s (%s) | color=%s")
    :format(
      info.name, info.scope, tostring(info.type), hx(info.hash),
      info.state_name or "?", hx(info.state_hash),
      info.color
    ))
end

exports('resolve', Regions.resolve)
exports('debugPrintHere', Regions.debugPrintHere)

return Regions
