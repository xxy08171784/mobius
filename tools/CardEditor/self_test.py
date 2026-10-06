from __future__ import annotations

import json
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

import core


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_scan_cards() -> None:
    cards = core.scan_card_defs()
    check(len(cards) >= 12, "expected at least 12 CardDef resources")
    strike = next((c for c in cards if c.card_id == "card.warrior.strike"), None)
    check(strike is not None, "strike card must be readable")
    check(strike.display_name == "斩击", "Chinese display name must survive parsing")
    check(strike.base_cost == 1, "strike cost must be 1")


def test_formal_catalog() -> None:
    cards = core.load_formal_card_catalog()
    expected_names = [
        "套索", "立刻征用", "谨慎", "欧拉欧拉欧拉", "招式领悟", "遣散", "躁动", "信心", "振奋", "恐吓", "勇气迸发", "复制",
        "冲刺斩", "蹬踢后翻", "抓钩", "旋风斩", "飞刀",
        "饮血剑", "妖刀", "击晕", "进攻秘术", "索命刀", "重击", "击退", "肉搏", "苦练", "妙用招式", "重影刀", "英勇打击", "困兽之力", "膝盖一箭", "打了就跑", "砍爆", "刺透", "扎根打击", "攻防一体",
        "堆叠防守", "留一手", "防守秘术", "符甲", "恰当防守", "重影盾", "再生硬壳", "应激格挡", "困兽之甲", "疗伤", "掌控", "扎根防守", "守护之手",
    ]
    expected_costs = [
        1, 1, 0, 2, 2, 2, 1, 1, 0, 1, 0, 2,
        2, 2, 1, 2, 1,
        2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 2, 0, 1,
        0, 1, 1, 0, 1, 1, 2, 1, 2, 1, 1, 0, 1,
    ]
    check(len(cards) == 49, "formal reward catalog must contain exactly 49 cards")
    check(core.validate_formal_card_catalog(cards) == [], "formal reward catalog must validate")
    check([card.display_name for card in cards] == expected_names, "formal 01~49 name order is frozen and must never drift")
    check(cards[0].card_number == 1 and cards[0].display_name == "套索", "#01 must be 套索")
    check(cards[22].card_number == 23 and cards[22].display_name == "重击", "#23 must be 重击")
    check(cards[-1].card_number == 49 and cards[-1].display_name == "守护之手", "#49 must be 守护之手")
    check(cards[0].visual_key == "card_01", "#01 visual key must be card_01")
    check(cards[-1].visual_key == "card_49", "#49 visual key must be card_49")
    check([card.base_cost for card in cards] == expected_costs, "formal 01~49 costs must match the confirmed design table")
    check(cards[27].play_count_weight == 2, "#28 重影刀 must count as two cards")
    check(cards[39].play_count_weight == 0, "#40 符甲 must not count toward play count")
    check(cards[41].play_count_weight == 2, "#42 重影盾 must count as two cards")


def test_slice_and_compose() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        atlas = Image.new("RGBA", (400, 200), (0, 0, 0, 0))
        draw = ImageDraw.Draw(atlas)
        draw.rectangle((20, 20, 180, 180), fill=(255, 0, 0, 255))
        draw.rectangle((220, 20, 380, 180), fill=(0, 0, 255, 255))
        atlas_path = root / "atlas.png"
        atlas.save(atlas_path)
        tiles = core.slice_atlas(atlas_path, 1, 2, trim=True)
        check(len(tiles) == 2, "atlas must return two cells")
        check(tiles[0].width > 0 and tiles[1].width > 0, "trimmed cells must be non-empty")

        boxes = core.grid_boxes(atlas.size, 1, 2)
        boxes[0][2] -= 20
        manual_tiles = core.crop_boxes(atlas, boxes, trim=False)
        check(manual_tiles[0].width == 180, "manual crop box resize must affect only that slice")
        check(manual_tiles[1].width == 200, "neighbor crop box must stay independent")

        frame = Image.new("RGBA", core.CARD_SIZE, (230, 220, 190, 255))
        frame_path = root / "frame.png"
        frame.save(frame_path)
        icon = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        ImageDraw.Draw(icon).ellipse((8, 8, 120, 120), fill=(220, 40, 40, 255))
        icon_path = root / "icon.png"
        icon.save(icon_path)

        card = core.CardData(
            card_id="card.test",
            display_name="测试牌",
            description="造成 5 点伤害",
            base_cost=1,
            tags=["attack"],
            source_path="test.tres",
        )
        config = core.VisualConfig(
            card_id=card.card_id,
            frame_path=str(frame_path),
            icon_path=str(icon_path),
        )
        result = core.compose_card(card, config)
        check(result.size == core.CARD_SIZE, "composed card size must be stable")
        output = root / "out.png"
        result.save(output)
        check(output.exists() and output.stat().st_size > 0, "PNG export must succeed")

        tall_frame = Image.new("RGBA", (200, 500), (255, 255, 255, 255))
        fitted = core._fit_layer_contain(tall_frame, core.CARD_SIZE)
        check(
            abs((fitted.width / fitted.height) - (200 / 500)) < 0.01,
            "frame fitting must preserve original aspect ratio",
        )

        padded_frame = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(padded_frame).rectangle((50, 8, 205, 248), fill=(255, 255, 255, 255))
        normalized_frame = core.normalize_frame_asset(padded_frame)
        check(
            normalized_frame.size == core.CARD_SIZE,
            "frame assets must normalize to the full card size",
        )
        check(
            normalized_frame.getchannel("A").getbbox() == (0, 0, core.CARD_SIZE[0], core.CARD_SIZE[1]),
            "normalized frame content must fill the card bounds",
        )

        frame_a = Image.new("RGBA", (200, 300), (0, 0, 0, 0))
        frame_b = Image.new("RGBA", (200, 300), (0, 0, 0, 0))
        da = ImageDraw.Draw(frame_a)
        db = ImageDraw.Draw(frame_b)
        da.rectangle((80, 100, 100, 120), fill=(255, 0, 0, 255))
        db.rectangle((80, 100, 100, 120), fill=(255, 0, 0, 255))
        da.rectangle((0, 0, 8, 8), fill=(0, 255, 0, 255))
        db.rectangle((191, 291, 199, 299), fill=(0, 0, 255, 255))
        mapped_a = core.map_frame_cell_to_card(frame_a)
        mapped_b = core.map_frame_cell_to_card(frame_b)

        def red_center(image: Image.Image) -> tuple[float, float]:
            points: list[tuple[int, int]] = []
            pixels = image.load()
            for y in range(image.height):
                for x in range(image.width):
                    r, g, b, a = pixels[x, y]
                    if a > 160 and r > 180 and g < 80 and b < 80:
                        points.append((x, y))
            check(bool(points), "red alignment marker must survive resize")
            return (
                sum(x for x, _ in points) / len(points),
                sum(y for _, y in points) / len(points),
            )

        ca = red_center(mapped_a)
        cb = red_center(mapped_b)
        check(
            abs(ca[0] - cb[0]) < 0.01 and abs(ca[1] - cb[1]) < 0.01,
            "frame batch mapping must keep identical source coordinates pixel-aligned",
        )

        grid = Image.new("RGBA", (630, 420), (0, 0, 0, 0))
        gd = ImageDraw.Draw(grid)
        x_starts = [35, 230, 425]
        y_starts = [28, 222]
        for y in y_starts:
            for x in x_starts:
                gd.rectangle((x, y, x + 168, y + 166), fill=(255, 255, 255, 255))
        detected = core.detect_uniform_grid_boxes(grid, 2, 3, padding=0)
        check(len(detected) == 6, "auto grid detector must return rows*cols boxes")
        widths = [round(box[2] - box[0], 4) for box in detected]
        heights = [round(box[3] - box[1], 4) for box in detected]
        check(len(set(widths)) == 1, "auto-aligned frame boxes must share one width")
        check(len(set(heights)) == 1, "auto-aligned frame boxes must share one height")


def test_visual_json() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "visual.json"
        payload = {"card.test": core.VisualConfig(card_id="card.test", icon_x=12)}
        data = {"cards": {k: vars(v) for k, v in payload.items()}}
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        loaded = json.loads(path.read_text(encoding="utf-8"))
        check(loaded["cards"]["card.test"]["icon_x"] == 12, "visual JSON must round-trip")


def main() -> int:
    core.ensure_dirs()
    test_scan_cards()
    test_formal_catalog()
    test_slice_and_compose()
    test_visual_json()
    print("CardEditor self-test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
