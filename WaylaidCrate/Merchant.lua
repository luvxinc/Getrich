local addonName, WC = ...

-- Merchant.lua: remembers what vendors sell for gold (read when the player opens a merchant window) and
-- answers WC:VendorPrice(itemID) from those observations, falling back to the built-in table WC.VENDOR.
--
-- SavedVariables (owned by this file; Store creates the empty table):
--   db.vendorObs[itemID] = { price = copper per single item, bundle = items per purchase, npc = npcID, name = npc name,
--                            zone, map = uiMapID, x, y (0-100), limited = true if the vendor has limited stock,
--                            stock = items in stock when seen (limited only; nil = unlimited),
--                            faction = player's faction, npcFaction = vendor's faction ("Neutral" if none), t = time }
-- Sold-out offers (numAvailable == 0) are not stored; a stored offer of the same vendor is dropped when it sells out.
-- One offer per item: the cheapest unlimited one (limited stock only if that's all we have seen).
--
-- API checked against the Forever UI source (wow-ui-source, branch forever, 1.60.1.70450):
--   C_MerchantFrame.GetItemInfo(index) -> MerchantItemInfo { name?, texture, price, stackCount, numAvailable,
--     isPurchasable, isUsable, hasExtendedCost, currencyID?, spellID?, isQuestStartItem }
--     (APIDoc/MerchantFrameDocumentation.lua:27, :126). `price` buys `stackCount` items
--     (Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua:719 divides price by stackCount).
--   numAvailable: -1 = unlimited, >= 0 = limited stock (SetItemButtonStock shows it only when > 0;
--     MerchantFrame.lua:373 greys out numAvailable == 0).
--   GetMerchantNumItems / GetMerchantItemID / GetMerchantItemLink: MerchantFrame.lua:278, 359, 307.
--   C_Map.GetBestMapForUnit / GetPlayerMapPosition (Vector2DMixin): APIDoc/MapDocumentation.lua:49, :437.
--   UnitGUID may return a secret value (SecretWhenUnitIdentityRestricted, APIDoc/UnitDocumentation.lua:1241).

local Merchant = {}
WC.Merchant = Merchant

local ready = false
local cache = {}        -- itemID -> { price, info } | false   (cleared on VENDOR_UPDATED)
local myFaction         -- "Alliance" | "Horde" | nil

local function DB()
  if not ready then
    if type(WaylaidCrateDB) ~= "table" then return nil end
    ready = true
  end
  local db = WC:DB()
  if type(db) ~= "table" then return nil end
  if type(db.vendorObs) ~= "table" then db.vendorObs = {} end
  return db
end

local function Plain(v)
  if v == nil then return nil end
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return nil end
  end
  return v
end

local function PlayerFaction()
  if myFaction then return myFaction end
  if UnitFactionGroup then
    local ok, f = pcall(UnitFactionGroup, "player")
    f = ok and Plain(f) or nil
    if f == "Alliance" or f == "Horde" then myFaction = f end
  end
  return myFaction
end

-- can the current character buy from this observed vendor? (faction not known yet: trust what a character of
-- this account has seen -- it could buy there)
local function Usable(o)
  local f = o.npcFaction or o.faction
  local mine = PlayerFaction()
  return f == nil or f == "" or f == "Neutral" or mine == nil or f == mine
end

-- npcID (number) and name of the merchant
local function NpcInfo()
  local id, name, faction
  if UnitGUID then
    local ok, guid = pcall(UnitGUID, "npc")
    guid = ok and Plain(guid) or nil
    if type(guid) == "string" then
      -- Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>
      local okM, kind, npc = pcall(string.match, guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
      if okM and (kind == "Creature" or kind == "Vehicle") then id = tonumber(npc) end
    end
  end
  if UnitName then
    local ok, n = pcall(UnitName, "npc")
    n = ok and Plain(n) or nil
    if type(n) == "string" and n ~= "" then name = n end
  end
  if UnitFactionGroup then
    local ok, f = pcall(UnitFactionGroup, "npc")
    if ok then
      f = Plain(f)
      if f == "Alliance" or f == "Horde" then faction = f
      elseif f == nil or f == "" or f == "Neutral" then faction = "Neutral" end
    end
  end
  return id, name, faction
end

local function Round1(v) return math.floor(v * 1000 + 0.5) / 10 end

-- where the player stands: zone text, uiMapID, x, y (0-100, one decimal)
local function Location()
  local zone = (GetZoneText and GetZoneText()) or nil
  if zone == "" then zone = nil end
  local map, x, y
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and type(m) == "number" then
      map = m
      local okP, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
      if okP and type(pos) == "table" and pos.GetXY then
        local okX, px, py = pcall(pos.GetXY, pos)
        if okX and type(px) == "number" and type(py) == "number" and (px > 0 or py > 0) then
          x, y = Round1(px), Round1(py)
        end
      end
    end
  end
  return zone, map, x, y
end

local function MerchantItemID(i)
  if GetMerchantItemID then
    local ok, id = pcall(GetMerchantItemID, i)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  if GetMerchantItemLink then
    local ok, link = pcall(GetMerchantItemLink, i)
    if ok and type(link) == "string" then return tonumber(link:match("item:(%d+)")) end
  end
  return nil
end

-- should offer `new` replace the stored offer `old`?
local function Better(old, new)
  if type(old) ~= "table" or type(old.price) ~= "number" then return true end
  if new.npc and old.npc == new.npc and old.name == new.name then return true end   -- same vendor: fresh data
  local ou, nu = Usable(old), Usable(new)
  if ou ~= nu then return nu end
  if (old.limited and true or false) ~= (new.limited and true or false) then return not new.limited end
  return new.price < old.price
end

-- same offer (price-wise) as before? Location/time may still differ a little.
local function Same(a, b)
  if type(a) ~= "table" then return false end
  for _, k in ipairs({ "price", "bundle", "npc", "name", "limited", "stock", "npcFaction" }) do
    if a[k] ~= b[k] then return false end
  end
  return true
end

-- read the open merchant window
function Merchant:Scan()
  local db = DB()
  if not db or not GetMerchantNumItems or not (C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return 0 end
  local okN, n = pcall(GetMerchantNumItems)
  if not okN or type(n) ~= "number" or n <= 0 then return 0 end
  local npc, npcName, npcFaction = NpcInfo()
  local zone, map, x, y = Location()
  local faction, now = PlayerFaction(), time()
  local obs, seen, changed = db.vendorObs, 0, false
  for i = 1, n do
    local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(info) == "table" and type(info.price) == "number" and info.price > 0
       and not info.hasExtendedCost and not info.currencyID and info.isPurchasable ~= false then
      local itemID = MerchantItemID(i)
      local avail = tonumber(info.numAvailable) or -1      -- -1 unlimited, 0 sold out, n in stock
      local old = itemID and obs[itemID]
      if itemID and avail == 0 then
        -- sold out: not an offer; forget this vendor's earlier (now stale) record of it
        if type(old) == "table" and npc and old.npc == npc and old.name == npcName then obs[itemID] = nil; changed = true end
      elseif itemID then
        local bundle = (type(info.stackCount) == "number" and info.stackCount > 0) and info.stackCount or 1
        local limited = avail > 0
        local rec = { price = info.price / bundle, bundle = bundle, npc = npc, name = npcName, zone = zone, map = map,
                      x = x, y = y, limited = limited, stock = limited and avail or nil, faction = faction,
                      npcFaction = npcFaction, t = now }
        seen = seen + 1
        if Better(old, rec) then
          if not Same(old, rec) then changed = true end  -- same offer again: refresh silently
          obs[itemID] = rec
        end
      end
    end
  end
  if changed then
    cache = {}
    WC:Fire("VENDOR_UPDATED")
  end
  return seen
end

-- ---------------------------------------------------------------------------
-- WC:VendorPrice(itemID) -> unit price (copper per item), info { source = "seen"|"data", npc = name, npcID,
--   zone, x, y, map, bundle, limited, stock (items in stock when seen; nil = unlimited), classic, t }
--   or nil when no vendor sells it (for this faction).
-- Order: an unlimited offer the player has seen > WC.VENDOR (unlimited by definition) > a limited seen offer.
-- While the player's faction is still unknown (early login): seen offers are trusted, WC.VENDOR only through a
-- neutral NPC (never a guessed faction), and nothing is cached.
-- The returned info table is shared (cached): read it, don't change it.

local FACTION_CODE = { Alliance = "A", Horde = "H" }

-- NPC of a WC.VENDOR entry this character can use: the first neutral ("") one or one of the player's faction,
-- in list order. false if the list has NPCs but none we can use -- including "faction not known yet" when the
-- list has no neutral NPC.
local function PickNpc(npcs)
  if type(npcs) ~= "table" or #npcs == 0 then return nil end
  local code = FACTION_CODE[PlayerFaction() or ""]
  for i = 1, #npcs do
    local n = npcs[i]
    if type(n) == "table" then
      local f = n[6]
      if f == nil or f == "" or (code ~= nil and f == code) then return n end
    end
  end
  return false
end

local function SeenInfo(o)
  return { source = "seen", npc = o.name, npcID = o.npc, zone = o.zone, x = o.x, y = o.y, map = o.map,
           bundle = o.bundle or 1, limited = o.limited and true or false, stock = o.limited and o.stock or nil,
           classic = false, t = o.t }
end

local function Lookup(itemID)
  local db = DB()
  local o = db and db.vendorObs[itemID]
  if type(o) ~= "table" or type(o.price) ~= "number" or not Usable(o) then o = nil end
  if o and not o.limited then return o.price, SeenInfo(o) end
  local d = WC.VENDOR and WC.VENDOR[itemID]
  if type(d) == "table" and type(d.buy) == "number" and d.buy > 0 then
    local stack = (type(d.stack) == "number" and d.stack > 0) and d.stack or 1
    local npc = PickNpc(d.npcs)
    if npc ~= false then
      local classic = d.classic and true or false
      if npc and npc[7] then classic = true end      -- npc[7] = classicLocation (DataVendor.lua header)
      return d.buy / stack, { source = "data", npc = npc and npc[2] or nil, npcID = npc and npc[1] or nil,
        zone = npc and npc[3] or nil, x = npc and npc[4] or nil, y = npc and npc[5] or nil,
        bundle = stack, limited = false, classic = classic, seen = d.seen and true or false }
    end
  end
  if o then return o.price, SeenInfo(o) end
  return nil
end

function WC:VendorPrice(itemID)
  if type(itemID) ~= "number" then return nil end
  local c = cache[itemID]
  if c == nil then
    local price, info = Lookup(itemID)
    c = price and { price, info } or false
    if ready and PlayerFaction() then cache[itemID] = c end   -- don't keep answers made without a faction
  end
  if c then return c[1], c[2] end
  return nil
end

-- ---------------------------------------------------------------------------
-- events: MERCHANT_SHOW / MERCHANT_UPDATE (debounced; MERCHANT_UPDATE also fires after every purchase)

local frame = CreateFrame("Frame")
local token = 0
frame:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_CLOSED" then token = token + 1; return end
  token = token + 1
  local my = token
  C_Timer.After(event == "MERCHANT_SHOW" and 0.1 or 0.5, function()
    if my ~= token then return end
    local ok, err = pcall(Merchant.Scan, Merchant)
    if not ok and WC.Debug then WC.Debug("Merchant", err) end
  end)
end)
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
  pcall(frame.RegisterEvent, frame, e)
end

WC:On("DB_READY", function() ready = true; cache = {} end)
WC:On("VENDOR_UPDATED", function() cache = {} end)
