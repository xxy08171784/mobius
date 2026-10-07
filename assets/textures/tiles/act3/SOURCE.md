# 第三章地块（原始素材）

来源：`C:\Users\yang\Downloads\3新地块`（5 张 `3地块1..5.png`），2026-10-07 整理入库。
命名：`tile_01.png` .. `tile_05.png`（对应 `3地块1..5`，无重排、像素未改动）。

## 目录内容

| 路径 | 说明 |
|---|---|
| `tile_01..05.png` | 原始素材（500×500，透明底，菱形几何略有差异） |
| `normalized/tile_01..05.png` | **已归一化**，可直接进 TileSet |

## 归一化输出（`normalized/`）

按 `docs/battle_board_art_requirements.md` 的冻结规格生成：

- 画布统一 **340×300**；顶面菱形统一 **300×200**；
  菱形四角 (170,20)/(320,120)/(170,220)/(20,120)。

源图菱形实测 ~405–424 × 266–298（长宽比 1.42–1.53 ≈ 目标 1.5），各向拉伸 25–33%，
**≈ 等比缩小，肉眼无变形**。

重新生成：
`<godot> --headless --path D:/mobius --script res://tools/normalize_tiles.gd -- res://assets/textures/tiles/act3`

## 备注

- 素材带 C2PA 元数据，标明 AI 生成。正式发布前请确认来源合规。
