# Phase 0 基础设施说明

本文档说明 Phase 0 新增/完善的基础设施文件。它们暂时不负责“具体卡牌、移动、伤害、AI”等玩法，而是先把后续战斗系统需要依赖的 **确定性随机、状态深拷贝/存档编解码、自动测试、确定性回放验证** 搭稳。

## 1. 这批文件整体解决什么问题

Phase 0 主要保证四件事：

1. **随机可重复**：同一个 run seed 能复现同样的路线、遭遇、战斗和奖励随机结果。
2. **随机互不污染**：例如生成路线消耗了随机数，不应该改变之后战斗里的随机结果。
3. **状态可以安全复制和保存**：预览战斗时复制一份状态计算，不能改到正式状态；存档再读档后数据应保持一致。
4. **规则可以自动验证**：以后每加一个战斗规则，都可以用 headless 测试确认没有破坏确定性和存档兼容性。

---

## 2. 核心模块

### `core/rng/rng_streams.gd`

**职责：统一管理一局游戏中的确定性随机数。**

目前拆成四条互相独立的随机流：

| 随机流 | 用途 |
|---|---|
| `route` | 路线/地图节点生成 |
| `encounter` | 遭遇、敌人组合等生成 |
| `battle` | 战斗规则内部的随机行为 |
| `reward` | 战后奖励、掉落等随机 |

主要功能：

- `derive_streams(run_seed)`：从一个本局 seed 出发，用固定的 SplitMix64 派生四条随机流。
- `get_stream(stream_id)`：取得指定随机流。
- `battle_rng()`：战斗层常用的便捷入口。
- `snapshot()`：保存当前 seed 和四条随机流各自的 state。
- `restore()`：恢复到之前保存的随机状态。
- `clone()`：复制一套完全独立的随机流，主要给“战斗预览/模拟”使用。

为什么要分流：

> 如果所有系统共用一个 RNG，那么“多生成一次路线”就可能导致后面的敌人暴击、抽牌或奖励全部变化。分流之后，各模块只推进自己的随机流，互不污染。

预览时必须使用 `clone()` 后的 RNG，不能直接调用正式 `battle_rng()`，否则玩家只是查看一次预览就会偷偷推进正式随机结果。

---

### `core/save/save_codec.gd`

**职责：运行状态与可保存 Dictionary 之间的唯一编解码入口，同时承担规则状态的深拷贝。**

当前已经支持：

- `BattleState -> Dictionary`
- `Dictionary -> BattleState`
- `clone_state()` 深拷贝状态
- `schema_version` 检查与 `SaveMigrator` 接入
- 64 位整数的安全 JSON 保存
- `Vector2i` 编解码
- `StringName` 编解码
- Array / Dictionary 递归编解码
- 包括 `Dictionary[Vector2i, ...]` 这种后续棋盘状态会使用的结构

为什么 `clone_state()` 走“编码 -> 解码”：

这样项目只维护 **一套状态复制规则**。以后给 `BattleState` 加字段时，只要补进 SaveCodec，存档和深拷贝同时得到支持；测试也能立刻发现漏掉的字段。

为什么 64 位整数保存成十进制字符串：

JSON 数字在不同解析路径中可能出现大整数精度问题。像 UID、RNG state、事件序号这类值必须精确，因此编码时保存为字符串，解码时再转回整数。

---

## 3. 测试基础

### `tests/run_all.gd`

**职责：Phase 0 的总测试入口。**

运行方式：

```bash
godot --headless --path . -s res://tests/run_all.gd
```

它会：

1. 扫描 `res://tests/rules/`
2. 找出所有 `test_*.gd`
3. 按文件名排序执行
4. 调用每个测试对象的 `run()`
5. 汇总通过/失败数量
6. 有任意失败时以非 0 状态码退出

这样后续可以直接把它接到 CI，或者本地提交代码前跑一次。

---

### `tests/test_case.gd`

**职责：最小测试基类。**

目前提供：

- `reset()`
- `failures()`
- `assert_true()`
- `assert_equal()`
- `assert_not_equal()`

Phase 0 暂时不引入第三方测试框架，先用这套极轻量工具保证规则层能在无界面的 Godot headless 环境中测试。

---

### `tests/deterministic_replay.gd`

**职责：确定性回放/一致性验证的公共工具。**

目标模型：

```text
run seed + 初始状态 + 命令序列
        ↓
     重放规则
        ↓
最终状态 hash + 事件流 hash + RNG hash
```

主要功能：

- 克隆初始状态，避免污染调用者。
- 根据 run seed 创建独立 `RngStreams`。
- 依次执行传入的命令和 `stepper`。
- 对最终状态、事件流和 RNG 快照生成稳定 SHA-256 hash。

Phase 0 先把公共壳搭好；等 `BattleSession.submit()` 和真正战斗命令接入后，就可以用同一份命令序列重复运行，检查两次结果是否完全一致。

---

## 4. Phase 0 具体测试

### `tests/rules/test_runner_smoke.gd`

**测试测试框架自己能不能跑起来。**

这是最基础的 smoke test。如果连它都失败，说明测试加载、实例化或 runner 本身有问题，而不是业务规则的问题。

---

### `tests/rules/test_rng_streams.gd`

**测试随机流是否满足“可复现 + 隔离 + 可恢复”。**

覆盖：

- 同 seed 生成相同随机结果。
- 推进 `route` 流不会推进 `battle` 流。
- 推进 clone 不会影响正式 RNG。
- `snapshot -> restore` 后状态完全一致，并能从同一位置继续产生随机数。

这组测试是之后“预览不能改变正式战斗结果”的底层保障。

---

### `tests/rules/test_save_codec.gd`

**测试状态编解码和深拷贝是否可靠。**

覆盖：

- `BattleState` 编码后再解码，关键字段保持一致。
- clone 中修改 Array 或数值，不会反向修改原对象。
- 超过 JSON 安全整数范围的 int64 不丢精度。
- `Vector2i` 以及以 `Vector2i` 为 key 的 Dictionary 能正常往返。
- 高于当前支持版本的未来 `schema_version` 会被拒绝读取。

---

### `tests/rules/test_deterministic_replay.gd`

**测试确定性回放工具本身。**

目前 Phase 0 主要确认：

- 同 seed + 同初始状态得到相同 hash。
- 修改状态后，状态 hash 会发生变化。

等真实命令系统接入后，这里会继续扩展为完整的战斗回放一致性测试。

---

## 5. 这些模块之后怎么配合

以后一次“战斗预览”大致会是：

```text
正式 BattleState
    └─ SaveCodec.clone_state()
          ↓
      预览 BattleState

正式 RngStreams
    └─ RngStreams.clone()
          ↓
      预览 RNG

预览状态 + 预览 RNG
    └─ 执行同一套战斗规则
          ↓
      展示预计结果

正式 State / 正式 RNG 完全不动
```

真正执行命令时，再让正式状态和正式 RNG 前进。

存档时则保存：

```text
BattleState -> SaveCodec -> Dictionary/JSON
RngStreams  -> snapshot() -> seed + 各流 state
```

读档后恢复两者，就能继续得到与保存前一致的规则结果。

---

## 6. `.uid` 文件说明

本次这些新 `.gd` 脚本旁边出现的 `.gd.uid` 是 Godot 为脚本资源生成的 UID 文件，不是额外的玩法代码。

它们应当和对应 `.gd` 一起提交 Git，避免不同开发者机器重新生成资源 UID 后产生不必要的引用变化。

---

## 7. Phase 0 的边界

这批代码 **已经负责**：

- RNG 分流和恢复
- 状态 Codec/深拷贝基础
- 自动测试入口
- 确定性回放验证基础

这批代码 **还不负责**：

- 卡牌结算
- 棋盘移动/寻路
- 伤害、护盾、状态效果
- 敌人 AI
- 回合推进
- `BattleSession.submit()` 的真实命令执行

这些玩法模块后续建立在 Phase 0 的基础设施上，不应该反过来把存档、随机或测试逻辑散落进各个玩法脚本。
