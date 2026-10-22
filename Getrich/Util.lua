local addonName, WC = ...

-- Shared plumbing, loaded first. Keep this file small.

-- ---------------------------------------------------------------------------
-- internal message bus (no Blizzard events): WC:On("PRICES_UPDATED", fn) / WC:Fire("PRICES_UPDATED", ...)
-- Messages used across modules (see SPEC.md):
--   DB_READY            Store:Init() finished (SavedVariables loaded, defaults applied)
--   PRICES_UPDATED      new AH data was recorded (args: kind)
--   RECIPES_UPDATED     recipes or profession skills changed (args: charKey)
--   VENDOR_UPDATED      a merchant window was read
--   DE_UPDATED          a disenchant sample was recorded
--   BAGS_UPDATED        bag contents changed (debounced)
--   SETTINGS_CHANGED    a UI switch changed
local listeners = {}

function WC:On(msg, fn)
  local list = listeners[msg]
  if not list then list = {}; listeners[msg] = list end
  list[#list + 1] = fn
end

function WC:Fire(msg, ...)
  local list = listeners[msg]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and WC.Debug then WC.Debug(msg, err) end
  end
end

-- ---------------------------------------------------------------------------
-- localization: every module adds its own strings with
--   WC.AddLocale({ enUS = {...}, zhCN = {...}, zhTW = {...} })
-- English is the fallback for any key missing in the client's language.
WC.L = WC.L or {}
local LOCALE = (GetLocale and GetLocale()) or "enUS"
WC.LOCALE = LOCALE

function WC.AddLocale(t)
  local L = WC.L
  for k, v in pairs(t.enUS or {}) do
    if L[k] == nil then L[k] = v end
  end
  local mine = t[LOCALE]
  if mine then
    for k, v in pairs(mine) do L[k] = v end
  end
end

-- ---------------------------------------------------------------------------
-- small helpers

-- the current character, used as the key for per-character data
function WC:CharKey()
  return (UnitGUID and UnitGUID("player")) or ((UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?"))
end

-- C_Item.GetItemInfo, safely. Returns the same 18 values (nil until the item is cached).
-- 1 name, 2 link, 3 quality, 4 itemLevel, 5 minLevel, 6 type, 7 subType, 8 stackCount,
-- 9 equipLoc, 10 texture, 11 sellPrice, 12 classID, 13 subclassID, 14 bindType, ...
function WC.ItemInfo(itemID)
  if not itemID then return nil end
  local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
  if not fn then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, itemID)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h, i, j, k, l, m, n
end

-- vendor sell price (copper per item); nil if the item isn't cached yet, 0 if vendors don't buy it
function WC.SellPrice(itemID)
  local name, _, _, _, _, _, _, _, _, _, sell = WC.ItemInfo(itemID)
  if not name then return nil end
  return sell or 0
end

function WC.RequestItem(itemID)
  if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

-- items currently in the bags (bank not included)
function WC.BagCount(itemID)
  local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
  if not fn then return 0 end
  local ok, n = pcall(fn, itemID, false)
  return (ok and n) or 0
end

-- the Auction House takes 5% of the sale price
WC.AH_CUT = 0.05

-- Errors caught by pcall in event handlers are not thrown away: each distinct one is passed to the
-- game's error handler once (BugSack / "Display Lua errors") and kept for `/gr errors`.
WC.errors = WC.errors or {}
local seenErrors = {}
function WC.Debug(where, err)
  if WC.UI and WC.UI.Report then
    WC.UI.Report(where, err)
    return
  end
  local msg = tostring(where) .. ": " .. tostring(err)
  if seenErrors[msg] then return end
  seenErrors[msg] = true
  if #WC.errors < 50 then WC.errors[#WC.errors + 1] = msg end
  local handler = geterrorhandler and geterrorhandler()
  if handler then pcall(handler, "Getrich " .. msg) end
end
