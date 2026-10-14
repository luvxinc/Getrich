# Waylaid Crate

WoW Forever 插件：打开拍卖行时自动扫描 Waylaid Crate 和填充材料的价格，挑出每个箱子最便宜的填法，按 **每个 Merchant's Favor** 或 **每点声望** 的成本给 30 级以内的 22 种箱子排名，并高亮最优方案。

A WoW Forever addon that scans the Auction House for Waylaid Crates and their materials, picks the cheapest way to fill each crate, and ranks the 22 crates usable up to level 30 by cost per Merchant's Favor or per reputation point.

## 功能

- **自动扫描 + 进度条**：打开拍卖行 1 秒后开始，逐个查询 22 种箱子和 69 种材料（约 1–2 分钟，节流在暴雪每分钟 100 次查询以内）。
- **自动选最优填法**：每个箱子的多选一材料里，选拍卖行上数量够装满一箱、而且总价最低的那一组（从最便宜的挂单开始吃单计价）。没货或数量不够的选项自动跳过。
- **两种优先模式**
  - **商人货币**：成本 = 箱子价格 + 材料成本 − 交箱银币，除以每箱 Favor（含 Legacy「表现奖金」期望加成）。
  - **声望**：装满交箱给 **0** 声望。友善后，空箱 + 伪造的送货单（15 Favor）交回去 **+50** 声望（含 Legacy「外交官」加成）。成本 = 箱子价格 + 15 Favor（按你当前最便宜的 Favor 成本折算成金币），除以所得声望。
- **加成**：Legacy「表现奖金」0–3 级、「外交官」0–5 级在窗口里设置；种族加成自动检测（Forever 没有人类外交，插件仍会检查技能是否存在）。
- **点击搜索**：点箱子名或推荐材料，自动填进拍卖行搜索栏并搜索。
- **筛选**：只看我能开的 / 忽略没有箱子在售的 / 忽略材料都没货的。
- **语言自适应**：简体中文、繁體中文、English，跟随游戏客户端。

## 安装

把 `WaylaidCrate` 文件夹放进：

```
World of Warcraft/_classic_beta_/Interface/AddOns/
```

游戏里 `/reload`，打开拍卖行即可。`/wc` 打开或关闭窗口，`/wc scan` 手动扫描，`/wc stop` 停止。

## 数据（测试服，可能变化）

| 来源 | 内容 |
|---|---|
| Wowhead（WoW Forever 数据库） | 每个箱子的可选材料和数量 |
| wow-professions.com、leprestore.com | 每箱 Favor：学徒 白 5 / 绿 10，熟练 10 / 20，专家 15 / 30；交箱银币 |
| Wowhead「Forged Delivery Receipt」 | 空箱 + 送货单 +50 声望 |
| forever-codex.com、mmoherald.com（客户端数据） | 外交官 +2/4/6/8/10% 声望；表现奖金 5/10/15% 几率 Favor 翻倍 |
| Blizzard 官方 2026-09-22 种族公告 | 人类种族技能里没有 Diplomacy |

## 开发

`tests/mock_test.py` 用 LuaJIT 模拟 WoW 客户端和拍卖行，跑一遍完整扫描并检查计价、排名、筛选、点击搜索、声望模式和三种语言：

```
pip install lupa
python3 tests/mock_test.py WaylaidCrate enUS full
python3 tests/mock_test.py WaylaidCrate zhCN full
python3 tests/mock_test.py WaylaidCrate zhCN close   # 扫描中途关闭拍卖行
```

## 版本

版本号写在 `WaylaidCrate/WaylaidCrate.toc` 的 `## Version`，每次更新都要升版本，并在 `CHANGELOG.md` 记录。
