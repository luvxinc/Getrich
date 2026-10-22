# Waylaid Crate

WoW Forever 挣钱助手。打开拍卖行就能用，一个窗口六个页签：

| 页签 | 做什么 |
|---|---|
| **箱子** | 30 级以内 22 种 Waylaid Crate，自动选最便宜的填法，按每个 Merchant's Favor 的成本排名 |
| **Writ** | 150 种 Craftsman's Writ，Writ + 需求物品都从拍卖行买，按每点声望的成本排名 |
| **倒卖** | 翻完整个拍卖行，找出一口价低于 NPC 收购价的挂单，买下卖店就赚 |
| **制造** | 你已学的配方：材料成本（拍卖行或商人，取便宜的）对比卖 NPC、挂拍卖行、拆解三种卖法的利润 |
| **分解** | 背包里的装备、拍卖行上的装备、你能做的装备：分解能出什么、值多少，比卖店多赚多少 |
| **走势** | 扫描过的物品的价格曲线：24 小时 / 7 天 / 30 天 / 全部 |

A WoW Forever money-making addon: Waylaid Crates per Merchant's Favor, Craftsman's Writs per reputation point, AH listings
below the vendor price, crafting profit (sell to vendor / AH / disenchant), disenchanting, and price history. All in one
window docked to the Auction House.

## 怎么用

1. 把 `WaylaidCrate` 文件夹放进 `World of Warcraft/_classic_beta_/Interface/AddOns/`，游戏里 `/reload`。
2. **每个专业的窗口各打开一次**，插件会记下你学会的配方（换角色、学新配方后再开一次即可）。
3. 打开拍卖行，窗口自动贴在右边。选一个页签，点「扫描拍卖行」。开着自动扫描时，打开拍卖行会自动扫当前页；「倒卖」「分解」要翻完整个拍卖行，只在你点扫描时才扫。
4. 点任何物品名字，会填进拍卖行搜索栏直接搜索；鼠标悬停看全部明细（材料清单、商人位置、分解概率）。

| 命令 | 作用 |
|---|---|
| `/wc` | 打开或关闭窗口 |
| `/wc <页签>` | 打开某个页签：`crates` `writs` `flips` `craft` `de` `history` |
| `/wc scan [页签]` | 扫描当前页签（或指定页签） |
| `/wc stop` | 停止扫描 |
| `/wc errors` | 显示插件记录到的错误（出问题时发给我） |
| `/wc help` | 命令列表 |

## 算法

- **拍卖行价格**：从最便宜的挂单开始，买够需要的数量来算（不是只看最低价）。你自己挂的不算。
- **商人价格**：插件内置 Forever 客户端里的商人售价和每组数量；你打开商人窗口时会记下你实际看到的价格（含声望、讲价折扣、限量库存）。卖完或库存不够的限量商品不当作货源。
- **卖 NPC 价格**：直接读游戏接口。商人不收的物品不算这条路。
- **挂拍卖行**：最低一口价 × 产量，扣 5% 拍卖行手续费。
- **背包里已有的材料**：按当前市价算成本；悬停另外显示「还需要花多少钱」。
- **分解**：Forever 客户端的分解等级段 + 怀旧服概率，标为「估算」。你每次分解，插件会记下实际结果，同一等级段满 20 次后改用实测概率，标为「实测」。
- **没有价格不当 0**：缺价的显示「—」并说明缺哪一样，不会被当成免费或零利润。
- **不藏结果**：默认只隐藏已经被买走的倒卖；其他筛选都要你手动打开，隐藏了多少会显示出来。

## 价格记录

- 每次扫描都会存：同一小时内再扫，覆盖这一小时的记录；下一小时新增一条。
- 只记相关物品：箱子和 Writ 用到的、你所有角色配方的材料和产物、分解材料、你关注（星标）的物品。
- 小时记录保留 30 天，更早的压成每天一条（最低 / 平均 / 最高）。
- 超过 14 天的挂单明细会自动清掉（曲线不受影响）。

## 数据来源（测试服，可能变化）

| 来源 | 内容 |
|---|---|
| WoW Forever 客户端数据表（wago.tools，build 1.60.1.70450） | 商人售价和每组数量、分解等级段、不能分解的物品 |
| 你在游戏里的商人记录（51 个商人） | Forever 实际售价、NPC 名字和坐标 |
| [pfQuest](https://github.com/shagu/pfQuest)（MIT） | 少数没见过的商人的怀旧服位置（标「怀旧服位置，可能有变」） |
| [warcraft.wiki.gg Disenchanting tables](https://warcraft.wiki.gg/wiki/Disenchanting_tables)、[DisenchantForever](https://github.com/APGM82/DisenchantForever)（MIT） | 分解概率和数量 |
| Wowhead（WoW Forever 数据库） | 箱子材料、150 张 Writ 的需求物品、数量和声望 |
| wow-professions.com、leprestore.com、forever-codex.com、mmoherald.com | 每箱 Favor、交箱银币、Legacy 加成 |

数据表用 `tools/gen_data.py` 生成，见 [tools/README.md](tools/README.md)。

## 开发

```
pip install lupa
python3 tests/test_merge.py [--locale zhCN|zhTW]   # 25 个场景：扫描、计价、分解、记录、界面、旧版回归
python3 tests/mock_test.py WaylaidCrate zhCN full   # 箱子 / Writ（1.3.0 原有测试）
```

`tests/wowmock.py` 是模拟的 WoW Forever 客户端（按 Blizzard 1.60.1.70450 的界面源码核对过接口），
不存在的接口一调用就报错。测试用的价格和配方来自真实游戏存档。

## 版本

版本号 `YYYY.M.当月序号`：年、月（不补 0）、这个月第几次提交（从 0 开始）。写在
`WaylaidCrate/WaylaidCrate.toc` 的 `## Version`，发布日期写在 `## X-Released`（太平洋时间）。
每次提交都要升版本，并在 `CHANGELOG.md` 记录。
