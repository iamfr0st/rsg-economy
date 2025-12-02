-- regions.lua (drop-in)
-- Lightweight zone/region resolver for RedM / RDR2
-- Covers States, Districts, Towns and common Water zones.
-- Uses joaat(GetHashKey) so you don't need to paste raw hex hashes.

local J = GetHashKey

local Regions = {}

-- Zone type enum (return value #2 of GET_MAP_ZONE_AT_COORDS)
Regions.ZONE_TYPE = {
  STATE   = 0,
  TOWN    = 1,
  LAKE    = 2,
  RIVER   = 3,
  OIL     = 4,
  SWAMP   = 5,
  OCEAN   = 6,
  CREEK   = 7,
  POND    = 8,
  [9]     = "UNUSED9",
  DISTRICT= 10,
  [11]    = "UNUSED11",
}

-- Helpers
local function title_from_key(key)
  -- "THE_HEARTLANDS" -> "The Heartlands"
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

-- States (complete)
Regions.STATE = {
  AMBARINO        = J("STATE_AMBARINO"),
  LEMOYNE         = J("STATE_LEMOYNE"),
  NEW_HANOVER     = J("STATE_NEW_HANOVER"),
  WEST_ELIZABETH  = J("STATE_WEST_ELIZABETH"),
  NEW_AUSTIN      = J("STATE_NEW_AUSTIN"),
  GUARMA          = J("STATE_GUARMA"),
}

-- Districts (common / high-traffic)
Regions.DISTRICT = {
  -- Ambarino / Grizzlies
  GRIZZLIES_WEST     = J("DISTRICT_GRIZZLIES_WEST"),
  GRIZZLIES_EAST     = J("DISTRICT_GRIZZLIES_EAST"),
  -- New Hanover
  THE_HEARTLANDS     = J("DISTRICT_THE_HEARTLANDS"),
  ROANOKE_RIDGE      = J("DISTRICT_ROANOKE_RIDGE"),
  -- Lemoyne
  BAYOU_NWA          = J("DISTRICT_BAYOU_NWA"),
  SCARLETT_MEADOWS   = J("DISTRICT_SCARLETT_MEADOWS"),
  BLUEGILL_MARSH     = J("DISTRICT_BLUEGILL_MARSH"),
  -- West Elizabeth
  BIG_VALLEY         = J("DISTRICT_BIG_VALLEY"),
  GREAT_PLAINS       = J("DISTRICT_GREAT_PLAINS"),
  TALL_TREES         = J("DISTRICT_TALL_TREES"),
  -- New Austin
  RIO_BRAVO          = J("DISTRICT_RIO_BRAVO"),
  CHOLLA_SPRINGS     = J("DISTRICT_CHOLLA_SPRINGS"),
  HENNIGANS_STEAD    = J("DISTRICT_HENNIGANS_STEAD"),
}

-- Towns / Settlements (common)
Regions.TOWN = {
  VALENTINE    = J("TOWN_VALENTINE"),
  RHODES       = J("TOWN_RHODES"),
  STRAWBERRY   = J("TOWN_STRAWBERRY"),
  BLACKWATER   = J("TOWN_BLACKWATER"),
  SAINT_DENIS  = J("TOWN_SAINT_DENIS"),
  VAN_HORN     = J("TOWN_VAN_HORN"),
  ANNENSBURG   = J("TOWN_ANNESBURG"),
  EMERALD_RANCH= J("TOWN_EMERALD_RANCH"),
  ARMADILLO    = J("TOWN_ARMADILLO"),
  TUMBLEWEED   = J("TOWN_TUMBLEWEED"),
  LAGRAS       = J("TOWN_LAGRAS"),
  WAPITI       = J("TOWN_WAPITI"),
  MANZANITA    = J("TOWN_MANZANITA"),
}

-- Water (handy for roleplay messages)
Regions.WATER = {
  FLAT_IRON_LAKE     = J("WATER_FLAT_IRON"),
  KAMASSA_RIVER      = J("WATER_KAMASSA"),
  DAKOTA_RIVER       = J("WATER_DAKOTA"),
  UPPER_MONTANA_RIVER= J("WATER_UPPER_MONTANA"),
  LOWER_MONTANA_RIVER= J("WATER_LOWER_MONTANA"),
  SAN_LUIS_RIVER     = J("WATER_SAN_LUIS"),
  LANAHECHEE_RIVER   = J("WATER_LANAHECHEE"),
  OWANJILA           = J("WATER_OWANJILA"),
  ELYSIAN_POOL       = J("WATER_ELYSIAN_POOL"),
  LAGRAS_SWAMP       = J("WATER_BAYOU_NWA"),
}

-- =========================
-- Configurable coloring for STATES
-- (district/town/water will fall back)
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

-- =========================
-- Core: native wrappers
-- =========================

---Returns zoneHash, zoneType for a world coord
---@param coords vector3
function Regions.getZoneAtCoords(coords)
  -- GET_MAP_ZONE_AT_COORDS (0x43AD8FC02B429D33)
  local zh   = Citizen.InvokeNative(0x43AD8FC02B429D33, coords.x, coords.y, coords.z, Citizen.ResultAsInteger())
  local ztyp = Citizen.InvokeNative(0x43AD8FC02B429D33, coords.x, coords.y, coords.z, Citizen.ResultAsInteger(), Citizen.ResultAsInteger())
  -- note: some bindings need two separate calls; others return both. this keeps compatibility.
  return zh, ztyp
end

-- Optional: find the *state* that contains a coord by probing common states.
-- Cheap and reliable for coloring even if current zoneType is not STATE.
local _stateIndex = {}
for _, row in ipairs(Regions.Config.Zones) do _stateIndex[row.Hash] = row end

---Try to infer state name/color given ANY zone hash (by proximity check).
---If the current zone IS a state, this returns it directly.
---@param coords vector3
function Regions.getStateInfo(coords)
  -- If current zone is a STATE, just match directly.
  local zh, zt = Regions.getZoneAtCoords(coords)
  if zt == Regions.ZONE_TYPE.STATE and _stateIndex[zh] then
    local row = _stateIndex[zh]
    return row.Name, row.Color, zh
  end

  -- Otherwise, sample a small 2D ring around the ped to catch parent STATE.
  -- (In practice, states are large; this will usually hit a state band.)
  local ped = PlayerPedId()
  local base = coords
  local offsets = {
    vec3(0.0, 0.0, 0.0),
    vec3(25.0, 0.0, 0.0), vec3(-25.0, 0.0, 0.0),
    vec3(0.0, 25.0, 0.0), vec3(0.0, -25.0, 0.0),
  }
  for _, off in ipairs(offsets) do
    local sample = base + off
    local sHash, sType = Regions.getZoneAtCoords(sample)
    if sType == Regions.ZONE_TYPE.STATE and _stateIndex[sHash] then
      local row = _stateIndex[sHash]
      return row.Name, row.Color, sHash
    end
  end

  -- Fallback
  return nil, Regions.Config.DefaultColor, nil
end

-- =========================
-- Public: resolve() main API
-- =========================

---Resolve a friendly label and color for the player's location.
---@param coords vector3
---@return { name:string, color:string, hash:number, type:number, scope:string, state_hash?:number, state_name?:string }
function Regions.resolve(coords)
  local zHash, zType = Regions.getZoneAtCoords(coords)

  -- 1) If it is a STATE, we're done (guaranteed coverage)
  if zType == Regions.ZONE_TYPE.STATE then
    local stateRow = _stateIndex[zHash]
    if stateRow then
      return {
        name  = stateRow.Name,
        color = stateRow.Color,
        hash  = zHash,
        type  = zType,
        scope = "state",
        state_hash = zHash,
        state_name = stateRow.Name,
      }
    end
  end

  -- 2) District / Town / Water name lookup
  local scope, name = nil, nil
  if zType == Regions.ZONE_TYPE.DISTRICT then
    name, scope = name_from_map(Regions.DISTRICT, zHash), "district"
  elseif zType == Regions.ZONE_TYPE.TOWN then
    name, scope = name_from_map(Regions.TOWN, zHash), "town"
  elseif zType == Regions.ZONE_TYPE.LAKE
      or zType == Regions.ZONE_TYPE.RIVER
      or zType == Regions.ZONE_TYPE.OCEAN
      or zType == Regions.ZONE_TYPE.CREEK
      or zType == Regions.ZONE_TYPE.POND
      or zType == Regions.ZONE_TYPE.SWAMP then
    name, scope = name_from_map(Regions.WATER, zHash), "water"
  end

  -- 3) Always try to obtain a state color (even if current zone isn't a state)
  local stateName, stateColor, stateHash = Regions.getStateInfo(coords)

  -- Name priority: explicit name > "Unknown Area"
  local finalName = name or "Unknown Area"
  local finalColor = stateColor or Regions.Config.DefaultColor

  return {
    name  = finalName,
    color = finalColor,
    hash  = zHash,
    type  = zType,
    scope = scope or "unknown",
    state_hash = stateHash,
    state_name = stateName,
  }
end

-- =========================
-- Convenience: pretty print
-- =========================
function Regions.debugPrintHere(coords)
  local info = Regions.resolve(coords)
  print(("[regions] %s | scope=%s type=%s hash=0x%X | state=%s | color=%s")
    :format(info.name, info.scope, tostring(info.type), info.hash,
            info.state_name or "?", info.color))
end

-- =========================
-- Example export (fxmanifest)
-- exports { "resolve", "debugPrintHere" }
-- =========================

return Regions