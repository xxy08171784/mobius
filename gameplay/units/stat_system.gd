class_name StatSystem
extends RefCounted
## 属性计算（纯函数，顺序写死，测试锁定）。顺序（architecture_review 中优先）：
##   基础 -> 固定加成 -> 百分比加成 -> 上下限钳制 -> 取整
## 百分比为"加成比例"（0.5 = +50%），作用于(基础+固定)之后。
## 取整为**向下取整**（与伤害管线 §6 一致）；钳制在取整之前。
## 修改顺序/取整方式必须同步更新本注释与测试。

## 标准属性键（Def 的 base_stats、修饰来源共用）。
const STAT_MAX_HP := &"stat.max_hp"
const STAT_ATTACK := &"stat.attack"
const STAT_MOVE := &"stat.move"
const STAT_RANGE := &"stat.range"


## 计算单个属性值。lower/upper 用 float 以允许 ±INF（不钳制）。
static func compute(base: float, flat: float, percent: float, lower: float, upper: float) -> int:
	var v := base + flat
	v *= 1.0 + percent
	v = clampf(v, lower, upper)
	return int(floor(v))


## 从一组固定/百分比修饰求和后计算（修饰来源的求和顺序不影响结果，保持确定性）。
static func compute_summed(base: float, flats: Array[float], percents: Array[float], lower: float, upper: float) -> int:
	var flat := 0.0
	for f: float in flats:
		flat += f
	var percent := 0.0
	for p: float in percents:
		percent += p
	return compute(base, flat, percent, lower, upper)
