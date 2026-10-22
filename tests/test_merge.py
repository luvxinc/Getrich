#!/usr/bin/env python3
"""Scenario tests for Waylaid Crate 2026.10.2 (merge of Getrich), run against tests/wowmock.py.

usage: python3 tests/test_merge.py [--locale enUS|zhCN|zhTW] [-k substring] [-v] [--list]
Each scenario starts a fresh mock client, prints PASS / FAIL / ERROR with the reason, and every scenario also fails on
Lua errors, strict-API violations (calls to APIs that do not exist on WoW Forever 1.60.1) and unexpected globals.
Expected numbers are computed by hand from tests/fixtures (the arithmetic is in the comments next to each check).
"""
import argparse, json, math, os, re, sys, time, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wowmock import WowClient, DEFAULT_CHAR, SECOND_CHAR, SERVER_TIME0, _strip  # noqa: E402

REAL_SV = os.path.join(HERE, "fixtures", "sv_waylaidcrate_130.lua")   # the user's real 1.3.0 SavedVariables
ADDON_TOC = os.environ.get("WC_ADDON_TOC", "WaylaidCrate/WaylaidCrate.toc")   # --addon DIR overrides (mutation tests)
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
    """Start a scan kind and run the clock until the scanner finished. Returns the seconds it took."""
    WC = c.WC
    t0 = c.now()
    ok = WC.Scanner.Start(WC.Scanner, kind)
    c.advance(timeout, until=lambda: not WC.Scanner.active)
    return ok, c.now() - t0


def visible_tab_texts(c):
    return c.texts(clip=True)


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
    """The 1.3.0 test session: crates scan on AH open, writs scan, writs scan with the filter off.
    Returns the evaluation dumps after each step."""
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(400, until=lambda: WC.Scanner.kind == "crates" and not WC.Scanner.active and c.now() > 1002)
    c.advance(1)
    out = {"after_crates": eval_dump(c)}
    WC.UI.SelectTab(WC.UI, "writs")
    start_scan(c, "writs", 900)
    out["after_writs"] = eval_dump(c)
    c.g("WaylaidCrateDB").hideNoWrit = False
    start_scan(c, "writs", 1500)
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
@scenario("load_all_locales", "all 22 files load in TOC order in enUS / zhCN / zhTW; every tab opens; zh strings in the right script")
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
        frame = c.g("WaylaidCrateFrame")
        ctx.require(frame is not None, "%s: no WaylaidCrateFrame after /wc" % loc)
        ctx.check(frame.IsVisible(frame), "%s: /wc did not show the window" % loc)
        if loc == "enUS":
            t = c.texts()
            ctx.check(any("2026.10.2" in x and "2026-10-22" in x for x in t),
                      "title should show 'v2026.10.2 · 2026-10-22' (TOC Version + X-Released); texts: %s" % t[:6])
        ctx.eq(frame.GetWidth(frame), 700, "%s: window width" % loc)
        ctx.eq(frame.GetHeight(frame), 700, "%s: window height" % loc)
        for tab in TABS:
            c.slash("/wc " + tab)
            ctx.eq(c.g("WaylaidCrateDB").tab, tab, "%s: /wc %s -> db.tab" % (loc, tab))
            ctx.check(frame.IsVisible(frame), "%s: window hidden after /wc %s" % (loc, tab))
            n = len(c.texts(clip=True))
            ctx.check(n >= 8, "%s: tab %s shows only %d texts" % (loc, tab, n))
        check_clean(ctx, c, loc)


# ------------------------------------------------------------------------------------------------------------------
@scenario("crates_writs_130", "1.3.0 crates/writs session: evaluations identical to v1.3.0 (eval_130.json) + 1.3.0 UI checks")
def s_130(ctx):
    c = ctx.client(locale="enUS")
    got = run_market_130(c, ctx)
    ref = json.load(open(os.path.join(FIX, "eval_130.json")))
    for step in ("after_crates", "after_writs", "after_writs_all"):
        for part in ("crates", "writs"):
            a, b = got[step][part], ref[step][part]
            ctx.eq(len(a), len(b), "%s %s count" % (step, part))
            for x, y in zip(a, b):
                if x != y:
                    diff = {k: (x.get(k), y.get(k)) for k in set(x) | set(y) if x.get(k) != y.get(k)}
                    ctx.failures.append("%s %s id %s differs from 1.3.0 (new, 1.3.0): %s" % (step, part, y.get("id"), diff))
                    break
    WC = c.WC
    # 1.3.0 checks (tests/mock_test.py): filters, rank order, bonuses
    db = c.g("WaylaidCrateDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat after scans")
    ctx.check(db.scannedAt.crates and db.scannedAt.writs, "scannedAt.crates / .writs set")
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
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, secs = start_scan(c, "history", 120)
    ctx.require(ok, "Scanner:Start('history') refused")
    st = c.ah_stats()
    calls = st["commodityInfoCalls"].get(2589, 0)
    searches = st["searchByItem"].get(2589, 1)
    ctx.check(calls <= 3 * searches + 2, "GetCommoditySearchResultInfo(2589) called %d times for 3 rows (%d searches) - loop over units?" % (calls, searches))
    ctx.check(st["itemInfoCalls"].get(1273, 0) <= 2 * st["searchByItem"].get(1273, 1) + 2, "GetItemSearchResultInfo(1273) called %d times for 2 rows" % st["itemInfoCalls"].get(1273, 0))
    res = c.g("WaylaidCrateDB").results
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
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    chat0 = len(c.chat)
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.require(ok, "Scanner:Start('crates') refused")
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
    ctx.check(not WC.Scanner.active, "crates scan still running after %d s of noise" % int(step * 0.3))
    ctx.check(len(c.chat) > chat0, "no chat line when the scan finished: %s" % c.chat[-3:])
    res = c.g("WaylaidCrateDB").results
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
    1273: [(1000, 1)],                             # Forest Chain (gear), sell 1656
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
    c.M.AH.browsePageSize = 4          # 12 browse rows -> 3 pages


def flip_dump(c):
    lst = lua_list(first(c.WC.Profit.Flips(c.WC.Profit)))
    return [(int(e.itemID), e.status, None if e.qty is None else int(e.qty), fnum(e.profit), fnum(e.cost), fnum(e.unit), fnum(e.perUnit)) for e in lst]


@scenario("flips_scan", "flips: browse 3 pages -> candidates -> targeted searches -> exact profit, 'gone' when the cheap listing vanished")
def s_flips(ctx):
    c = ctx.client()
    WC = c.WC
    flip_market(c)
    count_price_fires(c)
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    # run until the first targeted search went out, then the cheap Mageweave row is bought by someone
    c.advance(120, until=lambda: c.ah_stats()["searches"] >= 1 or not WC.Scanner.active)
    c.set_listings(4338, [(300, 50)])
    c.advance(300, until=lambda: not WC.Scanner.active)
    ctx.require(not WC.Scanner.active, "flips scan did not finish")
    st = c.ah_stats()
    ctx.eq(st["browses"], 1, "browse queries sent")
    db = c.g("WaylaidCrateDB")
    items = db.browse["items"]
    got = {int(k): (int(items[k].min), int(items[k].qty)) for k in lua_keys(items)}
    # browse rows = cheapest unit + total units per itemKey: Silk 100/215, Mageweave 200/53, Linen 12/101 ...
    exp = {iid: (min(u for u, q in rows), sum(q for u, q in rows)) for iid, rows in FLIP_LISTINGS.items()}
    ctx.eq(got, exp, "db.browse.items after 3 pages (min, qty)")
    ctx.eq(int(items[1273].ilvl or 0), 25, "browse ilvl for gear (Forest Chain itemKey.itemLevel)")
    ctx.check(db.browse.full, "db.browse.full timestamp not set")
    # candidates: (sell - min) x min(qty, 20):
    #   Silk (150-100) x 20 = 1000; Mageweave (250-200) x 20 = 1000 (tie -> lower itemID first); Forest Chain 656 x 1 = 656;
    #   Linen (13-12) x 20 = 20; Medium Leather (50-49) x 2 = 2; Wool 40 >= 33 and the crate (sell 0) are not candidates
    cand = [int(x) for x in lua_list(WC.Profit.FlipCandidates(WC.Profit, 80))]
    ctx.eq(cand, [4306, 4338, 1273, 2589, 2319], "FlipCandidates(80)")
    searched = set(st["searchByItem"].keys())
    ctx.eq(searched, {4306, 4338, 1273, 2589, 2319}, "items searched in phase 2")
    # Flips (order book after the browse):
    #   Forest Chain: 1 x (1656-1000) = 656, cost 1000
    #   Silk: 5 x (150-100) + 10 x (150-140) = 250 + 100 = 350, qty 15, cost 5x100 + 10x140 = 1900
    #   Medium Leather: 2 x (50-49) = 2, cost 98;  Linen: 1 x (13-12) = 1, cost 12 (the 13c row is not below 13)
    #   Mageweave: searched after the browse, nothing below 250 any more -> "gone", last
    exp = [(1273, "ok", 1, 656.0, 1000.0, 1000.0, 656.0),
           (4306, "ok", 15, 350.0, 1900.0, 100.0, 50.0),
           (2319, "ok", 2, 2.0, 98.0, 49.0, 1.0),
           (2589, "ok", 1, 1.0, 12.0, 12.0, 1.0)]
    got = flip_dump(c)
    ctx.eq(got[:4], exp, "Profit:Flips() ok entries")
    ctx.check(len(got) == 5 and got[4][0] == 4338 and got[4][1] == "gone" and got[4][3] in (0, 0.0, None),
              "Mageweave should be the last entry with status 'gone': %s" % got[4:])
    # CostForAny: search newer than browse -> order book; browse only -> min x qty "est"
    cost, status, info = multi(WC.CostForAny(WC, 4306, 10), 3)
    ctx.eq((cost, status, info and info.source), (1200, "ok", "search"), "CostForAny(Silk, 10) = 5x100 + 5x140")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 5), 3)
    ctx.eq((cost, status, info and info.source), (150, "est", "browse"), "CostForAny(Copper Ore, 5) from the browse = 5 x 30")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 25), 3)
    ctx.eq(status, "short", "CostForAny(Copper Ore, 25): browse says only 20 listed")
    up = multi(WC.UnitPrice(WC, 2770), 3)
    ctx.eq((up[0], up[2]), (30, "browse"), "UnitPrice(Copper Ore) from the browse")
    # history from the browse: relevant items only (Copper Ore is a crate material, Forest Chain is not relevant)
    H = c.server_time() // 3600
    hist = c.g("WaylaidCrateDB").history
    rec = hist[2770] and hist[2770].h[H]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (30, 20), "browse wrote history for relevant Copper Ore")
    ctx.eq(hist[1273], None, "no history for Forest Chain (not relevant)")
    # PRICES_UPDATED at most ~4 per second
    times = sorted(float(x) for x in lua_list(c.M.priceFires)) if id(c) in PRICE_FIRES else []
    worst = max([sum(1 for u in times if t0 <= u < t0 + 1.0) for t0 in times] or [0])
    ctx.check(worst <= 5, "PRICES_UPDATED fired %d times within one second (spec: <= ~4/s)" % worst)
    # tab
    c.slash("/wc flips")
    t = c.texts(clip=True)
    ctx.check(any("Forest Chain" in x for x in t), "flips tab does not list Forest Chain: %s" % t[:30])
    tip = "\n".join(c.hover_text("Silk Cloth"))
    for need in (ctx.money(100), ctx.money(150), "15", ctx.money(1900), ctx.money(350)):
        ctx.check(need in tip, "Silk Cloth flip tooltip lacks %r:\n%s" % (need, tip))
    ctx.check(any(ctx.money(656) in x for x in t), "flips tab does not show the 656c profit (%s)" % ctx.money(656))
    ctx.check(any(ctx.money(350) in x for x in t), "flips tab does not show Silk's 350c profit (%s)" % ctx.money(350))
    check_clean(ctx, c)


@scenario("flips_fresh_login", "flips on a fresh login (nothing in the item cache): candidates still found once item data arrives")
def s_flips_fresh(ctx):
    # Real client: C_Item.GetItemInfo (sell price) is nil for items not seen this session until requested + loaded.
    # After a full browse most rows are such items; the search phase must not silently skip them.
    c = ctx.client(cached=False)
    WC = c.WC
    flip_market(c)
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    c.advance(300, until=lambda: not WC.Scanner.active)
    searched = set(c.ah_stats()["searchByItem"].keys())
    ctx.eq(searched, {4306, 4338, 1273, 2589, 2319},
           "items searched in phase 2 with a cold item cache (candidates whose sell price was still loading were skipped?)")
    got = {e[0]: e[1] for e in flip_dump(c)}
    ctx.eq(got.get(1273), "ok", "Forest Chain flip status after the scan (cold item cache)")
    check_clean(ctx, c)


def foreign_market(c, n=40):
    """n plain items (quality 1, sell 100+i) listed at 50 + (i*7) % 300 x 3; browse pages of 5 rows."""
    c.clear_listings()
    for i in range(n):
        iid = 800000 + i
        c.add_item(iid, "Market Item %d" % i, quality=1, ilvl=10, classID=7, sell=100 + i, cached=True)
        c.set_listings(iid, [(50 + (i * 7) % 300, 3)])
    c.M.AH.browsePageSize = 5


@scenario("browse_foreign_list", "review: a Favorites list (SearchForFavorites / a whole new BROWSE_RESULTS_UPDATED) during our full browse never wipes the snapshot")
def s_browse_foreign(ctx):
    for how in ("favorites", "raw_updated"):
        c = ctx.client()
        WC = c.WC
        foreign_market(c)
        c.g("WaylaidCrateDB").autoScan = False
        c.open_ah()
        c.advance(1)
        ok, _ = start_scan(c, "flips")
        ctx.require(ok and not WC.Scanner.active, "%s: first flips scan did not run" % how)
        db = c.g("WaylaidCrateDB")
        ctx.eq(len(lua_keys(db.browse["items"])), 40, "%s: snapshot after a complete full browse" % how)
        stamp = db.browse.full
        ctx.check(stamp is not None, "%s: db.browse.full not stamped after a complete browse" % how)
        c.advance(5)
        ok = WC.Scanner.Start(WC.Scanner, "flips")
        ctx.require(ok, "%s: second flips scan refused" % how)
        # 8 pages of 5: wait until our 3rd page is in and the next page request is in flight
        c.advance(120, until=lambda: WC.Scanner.browse is not None and WC.Scanner.browse.pages >= 3 and WC.Scanner.browse.state == "sent")
        ctx.require(WC.Scanner.browse is not None and WC.Scanner.browse.pages >= 3, "%s: browse did not reach page 3" % how)
        if how == "favorites":
            c.ah_blizzard_favorites([800001, 800002])          # Blizzard's Favorites button (hooked call)
        else:
            # the same list change arriving without our hook seeing the call (Blizzard_AuctionHouseFrame.lua:760-772)
            c.eval("""local AH = __WOWMOCK.AH
              AH.browse = { results = {
                { itemKey = { itemID = 800001, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, totalQuantity = 3, minPrice = 57, containsOwnerItem = false },
                { itemKey = { itemID = 800002, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, totalQuantity = 3, minPrice = 64, containsOwnerItem = false } },
                full = true, pages = {}, delivered = 0, query = {} }
              __WOWMOCK.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")""")
        c.advance(400, until=lambda: not WC.Scanner.active)
        ctx.require(not WC.Scanner.active, "%s: scan did not finish after the foreign list" % how)
        ctx.eq(len(lua_keys(db.browse["items"])), 40, "%s: snapshot kept (an interrupted browse deletes nothing)" % how)
        ctx.eq(db.browse.full, stamp, "%s: db.browse.full not re-stamped by an interrupted browse" % how)
        check_clean(ctx, c, how)


@scenario("gear_random_suffix", "review: random-suffix gear is searched with the browse row's exact itemKey (level + suffix); 'gone' only from that key")
def s_gear_suffix(ctx):
    c = ctx.client()
    WC = c.WC
    c.clear_listings()
    # a green sword with two random suffixes ("of the Monkey" 1201 cheap, "of the Bear" 1202 dear); vendor pays 1000c
    c.add_item(900001, "Mock Sword", quality=2, ilvl=20, classID=2, equipLoc="INVTYPE_WEAPON", sell=1000, stack=1, cached=True)
    c.set_listings(900001, [{"unit": 400, "qty": 1, "sfx": 1201}, {"unit": 1500, "qty": 1, "sfx": 1202}], commodity=False)
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, _ = start_scan(c, "flips")
    ctx.require(ok and not WC.Scanner.active, "flips scan did not run")
    db = c.g("WaylaidCrateDB")
    b = db.browse["items"][900001]
    ctx.require(b is not None, "sword not in the browse snapshot")
    # cheapest variant: 400c, suffix 1201, item level 20; units of both variants: 2
    ctx.eq((int(b.min), int(b.qty), int(b.ilvl or 0), int(b.sfx or 0)), (400, 2, 20, 1201), "browse entry (min, qty, ilvl, sfx)")
    r = WC.Scanner.results[900001]
    ctx.require(r is not None, "sword was not searched")
    # searched with (900001, 20, 1201): the 400c row; without the suffix the AH answers nothing and the flip shows 'gone'
    ctx.eq((r.status, int(r.min or 0), int(r.sfx or 0)), ("listed", 400, 1201), "search result (status, min, searched suffix)")
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(900001) and got[900001][1:4], ("ok", 1, 600.0), "sword flip (status, qty, profit = 1000 - 400)")
    # a later 'nothing listed' answer for another key (e.g. a level-0 search) must not turn the flip into 'gone'
    c.eval("local WC = ...; WC.Scanner.results[900001] = { status = 'none', avail = 0, time = time() + 5 }; WC:Fire('PRICES_UPDATED', 'test')", WC)
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(900001) and got[900001][1], "est", "flip status after a 'none' answer for a different key")
    check_clean(ctx, c)


@scenario("flips_estimate", "flips: only browse data (search phase stopped) -> status 'est', profit = sell - min for one unit")
def s_flips_est(ctx):
    c = ctx.client()
    WC = c.WC
    flip_market(c)
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    WC.Scanner.Start(WC.Scanner, "flips")
    c.advance(120, until=lambda: c.ah_stats()["searches"] >= 1 or not WC.Scanner.active)
    WC.Scanner.Stop(WC.Scanner, "test")
    c.advance(2)
    # est profits = sell - min: Forest Chain 656, Silk 50, Mageweave 50 (tie -> itemID), Medium Leather 1, Linen 1
    got = [(i, s, q, p) for (i, s, q, p, _, _, _) in flip_dump(c)]
    ctx.eq(got, [(1273, "est", None, 656.0), (4306, "est", None, 50.0), (4338, "est", None, 50.0),
                 (2319, "est", None, 1.0), (2589, "est", None, 1.0)], "Profit:Flips() with browse data only")
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
    recs = c.g("WaylaidCrateDB").recipes[ck]
    ctx.require(recs is not None and recs[9983] is not None, "Blacksmithing recipes were not captured (db.recipes[%s][9983])" % ck)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    c.set_bags({(0, 1): (2840, 3)})   # 3 Copper Bars already owned
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, secs = start_scan(c, "craft", 900)
    ctx.require(ok, "Scanner:Start('craft') refused")
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
        c.g("WaylaidCrateDB").autoScan = False
        c.open_ah()
        c.advance(1)
        start_scan(c, "de", 600)
        c.advance(1)


def band_tuple(b):
    return None if b is None else (int(b.q), int(b["class"]), int(b.lo), int(b.hi))


@scenario("de_value", "disenchant bands + value (estimate) for uncommon/rare gear incl. new Forever IDs >= 240000; reasons; partial prices")
def s_de_value(ctx):
    c = ctx.client()
    WC = c.WC
    c.set_listings(241089, [(200, 1)])      # Scarlet Dagger on the AH (gear browse of the de scan)
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
    # AH gear from the de scan's browse: Scarlet Dagger for 200 -> gain 353.4 - 200 = 153.4
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    ah = [e for e in lst if e.source == "ah" and int(e.itemID) == 241089]
    ctx.check(ah, "Profit:Disenchant() has no AH entry for Scarlet Dagger 241089 (new Forever ID refused?)")
    if ah:
        ctx.eq(fnum(ah[0].buy), 200.0, "DE AH entry buy")
        ctx.eq(fnum(ah[0].gain), 153.4, "DE AH entry gain = 353.4 - 200")
    # partial: Lesser Astral Essence price unknown -> value from the priced outputs only: (150 + 60) x 0.95 = 199.5
    db = c.g("WaylaidCrateDB")
    db.results[10998] = None
    db.browse["items"][10998] = None
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
    rec = c.g("WaylaidCrateDB").deSamples["2:4:21-25"]
    ctx.require(rec is not None, "db.deSamples['2:4:21-25'] missing; keys: %s" % lua_keys(c.g("WaylaidCrateDB").deSamples))
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
    rec = c.g("WaylaidCrateDB").deSamples["2:4:21-25"]
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
    h = c.g("WaylaidCrateDB").history[2589].h
    ctx.eq({int(k): (int(h[k].min), int(h[k].qty)) for k in lua_keys(h)}, {H: (90, 7), H + 1: (95, 6)}, "hourly records")
    c.add_item(999002, "Irrelevant Trinket", classID=15, stack=1)
    ctx.check(not S.RecordHistory(S, 999002, 50, 1, t0), "history recorded for an item that is not relevant")
    ctx.eq(c.g("WaylaidCrateDB").history[999002], None, "no history for an irrelevant item")
    hist = lua_list(S.History(S, 2589))
    ctx.eq([(int(x.t), int(x.min)) for x in hist], [(H * 3600, 90), ((H + 1) * 3600, 95)], "Store:History(2589)")
    # a watched-items scan records the hour's cheapest price; a second scan in the same hour overwrites it
    c.set_listings(2589, [(12, 100)])
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah(); c.advance(1)
    start_scan(c, "history", 60)
    H2 = c.server_time() // 3600
    rec = c.g("WaylaidCrateDB").history[2589].h[H2]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (12, 100), "history written by the scan")
    c.set_listings(2589, [(11, 50)])
    start_scan(c, "history", 60)
    rec = c.g("WaylaidCrateDB").history[2589].h[c.server_time() // 3600]
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
    sv = """WaylaidCrateDB = { resultsFormat = 3, watch = { [2589] = true }, history = { [2589] = {
      h = { [%d] = { min = 100, qty = 1 }, [%d] = { min = 80, qty = 2 }, [%d] = { min = 120, qty = 3 },
            [%d] = { min = 90, qty = 4 }, [%d] = { min = 77, qty = 5 } },
      d = { [%d] = { lo = 50, avg = 60, hi = 70, n = 2 } } } } }""" % (D * 24 + 1, D * 24 + 5, D * 24 + 9, D2 * 24 + 3, H0 - 10, D2)
    c = ctx.client(sv=sv)
    rec = c.g("WaylaidCrateDB").history[2589]
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
    obs = c.g("WaylaidCrateDB").vendorObs
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
    db = c.g("WaylaidCrateDB")
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
    c.g("WaylaidCrateDB").autoScan = False
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
@scenario("idle_progress_sound", "progress bar shows phase + elapsed time, completion chat + sound; nothing runs when idle")
def s_idle(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(1.5)
    ctx.check(WC.Scanner.active, "auto-scan did not start 1 s after the AH opened")
    c.advance(10)
    t = c.texts()
    ctx.check(any(re.search(r"\b1[01]s\b", x) or re.search(r"\b0:1[01]\b", x) or re.search(r"1[01] ?秒", x) for x in t),
              "elapsed time (~11s) not visible while scanning: %s" % [x for x in t if re.search(r"\d", x)][:8])
    chat0 = len(c.chat)
    c.advance(400, until=lambda: not WC.Scanner.active)
    ctx.check(len(c.chat) > chat0, "no chat line when the scan finished")
    snd = c.sounds
    ctx.check(len(snd) >= 1, "no sound when the scan finished (db.soundOnDone)")
    c.advance(2)
    idle = c.idle_report()
    ctx.check(not idle["timers"], "timers still pending after the scan: %s" % idle["timers"])
    ctx.check(not idle["onupdate"], "OnUpdate scripts running while idle (window open): %s" % idle["onupdate"])
    ctx.check(not idle["animations"], "animations playing while idle: %s" % idle["animations"])
    # writs: two phases visible in the bar
    c.slash("/wc writs")
    WC.Scanner.Start(WC.Scanner, "writs")
    c.advance(5)
    t = " ".join(c.texts())
    ctx.check(re.search(r"1\s*/\s*2", t), "phase '1/2' not shown during the writs scan")
    c.advance(900, until=lambda: not WC.Scanner.active)
    c.g("WaylaidCrateDB").soundOnDone = False
    n = len(c.sounds)
    start_scan(c, "crates", 400)
    ctx.eq(len(c.sounds), n, "sound played although soundOnDone = false")
    c.close_ah()
    c.advance(3)
    frame = c.g("WaylaidCrateFrame")
    ctx.check(not frame.IsVisible(frame), "window still shown after the AH closed (1.3.0 behaviour: hide with the AH)")
    idle = c.idle_report()
    ctx.check(not idle["timers"] and not idle["onupdate"] and not idle["animations"], "work while idle after AH close: %s" % idle)
    c.slash("/wc")
    c.advance(5)
    idle = c.idle_report()
    ctx.check(not idle["onupdate"] and not idle["timers"], "window opened with /wc runs work while idle: %s" % idle)
    check_clean(ctx, c)


@scenario("ah_closed_mid_scan", "closing the AH stops the scan, keeps what was scanned, hides the window, leaves no timers")
def s_close(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(12)
    ctx.check(WC.Scanner.active, "scan not running 12 s after AH open")
    c.close_ah()
    c.advance(5)
    ctx.check(not WC.Scanner.active, "scanner still active after AH close")
    frame = c.g("WaylaidCrateFrame")
    ctx.check(not frame.IsVisible(frame), "window still visible after AH close")
    n = sum(1 for k in lua_keys(c.g("WaylaidCrateDB").results))
    ctx.check(n >= 5, "results from before the close were dropped (%d left)" % n)
    ctx.check(not c.running_timers(), "timers left after AH close: %s" % c.running_timers())
    check_clean(ctx, c)


@scenario("memory_and_widgets", "memory sanity after scans and repeated refreshes; refreshing tabs creates no new widgets")
def s_mem(ctx):
    c = ctx.client()
    WC = c.WC
    # a big auction house: 1500 extra items for the full browse
    for i in range(1500):
        iid = 900000 + i
        c.add_item(iid, "Bulk Item %d" % i, quality=1 + (i % 3), ilvl=5 + i % 40, classID=(7 if i % 4 else 4), equipLoc=("" if i % 4 else "INVTYPE_CHEST"),
                   sell=10 + i % 300, stack=(20 if i % 4 else 1))
        c.set_listings(iid, [(50 + (i * 37) % 900, 1 + i % 30)])
    c.M.AH.browsePageSize = 500
    m0 = c.memory_kb()
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah(); c.advance(1)
    ok, secs = start_scan(c, "flips", 900)
    ctx.require(ok and not WC.Scanner.active, "flips scan did not finish")
    m1 = c.memory_kb()
    for tab in TABS:
        c.slash("/wc " + tab)
    w1 = c.addon_widget_count()
    m2 = c.memory_kb()
    for _ in range(5):
        for tab in TABS:
            c.slash("/wc " + tab)
            WC.Fire(WC, "PRICES_UPDATED", "test")
            c.advance(0.3)
    w2 = c.addon_widget_count()
    m3 = c.memory_kb()
    ctx.log("memory KB: start %.0f, after browse+search %.0f, tabs %.0f, 5 refresh rounds %.0f; widgets %d -> %d" % (m0, m1, m2, m3, w1, w2))
    ctx.note("Lua heap: %.0f KB after a 1500-item browse + flip searches (+%.0f KB), +%.0f KB after 5 refresh rounds; %d addon widgets"
             % (m1, m1 - m0, m3 - m2, w2))
    ctx.check(m1 - m0 < 4000, "1500-item browse grew the Lua heap by %.0f KB (> 4 MB)" % (m1 - m0))
    ctx.check(m3 - m2 < 300, "5 refresh rounds grew the Lua heap by %.0f KB (leak?)" % (m3 - m2))
    ctx.check(w2 - w1 <= 10, "refreshing tabs created %d new widgets" % (w2 - w1))
    check_clean(ctx, c)


@scenario("slash_commands", "/wc, /wc <tab>, /wc scan [tab], /wc stop")
def s_slash(ctx):
    c = ctx.client()
    WC = c.WC
    frame_shown = lambda: (c.g("WaylaidCrateFrame") is not None and c.g("WaylaidCrateFrame").IsVisible(c.g("WaylaidCrateFrame")))
    c.slash("/wc")
    ctx.check(frame_shown(), "/wc did not open the window")
    c.slash("/wc")
    ctx.check(not frame_shown(), "/wc did not toggle the window closed")
    n = len(c.chat)
    c.slash("/wc scan")
    ctx.check(not WC.Scanner.active and len(c.chat) > n, "/wc scan with the AH closed should print a hint")
    c.g("WaylaidCrateDB").autoScan = False
    setup_market_130(c)
    c.open_ah(); c.advance(1)
    c.slash("/wc scan writs")
    ctx.check(WC.Scanner.active and WC.Scanner.kind == "writs", "/wc scan writs did not start a writs scan")
    ctx.eq(c.g("WaylaidCrateDB").tab, "writs", "/wc scan writs selects the writs tab")
    c.advance(5)
    c.slash("/wc stop")
    ctx.check(not WC.Scanner.active, "/wc stop did not stop the scan")
    c.slash("/waylaid crates")
    ctx.eq(c.g("WaylaidCrateDB").tab, "crates", "/waylaid crates")
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
            b.Click(b, "RightButton") if c.g("WaylaidCrateFrame").IsVisible(c.g("WaylaidCrateFrame")) else None
            clicked += 1
            if not c.g("WaylaidCrateFrame").IsVisible(c.g("WaylaidCrateFrame")):
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
    db = c.g("WaylaidCrateDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat upgraded 2 -> 3")
    r = db.results[2319]
    ctx.eq(r and (r.status, int(r.min), int(r.avail)), ("listed", 194, 8883), "results[2319] kept from the 1.3.0 SV")
    ctx.eq((db.autoScan, db.onlyMine, db.tab), (False, True, "crates"), "1.3.0 settings kept")
    ctx.eq(db.soundOnDone, True, "new default soundOnDone added")
    cost = c.WC.CostFor(c.WC, 2319, 20)
    ctx.eq(cost[0], 194 * 20, "CostFor(2319, 20) from saved results (80 listed at 194c)")
    c.open_ah()
    c.advance(5)
    ctx.check(not c.WC.Scanner.active, "autoScan = false in the SV, but a scan started")
    # round trip
    setup_market_130(c)
    start_scan(c, "crates", 400)
    c.WC.Store.SetWatch(c.WC.Store, 2589, True)
    text = c.logout_sv()
    ctx.check("WaylaidCrateDB" in text, "logout produced no SavedVariables")
    c2 = ctx.client(sv=text)
    db2 = c2.g("WaylaidCrateDB")
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
    recs = c.g("WaylaidCrateDB").recipes[SECOND_CHAR]
    fx = json.load(open(os.path.join(FIX, "recipes.json")))["chars"][SECOND_CHAR]["recipes"]
    exp = {int(k) for k, r in fx.items() if r["learned"] and r["skillLine"] in (197, 333, 185, 129)}
    ctx.eq({int(k) for k in lua_keys(recs)} if recs else set(), exp, "captured recipes of the second character")
    c.g("WaylaidCrateDB").autoScan = False
    c.open_ah(); c.advance(1)
    ok, secs = start_scan(c, "craft", 900)
    ctx.check(ok and not WC.Scanner.active, "craft scan did not finish")
    lst, counts = WC.Profit.Craft(WC.Profit)
    ctx.check(len(lua_list(lst)) > 20, "Profit:Craft() returned only %d entries" % len(lua_list(lst)))
    c.slash("/wc craft")
    c.slash("/wc de")
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
    ap.add_argument("--addon", default=None, help="addon folder to test instead of WaylaidCrate/ (e.g. a mutated copy)")
    ap.add_argument("--uncached", action="store_true", help="start with an empty item cache (fresh login) in every scenario")
    args = ap.parse_args()
    global UNCACHED
    UNCACHED = args.uncached
    if args.addon:
        global ADDON_TOC
        ADDON_TOC = os.path.join(os.path.abspath(args.addon), "WaylaidCrate.toc")
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
