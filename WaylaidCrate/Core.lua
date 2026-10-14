local addonName, WC = ...

WC.ahOpen = false

-- version comes from the TOC so it is set in one place
do
  local ok, v = pcall(function()
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(addonName, "Version") end
    if GetAddOnMetadata then return GetAddOnMetadata(addonName, "Version") end
  end)
  WC.VERSION = ok and v or nil
end

local DEFAULTS = {
  autoScan = true,        -- scan when the Auction House opens
  onlyMine = false,       -- only crates my level can open
  hideNoCrate = true,     -- ignore crates that nobody is selling
  hideNoMats = true,      -- ignore crates whose materials are all out of stock
  mode = "favor",         -- "favor" = Merchant's Favor first, "rep" = reputation first
  perfRank = 0,           -- Legacy Performance Bonus rank (0-3)
  diplomatRank = 0,       -- Legacy Diplomat rank (0-5)
}

function WC:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Waylaid Crate|r: " .. tostring(msg))
end

-- Item names come from the game client, so they are in the player's language.
-- Until the client has cached an item, fall back to the built-in English / Chinese name.
local function ClientName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local name = C_Item.GetItemNameByID(itemID)
    if name and name ~= "" then return name end
  end
end

function WC:ItemName(itemID)
  local name = ClientName(itemID)
  if name then return name end
  local d = WC.ITEMS[itemID]
  if not d then return "item:" .. itemID end
  return WC.USE_CN_FALLBACK and d[2] or d[1]
end

-- Crate name without the "Waylaid Crate:" prefix.
function WC:CrateShortName(crate)
  local name = ClientName(crate.id)
  if not name then return WC.USE_CN_FALLBACK and crate.cn or crate.en end
  local p = name:find(": ", 1, true)
  if p then return name:sub(p + 2) end
  p = name:find("：", 1, true)
  if p then return name:sub(p + 3) end
  return name
end

function WC:SaveResults()
  if not WaylaidCrateDB then return end
  WaylaidCrateDB.results = WC.Scanner.results
  WaylaidCrateDB.scannedAt = time()
end

-- ---------------------------------------------------------------------------
-- bonuses

function WC:DB() return WaylaidCrateDB or DEFAULTS end
function WC:Mode() return WC:DB().mode == "rep" and "rep" or "favor" end

-- Human "Diplomacy" (+10% reputation): not in Forever's racial list, but check the spell anyway.
function WC:HasDiplomacy()
  local ok, known = pcall(function()
    if IsPlayerSpell then return IsPlayerSpell(WC.DIPLOMACY_SPELL) end
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(WC.DIPLOMACY_SPELL) end
    return false
  end)
  return (ok and known) and true or false
end

-- reputation bonus as a fraction: Legacy Diplomat 2% per rank (+ racial if present)
function WC:RepBonus()
  local b = 0.02 * (tonumber(WC:DB().diplomatRank) or 0)
  if WC:HasDiplomacy() then b = b + 0.10 end
  return b
end

-- expected Merchant's Favor bonus: Legacy Performance Bonus 5% chance per rank of +100%
function WC:FavorBonus()
  return 0.05 * (tonumber(WC:DB().perfRank) or 0)
end

-- current standing with the crate faction, if the client exposes it
function WC:Standing()
  local id = WC.FACTION_IDS[UnitFactionGroup and UnitFactionGroup("player") or ""]
  if not id then return nil end
  local ok, name, reaction = pcall(function()
    if C_Reputation and C_Reputation.GetFactionDataByID then
      local d = C_Reputation.GetFactionDataByID(id)
      if d then return d.name, d.reaction end
    elseif GetFactionInfoByID then
      local n, _, standingID = GetFactionInfoByID(id)
      return n, standingID
    end
  end)
  if ok and name and reaction then return name, reaction end
  return nil
end

-- ---------------------------------------------------------------------------
-- evaluation

-- Evaluate every crate from the latest scan.
-- Favor: the cheapest material bundle the AH can fully supply is picked automatically.
-- Reputation: a filled crate gives 0; an empty crate + receipt (15 Favor) gives +50 after Friendly.
function WC:Evaluate()
  local R = WC.Scanner.results or {}
  local level = UnitLevel("player") or 0
  local favorMult = 1 + WC:FavorBonus()
  local repMult = 1 + WC:RepBonus()
  local mode = WC:Mode()
  local list = {}
  for _, crate in ipairs(WC.CRATES) do
    local e = { crate = crate, opts = {}, locked = level < crate.lvl }
    local cr = R[crate.id]
    e.crateRes = cr
    e.crateCost = (cr and cr.status == "ok") and cr.cost or nil
    e.favorExp = crate.favor * favorMult
    e.repFill = WC.REP.fill * repMult          -- always 0
    e.repGain = WC.REP.empty * repMult         -- empty crate + receipt
    local scannedAny = cr ~= nil
    local anyListed = false
    for j, opt in ipairs(crate.opts) do
      local r = R[opt[1]]
      if r then scannedAny = true; e.matsScanned = true end
      if r and (r.status == "ok" or r.status == "short") then anyListed = true end
      local cost = (r and r.status == "ok") and r.cost or nil
      e.opts[j] = { itemID = opt[1], qty = opt[2], note = opt[3], res = r, cost = cost }
      if cost and (not e.matCost or cost < e.matCost) then
        e.matCost = cost
        e.bestIdx = j
      end
    end
    if e.crateCost and e.matCost then
      e.net = e.crateCost + e.matCost - crate.silver
      e.perFavor = math.max(e.net, 0) / e.favorExp
      e.favorPerGold = e.net > 0 and e.favorExp / (e.net / 10000) or nil
      e.status = "ok"
    elseif not scannedAny then
      e.status = "unscanned"
    elseif not e.crateCost then
      e.status = "nocrate"
    elseif anyListed then
      e.status = "short"     -- materials listed, but not enough of any bundle
    else
      e.status = "nomats"
    end
    list[#list + 1] = e
  end

  -- The receipt costs 15 Favor; value it at the cheapest Favor you can make (crates you can open).
  local bestPerFavor, bestAny
  for _, e in ipairs(list) do
    if e.perFavor then
      if not bestAny or e.perFavor < bestAny then bestAny = e.perFavor end
      if not e.locked and (not bestPerFavor or e.perFavor < bestPerFavor) then bestPerFavor = e.perFavor end
    end
  end
  bestPerFavor = bestPerFavor or bestAny
  WC.bestPerFavor = bestPerFavor
  for _, e in ipairs(list) do
    e.receiptGold = bestPerFavor and WC.REP.receiptFavor * bestPerFavor or nil
    if e.crateCost then
      e.repCost = e.crateCost + (e.receiptGold or 0)
      e.perRep = e.repCost / e.repGain
    end
    e.score = (mode == "rep") and e.perRep or e.perFavor
  end

  table.sort(list, function(a, b)
    if a.score and b.score then
      if a.score ~= b.score then return a.score < b.score end
      return a.crate.id < b.crate.id
    end
    if a.score then return true end
    if b.score then return false end
    if a.crate.tier ~= b.crate.tier then return a.crate.tier < b.crate.tier end
    return a.crate.id < b.crate.id
  end)
  return list
end

-- Apply the filter switches.
function WC:Visible(list)
  local db = WC:DB()
  local repMode = WC:Mode() == "rep"
  local out, rank = {}, 0
  for _, e in ipairs(list) do
    local show = true
    if db.onlyMine and e.locked then show = false end
    -- crate was scanned but nobody sells it
    if db.hideNoCrate and e.crateRes and not e.crateCost then show = false end
    -- materials were scanned but no bundle can be fully bought (materials don't matter for reputation)
    if not repMode and db.hideNoMats and e.matsScanned and not e.matCost then show = false end
    if show then
      if e.score then rank = rank + 1; e.rank = rank else e.rank = nil end
      out[#out + 1] = e
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- events

local frame = CreateFrame("Frame")

local function SafeRegister(event)
  pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")
SafeRegister("AUCTION_HOUSE_SHOW")
SafeRegister("AUCTION_HOUSE_CLOSED")
SafeRegister("COMMODITY_SEARCH_RESULTS_UPDATED")
SafeRegister("ITEM_SEARCH_RESULTS_UPDATED")
SafeRegister("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
SafeRegister("PLAYER_LEVEL_UP")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    WaylaidCrateDB = WaylaidCrateDB or {}
    for k, v in pairs(DEFAULTS) do
      if WaylaidCrateDB[k] == nil then WaylaidCrateDB[k] = v end
    end
    if type(WaylaidCrateDB.results) == "table" then
      WC.Scanner.results = WaylaidCrateDB.results
    end
  elseif event == "PLAYER_LOGIN" then
    -- warm the item cache so names show in the client's language
    if C_Item and C_Item.RequestLoadItemDataByID then
      for itemID in pairs(WC.ITEMS) do pcall(C_Item.RequestLoadItemDataByID, itemID) end
      for _, c in ipairs(WC.CRATES) do pcall(C_Item.RequestLoadItemDataByID, c.id) end
    end
    WC.UI:Create()
  elseif event == "AUCTION_HOUSE_SHOW" then
    WC.ahOpen = true
    WC.UI:ShowAtAuctionHouse()
    if WaylaidCrateDB and WaylaidCrateDB.autoScan then
      C_Timer.After(1.0, function()
        if WC.ahOpen and not WC.Scanner.active then WC.Scanner:Start() end
      end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    WC.ahOpen = false
    WC.Scanner:Stop(WC.L.STOP_AH_CLOSED)
    WC.UI:OnAuctionHouseClosed()
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    WC.Scanner:OnCommodityResults(...)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    WC.Scanner:OnItemResults(...)
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    WC.Scanner:OnMessageDropped()
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(0.5, function() WC.UI:Refresh() end)
  end
end)

-- ---------------------------------------------------------------------------
-- slash commands: /wc  /waylaid

SLASH_WAYLAIDCRATE1 = "/wc"
SLASH_WAYLAIDCRATE2 = "/waylaid"
SlashCmdList.WAYLAIDCRATE = function(msg)
  msg = strtrim(string.lower(msg or ""))
  if msg == "scan" then
    WC.UI:Show()
    WC.Scanner:Start()
  elseif msg == "stop" then
    WC.Scanner:Stop(WC.L.STOP_MANUAL)
  else
    WC.UI:Toggle()
  end
end
