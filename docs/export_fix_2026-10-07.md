# 0.3.1 试玩包棋盘与动画加载修复

现象：点击地图战斗节点后，部署界面只剩一块巨大的红色菱形，无法选择进场格。

## 原因

地板与单位动画原先使用 `DirAccess` 扫描以 `.png` 结尾的文件。开发目录有原始 PNG，导出 PCK 中对应路径却是 `.png.import` 和转换后的纹理资源，因此两个扫描器在导出包里都返回空列表。

地板扫描失败后，旧回退路径把 `TileMapLayer.tile_set` 设为 null。`map_to_local` 无法计算格子坐标，每个格子都返回同一点；所有高亮叠在一起、再按单格边界放大，形成截图中的红色大菱形。单位动画存在同一类加载缺陷。

## 修复

- `presentation/battle/iso_board_theme.gd` 与 `unit_sprite_frames.gd` 改用 `ResourceLoader.list_directory`，读取导入前的逻辑文件名，排序后通过资源系统加载。编辑器和导出包使用同一实现。
- 地块缺失时仍保留正确的等轴测 TileSet 几何，显示带格线的纯色棋盘；64 个坐标、布局和点击拾取不依赖贴图是否存在。
- 原始图片、存档格式、卡牌和敌人数值保持兼容；不需要删除存档。
- 发布版本升级为 0.3.1，单独生成新试玩包，不覆盖旧包。

## 回归检查

此前开发目录中的 UI 集成测试能通过，但 EXE 只检查到了主菜单启动，遗漏了导出后才出现的资源扫描差异。本轮新增 `tools/verify_export.py`，直接加载正式发布的 PCK，而不是读取工作区游戏资源。

检查覆盖：16 张地板、玩家与三章 24 类敌人的左右动画、地图进入部署、64 格纹理与点击坐标、选择绿格进入战斗、敌方行动后返回玩家回合、返回主菜单后继续同一回合；截图用于核对实际棋盘和单位显示。

旧 0.3.0 包在新增检查中稳定出现 26 项失败（地板、玩家、24 类敌人动画），作为复现证据。

修复后已验证：52 组规则测试全部通过，内容与 UI 检查无失败；正式 PCK 在 OpenGL 与 D3D12 下通过以上完整流程，部署和战斗截图正常；Windows EXE 在两种模式下均正常启动。修复包包含本说明和原 0.3.0 数值表。

```powershell
$godotExe = 'D:\MyData\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
python tools/verify_project.py --godot $godotExe --capture --resolution 1366x768
python tools/verify_export.py --godot $godotExe --package builds/playtest/Mobius-0.3.1-Fix-Windows-x64/Mobius.pck --capture
python tools/verify_export.py --godot $godotExe --package builds/playtest/Mobius-0.3.1-Fix-Windows-x64/Mobius.pck --capture --renderer forward_plus
```

Windows 正式模板禁止通过命令行切换脚本/场景；包内流程检查使用同版本引擎运行 PCK，测试驱动放在包外且不分发。EXE 另外检查 D3D12 与 OpenGL 启动。测试数据均隔离在 `.validation`，不读取或修改玩家真实存档。
