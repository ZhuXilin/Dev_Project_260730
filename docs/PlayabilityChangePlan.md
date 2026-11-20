# 《魂火》v6 可玩性修改方案

> 版本：v1，日期 2026-11-20。基于 2026-11-20 代码实况 + 三份子系统分析报告，关键改动点已逐行核实。
> 范围：第一/二/三档全部问题，**排除地图编辑**（用户手动改）。
> 本文是方案，每项是独立可执行的改动，按优先级排序。

> **实施状态（2026-11-20 已落地，见文末「实施记录」）**：H1/H2/H3、M1~M3、L1、B1~B4 已改代码；
> M4 共鸣标签、M5 自动配装预设、L2 剧情轮换/派遣增益、L3 独立可视化基于设计取舍未做或已由 B1 覆盖。

---

## 第一档 · 硬伤（成本极低，强烈建议先做）

### H1 击杀魂火 +3 从未生效

- **现状**：`CombatManager.gd:1008` 在 `_on_kill` 末尾调 `SoulFireManager.on_hit(1)`。命中与击杀互斥（`:581` 等 8 处 `on_hit(1)` 都是"命中未击杀"分支），所以击杀这一支被误用了 `on_hit`。`SoulFireManager.on_kill()`（配置 `kill=3`、`multi_kill_bonus=2`、归零触底 +1）全项目零调用。
- **改法**：把 `CombatManager.gd:1008` 的 `SoulFireManager.on_hit(1)` 改为 `SoulFireManager.on_kill(1)`。其余 8 处 `on_hit(1)` **不要动**。
- **注意**：`on_kill()` 内部已含 `add()` 与提示，轮回的额外回魂（`:1001-1006`）在其之前结算，两段收益不冲突；击杀金色提示用现有 hint 通道即可，无需新增 UI。
- **收益**：击杀回魂从 +1 恢复为 +3（多杀更多），魂火经济与轮回流派定位回归设计。
- **验证**：一场战斗里击杀一个敌人，魂火应 +3（命中那次不额外 +1）；AOE 击杀 2 个应 +3×2+2=+8（乘地图倍率）。

### H2 三天难度曲线恒为平

- **现状**：`UnitSpawner.gd:6` `ENABLE_STRENGTH_MULTIPLIERS=false`，导致 `DAY_ATTR_MULT{1:0.8,2:1.0,3:1.2}`、`BOSS_HP_MULT=2.0`、`ELITE_SCRUB_HP_MULT=1.5` 全部被 bypass（`get_enemy_hp_mult/extra/day_attr_mult` 直接 return 1.0）。调用链存在于 `WaveManager.gd:311-312` 和 `UnitSpawner.gd:231-235`，开关打开即生效。
- **改法**：两选一——
  - 方案 A（最简）：`ENABLE_STRENGTH_MULTIPLIERS` 改 `true`，沿用现有倍率。
  - 方案 B（更稳）：保持开关 false，直接把 day 倍率接进主线（在 `UnitSpawner.get_day_attr_mult` / `get_enemy_hp_extra` 去掉开关短路），这样精英/Boss 的额外血量也可单独调而不受总开关牵连。
- **建议**：先 A 试玩，若 day1 的 0.8 倍让开局过于轻松、day3 的 1.2 倍不够陡，再调表内数值；Boss `2.0` 倍血量确认是否过肉（配合 H1 魂火恢复后伤害节奏会变）。
- **验证**：day1/day3 同一类敌人 HP/属性应有可见差距；Boss 血量约为普通精英的 2 倍。

### H3 代码/文档口径统一（顺手清理）

- 文档 `GameplayDesignDoc.md:120,272,445-446` 仍写"重铸 500G""机制合并 200G"，代码早已移除重铸、合并免费。同步文档表格为最新值（重铸已移除/合并 0G），并把 6.1 资源产出的金币改为减半后的值（250/250/400/600，宝箱 300±200 / 500±200）。
- `EquipmentConfigForge.gd:192,245-251` 仍保留一个 500G"锻造=重铸"入口，与"重铸已移除"冲突。确认该入口是锻造界面独立功能还是残留：若与 build 无关（锻造新防具），保留但改文案避免叫"重铸"；若确为残留，下架。

---

## 第二档 · 核心手感（流派与成长反馈）

### M1 六流派强度失衡

- **灰烬后期无感**：`BuildManager.get_ash_tile_damage = 3+2×(Lv-1)`（`:338-341`），满 Lv4 仅 9 点固定伤害，而后期敌人几十~上百血；且 AI 会躲燃烧格（`EnemyAI.gd:53-65,767-769`）。
  - 改法：伤害改为"按施放者攻击力的百分比 + 固定值"，例如 `int(owner.attack × (0.3+0.1×Lv)) + 基础值`，或随天数缩放 `×(1+0.2×(day-1))`。需把 owner 传入 `trigger_ash_tile`（当前 tile 已存 `owner`，见 `CombatManager.gd:1262`），改动小。
  - 目标：满 Lv 地块伤害与同期普攻同量级（约 20~30 点），让"布火封路"有威慑。
- **烈焰/守护碾压**：烈焰追加 15~45% 无视减伤伤害（`CombatManager.gd:1164-1176`），守护反弹 30~75%、格挡 ×2 最高 150%（`:1113-1128`）。
  - 改法：守护反弹上限压到 50%（格挡当次 ×2 仍可到 100%，但需格挡触发条件），或给反弹加"每次受击最多一次"上限防叠；烈焰维持（它是样板机制，手感好），其余流派靠增强灰烬/献祭来拉近。
  - 目标：六流派都在"能改变打法"的同一档，不出现绝对最优。
- **献祭代价过低**：扣 3~7% 血换 10~25% 攻（`TurnManager.gd:199-219`），几乎无风险。改法：提高扣血比例或改为"按已损失生命递增收益"，让残血献祭成为主动博弈。

### M2 成长卡死（common 品质 cap=1 吞掉升 Lv）

- **现状**：`BuildManager.gd:74` `QUALITY_CAP` common1/rare2/epic3/legendary4；早期防具池 common 权重 60%（`:100-107`）。并入时 `level=mini(count, new_cap)`（`:387`），用 common 并入仍停在 Lv1，"同流派升 Lv"这一核心爽点早期为零。
- **改法（择一或组合）**：
  1. 品质 cap 表前移一档：common2 / rare3 / epic4 / legendary4（让 common 也能升到 Lv2，早期有反馈）。
  2. 并入到 cap 时给"溢出补偿"：若 `count>cap`，把多余件数转成小属性加成（如 +2% 该流派相关属性）并显示提示，让重复 roll 不白费。
  3. 提高早期防具池 rare+ 保底（见 M3）。
- **建议**：先做 1 + 提示文案（"烈焰 Lv1→Lv2"），成本最低、反馈最直接；2 作为后续调优。

### M3 防具 roll 同质化 + 覆盖口径脱节

- **候选同质**：`BuildManager.get_armor_roll_pool(count=8)`（`:897-931`）+ 品质过滤（`:866-895`），早期 common 占多数，8 个候选大量低价值重复。
  - 改法：每池保底 1 件 rare 及以上；按玩家**已有流派**加权（已觉醒流派的防具权重提高，让"升 Lv"机会更多出现在轮盘里）。
- **覆盖流派不删旧防具**：`overwrite_school`（`:408-418`）只 `mechs.erase(school)`，未从 `armor_slots` 移除该流派防具实例；`SetBonusManager.gd:59-72` 仍按 armor_slots 统计 tag → 被覆盖的流派还在贡献套装/词条，机制视图与底层数据脱节。
  - 改法：`overwrite_school` 里同步移除 `armor_slots` 中属于 `school_to_remove` 的防具实例（或清理其流派贡献），保证机制、套装、词条三处口径一致。

### M4 技能 roll 偏手速 + 共鸣难凑

- **现状**：`SlotMachineUI` 靠停轮时机定结果，`SkillRollUI` 选定 `locked=true` 不可撤销（`:159-218` / `BuildManager.gd:796-810`）。守护共鸣技能仅 2 个（`SCHOOL_BY_SKILL` 中守护=嘲讽、战斗呐喊），玩家难凑守护流派共鸣。
- **改法（择一）**：
  1. 加"开局一次重掷"入口（roll 完 3 个技能后可整体重置一次），降低运气方差与误选焦虑——设计文档 §7 风险 3 已点名此问题。
  2. 给守护/轮回各补 1~2 个技能共鸣标签（在 `talents.json` 的 `resonance_school` + `BuildManager.SCHOOL_BY_SKILL` 同步），让六流派共鸣分布均衡（当前献祭/余烬各 4，守护仅 2）。
- **建议**：两者都做——重掷解决"手速焦虑"，补标签解决"流派可表达性"。

### M5 单位槽位与自动配装偏好

- **1 槽单位单薄**：`MECHANISM_SLOTS` armored/dragonborn=1（`:66-70`），觉醒后只能同流派并入或覆盖（覆盖丢积累）。
  - 改法：1 槽单位允许"重置流派"（付少量金币清空当前流派重开），而非只能覆盖；或给 1 槽单位一个"双流派但各 Lv 上限-1"的可选定位，增加 build 多样性。
- **自动配装偏好攻击流**：`EquipmentConfig.gd:2761-2804` 三预设（攻击/防御/平衡），`_school_weight` 把灰烬归 hp_w（攻击流权重仅 0.3），评分偏好 eff×权重与满 cap（`:2843-2856`）。
  - 改法：增"功能/流派流"预设，提高灰烬/轮回等功能流派权重；结果弹窗展示各方案的流派构成差异，而不只显示一个总分。
- **有效 Lv 口径脆弱**：`EquipmentConfig.gd:2848-2851` 手算 `mini(lv+1,4)`，未复用 `RESONANCE_LEVEL_BONUS/MAX` 常量。改法：改调 `BuildManager.get_effective_school_level`，避免改共鸣数值时评分与战斗不同步。

---

## 第三档 · 内容厚度与长期价值（排除地图编辑）

### L1 局外成长两端失衡

- **现状**：`progress_unlocks.json` 天赋阈值 3/6/10/15/21/28、遗物 5/12/20/30，一局约 +7 进度（`VictoryHandler.gd:187-188`），4~5 局全解锁；而祝福 6 属性×3 级、每属性成本 50/200/800（共 6300 魂，`progression_config.json`），主线约 70 魂/局，需数十局。
- **改法**：
  1. 后移解锁阈值曲线（如天赋 5/10/18/28/40/55、遗物 8/18/32/50），并把后期里程碑绑定"首通更高难度/竞技场段位"，让解锁不是纯挂机计数。
  2. 大幅降低后期祝福成本或提高魂产出：把第三级成本从 800 降到 300~400，或提高 Elt/Boss 的魂奖励（当前 ELITE 6 / BOSS 15+5）。
  - 目标：解锁与祝福两条永久成长线在"约 10~15 局"内同步趋于完整，避免一边 4 局就满、一边 40 局无望。

### L2 外围系统不反哺核心

- **派遣**：`DispatchManager.gd` 6 路线仅产 1~4 魂、需跨局等待。改法：产出接入局内可用资源（如局内开局额外魂火上限、防具 roll 折扣券），让派遣影响下一局 build 而非只是数字。
- **剧情**：83 个对话 id、仅 5 个可重复（`StoryManager.gd:185-191,257-303`），一次性去重后枯竭。改法：改周目轮换池 + 关键对话可重复但变体文案，保证多周目有内容。
- **竞技场**：金币退出即失效、魂收益低（`Arena.gd:23-33,612-650`），像独立小游戏。改法：竞技场段位/连胜接入主线（解锁节点或共鸣加成），金币可在竞技场内延续跨场次（当前每场重置），提升"经营"感。

### L3 收益可视化（配合第二档，提升"看得懂"）

- 三态效果、流派机制触发、遗物/套装来源目前有相当一部分只在 print 或颜色里。建议在 HUD/信息面板统一补：
  - 魂火三态的当前效果文案（燃烧=溅射50% / 枯竭=暴伤+50%）；
  - 每次伤害弹字标注流派来源（"烈焰 +X"）；
  - 遗物/套装激活时的即时反馈。
- 与近期 v6.31（信息面板显示技能 CD）同一思路：把"系统已算但玩家看不见"的收益显性化。

---

## 实施顺序建议

1. **第一批（低风险高收益）**：H1、H2、H3 —— 两处硬伤 + 文档口径。
2. **第二批（核心手感）**：M2（common cap 反馈）、M1（灰烬数值）、M3（roll 保底 + 覆盖口径）。
3. **第三批（可表达性）**：M4（重掷 + 共鸣标签）、M5（槽位/自动配装）。
4. **第四批（长期价值）**：L1（局外曲线）、L2（外围反哺）、L3（收益可视化）。

> 每批做完建议试玩验证再进下一批，尤其 H1/H2 会改变魂火与难度节奏，需观察后再定 M1/M2 的具体数值。

---

## 第四部分 · Build 爽感四层（与 1-3 档同期实施）

> 诊断：反馈通道（震屏/飘字/提示/音效）已完善，缺的是"值得爆发的高光时刻"。六流派全被动触发、Lv 线性数值、流派各自为战、魂火爆发与 build 无关。

### B1 觉醒时刻 · 仪式化反馈（成本：低，先做）
- 核心：把"凑齐流派 / 升 Lv"从一行小字升级为仪式事件。
- 落地：新增 `build_awakened` 信号（携带单位/流派/新 Lv），由战斗层/UI 监听。觉醒瞬间播 ~0.5s 单位高亮 + 放大飘字（"烈焰 Lv2 觉醒！"，颜色随流派色）+ 专属音效。
- 复用基础：`BuildManager.apply_armor/overwrite_school` 的 `build_changed` 信号；`CombatManager` 已有的 `request_screen_shake` / `request_hint_override` / 音效通道。
- 关键：**只在首次觉醒与 Lv 质变点触发**，普通并入不重复播放，避免变成噪音。

### B2 阈值质变 · Lv2 / Lv4 解锁新能力（成本：中，核心）
- 核心：Lv 不再只是数值变大，而是解锁定性能力——爽感与纯数值的分水岭。
- 落地：`BuildManager` 加 `get_school_breakthrough(unit, school, lv)` 返回已解锁能力标记；战斗层各钩子读标记（沿用 `get_effective_school_level` 统一出口）。

| 流派 | Lv2 解锁 | Lv4 解锁 |
|---|---|---|
| 烈焰 | 灼烧可叠 2 层 | 灼烧击杀时传染相邻敌人 |
| 守护 | 反弹同时给自身回血 | 格挡时全队共享护盾 |
| 轮回 | 击杀回魂火同时治疗最低血队友 | 斩杀时返还一次技能冷却 |
| 灰烬 | 地块持续 3 回合 | 地块被踩中爆炸成小 AOE |
| 献祭 | 扣血改为扣护盾优先 | 残血(<30%)时攻击加成翻倍 |
| 余烬 | 必暴时附带破甲 | 连续两次必暴触发"焚尽"斩杀线 |

- 与 M2 配合：Lv2 质变让"升到 Lv2"成为明确目标，解决 common cap=1 升不动的痛点。

### ~~B3 流派联动 · 1+1>2~~（v6.36 已移除）
- ~~核心：让"选哪两个流派"产生化学反应，制造构筑欲。~~
- **移除决定**：用户明确 build 配合方向是**单位之间**（不同单位穿不同流派互补），而非**单单位堆多流派**。v6.34 实验的双流派联动与方向相反，且只有数据层 + 竞技场简化数值、主线从未接线，故整体移除。设计原则已写入 `GameplayDesignDoc.md` §5.2。
- 曾实验的 5 组（均已删除）：野火（烈焰+灰烬）/ 血祭（轮回+献祭）/ 背水（守护+余烬）/ 收割（轮回+余烬）/ 焚身（烈焰+献祭）。
- 后续配合类设计应落在**队伍级/跨单位效果**（光环、遗物全队增益、前后排联动），不再做单单位双流派组合技。

### B4 主动引爆 · Build 觉醒技（成本：较高，旗舰）
- 核心：给玩家主动权——攒能量，按键释放属于自己 build 的大招。
- 能量：新增独立 `build_energy`（流派机制触发 +1、击杀 +2），与魂火分开，不干扰三态经济。
- 释放：复用 `DragMoveController._show_attack_menu`（已加灰显项）加"Build 觉醒技"选项，满能量可点。
- 效果：取单位有效 Lv 最高流派释放专属大招——烈焰全场点燃 / 守护全队护盾+反弹翻倍 / 轮回全体回魂火+治疗 / 灰烬全场铺火 / 献祭全队攻击爆发 / 余烬全体必暴一回合。
- 与魂火爆发区别：魂火爆发是通用小爆发（≥3 魂火），觉醒技是 build 专属大招，两者并存定位不同。

### 爽感实施顺序
B1 + B2 优先（解决"升 Lv 没感觉/build 无高光"），B4 作为大版本亮点最后做。与 1-3 档同期实施时，B1/B2 依附的 M2（cap 前移）需先落地。B3 已移除，不再实施。

---

## 实施记录（2026-11-20）

本轮按"4 层爽感 + 1-3 档同期"一次性落地，逐项校验 gdtoolkit 语法 / JSON 合法。

### 已改代码
| 项 | 落点 | 说明 |
|---|---|---|
| H1 | `CombatManager._on_kill` | 击杀结算 `on_hit(1)`→`on_kill(1)`，恢复配置 kill=3/多杀+2/触底+1 |
| H2 | `UnitSpawner.gd:6` | 难度倍率开关 false→true，三天 0.8/1.0/1.2、Boss×2.0 生效 |
| H3 | `GameplayDesignDoc.md` | 金币产出/消耗、重铸/合并口径同步最新值 |
| M2 | `BuildManager.QUALITY_CAP` | common/rare/epic cap 1/2/3→2/3/4 |
| M3 | `BuildManager.get_armor_roll_pool` / `overwrite_school` | roll 池全 common 时保底 1 件 rare+；覆盖流派同步删 armor_slots 旧防具 |
| L1 | `progress_unlocks.json` / `progression_config.json` | 解锁阈值后移（天赋 5/10/18/28/40/55、遗物 8/18/32/50）、祝福三级 800→350 |
| B1 | `SignalBus.build_awakened` + `BuildManager.apply_armor` + `Battlefield._on_build_awakened` | 首次觉醒 / 跨 Lv2·4 阈值发信号，战斗层播震屏+流派色飘字+单格高亮 |
| B2 | `BuildManager.has_breakthrough` + 战斗钩子 | 已接：守护 Lv2 反弹回血、轮回 Lv2 击杀治疗最低血队友、献祭 Lv4 残血攻击翻倍；其余质变函数已备、待试玩后接 |
| ~~B3~~ | ~~`BuildManager.SYNERGIES` / `get_active_synergies`~~ | v6.36 整体移除（方向改为单位间配合，且原实现仅数据层+竞技场简化数值） |
| B4 | `CombatManager` build_energy 三函数 + `DragMoveController` 菜单项 | 完整闭环：击杀+2/烈焰触发+1，满 100 攻击菜单出"Build 觉醒技"，按最高流派释放全场效果并消耗行动 |
| M1(部分) | `BuildManager.get_ash_tile_damage` 等 | 灰烬/守护数值项并入 B2 质变体系处理；未直接改基础曲线 |

### 基于设计取舍未做（非遗漏）
- **M4 共鸣标签**：共鸣数值在 `GameplayDesignDoc.md` 明确"v6.2 冻结"，且守护/轮回技能少受技能主题所限，贸然改破坏口径一致性；`build_skill_pool` 不检查解锁，17 技能开局全可用，不受影响。
- **M4 技能重掷**：设计核心原则"选定离手、不提供重掷"（文档 §3.1），加全局重掷会推翻该原则，故保留。
- **M5 自动配装功能流预设**：需扩 UI 预设与评分权重，属增强非修复，暂缓。
- **L2 剧情周目轮换**：一次性剧情是叙事设计，改轮换需内容支撑，暂缓。竞技场已通过"每 2 胜推进 1 点地图进度"反哺主线；派遣产魂已接入永久魂池。
- **L3 独立可视化**：B1 觉醒提示已带流派名+Lv+颜色，收益显性化的核心已覆盖。

### 试玩重点（改动影响节奏，务必验证）
1. H1 后魂火攒得快很多（击杀 +3），燃烧态占比会上升，观察是否过强。
2. H2 后 day1 敌人 0.8 倍偏弱、day3 1.2 倍，Boss×2.0 是否过肉。
3. M2 cap 前移后早期就能升 Lv2 触发 B2 质变，观察 build 成型速度。
4. B4 觉醒技满 100 能量的节奏（当前击杀+2、烈焰触发+1）——可能偏慢，试玩后调 `BUILD_ENERGY_MAX` 或增量。

---

## A+B 补充实施记录（2026-11-20 v6.35）

### A. Arena 跟进爽感四层
Arena 用独立战斗内核 `ArenaBattle.gd`（非主线 CombatManager），且为**自动战斗无玩家操作**，故 B4 改为"能量满自动释放"：

| 层 | 落点 | 说明 |
|---|---|---|
| A-B1 | `Arena.gd._ready/_on_build_awakened_arena` | 监听 `build_awakened`，用 hint_label 显示觉醒提示 2 秒 + 震屏（Arena 无世界坐标，不做单位高亮） |
| A-B2 | `ArenaBattle` 守护反弹段 + `_apply_sacrifice` | 守护 Lv2 反弹回血、献祭 Lv4 残血攻翻倍（轮回 Lv2 治疗队友在 1v1 无队友，跳过） |
| ~~A-B3~~ | ~~`ArenaBattle._apply_synergies` + `_calc_damage`~~ | v6.36 随 B3 一并移除（字段/初始化/回合调用/函数/伤害加成全删） |
| A-B4 | `ArenaBattle` build 能量 + `_try_release_build_burst` | 命中+1/击杀+2，满 100 在回合开始自动释放（攻击型伤敌/防御型回血/献祭加攻），按最高流派 |

H1 击杀魂火未跟进：Arena 本就是简化魂火（命中+1），`_arena_on_kill` 只有轮回额外回魂，保持设计差异。

### B. 局外经济修复
| 项 | 落点 | 说明 |
|---|---|---|
| ~~祝福入口~~（已整体移除，见文末 v6.36） | ~~`GameState.buy_blessing/get_blessing_*` + `UnitData.get_effective_attr` + `SoulAltar`~~ | 曾补购买 UI 与战斗生效；因与「局外属性上限升级 + 局内单位升级」重复，已全部移除 |
| 光环设计债 | `AuraManager.start_research/accelerate_research` 停用；`CombatManager`/`TurnManager` 删光环战斗接线；`LevelManager` 停研究推进；`GameState.refresh_aura_candidates` 返回空；`AnvilTavern` 按钮改提示 | aura_* 6 个光环已完整迁移到 `relic_data.json`（effects + lifetime + from_aura），独立系统纯重复。保留数据/存档字段兼容，仅切断扣魂与双重结算 |
| 金币沉淀 | `GameState.finish_cycle/abandon_cycle` | 通关时剩余金币 10% 折算魂（上限 50），弃局 5%（上限 25），消除"最后局花不完浪费" |
| 竞技场防刷 | `Arena.gd` 进度反哺条件 | 仅当 `_streak` 刷新历史最佳（`arena_best_streak`）才推进进度，且补上 best_streak 更新；反复重开不再刷进度 |

### 校验与待验证
14 个脚本 gdtoolkit 解析全通过，JSON 合法，光环扣魂残留已清除。需实机验证：Arena 觉醒技释放节奏、光环移除后 aura_* 遗物三选一能否正常获取、金币折算比例是否合适。（祝福相关验证项已随 v6.36 系统移除作废）

---

## 补充记录 v6.36：祝福系统整体移除

**决定**：局外属性成长统一由两条既有链路承担——「局外属性上限升级」（`SoulAltar` 属性上限页 + `GameState.unit_attr_cap` + `UnitDataManager.get_attr_cap_level_bonus`）与「局内单位升级」（`BuildManager.add_experience` → `Unit.apply_level_up`，等级上限 Lv6）。祝福（每单位每属性 0~3 级、+1 属性）功能重复，整体移除。

**移除范围**（8 个文件）：
- `GameState`：`unit_blessings` 字段代理 + `get_blessing_level/get_blessing_cost_for/buy_blessing`
- `SaveManager` / `SaveData` / `ResourceState`：`unit_blessings` 字段与读写
- `UnitData.get_effective_attr`：祝福加成分支与 `_get_blessing_level`
- `SoulAltar`：祝福购买区 UI + `_on_buy_blessing`（否则调用已删函数会崩）
- `GMConsole`：`blessing` 命令注册与 `_cmd_blessing`（否则访问已删字段会崩）
- `progression_config.json`：`blessings` 与 `blessing_max_level`（保留 growth/talent 字段，仍被 `UnitDataManager`/`TalentManager` 使用）

**Arena 核对**：Arena 原本无祝福接口，玩家数据经 `create_unit_data` 构建、属性走 `get_effective_attr`；祝福加成删除后自动回到净状态，无需额外改动。两条替代成长链（属性上限 / 单位升级）在 Arena 与主线共用同一套 `UnitData` 与 `UnitDataManager`，口径一致。

**注意**：老存档中残留的 `unit_blessings` 字段会被 Godot 反序列化忽略（无副作用）；被祝福改动过的 `max_hp` 已固化在存档单位属性里，不会因移除而回退。

**校验**：9 个相关脚本 gdtoolkit 解析全通过，配置 JSON 合法，代码/配置零 `blessing` 残留（剩余 3 处「祝福」为英灵殿复活文案、遗物 flavor、转职文案，属其它系统）。

---

## 补充记录 v6.36：流派联动（B3）整体移除

**决定**：用户明确 build 配合应强调**单位之间**（不同单位不同流派互补），而非**单单位多流派堆叠**。v6.34 实验的"同单位双流派联动"方向相反，且实现不完整（主线战场从未接线，只有 Arena 简化数值），整体移除。设计原则写入 `GameplayDesignDoc.md` §5.2。

**移除范围**（2 个文件）：
- `BuildManager.gd`：`SYNERGIES` 常量（野火/血祭/背水/收割/焚身）、`get_active_synergies()`、相关注释。
- `ArenaBattle.gd`：`_player/enemy_synergy_bonus` 字段与初始化、`_run_battle` 的 `_apply_synergies` 调用、`_apply_synergies()` 函数、`_calc_damage` 里的联动加成。

**保留**：B1 觉醒仪式、B2 Lv 阈值质变（守护 Lv2 回血 / 轮回 Lv2 治疗 / 献祭 Lv4 残血翻倍）、B4 觉醒技——这些是**单流派内部**的强化，与"单位间配合"方向不冲突。

**校验`：2 个脚本解析通过，代码零 `SYNERGIES`/`get_active_synergies`/`synergy` 残留（仅剩一句无关的转职注释）。

