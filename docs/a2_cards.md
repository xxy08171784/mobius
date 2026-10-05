# A2 卡牌模块说明

本文对应 development_split.md 的 Track A / A2。A2 负责“卡是什么、战斗中每张卡是哪一张、卡在哪个牌区、怎么抽/洗/弃/消耗、组合如何顺序预演”。

## 1. CardDef

gameplay/cards/card_def.gd 是只读 Resource 定义。

核心数据：

    card_id
    base_cost
    tags
    effects
    exhaust_on_play
    target_rule
    upgrade_overrides

运行时不直接修改 CardDef。升级通过 upgrade_level 查询覆盖数据，临时费用/标签放 BattleCardState。

target_rule 已收紧为 B1 的 TargetSpec。null 表示无目标；单位/格子/方向目标按 TargetSpec 的 kind 与 resolved 状态校验。

## 2. RunCardState / BattleCardState

RunCardState 表示“一整局拥有的永久卡”：

    run_uid
    card_id
    upgrade_level
    permanent_modifiers

BattleCardState 表示“本场战斗中的实例”：

    battle_uid
    source_run_uid
    card_id
    upgrade_level
    cost_modifier
    temporary_tags
    generated

两张同名卡可以引用同一个 card_id，但 UID 必须不同。

CardSystem 提供：

    create_battle_card(run_card, battle_uid)
    create_generated_card(card_id, battle_uid, upgrade_level)

生成卡没有 source_run_uid，不会因为本场产生一张临时卡就写回永久卡组。

## 3. DeckState

DeckState 保存 battle_uid -> BattleCardState，并维护五个互斥牌区：

    draw
    hand
    discard
    exhaust
    resolving

核心接口：

    add_card(card, zone)
    get_card(uid)
    zone_of(uid)
    move_card(uid, from_zone, to_zone)
    validate_invariants()
    duplicate_deck()

validate_invariants() 保证每个已登记的 battle UID 恰好属于一个牌区。

## 4. CardSystem

规则服务：

    draw_cards(deck, count, rng)
    reshuffle_discard(deck, rng)
    move_hand_to_resolving(deck, uids)
    finish_resolving(deck, uid, exhaust_card)
    discard_from_hand(deck, uid)
    exhaust_from_hand(deck, uid)

抽牌堆空时，只把 discard 洗回 draw；exhaust 永不参与洗回。

洗牌只使用传入 RNG，使用同一 RNG 状态会得到相同顺序。

组合确认时，move_hand_to_resolving() 会先验证整组选牌，再一次性移动，避免只移动一半。

## 5. ComboPlanner

核心接口：

    build_plan(
        state_in,
        deck_in,
        PlayCardsCommand,
        card_defs,
        available_resource,
        rng_in,
        target_validator
    )

还有一层正式 UnitState 资源入口：

    build_plan_for_actor(
        state_in,
        deck_in,
        command,
        card_defs,
        rng_in,
        resource_key = "energy",
        target_validator
    )

它会：

1. 校验 card_uids 和 targets 一一对应。
2. 校验所有 UID 都在 hand，且没有重复。
3. 按 BattleCardState 的临时费用修正计算组合总费用。
4. 费用不足直接拒绝，State / Deck / RNG 零修改。
5. 在独立 Deck 副本中把所有选牌一次性 hand -> resolving，冻结本次组合。
6. 按玩家给的顺序逐张处理。
7. 每张牌执行前重新调用 target_validator，因此前一张牌移动后，后一张牌按新位置重新算射程。
8. 调用 A1 EffectResolver 在工作 State / RNG 上预演效果。
9. 已承诺目标因前一张牌死亡/离场等原因失效时，可由 target_validator 返回 fizzle；卡落空、不换目标、不退费，但仍离开 resolving。
10. 结算完按 CardDef 决定 resolving -> discard 或 exhaust。

成功返回：

    state_out
    deck_out
    rng_out
    events
    steps
    cost_spent
    resource_after
    selected_uids

其中 cost_spent/resource_after 是“本次应一次性扣除多少资源”的规划结果。

build_plan_for_actor 已直接读取 B2 UnitState.resources。真正扣除权威资源仍属于 Phase 3 BattleSession.submit() 的一次性提交步骤，因此预览不会修改 UnitState。

## 6. TargetSpec / B 线接入

PlayCardsCommand.targets 容器仍为 Array，但正式元素使用 TargetSpec（目标为空的卡可继续使用 null）。

- CardDef.target_rule 已使用 TargetSpec；
- ComboPlanner 会先检查目标 kind / resolved，并对 UnitTarget 检查 ANY/ALLY/ENEMY/SELF；
- CellTarget 在有 BoardState 时检查是否在盘内；
- 更具体的射程 / LoS / 技能特殊条件继续通过 target_validator 调用 BoardQuery；
- Move/Push 已走 B1 的 Displacement 统一入口。

A2 不实现射程、LoS、墙和占用规则。

## 7. 当前 DoD 对应测试

- test_card_models.gd
  - 同名卡 UID 不混；
  - RunCard -> BattleCard；
  - 升级费用 + 本场费用修正；
  - 运行时状态不污染 CardDef。
- test_deck_state.gd
  - 一卡只属一区；
  - Deck 深复制独立。
- test_card_system.gd
  - 抽牌区流转；
  - discard 确定性洗回；
  - exhaust 不洗回；
  - 批量进入 resolving 失败时原子回滚。
- test_combo_planner.gd
  - 组合费用只计算一次；
  - 费用不足零副作用；
  - resolving -> discard/exhaust；
  - 位移后下一张牌重新计算射程；
  - 后续目标死亡时落空、不转火、不退费。
- test_ab_integration.gd
  - CardDef TargetSpec 与实际命令目标类型/阵营对接；
  - ComboPlanner 从 UnitState 读取 energy；
  - A1/A2 与 B1/B2 共用工作快照时不污染权威状态。
