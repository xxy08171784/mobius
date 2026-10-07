# 第二章地块（原始素材）

来源：`C:\Users\yang\Downloads\2地块新`（5 张 `2地块新1..5.png`），2026-10-07 整理入库。
命名：`tile_01.png` .. `tile_05.png`（对应 `2地块新1..5`，无重排、像素未改动）。

## 目录内容

| 路径 | 说明 |
|---|---|
| `tile_01..05.png` | 原始素材（500×500，透明底，菱形顶面 + 侧壁的六边形轮廓） |
| `normalized/tile_01..05.png` | **已归一化**，可直接进 TileSet |

## 归一化输出（`normalized/`）

按 `docs/battle_board_art_requirements.md` 的冻结规格生成：画布 340×300、顶面菱形 300×200、
菱形四角 (170,20)/(320,120)/(170,220)/(20,120)。

源图菱形实测 445~449 × 274~288（长宽比 ~1.5），各向拉伸 27~33%、各向差 ≤6%，
≈ 等比缩小，无肉眼变形。

**注意**：这批图是六边形轮廓（顶面+侧壁），老版 `_measure` 逐像素取"最宽行"会被侧壁 1px 抖动
带到平台底部、把厚度当菱形高。`tools/normalize_tiles.gd` 已改为"取首个接近最大值的行（±2px 容差）"
修复（对第一幕平顶菱形无副作用，实测拉伸不变）。

重新生成：
`<godot> --headless --path D:/mobius --script res://tools/normalize_tiles.gd -- res://assets/textures/tiles/act2`

## 备注

- 素材带 C2PA 元数据，标明 AI 生成。正式发布前请确认来源合规。
