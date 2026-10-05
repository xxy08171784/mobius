class_name BattleSession
extends RefCounted
## 战斗协调器：唯一规则命令入口。拥有 BattleState 与规则服务。
## 具体算法分置于卡牌/棋盘/效果模块；本类只做校验、编排与提交。


var state: BattleState = null


## 生成一场战斗（战场/单位/牌区/意图），派生战斗 RNG。
func setup(_rng: RngStreams) -> void:
	# TODO: 由 BattleFactory 从 RunState 构造 BattleState。
	state = BattleState.new()


## 唯一命令入口。
## 成功：在工作快照上结算，一次性提交 state_out/rng_out，version+1，返回事件。
## 失败：零副作用，返回错误码与本地化文本键。
func submit(_command: GameCommand) -> CommandResult:
	var result := CommandResult.new()
	if state == null:
		result.error_code = CommandResult.ErrorCode.PHASE
		return result

	# TODO: 按 combat_rules.md §3 的顺序校验（去重/阶段/锁/施法者/类型/费用/目标/组合）。
	# TODO: 校验通过后调用纯函数 resolve() 结算；预览走同一函数。
	result.accepted = false
	result.error_code = CommandResult.ErrorCode.COMMAND_TYPE
	result.state_version = state.version
	return result
