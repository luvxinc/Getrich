# Getrich

WoW Forever 挣钱助手。作者 **Aaron Tong**（联系：Luvx.inc@gmail.com）。

打开拍卖行就能用，一个窗口六个页签：

| 页签 | 做什么 |
|---|---|
| **箱子** | 全部 30 种 Waylaid Crate（学徒、熟练、专家、工匠），自动选最便宜的填法，按每个 Merchant's Favor 的成本排名 |
| **Writ** | 150 种 Craftsman's Writ，Writ + 需求物品都从拍卖行买，按每点声望的成本排名 |
| **倒卖** | 翻完整个拍卖行，找出一口价低于 NPC 收购价的挂单，买下卖店就赚 |
| **制造** | **赚钱**：每个配方的材料成本（拍卖行或商人，取便宜的）对比卖 NPC、挂拍卖行、做了再分解三种卖法的利润，可以把训练师能学但还没学的配方也算进来。**冲技能**：每点技能的成本、从当前技能到目标的最省钱路线和购物清单 |
| **分解** | 背包里的装备、拍卖行上的装备、你能做的装备：分解能出什么、值多少，比卖店多赚多少 |
| **走势** | 扫描过的物品的价格曲线：24 小时 / 7 天 / 30 天 / 全部 |

专业书里每个配方旁边显示利润；还没满级的专业会标出最省钱的 3 个冲技能配方。设置在
**游戏菜单 → 选项 → 插件 → Getrich**（或 `/gr settings`）。

A WoW Forever money-making addon by Aaron Tong: AH listings below the vendor price, crafting profit (vendor / AH /
disenchant) and a cheapest skill-up route, disenchanting, price history, Waylaid Crates and Craftsman's Writs. One window
docked to the Auction House, plus a settings page under Options → AddOns → Getrich.

## 怎么用

1. 把 `Getrich` 文件夹放进 `World of Warcraft/_forever_/Interface/AddOns/`，游戏里 `/reload`。
2. **每个专业的窗口各打开一次**，插件会记下你学会的配方和当前技能（学新配方、技能涨了会自动更新）。
3. 打开拍卖行，窗口自动贴在右边。选一个页签，点「扫描拍卖行」。开着自动扫描时，打开拍卖行会自动扫当前页；「倒卖」「分解」要翻完整个拍卖行，只在你点扫描时才扫。
   **装了 Auctionator 插件会快很多**：它每做完一次全拍卖行扫描，箱子页和 Writ 页立刻有估算价（带「~」），再点扫描只需十几秒核实前几名（见下面「Auctionator 和快速扫描」）。
4. 点任何物品名字，会填进拍卖行搜索栏直接搜索；鼠标悬停看全部明细（材料清单、商人位置、分解概率、冲技能路线）。

| 命令 | 作用 |
|---|---|
| `/gr` | 打开或关闭窗口（`/getrich`、旧的 `/wc` 也可以） |
| `/gr <页签>` | 打开某个页签：`crates` `writs` `flips` `craft` `de` `history` |
| `/gr scan [页签]` | 扫描当前页签（或指定页签） |
| `/gr stop` | 停止扫描 |
| `/gr settings` | 打开设置页 |
| `/gr auc` | Auctionator 的价格现在有没有在用，没用的话是什么原因 |
| `/gr errors` | 显示插件记录到的错误（出问题时发给作者） |
| `/gr help` | 命令列表 |

## 算法

- **拍卖行价格**：从最便宜的挂单开始，买够需要的数量来算（不是只看最低价）。你自己挂的不算。
- **商人价格**：插件内置 Forever 客户端里的商人售价和每组数量；你打开商人窗口时会记下你实际看到的价格（含声望、讲价折扣、限量库存）。卖完或库存不够的限量商品不当作货源。
- **卖 NPC 价格**：直接读游戏接口。商人不收的物品不算这条路。
- **挂拍卖行**：最低一口价 × 产量，扣拍卖行手续费：本阵营拍卖行 5%，中立拍卖行 15%（客户端 AuctionHouse 表）。
- **每个拍卖行的价格分开存**：正式服每个规则集、每个阵营各有一个拍卖行，中立拍卖行另算。价格和走势按「规则集 + 阵营」分开记录（规则集读游戏规则接口；`GetRealmName()` 在正式服只是内部分服名，同一规则集的分服共用拍卖行），换角色或在中立拍卖行扫描不会互相覆盖。
- **箱子奖励**：学徒 / 熟练 / 专家每箱 5 / 10 / 15 Favor（白色，原材料）和 10 / 20 / 30（绿色，成品），来自 Wowhead 的任务数据。工匠箱子的奖励目前没有任何公开来源，先按 20 / 40 估算并在界面上标「?」；你每次交箱，插件都会记下游戏实际给的 Favor 和金币，记到之后就用实际数值。
- **背包里已有的材料**：按当前市价算成本；悬停另外显示「还需要花多少钱」。
- **分解**：Forever 客户端的分解等级段 + 怀旧服概率，标为「估算」。已按 Wowhead 的正式服分解数据核对过主要产物：只有 21–30 物品等级的绿色武器和怀旧服不同（出 Greater Magic Essence），已改。你每次分解，插件会记下实际结果，同一等级段满 20 次（可在设置里改）后改用实测概率，标为「实测」。
- **冲技能**：配方的橙 / 黄 / 绿 / 灰门槛来自 Forever 客户端数据。升级概率：橙色 100%，黄色和绿色 = (灰色门槛 − 当前技能) ÷ (灰色门槛 − 黄色门槛)，灰色 0。
  每次制造的净成本 = 材料成本 − 做出来的东西的价值（卖 NPC、挂拍卖行扣 5%、分解价值里取最高；设置里可改成只算 NPC + 分解，或不抵扣）。
  每点技能成本 = 净成本 ÷ (升级概率 × 每次升几点)。路线是每一级都选每点最便宜的配方（已学的和训练师能学的），整条路线的材料合起来按拍卖行挂单重新算价。
- **没有价格不当 0**：缺价的显示「—」并说明缺哪一样，不会被当成免费或零利润。
- **不藏结果**：默认只隐藏已经被买走的倒卖；其他筛选都要你手动打开，隐藏了多少会显示出来。

## Auctionator 和快速扫描

箱子页要搜 126 个物品（约 2 分钟），Writ 页最多 300 个（约 4 分钟）。装了 Auctionator 时：

1. 在 Auctionator 里做一次全拍卖行扫描（Getrich 要已经加载）。扫完聊天框会提示，箱子页和 Writ 页立刻按它记录的最低价排好名，数字前带「~」。
2. 点 Getrich 的扫描：只精确搜索排在最前面的 5 项（设置里可改成 3 / 10 / 20），最多三轮，因为精确价格可能改变排名。核实过的行不再带「~」。
3. 这份估算用 12 小时。之后，或者 Auctionator 又在对立阵营 / 中立拍卖行扫描过（它的数据库不分阵营），Getrich 自动回到全扫，直到 Auctionator 在这个拍卖行再扫一次。

要点：

- 只用 Auctionator 公开给其他插件的接口（`Auctionator.API.v1`：价格、几天前见过、数据库更新通知），不读它的其他数据。接口不提供价格的具体时间和所属拍卖行，所以 Getrich 只认它亲眼看到完成的全扫描；单个物品的搜索、购物清单不算。
- 「~」的含义：只知道最低价，不知道那个价位有多少个，整组购买可能更贵；最低价也可能是你自己挂的。那次扫描没看到的物品按「没人卖」。
- Getrich 自己搜到的精确价格优先；较新的 Auctionator 扫描只有在最低价不同时才会替换它。
- 只影响箱子页和 Writ 页。倒卖、制造、分解、走势仍然只用 Getrich 自己的数据。
- `/gr auc` 随时查看状态。设置里可以关掉估算或快速扫描，关掉后和以前完全一样。

## 价格记录

- 每次扫描都会存：同一小时内再扫，覆盖这一小时的记录；下一小时新增一条。
- 只记相关物品：箱子和 Writ 用到的、你所有角色配方的材料和产物、分解材料、你关注（星标）的物品。
- 只记 Getrich 自己搜到的价格。快速扫描时，只有被精确搜索的那几项会新增记录；Auctionator 的估算不进走势。
- 小时记录默认保留 30 天，更早的压成每天一条（最低 / 平均 / 最高）；超过 14 天的挂单明细会自动清掉（曲线不受影响）。两个天数都能在设置里改。

## 数据来源

| 来源 | 内容 |
|---|---|
| WoW Forever 客户端数据表（wago.tools，build 1.60.1.70938） | 全部配方（门槛、材料、产物、学习方式）、商人售价和每组数量、分解等级段、不能分解的物品、箱子的等级 / 数量、拍卖行手续费、Legacy 天赋数值 |
| 作者在游戏里的商人记录（51 个商人） | Forever 实际售价、NPC 名字和坐标 |
| [pfQuest](https://github.com/shagu/pfQuest)（MIT） | 少数没见过的商人的怀旧服位置（标「怀旧服位置，可能有变」） |
| [warcraft.wiki.gg Disenchanting tables](https://warcraft.wiki.gg/wiki/Disenchanting_tables)、[DisenchantForever](https://github.com/APGM82/DisenchantForever)（MIT） | 分解概率和数量 |
| Wowhead（WoW Forever 数据库，2026-11-15 按正式服重新核对） | 箱子材料（物品提示）、每箱 Favor、150 张 Writ 的需求物品、数量和声望、送货单价格、Crate Return 和 Shipping Label 的声望 |
| wow-professions.com、leprestore.com、forever-codex.com、mmoherald.com | 交箱银币（Wowhead 没有这项，以游戏里实际记录为准）、送货单需要友善 |
| [warcraft.wiki.gg Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes) | 规则集的读法（`C_GameRules.IsGameRuleActive` + `Enum.GameRule.HardcoreRuleset / RPRuleset / PvPRuleset`） |
| Auctionator 的插件接口 `Auctionator.API.v1`（运行时调用，可选） | 箱子页和 Writ 页的估算价 |

数据表用 `tools/gen_data.py` 生成，见 [tools/README.md](tools/README.md)。手写的数据（箱子、Writ、手续费等）用
`tools/verify_game_data.py` 对照客户端数据表和 Wowhead 核对，游戏更新后跑一遍就知道哪里变了。

## 开发

```
pip install lupa
python3 tests/test_merge.py [--locale zhCN|zhTW] [--uncached]   # 场景测试：扫描、计价、冲技能、分解、记录、设置、界面、旧版回归
python3 tests/mock_test.py Getrich zhCN full                     # 箱子 / Writ（1.3.0 原有测试）
python3 tools/verify_game_data.py --db cache/1.60.1.70938 --download --wowhead   # 手写数据对照正式服
```

`tests/wowmock.py` 是模拟的 WoW Forever 客户端（按 Blizzard 1.60.1.70938 的界面源码核对过接口），
不存在的接口一调用就报错。测试用的价格和配方来自真实游戏存档（角色 ID 已匿名）。

## 版本

版本号 `YYYY.M.当月序号`：年、月（不补 0）、这个月第几次提交（从 0 开始）。写在
`Getrich/Getrich.toc` 的 `## Version`，发布日期写在 `## X-Released`（太平洋时间）。
每次提交都要升版本，并在 `CHANGELOG.md` 记录。

## 作者

Aaron Tong · Luvx.inc@gmail.com · https://github.com/luvxinc/Getrich
