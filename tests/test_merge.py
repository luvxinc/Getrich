#!/usr/bin/env python3
"""Scenario tests for Getrich (formerly Waylaid Crate; 2026.10.2 merge + 2026.10.3 round 2), run against tests/wowmock.py.

usage: python3 tests/test_merge.py [--locale enUS|zhCN|zhTW] [-k substring] [-v] [--list]
Each scenario starts a fresh mock client, prints PASS / FAIL / ERROR with the reason, and every scenario also fails on
Lua errors, strict-API violations (calls to APIs that do not exist on WoW Forever 1.60.1) and unexpected globals.
Expected numbers are computed by hand from tests/fixtures (the arithmetic is in the comments next to each check).
"""
import argparse, json, math, os, re, sys, time, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wowmock import WowClient, DEFAULT_CHAR, SECOND_CHAR, SERVER_TIME0, _strip, _json  # noqa: E402

REAL_SV = os.path.join(HERE, "fixtures", "sv_waylaidcrate_130.lua")   # the user's real 1.3.0 SavedVariables
ADDON_TOC = os.environ.get("WC_ADDON_TOC", "Getrich/Getrich.toc")   # --addon DIR overrides (mutation tests)
UNCACHED = False     # --uncached: start every client with an empty item cache (fresh login)
FIX = os.path.join(HERE, "fixtures")


# ===================================================================================================================
# tiny test framework
# ===================================================================================================================
class Fail(Exception):
    pass


class Ctx:
    """Per-scenario context: collects soft failures so one run reports everything that is wrong."""

    def __init__(self, name, locale, verbose):
        self.name, self.locale, self.verbose = name, locale, verbose
        self.failures, self.notes, self.clients = [], [], []

    def check(self, cond, msg):
        if not cond:
            self.failures.append(msg)
        return bool(cond)

    def eq(self, actual, expected, what, tol=1e-6):
        ok = False
        if isinstance(expected, float) or isinstance(actual, float):
            ok = actual is not None and expected is not None and abs(float(actual) - float(expected)) <= tol
        else:
            ok = actual == expected
        if not ok:
            self.failures.append("%s: expected %r, got %r" % (what, expected, actual))
        return ok

    def require(self, cond, msg):
        if not cond:
            raise Fail(msg)

    def money(self, copper):
        return copper_text(copper, self.locale)

    def note(self, msg):
        self.notes.append(msg)

    def log(self, *a):
        if self.verbose:
            print("      ", *a)

    def client(self, locale=None, char=DEFAULT_CHAR, sv=None, login=True, cached=True, **kw):
        if UNCACHED:
            cached = False
        c = WowClient(locale=locale or self.locale, char=char, cached=cached, **kw)
        if sv:
            c.load_sv(sv)
        c.load_addon(ADDON_TOC)
        if login:
            c.login()
        self.clients.append(c)
        return c


SCENARIOS = []


def scenario(name, doc=""):
    def deco(fn):
        SCENARIOS.append((name, fn, doc or (fn.__doc__ or "").strip().split("\n")[0]))
        return fn
    return deco


def lua_list(t):
    if t is None:
        return []
    return [t[i] for i in range(1, len(t) + 1)]


def lua_keys(t):
    return [] if t is None else list(t.keys())


def multi(v, n=2):
    """Normalize a Lua call result (lupa returns a tuple for several values) to a tuple of length n."""
    if isinstance(v, tuple):
        return tuple(v[:n]) + (None,) * (n - len(v))
    return (v,) + (None,) * (n - 1)


def first(v):
    return v[0] if isinstance(v, tuple) else v


def fnum(v):
    return None if v is None else float(v)


def copper_text(copper, locale="enUS"):
    """What WC.Money prints, without color codes ('1g 2s 3c'; zh uses 金/银/铜 per Locale.lua)."""
    neg = copper < 0
    c = int(math.floor(abs(copper) + 0.5))
    g, s, cp = c // 10000, (c % 10000) // 100, c % 100
    sym = {"enUS": ("g", "s", "c"), "zhCN": ("金", "银", "铜"), "zhTW": ("金", "銀", "銅")}[locale]
    parts = []
    if g:
        parts.append("%d%s" % (g, sym[0]))
    if s:
        parts.append("%d%s" % (s, sym[1]))
    if cp or not parts:
        parts.append("%d%s" % (cp, sym[2]))
    return ("-" if neg else "") + " ".join(parts)


def start_scan(c, kind, timeout=900):
    """Press a tab's check button (Scanner kind) and run the clock until it finished. Returns ok, seconds."""
    WC = c.WC
    t0 = c.now()
    ok = WC.Scanner.Start(WC.Scanner, kind)
    c.advance(timeout, until=lambda: not WC.Scanner.active)
    return ok, c.now() - t0


# Until 2026.11.1 a scan searched everything a tab uses; since 2026.11.2 prices come from Auctionator and a check
# only searches the best entries. The price maths (order books, bundles, profits, routes) is still tested on exact
# order books of everything: these lists are what the old scans searched, and search_exact() searches them with a
# test-only Scanner kind.
OLD_SCAN_LIST = r'''
local WC, kind, all = ...
local list, seen = {}, {}
local function add(id) if type(id) == "number" and not seen[id] then seen[id] = true; list[#list + 1] = id end end
local function sorted(set) local t = {} for id in pairs(set) do t[#t + 1] = id end table.sort(t) return t end
if kind == "crates" then
  for _, c in ipairs(WC.CRATES) do add(c.id); for _, o in ipairs(c.opts) do add(o[1]) end end
elseif kind == "writs" then
  for _, w in ipairs(WC.WRITS) do add(w.writ) end
elseif kind == "writ_items" then
  for _, w in ipairs(WC.WRITS) do
    local _, status = WC:CostFor(w.writ, 1)
    if all or status == "ok" then add(w.item) end
  end
elseif kind == "de" then
  for _, id in ipairs(sorted(WC.DE.mats)) do add(id) end
elseif kind == "craft" then
  -- materials (not the ones a confirmed unlimited vendor sells) and products of the character's recipes and of
  -- its skill-up candidates; the disenchanting materials when something it makes is gear and it has Enchanting
  local charKey = WC:CharKey()
  local reag, outs = {}, {}
  local function Reagent(id)
    if id and reag[id] == nil then
      local unit, info = WC:VendorPrice(id)
      reag[id] = not (unit and type(info) == "table" and not info.limited and not info.classic)
    end
  end
  for _, r in pairs(WC.Recipes:ForChar(charKey) or {}) do
    if type(r) == "table" and r.o then
      outs[r.o] = true
      for _, rg in ipairs(type(r.r) == "table" and r.r or {}) do Reagent(tonumber(rg[1] or rg.itemID)) end
    end
  end
  local lr, lo = WC.Leveling:ScanItems(charKey)
  for id in pairs(lr or {}) do Reagent(id) end
  for id in pairs(lo or {}) do outs[id] = true end
  local need = {}
  for id, search in pairs(reag) do if search then need[id] = true end end
  for _, id in ipairs(sorted(need)) do add(id) end
  local anyGear = false
  for _, id in ipairs(sorted(outs)) do
    add(id)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    if classID == 2 or classID == 4 then anyGear = true end
  end
  local ench = WC:EnchantingSkill(charKey)
  if anyGear and ench and ench > 0 then for _, id in ipairs(sorted(WC.DE.mats)) do add(id) end end
end
return list
'''


def old_scan_list(c, kind, all_items=False):
    return [int(x) for x in lua_list(c.eval(OLD_SCAN_LIST, c.WC, kind, all_items))]


def search_exact(c, items, timeout=3600):
    """Search `items` exactly, one after the other, as a check does. Returns ok, seconds."""
    WC = c.WC
    t0 = c.now()
    ok = begin_exact(c, items)
    c.advance(timeout, until=lambda: not WC.Scanner.active)
    return ok, c.now() - t0


def full_search(c, kind, timeout=3600):
    """Exact order books of everything the tab `kind` uses (what its scan searched until 2026.11.1).
    kind: crates | writs (the writs, then the items of the writs for sale, or of all with hideNoWrit off) | craft | de."""
    if kind == "writs":
        ok, t1 = search_exact(c, old_scan_list(c, "writs"), timeout)
        items = old_scan_list(c, "writ_items", not c.g("GetrichDB").hideNoWrit)
        t2 = search_exact(c, items, timeout)[1] if items else 0
        return ok, t1 + t2
    return search_exact(c, old_scan_list(c, kind), timeout)


def visible_tab_texts(c):
    return c.texts(clip=True)


# ---- a stand-in for Auctionator: the only source of prices since 2026.11.2 ----------------------------------------
def install_auctionator(c):
    """Auctionator's add-on API (Auctionator.API.v1). Auctionator.prices[itemID] = { cheapest unit price, age in days }.
    Installed before login when Getrich should be told about updates (RegisterForDBUpdate), else any time."""
    c.eval("""
      if rawget(_G, "Auctionator") then return end
      local A = { API = { v1 = {} }, callbacks = {}, prices = {}, calls = 0 }
      local function check(id)
        A.calls = A.calls + 1
        if type(id) ~= "string" or id == "" then error("Invalid callerID. Use the name of your add-on.") end
      end
      function A.API.v1.GetAuctionPriceByItemID(callerID, itemID) check(callerID); local p = A.prices[itemID]; return p and p[1] or nil end
      function A.API.v1.GetAuctionAgeByItemID(callerID, itemID) check(callerID); local p = A.prices[itemID]; return p and p[2] or nil end
      function A.API.v1.RegisterForDBUpdate(callerID, fn) check(callerID); A.callbacks[#A.callbacks + 1] = fn end
      rawset(_G, "Auctionator", A)""")


# crate materials whose crates are not listed in the test markets (nothing ranks from them)
AUC_BACKGROUND_CRATE = [7911, 10620, 11370, 13464, 8838, 8839, 8845, 8846, 13463, 13465, 13466, 13467]


def auctionator_update(c, prices, background=0, fire=True):
    """Auctionator stores `prices` ({itemID: unit price}) as seen today and tells its listeners.
    background = a price: the update also saw 12 other crate materials and the items of the first 8 writs at about
    that price, like a full scan does (Getrich recognises a full scan by many crate and writ items).
    background = 0: only `prices`, like a search for those items."""
    install_auctionator(c)
    c.eval("""local WC, prices, bg, crateBg, fire = ...
      local A = Auctionator
      for id, p in pairs(prices) do A.prices[id] = { p, 0 } end
      if bg > 0 then
        for _, id in pairs(crateBg) do if not prices[id] then A.prices[id] = { bg, 0 } end end
        for i = 1, 8 do local id = WC.WRITS[i].item; if not prices[id] then A.prices[id] = { bg + i, 0 } end end
      end
      if fire then for _, fn in ipairs(A.callbacks) do fn() end end""",
           c.WC, c.lua.table_from(prices), background, c.lua.table_from(AUC_BACKGROUND_CRATE), fire)
    if fire:
        c.advance(0.3)        # Getrich looks a moment after Auctionator's callback (External.lua LookSoon)
    c.eval("local WC = ...; WC.External:Invalidate()", c.WC)


def auctionator_scan_ah(c, background=500000, fire=True):
    """Auctionator runs a full scan of the mock Auction House: the cheapest listing of every item that is listed
    (plus the background of auctionator_update). Returns {itemID: price}."""
    t = c.eval("""local M = ...
      local out = {}
      for id, l in pairs(M.AH.listings) do
        local min
        for _, r in ipairs(l.rows or {}) do if r.unit and (not min or r.unit < min) then min = r.unit end end
        if min then out[id] = min end
      end
      return out""", c.M)
    prices = {int(k): int(t[k]) for k in t.keys()}
    auctionator_update(c, prices, background=background, fire=fire)
    return prices


def auctionator_new_day(c):
    """Auctionator's day counter moves on: everything it knows is one day older."""
    c.eval("for _, p in pairs(Auctionator.prices) do p[2] = p[2] + 1 end")
    c.eval("local WC = ...; WC.External:Invalidate()", c.WC)


def ext_state(c):
    """(usable, why) of External.lua, freshly computed."""
    return multi(c.eval("local WC = ...; local X = WC.External; X:Invalidate(); local s = X:State(); return X:Usable(), s.why", c.WC), 2)


def crate_entry(c, crate_id):
    return [e for e in lua_list(c.eval("local WC = ...; return WC:EvaluateCrates()", c.WC)) if e.crate.id == crate_id][0]


def begin_exact(c, items):
    """Start an exact search of `items` (test-only kind) without waiting for it. Returns ok."""
    WC = c.WC
    c.eval("""local WC, ids = ...
      local list = {}
      for i = 1, #ids do list[i] = ids[i] end
      WC.Scanner:RegisterKind("exact", { label = function() return "exact search" end,
                                         phases = { { label = "items", items = function() return list end } } })""",
           WC, c.lua.table_from(list(items)))
    return WC.Scanner.Start(WC.Scanner, "exact")


# ===================================================================================================================
# 1.3.0 market (port of tests/mock_test.py, same deterministic order books)
# ===================================================================================================================
MARKET_130 = r'''
local WC, M = ...
local function setL(id, rows, commodity)
  local t = {}
  for _, r in ipairs(rows) do M.AH.auctionSeq = M.AH.auctionSeq + 1; t[#t + 1] = { unit = r[1], qty = r[2], auctionID = M.AH.auctionSeq } end
  M.AH.listings[id] = { rows = t, commodity = commodity }
end
local seed = 7
local function rnd(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end
local BOOK, ITEM_PATH = {}, {}
for _, c in ipairs(WC.CRATES) do
  ITEM_PATH[c.id] = true
  BOOK[c.id] = { { rnd(5000, 30000), 1 }, { 40000, 1 } }
  for _, o in ipairs(c.opts) do BOOK[o[1]] = { { rnd(50, 500), 200 }, { rnd(600, 900), 500 } } end
end
for _, w in ipairs(WC.WRITS) do ITEM_PATH[w.writ] = true; BOOK[w.writ] = {} end
BOOK[2589] = { { 10, 30 } }                       -- Linen: only 30 (needs 40)
BOOK[2318] = { { 400, 10 }, { 900, 50 } }         -- 20 Light Leather = 13000
BOOK[248683] = {}                                 -- Apprentice Ore crate not for sale
for _, id in ipairs({ 2447, 765, 2449, 785, 2450 }) do BOOK[id] = {} end   -- herbs sold out
BOOK[248710] = { { 100, 1 } }                     -- Expert Parts crate: 1c
BOOK[10559] = { { 1, 100 } }                      -- Mithril Tube
M.AH.noAnswer[2771] = true                        -- Tin Ore never answers
M.AH.notLoadedOnce[4306] = true                   -- Silk Cloth answers 'not loaded' first
WRITS_LISTED = {
  [264072] = { writ = 5000,  item = 20000 },
  [264082] = { writ = 3000,  item = 9000 },
  [264037] = { writ = 2000,  item = 5 },
  [264013] = { writ = 1500,  item = 300 },
  [264124] = { writ = 9000,  item = 40000 },
  [264047] = { writ = 1000,  item = nil },
  [264085] = { writ = 4000,  item = 2500 },
  [264153] = { writ = 20000, item = 30000 },
}
for _, w in ipairs(WC.WRITS) do
  local s = WRITS_LISTED[w.writ]
  if s then
    BOOK[w.writ] = { { s.writ, 1 }, { s.writ * 2, 1 } }
    if s.item then BOOK[w.item] = { { s.item, 150 }, { s.item * 3, 300 } } else BOOK[w.item] = {} end
  elseif w.item ~= 10560 then
    BOOK[w.item] = { { 777, 5 } }
  end
end
M.questsDone[94213] = true                        -- Lesser Mana Potion writ done today
for id, rows in pairs(BOOK) do setL(id, rows, not ITEM_PATH[id]) end
'''

EVAL_DUMP = r'''
local WC = ...
local out = { crates = {}, writs = {} }
for _, e in ipairs(WC:EvaluateCrates()) do
  local best = e.bestIdx and e.opts[e.bestIdx]
  out.crates[#out.crates + 1] = { id = e.crate.id, crateCost = e.crateCost, crateStatus = e.crateStatus, matCost = e.matCost,
    best = best and best.itemID or false, net = e.net, perFavor = e.perFavor, status = e.status, locked = e.locked }
end
for _, e in ipairs(WC:EvaluateWrits()) do
  out.writs[#out.writs + 1] = { id = e.receipt and 0 or e.writ.writ, writCost = e.writCost, itemCost = e.itemCost, cost = e.cost,
    repGain = e.repGain, perRep = e.perRep, status = e.status, done = e.done or false, receipt = e.receipt or false }
end
return out
'''


def setup_market_130(c):
    c.clear_listings()
    c.eval(MARKET_130, c.WC, c.M)


def eval_dump(c):
    t = c.eval(EVAL_DUMP, c.WC)

    def norm(row):
        d = {}
        for k in row.keys():
            v = row[k]
            d[k] = round(v, 6) if isinstance(v, float) else v
        return d
    return {"crates": [norm(x) for x in lua_list(t.crates)], "writs": [norm(x) for x in lua_list(t.writs)]}


def run_market_130(c, ctx=None):
    """The 1.3.0 test session: everything of the Crates tab searched, then the writs (and the items of the writs for
    sale), then the items of all writs. Returns the evaluation dumps after each step."""
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    full_search(c, "crates")
    out = {"after_crates": eval_dump(c)}
    WC.UI.SelectTab(WC.UI, "writs")
    full_search(c, "writs")
    out["after_writs"] = eval_dump(c)
    c.g("GetrichDB").hideNoWrit = False
    full_search(c, "writs")
    out["after_writs_all"] = eval_dump(c)
    return out


# ===================================================================================================================
# scenarios
# ===================================================================================================================
TABS = ["crates", "writs", "flips", "craft", "de", "history"]

# Simplified-only / traditional-only characters common in this addon's wording (heuristic script check).
SIMPLIFIED_ONLY = set("价钱扫卖买时间设显隐数项关开进结记录历势图单总计润这们个为东变认让说选择标题货币银铜级满处确输误栏统钟导启额实际专业应宽对齐无产资务场库种类测试发现获损坏状态动杂节点头层页签号码张条线网络电话质别长门钥锁鉴识难颜绿红蓝黄筛汇储仅当预览帮载报错购补赚亏职涨来观样换铁锡矿药剂炉锤")
TRADITIONAL_ONLY = set("價錢掃賣買時間設顯隱數項關開進結記錄歷勢圖單總計潤這們個為東變認讓說選擇標題貨幣銀銅級滿處確輸誤欄統鐘導啟額實際專業應寬對齊無產資務場庫種類測試發現獲損壞狀態動雜節點頭層頁簽號碼張條線網絡電話質別長門鑰鎖鑑識難顏綠紅藍黃篩匯儲僅當預覽幫載報錯購補賺虧職漲來觀樣換鐵錫礦藥劑爐錘")


def locale_strings(c):
    """All string values of WC.L (nested tables flattened) -> {key: text}"""
    out = {}

    def walk(prefix, t):
        for k in t.keys():
            v = t[k]
            key = "%s%s" % (prefix, k)
            if isinstance(v, str):
                out[key] = v
            elif v is not None and hasattr(v, "keys"):
                walk(key + ".", v)
    walk("", c.WC.L)
    return out


def check_clean(ctx, c, what=""):
    for p in c.problems():
        ctx.failures.append((what + ": " if what else "") + p)


# ------------------------------------------------------------------------------------------------------------------
@scenario("load_all_locales", "all TOC files load in order in enUS / zhCN / zhTW; every tab opens; zh strings in the right script")
def s_load(ctx):
    base = None
    for loc in ("enUS", "zhCN", "zhTW"):
        c = ctx.client(locale=loc)
        ctx.check(not c.missing_files, "%s: files listed in the TOC but missing: %s" % (loc, c.missing_files))
        ctx.eq(len(c.loaded_files), len(c.toc["files"]), "%s: files loaded" % loc)
        L = locale_strings(c)
        if loc == "enUS":
            base = L
        else:
            same = [k for k, v in L.items() if base.get(k) == v and re.search(r"[A-Za-z]{4,}", v) and not re.search(r"Writ|Favor|Crate|AH|%s|%d", v)]
            ctx.check(len(same) <= max(5, len(L) // 12), "%s: %d strings identical to English (untranslated?): %s" % (loc, len(same), same[:12]))
            bad = SIMPLIFIED_ONLY if loc == "zhTW" else TRADITIONAL_ONLY
            wrong = sorted((k, "".join(sorted(set(v) & bad))) for k, v in L.items() if set(v) & bad)
            ctx.check(not wrong, "%s: %d strings use characters of the other Chinese script, e.g. %s" % (loc, len(wrong), wrong[:8]))
        c.slash("/wc")
        frame = c.g("GetrichFrame")
        ctx.require(frame is not None, "%s: no GetrichFrame after /wc" % loc)
        ctx.check(frame.IsVisible(frame), "%s: /wc did not show the window" % loc)
        if loc == "enUS":
            t = c.texts()
            ver, rel = c.toc["meta"].get("Version"), c.toc["meta"].get("X-Released")
            ctx.check(ver and rel and any(ver in x and rel in x for x in t),
                      "title should show 'v%s · %s' (TOC Version + X-Released); texts: %s" % (ver, rel, t[:6]))
        ctx.eq(frame.GetWidth(frame), 700, "%s: window width" % loc)
        ctx.eq(frame.GetHeight(frame), 700, "%s: window height" % loc)
        for tab in TABS:
            c.slash("/wc " + tab)
            ctx.eq(c.g("GetrichDB").tab, tab, "%s: /wc %s -> db.tab" % (loc, tab))
            ctx.check(frame.IsVisible(frame), "%s: window hidden after /wc %s" % (loc, tab))
            n = len(c.texts(clip=True))
            ctx.check(n >= 8, "%s: tab %s shows only %d texts" % (loc, tab, n))
        check_clean(ctx, c, loc)


# ------------------------------------------------------------------------------------------------------------------
@scenario("crates_writs_130", "1.3.0 crates/writs session: the 22 crates and 150 writs of v1.3.0 evaluate as they did then (eval_130.json) + 1.3.0 UI checks")
def s_130(ctx):
    c = ctx.client(locale="enUS")
    got = run_market_130(c, ctx)
    ref = json.load(open(os.path.join(FIX, "eval_130.json")))
    for step in ("after_crates", "after_writs", "after_writs_all"):
        for part in ("crates", "writs"):
            a, b = got[step][part], ref[step][part]
            # 2026.11.0 added the 8 Artisan crates (level 35): everything 1.3.0 had must still be there, by id
            new = {x.get("id"): x for x in a}
            ctx.eq(len(a), len(b) + (8 if part == "crates" else 0), "%s %s count" % (step, part))
            for y in b:
                x = new.get(y.get("id"))
                if x is None:
                    ctx.failures.append("%s %s id %s of 1.3.0 is gone" % (step, part, y.get("id")))
                    break
                diff = {k: (x.get(k), y.get(k)) for k in set(x) | set(y) if x.get(k) != y.get(k)}
                if part == "writs":
                    # 2026.11.0, on purpose: a writ that was never searched is "unscanned" even when its requested
                    # item already has a price from the crate scan (1.3.0 called that "nowrit"); and Truesilver
                    # Transformer (writ 264140) is now a crate material, so the crate scan prices it.
                    if diff.get("status") == ("unscanned", "nowrit") and x.get("writCost") is None:
                        del diff["status"]
                    if y.get("id") == 264140 and diff.get("itemCost", (None, 0))[1] is None:
                        del diff["itemCost"]
                if diff:
                    ctx.failures.append("%s %s id %s differs from 1.3.0 (new, 1.3.0): %s" % (step, part, y.get("id"), diff))
                    break
    WC = c.WC
    # 1.3.0 checks (tests/mock_test.py): filters, rank order, bonuses
    db = c.g("GetrichDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat after the searches")
    vis = lua_list(c.eval("local WC = ...; return WC:VisibleCrates(WC:EvaluateCrates())", WC))
    names = [v.crate.en for v in vis]
    ctx.check("Apprentice Ore" not in names and "Apprentice Herbs" not in names, "default crate filters hide Ore/Herbs: %s" % names)
    vw = lua_list(c.eval("local WC = ...; return WC:VisibleWrits(WC:EvaluateWrits())", WC))
    scores = [v.perRep for v in vw]
    ctx.check(None not in scores[:scores.index(None)] if None in scores else True, "unscored writs must come after scored ones")
    scored = [x for x in scores if x is not None]
    ctx.check(scored == sorted(scored), "writs ranked by cost per reputation")
    db.diplomatRank = 5
    e75 = [e for e in lua_list(c.eval("local WC = ...; return WC:EvaluateWrits()", WC)) if not e.receipt and e.writ.writ == 264013][0]
    ctx.eq(fnum(e75.repGain), 82.5, "Legacy Diplomat 5/5: 75 rep -> 75 x 1.10")
    db.diplomatRank = 0
    # click search: crate name -> "Waylaid Crate: Expert Parts"; recommended material -> "Mithril Tube"
    c.slash("/wc crates")
    c.click_text("Expert Parts")
    ctx.eq(c.eval("return AuctionHouseFrame.SearchBar.SearchBox:GetText()"), "Waylaid Crate: Expert Parts", "click crate name -> AH search box")
    c.click_text("Mithril Tube")
    ctx.eq(c.eval("return AuctionHouseFrame.SearchBar.SearchBox:GetText()"), "Mithril Tube", "click material -> AH search box")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("scanner_rows_vs_quantity", "1.3.0 bug: result loops must walk rows (GetNum*SearchResults), not units; paging keeps unit totals")
def s_rows(ctx):
    c = ctx.client()
    WC = c.WC
    # 3 rows holding 9000 units: the old loop asked GetCommoditySearchResultInfo 9000 times
    c.set_listings(2589, [(10, 3000), (11, 3000), (12, 3000)])
    c.set_listings(1273, [(5000, 1), (6000, 1)])                    # gear: item search, 2 rows of 1
    c.M.AH.resultPageSize = 2
    c.set_listings(2770, [(5, 1), (6, 1), (7, 100), (8, 100)])       # 4 rows, first page = 2 rows (2 units)
    for i in (2589, 1273, 2770):
        WC.Store.SetWatch(WC.Store, i, True)
    c.open_ah()
    c.advance(1)
    ok, secs = start_scan(c, "history", 120)
    ctx.require(ok, "Scanner:Start('history') refused")
    st = c.ah_stats()
    calls = st["commodityInfoCalls"].get(2589, 0)
    searches = st["searchByItem"].get(2589, 1)
    ctx.check(calls <= 3 * searches + 2, "GetCommoditySearchResultInfo(2589) called %d times for 3 rows (%d searches) - loop over units?" % (calls, searches))
    ctx.check(st["itemInfoCalls"].get(1273, 0) <= 2 * st["searchByItem"].get(1273, 1) + 2, "GetItemSearchResultInfo(1273) called %d times for 2 rows" % st["itemInfoCalls"].get(1273, 0))
    res = c.g("GetrichDB").results
    r = res[2589]
    ctx.require(r is not None and r.status == "listed", "2589 not recorded as listed: %s" % (r and r.status))
    # KEEP_QTY 250: the first row (3000 units) already covers it -> one kept entry; avail = 3 x 3000 = 9000
    ctx.eq([[int(e[1]), int(e[2])] for e in lua_list(r.entries)], [[10, 3000]], "2589 kept entries")
    ctx.eq(int(r.avail), 9000, "2589 avail (sum of units)")
    ctx.eq(int(r.min), 10, "2589 min")
    r = res[1273]
    ctx.eq([[int(e[1]), int(e[2])] for e in lua_list(r.entries)] if r else None, [[5000, 1], [6000, 1]], "1273 entries (item search, buyout per unit)")
    r = res[2770]
    ctx.require(r is not None and r.status == "listed", "2770 (paged) not listed")
    ent = [[int(e[1]), int(e[2])] for e in lua_list(r.entries)]
    ctx.eq(ent[:2], [[5, 1], [6, 1]], "2770 first page rows")
    # either only the first page (avail from GetCommoditySearchResultsQuantity = 1+1+100+100) or all pages
    ctx.eq(int(r.avail), 202, "2770 avail = units listed (202), even if only page 1 was read")
    ctx.eq(WC.CostFor(WC, 2770, 2)[0], 11, "CostFor(2770, 2) = 5 + 6")
    info_calls = st["commodityInfoCalls"].get(2770, 0)
    ctx.check(info_calls <= 4 * st["searchByItem"].get(2770, 1) + 2, "GetCommoditySearchResultInfo(2770) called %d times" % info_calls)
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("scan_survives_noise", "Getrich regression: ITEM_DATA_LOAD_RESULT / bag updates / Blizzard's own AH queries / dropped messages never cancel or corrupt a scan")
def s_noise(ctx):
    c = ctx.client(cached=False)
    WC = c.WC
    books = c.load_orderbooks()
    crate_items = set()
    for cr in lua_list(WC.CRATES):
        crate_items.add(int(cr.id))
        for o in lua_list(cr.opts):
            crate_items.add(int(o[1]))
    c.set_listings(2835, [(3, 40)])            # not a crate item: Blizzard's UI will search it
    c.set_listings(1273, [(1000, 1)])
    c.open_ah()
    c.advance(1)
    chat0 = len(c.chat)
    ok = begin_exact(c, sorted(crate_items))
    ctx.require(ok, "the exact search of all crate items did not start")
    step, noise = 0, 0
    while WC.Scanner.active and step < 2000:
        step += 1
        c.advance(0.3)
        k = step % 9
        if k == 0:
            c.fire("ITEM_DATA_LOAD_RESULT", 2589 + step % 50, True)
        elif k == 1:
            c.fire("BAG_UPDATE", 0); c.fire("BAG_UPDATE_DELAYED")
        elif k == 2:
            c.fire("GET_ITEM_INFO_RECEIVED", 10940, True)
        elif k == 3 and step % 27 == 3:
            c.ah_blizzard_search(2835)              # COMMODITY_SEARCH_RESULTS_UPDATED(2835) while we wait for something else
        elif k == 4 and step % 36 == 4:
            c.ah_blizzard_search(1273)              # ITEM_SEARCH_RESULTS_UPDATED for another item
        elif k == 5 and step % 45 == 5:
            c.ah_blizzard_browse("Linen")           # Blizzard's search box (browse query)
        elif k == 6 and step % 54 == 6:
            c.M.AH.dropNext = 1                     # the server drops the next throttled message
        elif k == 7:
            c.fire("PLAYER_MONEY"); c.fire("UNIT_INVENTORY_CHANGED", "player")
        elif k == 8 and step > 30:
            # unsolicited updates of result sets the client still holds (Blizzard's lists refreshing) while we wait
            c.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2835)
            c.fire("ITEM_SEARCH_RESULTS_UPDATED", c.eval("return C_AuctionHouse.MakeItemKey(1273)"), None)
        noise += 1
    ctx.check(not WC.Scanner.active, "the search is still running after %d s of noise" % int(step * 0.3))
    ctx.check(len(c.chat) > chat0, "no chat line when the scan finished: %s" % c.chat[-3:])
    res = c.g("GetrichDB").results
    missing, wrong = [], []
    for iid in sorted(crate_items):
        r = res[iid]
        if r is None:
            missing.append(iid)
            continue
        rows = books.get(iid)
        if rows and r.status == "listed":
            if int(r.min) != min(u for u, q in rows):
                wrong.append((iid, int(r.min), min(u for u, q in rows)))
        elif rows and r.status != "listed":
            wrong.append((iid, r.status, "listed"))
    ctx.check(not missing, "crate items without a result after the scan: %s" % missing)
    ctx.check(not wrong, "results that do not match the item's own listings (polluted by another search?): %s" % wrong[:8])
    st = c.ah_stats()
    ctx.check(st["blizzard"] >= 3, "test did not inject Blizzard queries (%d)" % st["blizzard"])
    own = sum(n for iid, n in st["searchByItem"].items() if iid in crate_items)
    # one search per item; Tin Ore (2771) is in the real books but answers fine here; dropped messages cost a retry each
    ctx.log("searches for crate items: %d for %d items, %d dropped" % (own, len(crate_items), st["dropped"]))
    ctx.check(own <= len(crate_items) + st["dropped"] + 3,
              "%d searches for %d crate items (%d dropped): results for other items made the scanner retry?" % (own, len(crate_items), st["dropped"]))
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
FLIP_LISTINGS = {
    # itemID: rows (unit, qty)                     sell price (items.json)
    4306: [(100, 5), (140, 10), (160, 200)],       # Silk Cloth, sell 150
    4800: [(565, 1)],                              # Mighty Chain Pants (green armor, bind on equip), sell 1221
    4338: [(200, 3), (300, 50)],                   # Mageweave Cloth, sell 250 (cheap row bought before our search)
    2592: [(40, 20)],                              # Wool Cloth, sell 33 -> not below vendor
    2589: [(12, 1), (13, 100)],                    # Linen Cloth, sell 13
    248684: [(5000, 1)],                           # Waylaid Crate, sell 0 -> vendors don't buy
    2319: [(49, 2)],                               # Medium Leather, sell 50
    2770: [(30, 20)], 2771: [(60, 20)], 2318: [(30, 10)], 2840: [(50, 4)], 2996: [(90, 5)],   # fillers above vendor price
}


PRICE_FIRES = {}


def count_price_fires(c):
    # a Lua listener (a Python callback inside addon code would trip the 'debug' check through lupa internals)
    c.eval("local WC, M = ...; M.priceFires = {}; WC:On('PRICES_UPDATED', function() M.priceFires[#M.priceFires + 1] = GetTime() end)", c.WC, c.M)
    PRICE_FIRES[id(c)] = c


def flip_market(c):
    c.clear_listings()
    for iid, rows in FLIP_LISTINGS.items():
        c.set_listings(iid, rows)


def flip_dump(c):
    lst = lua_list(first(c.WC.Profit.Flips(c.WC.Profit)))
    return [(int(e.itemID), e.status, None if e.qty is None else int(e.qty), fnum(e.profit), fnum(e.cost), fnum(e.unit), fnum(e.perUnit)) for e in lst]


@scenario("flips_scan", "flips: Auctionator's prices -> candidates -> exact searches -> exact profit, 'gone' when the cheap listing vanished")
def s_flips(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    flip_market(c)
    count_price_fires(c)
    c.open_ah()
    c.advance(1)
    ctx.eq(flip_dump(c), [], "no flips before Auctionator has scanned")
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.check(not ok, "nothing to check without prices")
    auctionator_scan_ah(c)
    ctx.eq(ext_state(c), (True, None), "Auctionator's full scan is in use")
    # candidates, biggest gain per item first (sell - cheapest): Mighty Chain Pants 1221 - 565 = 656; Silk 150 - 100 = 50;
    # Mageweave 250 - 200 = 50 (tie -> lower itemID first); Medium Leather 50 - 49 = 1; Linen 13 - 12 = 1.
    # Wool 40 >= 33 and the crate (vendors don't buy it) are not candidates.
    cand = [int(x) for x in lua_list(WC.Profit.FlipCandidates(WC.Profit, 80))]
    ctx.eq(cand, [4800, 4306, 4338, 2319, 2589], "FlipCandidates(80)")
    got = [(i, st, q, pr) for (i, st, q, pr, _, _, _) in flip_dump(c)]
    ctx.eq(got, [(4800, "est", None, 656.0), (4306, "est", None, 50.0), (4338, "est", None, 50.0),
                 (2319, "est", None, 1.0), (2589, "est", None, 1.0)], "before a check: estimates, quantity unknown")
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    # run until the first search went out, then the cheap Mageweave row is bought by someone
    c.advance(120, until=lambda: c.ah_stats()["searches"] >= 1 or not WC.Scanner.active)
    c.set_listings(4338, [(300, 50)])
    c.advance(300, until=lambda: not WC.Scanner.active)
    ctx.require(not WC.Scanner.active, "the flips check did not finish")
    st = c.ah_stats()
    ctx.eq(st["browses"], 0, "no browse query: Getrich does not read the whole Auction House")
    ctx.eq(set(st["searchByItem"].keys()), {4306, 4338, 4800, 2589, 2319}, "items searched by the check")
    # Flips (order books):
    #   Mighty Chain Pants: 1 x (1221-565) = 656, cost 565
    #   Silk: 5 x (150-100) + 10 x (150-140) = 250 + 100 = 350, qty 15, cost 5x100 + 10x140 = 1900
    #   Medium Leather: 2 x (50-49) = 2, cost 98;  Linen: 1 x (13-12) = 1, cost 12 (the 13c row is not below 13)
    #   Mageweave: searched after Auctionator's scan, nothing below 250 any more -> "gone", last
    exp = [(4800, "ok", 1, 656.0, 565.0, 565.0, 656.0),
           (4306, "ok", 15, 350.0, 1900.0, 100.0, 50.0),
           (2319, "ok", 2, 2.0, 98.0, 49.0, 1.0),
           (2589, "ok", 1, 1.0, 12.0, 12.0, 1.0)]
    got = flip_dump(c)
    ctx.eq(got[:4], exp, "Profit:Flips() ok entries")
    ctx.check(len(got) == 5 and got[4][0] == 4338 and got[4][1] == "gone" and got[4][3] in (0, 0.0, None),
              "Mageweave should be the last entry with status 'gone': %s" % got[4:])
    # CostForAny: searched -> order book; only Auctionator -> cheapest x qty "est" (it does not know how many)
    cost, status, info = multi(WC.CostForAny(WC, 4306, 10), 3)
    ctx.eq((cost, status, info and info.source), (1200, "ok", "search"), "CostForAny(Silk, 10) = 5x100 + 5x140")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 5), 3)
    ctx.eq((cost, status, info and info.source), (150, "est", "auctionator"), "CostForAny(Copper Ore, 5) from Auctionator = 5 x 30")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 25), 3)
    ctx.eq((cost, status), (750, "est"), "CostForAny(Copper Ore, 25): 25 x 30, although only 20 are listed (not known)")
    up = multi(WC.UnitPrice(WC, 2770), 3)
    ctx.eq((up[0], up[2]), (30, "auctionator"), "UnitPrice(Copper Ore) from Auctionator")
    ctx.eq(multi(WC.CostForAny(WC, 2775, 5), 2), (None, "none"), "Silver Ore: not seen in the full scan -> not for sale")
    # history from the scan Getrich watched: relevant items only (Copper Ore is a crate material, Forest Chain is not)
    H = c.server_time() // 3600
    hist = c.g("GetrichDB").history
    rec = hist[2770] and hist[2770].h[H]
    ctx.eq(rec and (int(rec.min), rec.qty), (30, None), "the scan wrote history for Copper Ore (cheapest price, quantity unknown)")
    ctx.eq(hist[4800], None, "no history for Mighty Chain Pants (not an item Getrich follows)")
    # PRICES_UPDATED at most ~4 per second
    times = sorted(float(x) for x in lua_list(c.M.priceFires)) if id(c) in PRICE_FIRES else []
    worst = max([sum(1 for u in times if t0 <= u < t0 + 1.0) for t0 in times] or [0])
    ctx.check(worst <= 5, "PRICES_UPDATED fired %d times within one second (spec: <= ~4/s)" % worst)
    # tab
    c.slash("/wc flips")
    t = c.texts(clip=True)
    ctx.check(any("Mighty Chain Pants" in x for x in t), "flips tab does not list Mighty Chain Pants: %s" % t[:30])
    tip = "\n".join(c.hover_text("Silk Cloth"))
    for need in (ctx.money(100), ctx.money(150), "15", ctx.money(1900), ctx.money(350)):
        ctx.check(need in tip, "Silk Cloth flip tooltip lacks %r:\n%s" % (need, tip))
    ctx.check(any(ctx.money(656) in x for x in t), "flips tab does not show the 656c profit (%s)" % ctx.money(656))
    ctx.check(any(ctx.money(350) in x for x in t), "flips tab does not show Silk's 350c profit (%s)" % ctx.money(350))
    ctx.check(any("Auctionator" in x for x in t), "the tab does not say where the prices are from: %s" % t[:12])
    check_clean(ctx, c)


@scenario("flips_fresh_login", "flips on a fresh login (nothing in the item cache): found from the built-in vendor prices, exact once the item data arrives")
def s_flips_fresh(ctx):
    # Real client: C_Item.GetItemInfo (sell price) is nil for items not seen this session until requested + loaded.
    # Auctionator's prices are there right after login; the built-in item table (DataItems.lua) says what a vendor
    # pays, so the candidates are known without loading anything.
    c = ctx.client(cached=False)
    WC = c.WC
    flip_market(c)
    auctionator_scan_ah(c, fire=False)       # Auctionator's data from an earlier session
    ctx.eq(ext_state(c), (True, None), "prices right after login, Auction House closed")
    cand = [int(x) for x in lua_list(WC.Profit.FlipCandidates(WC.Profit, 80))]
    ctx.eq(cand, [4800, 4306, 4338, 2319, 2589], "FlipCandidates with a cold item cache")
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    c.advance(300, until=lambda: not WC.Scanner.active)
    searched = set(c.ah_stats()["searchByItem"].keys())
    ctx.eq(searched, {4306, 4338, 4800, 2589, 2319}, "items searched with a cold item cache")
    c.advance(5)
    got = {e[0]: e[1] for e in flip_dump(c)}
    ctx.eq(got.get(4800), "ok", "Mighty Chain Pants flip status after the check (cold item cache)")
    check_clean(ctx, c)


@scenario("gear_random_suffix", "a search that finds nothing proves nothing for gear (random suffixes are listed under their own key): the flip stays an estimate")
def s_gear_suffix(ctx):
    c = ctx.client()
    WC = c.WC
    c.clear_listings()
    # Mighty Chain Pants (green armor, vendor pays 1221c) listed with two random suffixes; Linen Cloth (not gear) at 12c
    c.set_listings(4800, [{"unit": 400, "qty": 1, "sfx": 1201}, {"unit": 1500, "qty": 1, "sfx": 1202}], commodity=False)
    c.set_listings(2589, [(12, 1), (13, 100)])
    c.open_ah()
    c.advance(1)
    auctionator_scan_ah(c)
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(4800) and got[4800][1:4], ("est", None, 821.0), "Mighty Chain Pants from Auctionator: estimate, 1221 - 400")
    # the cheap Linen is bought before the check
    c.set_listings(2589, [(13, 100)])
    ok, _ = start_scan(c, "flips")
    ctx.require(ok and not WC.Scanner.active, "the flips check did not run")
    r = WC.Scanner.results[4800]
    ctx.require(r is not None, "Mighty Chain Pants was not searched")
    ctx.eq(str(r.status), "none", "(the search without a suffix finds nothing in this mock)")
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(4800) and got[4800][1:4], ("est", None, 821.0), "gear: a search that found nothing does not make it 'gone'")
    ctx.eq(got.get(2589) and got[2589][1], "gone", "not gear: nothing below the vendor price any more -> gone")
    check_clean(ctx, c)


@scenario("flips_estimate", "flips: only Auctionator's prices (nothing checked) -> status 'est', profit = sell - cheapest for one unit")
def s_flips_est(ctx):
    c = ctx.client()
    WC = c.WC
    flip_market(c)
    auctionator_scan_ah(c, fire=False)
    # est profits = sell - min: Mighty Chain Pants 656, Silk 50, Mageweave 50 (tie -> itemID), Medium Leather 1, Linen 1
    got = [(i, s, q, p) for (i, s, q, p, _, _, _) in flip_dump(c)]
    ctx.eq(got, [(4800, "est", None, 656.0), (4306, "est", None, 50.0), (4338, "est", None, 50.0),
                 (2319, "est", None, 1.0), (2589, "est", None, 1.0)], "Profit:Flips() with Auctionator's prices only")
    c.slash("/wc flips")
    t = " ".join(c.texts(clip=True)).lower()
    ctx.check(("estimate" in t) if ctx.locale == "enUS" else ("估" in t), "estimate rows are not marked as an estimate on the flips tab")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
CRAFT_LISTINGS = {
    2840: [(50, 4), (60, 100)],      # Copper Bar
    2318: [(30, 10)],                # Light Leather
    2880: [(150, 20)],               # Weak Flux on the AH (vendor sells it for 100 -> vendor wins)
    3470: [(25, 5)],                 # Rough Grinding Stone
    7955: [(1500, 1)],               # Copper Claymore (product, gear)
    10938: [(300, 20)],              # Lesser Magic Essence
    10940: [(40, 50), (45, 500)],    # Strange Dust
    10939: [(900, 10)],              # Greater Magic Essence
    10978: [(600, 10)],              # Small Glimmering Shard
    10998: [(1000, 10)],             # Lesser Astral Essence
}


def craft_setup(ctx, c):
    WC = c.WC
    c.open_profession(164)            # Blacksmithing: the addon captures the recipes
    c.advance(3)
    c.close_profession()
    c.advance(1)
    ck = WC.CharKey(WC)
    recs = c.g("GetrichDB").recipes[ck]
    ctx.require(recs is not None and recs[9983] is not None, "Blacksmithing recipes were not captured (db.recipes[%s][9983])" % ck)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    c.set_bags({(0, 1): (2840, 3)})   # 3 Copper Bars already owned
    c.open_ah()
    c.advance(1)
    ok, secs = full_search(c, "craft", 900)
    ctx.require(ok, "the exact search of the crafting items did not start")
    c.advance(2)


@scenario("craft_profit", "craft scan + exact profits: vendor/AH mix, missing reagent, owned mats -> cash, Anvil recipes not hidden, DE route")
def s_craft(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    st = c.ah_stats()
    searched = set(st["searchByItem"].keys())
    ctx.check(2880 not in searched, "Weak Flux (unlimited vendor item) should not be searched by the craft scan")
    for iid in (2840, 2318, 3470, 7955, 10938, 10940):
        ctx.check(iid in searched, "craft scan did not search %d" % iid)
    P = WC.Profit

    def entry(rid):
        e = P.CraftEntry(P, rid)
        ctx.require(e is not None, "Profit:CraftEntry(%d) is nil" % rid)
        return e
    # Copper Claymore 9983: 1 Light Leather 30 + 10 Copper Bar (4x50 + 6x60 = 560) + 2 Weak Flux from the vendor 2x100 = 200
    #   + 1 Rough Grinding Stone 25 = 815. NPC 241 -> -574. AH 1500 x 0.95 = 1425 -> +610.
    #   DE (weapon q2 ilvl 11, band 5-15): LME 0.8 x 1.5 = 1.2 x 300 + SD 0.2 x 1.5 = 0.3 x 40 = 372 x 0.95 = 353.4 -> -461.6
    #   cash: 3 bars owned -> 7 bars 4x50 + 3x60 = 380, + 30 + 200 + 25 = 635. Needs an Anvil (not met) - still shown.
    e = entry(9983)
    ctx.eq(e.status, "ok", "9983 status")
    ctx.eq(fnum(e.cost), 815.0, "9983 cost")
    ctx.eq(fnum(e.npc), 241.0, "9983 npc")
    ctx.eq(fnum(e.npcProfit), -574.0, "9983 npcProfit")
    ctx.eq(fnum(e.ah), 1425.0, "9983 ah")
    ctx.eq(fnum(e.ahProfit), 610.0, "9983 ahProfit")
    ctx.eq(fnum(e.de), 353.4, "9983 de (estimate)", tol=1e-6)
    ctx.eq(fnum(e.deProfit), -461.6, "9983 deProfit", tol=1e-6)
    ctx.eq(fnum(e.best), 610.0, "9983 best")
    ctx.eq(e.bestKind, "ah", "9983 bestKind")
    ctx.eq(fnum(e.cash), 635.0, "9983 cash still needed (3 bars owned)")
    ctx.check(e.tool is not None and "Anvil" in str(e.tool), "9983 tool/station text should mention Anvil: %r" % e.tool)
    flux = [x for x in lua_list(e.reagents) if int(x.itemID) == 2880]
    ctx.check(flux and flux[0].source == "vendor" and fnum(flux[0].cost) == 200.0, "Weak Flux should come from the vendor (2 x 100): %r" % ((flux[0].source, flux[0].cost) if flux else None,))
    # Copper Bracers 2663: 2 bars = 100; NPC 17 -> -83; not on the AH; quality 1 -> no DE. Owned bars cover it: cash 0
    e = entry(2663)
    ctx.eq(fnum(e.cost), 100.0, "2663 cost")
    ctx.eq(fnum(e.npcProfit), -83.0, "2663 npcProfit")
    ctx.eq(e.ah, None, "2663 ah (not listed)")
    ctx.eq(e.de, None, "2663 de (common quality)")
    ctx.eq(fnum(e.best), -83.0, "2663 best")
    ctx.eq(fnum(e.cash), 0.0, "2663 cash (3 bars owned >= 2)")
    # Copper Axe 2738: Linen Cloth is not listed and no vendor sells it -> missing
    e = entry(2738)
    ctx.eq(e.status, "missing", "2738 status")
    ctx.eq(e.cost, None, "2738 cost")
    ctx.eq([int(x) for x in lua_list(e.missing)], [2589], "2738 missing reagents")
    # Copper Dagger 8880: 30 + 6 bars (4x50 + 2x60 = 320) + 100 + 25 = 475; NPC 194 -> -281; DE 353.4 -> -121.6 = best (de)
    e = entry(8880)
    ctx.eq(fnum(e.cost), 475.0, "8880 cost")
    ctx.eq(fnum(e.deProfit), -121.6, "8880 deProfit", tol=1e-6)
    ctx.eq(e.bestKind, "de", "8880 bestKind")
    # Heavy Copper Maul 7408: 2 leather 60 + 12 bars (4x50 + 8x60 = 680) + 2 flux 200 = 940.
    #   DE (weapon q2 ilvl 16, band 16-20): GME 0.75 x 1.5 = 1.125 x 900 = 1012.5, SD 0.2 x 2.5 = 0.5 x 40 = 20,
    #   SGS 0.05 x 1 x 600 = 30 -> 1062.5 x 0.95 = 1009.375 -> deProfit 69.375 (best); NPC 466 -> -474
    e = entry(7408)
    ctx.eq(fnum(e.cost), 940.0, "7408 cost")
    ctx.eq(fnum(e.de), 1009.375, "7408 de", tol=1e-6)
    ctx.eq(fnum(e.best), 69.375, "7408 best", tol=1e-6)
    ctx.eq(e.bestKind, "de", "7408 bestKind")
    # order: best desc, missing last
    lst = lua_list(first(P.Craft(P)))
    bests = [fnum(x.best) for x in lst if x.best is not None]
    ctx.check(bests == sorted(bests, reverse=True), "Profit:Craft() not sorted by best desc")
    st_list = [x.status for x in lst]
    if "missing" in st_list:
        ctx.check(all(s == "missing" for s in st_list[st_list.index("missing"):]), "missing recipes should be last")
    # Getrich regression: prices do not expire after an hour
    c.set_server_time(c.server_time() + 2 * 3600)
    WC.Fire(WC, "SETTINGS_CHANGED", "test")
    e = entry(9983)
    ctx.eq(fnum(e.best), 610.0, "9983 best 2 hours later (no 1-hour freshness cut-off)")
    ctx.eq(WC.UnitPrice(WC, 2840)[0], 50, "UnitPrice(Copper Bar) 2 hours later")
    # crafted gear in the Disenchant list (Enchanting): Copper Claymore costs 815 to make -> gain 353.4 - 815 = -461.6
    de = [x for x in lua_list(first(P.Disenchant(P))) if x.source == "craft" and int(x.itemID) == 7955]
    ctx.check(de, "Profit:Disenchant() has no 'craft' entry for Copper Claymore")
    if de:
        ctx.eq(fnum(de[0].buy), 815.0, "DE craft entry buy = craft cost")
        ctx.eq(fnum(de[0].gain), -461.6, "DE craft entry gain", tol=1e-6)
    # tab + shopping-list tooltip (reagents, vendor NPC for Weak Flux, cash still needed, station)
    c.slash("/wc craft")
    t = c.texts(clip=True)
    ctx.check(any("Copper Claymore" in x for x in t), "craft tab does not list Copper Claymore")
    ctx.check(any(ctx.money(610) in x for x in t), "craft tab does not show the AH profit %s" % ctx.money(610))
    c.hover_text("Copper Claymore")        # the first hover may ask the client for item names it has not cached yet
    c.advance(1)
    tip = c.hover_text("Copper Claymore")
    joined = "\n".join(tip)
    for need in ("Light Leather", "Copper Bar", "Weak Flux", "Rough Grinding Stone", "Anvil", ctx.money(635), ctx.money(815)):
        ctx.check(need in joined, "Copper Claymore tooltip lacks %r:\n%s" % (need, joined))
    npc = c.eval("local WC = ...; local p, info = WC:VendorPrice(2880); return info and info.npc", WC)
    ctx.check(npc and npc in joined, "tooltip does not name the vendor NPC for Weak Flux (%s)" % npc)
    # a merchant selling Copper Bar for 30c (unlimited) -> VENDOR_UPDATED -> Copper Bracers = 2 x 30 = 60 from the vendor
    c.open_merchant(990002, "Test Smith", [{"itemID": 2840, "price": 30, "stackCount": 1}], zone="Orgrimmar", map_id=1454, x=0.3, y=0.4)
    c.advance(1); c.close_merchant(); c.advance(0.5)
    e = entry(2663)
    ctx.eq(fnum(e.cost), 60.0, "Copper Bracers after a vendor sells Copper Bar at 30c")
    ctx.eq(lua_list(e.reagents)[0].source, "vendor", "Copper Bar source after the merchant visit")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
DE_PRICES = {10940: [(40, 50)], 10938: [(300, 20)], 10998: [(1000, 10)], 10978: [(600, 10)], 10939: [(900, 10)]}


def de_setup(c, scan=True):
    for iid, rows in DE_PRICES.items():
        c.set_listings(iid, rows)
    if scan:
        # Auctionator has scanned the whole Auction House (the gear on it comes from there); the tab's check then
        # searches the disenchanting materials exactly
        c.open_ah()
        c.advance(1)
        auctionator_scan_ah(c)
        c.advance(6)
        start_scan(c, "de", 600)
        c.advance(1)


def band_tuple(b):
    return None if b is None else (int(b.q), int(b["class"]), int(b.lo), int(b.hi))


@scenario("de_value", "disenchant bands + value (estimate) for uncommon/rare gear incl. new Forever IDs >= 240000; reasons; partial prices")
def s_de_value(ctx):
    c = ctx.client()
    WC = c.WC
    c.set_listings(241089, [(200, 1)])      # Scarlet Dagger on the AH (Auctionator's full scan sees it)
    de_setup(c)
    DE = WC.DE
    for iid in (1273, 241089, 250482, 11287, 142503, 2589, 2853):
        DE.Band(DE, iid)                    # first call may answer "loading" and ask the client for the item
    c.advance(1)
    # bands
    b, why = multi(DE.Band(DE, 1273))
    ctx.eq(band_tuple(b), (2, 4, 21, 25), "Band(Forest Chain q2 armor ilvl 25)")
    b, why = multi(DE.Band(DE, 241089))
    ctx.eq(band_tuple(b), (2, 2, 5, 15), "Band(Scarlet Dagger 241089, q2 weapon ilvl 10) - Forever item ID >= 240000")
    b, why = multi(DE.Band(DE, 250482))
    ctx.eq(band_tuple(b), (3, 4, 5, 15), "Band(Glowing Copper Boots 250482, rare armor ilvl 15) - new Forever rare band")
    b, why = multi(DE.Band(DE, 1273, 18))
    ctx.eq(band_tuple(b), (2, 4, 16, 20), "Band(1273, ilvl 18) uses the explicit item level")
    for iid, reason, what in ((11287, "nodisenchant", "Lesser Magic Wand (flag 0x8000)"), (142503, "notgear", "shirt (INVTYPE_BODY)"),
                              (2589, "notgear", "Linen Cloth"), (2853, "quality", "Copper Bracers (common)")):
        b, why = multi(DE.Band(DE, iid))
        ctx.eq((b, why), (None, reason), "Band(%d %s)" % (iid, what))
    c.add_item(999001, "Test Green Vest", quality=2, ilvl=22, classID=4, subclassID=1, equipLoc="INVTYPE_CHEST", sell=400, stack=1, cached=False)
    b, why = multi(DE.Band(DE, 999001))
    ctx.eq((b, why), (None, "loading"), "Band(uncached item)")
    c.advance(1)
    b, why = multi(DE.Band(DE, 999001))
    ctx.eq(band_tuple(b), (2, 4, 21, 25), "Band(item after it loaded)")
    # value: Forest Chain band 21-25 armor: SD 0.75 x 5 = 3.75 x 40 = 150; LAE 0.15 x 1.5 = 0.225 x 1000 = 225;
    #   SGS 0.10 x 1 x 600 = 60 -> 435 x 0.95 = 413.25
    v = DE.Value(DE, 1273)
    ctx.require(v is not None, "DE:Value(1273) is nil")
    ctx.eq(fnum(v.value), 413.25, "Value(Forest Chain)")
    parts = {int(p.itemID if p.itemID else p[1]): fnum(p.qty if p.qty is not None else p[2]) for p in lua_list(v.parts)}
    ctx.eq({k: round(v, 9) for k, v in parts.items()}, {10940: 3.75, 10998: 0.225, 10978: 0.1}, "Value(1273).parts expected qty per cast")
    ctx.eq(bool(v.measured), False, "Value(1273).measured")
    ctx.eq(bool(v.partial), False, "Value(1273).partial")
    ctx.eq(bool(v.skillOK), True, "Value(1273).skillOK (Enchanting 150 >= band skill)")
    # Scarlet Dagger (weapon 5-15): LME 0.8 x 1.5 = 1.2 x 300 = 360 + SD 0.2 x 1.5 = 0.3 x 40 = 12 -> 372 x 0.95 = 353.4
    ctx.eq(fnum(DE.Value(DE, 241089).value), 353.4, "Value(Scarlet Dagger 241089)")
    # Glowing Copper Boots (rare 5-15, nearest Classic band): SGS 1 x 600 x 0.95 = 570
    ctx.eq(fnum(DE.Value(DE, 250482).value), 570.0, "Value(Glowing Copper Boots 250482, rare)")
    # AH gear from Auctionator's full scan: Scarlet Dagger for 200 -> gain 353.4 - 200 = 153.4
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    ah = [e for e in lst if e.source == "ah" and int(e.itemID) == 241089]
    ctx.check(ah, "Profit:Disenchant() has no AH entry for Scarlet Dagger 241089 (new Forever ID refused?)")
    if ah:
        ctx.eq(fnum(ah[0].buy), 200.0, "DE AH entry buy")
        ctx.eq(fnum(ah[0].gain), 153.4, "DE AH entry gain = 353.4 - 200")
    # partial: Lesser Astral Essence price unknown -> value from the priced outputs only: (150 + 60) x 0.95 = 199.5
    db = c.g("GetrichDB")
    db.results[10998] = None
    c.eval("Auctionator.prices[10998] = nil")
    c.eval("local WC = ...; WC.External:Invalidate()", WC)
    WC.Fire(WC, "PRICES_UPDATED", "test")
    v = DE.Value(DE, 1273)
    ctx.eq([int(x) for x in lua_list(v.missing)], [10998], "Value(1273).missing without LAE price")
    ctx.eq(bool(v.partial), True, "Value(1273).partial without LAE price")
    ctx.eq(fnum(v.value), 199.5, "Value(1273) without LAE price")
    check_clean(ctx, c)


@scenario("de_tab_shows_outputs", "Getrich regression: the Disenchant tab shows what bag gear disenchants into and its value")
def s_de_tab(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c)
    c.set_bags({(0, 1): (1273, 1), (0, 2): (241089, 1)})
    c.advance(2)
    c.slash("/wc de")
    t = c.texts(clip=True)
    ctx.check(any("Forest Chain" in x for x in t), "Disenchant tab does not list Forest Chain from the bags: %s" % t[:30])
    ctx.check(any("Strange Dust" in x for x in t), "Disenchant tab does not say what it disenchants into (Strange Dust)")
    ctx.check(any(ctx.money(413.25) in x for x in t), "Disenchant tab does not show the DE value %s" % ctx.money(413.25))
    ctx.check(any("Scarlet Dagger" in x for x in t), "Disenchant tab does not list Scarlet Dagger (ID 241089)")
    tip = "\n".join(c.hover_text("Forest Chain"))
    for need in ("Strange Dust", "Lesser Astral Essence", "Small Glimmering Shard", ctx.money(413.25)):
        ctx.check(need in tip, "Forest Chain DE tooltip lacks %r:\n%s" % (need, tip))
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    bag = [e for e in lst if e.source == "bag" and int(e.itemID) == 1273]
    ctx.check(bag, "Profit:Disenchant() has no bag entry for Forest Chain")
    if bag:
        # gain for bag gear = DE value - vendor price = 413.25 - 1656 = -1242.75
        ctx.eq(fnum(bag[0].gain), -1242.75, "bag Forest Chain gain (DE value - vendor price)")
        ctx.eq(fnum(bag[0].sell), 1656.0, "bag Forest Chain sell")
    check_clean(ctx, c)


def do_de_casts(c, plan, interleave=None):
    """plan: list of (loot list, kwargs). interleave: {index: callable} run after cast index."""
    for i, (loot, kw) in enumerate(plan, 1):
        slot = c.find_bag_slot(1273)
        assert slot, "no Forest Chain left in the bags"
        c.disenchant(slot[0], slot[1], loot, **kw)
        if interleave and i in interleave:
            interleave[i]()


@scenario("de_sampling", "20 recorded disenchants switch the band to measured odds; mob loot / interrupted casts are ignored")
def s_de_samples(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=True)
    c.learn_disenchant()
    c.set_bags({(b, s): (1273, 1) for b in range(0, 2) for s in range(1, 13)})   # 24 Forest Chains
    plan = [([(10940, 4)], {})] * 15 + [([(10998, 2)], {})] * 3 + [([(10978, 1)], {})] + [([(10940, 4)], {})]
    for i in (12, 13):
        plan[i - 1] = (plan[i - 1][0], {"autoloot": True})
    inter = {
        5: lambda: c.loot_window([(10940, 7)]),                                            # mob corpse loot: not a DE
        # interrupted cast (no loot), then a mob corpse looted right away: neither counts
        10: lambda: (c.disenchant(*c.find_bag_slot(1273), [(10940, 9)], interrupt=True, run=False), c.advance(3.2), c.loot_window([(10998, 5)])),
    }
    do_de_casts(c, plan[:19], inter)
    band = first(WC.DE.Band(WC.DE, 1273))
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 19), "after 19 casts: still an estimate")
    do_de_casts(c, plan[19:])
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (True, 20), "after 20 casts: measured")
    # 16 casts x 4 Strange Dust = 64 -> 3.2 per cast, hit 16/20 = 0.8; 3 x 2 LAE = 6 -> 0.3, 0.15; 1 SGS -> 0.05, 0.05
    got = {int(e.itemID): (round(fnum(e.qty), 6), round(fnum(e.chance), 6)) for e in lua_list(lst)}
    ctx.eq(got, {10940: (3.2, 0.8), 10998: (0.3, 0.15), 10978: (0.05, 0.05)}, "measured Expected()")
    rec = c.g("GetrichDB").deSamples["2:4:21-25"]
    ctx.require(rec is not None, "db.deSamples['2:4:21-25'] missing; keys: %s" % lua_keys(c.g("GetrichDB").deSamples))
    ctx.eq(int(rec.casts), 20, "deSamples casts")
    ctx.eq({int(k): int(rec.qty[k]) for k in lua_keys(rec.qty)}, {10940: 64, 10998: 6, 10978: 1}, "deSamples qty totals")
    ctx.eq({int(k): int(rec.hit[k]) for k in lua_keys(rec.hit)}, {10940: 16, 10998: 3, 10978: 1}, "deSamples casts containing")
    # measured value: (3.2 x 40 + 0.3 x 1000 + 0.05 x 600) x 0.95 = 458 x 0.95 = 435.1
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 435.1, "Value(Forest Chain) with measured odds")
    check_clean(ctx, c)


@scenario("de_sampling_event_order", "disenchant samples are recorded when LOOT_READY arrives before UNIT_SPELLCAST_SUCCEEDED")
def s_de_order(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=False)
    c.learn_disenchant()
    c.set_bags({(0, s): (1273, 1) for s in range(1, 4)})
    do_de_casts(c, [([(10940, 5)], {"order": "loot-first"}), ([(10998, 1)], {"order": "loot-first"}), ([(10940, 4)], {})])
    rec = c.g("GetrichDB").deSamples["2:4:21-25"]
    ctx.require(rec is not None, "no samples recorded")
    ctx.eq(int(rec.casts), 3, "casts recorded")
    ctx.eq({int(k): int(rec.qty[k]) for k in lua_keys(rec.qty)}, {10940: 9, 10998: 1}, "qty totals")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("history_hourly", "history: one record per hour (overwrite), only relevant items, scans record history")
def s_hist(ctx):
    c = ctx.client()
    WC = c.WC
    S = WC.Store
    S.SetWatch(S, 2589, True)
    t0 = c.server_time()
    H = t0 // 3600
    ctx.check(S.RecordHistory(S, 2589, 100, 5, t0), "RecordHistory(watched item) returned false")
    S.RecordHistory(S, 2589, 90, 7, H * 3600 + 3599)            # same hour -> overwrite
    S.RecordHistory(S, 2589, 95, 6, (H + 1) * 3600 + 10)        # next hour
    h = c.g("GetrichDB").history[2589].h
    ctx.eq({int(k): (int(h[k].min), int(h[k].qty)) for k in lua_keys(h)}, {H: (90, 7), H + 1: (95, 6)}, "hourly records")
    c.add_item(999002, "Irrelevant Trinket", classID=15, stack=1)
    ctx.check(not S.RecordHistory(S, 999002, 50, 1, t0), "history recorded for an item that is not relevant")
    ctx.eq(c.g("GetrichDB").history[999002], None, "no history for an irrelevant item")
    hist = lua_list(S.History(S, 2589))
    ctx.eq([(int(x.t), int(x.min)) for x in hist], [(H * 3600, 90), ((H + 1) * 3600, 95)], "Store:History(2589)")
    # a watched-items scan records the hour's cheapest price; a second scan in the same hour overwrites it
    c.set_listings(2589, [(12, 100)])
    c.open_ah(); c.advance(1)
    start_scan(c, "history", 60)
    H2 = c.server_time() // 3600
    rec = c.g("GetrichDB").history[2589].h[H2]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (12, 100), "history written by the scan")
    c.set_listings(2589, [(11, 50)])
    start_scan(c, "history", 60)
    rec = c.g("GetrichDB").history[2589].h[c.server_time() // 3600]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (11, 50), "second scan in the same hour overwrites")
    # Prices tab lists the watched item
    c.slash("/wc history")
    ctx.check(any("Linen Cloth" in x for x in c.texts(clip=True)), "Prices tab does not list the watched Linen Cloth")
    check_clean(ctx, c)


@scenario("history_compression", "hourly records older than 30 days fold into daily {lo, avg, hi, n} on load, merged into an existing day")
def s_hist_compress(ctx):
    H0 = SERVER_TIME0 // 3600
    D = (H0 - 800) // 24              # a day well past the 30-day (720 h) window
    D2 = D - 1
    sv = """GetrichDB = { resultsFormat = 3, watch = { [2589] = true }, history = { [2589] = {
      h = { [%d] = { min = 100, qty = 1 }, [%d] = { min = 80, qty = 2 }, [%d] = { min = 120, qty = 3 },
            [%d] = { min = 90, qty = 4 }, [%d] = { min = 77, qty = 5 } },
      d = { [%d] = { lo = 50, avg = 60, hi = 70, n = 2 } } } } }""" % (D * 24 + 1, D * 24 + 5, D * 24 + 9, D2 * 24 + 3, H0 - 10, D2)
    c = ctx.client(sv=sv)
    rec = c.g("GetrichDB").history[2589]
    ctx.require(rec is not None, "history[2589] gone after load")
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), [H0 - 10], "hourly records kept (only the recent one)")
    d = {int(k): (fnum(rec.d[k].lo), round(fnum(rec.d[k].avg), 6), fnum(rec.d[k].hi), int(rec.d[k].n)) for k in lua_keys(rec.d)}
    # day D: 100, 80, 120 -> lo 80, avg 100, hi 120, n 3
    # day D2: existing {50, 60, 70, n 2} + hour 90 -> lo 50, avg (60 x 2 + 90) / 3 = 70, hi 90, n 3
    ctx.eq(d, {D: (80.0, 100.0, 120.0, 3), D2: (50.0, 70.0, 90.0, 3)}, "daily records")
    hist = lua_list(c.WC.Store.History(c.WC.Store, 2589))
    ctx.eq([(int(x.t), bool(x.daily), int(x.min)) for x in hist],
           [(D2 * 86400, True, 70), (D * 86400, True, 100), ((H0 - 10) * 3600, False, 77)], "Store:History() sorted, daily flagged")
    c.slash("/wc history")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
def fixture_merchant(npc_id):
    for m in json.load(open(os.path.join(FIX, "merchants.json")))["merchants"]:
        if m["npcID"] == npc_id:
            return m
    raise KeyError(npc_id)


@scenario("merchant_capture", "merchant window -> db.vendorObs (unit price, bundle, npc, zone, x/y 0-100), cheapest unlimited offer, VendorPrice sources")
def s_merchant(ctx):
    c = ctx.client()
    WC = c.WC
    m = fixture_merchant(4615)        # Katrina Alliestar, Undercity (real scan from the user's client)
    c.open_merchant(m["npcID"], m["name"], m["offers"], zone=m["zone"], map_id=m["map"], x=m["x"], y=m["y"])
    c.advance(1)
    c.close_merchant()
    obs = c.g("GetrichDB").vendorObs
    o = obs[3372]                      # Leaded Vial: 200c per 5 -> 40c each
    ctx.require(o is not None, "vendorObs[3372] (Leaded Vial) not recorded; keys %s" % sorted(int(k) for k in lua_keys(obs))[:10])
    ctx.eq((int(o.price), int(o.bundle), int(o.npc), o.name, o.zone, int(o.map)), (40, 5, 4615, "Katrina Alliestar", "Undercity", 1458), "vendorObs[3372]")
    ctx.eq(fnum(o.x), m["x"] * 100, "vendorObs x (0-100, 0.1 precision)", tol=0.051)
    ctx.eq(fnum(o.y), m["y"] * 100, "vendorObs y (0-100, 0.1 precision)", tol=0.051)
    ctx.eq(bool(o.limited), False, "vendorObs limited")
    ctx.eq(o.faction, "Horde", "vendorObs faction")
    p, info = WC.VendorPrice(WC, 3372)
    ctx.eq(p, 40, "VendorPrice(3372)")
    ctx.eq((info.source, info.npc, int(info.bundle)), ("seen", "Katrina Alliestar", 5), "VendorPrice(3372) info")
    o = obs[8925]
    ctx.eq(o and int(o.price), 500, "Crystal Vial 2500 per 5 -> 500")
    # limited vs unlimited: Kithas sells Lesser Magic Essence limited (1 left) for 800; another vendor unlimited for 1000
    c.open_merchant(3346, "Kithas", [{"itemID": 10938, "price": 800, "stackCount": 1, "numAvailable": 1}], zone="Orgrimmar", map_id=1454, x=0.5377, y=0.3829)
    c.advance(1); c.close_merchant()
    o = obs[10938]
    ctx.eq(o and (int(o.price), bool(o.limited)), (800, True), "only a limited offer known -> kept")
    c.open_merchant(990001, "Test Supplier", [{"itemID": 10938, "price": 1000, "stackCount": 1},
                                              {"itemID": 249496, "price": 0, "stackCount": 1, "hasExtendedCost": True},
                                              {"itemID": 2320, "price": 10, "stackCount": 1, "isPurchasable": False}],
                    zone="Orgrimmar", map_id=1454, x=0.4, y=0.6)
    c.advance(1); c.close_merchant()
    o = obs[10938]
    ctx.eq(o and (int(o.price), bool(o.limited), int(o.npc)), (1000, False, 990001), "cheapest UNLIMITED offer wins over a cheaper limited one")
    ctx.eq(obs[249496], None, "extended-cost (currency) offer skipped")
    ctx.eq(obs[2320], None, "non-purchasable offer skipped")
    # item never seen by this character: from the built-in data
    p, info = WC.VendorPrice(WC, 2880)
    ctx.eq((p, info and info.source), (100, "data"), "VendorPrice(Weak Flux) from WC.VENDOR")
    ctx.eq(WC.VendorPrice(WC, 1273), None, "VendorPrice(gear nobody sells) is nil")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("profession_capture", "recipes captured from the open profession (learned only, wholesale replace, linked skipped, interrupted capture)")
def s_prof(ctx):
    c = ctx.client()
    WC = c.WC
    fx = json.load(open(os.path.join(FIX, "recipes.json")))["chars"][DEFAULT_CHAR]["recipes"]
    bs = {int(k) for k, r in fx.items() if r["skillLine"] == 164 and r["learned"]}
    en = {int(k) for k, r in fx.items() if r["skillLine"] == 333 and r["learned"]}
    c.open_profession(164)
    c.advance(3)
    ck = WC.CharKey(WC)
    ctx.eq(ck, DEFAULT_CHAR, "WC:CharKey() = player GUID")
    db = c.g("GetrichDB")
    recs = db.recipes[ck]
    ctx.require(recs is not None, "db.recipes[charKey] missing")
    got = {int(k) for k in lua_keys(recs)}
    ctx.eq(got, bs, "captured Blacksmithing recipes")
    r = recs[9983]
    ctx.eq((r.n, int(r.p), int(r.o), int(r.y1), int(r.y2)), ("Copper Claymore", 164, 7955, 1, 1), "recipe 9983 fields")
    ctx.eq([[int(x[1]), int(x[2])] for x in lua_list(r.r)], [[2318, 1], [2840, 10], [2880, 2], [3470, 1]], "recipe 9983 reagents")
    ctx.check(r.tool is not None and "Anvil" in str(r.tool), "recipe 9983 tool text: %r" % r.tool)
    ctx.eq(recs[3115].tool, None, "Rough Weightstone has no tool")
    prof = db.chars[ck].profs
    ctx.eq(sorted(int(k) for k in lua_keys(prof)), [129, 164, 185, 333, 356], "db.chars profs (identified by skillLine)")
    ctx.eq((prof[164].name, int(prof[164].rank), int(prof[164].max)), ("Blacksmithing", 150, 225), "profs[164]")
    ctx.eq(WC.EnchantingSkill(WC), 150, "WC:EnchantingSkill()")
    per_frame = max([int(v) for v in c.M.tsStats.frames.values()] or [0])
    ctx.check(per_frame <= 25, "GetRecipeSchematic called %d times in one frame (spec: <= 25 recipes per frame)" % per_frame)
    # second profession keeps the first
    c.open_profession(333)
    c.advance(3)
    got = {int(k) for k in lua_keys(db.recipes[ck])}
    ctx.eq(got, bs | en, "Blacksmithing + Enchanting recipes")
    wrongp = [int(k) for k in lua_keys(db.recipes[ck]) if int(db.recipes[ck][k].p) != fx[str(int(k))]["skillLine"]]
    ctx.check(not wrongp, "recipes stored under the wrong profession: %s" % wrongp[:8])
    ids = c.WC.Recipes.AllItemIDs(c.WC.Recipes)
    ctx.check(ids[7955] and ids[2840], "Recipes:AllItemIDs() lacks 7955 / 2840")
    # unlearned recipe disappears after the next complete capture
    recipes = {int(k): dict(v) for k, v in fx.items()}
    recipes[2663]["learned"] = False
    c.set_recipes(recipes)
    c.open_profession(164)
    c.advance(3)
    ctx.eq(db.recipes[ck][2663], None, "unlearned recipe removed on recapture")
    ctx.check(db.recipes[ck][9983] is not None, "other recipes kept on recapture")
    # a linked (other player's) profession is never captured
    recipes[777001] = {"name": "Linked Recipe", "skillLine": 164, "output": 2853, "reagents": [[2840, 1]], "learned": True}
    c.set_recipes(recipes)
    c.M.TS.linked = True
    c.open_profession(164)
    c.advance(3)
    c.M.TS.linked = False
    ctx.eq(db.recipes[ck][777001], None, "linked profession captured")
    # switching profession while a capture runs: nothing ends up under the wrong profession
    c.open_profession(164, ready_delay=0.1)
    c.advance(0.15)
    c.open_profession(333, ready_delay=0.1)
    c.advance(3)
    wrongp = [int(k) for k in lua_keys(db.recipes[ck]) if fx.get(str(int(k))) and int(db.recipes[ck][k].p) != fx[str(int(k))]["skillLine"]]
    ctx.check(not wrongp, "interrupted capture stored recipes under the wrong profession: %s" % wrongp[:8])
    ctx.check(db.recipes[ck][9983] is not None and db.recipes[ck][7426] is not None, "recipes lost after switching professions mid-capture")
    check_clean(ctx, c)


@scenario("profession_overlay", "profit label on ProfessionsFrame recipe rows (reused font strings, refresh on price change)")
def s_overlay(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    c.open_profession(164)
    c.advance(2)

    def label_of(rid):
        sb = c.eval("return ProfessionsFrame.CraftingPage.RecipeList.ScrollBox")
        idx = c.eval("""local sb, rid = ...
          for i, n in ipairs(sb:GetDataProvider():Flatten()) do local d = n:GetData(); if d.recipeInfo and d.recipeInfo.recipeID == rid then return i end end""", sb, rid)
        if idx is None:
            return None, None
        sb.ScrollToElementDataIndex(sb, idx)
        for fr, r in c.recipe_rows():
            if r == rid:
                texts = [(fs._text, fs) for fs in c.regions(fr, "FontString") if fs._where and fs._text]
                return fr, [t for t, _ in texts]
        return None, None
    fr, t = label_of(9983)
    ctx.require(fr is not None, "recipe 9983 row not found in ProfessionsFrame")
    ctx.check(t and any(ctx.money(610) in _strip(x) for x in t), "Copper Claymore row label should show +%s, got %s" % (ctx.money(610), t))
    fr, t = label_of(2663)
    ctx.check(t and any(ctx.money(-83).lstrip("-") in _strip(x) for x in t), "Copper Bracers row label should show the -83c loss, got %s" % t)
    fr, t = label_of(2738)
    ctx.check(not t or all(_strip(x).strip() == "" for x in t), "Copper Axe (missing price) should have no profit label, got %s" % t)
    label_of(9983); label_of(2663)                 # warm the scroll box frame pool first
    n0 = c.addon_widget_count("FontString")
    for _ in range(5):
        WC.Fire(WC, "PRICES_UPDATED", "test")
        c.advance(0.5)
        label_of(9983); label_of(2663)
    n1 = c.addon_widget_count("FontString")
    ctx.check(n1 - n0 <= 2, "profession overlay keeps creating font strings: +%d after 5 refreshes" % (n1 - n0))
    # a price change shows up after PRICES_UPDATED: Claymore now sells for 2000 -> 2000 x 0.95 - 815 = 1085
    c.set_listings(7955, [(2000, 1)])
    c.ah_blizzard_search(7955)    # (the addon only learns prices from its own scans; rescan the product)
    c.advance(1)
    WC.Store.SetWatch(WC.Store, 7955, True)
    start_scan(c, "history", 60)
    c.advance(1)
    fr, t = label_of(9983)
    ctx.check(t and any(ctx.money(1085) in _strip(x) for x in t), "label not refreshed after a new price: %s" % t)
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("ah_row_tint", "Blizzard AH rows cheaper than the vendor price get a 'vendor +X' label (browse, commodity and item lists)")
def s_tint(ctx):
    c = ctx.client()
    c.set_listings(4306, [(100, 5), (160, 200)])     # Silk Cloth, sell 150
    c.set_listings(1273, [(1000, 1), (2000, 1)])     # Forest Chain, sell 1656
    c.set_listings(2592, [(40, 20)])                 # Wool Cloth, sell 33
    c.open_ah()
    c.advance(1)

    def labels(fr):
        out = [_strip(fs._text) for fs in c.regions(fr, "FontString") if fs._where and fs._text and _strip(fs._text).strip()]
        tints = [t for t in c.regions(fr, "Texture") if t._where]
        if out:
            ctx.check(tints, "tinted row has a label but no visible tint texture")
        else:
            ctx.check(not tints, "untinted row still shows a tint texture")
        return out
    c.ah_blizzard_browse("")
    c.advance(2)
    c.ah_show_browse()
    c.advance(0.5)
    rows = {int(rd.itemKey.itemID): labels(fr) for fr, rd in c.ah_rows("browse")}
    ctx.eq(sorted(rows), [1273, 2592, 4306], "browse rows shown")
    ctx.check(any(ctx.money(50) in x for x in rows.get(4306, [])), "Silk browse row (100 < 150) should say +%s: %s" % (ctx.money(50), rows.get(4306)))
    ctx.check(any(ctx.money(656) in x for x in rows.get(1273, [])), "Forest Chain browse row (1000 < 1656) should say +%s: %s" % (ctx.money(656), rows.get(1273)))
    ctx.check(not rows.get(2592), "Wool row (40 > 33) should have no vendor label: %s" % rows.get(2592))
    c.ah_blizzard_search(4306)
    c.advance(1)
    c.ah_show_commodity(4306)
    c.advance(0.5)
    rows = [(int(rd.unitPrice), labels(fr)) for fr, rd in c.ah_rows("commodity")]
    ctx.eq([u for u, _ in rows], [100, 160], "commodity rows")
    ctx.check(rows and any(ctx.money(50) in x for x in rows[0][1]), "commodity row at 100 should say +50c: %s" % rows[:1])
    ctx.check(len(rows) > 1 and not rows[1][1], "commodity row at 160 should have no label: %s" % rows[1:])
    c.ah_blizzard_search(1273)
    c.advance(1)
    c.ah_show_item(1273)
    c.advance(0.5)
    rows = [(int(rd.buyoutAmount), labels(fr)) for fr, rd in c.ah_rows("item")]
    ctx.eq([u for u, _ in rows], [1000, 2000], "item rows")
    ctx.check(rows and any(ctx.money(656) in x for x in rows[0][1]), "item row at 1000 should say +6s 56c: %s" % rows[:1])
    ctx.check(len(rows) > 1 and not rows[1][1], "item row at 2000 should have no label: %s" % rows[1:])
    st = c.ah_stats()
    ctx.eq(st["searches"] + st["browses"] - st["blizzard"], 0, "the row tint must not send AH queries of its own")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------

@scenario("idle_progress_sound", "opening the AH searches nothing; a check shows round + elapsed time, chat + sound when done; nothing else runs when idle")
def s_idle(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    setup_market_130(c)
    auctionator_scan_ah(c, fire=False)                 # Auctionator's prices from an earlier session
    chat0 = len(c.chat)
    c.open_ah()
    c.advance(30)
    st = c.ah_stats()
    ctx.check(not WC.Scanner.active and st["searches"] == 0 and st["browses"] == 0,
              "opening the Auction House must not send a query (since 2026.11.2 nothing is scanned): %s" % st)
    ctx.eq(len(c.chat), chat0, "nothing to say in the chat when the prices are there: %s" % c.chat[chat0:])
    # with the AH open the only thing that runs is the look at Auctionator's prices every 5 seconds
    idle = c.idle_report()
    only_look = lambda timers: (len(timers) == 1 and timers[0][0] == "C_Timer.NewTicker" and timers[0][1] <= 5.0
                                and WC.External.ticker is not None)
    ctx.check(only_look(idle["timers"]), "with the AH open only External's 5 s look should be pending: %s" % idle["timers"])
    ctx.check(not idle["onupdate"], "OnUpdate scripts running while idle (window open): %s" % idle["onupdate"])
    ctx.check(not idle["animations"], "animations playing while idle: %s" % idle["animations"])
    t = " ".join(c.texts())
    ctx.check("Auctionator" in t, "the idle bar does not say where the prices are from: %s" % [x for x in c.texts() if "ago" in x or "前" in x][:5])
    # the check button of the crates tab
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.require(ok, "the crates check did not start")
    c.advance(6)
    ctx.check(WC.Scanner.active, "the check should still be running after 6 s")
    t = c.texts()
    ctx.check(any(re.search(r"\b[67]s\b", x) or re.search(r"\b0:0[67]\b", x) or re.search(r"[67] ?秒", x) for x in t),
              "elapsed time (~6s) not visible while checking: %s" % [x for x in t if re.search(r"\d", x)][:8])
    ctx.check(any(str(WC.L.SCAN_PH_QUICK) % 5 in x for x in t), "the bar does not say what is being checked ('the best 5'): %s" % [x for x in t if re.search(r"\d", x)][:8])
    chat0 = len(c.chat)
    c.advance(400, until=lambda: not WC.Scanner.active)
    ctx.check(not WC.Scanner.active, "the crates check did not finish")
    ctx.check(len(c.chat) > chat0, "no chat line when the check finished")
    ctx.check(len(c.sounds) >= 1, "no sound when the check finished (db.soundOnDone)")
    c.advance(2)
    idle = c.idle_report()
    ctx.check(only_look(idle["timers"]), "timers pending after the check: %s" % idle["timers"])
    ctx.check(not idle["onupdate"], "OnUpdate scripts running after the check: %s" % idle["onupdate"])
    ctx.check(not idle["animations"], "animations playing after the check: %s" % idle["animations"])
    # writs
    c.slash("/wc writs")
    ok = WC.Scanner.Start(WC.Scanner, "writs")
    ctx.require(ok, "the writs check did not start")
    c.advance(3)
    ctx.check(any(str(WC.L.SCAN_PH_QUICK) % 5 in x for x in c.texts()), "the bar does not say what is being checked during the writs check")
    c.advance(900, until=lambda: not WC.Scanner.active)
    c.g("GetrichDB").soundOnDone = False
    n = len(c.sounds)
    ok, _ = start_scan(c, "crates", 400)
    ctx.check(ok, "the second crates check did not start")
    ctx.eq(len(c.sounds), n, "sound played although soundOnDone = false")
    c.close_ah()
    c.advance(3)
    frame = c.g("GetrichFrame")
    ctx.check(not frame.IsVisible(frame), "window still shown after the AH closed (1.3.0 behaviour: hide with the AH)")
    idle = c.idle_report()
    ctx.check(not idle["timers"] and not idle["onupdate"] and not idle["animations"], "work while idle after AH close: %s" % idle)
    c.slash("/wc")
    c.advance(5)
    idle = c.idle_report()
    ctx.check(not idle["onupdate"] and not idle["timers"], "window opened with /wc runs work while idle: %s" % idle)
    check_clean(ctx, c)



@scenario("ah_closed_mid_scan", "closing the AH stops the check, keeps what was searched, hides the window, leaves no timers")
def s_close(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    setup_market_130(c)
    auctionator_scan_ah(c, fire=False)
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.require(ok, "the crates check did not start")
    c.advance(6)
    ctx.check(WC.Scanner.active, "check not running 6 s after it started")
    c.close_ah()
    c.advance(5)
    ctx.check(not WC.Scanner.active, "scanner still active after AH close")
    frame = c.g("GetrichFrame")
    ctx.check(not frame.IsVisible(frame), "window still visible after AH close")
    n = sum(1 for k in lua_keys(c.g("GetrichDB").results))
    ctx.check(n >= 3, "results from before the close were dropped (%d left)" % n)
    ctx.check(not c.running_timers(), "timers left after AH close: %s" % c.running_timers())
    # the prices stay usable with the AH closed (they are Auctionator's)
    ctx.eq(ext_state(c), (True, None), "Auctionator's prices with the AH closed")
    check_clean(ctx, c)



@scenario("memory_and_widgets", "memory sanity with a price for every item of the built-in table; refreshing tabs creates no new widgets")
def s_mem(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    m0 = c.memory_kb()
    n_items = int(c.eval("local WC = ...; return #(WC.ItemTable())", WC))
    m_table = c.memory_kb()
    # a big Auction House: Auctionator has a price for every item of the built-in table, one in five of them below
    # what a vendor pays; the items the mock client knows are listed at that price. (The stand-in's own tables are
    # not Getrich's memory: the heap is measured again after they exist.)
    auctionator_update(c, {}, background=500000, fire=False)      # the crate and writ items: a full scan
    n_cheap = int(c.eval("""local WC = ...
      local ids, sell = WC.ItemTable()
      local A = Auctionator
      local cheap = 0
      for i = 1, #ids do
        local id = ids[i]
        local s = sell[id] or 0
        if s > 1 and i % 5 == 0 then A.prices[id] = { math.max(1, math.floor(s * 0.8)), 0 }; cheap = cheap + 1
        else A.prices[id] = { s * 3 + 100, 0 } end
      end
      return cheap""", WC))
    ctx.check(n_items > 7000 and n_cheap > 1000, "item table: %d items, %d cheap" % (n_items, n_cheap))
    known = int(c.eval("""local WC, M = ...
      local ids = WC.ItemTable()
      local n = 0
      for i = 1, #ids do
        local id = ids[i]
        if C_Item.GetItemInfoInstant(id) then
          M.AH.auctionSeq = M.AH.auctionSeq + 1
          M.AH.listings[id] = { rows = { { unit = Auctionator.prices[id][1], qty = 1 + i % 7, auctionID = M.AH.auctionSeq } } }
          n = n + 1
        end
      end
      return n""", WC, c.M))
    c.open_ah(); c.advance(1)
    m_mock = c.memory_kb()
    ctx.eq(ext_state(c), (True, None), "Auctionator's full scan is in use")
    flips, gear = [int(x) for x in multi(c.eval("""local WC = ...
      local f, g = WC.External:Lists()
      local nf, ng = 0, 0
      for _ in pairs(f) do nf = nf + 1 end
      for _ in pairs(g) do ng = ng + 1 end
      return nf, ng""", WC), 2)]
    ctx.check(flips >= n_cheap and gear > 500, "lists from the item table: %d flips (>= %d), %d gear" % (flips, n_cheap, gear))
    ok, secs = start_scan(c, "flips", 900)
    ctx.require(ok and not WC.Scanner.active, "the flips check did not finish")
    ctx.eq(c.ah_stats()["browses"], 0, "no browse query")
    m1 = c.memory_kb()
    for tab in TABS:
        c.slash("/wc " + tab)
    # one warm-up round: the first refresh after the item data arrived fills caches once (craft + disenchant lists
    # including the trainer recipes of the character's professions); a leak is growth on every round after that
    mw = c.memory_kb()
    for tab in TABS:
        c.slash("/wc " + tab)
        WC.Fire(WC, "PRICES_UPDATED", "test")
        c.advance(0.3)
    w1 = c.addon_widget_count()
    m2 = c.memory_kb()
    for _ in range(5):
        for tab in TABS:
            c.slash("/wc " + tab)
            WC.Fire(WC, "PRICES_UPDATED", "test")
            c.advance(0.3)
    w2 = c.addon_widget_count()
    m3 = c.memory_kb()
    # the price state is rebuilt (prices read again, the lists walked again) whenever Auctionator's prices change
    for _ in range(5):
        c.eval("local WC = ...; WC.External:Invalidate(); WC.External:Lists(); WC:Fire('PRICES_UPDATED', 'external')", WC)
        c.advance(0.3)
    m4 = c.memory_kb()
    ctx.log("memory KB: start %.0f, item table %.0f, with the stand-in's data %.0f, after lists + flip searches %.0f, all tabs opened %.0f, "
            "first refresh round %.0f, 5 more %.0f, 5 rebuilds %.0f; widgets %d -> %d; %d of %d items known to the mock"
            % (m0, m_table, m_mock, m1, mw, m2, m3, m4, w1, w2, known, n_items))
    ctx.note("Lua heap: item table of %d items +%.0f KB; a price for every one of them (%d flips, %d gear) +%.0f KB for the lists and %d searches; "
             "all tabs opened +%.0f KB; refresh rounds +%.0f KB, then +%.0f KB after 5 more and +%.0f KB after 5 rebuilds; %d addon widgets"
             % (n_items, m_table - m0, flips, gear, m1 - m_mock, c.ah_stats()["searches"], mw - m1, m2 - mw, m3 - m2, m4 - m3, w2))
    ctx.check(m_table - m0 < 1500, "decoding the item table grew the Lua heap by %.0f KB (> 1.5 MB)" % (m_table - m0))
    ctx.check(m1 - m_mock < 3000, "lists + flip searches grew the Lua heap by %.0f KB (> 3 MB)" % (m1 - m_mock))
    ctx.check(m2 - mw < 1500, "the first refresh round grew the Lua heap by %.0f KB" % (m2 - mw))
    ctx.check(m3 - m2 < 300, "5 refresh rounds grew the Lua heap by %.0f KB (leak?)" % (m3 - m2))
    ctx.check(m4 - m3 < 300, "5 rebuilds of the price state grew the Lua heap by %.0f KB (leak?)" % (m4 - m3))
    ctx.check(w2 - w1 <= 10, "refreshing tabs created %d new widgets" % (w2 - w1))
    check_clean(ctx, c)


@scenario("slash_commands", "/wc, /wc <tab>, /wc scan [tab] = /gr check [tab], /wc stop, /gr auc")
def s_slash(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    frame_shown = lambda: (c.g("GetrichFrame") is not None and c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")))
    c.slash("/wc")
    ctx.check(frame_shown(), "/wc did not open the window")
    c.slash("/wc")
    ctx.check(not frame_shown(), "/wc did not toggle the window closed")
    n = len(c.chat)
    c.slash("/wc scan")
    ctx.check(not WC.Scanner.active and len(c.chat) > n, "/wc scan with the AH closed should print a hint")
    setup_market_130(c)
    c.open_ah(); c.advance(1)
    # no prices from Auctionator yet: nothing to check, and the chat says what is missing
    n = len(c.chat)
    c.slash("/wc scan writs")
    ctx.check(not WC.Scanner.active, "/wc scan writs started without any prices")
    ctx.check(any("Auctionator" in str(x) for x in c.chat[n:]), "/wc scan without prices should say that Auctionator has no scan: %s" % c.chat[n:])
    auctionator_scan_ah(c)
    c.slash("/wc scan writs")
    ctx.check(WC.Scanner.active and WC.Scanner.kind == "writs", "/wc scan writs did not start a writs check")
    ctx.eq(c.g("GetrichDB").tab, "writs", "/wc scan writs selects the writs tab")
    c.advance(2)
    c.slash("/wc stop")
    ctx.check(not WC.Scanner.active, "/wc stop did not stop the check")
    c.slash("/gr crates")
    ctx.eq(c.g("GetrichDB").tab, "crates", "/gr crates")
    c.slash("/gr check writs")
    ctx.check(WC.Scanner.active and WC.Scanner.kind == "writs" and c.g("GetrichDB").tab == "writs", "/gr check writs (the name of /gr scan since 2026.11.2)")
    c.slash("/gr stop")
    ctx.check(not WC.Scanner.active, "/gr stop")
    n = len(c.chat)
    c.slash("/gr auc")
    ctx.check(any("Auctionator" in str(x) for x in c.chat[n:]), "/gr auc should describe the price source: %s" % c.chat[n:])
    check_clean(ctx, c)


@scenario("click_everything", "click every visible button and hover every widget on every tab (after data exists): no Lua errors")
def s_monkey(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    de_setup(c, scan=False)
    flip_market(c)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    start_scan(c, "flips", 300)
    c.set_bags({(0, 1): (1273, 1), (0, 2): (2840, 3)})
    c.WC.Store.SetWatch(c.WC.Store, 2589, True)
    clicked = 0
    for tab in TABS:
        c.slash("/wc " + tab)
        c.advance(0.2)
        for b in c.buttons():
            if not b.IsVisible(b) or not b._enabled:
                continue
            label = _strip(b.GetText(b) or "")
            if label and re.search(r"scan|stop|扫描|掃描|停止", label, re.I):
                continue
            c.hover(b)
            b.Click(b, "LeftButton")
            b.Click(b, "RightButton") if c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")) else None
            clicked += 1
            if not c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")):
                c.slash("/wc " + tab)
        for w in c.regions(None):
            if w._kind not in ("FontString", "Texture", "Line") and w._scripts.OnEnter is not None:
                c.hover(w)
    ctx.note("clicked %d buttons" % clicked)
    ctx.check(clicked >= 20, "only %d buttons found to click" % clicked)
    check_clean(ctx, c)


@scenario("savedvariables", "real 1.3.0 SV (format 2) upgrades keeping prices/settings; SV round-trip after scans; stable char key")
def s_sv(ctx):
    c = ctx.client(sv=REAL_SV)
    db = c.g("GetrichDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat upgraded 2 -> 3")
    r = db.results[2319]
    ctx.eq(r and (r.status, int(r.min), int(r.avail)), ("listed", 194, 8883), "results[2319] kept from the 1.3.0 SV")
    ctx.eq((db.onlyMine, db.tab), (True, "crates"), "1.3.0 settings kept")
    ctx.eq(db.autoScan, None, "autoScan (no setting since 2026.11.2: nothing is scanned) is dropped from the saved data")
    ctx.eq(db.soundOnDone, True, "new default soundOnDone added")
    cost = c.WC.CostFor(c.WC, 2319, 20)
    ctx.eq(cost[0], 194 * 20, "CostFor(2319, 20) from saved results (80 listed at 194c)")
    c.open_ah()
    c.advance(5)
    ctx.check(not c.WC.Scanner.active and c.ah_stats()["searches"] == 0, "opening the Auction House must not search anything")
    # round trip
    setup_market_130(c)
    search_exact(c, [2589, 2318])
    c.WC.Store.SetWatch(c.WC.Store, 2589, True)
    text = c.logout_sv()
    ctx.check("GetrichDB" in text, "logout produced no SavedVariables")
    c2 = ctx.client(sv=text)
    db2 = c2.g("GetrichDB")
    ctx.eq(db2.results[2589] and int(db2.results[2589].min), 10, "results survive a reload")
    ctx.check(db2.watch[2589], "watch list survives a reload")
    keys = " ".join(str(k) for k in lua_keys(db2))
    ctx.check("Beta" not in keys and "Classic" not in keys, "realm names used as DB keys (Getrich market-key split): %s" % keys)
    check_clean(ctx, c)
    check_clean(ctx, c2, "reloaded")


@scenario("char_key_stable", "Getrich regression (market key split): the character key is the same before and after PLAYER_LOGIN")
def s_charkey(ctx):
    c = ctx.client(login=False)
    k1 = c.WC.CharKey(c.WC)
    c.login()
    k2 = c.WC.CharKey(c.WC)
    ctx.eq(k1, k2, "WC:CharKey() before vs after login")
    ctx.eq(k2, DEFAULT_CHAR, "WC:CharKey() is the player GUID")
    check_clean(ctx, c)


@scenario("second_character", "the Tailoring + Enchanting character: capture, craft scan, no errors")
def s_char2(ctx):
    c = ctx.client(char=SECOND_CHAR)
    WC = c.WC
    c.load_orderbooks()
    for sl in (197, 333, 185, 129):
        c.open_profession(sl)
        c.advance(3)
    c.close_profession()
    recs = c.g("GetrichDB").recipes[SECOND_CHAR]
    fx = json.load(open(os.path.join(FIX, "recipes.json")))["chars"][SECOND_CHAR]["recipes"]
    exp = {int(k) for k, r in fx.items() if r["learned"] and r["skillLine"] in (197, 333, 185, 129)}
    ctx.eq({int(k) for k in lua_keys(recs)} if recs else set(), exp, "captured recipes of the second character")
    c.open_ah(); c.advance(1)
    ok, secs = full_search(c, "craft", 900)
    ctx.check(ok and not WC.Scanner.active, "the exact search of the crafting items did not finish")
    lst, counts = WC.Profit.Craft(WC.Profit)
    ctx.check(len(lua_list(lst)) > 20, "Profit:Craft() returned only %d entries" % len(lua_list(lst)))
    c.slash("/wc craft")
    c.slash("/wc de")
    check_clean(ctx, c)


# ===================================================================================================================
# round 2 (SPEC2: Getrich 2026.10.3) - settings that change behaviour, old SV wipe
# ===================================================================================================================
CODEX_SV_REAL = "/home/claude/brief/sv/Getrich.lua"            # the user's real old (Codex-built) Getrich SavedVariables
CODEX_SV_FIXTURE = os.path.join(FIX, "sv_getrich_codex.lua")    # trimmed, anonymized copy with the same schema


@scenario("old_getrich_sv_wiped", "SPEC2 0.1: the old Codex-built GetrichDB (schemaVersion + markets + characters) is wiped, nothing migrated")
def s_codex_wipe(ctx):
    path = CODEX_SV_REAL if os.path.exists(CODEX_SV_REAL) else CODEX_SV_FIXTURE
    ctx.note("old SV: " + path)
    c = ctx.client(sv=path)
    db = c.g("GetrichDB")
    ctx.require(db is not None, "GetrichDB missing after load")
    for k in ("schemaVersion", "markets", "characters", "vendor", "disenchant", "settings"):
        ctx.eq(db[k], None, "old key GetrichDB.%s after load" % k)
    ctx.eq(db.resultsFormat, 3, "resultsFormat")
    ctx.eq((db.tab, db.soundOnDone), ("crates", True), "defaults applied after the wipe")
    for k, v in (("historyDays", 30), ("pruneDays", 14), ("deMeasuredCasts", 20), ("flipCandidates", 80), ("quickTop", 5)):
        ctx.eq(db[k], v, "default %s" % k)
    ctx.eq(lua_keys(db.recipes), [], "no recipes migrated from the old SV")
    ctx.eq(lua_keys(db.vendorObs), [], "no merchant records migrated from the old SV")
    text = c.logout_sv()
    for word in ("schemaVersion", "markets", "observations", "normalizationComplete"):
        ctx.check(word not in text, "saved GetrichDB still contains the old '%s'" % word)
    # our own format is kept (a DB with resultsFormat is never wiped, even if it had a schemaVersion key)
    own = 'GetrichDB = { resultsFormat = 3, schemaVersion = 1, tab = "flips", watch = { [2589] = true } }'
    c2 = ctx.client(sv=own)
    db2 = c2.g("GetrichDB")
    ctx.eq((db2.tab, bool(db2.watch[2589])), ("flips", True), "a current-format GetrichDB is kept")
    check_clean(ctx, c)
    check_clean(ctx, c2, "current format")


def fire_setting(c, key, value):
    """Set a GetrichDB key the way the settings page does: write it, then fire SETTINGS_CHANGED(key)."""
    c.g("GetrichDB")[key] = value
    c.WC.Fire(c.WC, "SETTINGS_CHANGED", key)


@scenario("history_days_setting", "historyDays: hourly records older than N days fold into days on load and when the setting changes")
def s_history_days(ctx):
    H0 = SERVER_TIME0 // 3600
    h40, h20, h2 = H0 - 40 * 24 - 3, H0 - 20 * 24 - 3, H0 - 2 * 24
    sv = """GetrichDB = { resultsFormat = 3, watch = { [2589] = true }, historyDays = 30, history = { [2589] = {
      h = { [%d] = { min = 40, qty = 1 }, [%d] = { min = 20, qty = 2 }, [%d] = { min = 2, qty = 3 } }, d = {} } } }""" % (h40, h20, h2)
    c = ctx.client(sv=sv)
    rec = c.g("GetrichDB").history[2589]
    # historyDays 30: only the 40-day-old hour folds -> day (h40 // 24) = { lo 40, avg 40, hi 40, n 1 }
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), sorted([h20, h2]), "hourly records kept with historyDays = 30")
    ctx.eq({int(k): (fnum(rec.d[k].lo), fnum(rec.d[k].avg), fnum(rec.d[k].hi), int(rec.d[k].n)) for k in lua_keys(rec.d)},
           {h40 // 24: (40.0, 40.0, 40.0, 1)}, "daily records with historyDays = 30")
    fire_setting(c, "historyDays", 14)
    # 14 days: the 20-day-old hour folds too; the 2-day-old one stays
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), [h2], "hourly records kept after historyDays -> 14")
    ctx.eq(sorted(int(k) for k in lua_keys(rec.d)), sorted([h40 // 24, h20 // 24]), "daily records after historyDays -> 14")
    check_clean(ctx, c)



@scenario("prune_days_setting", "pruneDays: search results older than N days are dropped on load and when the setting changes; obsolete tables of older versions go")
def s_prune_days(ctx):
    t0 = SERVER_TIME0
    d = 86400
    sv = """GetrichDB = { resultsFormat = 3, pruneDays = 14, autoScan = false, useAuctionator = true, quickScan = true,
      results = { [2589] = { status = "listed", min = 10, avail = 5, time = %d, entries = { { 10, 5 } } },
                  [2318] = { status = "listed", min = 30, avail = 5, time = %d, entries = { { 30, 5 } } } },
      browse = { full = %d, items = { [2770] = { min = 5, qty = 20, t = %d }, [2771] = { min = 9, qty = 20, t = %d } } },
      markets = { ["Classic Beta PvP 2|Neutral"] = { results = { [2589] = { status = "listed", min = 11, avail = 5, time = %d, entries = { { 11, 5 } } } },
                                                     browse = { items = { [2770] = { min = 6, qty = 20, t = %d } } } } } }""" % (
        t0 - 20 * d, t0 - 5 * d, t0 - 2 * d, t0 - 20 * d, t0 - 2 * d, t0 - 2 * d, t0 - 2 * d)
    c = ctx.client(sv=sv)
    db = c.g("GetrichDB")
    # 14 days: the 20-day-old search result (Linen) is dropped
    ctx.eq(sorted(int(k) for k in lua_keys(db.results)), [2318], "results kept with pruneDays = 14")
    ctx.eq(first(c.WC.UnitPrice(c.WC, 2589)), None, "UnitPrice of a pruned item")
    # what Getrich's own scans kept until 2026.11.1 (the browse snapshot) and their switches are gone, in every house
    ctx.eq((db.browse, db.autoScan, db.useAuctionator, db.quickScan), (None, None, None, None), "obsolete keys of 2026.11.1 and older")
    park = db.markets["Classic Beta PvP 2|Neutral"]
    ctx.check(park.browse is None and park.results[2589] is not None, "a parked house: browse snapshot gone, search results kept")
    ctx.eq(first(c.WC.UnitPrice(c.WC, 2771)), None, "no price from the old browse snapshot")
    fire_setting(c, "pruneDays", 3)
    # 3 days: Light Leather (5 days) goes
    ctx.eq(sorted(int(k) for k in lua_keys(db.results)), [], "results kept after pruneDays -> 3")
    text = c.logout_sv()
    for word in ("browse", "autoScan", "useAuctionator", "quickScan"):
        ctx.check(word not in text, "the saved data still contains '%s'" % word)
    check_clean(ctx, c)



@scenario("flip_candidates_setting", "flipCandidates (40 / 80 / 150) limits how many cheap items the flips check searches, best first")
def s_flip_n(ctx):
    for n, expect in ((40, 40), (150, 60)):
        c = ctx.client()
        WC = c.WC
        c.clear_listings()
        # 60 items of the built-in table that a vendor buys for at least 1000c, each listed 10 x (i + 1) below that:
        # the gain per item (sell - cheapest) is 10 x (i + 1)
        t = c.eval("""local WC = ...
          local ids, sell = WC.ItemTable()
          local out = {}
          for i = 1, #ids do
            local id = ids[i]
            if #out < 60 and sell[id] >= 1000 and C_Item.GetItemInfoInstant(id) and WC.SellPrice(id) == sell[id] then out[#out + 1] = id end
          end
          return out""", WC)
        items = [int(x) for x in lua_list(t)]
        ctx.require(len(items) == 60, "60 table items known to the mock client (%d)" % len(items))
        sell = {i: int(c.eval("local WC, id = ...; return (select(2, WC.ItemTable()))[id]", WC, i)) for i in items}
        for k, iid in enumerate(items):
            c.set_listings(iid, [(sell[iid] - 10 * (k + 1), 1)])
        c.g("GetrichDB").flipCandidates = n
        c.open_ah(); c.advance(1)
        auctionator_scan_ah(c)
        ok, _ = start_scan(c, "flips", 900)
        ctx.require(ok and not WC.Scanner.active, "the flips check did not finish (flipCandidates %d)" % n)
        searched = set(c.ah_stats()["searchByItem"])
        # the biggest gains are the highest k: flipCandidates 40 -> k = 20..59; 150 -> all 60
        ctx.eq(searched, set(items[60 - expect:]), "items searched with flipCandidates = %d" % n)
        check_clean(ctx, c, "flipCandidates %d" % n)


@scenario("de_measured_casts_setting", "deMeasuredCasts: with 10, ten recorded disenchants switch the band to measured odds")
def s_de_measured_n(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=True)
    c.learn_disenchant()
    fire_setting(c, "deMeasuredCasts", 10)
    c.set_bags({(0, s): (1273, 1) for s in range(1, 13)})
    plan = [([(10940, 4)], {})] * 8 + [([(10998, 1)], {})] * 2
    do_de_casts(c, plan[:9])
    band = first(WC.DE.Band(WC.DE, 1273))
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 9), "after 9 casts with deMeasuredCasts = 10")
    do_de_casts(c, plan[9:])
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (True, 10), "after 10 casts with deMeasuredCasts = 10")
    # 8 x 4 Strange Dust = 32 -> 3.2 per cast (hit 0.8); 2 x 1 LAE -> 0.2 (hit 0.2)
    got = {int(e.itemID): (round(fnum(e.qty), 6), round(fnum(e.chance), 6)) for e in lua_list(lst)}
    ctx.eq(got, {10940: (3.2, 0.8), 10998: (0.2, 0.2)}, "measured Expected() with 10 casts")
    # (3.2 x 40 + 0.2 x 1000) x 0.95 = 328 x 0.95 = 311.6
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 311.6, "Value(Forest Chain) measured from 10 casts")
    fire_setting(c, "deMeasuredCasts", 20)
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 10), "back to the estimate after deMeasuredCasts -> 20")
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 413.25, "Value(Forest Chain) estimate again")
    check_clean(ctx, c)


SETTING_DEFAULTS = {   # SPEC2 5: every adjustable parameter and its default
    "soundOnDone": True, "chatOnDone": True, "ahTint": True, "profOverlay": True, "profLevelMark": True,
    "uiScale": 1.0, "dockToAH": True, "quickTop": 5,
    "onlyMine": False, "hideNoCrate": True, "hideNoMats": True, "perfRank": 0,
    "hideNoWrit": True, "hideNoItem": True, "hideDone": True, "diplomatRank": 0,
    "flipMinProfit": 0, "flipShowGone": False, "flipCandidates": 80,
    "craftOnlyProfit": False, "craftHideMissing": False, "craftShowUnlearned": False, "levelOffset": "best3", "levelTarget": "max",
    "deSource": "all", "deHideSkill": False, "deHideLoss": False, "deMeasuredCasts": 20,
    "historyRange": "7d", "historyDays": 30, "pruneDays": 14,
}
SETTING_CHOICES = {    # option lists the page must offer (SPEC2 5)
    "flipMinProfit": {0, 1000, 10000, 50000}, "flipCandidates": {40, 80, 150}, "deMeasuredCasts": {10, 20, 30, 50},
    "historyDays": {7, 14, 30, 60, 90}, "pruneDays": {3, 7, 14, 30}, "levelOffset": {"best3", "npcde", "none"},
    "levelTarget": {"max", 225, 300}, "perfRank": {0, 1, 2, 3}, "diplomatRank": {0, 1, 2, 3, 4, 5},
    "quickTop": {3, 5, 10, 20},
}


def db_settings(c):
    db = c.g("GetrichDB")
    out = {}
    for k in lua_keys(db):
        v = db[k]
        if isinstance(v, (bool, int, float, str)):
            out[k] = v
    return out


def listen_settings_changed(c):
    c.eval("local WC, M = ...; M.settingsFired = {}; WC:On('SETTINGS_CHANGED', function(key) M.settingsFired[#M.settingsFired + 1] = tostring(key) end)", c.WC, c.M)
    return lambda: [x for x in lua_list(c.M.settingsFired)]


def fill_data(c):
    """Something in every data table the settings page can clear."""
    db = c.g("GetrichDB")
    H = c.server_time() // 3600
    c.eval("""local db, H, t = ...
      db.watch[2589] = true
      db.history[2589] = { h = { [H] = { min = 10, qty = 5 } }, d = {} }
      db.results[2589] = { status = "listed", min = 10, avail = 5, time = t, entries = { { 10, 5 } } }
      db.scannedAt.crates = t
      db.extScans[db.market] = { t = t, ids = { 2589 } }
      db.deSamples["2:4:21-25"] = { casts = 3, qty = { [10940] = 12 }, hit = { [10940] = 3 }, min = {}, max = {} }
      db.vendorObs[3372] = { price = 40, bundle = 5, npc = 4615, name = "Katrina Alliestar", zone = "Undercity", limited = false, t = t }""",
           db, H, c.server_time())


def data_state(c):
    db = c.g("GetrichDB")
    return {"history": len(lua_keys(db.history)), "results": len(lua_keys(db.results)),
            "scannedAt": len(lua_keys(db.scannedAt)), "extScans": len(lua_keys(db.extScans)),
            "deSamples": len(lua_keys(db.deSamples)), "vendorObs": len(lua_keys(db.vendorObs))}


@scenario("settings_page", "SPEC2 5: Settings -> AddOns -> Getrich page: every control writes its key + fires SETTINGS_CHANGED, data buttons, about")
def s_settings(ctx):
    c = ctx.client()
    WC = c.WC
    db = c.g("GetrichDB")
    # defaults registered for every parameter
    for k, v in SETTING_DEFAULTS.items():
        got = db[k]
        ctx.check(got == v or (isinstance(v, float) and got is not None and abs(float(got) - v) < 1e-9),
                  "default GetrichDB.%s: expected %r, got %r" % (k, v, got))
    cats = [x for x in c.settings_categories() if x["addon"]]
    ctx.require(len(cats) == 1, "expected one Settings category registered under AddOns, got %s" % [x["name"] for x in c.settings_categories()])
    cat = cats[0]
    ctx.eq(cat["name"], "Getrich", "Settings category name")
    # /gr settings opens the game options on our page (Settings.OpenToCategory(category:GetID()))
    c.slash("/gr settings")
    ctx.eq(c.settings_opened(), "Getrich", "/gr settings opens the Getrich category")
    page = cat["frame"] if cat["kind"] == "canvas" else None
    ctx.require(page is not None and page.IsVisible(page), "settings canvas page not visible after /gr settings")
    c.close_settings()
    c.slash("/gr config")
    ctx.eq(c.settings_opened(), "Getrich", "/gr config opens the Getrich category")
    # the gear button in the main window's title bar opens the same page
    c.close_settings()
    c.slash("/gr")
    c.advance(0.5)
    main = c.g("GetrichFrame")
    gears = [b for b in c.regions(main, "Button") if any("/gr settings" in x for x in c.hover(b))] if main is not None else []
    ctx.check(len(gears) == 1, "expected one title-bar button whose tooltip points to /gr settings, found %d" % len(gears))
    if gears:
        gears[0].Click(gears[0], "LeftButton")
        ctx.eq(c.settings_opened(), "Getrich", "the gear button opens the Getrich category")
    # about: author, contact, website, version from the TOC (copyable)
    t = c.texts(page, editboxes=True)
    meta = c.toc["meta"]
    for need in ("Aaron Tong", "Luvx.inc@gmail.com", "https://github.com/luvxinc/Getrich", meta["Version"], meta["X-Released"]):
        ctx.check(any(need in x for x in t), "settings page does not show %r" % need)
    boxes = [w for w in c.regions(page, "EditBox")]
    ctx.check(any("Luvx.inc@gmail.com" in str(w._text) for w in boxes), "contact e-mail is not in a (copyable) EditBox")
    # every control
    fired = listen_settings_changed(c)
    changed_by, values = {}, {}
    widgets = [w for w in c.regions(page) if w._kind in ("CheckButton", "Button") and w._enabled]
    actions = [w for w in widgets if w._kind == "Button" and "UIPanelButtonTemplate" in str(w._template or "")]
    others = [w for w in widgets if w not in actions]
    ctx.check(len(others) >= 40, "only %d setting controls found on the page" % len(others))
    for w in others:
        before = db_settings(c)
        n0 = len(fired())
        w.Click(w, "LeftButton")
        after = db_settings(c)
        diff = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        got = fired()[n0:]
        for k in diff:
            changed_by.setdefault(k, 0)
            changed_by[k] += 1
            values.setdefault(k, set()).add(after.get(k))
            ctx.check(k in got, "changing %s did not fire SETTINGS_CHANGED('%s') (fired %s)" % (k, k, got))
        if w._kind == "CheckButton" and diff:
            w.Click(w, "LeftButton")          # back to the original value
        if "uiScale" in diff:
            f = c.g("GetrichFrame")
            if f is not None:
                ctx.eq(round(float(f.GetScale(f)), 3), round(float(after["uiScale"]), 3), "GetrichFrame scale after uiScale = %s" % after["uiScale"])
    missing = sorted(k for k in SETTING_DEFAULTS if k not in changed_by)
    ctx.check(not missing, "no control on the settings page changes: %s" % missing)
    for k, opts in SETTING_CHOICES.items():
        seen = {int(v) if isinstance(v, float) and v == int(v) else v for v in values.get(k, set())} | {SETTING_DEFAULTS[k]}
        ctx.check(opts <= seen, "%s: options %s offered, expected at least %s" % (k, sorted(map(str, seen)), sorted(map(str, opts))))
    sc = values.get("uiScale", set())
    ctx.check(sc and min(sc) >= 0.8 - 1e-9 and max(sc) <= 1.3 + 1e-9, "uiScale values outside 0.8-1.3: %s" % sorted(sc))
    # data buttons: confirmation first; cancel keeps everything, accept clears exactly one kind of data
    cleared = []
    for w in actions:
        fill_data(c)
        full = data_state(c)
        npop = len(c.popups())
        w.Click(w, "LeftButton")
        if len(c.popups()) <= npop and not c.popups():
            continue                           # not a data button
        c.accept_popup(cancel=True)
        ctx.eq(data_state(c), full, "cancelling '%s' kept the data" % _strip(w.GetText(w)))
        db.flipCandidates, db.historyDays, db.pruneDays = 150, 60, 30
        w.Click(w, "LeftButton")
        ctx.require(c.accept_popup() is not None, "no confirmation for '%s'" % _strip(w.GetText(w)))
        st = data_state(c)
        gone = sorted(k for k in st if st[k] == 0)
        reset = (db.flipCandidates == 80)
        cleared.append((tuple(gone), reset))
        # data retention is not an option to reset: historyDays / pruneDays survive every button
        ctx.eq((db.historyDays, db.pruneDays), (60, 30), "historyDays / pruneDays after '%s'" % _strip(w.GetText(w)))
    ctx.check(((("history",), False) in cleared), "no button clears only the price history: %s" % cleared)
    ctx.check(((("results", "scannedAt"), False) in cleared),
              "no button clears exactly Getrich's own search results (the Auctionator scans it watched stay): %s" % cleared)
    ctx.check(((("deSamples",), False) in cleared), "no button clears the disenchant records: %s" % cleared)
    ctx.check(((("vendorObs",), False) in cleared), "no button clears the merchant records: %s" % cleared)
    ctx.check((((), True) in cleared), "no 'reset settings' button that keeps the data: %s" % cleared)
    check_clean(ctx, c)


@scenario("settings_effects", "chatOnDone / ahTint / dockToAH / uiScale switch the behaviour they name")
def s_settings_effects(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.set_listings(4306, [(100, 5), (160, 200)])
    fire_setting(c, "chatOnDone", False)
    fire_setting(c, "uiScale", 1.2)
    fire_setting(c, "dockToAH", False)
    c.open_ah()
    c.advance(1.5)
    f = c.g("GetrichFrame")
    ctx.require(f is not None, "no GetrichFrame")
    ctx.eq(round(float(f.GetScale(f)), 3), 1.2, "GetrichFrame scale with uiScale = 1.2")
    def docked():   # compare the Lua tables in Lua (two Python wrappers of one table are never ==)
        return bool(c.eval("local f = ...; for _, p in ipairs(f._points) do if rawequal(p[2], AuctionHouseFrame) then return true end end return false", f))
    ctx.check(not docked(), "window docked to the AH although dockToAH = false")
    n = len(c.chat)
    c.advance(400, until=lambda: not WC.Scanner.active)
    ctx.eq(c.chat[n:], [], "chat lines after a scan with chatOnDone = false")
    # ahTint off: no vendor labels on Blizzard's rows
    fire_setting(c, "ahTint", False)
    c.ah_blizzard_search(4306)
    c.advance(1)
    c.ah_show_commodity(4306)
    c.advance(0.5)
    labels = [_strip(fs._text) for fr, rd in c.ah_rows("commodity") for fs in c.regions(fr, "FontString") if fs._where and fs._text and _strip(fs._text).strip()]
    ctx.eq(labels, [], "AH row labels with ahTint = false")
    c.close_ah()
    # dockToAH on (default): docked again next time
    fire_setting(c, "dockToAH", True)
    c.open_ah()
    c.advance(0.5)
    ctx.check(docked(), "window not docked to the AH with dockToAH = true")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# skill-up planner (SPEC2 2). The built-in recipe table of the profession under test is replaced by a small controlled
# one (real spell/item IDs) so every number below is computed by hand; tailoring_data_rows checks the real table.
CHAR_TAILOR = SECOND_CHAR                     # the Tailoring + Enchanting character
TAILOR_LEARNED = {   # in the character's book (the mock's GetRecipeInfo colours come from y / g)
    2963: {"name": "Bolt of Linen Cloth", "skillLine": 197, "output": 2996, "reagents": [[2589, 2]], "y": 25, "g": 50},
    2387: {"name": "Linen Cloak", "skillLine": 197, "output": 2570, "reagents": [[2320, 1], [2996, 1]], "y": 35, "g": 60},
    12044: {"name": "Simple Linen Pants", "skillLine": 197, "output": 10045, "reagents": [[2320, 1], [2996, 1]], "y": 40, "g": 60},
    8776: {"name": "Linen Belt", "skillLine": 197, "output": 7026, "reagents": [[2320, 1], [2996, 1]], "y": 50, "g": 85},
}
TAILOR_ROWS = """local WC = ...
WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
rawset(WC.RECIPES, 197, {
  [2963]  = { s = 1,  y = 25, g = 50, o = 2996,  r = { 2589, 2 }, t = "t" },           -- learned
  [2387]  = { s = 15, y = 35, g = 60, o = 2570,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [12044] = { s = 15, y = 40, g = 60, o = 10045, r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [8776]  = { s = 15, y = 50, g = 85, o = 7026,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- Brown Linen Shirt: trainer, not learned
  [2385]  = { s = 50, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- Brown Linen Vest: trainer, skill 50
  [2389]  = { s = 40, y = 55, g = 80, o = 2572,  r = { 2320, 1, 2996, 2 }, t = "i" },  -- Red Linen Robe: taught by a pattern
})"""
TAILOR_LISTINGS = {
    2589: [(30, 10), (35, 1000)],    # Linen Cloth
    2996: [(40, 10), (45, 1000)],    # Bolt of Linen Cloth (reagent and product; AH 40 x 0.95 = 38 < vendor 40)
    2570: [(30, 5)],                 # Linen Cloak: AH 30 x 0.95 = 28.5 > vendor 11
    4344: [(60, 5)],                 # Brown Linen Shirt: AH 60 x 0.95 = 57 > its 50 cost -> negative net
}


def tailoring_setup(ctx, rank=20, scan=True, keep_open=False, rows=None):
    c = ctx.client(char=CHAR_TAILOR, login=False)
    c.set_professions([(197, rank, 75)])          # Tailoring only (no Enchanting -> no disenchant offsets)
    c.set_recipes(TAILOR_LEARNED)
    c.eval(rows or TAILOR_ROWS, c.WC)
    c.login()
    c.open_profession(197)
    c.advance(3)
    ck = c.WC.CharKey(c.WC)
    recs = c.g("GetrichDB").recipes[ck]
    ctx.require(recs is not None and recs[2963] is not None, "Tailoring recipes were not captured")
    if not keep_open:
        c.close_profession()
        c.advance(1)
    if scan:
        for iid, rows in TAILOR_LISTINGS.items():
            c.set_listings(iid, rows)
        c.open_ah()
        c.advance(1)
        ok, _ = full_search(c, "craft", 900)
        ctx.require(ok, "the exact search of the crafting items did not start")
        c.advance(1)
    return c, ck


def chance_of(c, row, skill, current=None):
    return multi(c.eval("local LV, row, skill, cur = ...; return LV:Chance(row, skill, cur)", c.WC.Leveling, c.table(row), skill, current), 3)


@scenario("leveling_chance", "SPEC2 2: skill-up chance: orange 1, yellow/green (g - skill) / (g - y), grey 0, green from floor((y+g)/2), red below the learn skill")
def s_level_chance(ctx):
    c = ctx.client()
    bolt = {"s": 1, "y": 25, "g": 50}
    for skill, (ch, color) in {1: (1.0, "orange"), 24: (1.0, "orange"), 25: (1.0, "yellow"), 30: (0.8, "yellow"),
                               36: (0.56, "yellow"), 37: (0.52, "green"), 49: (0.04, "green"), 50: (0.0, "grey"), 80: (0.0, "grey")}.items():
        got = chance_of(c, bolt, skill)
        ctx.eq((round(fnum(got[0]), 9), got[1]), (ch, color), "Chance(Bolt of Linen 1/25/50, %d)" % skill)
    bag = {"s": 1, "y": 30, "g": 65}
    ctx.eq(round(fnum(chance_of(c, bag, 47)[0]), 7), 0.5142857, "Chance(y30 g65, 47) = 18 / 35")
    flat = {"s": 1, "y": 40, "g": 40}            # yellow == grey: orange right up to grey
    ctx.eq((fnum(chance_of(c, flat, 39)[0]), fnum(chance_of(c, flat, 40)[0])), (1.0, 0.0), "Chance(y40 g40) at 39 / 40")
    shirt = {"s": 30, "y": 35, "g": 60}
    ctx.eq(fnum(chance_of(c, shirt, 29)[0]), 0.0, "Chance below the learn skill")
    # learned recipe without built-in data: the client's colour at the current skill decides orange / grey
    ctx.eq(fnum(chance_of(c, {"mt": 60, "d": 0}, 50, 50)[0]), 1.0, "captured orange (d 0) at the current skill")
    ctx.eq(fnum(chance_of(c, {"mt": 60, "d": 3}, 50, 50)[0]), 0.0, "captured grey (d 3) at the current skill")
    check_clean(ctx, c)


@scenario("leveling_candidates", "SPEC2 2: candidates = learned + trainer recipes (not pattern-taught, not above the skill), offset = best of NPC / AH / DE, negative net")
def s_level_cand(ctx):
    c, ck = tailoring_setup(ctx)
    WC = c.WC
    searched = set(c.ah_stats()["searchByItem"])
    for iid in (2589, 2996, 2570, 4344, 2568):   # 4344 / 2568: products of trainer recipes not learned yet
        ctx.check(iid in searched, "craft scan did not search %d" % iid)
    ctx.check(2572 not in searched, "craft scan searched the product of a pattern-taught recipe the character does not know (2572)")
    ctx.check(2320 not in searched, "craft scan searched Coarse Thread (unlimited vendor item)")
    LV = WC.Leveling
    lst = lua_list(LV.Candidates(LV, ck, 197, 30))
    got = [(int(e.recipeID), bool(e.learned), e.color, round(fnum(e.chance), 9), fnum(e.cost), fnum(e.offset), e.offsetKind,
            fnum(e.net), round(fnum(e.perPoint), 9)) for e in lst]
    # at skill 30 (current 20): Brown Linen Shirt (trainer, learn 30) 50 - 57 (AH) = -7 per point;
    #   Linen Cloak 50 - 28.5 (AH) = 21.5; Bolt 60 - 40 (vendor) = 20 / 0.8 = 25; Pants 50 - 23 = 27; Belt 50 - 22 = 28.
    #   Brown Linen Vest (learn 50) and Red Linen Robe (pattern) are not candidates.
    ctx.eq(got, [
        (3915, False, "orange", 1.0, 50.0, 57.0, "ah", -7.0, -7.0),
        (2387, True, "orange", 1.0, 50.0, 28.5, "ah", 21.5, 21.5),
        (2963, True, "yellow", 0.8, 60.0, 40.0, "npc", 20.0, 25.0),
        (12044, True, "orange", 1.0, 50.0, 23.0, "npc", 27.0, 27.0),
        (8776, True, "orange", 1.0, 50.0, 22.0, "npc", 28.0, 28.0),
    ], "Leveling:Candidates(Tailoring, 30)")
    shirt = [e for e in lst if int(e.recipeID) == 3915]
    if shirt:
        e = shirt[0]
        ctx.eq((e.source, int(e.learnSkill or 0), e.name, int(e.skillUps)), ("t", 30, "Brown Linen Shirt", 1), "trainer candidate fields")
    # at skill 20 the shirt can't be learned yet; at 50 the bolt is grey
    ids20 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 20))]
    ctx.eq(ids20, [2963, 2387, 12044, 8776], "Leveling:Candidates(Tailoring, 20)")
    ids50 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 50))]
    ctx.check(2963 not in ids50 and 2385 in ids50, "candidates at 50: bolt (grey) must be gone, Brown Linen Vest (learn 50) in: %s" % ids50)
    # the profit list shows trainer recipes only with craftShowUnlearned
    P = WC.Profit
    ids = {int(e.recipeID) for e in lua_list(first(P.Craft(P)))}
    ctx.check(not ids & {3915, 2385, 2389}, "unlearned recipes listed although craftShowUnlearned = false: %s" % sorted(ids & {3915, 2385, 2389}))
    fire_setting(c, "craftShowUnlearned", True)
    lst = lua_list(first(P.Craft(P)))
    un = {int(e.recipeID): (bool(e.learned), int(e.learnSkill or 0), bool(e.learnable), fnum(e.cost), fnum(e.best), e.bestKind) for e in lst if not e.learned}
    # Shirt: 50 vs AH 57 -> +7 (ah); Vest: 50 vs vendor 31 -> -19 (npc); the pattern recipe never
    ctx.eq(un, {3915: (False, 30, False, 50.0, 7.0, "ah"), 2385: (False, 50, False, 50.0, -19.0, "npc")}, "unlearned trainer recipes in Profit:Craft")
    ctx.eq(int(P.CraftCounts(P).unlearned), 2, "CraftCounts().unlearned")
    # a skill-up to 30 makes the shirt learnable
    c.set_skill(197, 30)
    c.advance(2)
    e = P.CraftEntry(P, 3915)
    ctx.check(e is not None and bool(e.learnable), "Brown Linen Shirt not learnable at skill 30")
    check_clean(ctx, c)


@scenario("leveling_plan", "SPEC2 2: route 20 -> 40: greedy per level, merged steps, expected crafts, mats re-costed for the total, recipes to learn")
def s_level_plan(ctx):
    c, ck = tailoring_setup(ctx)
    WC = c.WC
    LV = WC.Leveling
    plan = LV.Plan(LV, ck, 197, 20, 40)
    ctx.require(plan is not None, "Leveling:Plan returned nil")
    # 20-26 Bolt (20 per point; at 26: 20 / 0.96 = 20.83 < Cloak 21.5): 6 + 1/0.96 crafts
    # 27-29 Linen Cloak (Bolt 20 / 0.92 = 21.74 > 21.5): 3 crafts
    # 30-39 Brown Linen Shirt (learn 30, -7 per craft): 5 orange + 1 + 1/0.96 + 1/0.92 + 1/0.88 + 1/0.84
    c_bolt = 6 + 1 / 0.96
    c_shirt = 5 + 1 + 1 / 0.96 + 1 / 0.92 + 1 / 0.88 + 1 / 0.84
    exp_steps = [(20, 27, 2963, True, c_bolt, c_bolt * 60, c_bolt * 20),
                 (27, 30, 2387, True, 3.0, 150.0, 64.5),
                 (30, 40, 3915, False, c_shirt, c_shirt * 50, c_shirt * -7)]
    steps = [(int(x["from"]), int(x.to), int(x.recipeID), bool(x.learned), fnum(x.crafts), fnum(x.cost), fnum(x.net)) for x in lua_list(plan.steps)]
    ctx.eq(len(steps), 3, "plan steps: %s" % steps)
    for got, exp in zip(steps, exp_steps):
        ok = got[:4] == exp[:4] and all(abs(a - b) < 1e-6 for a, b in zip(got[4:], exp[4:]))
        ctx.check(ok, "plan step: expected %s, got %s" % (exp, got))
    # materials for the whole route, bought at once (order book walked for the total):
    #   Linen 2 x 7.0417 = 14.08 -> 15 = 10 x 30 + 5 x 35 = 475; Coarse Thread 3 + 10.455 -> 14 x 10 (vendor) = 140;
    #   Bolt 10.455 + 3 -> 14 = 10 x 40 + 4 x 45 = 580
    mats = {int(m.itemID): (int(m.qty), fnum(m.cost), m.source) for m in lua_list(plan.mats)}
    ctx.eq(mats, {2589: (15, 475.0, "ah"), 2320: (14, 140.0, "vendor"), 2996: (14, 580.0, "ah")}, "plan.mats")
    ctx.eq([int(m.itemID) for m in lua_list(plan.mats)], [2996, 2589, 2320], "plan.mats order (costliest first)")
    offset = c_bolt * 40 + 3 * 28.5 + c_shirt * 57
    ctx.eq(fnum(plan.total), 1195 - offset, "plan.total = mats 1195 - products %.6f" % offset)
    ctx.eq([(int(x.recipeID), int(x.skill), int(x.learnSkill)) for x in lua_list(plan.learn)], [(3915, 30, 30)], "plan.learn")
    ctx.eq([int(x) for x in lua_list(plan.missing)], [], "plan.missing")
    ctx.eq((int(plan["from"]), int(plan.to), int(plan.reached or 0)), (20, 40, 40), "plan from / to / reached")
    # default range: current skill -> levelTarget ("max" = the rank's cap 75; 225 when set)
    d = LV.Plan(LV, ck, 197)
    ctx.eq((int(d["from"]), int(d.to)), (20, 75), "Plan() default range with levelTarget = max")
    fire_setting(c, "levelTarget", 225)
    d = LV.Plan(LV, ck, 197)
    ctx.eq(int(d.to), 225, "Plan() target with levelTarget = 225")
    # Crafting tab, skill-up mode: lists the candidates and the route
    fire_setting(c, "levelTarget", "max")
    c.g("GetrichDB").craftMode = "level"
    c.slash("/gr craft")
    c.advance(0.5)
    t = visible_tab_texts(c)
    for need in ("Bolt of Linen Cloth", "Linen Cloak"):
        ctx.check(any(need in x for x in t), "skill-up mode (current list) does not list %r" % need)
    ctx.check(not any("Brown Linen Shirt" in x for x in t), "the current list at 20 shows the shirt (learn skill 30)")
    c.g("GetrichDB").craftLevelView = "plan"        # route view: the three steps, the shirt to learn
    c.slash("/gr craft")
    c.advance(0.5)
    t = visible_tab_texts(c)
    for need in ("Bolt of Linen Cloth", "Linen Cloak", "Brown Linen Shirt"):
        ctx.check(any(need in x for x in t), "skill-up route view does not list %r" % need)
    check_clean(ctx, c)


def rank_key(e):
    """SPEC2 round 4 ranking: max(net, 0) / (chance x skill-ups); ties: higher chance x skill-ups, then more profit."""
    pc = fnum(e.chance) * max(int(e.skillUps or 1), 1)
    return (max(fnum(e.net), 0.0) / pc, -pc, fnum(e.net))


@scenario("leveling_offsets", "SPEC2 2: levelOffset best3 / npcde / none on Blacksmithing 85 (AH beats DE beats NPC; negative net when the AH pays more than the mats)")
def s_level_offsets(ctx):
    c = ctx.client(login=False)
    c.set_professions([(164, 85, 150), (333, 150, 225)])
    c.eval("""local WC = ...
      WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
      WC.RECIPES[164] = type(WC.RECIPES[164]) == "table" and WC.RECIPES[164] or {}
      WC.RECIPES[164][9983] = { s = 30, y = 65, g = 105, o = 7955, r = { 2318, 1, 2840, 10, 2880, 2, 3470, 1 }, t = "t" }
      WC.RECIPES[164][8880] = { s = 30, y = 65, g = 105, o = 7166, r = { 2318, 1, 2840, 6, 2880, 1, 3470, 1 }, t = "t" }""", c.WC)
    c.login()
    WC = c.WC
    craft_setup(ctx, c)
    ck = WC.CharKey(WC)
    LV = WC.Leveling

    def cand(rid):
        for e in lua_list(LV.Candidates(LV, ck, 164, 85)):
            if int(e.recipeID) == rid:
                return e
        return None
    # Copper Claymore at 85: green, (105 - 85) / 40 = 0.5. Cost 815; vendor 241, AH 1500 x 0.95 = 1425, DE 353.4
    # Copper Dagger: cost 475; vendor 194, not on the AH, DE 353.4
    expect = {
        "best3": {9983: (1425.0, "ah", -610.0, -1220.0), 8880: (353.4, "de", 121.6, 243.2)},
        "npcde": {9983: (353.4, "de", 461.6, 923.2), 8880: (353.4, "de", 121.6, 243.2)},
        "none": {9983: (0.0, None, 815.0, 1630.0), 8880: (0.0, None, 475.0, 950.0)},
    }
    for mode in ("best3", "npcde", "none"):
        fire_setting(c, "levelOffset", mode)
        for rid, (off, kind, net, pp) in expect[mode].items():
            e = cand(rid)
            ctx.require(e is not None, "recipe %d is not a candidate at 85" % rid)
            ctx.eq((round(fnum(e.chance), 9), e.color), (0.5, "green"), "%d chance at 85" % rid)
            got = (round(fnum(e.offset), 6), e.offsetKind, round(fnum(e.net), 6), round(fnum(e.perPoint), 6))
            ctx.eq(got, (off, kind, net, pp), "%s: %d offset / kind / net / perPoint" % (mode, rid))
        keys = [rank_key(e) for e in lua_list(LV.Candidates(LV, ck, 164, 85)) if e.net is not None]
        ctx.check(keys == sorted(keys), "%s: candidates not sorted by max(net, 0) / (chance x skill-ups), then chance, then profit" % mode)
        if mode == "best3":
            # both make money (Maul -69.375 at 87.5%%, Claymore -610 at 50%%): the surer skill-up ranks first
            order = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 164, 85)) if int(e.recipeID) in (7408, 9983)]
            ctx.eq(order, [7408, 9983], "best3: order of two profitable recipes (higher chance first)")
    check_clean(ctx, c)


@scenario("craft_de_unlearned", "SPEC2 2: craft -> disenchant covers a trainer recipe the character has not learned (always; the profit list only with craftShowUnlearned)")
def s_craft_de_unlearned(ctx):
    c = ctx.client(login=False)
    recs = {int(k): dict(v) for k, v in _json("recipes.json")["chars"][DEFAULT_CHAR]["recipes"].items()}
    recs[7408]["learned"] = False                # Heavy Copper Maul: not learned, a trainer teaches it at 70
    c.set_recipes(recs)
    c.set_professions([(164, 85, 150), (333, 150, 225)])
    c.eval("""local WC = ...
      WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
      WC.RECIPES[164] = type(WC.RECIPES[164]) == "table" and WC.RECIPES[164] or {}
      WC.RECIPES[164][7408] = { s = 70, y = 80, g = 120, o = 6214, r = { 2318, 2, 2840, 12, 2880, 2 }, t = "t" }""", c.WC)
    c.login()
    WC = c.WC
    craft_setup(ctx, c)
    P = WC.Profit
    ck = WC.CharKey(WC)
    ctx.eq(c.g("GetrichDB").recipes[ck][7408], None, "Heavy Copper Maul must not be captured (not learned)")

    def de_craft():
        return {int(e.recipeID): e for e in lua_list(first(P.Disenchant(P))) if e.source == "craft"}
    ctx.check(9983 in de_craft(), "learned Copper Claymore missing from the craft->DE list")
    ctx.check(7408 not in {int(e.recipeID) for e in lua_list(first(P.Craft(P)))}, "unlearned Heavy Copper Maul in the profit list although craftShowUnlearned = false")
    for show in (False, True):
        fire_setting(c, "craftShowUnlearned", show)
        d = de_craft()
        ctx.check(7408 in d, "unlearned trainer recipe Heavy Copper Maul not in the craft->DE list (craftShowUnlearned = %s)" % show)
        if 7408 in d:
            e = d[7408]
            # 2 Light Leather 60 + 12 Copper Bar (4 x 50 + 8 x 60 = 680) + 2 Weak Flux 200 = 940; DE 1009.375 -> +69.375
            ctx.eq((int(e.itemID), fnum(e.buy), round(fnum(e.value), 6), round(fnum(e.gain), 6), e.status), (6214, 940.0, 1009.375, 69.375, "ok"),
                   "craft->DE entry for the unlearned Heavy Copper Maul (craftShowUnlearned = %s)" % show)
    ce = P.CraftEntry(P, 7408)
    ctx.check(ce is not None and ce.learned is False and int(ce.learnSkill) == 70 and bool(ce.learnable),
              "Profit:CraftEntry(7408): learned false, learnSkill 70, learnable at 85")
    c.slash("/gr de")
    c.advance(0.5)
    ctx.check(any("Heavy Copper Maul" in x for x in c.texts(clip=True)), "Disenchant tab does not list the unlearned Heavy Copper Maul")
    check_clean(ctx, c)


def recipe_label(c, rid):
    """(label frame, stripped text) of a recipe row in the open ProfessionsFrame (scrolls to it)."""
    sb = c.eval("return ProfessionsFrame.CraftingPage.RecipeList.ScrollBox")
    idx = c.eval("""local sb, rid = ...
      for i, n in ipairs(sb:GetDataProvider():Flatten()) do local d = n:GetData(); if d.recipeInfo and d.recipeInfo.recipeID == rid then return i end end""", sb, rid)
    if idx is None:
        return None, None
    sb.ScrollToElementDataIndex(sb, idx)
    for fr, r in c.recipe_rows():
        if r == rid:
            f = fr.wcProfit
            if f is None or not f.IsShown(f):
                return f, ""
            return f, _strip(f.text._text or "")
    return None, None


@scenario("profession_skillup_badges", "SPEC2 3: badges on the 3 learned recipes with the lowest cost per skill point + tooltip; follow skill-ups; profLevelMark / profOverlay off")
def s_badges(ctx):
    c, ck = tailoring_setup(ctx, keep_open=False)
    c.close_ah()
    c.open_profession(197)
    c.advance(2)
    mark = {"enUS": "Lv%d", "zhCN": "升%d", "zhTW": "升%d"}[ctx.locale]

    def marks():
        out = {}
        for rid in (2963, 2387, 12044, 8776):
            f, t = recipe_label(c, rid)
            m = [i for i in (1, 2, 3) if t and t.startswith(mark % i)]
            out[rid] = m[0] if m else None
        return out
    # at 20: Bolt 20 per point, Cloak 21.5, Pants 27 (Belt 28: no badge; the unlearned shirt is not in the book)
    ctx.eq(marks(), {2963: 1, 2387: 2, 12044: 3, 8776: None}, "badges at skill 20")
    f, t = recipe_label(c, 2963)
    tip = "\n".join(c.hover(f)) if f is not None else ""
    ctx.check("100%" in tip and ("20" + {"enUS": "c", "zhCN": "铜", "zhTW": "銅"}[ctx.locale]) in tip,
              "badge tooltip should give ~20c per skill point at 100%%:\n%s" % tip)
    # skill-up to 27: Cloak 21.5 < Bolt 20 / 0.92 = 21.74 < Pants 27
    c.set_skill(197, 27)
    c.advance(2)
    ctx.eq(marks(), {2963: 2, 2387: 1, 12044: 3, 8776: None}, "badges after the skill-up to 27")
    f, t = recipe_label(c, 2963)
    tip = "\n".join(c.hover(f)) if f is not None else ""
    ctx.check("92%" in tip, "badge tooltip of the bolt at 27 should show the 92%% chance:\n%s" % tip)
    fire_setting(c, "profLevelMark", False)
    c.advance(1)
    ctx.eq(marks(), {2963: None, 2387: None, 12044: None, 8776: None}, "badges with profLevelMark = false")
    fire_setting(c, "profLevelMark", True)
    fire_setting(c, "profOverlay", False)
    c.advance(1)
    shown = [rid for rid in (2963, 2387, 12044, 8776) if (recipe_label(c, rid)[1] or "").strip()]
    ctx.eq(shown, [], "labels shown with profOverlay = false")
    # a maxed profession gets no badges
    fire_setting(c, "profOverlay", True)
    c.set_skill(197, 75)
    c.advance(2)
    ctx.eq(marks(), {2963: None, 2387: None, 12044: None, 8776: None}, "badges when the profession is maxed (75/75)")
    check_clean(ctx, c)


@scenario("recipe_table_data", "SPEC2 1: DataRecipes.lua matches every recipe captured from the client (y / g / output / reagents), trainer vs pattern, skill-up rule")
def s_recipe_data(ctx):
    c = ctx.client()
    WC = c.WC
    R = WC.RECIPES
    ctx.require(R is not None, "WC.RECIPES missing")
    size = os.path.getsize(os.path.join(os.path.dirname(HERE), "Getrich", "DataRecipes.lua"))
    ctx.check(size <= 260 * 1024, "DataRecipes.lua is %d KB (spec: about 250 KB)" % (size // 1024))
    su = WC.SKILLUP
    ctx.check(su is not None and su.formula == "classic" and str(su.source or "").startswith("http"), "WC.SKILLUP {formula = 'classic', source = url} missing")
    for sl in (171, 164, 333, 202, 165, 197, 185, 129, 186):
        n = len(lua_keys(R[sl])) if R[sl] is not None else 0
        ctx.check(n > 0, "WC.RECIPES[%d] is empty" % sl)
    # every recipe the two fixture characters know (captured from the client, thresholds from SkillLineAbility)
    checked, bad = 0, []
    for guid, ch in _json("recipes.json")["chars"].items():
        for rid, r in ch["recipes"].items():
            if r.get("y") is None:
                continue
            rid, sl = int(rid), r["skillLine"]
            row = R[sl][rid] if R[sl] is not None else None
            if row is None:
                bad.append("%d %s: not in WC.RECIPES[%d]" % (rid, r["name"], sl))
                continue
            flat = lua_list(row.r)
            got = (row.y, row.g, row.o, sorted((int(flat[i]), int(flat[i + 1])) for i in range(0, len(flat) - 1, 2)))
            want = (r["y"], r["g"], r.get("output"), sorted((int(a), int(b)) for a, b in r["reagents"]))
            if got != want:
                bad.append("%d %s: %s, client %s" % (rid, r["name"], got, want))
            checked += 1
    ctx.check(checked >= 250, "only %d captured recipes checked" % checked)
    ctx.check(not bad, "WC.RECIPES differs from the client for %d recipes: %s" % (len(bad), bad[:8]))
    # spot checks: trainer / auto-learned vs taught by a pattern item
    b = R[197][2963]
    ctx.eq((b.s, b.y, b.g, b.o, [int(x) for x in lua_list(b.r)], b.t), (1, 25, 50, 2996, [2589, 2], "t"), "Bolt of Linen Cloth row")
    rl = R[197][2389]
    ctx.eq((rl.t, rl.ri), ("i", 2598), "Red Linen Robe: taught by Pattern: Red Linen Robe (2598)")
    # row shape: even reagent list, t in t/i/?, a recipe item for 'i' and none for 't', yields ordered, learn skill <= 300
    shape = c.eval("""local R = ...
      local bad = {}
      for sl, rows in pairs(R) do
        for id, row in pairs(rows) do
          local why
          if type(row.r) ~= "table" or #row.r == 0 or #row.r % 2 ~= 0 then why = "reagents" end
          if not (row.t == "t" or row.t == "i" or row.t == "?") then why = "t" end
          if (row.t == "i" and row.ri == nil) or (row.t == "t" and row.ri ~= nil) then why = "ri" end   -- '?' may name a missing item
          if not (type(row.s) == "number" and row.s <= 300 and type(row.y) == "number" and type(row.g) == "number" and row.y <= row.g) then why = "s/y/g" end
          if (row.n1 or 1) > (row.n2 or row.n1 or 1) then why = "yield" end
          if why and #bad < 10 then bad[#bad + 1] = sl .. ":" .. id .. " " .. why end
        end
      end
      return table.concat(bad, ", ")""", R)
    ctx.eq(shape, "", "malformed WC.RECIPES rows")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# round 3 (SPEC2 8): trainer window capture -> exact learn skill + training cost in the planner; lazy recipe data
# the shirt and the vest with the data's guessed learn skill (se = 1: s = yellow), as DataRecipes ships trainer recipes
TAILOR_ROWS_GUESS = TAILOR_ROWS.replace(
    '[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" }',
    '[3915]  = { s = 35, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t", se = 1 }').replace(
    '[2385]  = { s = 50, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t" }',
    '[2385]  = { s = 70, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t", se = 1 }')
assert TAILOR_ROWS_GUESS.count("se = 1") == 2
TAILOR_TRAINER = [   # what the trainer window offers (filtered by the client's type filter)
    {"spellID": 2963, "itemID": 2996, "req": 1, "cost": 10, "learned": True},
    {"spellID": 2387, "itemID": 2570, "req": 15, "cost": 50, "learned": True},
    {"spellID": 12044, "itemID": 10045, "req": 15, "cost": 25, "learned": True},
    {"spellID": 3915, "itemID": 4344, "req": 30, "cost": 150},
    {"spellID": 2385, "itemID": 2568, "req": 50, "cost": 300, "nameDelay": 0.6},   # name arrives later (TRAINER_SERVICE_INFO_NAME_UPDATE)
    {"spellID": 0, "name": "Journeyman Tailoring", "req": 50, "cost": 500, "step": True},
]
for _i, _e in enumerate(TAILOR_TRAINER):
    if _e["spellID"]:
        _e["teachSpellID"] = 2000000 + _e["spellID"]   # the trainer's "teach" spell: not a recipe of the line
TRAINER_EXPECT = {2963: (1, 10), 2387: (15, 50), 12044: (15, 25), 3915: (30, 150), 2385: (50, 300)}


def visit_trainer(c, tooltip="item", late_names=True):
    c.set_trainer_filter(available=True, unavailable=False, used=False)   # the user shows only what they can learn now
    services = TAILOR_TRAINER if late_names else [{k: v for k, v in e.items() if k != "nameDelay"} for e in TAILOR_TRAINER]
    c.open_trainer(990010, "Tailoring Trainer", 197, services, tooltip=tooltip)
    c.advance(3)


def trainer_db(c):
    t = c.g("GetrichDB").trainer
    line = t[197] if t is not None else None
    return {int(k): (line[k].s, line[k].cost) for k in lua_keys(line)} if line is not None else {}


@scenario("trainer_capture", "SPEC2 8: trainer window -> db.trainer[skillLine][spellID] = { s, cost } for every service (also the ones the filter hides), filter restored")
def s_trainer_capture(ctx):
    for mode in ("item", "spell", "teach", "none"):   # what C_TooltipInfo.GetTrainerService gives is not in the UI source
        c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
        WC = c.WC
        visit_trainer(c, tooltip=mode)
        got = trainer_db(c)
        ctx.eq({k: v for k, v in got.items() if k in TRAINER_EXPECT}, TRAINER_EXPECT, "db.trainer[197] (tooltip mode %s)" % mode)
        ctx.check(0 not in got, "the profession-rank service (Journeyman) was stored as a recipe (mode %s)" % mode)
        ctx.check(not [k for k in got if k >= 2000000], "teaching spell ids stored as recipes (mode %s): %s" % (mode, sorted(got)))
        ctx.eq(c.trainer_filter(), {"available": True, "unavailable": False, "used": False}, "the user's trainer filter after the capture (mode %s)" % mode)
        ctx.eq(multi(WC.Recipes.TrainerInfo(WC.Recipes, 197, 3915), 2), (30, 150), "Recipes:TrainerInfo(197, Brown Linen Shirt) (mode %s)" % mode)
        ctx.eq(multi(WC.Recipes.TrainerInfo(WC.Recipes, 197, 2389), 2), (None, None), "TrainerInfo of a recipe never seen at a trainer")
        c.close_trainer()
        c.advance(1)
        check_clean(ctx, c, "tooltip mode " + mode)
    # a class trainer is not a profession trainer: nothing is stored
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
    c.open_trainer(990011, "Warrior Trainer", 197, [{"spellID": 0, "name": "Battle Shout", "cost": 100, "level": 12},
                                                    {"spellID": 0, "name": "Rend", "cost": 200, "level": 10}], tradeskill=False)
    c.advance(3)
    c.close_trainer()
    c.advance(1)
    ctx.eq(trainer_db(c), {}, "db.trainer after visiting a class trainer")
    check_clean(ctx, c, "class trainer")
    # account-wide data: kept in the SavedVariables
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
    visit_trainer(c, late_names=False)
    text = c.logout_sv()
    ctx.check("trainer" in text and "= 150" in text.replace("=150", "= 150"), "db.trainer is not saved")


@scenario("trainer_plan", "SPEC2 8: the planner uses the trainer's exact learn skill (learnGuess cleared) and adds the training cost to the route total")
def s_trainer_plan(ctx):
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS)
    WC = c.WC
    LV = WC.Leveling
    c_bolt = 6 + 1 / 0.96
    yel = 1 + 1 / 0.96 + 1 / 0.92 + 1 / 0.88 + 1 / 0.84          # 35..39 at (60 - L) / 25
    # before the trainer visit the shirt's learn skill is the data's guess (35 = yellow): Cloak 27 -> 35, shirt 35 -> 40
    shirt = [e for e in lua_list(LV.Candidates(LV, ck, 197, 35)) if int(e.recipeID) == 3915]
    ctx.check(shirt and bool(shirt[0].learnGuess) and int(shirt[0].learnSkill) == 35, "before the trainer: shirt learnGuess with learn skill 35")
    ctx.check(not [e for e in lua_list(LV.Candidates(LV, ck, 197, 30)) if int(e.recipeID) == 3915], "before the trainer: shirt a candidate at 30 (guessed learn skill 35)")
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 35, 2387), (35, 40, 3915)], "plan steps with the guessed learn skill")
    learn = [(int(x.recipeID), int(x.skill), int(x.learnSkill), x.cost, bool(x.learnGuess)) for x in lua_list(plan.learn)]
    ctx.eq(learn, [(3915, 35, 35, None, True)], "plan.learn before the trainer (cost unknown, guessed)")
    ctx.eq((fnum(plan.learnCost or 0), int(plan.learnCostUnknown or 0)), (0.0, 1), "learnCost / learnCostUnknown before the trainer")
    offset0 = c_bolt * 40 + 8 * 28.5 + yel * 57
    ctx.eq(fnum(plan.total), 1195 - offset0, "plan.total before the trainer (mats 1195 - products %.6f, training unknown)" % offset0)
    # the trainer: shirt at 30 for 1s 50c
    c.close_ah()
    visit_trainer(c, late_names=False)
    c.close_trainer()
    c.advance(1)
    shirt = [e for e in lua_list(LV.Candidates(LV, ck, 197, 30)) if int(e.recipeID) == 3915]
    ctx.check(shirt and not shirt[0].learnGuess and int(shirt[0].learnSkill) == 30, "after the trainer: shirt a candidate at 30, learnGuess cleared")
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 30, 2387), (30, 40, 3915)], "plan steps with the trainer's learn skill")
    learn = [(int(x.recipeID), int(x.skill), int(x.learnSkill), fnum(x.cost), bool(x.learnGuess)) for x in lua_list(plan.learn)]
    ctx.eq(learn, [(3915, 30, 30, 150.0, False)], "plan.learn after the trainer")
    ctx.eq((fnum(plan.learnCost), int(plan.learnCostUnknown or 0)), (150.0, 0), "learnCost / learnCostUnknown after the trainer")
    offset1 = c_bolt * 40 + 3 * 28.5 + (5 + yel) * 57
    ctx.eq(fnum(plan.total), 1195 - offset1 + 150, "plan.total = mats 1195 - products %.6f + training 150" % offset1)
    # the vest: exact learn skill 50 instead of the guessed 70
    ids50 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 50))]
    ctx.check(2385 in ids50, "Brown Linen Vest not a candidate at 50 after the trainer (guess was 70)")
    check_clean(ctx, c)


def lua_heap_kb(lua):
    return float(lua.eval("(function() collectgarbage('collect'); collectgarbage('collect'); return collectgarbage('count') end)()"))


@scenario("recipes_lazy_data", "SPEC2 8: recipe data stays encoded until a skill line is read (memory bound), decodes fast, RECIPE_LINES iteration, consumers still find recipes")
def s_lazy(ctx):
    from lupa import lua51
    path = os.path.join(os.path.dirname(HERE), "Getrich", "DataRecipes.lua")
    src = open(path, encoding="utf-8").read()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    WCt = lua.table()
    load = lua.eval("function(src, WC) local f, e = loadstring(src, '=DataRecipes.lua'); if not f then error(e) end; f('Getrich', WC) end")
    base = lua_heap_kb(lua)
    load(src, WCt)                       # compile + run like the client; the compiled chunk is garbage afterwards
    after = lua_heap_kb(lua)
    ctx.note("Lua heap of DataRecipes.lua after load: %.0f KB" % (after - base))
    ctx.check(after - base <= 300, "DataRecipes.lua uses %.0f KB of Lua memory after load (limit 300 KB until a profession is used)" % (after - base))
    lines = [int(x) for x in lua_list(WCt.RECIPE_LINES)]
    ctx.check(lines == sorted(lines) and {171, 164, 333, 202, 165, 197, 185, 129, 186} <= set(lines), "WC.RECIPE_LINES: %s" % lines)
    R = WCt.RECIPES
    ctx.eq([k for k in R.keys()], [], "pairs(WC.RECIPES) before any line was read")
    rawget = lua.eval("rawget")
    ctx.eq(WCt.RecipeLine(2963) if WCt.RecipeLine else None, 197, "WC.RecipeLine(Bolt of Linen Cloth)")
    ctx.eq(rawget(R, 197), None, "WC.RecipeLine decoded the Tailoring line")
    timer = lua.eval("function(R, sl) local t0 = os.clock(); local rows = R[sl]; local dt = os.clock() - t0; local n = 0; for _ in pairs(rows or {}) do n = n + 1 end; return dt, n end")
    worst, total = (0, None), 0
    for sl in lines:
        dt, n = timer(R, sl)
        total += n
        ctx.check(n > 0, "WC.RECIPES[%d] decodes to nothing" % sl)
        if dt > worst[0]:
            worst = (dt, sl)
        ctx.check(lua.eval("rawequal")(R[sl], rawget(R, sl)), "WC.RECIPES[%d] is not cached after the first read" % sl)
    ctx.note("decoded %d recipes in %d lines; slowest line %s: %.1f ms; heap with every line decoded: %.0f KB"
             % (total, len(lines), worst[1], worst[0] * 1000, lua_heap_kb(lua) - base))
    ctx.check(worst[0] < 0.020, "decoding skill line %s took %.1f ms (limit 20 ms)" % (worst[1], worst[0] * 1000))
    ctx.check(total >= 2000, "only %d recipes decoded" % total)
    # in the addon: after login only lines something asked for are decoded; consumers find recipes in other lines
    c = ctx.client()
    WC = c.WC
    decoded = lambda: sorted(int(sl) for sl in lua_list(WC.RECIPE_LINES) if c.eval("local R, sl = ...; return rawget(R, sl) ~= nil", WC.RECIPES, sl))
    d0 = decoded()
    ctx.check(not set(d0) & {171, 202, 165, 197}, "lines of professions the character does not have were decoded at login: %s" % d0)
    a = WC.Profit.StaticRecipe(WC.Profit, 2963)                 # no skill line given: found via WC.RecipeLine
    ctx.check(a is not None and a.p == 197 and int(a.o) == 2996, "Profit:StaticRecipe(Bolt of Linen Cloth) without a skill line")
    ctx.eq(decoded(), sorted(set(d0) | {197}), "lines decoded after Profit:StaticRecipe(2963)")
    a = WC.Profit.StaticRecipe(WC.Profit, 3275)                 # Linen Bandage (First Aid)
    ctx.check(a is not None and a.p == 129, "Profit:StaticRecipe(Linen Bandage) without a skill line")
    st = c.eval("local WC = ...; local T = WC.UICraft or (WC.UI and WC.UI.tabs and WC.UI.tabs.craft); if T and T.StaticRecipe then return T:StaticRecipe(nil, 2963) end", WC)
    ctx.check(st is not None, "UICraft Tab:StaticRecipe(nil, Bolt of Linen Cloth) found nothing")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# round 4 (review fixes)
def harmonic(lo, hi, g, y):
    """expected crafts for levels lo..hi-1 at chance (g - L) / (g - y) (1 below y)."""
    return sum(1.0 if L < y else (g - y) / (g - L) for L in range(lo, hi))


@scenario("leveling_skillups_zero", "review: a recipe captured with numSkillUps = 0 never hangs Leveling:Plan (counted as 1); profitable recipes tie at 0 -> surer skill-up, then more profit; long routes priced past the kept listings")
def s_level_su0(ctx):
    learned = dict(TAILOR_LEARNED)
    learned[3755] = {"name": "Linen Bag", "skillLine": 197, "output": 4238, "reagents": [[2320, 3], [2996, 3]], "y": 30, "g": 65, "su": 0}
    rows = TAILOR_ROWS.replace("})", '  [3755]  = { s = 1, y = 30, g = 65, o = 4238, r = { 2320, 3, 2996, 3 }, t = "t" },\n})')
    c = ctx.client(char=CHAR_TAILOR, login=False)
    c.set_professions([(197, 20, 75)])
    c.set_recipes(learned)
    c.eval(rows, c.WC)
    c.login()
    c.open_profession(197); c.advance(3); c.close_profession(); c.advance(1)
    WC = c.WC
    ck = WC.CharKey(WC)
    ctx.eq(c.g("GetrichDB").recipes[ck][3755].su, 0, "captured numSkillUps of Linen Bag")
    listings = dict(TAILOR_LISTINGS)
    listings[2996] = [(40, 7), (45, 300), (50, 1254)]   # 1561 bolts listed, the scanner keeps the cheapest 307
    for iid, r in listings.items():
        c.set_listings(iid, r)
    c.open_ah(); c.advance(1)
    full_search(c, "craft", 900)
    c.advance(1)
    LV = WC.Leveling
    bag = [e for e in lua_list(LV.Candidates(LV, ck, 197, 20)) if int(e.recipeID) == 3755]
    ctx.check(bag and int(bag[0].skillUps) == 1 and fnum(bag[0].perPoint) == -50.0,
              "Linen Bag candidate at 20: skillUps 1 and -50 per point (150 mats - 200 vendor), got %s" % ((int(bag[0].skillUps), fnum(bag[0].perPoint)) if bag else None,))
    ok, plan, ticks, secs = multi(c.eval("""local LV, ck = ...
      local n = 0
      debug.sethook(function() n = n + 1; if n > 20000 then debug.sethook(); error("instruction guard: Leveling:Plan runs away") end end, "", 1000)
      local t0 = os.clock()
      local ok, plan = pcall(LV.Plan, LV, ck, 197, 10, 75)
      debug.sethook()
      return ok, plan, n, os.clock() - t0""", LV, ck), 4)
    ctx.note("Leveling:Plan(197, 10, 75): %.0f ms, %d k instructions" % (secs * 1000, ticks))
    ctx.require(ok, "Leveling:Plan(197, 10, 75) did not finish: %s" % plan)
    ctx.check(secs < 1.0, "Leveling:Plan took %.2f s" % secs)
    # 10-30 Linen Bag (-50, orange); 30: Bag and Shirt both certain -> more profit (Bag); 31-47 Shirt (more likely than the
    # Bag: (60-L)/25 > (65-L)/35 below 47.5); 48-64 Bag; 65-74 Brown Linen Vest (19 per point, cheapest positive)
    c_bag1 = 21.0
    c_shirt = harmonic(31, 48, 60, 35)
    c_bag2 = harmonic(48, 65, 65, 30)
    c_vest = harmonic(65, 75, 95, 70)
    exp = [(10, 31, 3755, c_bag1), (31, 48, 3915, c_shirt), (48, 65, 3755, c_bag2), (65, 75, 2385, c_vest)]
    got = [(int(x["from"]), int(x.to), int(x.recipeID), fnum(x.crafts)) for x in lua_list(plan.steps)]
    ok_steps = len(got) == len(exp) and all(g[:3] == e[:3] and abs(g[3] - e[3]) < 1e-6 for g, e in zip(got, exp))
    ctx.check(ok_steps, "plan 10 -> 75 steps:\n   expected %s\n   got      %s" % (exp, got))
    ctx.eq([(int(x.recipeID), int(x.skill)) for x in lua_list(plan.learn)], [(3915, 31), (2385, 65)], "plan.learn")
    bags, shirts, vests = c_bag1 + c_bag2, c_shirt, c_vest
    n_bolt = math.ceil(3 * bags + shirts + vests - 1e-9)
    n_thread = math.ceil(3 * bags + shirts + vests - 1e-9)
    mats = {int(m.itemID): (int(m.qty), fnum(m.cost), m.source) for m in lua_list(plan.mats)}
    # bolts: 7 x 40 + 300 x 45 kept; the rest priced at the dearest kept price 45 (1561 listed >= need)
    bolt_cost = 7 * 40 + (n_bolt - 7) * 45
    ctx.eq(mats.get(2996), (n_bolt, float(bolt_cost), "ah"), "plan.mats Bolt of Linen Cloth (%d > 307 kept)" % n_bolt)
    ctx.eq(mats.get(2320), (n_thread, float(n_thread * 10), "vendor"), "plan.mats Coarse Thread")
    offset = bags * 200 + shirts * 57 + vests * 31
    ctx.check(plan.total is not None, "plan.total is nil for a route deeper than the kept listings")
    if plan.total is not None:
        ctx.eq(fnum(plan.total), bolt_cost + n_thread * 10 - offset, "plan.total (training costs unknown: %s)" % plan.learnCostUnknown)
    check_clean(ctx, c)


@scenario("cost_beyond_kept_listings", "review: CostForAny prices past the ~250 kept units at the dearest kept price when enough are listed ('est'); 'short' only when fewer are listed")
def s_cost_deep(ctx):
    c = ctx.client()
    WC = c.WC
    c.set_listings(2996, [(40, 7), (45, 300), (50, 1254)])
    c.open_ah(); c.advance(1)
    WC.Store.SetWatch(WC.Store, 2996, True)
    start_scan(c, "history", 120)
    c.advance(1)
    r = c.g("GetrichDB").results[2996]
    ctx.require(r is not None and r.status == "listed", "Bolt of Linen Cloth was not scanned")
    ctx.eq(([[int(e[1]), int(e[2])] for e in lua_list(r.entries)], int(r.avail)), ([[40, 7], [45, 300]], 1561), "kept entries / avail")
    def cost(q):
        v = multi(WC.CostForAny(WC, 2996, q), 2)
        return (None if v[0] is None else fnum(v[0]), v[1])
    ctx.eq(cost(300), (280 + 293 * 45.0, "ok"), "CostForAny(300): inside the kept listings")
    ctx.eq(cost(909), (280 + 902 * 45.0, "est"), "CostForAny(909): 307 kept + 602 at 45")
    ctx.eq(cost(1561), (280 + 1554 * 45.0, "est"), "CostForAny(1561): everything listed")
    ctx.eq(cost(1600), (None, "short"), "CostForAny(1600): more than listed")
    m = WC.Profit.MatCost(WC.Profit, 2996, 909)
    ctx.eq((fnum(m.cost), m.source, bool(m.est)), (280 + 902 * 45.0, "ah", True), "Profit:MatCost(Bolt, 909)")
    # crates / writs keep the exact order book
    ctx.eq(multi(WC.CostFor(WC, 2996, 909), 2), (None, "short"), "CostFor(909) stays exact")
    check_clean(ctx, c)


@scenario("leveling_auto_learned", "review: recipes learned automatically with the profession (a = 1) are never 'to learn' and cost no training")
def s_level_auto(ctx):
    rows = TAILOR_ROWS.replace('[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" }',
                               '[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t", a = 1 }')
    assert "a = 1" in rows
    c, ck = tailoring_setup(ctx, rows=rows)
    WC = c.WC
    LV = WC.Leveling
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 30, 2387), (30, 40, 3915)], "plan steps (shirt automatic at 30)")
    ctx.eq([int(x.recipeID) for x in lua_list(plan.learn)], [], "plan.learn (nothing to learn at a trainer)")
    ctx.eq((fnum(plan.learnCost or 0), int(plan.learnCostUnknown or 0)), (0.0, 0), "learnCost / learnCostUnknown")
    c_bolt, c_shirt = 6 + 1 / 0.96, 5 + harmonic(35, 40, 60, 35)
    ctx.eq(fnum(plan.total), 1195 - (c_bolt * 40 + 3 * 28.5 + c_shirt * 57), "plan.total without training")
    # a trainer that lists it anyway changes nothing
    c.close_ah()
    visit_trainer(c, late_names=False)
    c.close_trainer(); c.advance(1)
    plan = LV.Plan(LV, ck, 197, 20, 40)
    ctx.eq(([int(x.recipeID) for x in lua_list(plan.learn)], fnum(plan.learnCost or 0)), ([], 0.0), "plan.learn / learnCost after a trainer visit")
    check_clean(ctx, c)


@scenario("craft_tab_lazy", "review: building the Crafting tab in profit mode decodes no recipe-data line itself (only Profit:Craft reads the character's own lines)")
def s_craft_lazy(ctx):
    c = ctx.client()
    WC = c.WC
    decoded = lambda: sorted(int(sl) for sl in lua_list(WC.RECIPE_LINES) if c.eval("local R, sl = ...; return rawget(R, sl) ~= nil", WC.RECIPES, sl))
    # who decodes: wrap the lazy table's __index and keep the Lua stack of every first read of a line
    c.eval("""local WC, M = ...
      local mt = getmetatable(WC.RECIPES)
      local orig = mt and mt.__index
      local traceback = debug.traceback      -- looked up here: inside the hook the caller is addon code
      M.decodes = {}
      if type(orig) == "function" then
        mt.__index = function(t, sl) M.decodes[#M.decodes + 1] = { sl = sl, tb = traceback("", 2) }; return orig(t, sl) end
      end""", WC, c.M)
    c.g("GetrichDB").craftMode = "profit"
    c.slash("/gr craft")
    c.advance(1)
    WC.Fire(WC, "PRICES_UPDATED", "test")
    c.advance(1)
    ctx.check(any(x.strip() for x in visible_tab_texts(c)), "craft tab is empty")
    mine = {int(sl) for sl in lua_keys(WC.Recipes.Professions(WC.Recipes))}
    ctx.check(set(decoded()) <= mine, "lines of professions the character does not have were decoded: %s (has %s)" % (decoded(), sorted(mine)))
    by_ui = [(int(d.sl), str(d.tb)) for d in lua_list(c.M.decodes) if "UICraft.lua" in str(d.tb) and "Profit.lua" not in str(d.tb)]
    ctx.check(not by_ui, "the Crafting tab (profit mode) decoded recipe lines itself: %s\n%s" % ([x[0] for x in by_ui], by_ui[0][1] if by_ui else ""))
    check_clean(ctx, c)


# ===================================================================================================================
# 2026.11.0: live game (level cap 60, one Auction House per ruleset and faction)
# ===================================================================================================================
@scenario("artisan_crates", "2026.11.0: 30 crates incl. 8 Artisan (level 35); their Favor is a guess until a turn-in is recorded; guesses never price the receipt")
def s_artisan(ctx):
    c = ctx.client()
    WC = c.WC
    crates = lua_list(WC.CRATES)
    ctx.eq(len(crates), 30, "crates")
    art = [x for x in crates if x.tier == 4]
    ctx.eq(len(art), 8, "Artisan crates")
    ctx.check(all(x.lvl == 35 and x.unconfirmed for x in art), "Artisan crates: level 35, unconfirmed")
    ctx.eq(sorted(x.favor for x in art), [20] * 5 + [40] * 3, "Artisan Favor placeholders (white 20, green 40)")
    ctx.eq(str(WC.TIER_NAME[4]), "Artisan" if c.locale == "enUS" else "工匠", "tier 4 name")
    # only Artisan Ore is for sale and fillable: it ranks, but as a guess, and BestPerFavor ignores it
    c.set_listings(248697, [(1000, 3)])
    c.set_listings(10620, [(10, 500)])
    c.open_ah()
    full_search(c, "crates")
    ev = {int(e.crate.id): e for e in lua_list(c.eval("local WC = ...; return WC:EvaluateCrates()", WC))}
    e = ev[248697]
    ctx.eq(str(e.status), "ok", "Artisan Ore status")
    ctx.eq(str(e.rewardState), "guess", "Artisan Ore reward state")
    ctx.eq(fnum(e.perFavor), (1000 + 200 - 1000) / 20.0, "Artisan Ore cost per Favor with the placeholder (crate 1000 + 20 x 10 - 10 s) / 20")
    ctx.check(ev[248697].locked, "a level 25 character can't open a level 35 crate")
    ctx.check(first(c.eval("local WC = ...; return WC:BestPerFavor()", WC)) is None, "a guessed reward must not become the Favor price used for the receipt")
    c.slash("/gr crates")
    ctx.check(any("20?" in t for t in c.texts()), "the crate row should mark a guessed reward with '?': %s" % [t for t in c.texts() if "Favor" in t][:6])
    # the first real turn-in: quest 91902 (white Artisan) pays 25 Favor and 12 s 50 c
    c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 125, 25, 0, 0)
    c.fire("QUEST_TURNED_IN", 91902, 0, 1250)
    c.advance(1)
    e = [x for x in lua_list(c.eval("local WC = ...; return WC:EvaluateCrates()", WC)) if x.crate.id == 248697][0]
    ctx.eq((str(e.rewardState), fnum(e.favor), fnum(e.silver)), ("seen", 25, 1250), "after the turn-in: recorded Favor and money")
    ctx.eq(fnum(e.perFavor), 0, "net cost 1000 + 200 - 1250 < 0 -> 0 per Favor")
    check_clean(ctx, c)


@scenario("crate_reward_records", "2026.11.0: recorded turn-ins: money always; Favor of a confirmed crate only when lower or seen 3 times (a Performance Bonus double is not the base)")
def s_reward_records(ctx):
    c = ctx.client()
    WC = c.WC
    reward = lambda cid: tuple(multi(c.eval("local WC, id = ...; for _, x in ipairs(WC.CRATES) do if x.id == id then return WC:CrateReward(x) end end", WC, cid), 4))
    ctx.eq(reward(248683)[:3], (5, 250, "data"), "Apprentice Ore, built-in")
    # one turn-in that the Performance Bonus doubled (10 Favor), paying 3 s
    c.fire("QUEST_TURNED_IN", 91899, 0, 300)
    c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 10, 10, 0, 0)
    ctx.eq(reward(248683)[:3], (5, 300, "data"), "one doubled turn-in: Favor stays 5, money is what the game paid")
    # unrelated: another currency, a Favor loss, another quest, a gain long after the turn-in
    c.fire("CURRENCY_DISPLAY_UPDATE", 1, 50, 50, 0, 0)
    c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 0, -15, 0, 0)
    c.fire("QUEST_TURNED_IN", 94219, 0, 0)
    c.fire("QUEST_TURNED_IN", 91899, 0, 300)
    c.advance(10)
    c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 60, 50, 0, 0)
    ctx.eq(int(c.g("GetrichDB").crateObs[91899].n), 1, "only the matched turn-in is recorded")
    # two normal turn-ins: three seen, the smallest (5) is the base
    for _ in range(2):
        c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 5, 5, 0, 0)
        c.fire("QUEST_TURNED_IN", 91899, 0, 300)
        c.advance(5)
    ctx.eq(reward(248683), (5, 300, "seen", 3), "three turn-ins seen")
    # the game changed the reward: green Journeyman (quest 91905, built-in 20) pays 16
    c.fire("CURRENCY_DISPLAY_UPDATE", 3402, 16, 16, 0, 0)
    c.fire("QUEST_TURNED_IN", 91905, 0, 800)
    ctx.eq(reward(248706)[:3], (16, 800, "seen"), "a lower reward is believed at once")
    ctx.eq(reward(248705)[:3], (16, 800, "seen"), "... for every green Journeyman crate")
    ctx.eq(reward(248688)[:3], (10, 500, "data"), "... not for the white ones")
    check_clean(ctx, c)



@scenario("markets", "search results are kept per Auction House (faction, neutral apart); Auctionator's prices are used only at the house its scan was seen at; a neutral house costs sales at 15%")
def s_markets(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    db = c.g("GetrichDB")
    ctx.eq(str(db.market), "Classic Beta PvP 2|Horde", "market after login")
    ctx.eq(fnum(c.eval("local WC = ...; return WC:AHCut()", WC)), 0.05, "faction house cut")
    cost = lambda: multi(c.eval("local WC = ...; return WC:CostForAny(2770, 20)", WC), 2)
    c.set_listings(2770, [(40, 100)])
    c.open_ah()
    c.advance(1)
    auctionator_scan_ah(c)                              # Auctionator's full scan, seen at the Horde house
    ctx.eq(ext_state(c), (True, None), "Auctionator's scan at the Horde house is in use there")
    ctx.eq(cost(), (800, "est"), "Copper Ore x 20 at the Horde house, from Auctionator")
    search_exact(c, [2770])
    ctx.eq(cost(), (800, "ok"), "Copper Ore x 20 at the Horde house, searched")
    c.close_ah()
    # a neutral auctioneer: its own (empty) market, 15% cut, a chat line; the Horde scan's prices are not this house's
    c.M.auctioneer = c.lua.table_from({"npcID": 8661, "name": "Auctioneer Beardo", "neutral": True})
    c.set_listings(2770, [(90, 100)])
    c.open_ah()
    ctx.eq(str(db.market), "Classic Beta PvP 2|Neutral", "market at a neutral auctioneer")
    ctx.eq(fnum(c.eval("local WC = ...; return WC:AHCut()", WC)), 0.15, "neutral house cut")
    ctx.eq(ext_state(c), (False, "other"), "Auctionator's last scan was at the Horde house: not used at the neutral one")
    ctx.eq(cost(), (None, None), "the neutral house starts without the Horde prices")
    ctx.check(any("15%" in str(m) for m in c.chat), "chat line about the neutral house: %s" % list(c.chat)[-3:])
    n = len(c.chat)
    c.advance(3)
    ctx.check(any("Classic Beta PvP 2|Horde" in str(m) for m in c.chat[n:]), "the chat should say that the prices are another house's: %s" % c.chat[n:])
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.check(not ok, "nothing to check without this house's prices")
    auctionator_scan_ah(c, background=600000)           # ... until Auctionator scans here (other prices, as at another house)
    ctx.eq(ext_state(c), (True, None), "Auctionator's scan at the neutral house is in use there")
    ctx.eq(cost(), (1800, "est"), "Copper Ore x 20 at the neutral house, from Auctionator")
    search_exact(c, [2770])
    ctx.eq(cost(), (1800, "ok"), "Copper Ore x 20 at the neutral house, searched")
    c.close_ah()
    ctx.eq(str(db.market), "Classic Beta PvP 2|Horde", "back to the faction market when the neutral house closes")
    # Auctionator's database now holds the neutral house's prices: the Horde house keeps its own search results only
    ctx.eq(ext_state(c), (False, "other"), "Auctionator's last scan was at the neutral house: not used at the Horde one")
    ctx.eq(cost(), (800, "ok"), "the Horde search results are back")
    ctx.eq(fnum(c.eval("local WC = ...; return WC:AHCut()", WC)), 0.05, "faction cut again")
    ctx.eq(fnum(db.markets["Classic Beta PvP 2|Neutral"].results[2770].min), 90, "the neutral search results are parked")
    # a faction auctioneer is not neutral
    c.M.auctioneer = c.lua.table_from({"npcID": 8672, "name": "Auctioneer Thathung"})
    c.open_ah()
    ctx.eq(str(db.market), "Classic Beta PvP 2|Horde", "market at a Horde auctioneer")
    c.close_ah()
    # clearing the search results clears every house; which house Auctionator's scan was seen at is kept
    WC.Settings.Clear(WC.Settings, "scans")
    ctx.eq(cost(), (None, None), "Clear search results: nothing left at the Horde house")
    ctx.check(db.markets["Classic Beta PvP 2|Neutral"].results is None, "Clear search results empties all houses")
    ctx.eq(ext_state(c), (False, "other"), "... and the neutral scan is still not taken for the Horde house's")
    check_clean(ctx, c)



@scenario("markets_login", "logging in on a character of another faction parks the other house's search results and history; an old database is adopted as this character's house")
def s_markets_login(ctx):
    now = SERVER_TIME0
    sv = ("GetrichDB = { resultsFormat = 3, market = 'Classic Beta PvP 2|Alliance', "
          "results = { [2770] = { status = 'listed', entries = { { 55, 100 } }, min = 55, avail = 100, time = %d } }, "
          "scannedAt = { crates = %d }, history = { [2770] = { h = { [%d] = { min = 55, qty = 100 } }, d = {} } }, "
          "browse = { full = %d, items = { [2770] = { min = 55, qty = 100, t = %d } } } }") % (now, now, now // 3600, now, now)
    c = ctx.client(sv=sv)
    WC = c.WC
    db = c.g("GetrichDB")
    ctx.eq(str(db.market), "Classic Beta PvP 2|Horde", "market after logging in on the Horde character")
    ctx.check(db.results[2770] is None and db.history[2770] is None and not db.scannedAt.crates,
              "the Alliance house's prices must not show for the Horde character")
    park = db.markets["Classic Beta PvP 2|Alliance"]
    ctx.eq((fnum(park.results[2770].min), fnum(park.history[2770].h[now // 3600].min)), (55, 55), "parked Alliance prices")
    ctx.check(db.browse is None and park.browse is None, "the browse snapshot of 2026.11.1 and older is dropped, also from a parked house")
    ctx.check(c.eval("local WC = ...; return rawequal(WC.Scanner.results, GetrichDB.results)", WC), "the Scanner must write into the loaded house's table")
    c.slash("/gr crates")
    c.set_listings(2770, [(40, 100)])
    c.open_ah()
    search_exact(c, [2770])
    ctx.eq(fnum(first(c.eval("local WC = ...; return (WC:CostFor(2770, 20))", WC))), 800, "Horde price after a search")
    ctx.eq(fnum(db.markets["Classic Beta PvP 2|Alliance"].results[2770].min), 55, "Alliance price untouched by the Horde search")
    check_clean(ctx, c)
    # a database from before 2026.11.0 has no market: its prices become this character's house
    old = "GetrichDB = { resultsFormat = 3, results = { [2770] = { status = 'listed', entries = { { 61, 100 } }, min = 61, avail = 100, time = %d } } }" % now
    c2 = ctx.client(sv=old)
    db2 = c2.g("GetrichDB")
    ctx.eq(str(db2.market), "Classic Beta PvP 2|Horde", "an old database is adopted")
    ctx.eq(fnum(db2.results[2770].min), 61, "... with its prices")
    ctx.check(db2.markets is None, "... and nothing parked")
    check_clean(ctx, c2)


# ===================================================================================================================
# 2026.11.1: markets keyed by ruleset
# ===================================================================================================================

@scenario("market_ruleset", "2026.11.1: in Forever (regional unique names) the Auction House key is the ruleset, not the realm name; a 2026.11.0 database keyed by realm is renamed")
def s_market_ruleset(ctx):
    now = SERVER_TIME0
    sv = ("GetrichDB = { resultsFormat = 3, market = 'Classic Beta PvP 2|Horde', "
          "results = { [2770] = { status = 'listed', entries = { { 55, 100 } }, min = 55, avail = 100, time = %d } }, "
          "markets = { ['Classic Beta PvP 2|Neutral'] = { results = { [2770] = { status = 'listed', entries = { { 90, 100 } }, min = 90, avail = 100, time = %d } } } } }") % (now, now)
    c = ctx.client(sv=sv, login=False)
    c.eval("""rawset(_G, "RegionalUniqueNamesEnabled", function() return true end)
      rawset(Enum, "GameRule", { PvPRuleset = 101, RPRuleset = 102, HardcoreRuleset = 103 })
      rawset(C_GameRules, "IsGameRuleActive", function(rule) return rule == 101 end)""")
    c.login()
    WC = c.WC
    db = c.g("GetrichDB")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store.RulesetName()", WC))), "PvP", "ruleset")
    ctx.eq(str(db.market), "Forever PvP|Horde", "market key by ruleset")
    ctx.eq(fnum(db.results[2770].min), 55, "the prices keyed by realm name in 2026.11.0 are kept under the new key")
    ctx.check(db.markets["Forever PvP|Horde"] is None and db.markets["Classic Beta PvP 2|Horde"] is None, "nothing parked under either Horde key")
    c.M.auctioneer = c.lua.table_from({"npcID": 8661, "name": "Auctioneer Beardo", "neutral": True})
    c.open_ah()
    ctx.eq(str(db.market), "Forever PvP|Neutral", "neutral house key by ruleset")
    ctx.eq(fnum(db.results[2770].min), 90, "the neutral prices of 2026.11.0 moved to the new key")
    c.close_ah()
    ctx.eq((str(db.market), fnum(db.results[2770].min)), ("Forever PvP|Horde", 55), "back at the faction house")
    ctx.check(db.markets["Classic Beta PvP 2|Neutral"] is None, "old neutral key gone")
    # RP + PvP, and no rule at all
    c.eval("rawset(C_GameRules, 'IsGameRuleActive', function(rule) return rule == 101 or rule == 102 end)")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store.RulesetName()", WC))), "RPPvP", "RP-PvP ruleset")
    c.eval("rawset(C_GameRules, 'IsGameRuleActive', function(rule) return rule == 103 end)")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store.RulesetName()", WC))), "HC", "Hardcore ruleset")
    c.eval("rawset(C_GameRules, 'IsGameRuleActive', function(rule) return rule == 103 or rule == 101 end)")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store.RulesetName()", WC))), "HCPvP", "Hardcore with the PvP rule: not the same key as the PvP ruleset")
    c.eval("rawset(C_GameRules, 'IsGameRuleActive', function(rule) return false end)")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store.RulesetName()", WC))), "PvE", "normal ruleset")
    # realms as before (no regional unique names): the realm name is the key
    c.eval("rawset(_G, 'RegionalUniqueNamesEnabled', function() return false end)")
    ctx.eq(str(first(c.eval("local WC = ...; return WC.Store:MarketKey(false)", WC))), "Classic Beta PvP 2|Horde", "with realms: realm name + faction")
    check_clean(ctx, c)

    # After a session in which the ruleset could not be read, the database is keyed by realm again and the real
    # prices are parked under the ruleset key. The next login with the ruleset must bring those back, not rename
    # the realm-keyed leftovers over them.
    sv = ("GetrichDB = { resultsFormat = 3, market = 'Classic Beta PvP 2|Horde', "
          "results = { [2771] = { status = 'listed', entries = { { 7, 1 } }, min = 7, avail = 1, time = %d } }, "
          "markets = { ['Forever PvP|Horde'] = { results = { [2770] = { status = 'listed', entries = { { 55, 100 } }, min = 55, avail = 100, time = %d } } } } }") % (now, now)
    c = ctx.client(sv=sv, login=False)
    c.eval("""rawset(_G, "RegionalUniqueNamesEnabled", function() return true end)
      rawset(Enum, "GameRule", { PvPRuleset = 101, RPRuleset = 102, HardcoreRuleset = 103 })
      rawset(C_GameRules, "IsGameRuleActive", function(rule) return rule == 101 end)""")
    c.login()
    db = c.g("GetrichDB")
    ctx.eq(str(db.market), "Forever PvP|Horde", "ruleset key again")
    ctx.check(db.results[2770] is not None and fnum(db.results[2770].min) == 55, "the prices parked under the ruleset key are loaded")
    ctx.check(db.results[2771] is None, "the realm-keyed leftovers are not mixed in")
    ctx.check(db.markets["Classic Beta PvP 2|Horde"] is not None, "... they are parked under the realm key")
    check_clean(ctx, c, "ruleset unreadable for a session")


# ===================================================================================================================
# 2026.11.2: prices from Auctionator, no scanning; the check buttons search a handful of entries exactly
# ===================================================================================================================
def auctionator_dump(c):
    """Auctionator's database of client c: {itemID: (price, age in days)}."""
    a, b = c.eval("local a, b = {}, {} for id, p in pairs(Auctionator.prices) do a[id] = p[1]; b[id] = p[2] end return a, b")
    return {int(k): (int(a[k]), int(b[k])) for k in a.keys()}


def auctionator_load(c, dump):
    """Give client c Auctionator with the database `dump` (what Auctionator saved in an earlier session)."""
    install_auctionator(c)
    c.eval("local p, a = ...; for id, v in pairs(p) do Auctionator.prices[id] = { v, a[id] } end",
           c.lua.table_from({k: v[0] for k, v in dump.items()}), c.lua.table_from({k: v[1] for k, v in dump.items()}))
    if c.WC.External is not None:
        c.eval("local WC = ...; WC.External:Invalidate()", c.WC)


def ext_info(c):
    """(exact, age text) of the prices in use."""
    return multi(c.eval("local WC = ...; local X = WC.External; X:Invalidate(); local s = X:State(); return s.exact, X:AgeText()", c.WC), 2)


def watched_lines(c, start=0):
    return [m for m in c.chat[start:] if str(c.WC.L.EXT_WATCHED) in str(m)]


@scenario("auctionator_login", "2026.11.2: Auctionator's prices are in use right after login, AH closed, nothing searched: ranking, estimates, age by the day, sold-out items")
def s_auc_login(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    setup_market_130(c)
    auctionator_scan_ah(c, fire=False)        # Auctionator's database from an earlier session (Getrich never saw the scan)
    ctx.eq(ext_state(c), (True, None), "Auctionator's prices in use at login")
    ctx.eq(ext_info(c), (False, str(WC.L.EXT_TODAY)), "a scan Getrich did not see is dated by its day")
    crates = lua_list(c.eval("local WC = ...; return WC:VisibleCrates(WC:EvaluateCrates())", WC))
    ranked = [e for e in crates if e.perFavor]
    ctx.check(len(ranked) >= 10, "crates ranked from Auctionator's prices alone: %d" % len(ranked))
    ctx.check(all(e.est for e in ranked), "every crate price is an estimate until it is checked")
    writs = [e for e in lua_list(c.eval("local WC = ...; return WC:VisibleWrits(WC:EvaluateWrits())", WC)) if e.perRep]
    ctx.check(len(writs) >= 5 and all(e.est for e in writs), "writs ranked from Auctionator's prices alone, as estimates: %d" % len(writs))
    best, est = multi(c.eval("local WC = ...; return WC:BestPerFavor()", WC), 2)
    ctx.check(best is not None and est is True, "BestPerFavor is an estimate: %s %s" % (best, est))
    # the window, Auction House closed
    c.slash("/gr crates")
    c.advance(1)
    t = c.texts()
    ctx.check(any("~" in x for x in t), "estimates are marked with ~ on the crates tab")
    ctx.check(any("Auctionator" in x and str(WC.L.EXT_TODAY) in x for x in t), "the bar says the prices are Auctionator's, from today: %s" % [x for x in t if "Auctionator" in x][:3])
    ctx.eq(len(c.chat), 0, "nothing to say in the chat: %s" % list(c.chat))
    st = c.ah_stats()
    ctx.eq((st["searches"], st["browses"]), (0, 0), "nothing was asked of the Auction House")
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.check(not ok, "a check needs the Auction House open")
    # older data
    auctionator_new_day(c)
    ctx.eq(ext_info(c), (False, str(WC.L.EXT_YESTERDAY)), "one day later")
    auctionator_new_day(c)
    ctx.eq(ext_info(c), (False, str(WC.L.EXT_DAYS).replace("%d", "2")), "two days later")
    ctx.eq(ext_state(c), (True, None), "old prices are still used (their age is shown)")
    # an item Auctionator saw before its last full scan but not in it: sold out. One it saw after it: for sale.
    c.eval("Auctionator.prices[2775] = { 33, 5 }; Auctionator.prices[2776] = { 44, 0 }")
    c.eval("local WC = ...; WC.External:Invalidate()", WC)
    ctx.eq(multi(WC.CostForAny(WC, 2775, 3), 2), (None, "none"), "Silver Ore: last seen before the full scan -> not for sale")
    cost, status, info = multi(WC.CostForAny(WC, 2776, 3), 3)
    ctx.eq((cost, status, info and info.source), (132, "est", "auctionator"), "Gold Ore: seen after the full scan -> 3 x 44")
    c.eval("Auctionator.prices[3858] = nil")
    c.eval("local WC = ...; WC.External:Invalidate()", WC)
    ctx.eq(multi(WC.CostForAny(WC, 3858, 1), 2), (None, "none"), "Mithril Ore: Auctionator has never seen it -> not for sale")
    ctx.eq(first(WC.UnitPrice(WC, 2775)), None, "UnitPrice of a sold-out item")
    check_clean(ctx, c)


@scenario("auctionator_relog", "2026.11.2: a scan Getrich watched is dated to the minute and still is after logging out and in; a record too old to be Auctionator's last scan is not used")
def s_auc_relog(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(2)
    auctionator_scan_ah(c)                    # Auctionator's full scan, with Getrich watching
    t_scan = c.server_time()
    ctx.eq(len(watched_lines(c)), 1, "one chat line when Auctionator finished its scan: %s" % list(c.chat))
    db = c.g("GetrichDB")
    rec = db.extScans[db.market]
    ctx.check(rec is not None and int(rec.t) == t_scan and len(lua_list(rec.ids)) >= 10, "the scan is noted for this house: %s" % (rec and (rec.t, len(lua_list(rec.ids))),))
    c.advance(600)
    ctx.eq(ext_info(c), (True, str(WC.L.EXT_AGO) % (str(WC.L.UI_AGE_MIN) % 10)), "ten minutes later")
    best1 = multi(c.eval("local WC = ...; return WC:BestPerFavor()", WC), 2)
    c.close_ah()
    text = c.logout_sv()
    dump = auctionator_dump(c)
    # the next session, 3 hours later: nothing scanned, Auction House not even opened
    c2 = ctx.client(sv=text, login=False, server_time=t_scan + 3 * 3600)
    auctionator_load(c2, dump)
    c2.login()
    WC2 = c2.WC
    ctx.eq(ext_state(c2), (True, None), "prices in use right after the next login")
    ctx.eq(ext_info(c2), (True, str(WC2.L.EXT_AGO) % (str(WC2.L.UI_AGE_HOUR) % 3)), "the age of the scan is still known")
    best2 = multi(c2.eval("local WC = ...; return WC:BestPerFavor()", WC2), 2)
    ctx.eq(best2, best1, "the same best crate price as before logging out")
    ctx.eq((c2.ah_stats()["searches"], c2.ah_stats()["browses"]), (0, 0), "nothing searched")
    # Auctionator scanned again while Getrich was not loaded, two days later: the record of the old scan is not its date
    c3 = ctx.client(sv=text, login=False, server_time=t_scan + 50 * 3600)
    auctionator_load(c3, dump)                # (every price seen "today": the scan is from the day of this session)
    c3.login()
    ctx.eq(ext_state(c3), (True, None), "prices in use")
    ctx.eq(ext_info(c3), (False, str(c3.WC.L.EXT_TODAY)), "a record from 50 hours ago cannot date a scan of today")
    check_clean(ctx, c)
    check_clean(ctx, c2, "next session")
    check_clean(ctx, c3, "two days later")


@scenario("auctionator_watch", "2026.11.2: what counts as Auctionator's full scan (many crate and writ items at once), single searches, scans stored in parts, without a callback, right before the AH closes")
def s_auc_watch(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    db = c.g("GetrichDB")
    setup_market_130(c)
    count_price_fires(c)
    fires = lambda: len(lua_list(c.M.priceFires))
    scans = lambda: int(c.eval("local M = ...; return M.extScanFires or 0", c.M))
    c.eval("local WC, M = ...; WC:On('EXTERNAL_SCAN', function() M.extScanFires = (M.extScanFires or 0) + 1 end)", WC, c.M)
    c.open_ah()
    c.advance(2)
    # a search for one item in Auctionator: the price is used at once, but it is not a scan
    auctionator_update(c, {2770: 77})
    ctx.eq(ext_state(c), (False, "noscan"), "one item is not a full scan")
    # a shopping list of crate materials (many items, but no writ items): not a scan either
    auctionator_update(c, {i: 500 + k for k, i in enumerate(AUC_BACKGROUND_CRATE)})
    ctx.eq(ext_state(c), (False, "noscan"), "crate materials alone are not a full scan")
    ctx.eq((len(watched_lines(c)), db.extScans[db.market], scans()), (0, None, 0), "nothing noted so far")
    # the full scan
    n0 = fires()
    auctionator_scan_ah(c)
    t1 = c.server_time()
    ctx.eq(ext_state(c), (True, None), "the full scan is in use")
    ctx.eq((len(watched_lines(c)), scans()), (1, 1), "announced once")
    ctx.eq(int(db.extScans[db.market].t), t1, "noted with its time")
    ctx.check(fires() > n0, "PRICES_UPDATED after the scan")
    ctx.eq(first(WC.UnitPrice(WC, 2589)), 10, "Linen Cloth from the scan")
    # later single searches: prices follow, the scan's date stays
    c.advance(120)
    n0 = fires()
    auctionator_update(c, {2589: 9})
    ctx.eq(first(WC.UnitPrice(WC, 2589)), 9, "a single search in Auctionator updates the price at once")
    ctx.check(fires() > n0, "PRICES_UPDATED after a single search")
    ctx.eq((int(db.extScans[db.market].t), len(watched_lines(c)), scans()), (t1, 1, 1), "a single search is not a new scan")
    # a second scan, stored in two parts and without telling anyone: found by the look every 5 seconds, announced once
    c.advance(600)
    c.eval("""local WC, crateBg = ...
      for _, id in pairs(crateBg) do Auctionator.prices[id] = { 610000, 0 } end""", WC, c.lua.table_from(AUC_BACKGROUND_CRATE))
    c.advance(6)
    ctx.eq(len(watched_lines(c)), 1, "half a scan (crate items only) is not announced")
    c.eval("local WC = ...; for i = 1, 8 do Auctionator.prices[WC.WRITS[i].item] = { 610000 + i, 0 } end", WC)
    c.advance(6)
    t2 = int(db.extScans[db.market].t)
    ctx.check(t2 > t1 + 600, "the second scan is noted with its own time (%d after the first)" % (t2 - t1))
    ctx.eq((len(watched_lines(c)), scans()), (2, 2), "the second scan is announced once")
    c.advance(30)
    ctx.eq((len(watched_lines(c)), scans(), int(db.extScans[db.market].t)), (2, 2, t2), "nothing more while nothing changes")
    # Auctionator calling back 500 times while it stores something costs one look, not 500
    c.advance(10)
    n_sample = int(c.eval("local WC = ...; local n = 0 for _, w in ipairs(WC.WRITS) do n = n + 2 end for _, x in ipairs(WC.CRATES) do n = n + 1 + #x.opts end return n", WC))
    c.eval("Auctionator.calls = 0; for i = 1, 500 do for _, fn in ipairs(Auctionator.callbacks) do fn() end end")
    c.advance(1)
    calls = int(c.eval("return Auctionator.calls"))
    ctx.check(0 < calls <= 2 * n_sample, "500 callbacks at once made %d API calls (one look is at most %d)" % (calls, 2 * n_sample))
    # midnight: Auctionator's day counter moves on while the Auction House is open. Every age goes up by one, no
    # price changes: that is not a scan, and the scan Getrich saw keeps its date
    auctionator_new_day(c)
    c.advance(12)
    ctx.eq((len(watched_lines(c)), scans(), int(db.extScans[db.market].t)), (2, 2, t2), "the day counter moving on is not a scan")
    ctx.eq(ext_state(c), (True, None), "the prices stay in use after midnight")
    ctx.eq(ext_info(c)[0], True, "... and the scan keeps the time Getrich saw it at")
    # a third scan finishes just before the Auction House is closed: the last look catches it
    c.advance(300)
    c.eval("""local WC, crateBg = ...
      for _, id in pairs(crateBg) do Auctionator.prices[id] = { 620000, 0 } end
      for i = 1, 8 do Auctionator.prices[WC.WRITS[i].item] = { 620000 + i, 0 } end""", WC, c.lua.table_from(AUC_BACKGROUND_CRATE))
    c.advance(1)
    key = str(db.market)
    c.close_ah()
    t3 = int(db.extScans[key].t)
    ctx.check(t3 > t2 + 300, "the scan right before closing is noted for the house that was open")
    ctx.eq(len(watched_lines(c)), 3, "... and announced")
    # with the Auction House closed nothing looks any more
    c.advance(60)
    ctx.check(not c.running_timers(), "timers with the AH closed: %s" % c.running_timers())
    # history: the watched scans recorded the items Getrich follows
    H = c.server_time() // 3600
    rec = db.history[2589] and db.history[2589].h[H]
    ctx.check(rec is not None and int(rec.min) == 9 and rec.qty is None, "history record of Linen Cloth from the watched scan: %s" % (rec and (rec.min, rec.qty),))
    # the Prices tab draws records without a quantity (Auctionator does not know how many are listed)
    WC.Store.SetWatch(WC.Store, 2589, True)
    c.slash("/gr history")
    c.advance(1)
    ctx.check(any("Linen Cloth" in x for x in c.texts(clip=True)), "Prices tab does not list the watched Linen Cloth")
    for w in c.regions(c.g("GetrichFrame")):
        if w.IsVisible(w):
            c.hover(w)
    check_clean(ctx, c)


@scenario("auctionator_missing", "2026.11.2: without Auctionator, or before its first full scan, Getrich says what is missing (once per session) and checks nothing")
def s_auc_missing(ctx):
    # no Auctionator at all
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    ctx.eq(ext_state(c), (False, "noapi"), "no Auctionator")
    c.open_ah()
    c.advance(3)
    hint = str(WC.L.EXT_NOAPI)
    ctx.eq(sum(1 for m in c.chat if hint in str(m)), 1, "one hint in the chat after opening the Auction House: %s" % list(c.chat))
    t = c.texts()
    ctx.check(any(hint in x for x in t), "the bar says what is missing")
    c.advance(30)
    st = c.ah_stats()
    ctx.eq((st["searches"], st["browses"]), (0, 0), "nothing is asked of the Auction House")
    c.close_ah()
    c.open_ah()
    c.advance(3)
    ctx.eq(sum(1 for m in c.chat if hint in str(m)), 1, "the hint is not repeated in the same session")
    n = len(c.chat)
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.check(not ok and not WC.Scanner.active, "nothing to check without prices")
    ctx.check(any(hint in str(m) for m in c.chat[n:]), "pressing the check button says why: %s" % c.chat[n:])
    ranked = [e for e in lua_list(c.eval("local WC = ...; return WC:EvaluateCrates()", WC)) if e.perFavor]
    ctx.eq(len(ranked), 0, "no prices -> nothing ranked")
    for tab in TABS:
        c.slash("/gr " + tab)
        c.advance(0.3)
    check_clean(ctx, c, "no Auctionator")
    # Auctionator installed, but it has only searched a few items so far
    c2 = ctx.client(login=False)
    install_auctionator(c2)
    c2.login()
    WC2 = c2.WC
    setup_market_130(c2)
    auctionator_update(c2, {2770: 40, 2589: 10, 2318: 400}, fire=False)
    ctx.eq(ext_state(c2), (False, "noscan"), "no full scan yet")
    ctx.eq(multi(WC2.CostForAny(WC2, 2770, 1), 2), (None, None), "single prices are not used without a full scan")
    c2.open_ah()
    c2.advance(3)
    hint2 = str(WC2.L.EXT_NOSCAN)
    ctx.eq(sum(1 for m in c2.chat if hint2 in str(m)), 1, "one hint about the missing full scan: %s" % list(c2.chat))
    # ... then the player runs Auctionator's full scan: everything is there, without doing anything in Getrich
    auctionator_scan_ah(c2)
    ctx.eq(ext_state(c2), (True, None), "prices in use as soon as Auctionator's scan is stored")
    ctx.eq(len(watched_lines(c2)), 1, "the scan is announced")
    ranked = [e for e in lua_list(c2.eval("local WC = ...; return WC:EvaluateCrates()", WC2)) if e.perFavor]
    ctx.check(len(ranked) >= 10, "crates ranked after the scan: %d" % len(ranked))
    c2.advance(1)
    t = c2.texts()
    ctx.check(any("Auctionator" in x and str(WC2.L.UI_AGE_MIN) % 1 in x for x in t), "the bar shows the new scan's age: %s" % [x for x in t if "Auctionator" in x][:3])
    ctx.check(not any(hint2 in x for x in t), "the bar no longer says a scan is missing")
    check_clean(ctx, c2, "no full scan")


# seven crates for sale; Strange Dust has one unit at 20c and the rest at 700c (a single cheap listing)
DEPTH_MARKET = {
    248685: [(1000, 5)], 10940: [(20, 1), (700, 500)],      # A: Apprentice Enchanting: 20 Strange Dust
    248683: [(1200, 5)], 2770: [(60, 500)],                 # B: Apprentice Ore: 20 Copper Ore
    248684: [(1500, 3)], 2589: [(30, 400)],                 # C: Apprentice Cloth: 40 Linen Cloth
    248702: [(4000, 2)], 2996: [(150, 100)],                # D: 20 Bolt of Linen Cloth
    248703: [(5000, 2)], 2840: [(200, 100)],                # E: 20 Copper Bar
    248704: [(6000, 2)], 4359: [(250, 100)],                # F: 16 Handful of Copper Bolts
    248688: [(7000, 2)], 2592: [(300, 100)],                # G: 20 Wool Cloth
}


@scenario("check_crates_depth", "2026.11.2: 'Check the best' searches the best five crates exactly; a single cheap listing no longer makes a crate the best; what moves up is checked too")
def s_check_crates(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    c.clear_listings()
    for iid, rows in DEPTH_MARKET.items():
        c.set_listings(iid, rows)
    c.open_ah()
    c.advance(1)
    auctionator_scan_ah(c)
    per = lambda: [(int(e.crate.id), fnum(e.perFavor), bool(e.est)) for e in lua_list(c.eval("local WC = ...; return WC:VisibleCrates(WC:EvaluateCrates())", WC)) if e.perFavor]
    # estimates: cheapest price x quantity. A: (1000 + 20 x 20 - 250) / 5 = 230 -- the bait; B: (1200 + 1200 - 250) / 5 = 430;
    # C: (1500 + 1200 - 250) / 5 = 490; D: (4000 + 3000 - 500) / 10 = 650; E: (5000 + 4000 - 500) / 10 = 850;
    # F: (6000 + 4000 - 500) / 10 = 950; G: (7000 + 6000 - 500) / 10 = 1250
    ctx.eq(per(), [(248685, 230.0, True), (248683, 430.0, True), (248684, 490.0, True), (248702, 650.0, True),
                   (248703, 850.0, True), (248704, 950.0, True), (248688, 1250.0, True)], "estimates before the check")
    ctx.eq(multi(c.eval("local WC = ...; return WC:BestPerFavor()", WC), 2), (230.0, True), "the estimate takes the bait")
    c.slash("/gr crates")
    ok, secs = start_scan(c, "crates")
    ctx.require(ok and not WC.Scanner.active, "the crates check did not run")
    st = c.ah_stats()
    searched = set(st["searchByItem"].keys())
    # round 1: the five best by estimate (A-E), crate + every bundle material. A's real cost: 20 + 19 x 700 = 13320 ->
    # (1000 + 13320 - 250) / 5 = 2814, last. F moves into the best five and is searched in round 2. G is never searched.
    expect = {248685, 10940, 10939, 10978, 11084, 248683, 2770, 2771, 248684, 2589, 2318, 248702, 4231, 2996,
              248703, 2840, 3576, 2841, 248704, 4359, 4361, 4363}
    ctx.eq(searched, expect, "items searched by the check")
    ctx.eq(st["browses"], 0, "no browse query")
    ctx.eq(int(WC.Scanner.round), 2, "rounds of the check")
    ctx.check(secs < 60, "the check took %.0f s" % secs)
    ctx.note("crates check: %d items searched in %.0f s" % (len(searched), secs))
    ctx.eq(per(), [(248683, 430.0, False), (248684, 490.0, False), (248702, 650.0, False), (248703, 850.0, False),
                   (248704, 950.0, False), (248688, 1250.0, True), (248685, 2814.0, False)], "after the check: exact, the bait is last")
    ctx.eq(multi(c.eval("local WC = ...; return WC:BestPerFavor()", WC), 2), (430.0, False), "the best Favor price is exact now")
    ctx.check(c.g("GetrichDB").scannedAt.crates, "the time of the check is kept")
    t = c.texts()
    ctx.check(any(ctx.money(430) in x and "~" not in x for x in t), "the best row shows 4s 30c without ~: %s" % [x for x in t if ctx.money(430) in x][:4])
    # a second check right away finds the same entries (they are searched again: the market may have moved)
    n0 = st["searches"]
    ok, _ = start_scan(c, "crates")
    ctx.check(ok and c.ah_stats()["searches"] > n0, "a second check searches again")
    # Auctionator scans again 20 minutes later: same cheapest prices -> the checked order books still stand
    c.advance(1200)
    auctionator_scan_ah(c, background=510000)
    ctx.eq(per()[0], (248683, 430.0, False), "a new scan with the same cheapest prices keeps the checked crates exact")
    ctx.eq(per()[-1], (248685, 2814.0, False), "... and the bait exposed")
    # the cheap Copper Ore is bought, the next scan sees another price: that crate is an estimate again
    c.set_listings(2770, [(65, 500)])
    c.advance(1200)
    auctionator_scan_ah(c, background=520000)
    e = crate_entry(c, 248683)
    ctx.eq((fnum(e.perFavor), bool(e.est)), ((1200 + 20 * 65 - 250) / 5.0, True), "a changed price in a newer scan replaces the checked one (estimate)")
    check_clean(ctx, c)


@scenario("check_until_exact", "2026.11.2: when Auctionator's best crates are gone from the Auction House, the check goes on, round after round, until the best five on the list are all exact")
def s_check_rounds(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    c.clear_listings()
    # twelve crates with one bundle material each; Auctionator's scan saw all of them
    crates = [x for x in lua_list(WC.CRATES)][:12]
    mats = {}
    for k, x in enumerate(crates):
        o = lua_list(x.opts)[0]
        mats[int(x.id)] = (int(o[1]), int(o[2]))
        c.set_listings(int(x.id), [(1000 + 100 * k, 3)])
        c.set_listings(int(o[1]), [(50, 2000)])
    order = lambda: [(int(e.crate.id), bool(e.est)) for e in lua_list(c.eval("local WC = ...; return WC:VisibleCrates(WC:EvaluateCrates())", WC)) if e.perFavor]
    c.open_ah()
    c.advance(1)
    auctionator_scan_ah(c)
    by_est = [i for i, _ in order()]
    ctx.eq(len(by_est), 12, "twelve crates ranked by estimate")
    # an hour later the seven best crates of the scan are sold out
    c.advance(3600)
    gone = by_est[:7]
    for i in gone:
        c.set_listings(i, [])
    c.slash("/gr crates")
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.require(ok, "the crates check did not start")
    seen_round = set()
    for _ in range(400):
        if not WC.Scanner.active:
            break
        c.advance(0.5)
        if WC.Scanner.active:
            seen_round.add(int(WC.Scanner.round))
            if int(WC.Scanner.round) == 2:
                ctx.check(any((str(WC.L.UI_ROUND_FMT) % (2, str(WC.L.SCAN_PH_QUICK) % 5)) in x for x in c.texts()),
                          "round 2 is not shown in the bar: %s" % [x for x in c.texts() if "5" in x][:5])
    ctx.require(not WC.Scanner.active, "the check did not finish")
    # round 1: the five best by estimate, all gone; round 2: the next five (two more gone, three there);
    # round 3: the two that moved into the best five; then nothing new
    ctx.eq(seen_round, {1, 2, 3}, "rounds")
    after = order()
    ctx.eq([i for i, _ in after], by_est[7:], "what is left on the list: the five crates that are really for sale")
    ctx.check(all(not est for _, est in after), "the best five are all exact after the check: %s" % after)
    searched = set(c.ah_stats()["searchByItem"].keys())
    ctx.check(all(i in searched for i in by_est), "every crate was searched on the way down the list")
    ctx.eq(c.ah_stats()["browses"], 0, "no browse query")
    check_clean(ctx, c)


@scenario("check_writs", "2026.11.2: the writs check searches the best five writs and the items they ask for, nothing else")
def s_check_writs(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(1)
    auctionator_scan_ah(c)
    vis = lambda: [e for e in lua_list(c.eval("local WC = ...; return WC:VisibleWrits(WC:EvaluateWrits())", WC)) if e.perRep and not e.receipt]
    before = vis()
    ctx.check(len(before) >= 6 and all(e.est for e in before), "writs ranked as estimates before the check: %d" % len(before))
    top5 = [(int(e.writ.writ), int(e.writ.item)) for e in before[:5]]
    c.slash("/gr writs")
    ok, secs = start_scan(c, "writs")
    ctx.require(ok and not WC.Scanner.active, "the writs check did not run")
    st = c.ah_stats()
    searched = set(st["searchByItem"].keys())
    all_writ_ids = {int(w.writ) for w in lua_list(WC.WRITS)} | {int(w.item) for w in lua_list(WC.WRITS)}
    ctx.check(searched <= all_writ_ids, "only writs and their items are searched: %s" % sorted(searched - all_writ_ids))
    for w, i in top5:
        ctx.check(w in searched and i in searched, "writ %d and its item %d (best five by estimate) were not searched" % (w, i))
    ctx.check(len(searched) <= 30 and secs < 60, "the check searched %d items in %.0f s" % (len(searched), secs))
    ctx.note("writs check: %d items searched in %.0f s" % (len(searched), secs))
    after = vis()
    ctx.check(all(not e.est for e in after[:5]), "the best five writs are exact after the check: %s" % [(int(e.writ.writ), bool(e.est)) for e in after[:6]])
    ctx.check(c.g("GetrichDB").scannedAt.writs, "the time of the check is kept")
    check_clean(ctx, c)


@scenario("check_craft", "2026.11.2: the crafting check searches what the most profitable recipes buy at the Auction House and what they make; skill-up mode: the route's shopping list")
def s_check_craft(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    c.open_profession(164)
    c.advance(3)
    c.close_profession()
    c.advance(1)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "craft")
    ctx.check(not ok, "nothing to check before Auctionator has prices")
    auctionator_scan_ah(c)
    P = WC.Profit
    e = P.CraftEntry(P, 9983)
    # Copper Claymore from Auctionator's cheapest prices: 1 Light Leather 30 + 10 Copper Bar x 50 + 2 Weak Flux (vendor) 200
    # + 1 Rough Grinding Stone 25 = 755 (really 815: only 4 bars are listed at 50)
    ctx.eq((fnum(e.cost), bool(e.est)), (755.0, True), "9983 cost from Auctionator: an estimate")
    want = [int(x) for x in lua_list(P.CheckItems(P, 5))]
    ctx.check(2840 in want and 7955 in want and 2880 not in want, "check list: Copper Bar and the Claymore, not the vendor's Weak Flux: %s" % want)
    c.slash("/gr craft")
    ok, secs = start_scan(c, "craft")
    ctx.require(ok and not WC.Scanner.active, "the crafting check did not run")
    searched = set(c.ah_stats()["searchByItem"].keys())
    ctx.eq(searched, set(want), "items searched by the crafting check")
    e = P.CraftEntry(P, 9983)
    ctx.eq((fnum(e.cost), bool(e.est)), (815.0, False), "9983 cost after the check: exact (4 x 50 + 6 x 60 for the bars)")
    ctx.check(c.g("GetrichDB").scannedAt.craft, "the time of the check is kept")
    check_clean(ctx, c)
    # skill-up mode (the Tailoring character, skill 20): the route's materials (not the vendor's) and what its steps make
    c, ck = tailoring_setup(ctx, scan=False)
    WC = c.WC
    P = WC.Profit
    install_auctionator(c)
    for iid, rows in TAILOR_LISTINGS.items():
        c.set_listings(iid, rows)
    auctionator_scan_ah(c, fire=False)
    db = c.g("GetrichDB")
    db.craftMode, db.levelProf = "level", 197
    WC.Fire(WC, "SETTINGS_CHANGED", "craftMode")
    plan = WC.Leveling.Plan(WC.Leveling, ck, 197)
    mats = [int(m.itemID) for m in lua_list(plan.mats) if str(m.source) != "vendor"]
    outs = [int(x.itemID) for x in lua_list(plan.steps)]
    want = [int(x) for x in lua_list(P.CheckItems(P, 5))]
    ctx.check(len(mats) > 0 and len(outs) > 0 and set(want) == set(mats) | set(outs),
              "skill-up check list = the route's AH materials + products: %s vs %s + %s" % (want, mats, outs))
    c.open_ah()
    c.advance(1)
    c.slash("/gr craft")
    ok, secs = start_scan(c, "craft")
    ctx.require(ok and not WC.Scanner.active, "the skill-up check did not run")
    ctx.eq(set(c.ah_stats()["searchByItem"].keys()), set(want), "items searched by the skill-up check")
    check_clean(ctx, c, "skill-up")


@scenario("de_cold_cache", "2026.11.2: right after login (empty item cache, AH closed) the gear Auctionator saw is valued from the built-in item table; the check searches the enchanting materials")
def s_de_cold(ctx):
    c = ctx.client(cached=False, login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    for iid, rows in DE_PRICES.items():
        c.set_listings(iid, rows)
    c.set_listings(241089, [(200, 1)])        # Scarlet Dagger (a Forever item, ID >= 240000)
    c.set_listings(4800, [(565, 1)])          # Mighty Chain Pants
    auctionator_scan_ah(c, fire=False)        # Auctionator's database from an earlier session
    ctx.check(not c.eval("return C_Item.IsItemDataCachedByID(241089) or C_Item.IsItemDataCachedByID(4800)"), "(the two items are not in the client's cache)")
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    ah = {int(e.itemID): e for e in lst if e.source == "ah"}
    ctx.eq(sorted(ah), [4800, 241089], "gear for sale, known without loading an item")
    # Scarlet Dagger (weapon q2 ilvl 10, band 5-15): LME 1.2 x 300 + SD 0.3 x 40 = 372 x 0.95 = 353.4; bought for 200
    e = ah.get(241089)
    ctx.eq(e and (str(e.status), fnum(e.buy), round(fnum(e.value), 6), round(fnum(e.gain), 6), int(e.ilvl)), ("ok", 200.0, 353.4, 153.4, 10), "Scarlet Dagger from the table")
    # Mighty Chain Pants (armor q2 ilvl 23, band 21-25): 413.25; bought for 565 -> a loss
    e = ah.get(4800)
    ctx.eq(e and (str(e.status), fnum(e.buy), round(fnum(e.value), 6), round(fnum(e.gain), 6), int(e.ilvl)), ("ok", 565.0, 413.25, -151.75, 23), "Mighty Chain Pants from the table")
    ctx.eq(fnum(ah[4800].sell), 1221.0, "vendor price from the built-in table until the client has the item")
    # the tab, and its check: the enchanting materials are searched exactly, nothing else
    c.open_ah()
    c.advance(1)
    c.slash("/gr de")
    c.advance(2)
    ctx.check(any("Scarlet Dagger" in x for x in c.texts(clip=True)), "the Disenchant tab lists the Scarlet Dagger")
    ok, secs = start_scan(c, "de")
    ctx.require(ok and not WC.Scanner.active, "the disenchant check did not run")
    mats = {int(x) for x in lua_keys(WC.DE.mats)}
    ctx.eq(set(c.ah_stats()["searchByItem"].keys()), mats, "the check searches the enchanting materials")
    ctx.check(c.g("GetrichDB").scannedAt.de, "the time of the check is kept")
    check_clean(ctx, c)


@scenario("price_precedence", "2026.11.2: which price is used: a check newer than Auctionator's scan; an older check only while the scan shows the same cheapest price and the check is under a day old; else Auctionator's")
def s_precedence(ctx):
    c = ctx.client(login=False)
    install_auctionator(c)
    c.login()
    WC = c.WC
    c.open_ah()
    c.advance(2)
    auctionator_update(c, {2770: 50, 2771: 60, 2775: 70, 2776: 80, 2772: 90, 3858: 95}, background=500000)
    T = c.server_time()
    ctx.eq(ext_info(c)[0], True, "the scan was watched")
    hour, day = 3600, 86400
    c.eval("""local db, T = ...
      local function listed(min, t, rows) return { status = "listed", min = min, avail = 105, time = t, entries = rows } end
      db.results[2770] = listed(50, T - 3600, { { 50, 5 }, { 90, 100 } })          -- older, same cheapest price
      db.results[2771] = listed(55, T - 3600, { { 55, 5 }, { 90, 100 } })          -- older, another price
      db.results[2775] = listed(70, T - 2 * 86400, { { 70, 5 }, { 90, 100 } })     -- same price, but two days old
      db.results[2776] = listed(99, T + 60, { { 99, 5 }, { 120, 100 } })           -- newer than the scan
      db.results[3575] = { status = "none", avail = 0, time = T - 3600 }           -- nothing then, nothing in the scan
      db.results[2772] = { status = "none", avail = 0, time = T - 3600 }           -- nothing then, for sale in the scan
      db.results[3858] = { status = "timeout", avail = 0, time = T + 60 }          -- no answer""", c.g("GetrichDB"), T)
    WC.Fire(WC, "PRICES_UPDATED", "test")

    def cost(iid, qty=10):
        cst, status, info = multi(WC.CostForAny(WC, iid, qty), 3)
        return (fnum(cst), status, info and str(info.source))
    ctx.eq(cost(2770), (5 * 50 + 5 * 90, "ok", "search"), "older check, the scan shows the same cheapest price: the order book stands")
    ctx.eq(cost(2771), (600, "est", "auctionator"), "older check, the scan shows another price: Auctionator's price")
    ctx.eq(cost(2775), (700, "est", "auctionator"), "same cheapest price, but the check is two days old: Auctionator's price")
    ctx.eq(cost(2776), (5 * 99 + 5 * 120, "ok", "search"), "a check newer than the scan wins")
    ctx.eq(cost(3575), (None, "none", "search"), "nothing found then and not in the scan: not for sale")
    ctx.eq(cost(2772), (900, "est", "auctionator"), "nothing found then, but the newer scan saw it")
    ctx.eq(cost(3858), (950, "est", "auctionator"), "a search without an answer: Auctionator's price")
    ctx.eq(multi(WC.UnitPrice(WC, 2770), 3)[::2], (50, "search"), "UnitPrice source: search")
    ctx.eq(multi(WC.UnitPrice(WC, 2771), 3)[::2], (60, "auctionator"), "UnitPrice source: Auctionator")
    # without Auctionator's prices (it is switched off the next session) the checks are all there is
    c.eval("rawset(_G, 'Auctionator', nil)")
    ctx.eq(ext_state(c), (False, "noapi"), "Auctionator gone")
    ctx.eq(cost(2771), (5 * 55 + 5 * 90, "ok", "search"), "without Auctionator the last check is used")
    ctx.eq(cost(2772), (None, "none", "search"), "... also a 'not listed'")
    check_clean(ctx, c)


@scenario("upgrade_from_2026_11_1", "2026.11.2: saved data of 2026.11.1 (own scans, browse snapshot, scan switches): switches and snapshot go, checked prices and the watched Auctionator scan stay")
def s_upgrade_11_1(ctx):
    now = SERVER_TIME0
    ids = ", ".join(str(i) for i in AUC_BACKGROUND_CRATE)
    sv = ("""GetrichDB = { resultsFormat = 3, market = 'Classic Beta PvP 2|Horde', autoScan = true, useAuctionator = true, quickScan = true, quickTop = 5,
      results = { [2770] = { status = 'listed', entries = { { 40, 10 }, { 80, 100 } }, min = 40, avail = 110, time = %d } },
      scannedAt = { crates = %d, flips = %d },
      browse = { full = %d, gear = %d, items = { [2770] = { min = 40, qty = 110, t = %d } } },
      extScans = { ['Classic Beta PvP 2|Horde'] = { t = %d, ids = { %s } } } }""" % (now - 1800, now - 1800, now - 1800, now - 1800, now - 1800, now - 1800, now - 3600, ids))
    c = ctx.client(sv=sv, login=False)
    install_auctionator(c)
    auctionator_update(c, {2770: 40, 2771: 55}, background=500000, fire=False)
    c.login()
    WC = c.WC
    db = c.g("GetrichDB")
    ctx.eq((db.autoScan, db.useAuctionator, db.quickScan, db.browse), (None, None, None, None), "switches and browse snapshot of 2026.11.1 are dropped")
    ctx.eq(db.quickTop, 5, "quickTop kept")
    ctx.eq(ext_state(c), (True, None), "Auctionator's prices in use")
    ctx.eq(ext_info(c), (True, str(WC.L.EXT_AGO) % (str(WC.L.UI_AGE_MIN) % 60)), "the scan 2026.11.1 watched an hour ago is still dated")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 20), 3)
    ctx.eq((fnum(cost), status, info and str(info.source)), (10 * 40 + 10 * 80, "ok", "search"), "the last scan of 2026.11.1 (newer than Auctionator's) is used as a checked price")
    ctx.eq(multi(WC.CostForAny(WC, 2771, 20), 2), (1100, "est"), "an item it did not search: Auctionator's price")
    c.open_ah()
    c.advance(30)
    ctx.check(not WC.Scanner.active and c.ah_stats()["searches"] == 0 and c.ah_stats()["browses"] == 0, "no scan starts when the Auction House opens")
    for tab in TABS:
        c.slash("/gr " + tab)
        c.advance(0.3)
    text = c.logout_sv()
    for word in ("browse", "autoScan", "useAuctionator", "quickScan"):
        ctx.check(word not in text, "the saved data still contains '%s'" % word)
    check_clean(ctx, c)


# ===================================================================================================================
# runner
# ===================================================================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--locale", default="enUS", choices=["enUS", "zhCN", "zhTW"])
    ap.add_argument("-k", default=None, help="only scenarios whose name contains this")
    ap.add_argument("-v", action="store_true", help="verbose")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--addon", default=None, help="addon folder to test instead of Getrich/ (e.g. a mutated copy)")
    ap.add_argument("--uncached", action="store_true", help="start with an empty item cache (fresh login) in every scenario")
    args = ap.parse_args()
    global UNCACHED
    UNCACHED = args.uncached
    if args.addon:
        global ADDON_TOC
        ADDON_TOC = os.path.join(os.path.abspath(args.addon), "Getrich.toc")
    if args.list:
        for name, _, doc in SCENARIOS:
            print("%-26s %s" % (name, doc))
        return 0
    results = []
    t_all = time.time()
    for name, fn, doc in SCENARIOS:
        if args.k and args.k not in name:
            continue
        ctx = Ctx(name, args.locale, args.v)
        t0 = time.time()
        status, detail = "PASS", []
        try:
            fn(ctx)
            if ctx.failures:
                status, detail = "FAIL", ctx.failures
        except Fail as e:
            status, detail = "FAIL", ctx.failures + [str(e)]
        except Exception as e:  # noqa: BLE001
            tb = traceback.format_exc().strip().split("\n")
            status, detail = "ERROR", ctx.failures + ["%s: %s" % (type(e).__name__, e)] + ["    " + l for l in tb[-6:]]
        gaps = set()
        for c in ctx.clients:
            for g in c.gaps:
                gaps.add(g["name"])
        dt = time.time() - t0
        results.append((name, status))
        print("%-5s %-26s %5.1fs  %s" % (status, name, dt, doc))
        for d in detail[:25]:
            print("        - " + str(d))
        if len(detail) > 25:
            print("        ... %d more" % (len(detail) - 25))
        for n in ctx.notes:
            print("        note: " + n)
        if gaps and (args.v or status != "PASS"):
            print("        mock gaps (documented API the mock does not implement): " + ", ".join(sorted(gaps)))
    n_pass = sum(1 for _, s in results if s == "PASS")
    print("\n%d scenarios: %d PASS, %d FAIL, %d ERROR  (%.1fs, locale %s)" % (
        len(results), n_pass, sum(1 for _, s in results if s == "FAIL"), sum(1 for _, s in results if s == "ERROR"),
        time.time() - t_all, args.locale))
    return 0 if n_pass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
