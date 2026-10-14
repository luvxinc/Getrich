"""Run the WaylaidCrate addon against a mocked WoW client + Auction House (LuaJIT via lupa)."""
import sys, os
from lupa import luajit21 as lj

ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'WaylaidCrate')
LOCALE = sys.argv[2] if len(sys.argv) > 2 else "enUS"
SCENARIO = sys.argv[3] if len(sys.argv) > 3 else "full"

lua = lj.LuaRuntime(unpack_returned_tuples=True)

MOCK = r'''
local LOCALE, SCENARIO = ...
CLOCK = 100
local timers = {}
local function schedule(delay, fn) local t = { at = CLOCK + delay, fn = fn, cancelled = false }; timers[#timers + 1] = t; return t end
function RUN(maxTime)
  local limit = CLOCK + maxTime
  local guard = 0
  while true do
    guard = guard + 1; if guard > 200000 then error('scheduler runaway at t=' .. CLOCK) end
    local nextT, idx = nil, nil
    for i, t in ipairs(timers) do if not t.cancelled and (not nextT or t.at < nextT.at) then nextT, idx = t, i end end
    if not nextT or nextT.at > limit then CLOCK = limit; return end
    table.remove(timers, idx)
    CLOCK = math.max(CLOCK, nextT.at)
    nextT.fn()
  end
end
C_Timer = {
  After = function(d, fn) schedule(d, fn) end,
  NewTimer = function(d, fn) local t = schedule(d, fn); return { Cancel = function() t.cancelled = true end } end,
}
function GetTime() return CLOCK end
function time() return 1791990000 + math.floor(CLOCK) end
function date(fmt, t) return os.date(fmt, t or time()) end
function GetLocale() return LOCALE end
PLAYER_LEVEL = 18
function UnitLevel() return PLAYER_LEVEL end
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT + 1] = m end }
SlashCmdList = {}
UISpecialFrames = {}
tinsert = table.insert
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Enum = { AuctionHouseSortOrder = { Price = 0 } }
C_Item = { GetItemNameByID = function(id) return nil end, RequestLoadItemDataByID = function() end }
C_AddOns = { GetAddOnMetadata = function(name, key) if key == "Version" then return "TEST" end end }
HAS_DIPLO = false
function IsPlayerSpell(id) return id == 20599 and HAS_DIPLO end
function UnitFactionGroup() return "Horde" end
STANDING = 5
C_Reputation = { GetFactionDataByID = function(id) if id == 2587 then return { name = "Durotar Supply and Logistics", reaction = STANDING } end end }
FACTION_STANDING_LABEL4 = "Neutral"; FACTION_STANDING_LABEL5 = "Friendly"

-- generic widget stub ------------------------------------------------------
local Stub
local function newStub(kind)
  local o = { _kind = kind, _scripts = {}, _shown = (kind ~= "toplevel"), _h = 20, _w = 600, _text = "", _checked = false, _scroll = 0 }
  return setmetatable(o, Stub)
end
Stub = { __index = function(t, k)
  local m = rawget(Stub, "_methods")[k]
  if m then return m end
  return function() return newStub("child") end
end }
Stub._methods = {
  SetScript = function(s, n, f) s._scripts[n] = f end,
  HookScript = function(s, n, f) local old = s._scripts[n]; s._scripts[n] = function(...) if old then old(...) end; f(...) end end,
  GetScript = function(s, n) return s._scripts[n] end,
  RegisterEvent = function(s, e) local ev = rawget(s, "_events") or {}; rawset(s, "_events", ev); ev[e] = true end,
  Show = function(s) s._shown = true; if s._scripts.OnShow then s._scripts.OnShow(s) end end,
  Hide = function(s) local was = s._shown; s._shown = false; if was and s._scripts.OnHide then s._scripts.OnHide(s) end end,
  SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
  IsShown = function(s) return s._shown end,
  SetText = function(s, t) s._text = t end,
  GetText = function(s) return s._text end,
  GetStringWidth = function(s) return #(s._text or "") * 5 end,
  SetHeight = function(s, h) s._h = h end,
  GetHeight = function(s) return s._h end,
  SetWidth = function(s, w) s._w = w end,
  GetWidth = function(s) return s._w end,
  SetSize = function(s, w, h) s._w, s._h = w, h end,
  SetChecked = function(s, v) s._checked = v and true or false end,
  GetChecked = function(s) return s._checked end,
  GetVerticalScroll = function(s) return s._scroll end,
  SetVerticalScroll = function(s, v) s._scroll = v end,
  CreateFontString = function(s) return newStub("font") end,
  CreateTexture = function(s) return newStub("tex") end,
  SetAlpha = function(s, a) s._alpha = a end,
}
FRAMES = {}
function CreateFrame(kind, name, parent, template)
  local f = newStub(kind)
  if kind == "Frame" and name == "WaylaidCrateFrame" then f._shown = false end
  FRAMES[#FRAMES + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = newStub("UIParent")
TT = {}
GameTooltip = setmetatable({
  SetOwner = function() TT = {} end,
  AddLine = function(_, t) TT[#TT + 1] = t end,
  AddDoubleLine = function(_, a, b) TT[#TT + 1] = a .. " || " .. b end,
  Show = function() end,
}, { __index = function() return function() end end })
GameTooltip_Hide = function() end
AuctionHouseFrame = newStub("AH")
AuctionHouseFrameDisplayMode = { Buy = { "buy" }, ItemBuy = { "ib" }, CommoditiesBuy = { "cb" }, ItemSell = { "is" } }
AH_MODE = AuctionHouseFrameDisplayMode.ItemSell
AuctionHouseFrame.GetDisplayMode = function() return AH_MODE end
AuctionHouseFrame.SetDisplayMode = function(_, m) AH_MODE = m end
SEARCHES = 0
AuctionHouseFrame.SearchBar = { SetSearchText = function(_, t) SEARCH_TEXT = t end, StartSearch = function() SEARCHES = SEARCHES + 1 end }

-- mock auction house ------------------------------------------------------
-- order book per item: list of {unitPrice, quantity}; crates are non-commodity items.
BOOK = {}
NO_EVENT = {}      -- items whose search never answers (simulates a dropped query)
FLAKY, FLAKED, LOADED = {}, {}, {}
SENT = {}
local CRATE_IDS = {}
function SETUP_BOOK(WC)
  for _, c in ipairs(WC.CRATES) do CRATE_IDS[c.id] = true end
  -- default: every material listed at 50c..5s with plenty of stock
  local seed = 7
  local function rnd(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end
  for id in pairs(WC.ITEMS) do BOOK[id] = { { rnd(50, 500), 200 }, { rnd(600, 900), 500 } } end
  for _, c in ipairs(WC.CRATES) do BOOK[c.id] = { { rnd(5000, 30000), 1 }, { 40000, 1 } } end
end
local current = { commodity = {}, item = {} }
C_AuctionHouse = {
  MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
  IsThrottledMessageSystemReady = function() return true end,
  -- item key info is 'uncached' for the first 0.5s after it is first requested
  GetItemKeyInfo = function(key)
    KEYREQ = KEYREQ or {}
    if not KEYREQ[key.itemID] then KEYREQ[key.itemID] = CLOCK end
    if CLOCK - KEYREQ[key.itemID] < 0.5 then return nil end
    return { itemID = key.itemID }
  end,
  HasSearchResults = function(key) return LOADED[key.itemID] ~= false end,
  HasFullCommoditySearchResults = function(id) return true end,
  HasFullItemSearchResults = function(key) return true end,
  SendSearchQuery = function(key, sorts, sep)
    SENT[#SENT + 1] = { id = key.itemID, t = CLOCK, keyAge = CLOCK - ((KEYREQ or {})[key.itemID] or CLOCK) }
    local id = key.itemID
    -- FLAKY items answer 'not loaded' the first time
    if FLAKY[id] and not FLAKED[id] then FLAKED[id] = true; LOADED[id] = false else LOADED[id] = true end
    if NO_EVENT[id] then return end
    C_Timer.After(0.2, function()
      if CRATE_IDS[id] then
        current.item[id] = BOOK[id] or {}
        FIRE("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id })
      else
        current.commodity[id] = BOOK[id] or {}
        FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", id)
      end
    end)
  end,
  GetCommoditySearchResultsQuantity = function(id) return #(current.commodity[id] or {}) end,
  GetCommoditySearchResultInfo = function(id, i)
    local e = current.commodity[id][i]; if not e then return nil end
    return { itemID = id, unitPrice = e[1], quantity = e[2], auctionID = i }
  end,
  GetItemSearchResultsQuantity = function(key) return #(current.item[key.itemID] or {}) end,
  GetItemSearchResultInfo = function(key, i)
    local e = current.item[key.itemID][i]; if not e then return nil end
    return { itemKey = key, quantity = e[2], buyoutAmount = e[1], auctionID = i, owners = {} }
  end,
}
function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do
    local ev = rawget(f, "_events"); if ev and ev[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
'''

lua.execute("MOCKSRC = ...", None)
mock_fn = lua.eval("function(src) return loadstring(src) end")(MOCK)
mock_fn(LOCALE, SCENARIO)

WC = lua.table()
loader = lua.eval("function(src, name, ns) local f, err = loadstring(src, '@' .. name); if not f then error(err) end; return f('WaylaidCrate', ns) end")
for line in open(os.path.join(ADDON, "WaylaidCrate.toc"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        loader(open(os.path.join(ADDON, line), encoding="utf-8").read(), line, WC)
print(f"[{LOCALE}/{SCENARIO}] loaded files OK")

g = lua.globals()
g.SETUP_BOOK(WC)
run = lua.eval("RUN")
fire = lua.eval("FIRE")

fire("ADDON_LOADED", "WaylaidCrate")
fire("PLAYER_LOGIN")

# scenario tweaks (set before scanning)
lua.eval('loadstring')(r'''
local WC = ...
-- Apprentice Textiles: Linen Cloth only 30 listed (crate needs 40) -> must fall back to Light Leather
BOOK[2589] = { { 10, 30 } }
BOOK[2318] = { { 400, 10 }, { 900, 50 } }       -- 20 Light Leather = 10*400 + 10*900 = 13000
-- Apprentice Ore: no crate for sale
BOOK[248683] = {}
-- Apprentice Herbs: all five herbs sold out
for _, id in ipairs({ 2447, 765, 2449, 785, 2450 }) do BOOK[id] = {} end
-- Expert Parts: make it the clear winner
BOOK[248710] = { { 100, 1 } }
BOOK[10559] = { { 1, 100 } }
-- one query that never answers (timeout path): Tin Ore
NO_EVENT[2771] = true
-- Silk Cloth and the Expert Ore crate answer 'not loaded' first, must be retried
FLAKY[4306] = true
FLAKY[248692] = true
''')(WC) if SCENARIO in ("full", "close") else None

fire("AUCTION_HOUSE_SHOW")
if SCENARIO == "close":
    run(12)
    fire("AUCTION_HOUSE_CLOSED")
    sc = WC.Scanner
    print("after close: active =", sc.active, "| bar:", WC.UI.barText._text)
    print("frame shown:", WC.UI.frame._shown)
    sys.exit(0)

run(400)
sc = WC.Scanner
sent = lua.eval("SENT")
n_sent = len(sent)
times = sorted(sent[i].t for i in range(1, n_sent + 1))
min_gap = min(b - a for a, b in zip(times, times[1:]))
print(f"scan active={sc.active} total={sc.total} queries sent={n_sent} min gap={min_gap:.2f}s duration={times[-1]-times[0]:.1f}s")
print("progress bar:", WC.UI.barText._text, "| value set via SetValue")
chat = lua.eval("CHAT")
print("chat:", [chat[i] for i in range(1, len(chat) + 1)])

R = sc.results
def res(i):
    r = R[i]
    return None if r is None else dict(status=r.status, cost=r.cost, min=r.min, avail=r.avail)
print("Linen (need 40, 30 listed):", res(2589))
print("Light Leather (need 20):", res(2318))
print("Tin Ore (no answer):", res(2771))
print("Silk Cloth (flaky first answer):", res(4306))
print("Expert Ore crate (flaky first answer):", res(248692))
assert res(4306)["status"] == "ok" and res(248692)["status"] == "ok"
ages = [sent[i].keyAge for i in range(1, n_sent + 1)]
early = [a for a in ages if a < 0.5]
print("searches sent before item key was cached:", len(early))
assert not early
silk = [sent[i] for i in range(1, n_sent + 1) if sent[i].id == 4306]
print("Silk Cloth searches:", len(silk))

ev = lua.eval("function(WC) return WC:Evaluate() end")(WC)
rows = []
for i in range(1, len(ev) + 1):
    e = ev[i]
    best = e.opts[e.bestIdx].itemID if e.bestIdx else None
    rows.append((e.crate.en, e.status, e.crateCost, e.matCost, best, e.perFavor, e.locked))
for r in rows[:4]:
    print("  ", r)
by = {r[0]: r for r in rows}
assert by["Apprentice Textiles"][4] == 2318 and by["Apprentice Textiles"][3] == 13000, by["Apprentice Textiles"]
assert by["Apprentice Ore"][1] == "nocrate", by["Apprentice Ore"]
assert by["Apprentice Herbs"][1] == "nomats", by["Apprentice Herbs"]
assert rows[0][0] == "Expert Parts", rows[0]
assert by["Expert Parts"][6] is True   # player level 18 < 20
# verify each ok crate's best = min over fully-buyable options, independently
for i in range(1, len(ev) + 1):
    e = ev[i]
    costs = [e.opts[j].cost for j in range(1, len(e.opts) + 1) if e.opts[j].cost is not None]
    if costs:
        assert abs(min(costs) - e.matCost) < 1e-9
    if e.perFavor is not None:
        exp = max(e.crateCost + e.matCost - e.crate.silver, 0) / e.crate.favor
        assert abs(exp - e.perFavor) < 1e-9
print("evaluation checks passed")

vis_fn = lua.eval("function(WC) return WC:Visible(WC:Evaluate()) end")
def visible_names():
    v = vis_fn(WC); return [v[i].crate.en for i in range(1, len(v) + 1)]
v_default = visible_names()
print("visible (default filters):", len(v_default), "hidden Ore/Herbs:", "Apprentice Ore" not in v_default, "Apprentice Herbs" not in v_default)
assert "Apprentice Ore" not in v_default and "Apprentice Herbs" not in v_default
db = lua.eval("WaylaidCrateDB")
db.hideNoCrate = False; db.hideNoMats = False
v_all = visible_names(); print("visible (filters off):", len(v_all))
assert len(v_all) == 22
db.onlyMine = True
v_mine = visible_names(); print("visible (only mine, level 18):", len(v_mine))
assert all(not n.startswith("Expert") and "Expert" not in n for n in v_mine)
db.onlyMine = False; db.hideNoCrate = True; db.hideNoMats = True

WC.UI.Refresh(WC.UI)
best = WC.UI.best
print("best panel:", best.name._text, "|", best.detail._text, "|", best.per._text, "|", best.net._text)
row1 = WC.UI.rows[1]
print("row1:", row1.rank._text, row1.name._text, "|", row1.fill._text, "|", row1.fillSub._text, "|", row1.price._text, row1.mats._text, row1.rep._text, row1.per._text)
WC.UI.ShowTooltip(WC.UI, row1, row1.entry)
tt = lua.eval("TT")
print("tooltip:"); [print("   ", tt[i]) for i in range(1, len(tt) + 1)]
# tooltip for Apprentice Textiles (shows 'not enough' for linen)
for i in range(1, 23):
    r = WC.UI.rows[i]
    if r.entry and r.entry.crate.en == "Apprentice Textiles":
        WC.UI.ShowTooltip(WC.UI, r, r.entry); tt = lua.eval("TT")
        print("textiles tooltip:"); [print("   ", tt[k]) for k in range(1, len(tt) + 1)]
        break
print("hidden label:", WC.UI.hiddenText._text)

# ---- click to search ----
g = lua.globals()
row1 = WC.UI.rows[1]
row1.crateBtn._scripts.OnClick()
isBuy = lua.eval("function() return AH_MODE == AuctionHouseFrameDisplayMode.Buy end")
isCB = lua.eval("function() return AH_MODE == AuctionHouseFrameDisplayMode.CommoditiesBuy end")
print("click crate ->", g.SEARCH_TEXT, "| switched Sell -> Buy:", isBuy(), "| searches:", g.SEARCHES)
assert isBuy()
if LOCALE == "enUS": assert g.SEARCH_TEXT == "Waylaid Crate: Expert Parts"
row1.matBtn._scripts.OnClick()
print("click material ->", g.SEARCH_TEXT)
if LOCALE == "enUS": assert g.SEARCH_TEXT == "Mithril Tube"
lua.execute("AH_MODE = AuctionHouseFrameDisplayMode.CommoditiesBuy")
WC.UI.best.crateBtn._scripts.OnClick()
print("best panel crate ->", g.SEARCH_TEXT, "| stays in CommoditiesBuy:", isCB())
assert isCB()
WC.UI.best.matBtn._scripts.OnClick()
print("best panel material ->", g.SEARCH_TEXT, "| searches:", g.SEARCHES)
assert g.SEARCHES == 4
# material hotspot hidden on a row without a recommendation
db = lua.eval("WaylaidCrateDB"); db.hideNoMats = False; db.hideNoCrate = False
WC.UI.Refresh(WC.UI)
for i in range(1, 23):
    r = WC.UI.rows[i]
    if r.entry and r.entry.crate.en == "Apprentice Herbs":
        print("Apprentice Herbs (no materials) material hotspot shown:", r.matBtn._shown); assert r.matBtn._shown is False
# tooltip hint
r = WC.UI.rows[1]; r.matBtn._scripts.OnEnter(r.matBtn); tt = lua.eval("TT"); print("hover hint:", tt[len(tt)])
# failure path: no search bar
AH = g.AuctionHouseFrame; AH.SearchBar = None
WC.UI.rows[1].crateBtn._scripts.OnClick()
chat = lua.eval("CHAT"); print("failure message:", chat[len(chat)])

# ---- reputation / bonuses ----
from math import fabs
AH.SearchBar = lua.eval("{ SetSearchText = function(_, t) SEARCH_TEXT = t end, StartSearch = function() end }")
db = lua.eval("WaylaidCrateDB"); db.hideNoMats = True; db.hideNoCrate = True
ev = lua.eval("function(WC) return WC:Evaluate() end")
first = ev(WC)[1]
print("favor mode, no bonus: favorExp =", first.favorExp, "repFill =", first.repFill, "repGain =", first.repGain)
assert first.repFill == 0 and first.repGain == 50
db.perfRank = 3; db.diplomatRank = 5
e1 = ev(WC)[1]
print("perf 3/3 + diplomat 5/5: favorExp =", e1.favorExp, "(base", e1.crate.favor, ") repGain =", e1.repGain)
assert fabs(e1.favorExp - e1.crate.favor * 1.15) < 1e-9 and fabs(e1.repGain - 55) < 1e-9
lua.execute("HAS_DIPLO = true")
e1 = ev(WC)[1]; print("with racial Diplomacy detected: repGain =", e1.repGain); assert fabs(e1.repGain - 60) < 1e-9
lua.execute("HAS_DIPLO = false")

db.mode = "rep"
lst = ev(WC)
best_per_favor = lua.eval("function(WC) return WC.bestPerFavor end")(WC)
rows = [(lst[i].crate.en, lst[i].crateCost, lst[i].receiptGold, lst[i].perRep) for i in range(1, len(lst) + 1)]
print("best per-Favor (unlocked crates):", best_per_favor)
print("rep mode top 3:", rows[:3])
priced = [(r[0], (r[1] + 15 * best_per_favor) / 55) for r in rows if r[1] is not None]
priced.sort(key=lambda t: t[1])
assert [p[0] for p in priced[:5]] == [r[0] for r in rows[:5]], (priced[:5], rows[:5])
assert fabs(rows[0][3] - priced[0][1]) < 1e-9
vis = lua.eval("function(WC) return WC:Visible(WC:Evaluate()) end")(WC)
names = [vis[i].crate.en for i in range(1, len(vis) + 1)]
print("rep mode visible:", len(names), "| Apprentice Herbs (no materials) shown:", "Apprentice Herbs" in names, "| Apprentice Ore (no crate) shown:", "Apprentice Ore" in names)
assert "Apprentice Herbs" in names and "Apprentice Ore" not in names
WC.UI.Refresh(WC.UI)
b = WC.UI.best
print("rep best panel:", b.label._text, "|", b.name._text, "|", b.detail._text, "|", b.perLabel._text, b.per._text, "|", b.net._text)
r1 = WC.UI.rows[1]
print("rep row1:", r1.rank._text, r1.name._text, "|", r1.fill._text, "|", r1.fillSub._text, "|", r1.price._text, "|", r1.mats._text, "|", r1.rep._text, "|", r1.per._text, "| matBtn shown:", r1.matBtn._shown)
print("headers:", WC.UI.hFill._text, "/", WC.UI.hMats._text, "/", WC.UI.hPer._text, "| race:", WC.UI.raceText._text, "| cyclers:", WC.UI.cyclers.perfRank._text, WC.UI.cyclers.diplomatRank._text)
r1.crateBtn._scripts.OnEnter(r1.crateBtn); tt = lua.eval("TT")
print("rep tooltip:"); [print("   ", tt[i]) for i in range(1, len(tt) + 1)]
WC.UI.cyclers.diplomatRank._scripts.OnClick(WC.UI.cyclers.diplomatRank, "LeftButton")
print("diplomat after left-click from 5:", db.diplomatRank); assert db.diplomatRank == 0
WC.UI.cyclers.diplomatRank._scripts.OnClick(WC.UI.cyclers.diplomatRank, "RightButton")
print("diplomat after right-click from 0:", db.diplomatRank); assert db.diplomatRank == 5
WC.UI.modeButtons.favor._scripts.OnClick()
print("favor mode again:", db.mode, "| row1 rep column:", WC.UI.rows[1].rep._text, "| per:", WC.UI.rows[1].per._text, "| sub:", WC.UI.rows[1].sub._text)
lua.execute("STANDING = 4")
db.mode = "rep"; WC.UI.Refresh(WC.UI); print("standing Neutral ->", WC.UI.best.net._text)
print("version label:", lua.eval("function(WC) return WC.VERSION end")(WC))
print("ALL REP CHECKS PASSED")
