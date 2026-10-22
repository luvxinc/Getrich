"""Run the WaylaidCrate addon against a mocked WoW client + Auction House (LuaJIT via lupa).

usage: python3 tests/mock_test.py [ADDON_DIR] [LOCALE] [SCENARIO]
  LOCALE   enUS | zhCN | zhTW        (default enUS)
  SCENARIO full | close             (default full)
needs: pip install lupa
"""
import sys, os
from math import fabs
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
TICKERS = 0        -- tickers currently running (must be 0 while idle)
C_Timer = {
  After = function(d, fn) schedule(d, fn) end,
  NewTimer = function(d, fn) local t = schedule(d, fn); return { Cancel = function() t.cancelled = true end } end,
  NewTicker = function(d, fn)
    local h = { dead = false }
    TICKERS = TICKERS + 1
    local function loop() if h.dead then return end; fn(h); if not h.dead then h.t = schedule(d, loop) end end
    h.t = schedule(d, loop)
    h.Cancel = function() if not h.dead then h.dead = true; TICKERS = TICKERS - 1; h.t.cancelled = true end end
    return h
  end,
}
function GetTime() return CLOCK end
function time() return 1791990000 + math.floor(CLOCK) end
function GetServerTime() return time() end
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
ITEM_PATH = {}     -- non-commodity items (crates, writs); everything else is a commodity
DONE = {}          -- quest IDs turned in today
C_QuestLog = { IsQuestFlaggedCompleted = function(q) return DONE[q] == true end }
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
      if ITEM_PATH[id] then
        current.item[id] = BOOK[id] or {}
        FIRE("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id })
      else
        current.commodity[id] = BOOK[id] or {}
        FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", id)
      end
    end)
  end,
  -- number of result rows (used by the 2026.10 Scanner; each BOOK entry is one row {unitPrice, quantity})
  GetNumCommoditySearchResults = function(id) return #(current.commodity[id] or {}) end,
  GetNumItemSearchResults = function(key) return #(current.item[key.itemID] or {}) end,
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

lua.eval("function(src) return loadstring(src) end")(MOCK)(LOCALE, SCENARIO)

WC = lua.table()
loader = lua.eval("function(src, name, ns) local f, err = loadstring(src, '@' .. name); if not f then error(err) end; return f('WaylaidCrate', ns) end")
for line in open(os.path.join(ADDON, "WaylaidCrate.toc"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        path = os.path.join(ADDON, line)
        if not os.path.exists(path):
            print(f"  (skipping {line}: not written yet)")   # modules are written in parallel
            continue
        loader(open(path, encoding="utf-8").read(), line, WC)
print(f"[{LOCALE}/{SCENARIO}] loaded files OK")

g = lua.globals()
run = lua.eval("RUN")
fire = lua.eval("FIRE")
L = lua.eval("function(src) return loadstring(src) end")
def lx(src, *args): return L(src)(*args)

fire("ADDON_LOADED", "WaylaidCrate")
fire("PLAYER_LOGIN")
UI = WC.UI
db = lua.eval("WaylaidCrateDB")
CRATE_TAB = UI.tabs.crates
WRIT_TAB = UI.tabs.writs

# ---------------------------------------------------------------- order books
lx(r"""
local WC = ...
local seed = 7
local function rnd(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end
for _, c in ipairs(WC.CRATES) do
  ITEM_PATH[c.id] = true
  BOOK[c.id] = { { rnd(5000, 30000), 1 }, { 40000, 1 } }
  for _, o in ipairs(c.opts) do BOOK[o[1]] = { { rnd(50, 500), 200 }, { rnd(600, 900), 500 } } end
end
for _, w in ipairs(WC.WRITS) do ITEM_PATH[w.writ] = true; BOOK[w.writ] = {} end
-- crate scenarios (same as before)
BOOK[2589] = { { 10, 30 } }                       -- Linen: only 30 (needs 40)
BOOK[2318] = { { 400, 10 }, { 900, 50 } }         -- 20 Light Leather = 13000
BOOK[248683] = {}                                 -- Apprentice Ore crate not for sale
for _, id in ipairs({ 2447, 765, 2449, 785, 2450 }) do BOOK[id] = {} end   -- herbs sold out
BOOK[248710] = { { 100, 1 } }                     -- Expert Parts crate: 1c
BOOK[10559] = { { 1, 100 } }                      -- Mithril Tube
NO_EVENT[2771] = true                             -- Tin Ore never answers
FLAKY[4306] = true                                -- Silk Cloth answers 'not loaded' first
-- writ scenarios: 8 writs listed
WRITS_LISTED = {
  [264072] = { writ = 5000,  item = 20000 },   -- Blue Glittering Axe (125)
  [264082] = { writ = 3000,  item = 9000 },    -- Craftsman's Monocle (125)
  [264037] = { writ = 2000,  item = 5 },       -- Crafted Solid Shot x200 (75)
  [264013] = { writ = 1500,  item = 300 },     -- Lesser Mana Potion (75)
  [264124] = { writ = 9000,  item = 40000 },   -- Distilled Firewater (200)
  [264047] = { writ = 1000,  item = nil },     -- Lesser Wizard's Robe: item not for sale
  [264085] = { writ = 4000,  item = 2500 },    -- Unstable Trigger (125) - also a crate material
  [264153] = { writ = 20000, item = 30000 },   -- Runecloth Bag (200)
}
for _, w in ipairs(WC.WRITS) do
  local s = WRITS_LISTED[w.writ]
  if s then
    BOOK[w.writ] = { { s.writ, 1 }, { s.writ * 2, 1 } }
    if s.item then BOOK[w.item] = { { s.item, 150 }, { s.item * 3, 300 } } else BOOK[w.item] = {} end
  elseif w.item ~= 10560 then
    BOOK[w.item] = { { 777, 5 } }               -- listed, but should not even be scanned in phase 2
  end
end
DONE[94213] = true                                 -- Lesser Mana Potion writ done today
""", WC)

# ---------------------------------------------------------------- crates tab
fire("AUCTION_HOUSE_SHOW")
if SCENARIO == "close":
    run(12)
    fire("AUCTION_HOUSE_CLOSED")
    print("after close: scanning =", WC.Scanner.active, "| bar:", UI.barText._text, "| frame shown:", UI.frame._shown)
    assert not WC.Scanner.active and not UI.frame._shown
    assert lua.eval("TICKERS") == 0
    print("CLOSE SCENARIO PASSED")
    sys.exit(0)
run(400)
sent = lua.eval("SENT")
n1 = len(sent)
print("crates scan: kind =", WC.Scanner.kind, "| queries =", n1, "| bar:", UI.barText._text)
assert WC.Scanner.kind == "crates" and not WC.Scanner.active

ev = lx("local WC = ... ; return WC:EvaluateCrates()", WC)
by = {}
for i in range(1, len(ev) + 1):
    e = ev[i]; by[e.crate.en] = e
    costs = [e.opts[j].cost for j in range(1, len(e.opts) + 1) if e.opts[j].cost is not None]
    if costs: assert fabs(min(costs) - e.matCost) < 1e-9
    if e.perFavor is not None:
        assert fabs(max(e.crateCost + e.matCost - e.crate.silver, 0) / e.favorExp - e.perFavor) < 1e-9
assert by["Apprentice Textiles"].opts[by["Apprentice Textiles"].bestIdx].itemID == 2318 and by["Apprentice Textiles"].matCost == 13000
assert by["Apprentice Ore"].status == "nocrate" and by["Apprentice Herbs"].status == "nomats"
assert ev[1].crate.en == "Expert Parts"
vis = lx("local WC = ... ; return WC:VisibleCrates(WC:EvaluateCrates())", WC)
names = [vis[i].crate.en for i in range(1, len(vis) + 1)]
assert "Apprentice Ore" not in names and "Apprentice Herbs" not in names
print("crates: evaluation + filters OK |", len(names), "visible | best:", UI.tabs.crates.best.name._text)
r1 = CRATE_TAB.list.rows[1]
r1.hotA._scripts.OnClick(); t1 = g.SEARCH_TEXT
r1.hotB._scripts.OnClick(); t2 = g.SEARCH_TEXT
print("crates click search:", t1, "/", t2)
if LOCALE == "enUS": assert t1 == "Waylaid Crate: Expert Parts" and t2 == "Mithril Tube"
crate_prices_before = {c: by[c].crateCost for c in by}

# ---------------------------------------------------------------- writs tab
UI.SelectTab(UI, "writs")
assert db.tab == "writs" and WRIT_TAB.panel._shown and not CRATE_TAB.panel._shown
WC.Scanner.Start(WC.Scanner, "writs")
run(900)
sent = lua.eval("SENT")
writ_q = [sent[i].id for i in range(n1 + 1, len(sent) + 1)]
phase1 = [q for q in writ_q if q >= 264000]
phase2 = [q for q in writ_q if q < 264000]
print("writs scan: queries =", len(writ_q), "(writs", len(set(phase1)), "+ items", len(set(phase2)), ") | bar:", UI.barText._text)
assert len(set(phase1)) == 150
listed_items = set(lx("""local WC = ...
local out = {}
for _, w in ipairs(WC.WRITS) do if WRITS_LISTED[w.writ] then out[#out + 1] = w.item end end
return out""", WC).values())
assert set(phase2) == listed_items, (sorted(set(phase2)), sorted(listed_items))

ev = lx("local WC = ... ; return WC:EvaluateWrits()", WC)
rows = []
receipt = None
for i in range(1, len(ev) + 1):
    e = ev[i]
    if e.receipt: receipt = e; continue
    rows.append(e)
ok = [e for e in rows if e.perRep is not None]
# independent check of cost per reputation (no bonus yet)
for e in ok:
    w = e.writ
    exp = (e.writCost + e.itemCost) / w.rep
    assert fabs(exp - e.perRep) < 1e-9, (w.en, exp, e.perRep)
solid = [e for e in rows if e.writ.writ == 264037][0]
print("Crafted Solid Shot x200: item cost =", solid.itemCost, "(expected 150 x 5 + 50 x 15 = 1500) | writ", solid.writCost)
assert solid.itemCost == 1500
robe = [e for e in rows if e.writ.writ == 264047][0]
print("Lesser Wizard's Robe status:", robe.status)
assert robe.status == "noitem"
mana = [e for e in rows if e.writ.writ == 264013][0]
assert mana.done
best_per_favor = lx("local WC = ... ; return WC:BestPerFavor()", WC)
cheapest_crate = min(v for v in crate_prices_before.values() if v is not None)
print("receipt row: crate", receipt.writCost, "receipt", receipt.itemCost, "rep", receipt.repGain, "per rep", receipt.perRep)
assert receipt.writCost == cheapest_crate and fabs(receipt.itemCost - 15 * best_per_favor) < 1e-9 and receipt.repGain == 50

vis = lx("local WC = ... ; return WC:VisibleWrits(WC:EvaluateWrits())", WC)
vnames = [("RECEIPT" if vis[i].receipt else vis[i].writ.en) for i in range(1, len(vis) + 1)]
print("visible (default filters):", vnames)
assert "Lesser Wizard's Robe" not in vnames and "Lesser Mana Potion" not in vnames
assert len([n for n in vnames if n != "RECEIPT"]) == 6
# ranking: by cost per reputation
scores = [vis[i].perRep for i in range(1, len(vis) + 1)]
assert scores == sorted(scores)
print("writs ranking order OK; top:", vnames[0])

db.hideDone = False; db.hideNoItem = False
vis2 = lx("local WC = ... ; return WC:VisibleWrits(WC:EvaluateWrits())", WC)
n2 = [("RECEIPT" if vis2[i].receipt else vis2[i].writ.en) for i in range(1, len(vis2) + 1)]
assert "Lesser Mana Potion" in n2 and "Lesser Wizard's Robe" in n2
db.hideDone = True; db.hideNoItem = True

# bonus
db.diplomatRank = 5
e75 = [e for e in [lx("local WC = ... ; return WC:EvaluateWrits()", WC)[i] for i in range(1, 152)] if not e.receipt and e.writ.writ == 264013][0]
print("Diplomat 5/5: 75 ->", e75.repGain)
assert fabs(e75.repGain - 82.5) < 1e-9
db.diplomatRank = 0

# UI rows + clicks
UI.Refresh(UI)
w1 = WRIT_TAB.list.rows[1]
print("writ row1:", w1.rank._text, "|", w1.name._text, "|", w1.sub._text, "|", w1.item._text, "|", w1.itemSub._text, "|", w1.price._text, "|", w1.cost._text, "|", w1.rep._text, "|", w1.per._text)
b = WRIT_TAB.best
print("writ best panel:", b.label._text, "|", b.name._text, "|", b.detail._text, "|", b.perLabel._text, b.per._text, "|", b.net._text)
print("race:", WRIT_TAB.race._text, "| standing:", WRIT_TAB.standing._text)
# find a writ row (not the receipt) and click both hotspots
for i in range(1, 152):
    r = WRIT_TAB.list.rows[i]
    if r.entry and not r.entry.receipt:
        r.hotA._scripts.OnClick(); a = g.SEARCH_TEXT
        r.hotB._scripts.OnClick(); bb = g.SEARCH_TEXT
        print("writ click search:", a, "/", bb)
        if LOCALE == "enUS":
            assert a == "Craftsman's Writ: " + r.entry.writ.en and bb == r.entry.writ.en
        r.hotA._scripts.OnEnter(r.hotA); tt = lua.eval("TT")
        print("writ tooltip:"); [print("   ", tt[k]) for k in range(1, len(tt) + 1)]
        break
for i in range(1, 152):
    r = WRIT_TAB.list.rows[i]
    if r.entry and r.entry.receipt:
        r._scripts.OnEnter(r); tt = lua.eval("TT")
        print("receipt tooltip:"); [print("   ", tt[k]) for k in range(1, len(tt) + 1)]
        assert not r.hotB._shown
        break

# crate prices survived the writ scan
ev = lx("local WC = ... ; return WC:EvaluateCrates()", WC)
after = {ev[i].crate.en: ev[i].crateCost for i in range(1, len(ev) + 1)}
assert after == crate_prices_before
tr = [ev[i] for i in range(1, len(ev) + 1) if ev[i].crate.en == "Expert Parts"][0]
assert any(tr.opts[j].itemID == 10560 and tr.opts[j].cost is not None for j in range(1, len(tr.opts) + 1))
print("crate prices kept after writ scan; Unstable Trigger still priced for crates")

# full writ scan with the 'not for sale' filter off scans every requested item
db.hideNoWrit = False
before = len(lua.eval("SENT"))
WC.Scanner.Start(WC.Scanner, "writs")
run(1500)
sent = lua.eval("SENT")
q = [sent[i].id for i in range(before + 1, len(sent) + 1)]
print("writ scan with filter off: queries =", len(q), "items:", len(set(x for x in q if x < 264000)))
assert len(set(x for x in q if x < 264000)) == 150

# saved results format (2 = 1.3.0, 3 = 2026.10.x with the same results layout)
assert db.resultsFormat in (2, 3) and db.scannedAt.writs and db.scannedAt.crates
# nothing ticks while idle, and no tab raised an error
assert lua.eval("TICKERS") == 0, lua.eval("TICKERS")
errs = UI.errors
assert errs is None or len(errs) == 0, [errs[i] for i in range(1, len(errs) + 1)]
print("ALL CHECKS PASSED")
