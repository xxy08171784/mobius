"""Create portable game audio from the team's masters without changing the originals.

Usage: python tools/import_audio.py --source <folder> --ffmpeg <ffmpeg.exe>
The manifest records each source hash, conversion and intended cue. Requires FFmpeg.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# key, source relative path, category; names deliberately remain stable in game content.
SOURCES = [
    ('menu', '音乐/Mu--Open.wav', 'music'),
    ('route', '音乐/Mu--Main scene.wav', 'music'),
    ('battle', '音乐/Mu--Fight.wav', 'music'),
    ('victory', '音乐/Mu--Win.wav', 'music'),
    ('defeat', '音乐/Mu--Lose.wav', 'music'),
    ('click', '音效/UI场景/按钮/button1.wav', 'sfx'),
    ('confirm', '音效/UI场景/按钮/UI button.wav', 'sfx'),
    ('map_open', '音效/UI场景/地图/Map Open.wav', 'sfx'),
    ('map_close', '音效/UI场景/地图/Map Close.wav', 'sfx'),
    ('reward', '音效/UI场景/点击奖励/Reward.wav', 'sfx'),
    ('campfire', '音效/UI场景/火堆/【白噪音】夜晚的篝火丨噼里啪啦烧木头的声音（实景系列）.mp3', 'ambience'),
    ('step_grass', '音效/UI场景/地块/Grass_walk.wav', 'sfx'),
    ('step_stone', '音效/UI场景/地块/Stone_walk.wav', 'sfx'),
    ('step_water', '音效/UI场景/地块/Water_walk.wav', 'sfx'),
    ('card_draw', '音效/卡牌/通用/Card_draw.wav', 'sfx'),
    ('card_use', '音效/卡牌/通用/Card_use_fly.wav', 'sfx'),
    ('card_upgrade', '音效/卡牌/通用/Card_level_up.wav', 'sfx'),
    ('shield', '音效/卡牌/通用/Defend(shield up).wav', 'sfx'),
    ('player_hurt', '音效/卡牌/通用/be attacked(player).wav', 'sfx'),
    ('punch', '音效/卡牌/通用/Fist_punch(common attack).wav', 'sfx'),
    ('sword', '音效/卡牌/通用/Sword1.wav', 'sfx'),
    ('sword_heavy', '音效/卡牌/通用/Sword2（heavy）.wav', 'sfx'),
    ('sword_skill', '音效/卡牌/技能/Sword.wav', 'sfx'),
    ('dice', '音效/UI场景/骰子/Dice.mp3', 'reserved'),
    ('water_appear', '音效/UI场景/地块/Water_appear.wav', 'reserved'),
    ('poison_trap', '音效/UI场景/地块/Posion trap.wav', 'reserved'),
]


def run(args: list[str]) -> str:
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return result.stderr.decode('utf-8', errors='replace')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--ffmpeg', required=True)
    args = parser.parse_args()
    scratch = ROOT / '.validation/audio_import'
    scratch.mkdir(parents=True, exist_ok=True)
    output = ROOT / 'assets/audio'
    manifest = []
    # ASCII staging paths also support older Windows FFmpeg builds lacking Unicode argv.
    with tempfile.TemporaryDirectory(dir=scratch) as directory:
        for key, relative, category in SOURCES:
            original = args.source / relative
            staged = Path(directory) / (key + original.suffix)
            shutil.copyfile(original, staged)
            report = run([args.ffmpeg, '-hide_banner', '-i', str(staged), '-af', 'volumedetect', '-f', 'null', '-'])
            mean = float(re.search(r'mean_volume: ([-\d.]+) dB', report)[1])
            peak = float(re.search(r'max_volume: ([-\d.]+) dB', report)[1])
            # Static gain preserves the recording's dynamics; no compressor or truncation.
            gain = round(min(12.0, -24.0 - mean, -6.0 - peak), 2)
            extension = '.mp3' if category in ('music', 'ambience') else '.wav'
            destination = output / category / (key + extension)
            destination.parent.mkdir(parents=True, exist_ok=True)
            encoding = ['-c:a', 'libmp3lame', '-q:a', '2'] if extension == '.mp3' else ['-c:a', 'pcm_s16le']
            run([args.ffmpeg, '-hide_banner', '-y', '-i', str(staged), '-vn', '-map_metadata', '-1',
                 '-af', f'volume={gain}dB', '-ar', '48000', *encoding, str(destination)])
            manifest.append({'key': key, 'source': relative, 'category': category,
                             'source_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
                             'file': destination.relative_to(ROOT).as_posix(),
                             'source_mean_db': mean, 'source_peak_db': peak, 'gain_db': gain,
                             'output_bytes': destination.stat().st_size,
                             'output_sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
            print(f'{key}: {destination.stat().st_size} bytes, gain {gain:+.2f} dB')
    (output / 'sources.json').write_text(json.dumps({'sample_rate': 48000, 'files': manifest},
                                                  ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
