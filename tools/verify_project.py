"""Run imports, references, rules, and real UI integration in isolated user data."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--resolution", default="1366x768")
    args = parser.parse_args()
    executable = shutil.which(args.godot) or args.godot
    output = ROOT / ".validation"
    output.mkdir(exist_ok=True)
    env = os.environ.copy()
    # Tests never read/write the player's real user:// files.
    env["APPDATA"] = str(output / "userdata")
    env["XDG_DATA_HOME"] = str(output / "userdata")
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    commands = [
        ("import", ["--headless", "--editor", "--import", "--quit"]),
        ("content", ["--headless", "-s", "res://tools/validate_content.gd"]),
        ("rules", ["--headless", "-s", "res://tests/run_all.gd"]),
        ("ui", ["--headless", "res://tests/ui_smoke.tscn"]),
        ("controls", ["--headless", "res://tests/battle_controls_smoke.tscn"]),
        ("audio", ["--headless", "res://tests/audio_smoke.tscn"]),
        ("startup", ["--headless", "--quit-after", "4"]),
    ]
    if args.capture:
        commands.append(("visual", ["--rendering-method", "gl_compatibility", "--resolution", args.resolution,
                                    "res://tests/ui_smoke.tscn", "--", "--capture"]))
        commands.append(("controls-visual", ["--rendering-method", "gl_compatibility", "--resolution", args.resolution,
                                             "res://tests/battle_controls_smoke.tscn", "--", "--capture"]))
    for name, options in commands:
        try:
            result = subprocess.run([executable, "--audio-driver", "Dummy", "--path", str(ROOT), *options], cwd=ROOT,
                                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    encoding="utf-8", errors="replace", timeout=300)
        except (OSError, subprocess.TimeoutExpired) as exc:
            print(f"[FAIL] {name}: {exc}")
            return 1
        (output / f"{name}.log").write_text(result.stdout, encoding="utf-8")
        # This Windows sandbox cannot enumerate system certificates; it is unrelated to offline game logic.
        inspected = result.stdout.replace("ERROR: Failed to read the root certificate store.", "")
        failed = result.returncode != 0 or re.search(r"SCRIPT ERROR:|Parse Error:|ERROR:|\[FAIL\]", inspected)
        print(f"[{'FAIL' if failed else 'PASS'}] {name}")
        if failed:
            print(result.stdout)
            return 1
        for line in result.stdout.splitlines():
            if line.startswith(("Rule tests:", "Content validation:", "UI smoke:", "Battle controls:", "Audio smoke:")):
                print(line)
    print(f"Logs: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
