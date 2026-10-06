# 第一章地块（原始素材）

来源：`C:\Users\yang\Desktop\第一章地块`（16 张 `地块1..16.png`），2026-10-06 整理入库。
命名：`tile_01.png` .. `tile_16.png`（对应 `地块1..16`，无重排、**像素未改动**）。

## 目录内容

| 路径 | 说明 |
|---|---|
| `tile_01..16.png` | 原始素材（几何不齐，见下） |
| `normalized/tile_01..16.png` | **已归一化**，可直接进 TileSet（见下） |

## 原始素材：不能直接当 TileSet 用

实测（`tools/measure_tiles.gd`）：画布 287×231 ~ 293×246；菱形宽 287~293；菱形高 **188~214**；锚点漂移。原因是这批 **AI 生成图每张透视不一致**，不是量法问题。

## 归一化输出（`normalized/`）

按 `docs/battle_board_art_requirements.md` 的冻结规格，用 `tools/normalize_tiles.gd` 生成：

- 画布统一 **340×300**；顶面菱形统一 **300×200**；锚点固定（菱形四角 (170,20)/(320,120)/(170,220)/(20,120)）。
- 因源图透视不一，采用**各向异性**缩放到精确 300×200（实测每张拉伸 ≤7%）。
- 已验证 16/16 几何完全一致 → 邻格可咬合。

重新生成：`<godot> --headless --path D:/mobius --script res://tools/normalize_tiles.gd -- res://assets/textures/tiles/act1`

## 备注

- 素材带 C2PA 元数据，标明 AI 生成（gpt-image / OpenAI Media Service，后经 Paint 编辑）。原型自用无碍；正式发布前请确认来源合规。
- 归一化对各向 ≤7% 拉伸，是"存量素材凑规格"的权宜；**新美术按规格出图即可零拉伸**。
