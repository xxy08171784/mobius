# Mobius 当前目录结构

更新：2026-10-06。正式根目录：`D:\GameProjects\GAMEGAM\mobius`。

| 目录 | 职责 |
|---|---|
| app/ | main 启动与 RunFlow 页面编排 |
| autoload/ | App、ContentDB、SaveService、SettingsService、AudioService |
| core/ | 命令/事件、RNG、存档编解码/迁移、内容校验、音频配置类型 |
| gameplay/battle/ | 战斗状态、Session、工厂、命令、回合门面 |
| gameplay/battle/systems/ | 敌人执行、状态 tick、延迟效果、胜负判断 |
| gameplay/cards/ | 卡牌定义/实例、牌区与组合；rules 下为注册表和分组规则 |
| gameplay/board/ | 网格、目标、寻路、位移/推拉 |
| gameplay/effects/ | 原子效果、触发、状态、遗物 |
| gameplay/enemies/ | 敌人、行为序列、行动、意图 |
| gameplay/run/ | Run/Profile、地图/章节、节点事务、遭遇、检查点、奖励/商店/事件 |
| gameplay/units/ | 单位、角色定义与属性 |
| content/ | Catalog 与可编辑 .tres；pools 同时容纳怪物池/卡池 |
| presentation/ | 战斗、地图、卡牌、通用弹窗、页面场景 |
| assets/ | 美术资源 |
| localization/ | CSV 与导入翻译 |
| addons/mobius_workbench/ | 编辑器工作台，导出排除 |
| tests/、tools/、docs/ | 测试、制作/验证工具、文档，导出排除 |
| docs/legacy/ | 旧 C# 工程文本备份 |
| .github/workflows/ | 自动检查定义 |
| .validation/ | 本地日志、截图、隔离用户数据，Git 忽略 |
| builds/windows/ | Windows exe/pck，Git 忽略 |

根目录 control.tscn、node_2d.tscn 和 temp/ 保留旧实验/参考素材，已从正式导出排除，不是游戏入口。`.godot/` 不提交；源资源旁 `.uid` 和 `.import` 设置应随源码保留。

依赖方向：应用/表现 → Session → 纯规则 + State/Def。规则层不依赖 SceneTree，Resource 定义只读，可变数据使用 State。

详见 [编辑与接口指南](editor_and_api_guide.md)、[当前状态](current_status.md)。
