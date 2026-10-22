# tools/gen_data.py

Generates the three data files of the addon. Never edit them by hand; re-run the generator.

| Output | Contents |
|---|---|
| `Getrich/DataVendor.lua` | `WC.VENDOR[itemID] = { buy, stack, npcs, seen, classic }`: items NPC vendors sell for gold with unlimited stock |
| `Getrich/DataDisenchant.lua` | `WC.DE = { spell, bands, noDE, mats }`: disenchant bands with estimated outputs |
| `Getrich/DataRecipes.lua` | `WC.RECIPES[skillLine][recipeID]` (thresholds, output, reagents, how it is learned) and `WC.SKILLUP` (skill-up chance rule) |

Python 3.8+ with the standard library only. `--check` also needs `lupa` (`pip install lupa`).

## Run

```sh
# refresh for a new client build (downloads the DB2 tables from wago.tools into --db)
python3 tools/gen_data.py --download --db cache/1.60.1.70532 --build 1.60.1.70532 \
    --sv path/to/WTF/Account/<ACCOUNT>/SavedVariables/Getrich.lua \
    --pfquest path/to/pfQuest --check
```

| Argument | Meaning |
|---|---|
| `--db DIR` | wago.tools CSV exports of the WoW Forever client: `ItemSparse`, `Item`, `ItemDisenchantLoot`, `SkillLineAbility`, `SpellReagents`, `SpellEffect`, `SpellName`, `ItemEffect`, `ItemXItemEffect` |
| `--build B` | client build of those tables (header text, and what `--download` fetches) |
| `--download` | fetch the tables from `https://wago.tools/db2/<Table>/csv?build=B` first |
| `--sv FILE` | SavedVariables with merchant scans made in the game (repeatable). Reads `GetrichDB.vendorObs` (Merchant.lua; `WaylaidCrateDB.vendorObs` before the rename) and the scan facts in the old Codex `GetrichDB.vendor.observations`. `--check` also compares recipes captured in the game with `WC.RECIPES` |
| `--pfquest DIR` | checkout of [shagu/pfQuest](https://github.com/shagu/pfQuest) (Classic vendor lists, NPC positions and factions) |
| `--out DIR` | addon folder (default `../Getrich`) |
| `--date D` | date written into the headers (default today); pass it to reproduce a file byte for byte |
| `--max-skill N` | vendor data: reagents of recipes up to this yellow skill; recipes: learn skill up to N (default 300) |
| `--per-side N` | at most N Classic NPCs per faction for an item (default 3) |
| `--check` | load the three files in Lua 5.1 and verify them (see below) |

`--check` alone only checks the files. With `--db` it generates first, so pass every input you used, or the
vendor file loses its Classic part.

The 2026-10-22 files were made from these inputs:
- Client build 1.60.1.70450. The DB2 tables used are byte-identical in 1.60.1.70532.
- The user's old Getrich.lua scans: 51 merchant scans from builds 70374-70450, and 300 captured recipes.
- pfQuest commit 104f356.

The `--check` run verifies:
- Disenchant chances sum to 1, every band has lo <= hi, and mats is complete.
- Recipe thresholds satisfy `1 <= s`, `y <= g`, and `s <= y` except for recipe items that ask more skill than
  Forever's yellow.
- `r` is a flat list of even length.
- Recipe outputs and recipe items exist in ItemSparse.
- Spot checks on known items and recipes.
- Every recipe captured in game matches `WC.RECIPES` in reagents and yield.

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

**Recipes.** One row per `SkillLineAbility` row of a profession skill line that has reagents or creates an item.

The file stores each skill line as one string, with one recipe per line in the form
`id,s,y,g,o,n1,n2,t,ri,se,su,ab,a,reagent,qty,...`.
- The first read of `WC.RECIPES[skillLine]` decodes that line into the row tables and drops the string.
- `WC.RECIPE_LINES` lists the lines; iterate it, because `pairs(WC.RECIPES)` shows decoded lines only.
- `WC.RecipeLine(recipeID)` finds a recipe's line without decoding anything.
- Memory in Lua 5.1: 148 KB after load (the eager table took 1.3 MB). A line adds 2-266 KB when decoded and
  takes at most 4 ms. `--check` decodes every line and compares every field with the source rows.
The recipe ID is the spell ID, which is what `C_TradeSkillUI` uses: all 300 captured recipe IDs are
`SkillLineAbility` spells.

| Field | Source |
|---|---|
| `y`, `g` | `TrivialSkillLineRankLow`, `TrivialSkillLineRankHigh` |
| `su` | `NumSkillUps` |
| `ab` | the `SkillLineAbility` ID |
| `r` | `SpellReagents` |
| `o`, `n1`, `n2` | `SpellEffect` 24 (create item). The count is `EffectBasePointsF`, spread by `Variance`: n = BP × (1 ± Variance/2). This matches Classic Era's die rolls, e.g. Iron Grenade 2-4 and Heavy Dynamite 1-5. A count of 0 means 1. |

How a recipe is learned (`t`):
1. **`"i"`, recipe item.** An item effect with TriggerType 6 names the spell, or casts a spell whose
   `SpellEffect` 36 learns it. The item must have an ItemSparse row and must not carry the deprecated flag
   `Flags_0` 0x10. For example, "Formula: Imbue Cloak - Protection" 6345 is deprecated, so Enchant Cloak - Minor
   Protection counts as a trainer recipe.
   - `ri` is the item.
   - `s` is the item's `RequiredSkillRank`.
2. **`"t"`, learned with the profession.** `AcquireMethod` is 1. `s` is `MinSkillLineRank`, which is 1.
   These rows carry `a = 1`: nothing to train.
3. **`"?"`, unknown source.**
   - The recipe's teaching item has no ItemSparse row in this build (55): a Classic plan Forever dropped, or a
     new Forever recipe item not released yet. `ri` names that item; Season of Discovery item IDs
     200000-239999 are ignored.
   - Or there is no recipe item and the spell has a Season of Discovery ID (398000-999999).
   - Or it is one of 12 Classic recipes no trainer taught (quest rewards or never available, listed in
     `NOT_TRAINER`).
   - In all three cases `s = y`, with `se = 1`.
4. **`"t"`, trainer.** Everything else.
   - The client has no trainer requirements, so `s = y` with `se = 1`. Classic trainers taught 439 of 440
     checked recipes at or below their Classic yellow (median 20 points below).
   - Forever changed some requirements (Bronze Warhammer was made at 110, yellow 155), so the in-game trainer
     window is the real source.

These recipes are left out:
- `AcquireMethod` 3: Classic recipes Forever retired or replaced, such as the Alchemy healing potions now in
  First Aid.
- Spells without a name.
- Learn skill above 300.
- 218 recipes whose product has no ItemSparse row in this build (unreleased or removed content).

The labels were checked against Classic trainer lists from cmangos classic-db, used only for checking.
1223 of the 1229 Classic-ID recipes agree:
- 747 recipe-item recipes have no Classic trainer.
- 424 trainer recipes have one.
- 28 are learned with the profession.
- 24 `"?"` recipes have no Classic trainer.

The 6 that disagree:
- Troll's Blood Elixir, Barbecued Buzzard Wing, Goblin Mining Helmet, Thorium Grenade and Thorium Widget were
  taught both ways in Classic; here they are `"i"`.
- Elixir of Minor Strength came with Alchemy in Classic; here it is `"t"`.

None of the 234 recipes the user's characters learned is `"?"`, and all 300 captured rows match in reagents
and yield.

Spot checks:
- Wowhead Forever item XML confirmed recipe items 2555, 2598 and 2881 with their required skill. It also confirmed
  the products and reagents of spells 2661 and 1244431.
- wowseer.gg confirmed trainer recipes 2661, 2541, 2963, 1244431 and 3276, and recipe item 2335.

**Skill-up chance (`WC.SKILLUP`):**
- Orange (skill < y): 1.
- Yellow and green (y <= skill < g): (g - skill) / (g - y).
- Grey (skill >= g): 0.

Blizzard has not published this rule; it is empirical. Sources:
- [TradeskillAdvice](https://wowinterface.com/downloads/info9529-TradeskillAdvice.html): "rate = (current
  skill-grey) / (yellow-grey)".
- SkillUp Forever's README calls it "the Classic formula".
- warcraft.wiki.gg [Skill up](https://warcraft.wiki.gg/wiki/Skill_up) only says the exact chances are unknown.
- vmangos uses steps of 100/75/25/0 per colour. These equal the linear formula's averages over the yellow and
  green halves.

## NOTICE (third-party data)

- **pfQuest** database, Copyright (c) 2017-2021 Eric Mauser (Shagu), MIT License. NPC ids, names, positions
  and factions in `DataVendor.lua` come from it. The full license text is in the header of `DataVendor.lua`.
- **DisenchantForever**, Copyright (c) 2026 APGM82, MIT License. Used only to cross-check the disenchant odds.
  No code or files are copied.
- **wago.tools** CSV exports of Blizzard's client tables. Game data (c) Blizzard Entertainment.
- vmangos (GPL-2.0) and cmangos classic-db (GPL-3.0) were only read to verify the odds and the trainer/item rule.
  No code or files are copied, and no trainer requirement from them ships. Getrich's GPL `Vendor.lua` is not used.
