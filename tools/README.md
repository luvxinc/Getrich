# tools/gen_data.py

Generates the two data files of the addon. Never edit them by hand; re-run the generator.

| Output | Contents |
|---|---|
| `WaylaidCrate/DataVendor.lua` | `WC.VENDOR[itemID] = { buy, stack, npcs, seen, classic }`: items NPC vendors sell for gold with unlimited stock |
| `WaylaidCrate/DataDisenchant.lua` | `WC.DE = { spell, bands, noDE, mats }`: disenchant bands with estimated outputs |

Python 3.8+ with the standard library only. `--check` also needs `lupa` (`pip install lupa`).

## Run

```sh
# refresh for a new client build (downloads 5 DB2 tables from wago.tools into --db)
python3 tools/gen_data.py --download --db cache/1.60.1.70532 --build 1.60.1.70532 \
    --sv path/to/WTF/Account/<ACCOUNT>/SavedVariables/WaylaidCrate.lua \
    --pfquest path/to/pfQuest --check
```

| Argument | Meaning |
|---|---|
| `--db DIR` | wago.tools CSV exports of the WoW Forever client: `ItemSparse`, `Item`, `ItemDisenchantLoot`, `SkillLineAbility`, `SpellReagents` |
| `--build B` | client build of those tables (header text, and what `--download` fetches) |
| `--download` | fetch the tables from `https://wago.tools/db2/<Table>/csv?build=B` first |
| `--sv FILE` | SavedVariables with merchant scans made in the game (repeatable). Reads `WaylaidCrateDB.vendorObs` (Merchant.lua) and the scan facts in `GetrichDB.vendor.observations` |
| `--pfquest DIR` | checkout of [shagu/pfQuest](https://github.com/shagu/pfQuest) (Classic vendor lists, NPC positions and factions) |
| `--out DIR` | addon folder (default `../WaylaidCrate`) |
| `--date D` | date written into the headers (default today); pass it to reproduce a file byte for byte |
| `--max-skill N` | recipes up to this yellow skill count (default 300) |
| `--per-side N` | at most N Classic NPCs per faction for an item (default 3) |
| `--check` | load both files in Lua 5.1 and verify them (chances sum to 1, lo <= hi, mats complete, spot checks) |

The 2026-10-21 files were made from build 1.60.1.70450 (the five tables are byte-identical in 1.60.1.70532),
the user's Getrich.lua scans (51 merchant scans, builds 70374-70450) and pfQuest commit 104f356.

## How the data is chosen

**Vendor items.** Every item seen in a merchant scan sold for gold with unlimited stock gets `seen = true`:
- The price and bundle come from the newest scan.
- Personal discounts (reputation, the Bartering perk) are undone. Each scan's discount is the most common ratio
  between the price paid and ItemSparse `BuyPrice`.
- A scan from an older build whose price disagrees with the current ItemSparse is replaced by ItemSparse.
- The NPCs listed are the scanned NPCs, with exact positions.

Then recipe reagents (all professions plus Poisons, yellow skill <= 300) that Classic vendors sold with
unlimited stock (pfQuest `V` stock 0) are added with `classic = true`:
- `buy` and `stack` come from the Forever ItemSparse (`BuyPrice`, `VendorStackCount`).
- Reagents sold only in limited stock are left out (herbs, Strange Dust, engineering parts).
- A faction that no scanned NPC covers gets up to 3 Classic NPCs, marked with a 7th field `true`. Capital
  cities come first.
- These NPCs are left out: NPCs with no spawn point, Winter Veil-only vendors, and NPCs the user scanned
  (the scan decides).

**Disenchanting.**
- Bands (quality, class, item-level range) come from the Forever `ItemDisenchantLoot` table.
- Outputs are the Classic 1.12 table: vmangos/cmangos `disenchant_loot_template`, cross-checked with
  warcraft.wiki.gg [Disenchanting tables](https://warcraft.wiki.gg/wiki/Disenchanting_tables) and
  [DisenchantForever](https://github.com/APGM82/DisenchantForever) `Materials.lua`. All three agree for every
  band up to item level 60.
- Forever's new rare bands 5-15 and 16-20 (and 21-25, formerly 20-25) fall inside the wiki's Classic rare 1-25
  row: Small Glimmering Shard 100%. `est = "nearest"` would mark a band with no Classic equivalent; there is none now.
- `SkillRequired` is 0 in every Forever band (and in Classic Era), so `skill = 1`.
- `noDE` lists weapons and armor of quality 2-4, item level <= 70, that carry ItemSparse `Flags_0` 0x8000.

## NOTICE (third-party data)

- **pfQuest** database, Copyright (c) 2017-2021 Eric Mauser (Shagu), MIT License. NPC ids, names, positions
  and factions in `DataVendor.lua` come from it. The full license text is in the header of `DataVendor.lua`.
- **DisenchantForever**, Copyright (c) 2026 APGM82, MIT License. Used only to cross-check the disenchant odds.
  No code or files are copied.
- **wago.tools** CSV exports of Blizzard's client tables. Game data (c) Blizzard Entertainment.
- vmangos (GPL-2.0) and cmangos classic-db (GPL-3.0) were only read to verify the odds. No code or files are
  copied. Getrich's GPL `Vendor.lua` is not used.
