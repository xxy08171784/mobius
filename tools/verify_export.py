"""Verify real release PCK resources and route/deployment/battle under the matching Godot engine.

Release templates disable scene/script overrides; the external harness uses the matching
editor binary with --main-pack. Game code/assets remain loaded from the release PCK.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--renderer', default='gl_compatibility')
    args = parser.parse_args()
    package = args.package.resolve()
    output = ROOT / '.validation' / f'export-{package.parent.name}-{args.renderer}'
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['APPDATA'] = str(output / 'userdata')
    env['XDG_DATA_HOME'] = env['APPDATA']
    Path(env['APPDATA']).mkdir(exist_ok=True)
    command = [args.godot, '--main-pack', str(package), '-s', str(ROOT / 'tests/export_smoke_runner.gd')]
    command += (['--rendering-method', args.renderer, '--resolution', '1366x768']
                if args.capture else ['--headless'])
    command += ['--', str(ROOT / 'tests/export_smoke.gd'), str(output / 'screenshots')]
    if args.capture:
        command.append('--capture')
    try:
        result = subprocess.run(command, cwd=package.parent, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, encoding='utf-8', errors='replace', timeout=90)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'[FAIL] export: {exc}')
        return 1
    (output / 'smoke.log').write_text(result.stdout, encoding='utf-8')
    inspected = result.stdout.replace('ERROR: Failed to read the root certificate store.', '')
    failed = (result.returncode != 0 or 'Export smoke: 0 failures' not in result.stdout
              or re.search(r'SCRIPT ERROR:|Parse Error:|ERROR:|\[FAIL\]', inspected))
    print(result.stdout if failed else '[PASS] export: textures, sprites, HUD layout, deployment, picking, card drop, next turn, continue')
    print(f'Logs and screenshots: {output}')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
