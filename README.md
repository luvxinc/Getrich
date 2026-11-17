# Getrich

WoW Forever 挣钱助手。作者 **Aaron Tong**（联系：Luvx.inc@gmail.com）。

拍卖行价格全部来自 **Auctionator** 的全拍卖行扫描（必须安装）：Getrich 自己不再扫描，登录后不用开拍卖行就有数据。一个窗口六个页签：

| 页签 | 做什么 |
|---|---|
| **箱子** | 全部 30 种 Waylaid Crate（学徒、熟练、专家、工匠），自动选最便宜的填法，按每个 Merchant's Favor 的成本排名 |
| **Writ** | 150 种 Craftsman's Writ，Writ + 需求物品都从拍卖行买，按每点声望的成本排名；今天交过的自动消失。**冲声望**：从当前声望到目标声望，今天交哪些最省钱、要买什么、一共多少钱 |
| **倒卖** | Auctionator 扫到的、一口价低于 NPC 收购价的物品，买下卖店就赚 |
| **制造** | **赚钱**：每个配方的材料成本（拍卖行或商人，取便宜的）对比卖 NPC、挂拍卖行、做了再分解三种卖法的利润，可以把训练师能学但还没学的配方也算进来。**冲技能**：每点技能的成本、从当前技能到目标的最省钱路线和购物清单 |
| **分解** | 背包里的装备、拍卖行上的装备、你能做的装备：分解能出什么、值多少，比卖店多赚多少 |
| **走势** | 价格曲线：24 小时 / 7 天 / 30 天 / 全部 |

专业书里每个配方旁边显示利润；还没满级的专业会标出最省钱的 3 个冲技能配方。设置在
**游戏菜单 → 选项 → 插件 → Getrich**（或 `/gr settings`）。

A WoW Forever money-making addon by Aaron Tong: AH listings below the vendor price, crafting profit (vendor / AH /
disenchant) and a cheapest skill-up route, disenchanting, price history, Waylaid Crates and Craftsman's Writs. Prices come
from Auctionator's full scans (required), so everything is there right after login; a "Check the best" button searches the
top entries of a tab exactly. One window docked to the Auction House, plus a settings page under Options → AddOns → Getrich.

## 怎么用

1. 装好 [Auctionator](https://www.curseforge.com/wow/addons/auctionator)，把 `Getrich` 文件夹放进 `World of Warcraft/_forever_/Interface/AddOns/`，重启游戏。
2. **每个专业的窗口各打开一次**，插件会记下你学会的配方和当前技能（学新配方、技能涨了会自动更新）。
3. 在拍卖行里用 **Auctionator 做一次全扫描**。扫完聊天框提示一次，六个页签立刻有数据。以后想要新行情，就再用 Auctionator 扫一次；Getrich 不需要任何操作。
4. Auctionator 的数据存在它自己的存档里，**下线再上线都在**：登录后 `/gr` 就能看，不用开拍卖行，也不用重新扫描。窗口底部写着这份价格是什么时候的。
5. 数字前带「~」的是估算（只知道最低价）。要精确的数，开着拍卖行点 **「核实前几名」**：只搜索当前页排在最前面的几项，十几秒（见下面「价格从哪来」）。
6. 点任何物品名字，会填进拍卖行搜索栏直接搜索；鼠标悬停看全部明细（材料清单、商人位置、分解概率、冲技能路线）。

| 命令 | 作用 |
|---|---|
| `/gr` | 打开或关闭窗口（`/getrich`、旧的 `/wc` 也可以） |
| `/gr <页签>` | 打开某个页签：`crates` `writs` `flips` `craft` `de` `history` |
| `/gr check [页签]` | 核实当前页签（或指定页签）的前几名，要开着拍卖行（旧的 `/gr scan` 也可以） |
| `/gr stop` | 停止核实 |
| `/gr settings` | 打开设置页 |
| `/gr auc` | 价格来自 Auctionator 哪一次扫描；没有价格的话是什么原因 |
| `/gr errors` | 显示插件记录到的错误（出问题时发给作者） |
| `/gr help` | 命令列表 |

## 算法

- **拍卖行价格**：核实过的物品，从最便宜的挂单开始买够需要的数量来算（不是只看最低价），你自己挂的不算。没核实的物品用 Auctionator 记录的最低价 × 数量，数字前带「~」。
- **商人价格**：插件内置 Forever 客户端里的商人售价和每组数量；你打开商人窗口时会记下你实际看到的价格（含声望、讲价折扣、限量库存）。卖完或库存不够的限量商品不当作货源。
- **卖 NPC 价格**：直接读游戏接口。商人不收的物品不算这条路。
- **挂拍卖行**：最低一口价 × 产量，扣拍卖行手续费：本阵营拍卖行 5%，中立拍卖行 15%（客户端 AuctionHouse 表）。
- **每个拍卖行分开**：正式服每个规则集、每个阵营各有一个拍卖行，中立拍卖行另算。核实结果和走势按「规则集 + 阵营」分开记录（规则集读游戏规则接口；`GetRealmName()` 在正式服只是内部分服名，同一规则集的分服共用拍卖行）。Auctionator 的数据库不分阵营，所以 Getrich 记着它看到的那次全扫描是在哪个拍卖行：换到另一个拍卖行时不会拿别处的价格来用，要在这里再扫一次。
- **箱子奖励**：学徒 / 熟练 / 专家每箱 5 / 10 / 15 Favor（白色，原材料）和 10 / 20 / 30（绿色，成品），来自 Wowhead 的任务数据。工匠箱子的奖励目前没有任何公开来源，先按 20 / 40 估算并在界面上标「?」；你每次交箱，插件都会记下游戏实际给的 Favor 和金币，记到之后就用实际数值。
- **背包里已有的材料**：按当前市价算成本；悬停另外显示「还需要花多少钱」。
- **分解**：Forever 客户端的分解等级段 + 怀旧服概率，标为「估算」。已按 Wowhead 的正式服分解数据核对过主要产物：只有 21–30 物品等级的绿色武器和怀旧服不同（出 Greater Magic Essence），已改。你每次分解，插件会记下实际结果，同一等级段满 20 次（可在设置里改）后改用实测概率，标为「实测」。
- **冲技能**：配方的橙 / 黄 / 绿 / 灰门槛来自 Forever 客户端数据。升级概率：橙色 100%，黄色和绿色 = (灰色门槛 − 当前技能) ÷ (灰色门槛 − 黄色门槛)，灰色 0。
  每次制造的净成本 = 材料成本 − 做出来的东西的价值（卖 NPC、挂拍卖行扣 5%、分解价值里取最高；设置里可改成只算 NPC + 分解，或不抵扣）。
  每点技能成本 = 净成本 ÷ (升级概率 × 每次升几点)。路线是每一级都选每点最便宜的配方（已学的和训练师能学的），整条路线的材料合起来按拍卖行挂单重新算价。
- **没有价格不当 0**：缺价的显示「—」并说明缺哪一样，不会被当成免费或零利润。
- **不藏结果**：默认只隐藏已经被买走的倒卖；其他筛选都要你手动打开，隐藏了多少会显示出来。

## 冲声望（Writ 页）

每张 Writ 每天只能交一次。插件读游戏的任务完成标记，并且自己记下你今天交过的（按角色，到每日重置清零），交过的从列表和方案里消失。

Writ 页左上的「视图」切到 **冲声望**：

1. 选目标（下一级 / 尊敬 / 崇敬 / 崇拜）。当前声望和还差多少点从游戏读。
2. 方案列出今天该交的每一张：Writ 价格、需求物品成本、声望、每点成本。上方是合计：交几张、得多少声望、今天要花多少钱。
3. 背包里已有的标「背包已有」，不再计入要花的钱；需求物品只买缺的数量。
4. 点 **购物清单**，把要买的全部物品发到 Auctionator 的购物清单「Getrich 声望」，到 Auctionator 的「购物」页选它逐个买。也可以点任意一行的名字直接搜索。
5. 买完交掉，交过的那一行就消失，合计跟着变。

规则：

- 方案是能凑够声望的最便宜的组合（Writ 有 75 / 125 / 200 三档，每张最多一次），不是简单按单价排。
- 今天凑不够时，今天能交的全部列出，并按今天的价格估算还要几天。
- 「每点上限」把太贵的留到以后；「用 Favor」允许用现有的 Merchant's Favor 换送货单（空箱 + 送货单 = 50 声望，需要友善，每张 15 Favor），不想动 Favor 就关掉。
- 在这个视图里点「核实前几名」，会精确搜索方案里要买的全部物品，然后重新规划。
- 只看背包，不看银行。「几天」按今天的价格估，仅供参考。

## 价格从哪来

Getrich 只用 Auctionator 公开给其他插件的接口（`Auctionator.API.v1`）：某个物品的最低价、它是几天前见到的、数据库更新通知。不读它的其他数据。

**这个接口能给的，和给不了的：**

| 接口不提供 | Getrich 的做法 |
|---|---|
| 物品还有没有人卖（卖光的物品，旧价格还留着） | 先找出 Auctionator 最近一次全扫描是哪一天；那天或之后见过的物品才算在售，其余按「没人卖」 |
| 最低价那一档有多少个 | 最低价 × 数量只是下限，标「~」；「核实前几名」精确搜索 |
| 最低价是不是你自己挂的 | 核实时会排除你自己的挂单 |
| 价格的具体时间（只有「几天前」） | 拍卖行开着时 Getrich 每 5 秒看一眼 Auctionator 的价格；一大批箱子和 Writ 物品同时变化就是一次全扫描，记下时间和所在拍卖行。看到过的扫描精确到分钟（「25 分钟前」），没看到的（装 Getrich 之前扫的）只显示「今天 / 昨天 / N 天前」 |
| 哪些物品在售（只能按物品 ID 一个一个问） | 插件内置一张物品表（客户端里所有能交易、商人收购或能分解的 7,197 个物品），倒卖页和分解页照这张表去问 |

**「核实前几名」做什么：**

| 页签 | 精确搜索的内容 |
|---|---|
| 箱子 / Writ | 排在最前面的 5 项（设置里可选 3 / 5 / 10 / 20）用到的全部物品。精确价格会改变排名，新进前列的接着查，直到前几名全部是精确价 |
| 倒卖 | 赚得最多的 80 个候选（设置里可选 40 / 80 / 150）：到底有几个低于商店价 |
| 制造 | 赚钱模式：最赚钱的 5 个配方要从拍卖行买的材料和它们的产物。冲技能模式：当前路线的购物清单和产物 |
| 分解 | 全部附魔材料（24 种） |
| 走势 | 你关注（星标）的物品 |

**为什么还要核实**（作者 2026-11-15 的真实数据）：

- 拿 Getrich 当时精确搜到的 126 个箱子物品的挂单明细算：96 种箱子材料组合里，「最低价 × 数量」和真实成本完全一致的 86 种，差 3% 以内的 7 种，差得多的 3 种（1.3 倍、4.5 倍、5.75 倍）。差得最多的是 20 个 Strange Dust：最便宜的一档只挂了 1 个（20 铜），按最低价算 4 银，实际要 23 银；只看最低价的话，这只箱子会排到第一名（每 Favor 58 铜），真正的第一名是每 Favor 1 银 45 铜的另一只。
- 用 Auctionator 同一天另一时刻的价格做估算、上面的挂单明细当作拍卖行回放：核实前 5 名搜 22 个物品、约 15 秒；最便宜的箱子和前四名与把 126 个物品全部精确搜索一遍（约 109 秒）的结果一致。真实的第 5 名因为两份数据之间价格变了、估算偏高，排在第 6 没被核实（它和核实出来的第 5 名每 Favor 只差 1 铜）。核实前 10 名（54 个物品、约 37 秒）时前六名全部一致。
- Writ 没有同期的挂单明细可比，按模拟的挂单深度：核实前 5 名 10 个物品约 7 秒，全部精确搜索 300 个物品约 219 秒。

**哪个价格优先：**

- 核实比 Auctionator 的扫描新：用核实的挂单明细。
- 扫描比核实新：最低价没变、而且核实是 24 小时以内的，继续用挂单明细；否则改用 Auctionator 的最低价（带「~」）。
- 没装 Auctionator、或它还没做过全扫描：窗口底部和聊天框会说明缺什么（每次登录提示一次），`/gr auc` 随时查看。

**局限：**

- Auctionator 按「天」记录。同一天里先扫到、后来卖光的物品，在下一次全扫描之前仍按有货算；核实时会发现并跳到下一名。Auctionator 的数据越旧，核实要查的轮数越多，先用 Auctionator 重扫一次更快。
- 核实范围之外的行都是 Auctionator 扫描那一刻的行情：之后变便宜的东西，要等 Auctionator 再扫一次才会排上来。
- 带随机后缀的装备（「of the Bear」）在 Auctionator 里按物品 ID 合并成一个最低价；精确搜索不带后缀，搜不到时保留估算。

## 价格记录

- Auctionator 每完成一次全扫描（Getrich 已加载、拍卖行开着），相关物品各记一个点（只有最低价）；核实过的物品另外记下最低价和挂单数量。同一小时内覆盖，下一小时新增一条。
- 只记相关物品：箱子和 Writ 用到的、你所有角色配方的材料和产物、分解材料、你关注（星标）的物品。
- 小时记录默认保留 30 天，更早的压成每天一条（最低 / 平均 / 最高）；超过 14 天的核实结果会自动清掉（曲线不受影响）。两个天数都能在设置里改。

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
| WoW Forever 客户端数据表 ItemSparse + Item（同一 build） | 内置物品表 `DataItems.lua`：7,197 个可交易物品的商店收购价，其中 1,192 件可分解装备的品质、类别和物品等级 |
| Auctionator 的插件接口 `Auctionator.API.v1`（运行时调用，必需） | 全部拍卖行价格；冲声望的购物清单（`CreateShoppingList`） |
| WoW Forever 客户端数据表 Faction（同一 build）、暴雪界面源码的声望接口说明 | 声望等级的起点（3,000 / 9,000 / 21,000 / 42,000）和当前声望的读法 |

数据表用 `tools/gen_data.py` 生成，见 [tools/README.md](tools/README.md)。手写的数据（箱子、Writ、手续费等）用
`tools/verify_game_data.py` 对照客户端数据表和 Wowhead 核对，游戏更新后跑一遍就知道哪里变了。

## 开发

```
pip install lupa
python3 tests/test_merge.py [--locale zhCN|zhTW] [--uncached]   # 场景测试：Auctionator 价格、核实、计价、冲声望、冲技能、分解、记录、设置、界面、旧版回归
python3 tests/mock_test.py Getrich zhCN full                     # 箱子 / Writ 的计价（1.3.0 原有测试）+ 2026.11.2 的流程，另一套独立的模拟客户端
python3 tools/gen_data.py --check --out Getrich                  # 检查内置数据表
python3 tools/verify_game_data.py --db cache/1.60.1.70938 --download --wowhead   # 手写数据对照正式服
```

`tests/wowmock.py` 是模拟的 WoW Forever 客户端（按 Blizzard 1.60.1.70938 的界面源码核对过接口），
不存在的接口一调用就报错。测试用的价格和配方来自真实游戏存档（角色 ID 已匿名）。测试里的 Auctionator 是一个只实现
`Auctionator.API.v1` 三个函数的替身，不包含 Auctionator 的任何代码。

## 版本

版本号 `YYYY.M.当月序号`：年、月（不补 0）、这个月第几次提交（从 0 开始）。写在
`Getrich/Getrich.toc` 的 `## Version`，发布日期写在 `## X-Released`（太平洋时间）。
每次提交都要升版本，并在 `CHANGELOG.md` 记录。

## 作者

Aaron Tong · Luvx.inc@gmail.com · https://github.com/luvxinc/Getrich
