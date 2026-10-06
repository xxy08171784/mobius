> 历史设计记录（2026-10-05），保留原文供追溯；其中脚手架/占位/旧路径描述不代表当前工程。请以 [current_status.md](current_status.md)、[editor_and_api_guide.md](editor_and_api_guide.md) 为准。

# GAMEGAM 架构评审

日期：2026-10-05。评审对象：`godot_architecture.md`（只读，未修改）。
被评审文档状态：设计方案，尚未创建可运行项目。当前工程为 `D:\mobius`（Godot 4.7，默认脚手架）。

本文给出**风险、缺口、与 Godot 4.7 的出入**及可落地的修改建议。分级：**高**=会直接产生 bug / 返工；**中**=会影响可维护性或边界；**低**=打磨。

## 0. 总体结论

分层方向正确：命令唯一入口、规则层脱离 SceneTree、Def/State/System/Session/View 分离、事件批驱动表现、内容走 Resource。主要问题不是"做错了"，而是**若干决定正确性与确定性的机制被留成了"约定"而没有定义清楚**——实现时最易在此返工：深拷贝语义、纯结算路径、权威输入门禁、ID/去重/触发序的持久化、结算边界。

## 1. 与 Godot 4.7 的事实核对

| 文档处 | 情况 | 建议 |
|---|---|---|
| 开头"4.3+ API" vs `project.godot` 的 `4.7` | 4.7 可用 4.3 之后的新特性 | 锚定 4.7；用 **`@abstract`（4.5+）** 标注 `GameCommand`、`GameEvent`、`EffectDef`、`TargetSpec`、`StatusDef`、`BehaviorDef` 基类，把"只能继承"变成编译器强制 |
| 类型化 GDScript | 4.7 支持**类型化 Dictionary**（4.4+） | `unit_id -> UnitState`、`cell -> unit_id` 用 `Dictionary[int, ...]` / `Dictionary[Vector2i, int]`，提前抓类型错误 |
| §3 Resource 共享加载 | 正确 | 补精确语义：`Array/Dictionary.duplicate(true)` **只深拷嵌套 Array/Dict**，Object/Resource 元素无论 deep 与否都共享引用；只有 `Resource.duplicate(true)` 深拷子资源 |
| 内容稳定 ID | 正确 | 4.4+ 脚本 `.uid` / 资源 `uid://`——把 `.uid` 与 `uid_cache` 一并入库，移动/重命名 `.tres` 时引用不裂 |
| §5.11 存 64 位 seed/state | **正确且关键** | 已核实：Godot 把 Variant 转 JSON 时**所有数值变 float（double）**，>2^53 的 int64 丢精度。存十进制字符串的约定保留 |
| §5.11 "引擎随机会变" | 正确 | 补充：`RandomNumberGenerator` 的 PCG 算法本身也不保证跨大版本不变，故 `game_version` 必须参与"可回放"判定 |
| `TileMapLayer`（4.3+） | 正确 | 可点名坐标转换 API：`local_to_map` / `map_to_local` |
| `AStarGrid2D` | 正确 | 可点名 `set_point_solid` / `set_point_weight_scale` / `jumping_enabled` |
| signal 用法 | 泛泛 | 4.x 语法：`signal x(a)` / `x.connect(callable)` / `x.emit()` |

## 2. 高优先级缺口

### H1. 结算做成"纯函数"，消灭预览/实际双路径
现状：`EffectResolver.resolve(...)` 与 `BattleSimulator.preview(...)` 并存，靠"复用步骤 3–5"保持一致——那是**两处代码必须永远同步**，是这类项目最常见的漂移源。收敛为一个纯函数：

```text
resolve(state_in, plan, rng_in) -> Resolution { state_out, rng_out, events }
```

`submit` 采纳 `state_out / rng_out / events`；`preview` 在 clone 上调用**同一函数**、只读 `events`、丢弃 `state_out`。"预览=实际"从而成为结构保证，而非纪律。

### H2. 深拷贝语义未定义（最大实现陷阱）
`BattleState` 是嵌套 RefCounted 图。建议**让 clone 复用 `SaveCodec`（encode→decode）**，保证"状态的唯一定义"只有一处；任何新字段漏进 codec 会被存档往返测试立刻抓到，避免维护第二套手写 `clone()`。加测试：深改 clone 后递归断言原图不变（含嵌套状态实例）。

### H3. 权威输入门禁必须在规则层
§5.9 的"界面命令门禁"若只存在于 Presenter，一个 UI bug 就能造成重复结算。`BattleSession.submit` 必须在 `phase ∈ {RESOLVING}` / 命令锁为真时**直接拒绝**（返回错误码）；UI 门禁只是视觉。命令锁属于 State、可存档。

### H4. ID 分配器与去重表必须确定且持久化
触发排序的"稳定实例 ID"、§7 的"重复命令"检查，都依赖**单调计数器**（`next_uid`、`next_event_seq`）与**已见命令 ID 集合**。若不随状态保存：读档后触发顺序可能变化（破坏确定性），重放命令可能二次生效。计数器与去重表进 State/SaveCodec；去重表有界并写清淘汰策略。

### H5. RNG 可克隆 + 显式子流派生
"预览不推进正式流"要求 `RngStreams` 是**可独立克隆的对象**并暴露 `snapshot()/restore()`。子流派生别用 `seed(run_seed + i)`，用随 `game_version` 固定的函数（如 `splitmix64(run_seed, stream_id)`）；seed 与 state 都保存。

### H6. 结算边界与"同时死亡"未定义
- 玩家与敌人在同一结算里同时死亡 → 谁胜？【建议默认：玩家死亡优先判 DEFEAT】
- 施法者在组合中途死亡 → 其后续效果是否执行？
- 文档只说过"组合中途战斗结束则停止攻击效果"，未把 **VICTORY/DEFEAT 定义为终态结算边界**（此后只做清理，不再产生伤害/触发）。→ 见 `combat_rules.md` §1、§11。

### H7. 位移落点冲突与视线算法未定义
- 击退/交换/传送落点被墙/单位/出界占据时的规则（阻挡/交换/双方受伤）未定。
- `has_line_of_sight` 未指定算法（Bresenham / supercover、是否被角阻挡）。→ `combat_rules.md` §9、§10。

### H8. Resource 内联子资源陷阱
effect 定义若**内联**进卡牌 `.tres` 的子资源，两卡共用同一内联子资源会"改一张动两张"；运行时**绝不能**改 Def。建议 effect 定义用**独立 `.tres` 外链**，配合 H1 的纯函数保证 Def 只读。

### H9. 预览频率（性能）
若预览挂在 hover/鼠标移动上，每帧深拷+结算是 60 次/秒的无谓开销。**只在选择/目标变化时重算**，复用单一预览缓冲。

### H10. `tests/`、`tools/` 会被打进导出包
它们在 `res://` 下，需在导出预设设 `exclude_filter`。`catalog.tres` 显式引用（文档已有）正确，正是防止导出丢资源。

## 3. 中优先级

- **版本字段消费方**：`BattleState.version` + `CommandResult.state_version` 应真正用于**拒绝过期 UI 预览**，而非只是携带。
- **存档前向兼容**：`save_migrator` 只讲升级；补一条"**旧 build 读到更高 schema 版本必须拒绝**"，不尝试解析。
- **Windows 原子写**：临时→备份→替换在 Windows 上"重命名覆盖已存在文件"有平台差异，需确认 `DirAccess.rename` 行为或先删后改 + 备份兜底。
- **StatSystem 取整/钳制顺序**：`基础→固定→百分比→上下限与取整`顺序固定，但"取整"是 floor/round、钳制在百分比前还是后，必须写死并测试，否则伤害差 1。
- **§6 表是对象级所有权**：升级为**字段级"持久 vs 战斗临时"矩阵**，直接兜住"临时护盾/临时费用/抽牌顺序不写回单局"。
- **App 防上帝对象**：显式列出 App 公开 API（`create_run/load_profile/end_run`），玩法方法一律不许挂 App。
- **本地化格式**：文本键用 Godot CSV→`Translation` 还是 `Translation` 资源要定，并约定"内容 ID ↔ 文本键"命名映射。

## 4. 低优先级 / 打磨

- 项目命名统一：`project.godot` 是 `mobius`，文档是 GAMEGAM——二选一。
- 明确 v1 **不做**的项（借机攻击 AoO、多格单位、战斗内续档、联机），让它们是**决策**而非**遗漏**。
- 补 `TileMapLayer` / `AStarGrid2D` / signal 的具体 API 名（见 §1）。

## 5. 建议补进架构文档的两块

### 5.1 不变量清单（提为独立段）

- 任何时刻每张牌只属于一个牌区（draw/hand/discard/exhaust/resolving）。
- 两张同名卡的 UID 不混淆。
- Def 资源永不被运行时修改。
- 被拒绝的命令零副作用（不扣费、不移牌、不推进正式 RNG、不改权威状态）。
- 预览零副作用。
- 存档往返（encode∘decode）后状态等价。
- 同一奖励 repeated claim、同一 battle result repeated submit 不重复发放。

### 5.2 确定性回放测试

`seed + 命令日志 → 最终状态哈希 + 事件流哈希`。这是唯一能机械验证 H1/H2/H4/H5 的手段。测试框架拍板（GUT 或 gdUnit4），`godot --headless -s` 进 CI。

## 6. 修订清单（按实施优先级）

1. 合并 `EffectResolver` / `BattleSimulator` 为单一纯函数 `resolve()`；预览 = 丢弃输出的 resolve。**(H1)**
2. clone = `SaveCodec` 往返；加"clone 无共享可变引用"测试。**(H2)**
3. 命令锁进 State；`submit` 在 RESOLVING 拒绝。**(H3)**
4. `next_uid` / `next_event_seq` / 已见命令 ID 入状态并持久化。**(H4)**
5. `RngStreams` 可克隆 + `snapshot/restore` + 写死的子流派生函数。**(H5)**
6. VICTORY/DEFEAT 定义为终态结算边界，写清同时死亡。**(H6)**
7. 定义位移落点冲突与 LoS 算法。**(H7)**
8. effect 改外链 `.tres`；导出设 `exclude_filter`。**(H8/H10)**
9. 用 `@abstract`、类型化 Dictionary，锚定 4.7。**(§1)**
10. §6 升级为字段级持久性矩阵；补不变量段与确定性回放测试。**(§5)**

配套：`combat_rules.md`（本次一并起草）承接 H1/H6/H7 与触发序、伤害管线、位移冲突、LoS 的精确合同。
