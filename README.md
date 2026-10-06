# Mobius

Godot 4.7.2、GDScript 制作的回合制棋盘卡牌 Roguelike。正式入口是 `app/main.tscn`。

当前版本已接通三幕路线、部署、战斗、节点交互、奖励、存档恢复和局外结算，可以在现有框架上持续制作内容。它仍需要美术、音频、翻译、数值平衡和发布前试玩；自动化通过不等于已完成商业发行验收。

## 开始使用

1. 用 Godot 4.7.2 打开本目录的 `project.godot`，等待首次资源导入。
2. 按 **F5** 从主菜单运行；按 **F6** 运行当前场景用于界面或战斗预览。
3. 编辑器右侧 **Mobius 工作台** 提供内容搜索、Inspector 编辑、主要场景入口和内容校验。未显示时在“项目 → 项目设置 → 插件”启用 Mobius Workbench。
4. 正式内容统一登记到 `content/catalog.tres`；仅把资源文件放入文件夹不会自动注册。

默认操作：鼠标选择卡牌/格子，Q 出牌，E 结束回合，Backspace 清除选择，数字 1–9 选手牌，方向键与 Enter 操作棋盘；设置页可修改三个战斗快捷键。手柄基础映射为 X/Y/B 和方向导航，完整手柄体验尚需实机验收。

## 文档入口

- [接口、可视化编辑入口与内容制作指南](docs/editor_and_api_guide.md)：首先阅读。
- [本次整合、当前完成情况与验证](docs/current_status.md)：对应 2026-10-06 的改进结果。
- [存档与整局生命周期](docs/save_and_run_lifecycle.md)：恢复、幂等、迁移和失败处理。
- [目录结构](docs/directory_structure.md)：现在各目录的职责。
- [后续制作与发布清单](docs/roadmap.md)：还需填充与人工验收的部分。
- [战斗规则](docs/combat_rules.md)、[路线规则](docs/route_map_rules.md)：玩法设计参考；具体实现以当前代码和测试为准。

## 检查与导出

在本目录的 PowerShell 中运行，按本机安装位置修改第一行：

```powershell
$godotExe = 'D:\MyData\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
python tools/verify_project.py --godot $godotExe
python tools/verify_project.py --godot $godotExe --capture --resolution 1366x768
```

检查依次执行导入、内容交叉引用、规则测试、实际场景流程测试和正式入口启动。测试存档隔离在 `.validation/userdata`，日志在 `.validation`，不会读写玩家真实存档。截图模式需要图形环境。

安装对应版本的 Windows 导出模板后，可在“项目 → 导出 → Windows Desktop”导出，或：

```powershell
New-Item -ItemType Directory -Force builds/windows
& $godotExe --headless --path . --export-release 'Windows Desktop' builds/windows/Mobius.exe
```

发布时 `Mobius.exe` 与 `Mobius.pck` 必须一起提供。预设排除了测试、工具、文档、编辑器插件、临时图和旧原型场景。CI 配置见 `.github/workflows/godot.yml`；推送后才会在 GitHub 执行。

玩家数据默认位于 Windows 的 `%APPDATA%\Godot\app_userdata\mobius`，与项目文件分开。不要把真实存档提交到 Git。

## 协作约定

- `cxm` 是本次工作分支，已合并朋友的 `xxy` 到 `323d605`。本次未执行远端推送。
- 稳定内容 ID 是存档契约，已发行内容不要随意改名或删除。
- `*Def` Resource 只读；运行数值写进 `*State`，玩法入口使用 Session。
- 修改规则后运行完整检查；修改场景后再做截图和实际交互检查。
- 工作目录和游戏正式名称统一使用 Mobius；GAMEGAM 是上层工作空间名称。
