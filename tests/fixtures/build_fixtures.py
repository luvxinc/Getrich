#!/usr/bin/env python3
"""Regenerate the JSON fixtures used by tests/wowmock.py and tests/test_merge.py.

Sources (not part of the repo; only needed to regenerate):
  * Blizzard UI source mirror, branch "forever", build 1.60.1.70450 (commit 172a387):
      --mirror  /tmp/claude-0/api-agent/wow-ui-source
  * Forever client tables exported from wago.tools, build 1.60.1.70450 (ItemSparse.csv, Item.csv):
      --db2     <scratchpad>/wago/db70450
  * The user's real SavedVariables (WoW Forever beta, Oct 2026):
      --sv      /home/claude/brief/sv   (WaylaidCrate.lua = AH order books, Getrich.lua = recipes + merchant scans)
  * The addon's own Data.lua / Writs.lua (crate + writ item IDs).

Outputs (tests/fixtures/):
  forever_api.json   API surface: C_* namespaces, documented globals, events, enums, widget method sets, XML templates,
                     font objects, and names of globals defined by Blizzard's Lua UI code (for strict-mode messages)
  items.json         itemID -> {name, quality, ilvl, req, classID, subclassID, equipLoc, sell, buy, vstack, stack, flags}
  recipes.json       the two characters' captured recipes (Getrich SV) in a neutral shape the mock serves through
                     C_TradeSkillUI, plus profession lists
  orderbooks.json    itemID -> [[unitPrice, quantity], ...] (cheapest first) from the WaylaidCrate SV "results"
  merchants.json     real merchant windows seen by the user (npc, zone, offers) from the Getrich SV

Run:  python3 tests/fixtures/build_fixtures.py [--mirror DIR] [--db2 DIR] [--sv DIR]
"""
import argparse, csv, glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--mirror", default="/tmp/claude-0/api-agent/wow-ui-source")
ap.add_argument("--db2", default="/tmp/claude-0/-home-claude/55dced39-fef5-5660-8cd3-4ed424fad23e/scratchpad/wago/db70450")
ap.add_argument("--sv", default="/home/claude/brief/sv")
args = ap.parse_args()

from lupa import lua51

ADDONS = os.path.join(args.mirror, "Interface", "AddOns")
OTHER_FLAVORS = re.compile(r"/(Vanilla|Classic|TBC|Wrath|Cata|Mists|Mainline_?Classic)/")


# the public repo must not carry the player's real character GUIDs: each distinct GUID becomes
# Player-0000-0000000A, ...B, ... in sorted order (the user's Blacksmithing character sorts first -> ...A)
GUID_RE = re.compile(r"Player-\d+-[0-9A-F]{8}")


def anonymize(text):
    real = sorted(set(GUID_RE.findall(text)))
    fake = {g: "Player-0000-0000000" + "ABCDEFGHIJKLMNOP"[i] for i, g in enumerate(real) if i < 16}
    return GUID_RE.sub(lambda m: fake.get(m.group(0), "Player-0000-00000000"), text)


def dump(name, obj):
    path = os.path.join(HERE, name)
    text = json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    with open(path, "w", encoding="utf-8") as f:
        f.write(anonymize(text))
        f.write("\n")
    print("wrote", path, os.path.getsize(path), "bytes")


# ----------------------------------------------------------------------------------------------- API surface
def build_api():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
      Enum = setmetatable({}, {__index=function(t,k) local v=setmetatable({}, {__index=function() return 0 end}); rawset(t,k,v); return v end})
      Constants = setmetatable({}, getmetatable(Enum)); DOCS = {}
      APIDocumentation = { AddDocumentationTable = function(self, t) DOCS[#DOCS + 1] = t end }""")
    load = lua.eval("function(s, n) local f, e = loadstring(s, n); if not f then return e end; local ok, e2 = pcall(f); if not ok then return e2 end end")
    for path in sorted(glob.glob(os.path.join(ADDONS, "Blizzard_APIDocumentationGenerated", "*.lua"))):
        err = load(open(path, encoding="utf-8").read(), os.path.basename(path))
        if err:
            print("WARN", path, err)
    docs = lua.eval("DOCS")
    lst = lambda t: [t[i] for i in range(1, len(t) + 1)] if t is not None else []
    api = {"namespaces": {}, "globals": [], "events": [], "enums": {}, "widget": {}}
    widget_docs = {}
    for i in range(1, len(docs) + 1):
        d = docs[i]
        ns = d.Namespace
        for fn in lst(d.Functions):
            if ns:
                api["namespaces"].setdefault(ns, [])
                if fn.Name not in api["namespaces"][ns]:
                    api["namespaces"][ns].append(fn.Name)
            elif d.Type == "ScriptObject":
                widget_docs.setdefault(d.Name, []).append(fn.Name)
            else:
                api["globals"].append(fn.Name)
        for ev in lst(d.Events):
            api["events"].append(ev.LiteralName)
        for t in lst(d.Tables):
            if t.Type == "Enumeration":
                api["enums"][t.Name] = {f.Name: f.EnumValue for f in lst(t.Fields)}
    W = {k: set(v) for k, v in widget_docs.items()}
    anim = W.get("SimpleAnimatableObjectAPI", set())
    obj = W["SimpleObjectAPI"] | W["SimpleFrameScriptObjectAPI"]
    sr = obj | W["SimpleScriptRegionAPI"] | W["SimpleScriptRegionResizingAPI"] | anim
    region = sr | W["SimpleRegionAPI"]
    frame = sr | W["SimpleFrameAPI"]
    tex = region | W["SimpleTextureBaseAPI"]
    kinds = {
        "Frame": frame,
        "Button": frame | W["SimpleButtonAPI"],
        "CheckButton": frame | W["SimpleButtonAPI"] | W["SimpleCheckboxAPI"],
        "EditBox": frame | W["SimpleEditBoxAPI"] | W["SimpleFontAPI"],
        "ScrollFrame": frame | W["SimpleScrollFrameAPI"],
        "Slider": frame | W["SimpleSliderAPI"],
        "StatusBar": frame | W["SimpleStatusBarAPI"],
        "GameTooltip": frame | W["FrameAPITooltip"],
        "Cooldown": frame | W.get("FrameAPICooldown", set()),
        "FontString": region | W["SimpleFontStringAPI"] | W["SimpleFontAPI"],
        "Texture": tex | W["SimpleTextureAPI"],
        "MaskTexture": tex,
        "Line": tex | W["SimpleLineAPI"],
        "AnimationGroup": obj | W["SimpleAnimGroupAPI"],
        "Animation": obj | W["SimpleAnimAPI"] | W.get("SimpleAnimAlphaAPI", set()) | W.get("SimpleAnimTranslationAPI", set())
                     | W.get("SimpleAnimScaleAPI", set()) | W.get("SimpleAnimRotationAPI", set()),
        "Font": obj | W["SimpleFontAPI"],
    }
    api["widget"] = {k: sorted(v) for k, v in kinds.items()}
    api["events"] = sorted(set(api["events"]))
    api["globals"] = sorted(set(api["globals"]))

    # XML templates that load for the camelot (Forever) flavor: every virtual element not only defined in another
    # flavor's folder. value = [element type, inherits]
    tmpl = {}
    for p in glob.glob(os.path.join(ADDONS, "**", "*.xml"), recursive=True):
        rel = p[len(ADDONS):].replace(os.sep, "/")
        s = open(p, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"<(\w+)\s+([^>]*?)virtual=\"true\"([^>]*)>", s):
            attrs = m.group(2) + m.group(3)
            n = re.search(r'name="([^"]+)"', attrs)
            if not n:
                continue
            inh = re.search(r'inherits="([^"]+)"', attrs)
            entry = [m.group(1), inh.group(1) if inh else None]
            other = bool(OTHER_FLAVORS.search(rel))
            prev = tmpl.get(n.group(1))
            if prev is None or (prev[2] and not other):
                tmpl[n.group(1)] = entry + [other]
    api["templates"] = {k: v[:2] for k, v in tmpl.items() if not v[2]}
    api["templates_other_flavors"] = sorted(k for k, v in tmpl.items() if v[2])

    fonts = set()
    for p in glob.glob(os.path.join(ADDONS, "Blizzard_Fonts_Shared", "**", "*.xml"), recursive=True):
        s = open(p, encoding="utf-8", errors="replace").read()
        fonts |= set(re.findall(r'<(?:Font|FontFamily)\s+name="([A-Za-z0-9_]+)"', s))
    api["fonts"] = sorted(fonts)

    # globals defined by Blizzard Lua code (function Foo( / Foo = at column 0) - used only for clearer strict messages
    ui = set()
    for p in glob.glob(os.path.join(ADDONS, "**", "*.lua"), recursive=True):
        rel = p[len(ADDONS):].replace(os.sep, "/")
        if "APIDocumentation" in rel or OTHER_FLAVORS.search(rel):
            continue
        for line in open(p, encoding="utf-8", errors="replace"):
            m = re.match(r"function ([A-Za-z_][A-Za-z0-9_]*)\s*\(", line) or re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]", line)
            if m and m.group(1) not in ("local", "end", "return"):
                ui.add(m.group(1))
    api["ui_globals"] = sorted(ui)
    sk = {}
    src = open(os.path.join(ADDONS, "Blizzard_SharedXML", "Mainline", "SoundKitConstants.lua"), encoding="utf-8").read()
    for m in re.finditer(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+)", src, re.M):
        sk[m.group(1)] = int(m.group(2))
    api["soundkit"] = sk
    sb = set()
    for f in glob.glob(os.path.join(ADDONS, "Blizzard_SharedXML", "Shared", "Scroll", "*.lua")):
        for m in re.finditer(r"^function (ScrollBoxBaseMixin|ScrollBoxListMixin|ScrollBoxMixin):([A-Za-z]+)", open(f, encoding="utf-8").read(), re.M):
            sb.add(m.group(2))
    api["scrollbox_methods"] = sorted(sb)
    api["source"] = "wow-ui-source branch forever, build 1.60.1.70450 (commit 172a387e3ab85b26e6640d3058d5ec1e6ccd4c63)"
    return api


# ----------------------------------------------------------------------------------------------- addon data
def addon_data():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("function GetLocale() return 'enUS' end")
    run = lua.eval("function(src, name, ns) local f = assert(loadstring(src, name)); return f('WaylaidCrate', ns) end")
    ns = lua.table()
    for f in ("Util.lua", "Locale.lua", "Data.lua", "Writs.lua"):
        run(open(os.path.join(REPO, "WaylaidCrate", f), encoding="utf-8").read(), f, ns)
    ids = set(int(k) for k in ns.ITEMS.keys())
    crates = []
    for i in range(1, len(ns.CRATES) + 1):
        c = ns.CRATES[i]
        ids.add(int(c.id))
        opts = []
        for j in range(1, len(c.opts) + 1):
            ids.add(int(c.opts[j][1])); opts.append([int(c.opts[j][1]), int(c.opts[j][2])])
        crates.append({"id": int(c.id), "en": c.en, "opts": opts})
    writs = []
    for i in range(1, len(ns.WRITS) + 1):
        w = ns.WRITS[i]
        ids.add(int(w.writ)); ids.add(int(w.item))
        writs.append([int(w.writ), int(w.item)])
    return ids, crates, writs


def load_sv(path, var):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8").read())
    return lua, lua.eval(var)


def to_py(v):
    if hasattr(v, "keys"):
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[k]) for k in sorted(keys)]
        return {(k if isinstance(k, str) else int(k)): to_py(v[k]) for k in keys}
    return v


# ----------------------------------------------------------------------------------------------- main
DE_MATS = [10940, 10938, 10939, 10998, 11082, 11083, 11134, 11135, 11137, 11174, 11175, 11176, 16202, 16203, 16204,
           10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725, 247786]
# gear picked for disenchant / flip scenarios (see test_merge.py for what each one tests)
EXTRA_GEAR = [1273, 1275, 2230, 241089, 248006, 250483, 250482, 250620, 253885, 250488, 11287, 11288, 142503, 7955,
              2845, 3488, 2852, 2853, 7166, 6214, 241090, 246164]
INVTYPE = {0: "", 1: "INVTYPE_HEAD", 2: "INVTYPE_NECK", 3: "INVTYPE_SHOULDER", 4: "INVTYPE_BODY", 5: "INVTYPE_CHEST",
           6: "INVTYPE_WAIST", 7: "INVTYPE_LEGS", 8: "INVTYPE_FEET", 9: "INVTYPE_WRIST", 10: "INVTYPE_HAND",
           11: "INVTYPE_FINGER", 12: "INVTYPE_TRINKET", 13: "INVTYPE_WEAPON", 14: "INVTYPE_SHIELD", 15: "INVTYPE_RANGED",
           16: "INVTYPE_CLOAK", 17: "INVTYPE_2HWEAPON", 18: "INVTYPE_BAG", 19: "INVTYPE_TABARD", 20: "INVTYPE_ROBE",
           21: "INVTYPE_WEAPONMAINHAND", 22: "INVTYPE_WEAPONOFFHAND", 23: "INVTYPE_HOLDABLE", 24: "INVTYPE_AMMO",
           25: "INVTYPE_THROWN", 26: "INVTYPE_RANGEDRIGHT", 27: "INVTYPE_QUIVER", 28: "INVTYPE_RELIC"}


def main():
    dump("forever_api.json", build_api())

    ids, crates, writs = addon_data()
    ids |= set(DE_MATS) | set(EXTRA_GEAR)

    # order books (WaylaidCrate SV)
    _, wc = load_sv(os.path.join(args.sv, "WaylaidCrate.lua"), "WaylaidCrateDB")
    books = {}
    for k in wc.results.keys():
        r = wc.results[k]
        if r.status == "listed" and r.entries:
            books[int(k)] = [[int(r.entries[i][1]), int(r.entries[i][2])] for i in range(1, len(r.entries) + 1)]
    statuses = {int(k): wc.results[k].status for k in wc.results.keys()}
    ids |= set(books)

    # recipes + merchant scans (Getrich SV)
    _, gr = load_sv(os.path.join(args.sv, "Getrich.lua"), "GetrichDB")
    chars = {}
    for ck in gr.characters.keys():
        c = gr.characters[ck]
        guid = ck.split(":", 1)[1]
        profs = sorted(int(p) for p in c.professions.keys())
        recipes = {}
        for rid in c.recipes.keys():
            r = c.recipes[rid]
            reag = [[int(r.reagents[i].itemID), int(r.reagents[i].quantity)] for i in sorted(r.reagents.keys())] if r.reagents else []
            tools = [{"name": r.tools[i].name, "met": bool(r.tools[i].met), "type": int(r.tools[i].type or 0)}
                     for i in sorted(r.tools.keys())] if r.tools else []
            out = int(r.outputItemID) if r.outputItemID else None
            recipes[int(rid)] = {"name": r.name, "skillLine": int(r.professionID), "output": out,
                                 "qmin": int(r.minOutput or 1), "qmax": int(r.maxOutput or 1), "reagents": reag,
                                 "tools": tools, "learned": bool(r.learned)}
            if out:
                ids.add(out)
            for rg in reag:
                ids.add(rg[0])
        chars[guid] = {"professions": profs, "recipes": recipes}
    merchants = []
    for ok in gr.vendor.observations.keys():
        o = gr.vendor.observations[ok]
        offers = []
        npc = None
        for iid in o.offers.keys():
            f = o.offers[iid]
            npc = npc or {"npcID": int(f.npcID), "name": f.npcName, "zone": f.locationText, "map": int(f.mapID or 0),
                          "x": float(f.x or 0), "y": float(f.y or 0)}
            offers.append({"itemID": int(f.itemID), "price": int(f.pricePerPurchase or 0), "stackCount": int(f.purchaseQuantity or 1),
                           "numAvailable": int(f.numAvailable if f.numAvailable is not None else -1),
                           "hasExtendedCost": bool(f.hasExtendedCost), "isPurchasable": bool(f.isPurchasable)})
            ids.add(int(f.itemID))
        offers.sort(key=lambda e: e["itemID"])
        merchants.append({"key": ok, **npc, "offers": offers})
    merchants.sort(key=lambda m: m["key"])

    # item table from the Forever client data
    sparse = {}
    with open(os.path.join(args.db2, "ItemSparse.csv"), encoding="utf-8") as f:
        for d in csv.DictReader(f):
            sparse[int(d["ID"])] = d
    item = {}
    with open(os.path.join(args.db2, "Item.csv"), encoding="utf-8") as f:
        for d in csv.DictReader(f):
            item[int(d["ID"])] = d
    items, missing = {}, []
    for iid in sorted(ids):
        s, it = sparse.get(iid), item.get(iid)
        if not s or not it:
            missing.append(iid)
            continue
        items[iid] = {"name": s["Display_lang"], "quality": int(s["OverallQualityID"]), "ilvl": int(s["ItemLevel"]),
                      "req": int(s["RequiredLevel"]), "classID": int(it["ClassID"]), "subclassID": int(it["SubclassID"]),
                      "equipLoc": INVTYPE.get(int(it["InventoryType"]), ""), "sell": int(s["SellPrice"]),
                      "buy": int(s["BuyPrice"]), "vstack": int(s["VendorStackCount"]), "stack": int(s["Stackable"]),
                      "flags": int(s["Flags_0"]) & 0xFFFFFFFF, "icon": int(it["IconFileDataID"])}
    print("items:", len(items), "missing from Forever data:", missing)
    dump("items.json", {"source": "wago.tools DB2 ItemSparse+Item, build 1.60.1.70450", "items": items, "missing": missing})
    dump("recipes.json", {"source": "Getrich SavedVariables (user's Forever beta characters, builds 70425/70450)", "chars": chars})
    dump("orderbooks.json", {"source": "WaylaidCrate SavedVariables results (user's Forever beta AH scans, Oct 2026)",
                             "books": books, "status": statuses,
                             "crates": crates, "writs": writs})
    dump("merchants.json", {"source": "Getrich SavedVariables vendor.observations (merchant API scans)", "merchants": merchants})


if __name__ == "__main__":
    main()
