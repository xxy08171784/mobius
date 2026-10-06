from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from functools import lru_cache
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont


CARD_SIZE = (420, 600)
EDITOR_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_DIR = EDITOR_ROOT / "workspace"
SOURCE_SHEETS_DIR = WORKSPACE_DIR / "source_sheets"
VISUAL_DB_PATH = WORKSPACE_DIR / "card_visuals.json"
FORMAL_CATALOG_PATH = PROJECT_ROOT / "content" / "cards" / "card_catalog_49.json"

CARD_ASSET_ROOT = PROJECT_ROOT / "assets" / "textures" / "cards"
FRAME_DIR = CARD_ASSET_ROOT / "frames"
ICON_DIR = CARD_ASSET_ROOT / "icons"
GENERATED_DIR = CARD_ASSET_ROOT / "generated"
MANIFEST_PATH = GENERATED_DIR / "visual_manifest.json"


@dataclass
class CardData:
    card_id: str
    display_name: str
    description: str
    base_cost: int | None
    tags: list[str]
    source_path: str
    card_number: int = 0
    category: str = ""
    category_label: str = ""
    visual_key: str = ""
    needs_confirmation: bool = False
    play_count_weight: int = 1
    exhaust_on_play: bool = False
    attack_range: int = 1
    requires_los: bool = True
    target_kind: int = 0
    target_team: int = 2
    effects: list[dict] | None = None


@dataclass
class VisualConfig:
    card_id: str
    frame_path: str = ""
    icon_path: str = ""
    frame_x: int = 0
    frame_y: int = 0
    frame_scale: float = 1.0
    icon_x: int = 0
    icon_y: int = -65
    icon_scale: float = 0.72
    icon_rotation: float = 0.0
    title_y: int = 350
    description_y: int = 430
    cost_x: int = 355
    cost_y: int = 55
    title_font_size: int = 30
    description_font_size: int = 22
    cost_font_size: int = 34
    text_width: int = 300


def ensure_dirs() -> None:
    for path in (
        WORKSPACE_DIR,
        SOURCE_SHEETS_DIR,
        FRAME_DIR,
        ICON_DIR,
        GENERATED_DIR,
    ):
        path.mkdir(parents=True, exist_ok=True)


def path_to_project_relative(path: Path | str) -> str:
    p = Path(path).resolve()
    try:
        return p.relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return str(p)


def resolve_saved_path(value: str) -> Path | None:
    if not value:
        return None
    p = Path(value)
    if not p.is_absolute():
        p = PROJECT_ROOT / p
    return p


def slug_from_card_id(card_id: str) -> str:
    slug = card_id.split(".")[-1].strip()
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "_", slug)
    return slug or "card"


def _read_tres_string(text: str, name: str, default: str = "") -> str:
    match = re.search(
        rf'(?m)^\s*{re.escape(name)}\s*=\s*"((?:\\.|[^"])*)"\s*$',
        text,
    )
    if not match:
        return default
    raw = match.group(1)
    try:
        return json.loads(f'"{raw}"')
    except json.JSONDecodeError:
        return raw.replace(r'\"', '"').replace(r"\n", "\n")


def _read_tres_stringname(text: str, name: str, default: str = "") -> str:
    match = re.search(
        rf'(?m)^\s*{re.escape(name)}\s*=\s*&"((?:\\.|[^"])*)"\s*$',
        text,
    )
    return match.group(1) if match else default


def _read_tres_int(text: str, name: str, default: int = 0) -> int:
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*=\s*(-?\d+)\s*$", text)
    return int(match.group(1)) if match else default


def _read_tres_bool(text: str, name: str, default: bool = False) -> bool:
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*=\s*(true|false)\s*$", text)
    if not match:
        return default
    return match.group(1) == "true"


def _read_tags(text: str) -> list[str]:
    match = re.search(r"tags\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", text, re.S)
    if not match:
        return []
    return re.findall(r'&"([^"]+)"', match.group(1))


def _parse_effect_params(block: str) -> dict:
    params: dict = {}
    params_match = re.search(r"params\s*=\s*\{(.*?)\}\s*$", block, re.S | re.M)
    if not params_match:
        return params
    body = params_match.group(1)
    for key, raw_value in re.findall(r'"([^"]+)"\s*:\s*([^,\n]+)', body):
        raw = raw_value.strip()
        if raw.startswith('&"') and raw.endswith('"'):
            params[key] = raw[2:-1]
        elif raw.startswith('"') and raw.endswith('"'):
            try:
                params[key] = json.loads(raw)
            except json.JSONDecodeError:
                params[key] = raw[1:-1]
        elif raw in ("true", "false"):
            params[key] = raw == "true"
        else:
            try:
                params[key] = float(raw) if "." in raw else int(raw)
            except ValueError:
                params[key] = raw
    return params


def _read_effects(text: str) -> list[dict]:
    resource_match = re.search(
        r'(?m)^\s*effects\s*=.*?\(\[(.*?)\]\)\s*$',
        text,
    )
    if not resource_match:
        return []
    ids = re.findall(r'SubResource\("([^"]+)"\)', resource_match.group(1))
    if not ids:
        return []
    blocks: dict[str, str] = {}
    for match in re.finditer(
        r'\[sub_resource\s+type="Resource"\s+id="([^"]+)"\]\s*(.*?)(?=\n\[|\Z)',
        text,
        re.S,
    ):
        blocks[match.group(1)] = match.group(2)
    effects: list[dict] = []
    for resource_id in ids:
        block = blocks.get(resource_id, "")
        type_match = re.search(r'type_key\s*=\s*&"([^"]+)"', block)
        if not type_match:
            continue
        effects.append({
            "type": type_match.group(1),
            "params": _parse_effect_params(block),
        })
    return effects


def scan_card_defs(root: Path | None = None) -> list[CardData]:
    root = root or (PROJECT_ROOT / "content" / "cards")
    if not root.exists():
        return []
    cards: list[CardData] = []
    for path in sorted(root.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        card_id = _read_tres_stringname(text, "card_id")
        if not card_id:
            continue
        cards.append(
            CardData(
                card_id=card_id,
                display_name=_read_tres_string(text, "display_name", card_id),
                description=_read_tres_string(text, "description", ""),
                base_cost=_read_tres_int(text, "base_cost", 0),
                tags=_read_tags(text),
                source_path=path_to_project_relative(path),
                card_number=_read_tres_int(text, "card_number", 0),
                visual_key=_read_tres_stringname(text, "visual_key", ""),
                play_count_weight=_read_tres_int(text, "play_count_weight", 1),
                exhaust_on_play=_read_tres_bool(text, "exhaust_on_play", False),
                attack_range=_read_tres_int(text, "attack_range", 1),
                requires_los=_read_tres_bool(text, "requires_los", True),
                target_kind=_read_tres_int(text, "content_target_kind", 0),
                target_team=_read_tres_int(text, "content_target_team", 2),
                effects=_read_effects(text),
            )
        )
    return cards


def load_formal_card_catalog(path: Path | None = None) -> list[CardData]:
    path = path or FORMAL_CATALOG_PATH
    if not path.exists():
        return []
    raw = json.loads(path.read_text(encoding="utf-8"))
    result: list[CardData] = []
    for item in raw.get("cards", []):
        if not isinstance(item, dict):
            continue
        number = int(item.get("number", 0))
        raw_cost = item.get("base_cost")
        cost = int(raw_cost) if isinstance(raw_cost, int) and not isinstance(raw_cost, bool) else None
        category = str(item.get("category", "")).strip()
        result.append(
            CardData(
                card_id=str(item.get("card_id", "")).strip(),
                display_name=str(item.get("display_name", "")).strip(),
                description=str(item.get("effect_text", "")),
                base_cost=cost,
                tags=[category] if category else [],
                source_path=path_to_project_relative(path),
                card_number=number,
                category=category,
                category_label=str(item.get("category_label", "")).strip(),
                visual_key=str(item.get("visual_key", "")).strip(),
                needs_confirmation=bool(item.get("needs_confirmation", False)),
                play_count_weight=max(0, int(item.get("play_count_weight", 1))),
                exhaust_on_play=bool(item.get("exhaust_on_play", False)),
            )
        )
    result.sort(key=lambda card: (card.card_number if card.card_number > 0 else 9999, card.card_id))
    return result


def validate_formal_card_catalog(cards: list[CardData] | None = None) -> list[str]:
    cards = cards if cards is not None else load_formal_card_catalog()
    errors: list[str] = []
    if len(cards) != 49:
        errors.append(f"正式卡牌数量必须为49，当前为{len(cards)}")
    numbers = [card.card_number for card in cards]
    if numbers != list(range(1, 50)):
        errors.append("正式卡牌编号必须严格覆盖1~49且按序唯一")
    if len({card.card_id for card in cards}) != len(cards):
        errors.append("存在重复 card_id")
    if len({card.display_name for card in cards}) != len(cards):
        errors.append("存在重复卡牌名称")
    if len({card.visual_key for card in cards}) != len(cards):
        errors.append("存在重复 visual_key")
    missing_costs = [card.card_number for card in cards if card.base_cost is None]
    if missing_costs:
        errors.append("正式卡牌基础费用必须全部填写")
    invalid_costs = [
        card.card_number
        for card in cards
        if card.base_cost is not None and card.base_cost < 0
    ]
    if invalid_costs:
        errors.append("正式卡牌基础费用不能为负数")
    category_ranges = (
        (1, 12, "skill"),
        (13, 17, "technique"),
        (18, 36, "attack"),
        (37, 49, "defense"),
    )
    for card in cards:
        expected_id = f"card.reward.{card.card_number:02d}"
        expected_visual = f"card_{card.card_number:02d}"
        if card.card_id != expected_id:
            errors.append(f"#{card.card_number:02d} card_id 应为 {expected_id}")
        if card.visual_key != expected_visual:
            errors.append(f"#{card.card_number:02d} visual_key 应为 {expected_visual}")
        expected_category = next(
            (category for lo, hi, category in category_ranges if lo <= card.card_number <= hi),
            "",
        )
        if card.category != expected_category:
            errors.append(
                f"#{card.card_number:02d} {card.display_name} 分类应为 {expected_category}"
            )
    return errors


def load_editor_cards() -> list[CardData]:
    formal = load_formal_card_catalog()
    if formal:
        errors = validate_formal_card_catalog(formal)
        if errors:
            raise ValueError("；".join(errors))
        return formal
    return scan_card_defs()


def scan_status_ids() -> list[str]:
    result: list[str] = []
    root = PROJECT_ROOT / "content" / "statuses"
    if not root.exists():
        return result
    for path in sorted(root.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        status_id = _read_tres_stringname(text, "status_id")
        if status_id:
            result.append(status_id)
    return result


def _godot_candidates() -> list[Path]:
    candidates: list[Path] = []
    from_env = os.environ.get("GODOT_EXE")
    if from_env:
        candidates.append(Path(from_env))
    candidates.append(Path("D:/MyData/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe"))
    return candidates


def find_godot_exe() -> Path:
    for candidate in _godot_candidates():
        if candidate.exists():
            return candidate
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        return Path(found)
    raise FileNotFoundError("找不到 Godot 可执行文件。可设置 GODOT_EXE 环境变量。")


def save_card_via_godot(payload: dict) -> dict:
    ensure_dirs()
    bridge_script = "res://tools/CardEditor/godot_card_bridge.gd"
    godot = find_godot_exe()
    with tempfile.TemporaryDirectory(dir=WORKSPACE_DIR) as tmp:
        tmp_dir = Path(tmp)
        payload_path = tmp_dir / "request.json"
        result_path = tmp_dir / "result.json"
        data = dict(payload)
        data["result_path"] = str(result_path)
        payload_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        completed = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(PROJECT_ROOT),
                "-s",
                bridge_script,
                "--",
                str(payload_path),
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            timeout=30,
        )
        if not result_path.exists():
            raise RuntimeError(
                "Godot CardDef 保存器没有返回结果。\n"
                + (completed.stdout or "")
                + "\n"
                + (completed.stderr or "")
            )
        result = json.loads(result_path.read_text(encoding="utf-8"))
        if not bool(result.get("ok", False)):
            raise RuntimeError(str(result.get("error", "CardDef 保存失败")))
        return result


def load_visual_db() -> dict[str, VisualConfig]:
    ensure_dirs()
    if not VISUAL_DB_PATH.exists():
        return {}
    try:
        raw = json.loads(VISUAL_DB_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    db_version = int(raw.get("version", 1))
    result: dict[str, VisualConfig] = {}
    allowed = set(VisualConfig.__dataclass_fields__)
    for card_id, values in raw.get("cards", {}).items():
        if not isinstance(values, dict):
            continue
        clean = {k: v for k, v in values.items() if k in allowed}
        clean["card_id"] = card_id
        # v1 的卡框采用“正方形 contain”语义，用户往往需要把 frame_scale
        # 手工调到 1.3~1.5 才能接近卡牌边界。v2 改为默认铺满 CARD_SIZE，
        # 因此旧配置中的卡框位移/缩放需要回到标准基线。
        if db_version < 2 and clean.get("frame_path"):
            clean["frame_x"] = 0
            clean["frame_y"] = 0
            clean["frame_scale"] = 1.0
        try:
            result[card_id] = VisualConfig(**clean)
        except TypeError:
            continue
    return result


def save_visual_db(configs: dict[str, VisualConfig]) -> None:
    ensure_dirs()
    data = {
        "version": 2,
        "project_root": str(PROJECT_ROOT),
        "cards": {
            card_id: asdict(config)
            for card_id, config in sorted(configs.items())
        },
    }
    VISUAL_DB_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def remove_near_black(image: Image.Image, threshold: int = 18) -> Image.Image:
    rgba = image.convert("RGBA")
    data = []
    for r, g, b, a in rgba.getdata():
        data.append((r, g, b, 0 if a > 0 and max(r, g, b) <= threshold else a))
    rgba.putdata(data)
    return rgba


def trim_alpha(image: Image.Image, padding: int = 0) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if not bbox:
        return rgba
    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(rgba.width, right + padding)
    bottom = min(rgba.height, bottom + padding)
    return rgba.crop((left, top, right, bottom))


def normalize_canvas(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgba = image.convert("RGBA")
    if rgba.width <= 0 or rgba.height <= 0:
        return Image.new("RGBA", size, (0, 0, 0, 0))
    scale = min(size[0] / rgba.width, size[1] / rgba.height)
    new_size = (
        max(1, round(rgba.width * scale)),
        max(1, round(rgba.height * scale)),
    )
    resized = rgba.resize(new_size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - new_size[0]) // 2
    y = (size[1] - new_size[1]) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas


def normalize_frame_asset(
    image: Image.Image,
    size: tuple[int, int] = CARD_SIZE,
) -> Image.Image:
    """把卡框的有效透明边界统一铺满标准卡牌画布。

    卡框和技能图标的需求不同：技能图标适合保持比例后放进正方形透明画布，
    而卡框本身就是整张卡牌的外壳。先裁掉透明边，再统一到 CARD_SIZE，
    可以避免“文件都是 256×256，但卡框主体大小仍不一致”的问题。
    """
    trimmed = trim_alpha(image, 0)
    if trimmed.width <= 0 or trimmed.height <= 0:
        return Image.new("RGBA", size, (0, 0, 0, 0))
    resized = trimmed.resize(size, Image.Resampling.LANCZOS)
    # LANCZOS 在极少数素材上会让最外侧一列/行的 alpha 被插值成 0，
    # 再按实际 alpha 边界收一次即可保证卡框主体真正贴到目标边界。
    bbox = resized.getchannel("A").getbbox()
    full_bbox = (0, 0, size[0], size[1])
    if bbox and bbox != full_bbox:
        resized = resized.crop(bbox).resize(size, Image.Resampling.LANCZOS)
    return resized


def map_frame_cell_to_card(
    image: Image.Image,
    size: tuple[int, int] = CARD_SIZE,
) -> Image.Image:
    """把完整的卡框网格单元映射到卡牌尺寸，不按单张内容重新裁边。"""
    rgba = image.convert("RGBA")
    if rgba.width <= 0 or rgba.height <= 0:
        return Image.new("RGBA", size, (0, 0, 0, 0))
    return rgba.resize(size, Image.Resampling.LANCZOS)


def slice_atlas(
    image_path: Path | str,
    rows: int,
    cols: int,
    *,
    padding_x: int = 0,
    padding_y: int = 0,
    gap_x: int = 0,
    gap_y: int = 0,
    trim: bool = True,
    trim_padding: int = 2,
    make_black_transparent: bool = False,
    normalize_to: tuple[int, int] | None = None,
) -> list[Image.Image]:
    if rows <= 0 or cols <= 0:
        raise ValueError("rows and cols must be positive")
    source = Image.open(image_path).convert("RGBA")
    usable_w = source.width - padding_x * 2 - gap_x * (cols - 1)
    usable_h = source.height - padding_y * 2 - gap_y * (rows - 1)
    if usable_w <= 0 or usable_h <= 0:
        raise ValueError("atlas padding/gap exceeds image size")
    cell_w = usable_w / cols
    cell_h = usable_h / rows

    tiles: list[Image.Image] = []
    for row in range(rows):
        for col in range(cols):
            left = round(padding_x + col * (cell_w + gap_x))
            top = round(padding_y + row * (cell_h + gap_y))
            right = round(padding_x + (col + 1) * cell_w + col * gap_x)
            bottom = round(padding_y + (row + 1) * cell_h + row * gap_y)
            tile = source.crop((left, top, right, bottom))
            if make_black_transparent:
                tile = remove_near_black(tile)
            if trim:
                tile = trim_alpha(tile, trim_padding)
            if normalize_to:
                tile = normalize_canvas(tile, normalize_to)
            tiles.append(tile)
    return tiles


def grid_boxes(
    image_size: tuple[int, int],
    rows: int,
    cols: int,
    *,
    padding_x: int = 0,
    padding_y: int = 0,
    gap_x: int = 0,
    gap_y: int = 0,
) -> list[list[float]]:
    if rows <= 0 or cols <= 0:
        raise ValueError("rows and cols must be positive")
    width, height = image_size
    usable_w = width - padding_x * 2 - gap_x * (cols - 1)
    usable_h = height - padding_y * 2 - gap_y * (rows - 1)
    if usable_w <= 0 or usable_h <= 0:
        raise ValueError("atlas padding/gap exceeds image size")
    cell_w = usable_w / cols
    cell_h = usable_h / rows
    boxes: list[list[float]] = []
    for row in range(rows):
        for col in range(cols):
            left = padding_x + col * (cell_w + gap_x)
            top = padding_y + row * (cell_h + gap_y)
            boxes.append([left, top, left + cell_w, top + cell_h])
    return boxes


def _low_projection_runs(values: list[int], threshold: int) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, value in enumerate(values):
        is_low = value <= threshold
        if is_low and start is None:
            start = index
        elif not is_low and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(values)))
    return runs


def _detect_axis_content_bands(
    mask: Image.Image,
    *,
    axis: str,
    count: int,
    low_fraction: float = 0.015,
) -> list[tuple[float, float]]:
    if axis == "x":
        projection = mask.resize((mask.width, 1), Image.Resampling.BOX)
        values = list(projection.getdata())
        axis_len = mask.width
    elif axis == "y":
        projection = mask.resize((1, mask.height), Image.Resampling.BOX)
        values = list(projection.getdata())
        axis_len = mask.height
    else:
        raise ValueError("axis must be 'x' or 'y'")

    threshold = max(0, min(255, round(255 * low_fraction)))
    runs = _low_projection_runs(values, threshold)
    leading = next((run for run in runs if run[0] == 0), None)
    trailing = next((run for run in reversed(runs) if run[1] == axis_len), None)
    interior = [
        run
        for run in runs
        if run[0] > 0 and run[1] < axis_len and (run[1] - run[0]) >= 2
    ]
    if len(interior) < count - 1:
        raise ValueError(f"无法检测到足够的{axis}方向网格间隔")

    separators = sorted(
        sorted(interior, key=lambda run: (run[1] - run[0]), reverse=True)[: count - 1]
    )
    start = float(leading[1] if leading else 0)
    end = float(trailing[0] if trailing else axis_len)
    bands: list[tuple[float, float]] = []
    cursor = start
    for gap_start, gap_end in separators:
        bands.append((cursor, float(gap_start)))
        cursor = float(gap_end)
    bands.append((cursor, end))
    if len(bands) != count or any(right - left < 8 for left, right in bands):
        raise ValueError(f"{axis}方向自动网格结果无效")
    return bands


def detect_uniform_grid_boxes(
    image: Image.Image,
    rows: int,
    cols: int,
    *,
    make_black_transparent: bool = False,
    padding: int = 2,
) -> list[list[float]]:
    """根据图集中的空白分隔带检测网格，并输出同尺寸、同尺度的裁剪框。

    与逐张 alpha trim 不同，这里只用整张图集确定行/列位置；随后所有格子
    使用统一宽高，因此不会因为单张卡框的颜色、抗锯齿或透明边差异而漂移。
    """
    if rows <= 0 or cols <= 0:
        raise ValueError("rows and cols must be positive")
    rgba = image.convert("RGBA")
    if make_black_transparent:
        rgba = remove_near_black(rgba)
    alpha = rgba.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > 8 else 0)
    x_bands = _detect_axis_content_bands(mask, axis="x", count=cols)
    y_bands = _detect_axis_content_bands(mask, axis="y", count=rows)

    common_w = max(right - left for left, right in x_bands) + padding * 2
    common_h = max(bottom - top for top, bottom in y_bands) + padding * 2
    common_w = min(float(rgba.width), common_w)
    common_h = min(float(rgba.height), common_h)

    def centered_interval(center: float, length: float, limit: int) -> tuple[float, float]:
        left = center - length / 2
        right = center + length / 2
        if left < 0:
            right -= left
            left = 0.0
        if right > limit:
            left -= right - limit
            right = float(limit)
        return max(0.0, left), min(float(limit), right)

    x_ranges = [
        centered_interval((left + right) / 2, common_w, rgba.width)
        for left, right in x_bands
    ]
    y_ranges = [
        centered_interval((top + bottom) / 2, common_h, rgba.height)
        for top, bottom in y_bands
    ]
    return [
        [left, top, right, bottom]
        for top, bottom in y_ranges
        for left, right in x_ranges
    ]


def crop_boxes(
    source: Image.Image,
    boxes: list[list[float]],
    *,
    trim: bool = True,
    trim_padding: int = 2,
    make_black_transparent: bool = False,
    normalize_to: tuple[int, int] | None = None,
) -> list[Image.Image]:
    rgba = source.convert("RGBA")
    tiles: list[Image.Image] = []
    for box in boxes:
        left, top, right, bottom = box
        left_i = max(0, min(rgba.width - 1, round(left)))
        top_i = max(0, min(rgba.height - 1, round(top)))
        right_i = max(left_i + 1, min(rgba.width, round(right)))
        bottom_i = max(top_i + 1, min(rgba.height, round(bottom)))
        tile = rgba.crop((left_i, top_i, right_i, bottom_i))
        if make_black_transparent:
            tile = remove_near_black(tile)
        if trim:
            tile = trim_alpha(tile, trim_padding)
        if normalize_to:
            tile = normalize_canvas(tile, normalize_to)
        tiles.append(tile)
    return tiles


def _font_candidates() -> Iterable[Path]:
    windir = Path("C:/Windows/Fonts")
    yield windir / "msyh.ttc"
    yield windir / "msyhbd.ttc"
    yield windir / "simhei.ttf"
    yield windir / "simsun.ttc"


@lru_cache(maxsize=64)
def find_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    paths = list(_font_candidates())
    if bold:
        paths = sorted(paths, key=lambda p: 0 if ("bd" in p.name.lower() or "hei" in p.name.lower()) else 1)
    for path in paths:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


_IMAGE_CACHE: dict[str, tuple[int, Image.Image]] = {}


def load_rgba_cached(path: Path) -> Image.Image:
    key = str(path.resolve())
    try:
        stamp = path.stat().st_mtime_ns
    except OSError:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    cached = _IMAGE_CACHE.get(key)
    if cached is not None and cached[0] == stamp:
        return cached[1]
    with Image.open(path) as source:
        image = source.convert("RGBA").copy()
    _IMAGE_CACHE[key] = (stamp, image)
    return image


def _fit_layer_contain(
    image: Image.Image,
    canvas_size: tuple[int, int],
    *,
    scale_multiplier: float = 1.0,
) -> Image.Image:
    rgba = image.convert("RGBA")
    if rgba.width <= 0 or rgba.height <= 0:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    contain = min(canvas_size[0] / rgba.width, canvas_size[1] / rgba.height)
    scale = max(0.01, contain * scale_multiplier)
    return rgba.resize(
        (
            max(1, round(rgba.width * scale)),
            max(1, round(rgba.height * scale)),
        ),
        Image.Resampling.LANCZOS,
    )


def _fit_frame_fill(
    image: Image.Image,
    canvas_size: tuple[int, int],
    *,
    scale_multiplier: float = 1.0,
) -> Image.Image:
    # 新版卡框素材已经以 CARD_SIZE 保存，必须保留固定坐标系；
    # 旧版非标准尺寸素材才走兼容归一化。
    if image.size == canvas_size:
        frame = image.convert("RGBA")
    else:
        frame = normalize_frame_asset(image, canvas_size)
    scale = max(0.01, scale_multiplier)
    if abs(scale - 1.0) < 0.0001:
        return frame
    return frame.resize(
        (
            max(1, round(canvas_size[0] * scale)),
            max(1, round(canvas_size[1] * scale)),
        ),
        Image.Resampling.LANCZOS,
    )


def _place_icon(base: Image.Image, icon: Image.Image, config: VisualConfig) -> None:
    icon = trim_alpha(icon, 1)
    target = max(8, round(min(CARD_SIZE) * config.icon_scale))
    if icon.width <= 0 or icon.height <= 0:
        return
    scale = min(target / icon.width, target / icon.height)
    resized = icon.resize(
        (max(1, round(icon.width * scale)), max(1, round(icon.height * scale))),
        Image.Resampling.LANCZOS,
    )
    if abs(config.icon_rotation) > 0.01:
        resized = resized.rotate(
            config.icon_rotation,
            resample=Image.Resampling.BICUBIC,
            expand=True,
        )
    x = CARD_SIZE[0] // 2 - resized.width // 2 + config.icon_x
    y = 190 - resized.height // 2 + config.icon_y
    base.alpha_composite(resized, (x, y))


def _text_width(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> int:
    box = draw.textbbox((0, 0), text, font=font)
    return max(0, box[2] - box[0])


def wrap_text_by_width(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.ImageFont,
    max_width: int,
) -> list[str]:
    if not text:
        return []
    result: list[str] = []
    for paragraph in text.splitlines() or [""]:
        line = ""
        for char in paragraph:
            candidate = line + char
            if line and _text_width(draw, candidate, font) > max_width:
                result.append(line)
                line = char
            else:
                line = candidate
        if line:
            result.append(line)
        elif paragraph == "":
            result.append("")
    return result


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    *,
    y: int,
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int, int],
    max_width: int | None = None,
    line_gap: int = 4,
    stroke_width: int = 0,
    stroke_fill: tuple[int, int, int, int] | None = None,
) -> None:
    lines = wrap_text_by_width(draw, text, font, max_width) if max_width else [text]
    current_y = y
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font, stroke_width=stroke_width)
        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        x = (CARD_SIZE[0] - width) // 2
        draw.text(
            (x, current_y),
            line,
            font=font,
            fill=fill,
            stroke_width=stroke_width,
            stroke_fill=stroke_fill,
        )
        current_y += max(1, height) + line_gap


def compose_card(card: CardData, config: VisualConfig) -> Image.Image:
    canvas = Image.new("RGBA", CARD_SIZE, (0, 0, 0, 0))
    frame_path = resolve_saved_path(config.frame_path)
    if frame_path and frame_path.exists():
        frame = _fit_frame_fill(
            load_rgba_cached(frame_path),
            CARD_SIZE,
            scale_multiplier=config.frame_scale,
        )
        frame_x = (CARD_SIZE[0] - frame.width) // 2 + config.frame_x
        frame_y = (CARD_SIZE[1] - frame.height) // 2 + config.frame_y
        canvas.alpha_composite(frame, (frame_x, frame_y))
    else:
        fallback = Image.new("RGBA", CARD_SIZE, (248, 240, 220, 255))
        d = ImageDraw.Draw(fallback)
        d.rounded_rectangle(
            (4, 4, CARD_SIZE[0] - 5, CARD_SIZE[1] - 5),
            radius=26,
            outline=(90, 75, 60, 255),
            width=6,
        )
        canvas.alpha_composite(fallback, (0, 0))

    icon_path = resolve_saved_path(config.icon_path)
    if icon_path and icon_path.exists():
        _place_icon(canvas, load_rgba_cached(icon_path), config)

    draw = ImageDraw.Draw(canvas)
    title_font = find_font(config.title_font_size, bold=True)
    desc_font = find_font(config.description_font_size)
    cost_font = find_font(config.cost_font_size, bold=True)
    text_fill = (50, 38, 30, 255)
    light_fill = (248, 243, 224, 255)

    draw_centered_text(
        draw,
        card.display_name,
        y=config.title_y,
        font=title_font,
        fill=light_fill,
        max_width=config.text_width,
        stroke_width=2,
        stroke_fill=(40, 25, 20, 230),
    )
    draw_centered_text(
        draw,
        card.description,
        y=config.description_y,
        font=desc_font,
        fill=text_fill,
        max_width=config.text_width,
        line_gap=5,
    )
    cost_text = "?" if card.base_cost is None else str(card.base_cost)
    cost_bbox = draw.textbbox((0, 0), cost_text, font=cost_font, stroke_width=2)
    cost_w = cost_bbox[2] - cost_bbox[0]
    draw.text(
        (config.cost_x - cost_w // 2, config.cost_y),
        cost_text,
        font=cost_font,
        fill=light_fill,
        stroke_width=2,
        stroke_fill=(30, 20, 15, 240),
    )
    return canvas


def export_card(card: CardData, config: VisualConfig, output_dir: Path | str) -> Path:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_key = card.visual_key.strip() if card.visual_key else slug_from_card_id(card.card_id)
    output_key = re.sub(r"[^a-zA-Z0-9_-]+", "_", output_key).strip("_") or "card"
    output = output_dir / f"{output_key}.png"
    compose_card(card, config).save(output, "PNG")
    return output


def sync_cards_to_godot(
    cards: list[CardData],
    configs: dict[str, VisualConfig],
) -> tuple[list[Path], list[str]]:
    ensure_dirs()
    exported: list[Path] = []
    skipped: list[str] = []
    manifest: dict[str, str] = {}
    numbered: dict[str, dict] = {}
    for card in cards:
        config = configs.get(card.card_id)
        if config is None or not config.frame_path:
            skipped.append(card.card_id)
            continue
        output = export_card(card, config, GENERATED_DIR)
        exported.append(output)
        res_path = "res://" + output.relative_to(PROJECT_ROOT).as_posix()
        manifest[card.card_id] = res_path
        if card.card_number > 0:
            numbered[f"{card.card_number:02d}"] = {
                "card_id": card.card_id,
                "display_name": card.display_name,
                "visual_key": card.visual_key,
                "path": res_path,
            }

    MANIFEST_PATH.write_text(
        json.dumps(
            {"version": 2, "cards": manifest, "by_number": numbered},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return exported, skipped


def copy_source_sheet(path: Path | str) -> Path:
    ensure_dirs()
    source = Path(path)
    dest = SOURCE_SHEETS_DIR / source.name
    if source.resolve() != dest.resolve():
        shutil.copy2(source, dest)
    return dest

