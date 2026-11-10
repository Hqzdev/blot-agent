#!/usr/bin/env python3
"""Validate bilingual app catalogs and test language selection without a simulator."""
import json
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r'%(?:(\d+)\$)?[-+0 #]*\d*(?:\.\d+)?(ll|l)?([@difu])')

def placeholders(text):
    return sorted((length or '', kind) for _, length, kind in TOKEN.findall(text))

for path in sorted((ROOT / 'apps/shared/Resources').glob('*.xcstrings')):
    catalog = json.loads(path.read_text())
    assert catalog['sourceLanguage'] == 'en', path
    for key, entry in catalog['strings'].items():
        localizations = entry['localizations']
        assert set(localizations) == {'en', 'ru'}, (path, key)
        english = localizations['en']['stringUnit']['value']
        russian = localizations['ru']['stringUnit']['value']
        assert english and russian, (path, key)
        assert placeholders(english) == placeholders(russian), (path, key, 'format arguments differ')
    print(f'{path.name}: {len(catalog["strings"])} bilingual entries validated')

with tempfile.TemporaryDirectory(prefix='blot-localization-') as temporary:
    directory = Path(temporary)
    bundle = directory / 'LocalizationCheck.app' / 'Contents'
    (bundle / 'MacOS').mkdir(parents=True)
    (bundle / 'Resources').mkdir()
    (bundle / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'verify', 'CFBundleIdentifier': 'dev.blot.localization.check',
        'CFBundlePackageType': 'APPL', 'CFBundleDevelopmentRegion': 'en',
    }))
    subprocess.run(['xcrun', 'xcstringstool', 'compile',
                    str(ROOT / 'apps/shared/Resources/Localizable.xcstrings'),
                    '--output-directory', str(bundle / 'Resources')], check=True, stdout=subprocess.DEVNULL)
    executable = bundle / 'MacOS' / 'verify'
    sources = [ROOT / 'apps/shared/WorkspaceV3' / name for name in ['WorkspaceLanguage.swift', 'WorkspaceCopyTemplate.swift', 'WorkspaceCopy.swift']]
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(directory / 'cache'),
                    *map(str, sources), str(ROOT / 'scripts/verify-localization.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
