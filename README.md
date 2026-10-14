# Waylaid Crate

WoW Forever 插件，窗口分两页：

- **箱子 · 商人货币**：扫描 30 级以内 22 种 Waylaid Crate 和填充材料，自动选每个箱子最便宜的填法，按每个 Merchant's Favor 的成本排名。
- **Writ · 声望**：扫描 150 种 Craftsman's Writ 和它们要的物品，按每点声望的成本排名。

A WoW Forever addon with two tabs: Waylaid Crates ranked by cost per Merchant's Favor, and Craftsman's Writs ranked by cost per reputation point. Both scan the Auction House and highlight the best option.

## 功能

**两页共用**
- 打开拍卖行 1 秒后自动扫描当前页，带进度条；查询节流在暴雪每分钟 100 次以内。
- 价格按「从最便宜的挂单开始，买够所需数量」计算。
- 点名字直接填进拍卖行搜索栏并搜索；鼠标悬停看全部细节。
- 界面语言跟随游戏客户端：简体中文、繁體中文、English。

**箱子 · 商人货币**
- 每个箱子的多选一材料里，自动选数量够装满一箱、总价最低的那一组；没货或数量不够的选项跳过。
- 成本 = 箱子价格 + 材料成本 − 交箱银币，除以每箱 Favor（含 Legacy「表现奖金」0–3 级的期望加成）。
- 装满交箱的声望是 **0**。
- 筛选：只看我能开的 / 忽略没有箱子在售的 / 忽略材料都没货的。

**Writ · 声望**
- 每张 Craftsman's Writ 道具和它要的物品都从拍卖行买，交给地图上标出的客户得声望（熟练 +75、专家 +125、工匠 +200），每张每天一次。
- 成本 = Writ 价格 + 需求物品价格，除以声望（含 Legacy「外交官」0–5 级 +2/4/6/8/10%；种族加成自动检测，Forever 没有人类外交）。
- 扫描分两步：先扫 150 张 Writ，再只扫在售 Writ 的需求物品。关掉「忽略没有 Writ 在售的」会扫全部 150 个物品。
- 自动标出今天已交的 Writ（读取任务完成状态）。
- 另含一行「空箱 + 送货单」：友善后最便宜的箱子 + 15 Favor 送货单 = +50 声望（15 Favor 按你当前最便宜的 Favor 成本折算）。
- 筛选：忽略没有 Writ 在售的 / 忽略需求物品买不到的 / 隐藏今天已交的。

## 安装

把 `WaylaidCrate` 文件夹放进：

```
World of Warcraft/_classic_beta_/Interface/AddOns/
```

游戏里 `/reload`，打开拍卖行即可。

| 命令 | 作用 |
|---|---|
| `/wc` | 打开或关闭窗口 |
| `/wc scan` | 扫描当前页 |
| `/wc crates` / `/wc writs` | 切到对应页并扫描 |
| `/wc stop` | 停止扫描 |

## 数据（测试服，可能变化）

| 来源 | 内容 |
|---|---|
| Wowhead（WoW Forever 数据库） | 箱子的可选材料和数量 |
| Wowhead 任务页（150 页逐个核对，2026-10-14） | 每张 Writ 的道具 ID、任务 ID、需求物品和数量、声望 |
| wowreputations.com、wowforevertalents.com（客户端任务缓存） | Writ 清单交叉核对 |
| wow-professions.com、leprestore.com | 每箱 Favor：学徒 白 5 / 绿 10，熟练 10 / 20，专家 15 / 30；交箱银币 |
| Wowhead「Forged Delivery Receipt」 | 空箱 + 送货单 +50 声望 |
| forever-codex.com、mmoherald.com（客户端数据） | 外交官 +2/4/6/8/10% 声望；表现奖金 5/10/15% 几率 Favor 翻倍 |
| Blizzard 官方 2026-09-22 种族公告 | 人类种族技能里没有 Diplomacy |

## 开发

`tests/mock_test.py` 用 LuaJIT 模拟 WoW 客户端和拍卖行，跑完两页的扫描，检查计价、排名、筛选、点击搜索、Writ 两阶段扫描、今天已交、加成和三种语言：

```
pip install lupa
python3 tests/mock_test.py WaylaidCrate enUS full
python3 tests/mock_test.py WaylaidCrate zhCN full
python3 tests/mock_test.py WaylaidCrate zhCN close   # 扫描中途关闭拍卖行
```

## 版本

版本号写在 `WaylaidCrate/WaylaidCrate.toc` 的 `## Version`，每次更新都要升版本，并在 `CHANGELOG.md` 记录。
