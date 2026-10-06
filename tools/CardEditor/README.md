# Mobius Card Editor

面向当前 mobius 项目的轻量卡牌美术制作工具。

## 启动

直接双击 tools\CardEditor\run_card_editor.bat。

需要 Python、Tk 和 Pillow；依赖见 requirements.txt。

## 主要功能

- 正式卡牌外观优先读取 `content/cards/card_catalog_49.json`，严格按 01~49 永久编号排序。
- 49 张奖励卡的基础费用已按最新版策划截图写入，CardEditor 直接显示正式费用。
- 图集按行列切割，可配置外边距、格子间隔、透明裁边。
- 支持把近黑色背景转透明，适合 AI 输出的黑底图集。
- 图标可统一到 256×256 透明画布，保证不同技能图标视觉尺寸稳定。
- 卡框和图标分别保存到：
  - assets/textures/cards/frames/
  - assets/textures/cards/icons/
- 卡牌编辑器支持卡框选择、图标选择、拖动、缩放、旋转、文字布局。
- 卡名、编号、分类和描述来自正式 49 卡总表；正式 CardDef 使用对应的 `card_number / visual_key` 身份接口。
- 正式 PNG 文件名固定为 `card_01.png` ~ `card_49.png`，避免中文名、排序变化导致错位。
- 单张 PNG 导出。
- 批量生成游戏卡牌外观：
  - assets/textures/cards/generated/*.png
  - assets/textures/cards/generated/visual_manifest.json
- 视觉配置保存到 tools/CardEditor/workspace/card_visuals.json。
- 当前 UI 不提供新建卡牌、技能/规则编辑或 CardDef 写回；CardEditor 暂时作为纯外观编辑工具使用。

## 当前边界

Card Editor v1 已经负责把散的卡框、图标和正式卡牌总表文本合成为正式游戏 PNG。

Godot 正式手牌已经使用 `presentation/cards/battle_card_view.tscn` 动态组合卡框、图标和文字。`CardVisuals` 读取 frames 与 icons；generated 下整卡 PNG 保留用于预览，不直接用于战斗手牌。修改卡牌规则和数值请使用 Godot Inspector / Mobius 工作台，见 [编辑指南](../../docs/editor_and_api_guide.md)。

## 自测

在 mobius 项目根目录运行：

python tools\CardEditor\self_test.py
