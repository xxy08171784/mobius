"""Apply a reviewed encounter tuning table to existing Godot resources.

Run from the project root. Runtime reads .tres; this tool is only for intentional
bulk tuning. Unknown actions are rejected, and art/IDs/behavior sequences survive.
"""
import json
import re
from pathlib import Path

def field(section, key, value):
    text = json.dumps(value, ensure_ascii=False) if isinstance(value, (str, bool)) else str(value)
    pattern = rf'^{re.escape(key)} = .*?$'
    if re.search(pattern, section, re.M):
        return re.sub(pattern, f'{key} = {text}', section, flags=re.M)
    return section.rstrip() + f'\n{key} = {text}\n\n'

def apply(path):
    root = Path.cwd().resolve()
    for row in json.loads(Path(path).read_text(encoding='utf-8')):
        resource = (root / 'content/enemies' / (row['enemy'] + '.tres')).resolve()
        unit = resource.with_name(resource.stem + '_unit.tres')
        assert resource.is_relative_to(root) and unit.is_relative_to(root)
        data = unit.read_text(encoding='utf-8')
        data, count = re.subn(r'("stat.max_hp": )\d+', rf'\g<1>{row["hp"]}', data)
        assert count == 1, unit
        unit.write_text(data, encoding='utf-8')
        sections = re.split(r'(?=\[sub_resource|\[resource\])', resource.read_text(encoding='utf-8'))
        for action, values in row.get('actions', {}).items():
            matched = False
            for i, section in enumerate(sections):
                if re.search(rf'^id = &"[^"\n]*\.{re.escape(action)}"$', section, re.M):
                    for key, value in values.items():
                        section = field(section, key, value)
                    sections[i] = section
                    matched = True
            assert matched, (resource, action)
        resource.write_text(''.join(sections), encoding='utf-8')

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('table')
    apply(parser.parse_args().table)
