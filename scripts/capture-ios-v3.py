#!/usr/bin/env python3
"""Capture the 25 reference routes on an explicitly selected, booted iPhone simulator."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
parser = argparse.ArgumentParser()
parser.add_argument('--udid', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
def sim(*arguments):
    subprocess.run(['xcrun', 'simctl', *arguments], check=True, stdout=subprocess.DEVNULL)
manifest = []
for theme in ['light', 'dark']:
    sim('ui', args.udid, 'appearance', theme)
    for path in sorted((root / 'screens/ios').glob('*.png')):
        sim('launch', '--terminate-running-process', args.udid, 'yaroslavstrelkov.blot-agent.ios', '--workspace-preview', '--screen', path.stem)
        time.sleep(3.0 if path.stem == "01-welcome" else 1.1)
        target = args.output / f'{path.stem}-{theme}.png'
        sim('io', args.udid, 'screenshot', str(target))
        manifest.append(dict(reference=str(path.relative_to(root)), capture=target.name, theme=theme, simulator=args.udid))
        print(f'Captured {path.stem} ({theme})', flush=True)
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
sim('ui', args.udid, 'appearance', 'light')
print(f'Captured {len(manifest)} iPhone frames')
