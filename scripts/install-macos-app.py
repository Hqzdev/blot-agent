#!/usr/bin/env python3
"""Install this project's built app atomically, retaining the previous bundle for rollback."""
from datetime import datetime
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.build/xcode/Build/Products/Debug/Ori.app'
DESTINATION = Path('/Applications/Ori.app')
LEGACY_DESTINATION = DESTINATION.with_name('Blot.app')


def bundle_id(path):
    with (path / 'Contents/Info.plist').open('rb') as stream:
        return plistlib.load(stream)['CFBundleIdentifier']


def main():
    if not SOURCE.is_dir() or SOURCE.is_symlink():
        raise ValueError('Build Ori before installation')
    identifier = bundle_id(SOURCE)
    if DESTINATION.is_symlink() or (DESTINATION.exists() and bundle_id(DESTINATION) != identifier):
        raise ValueError('The destination is not this Ori application')
    previous = DESTINATION
    if (not DESTINATION.exists()
            and not LEGACY_DESTINATION.is_symlink()
            and (LEGACY_DESTINATION / 'Contents/Info.plist').is_file()
            and bundle_id(LEGACY_DESTINATION) == identifier):
        previous = LEGACY_DESTINATION
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(SOURCE)], check=True)
    backup_directory = ROOT / '.build/app-install-backups'
    backup_directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    backup = backup_directory / ('Ori-' + stamp + '.app')
    stage = DESTINATION.parent / ('.Ori-update-' + uuid.uuid4().hex + '.app')
    moved_previous = False
    try:
        subprocess.run(['/usr/bin/ditto', str(SOURCE), str(stage)], check=True)
        if previous.exists():
            previous.rename(backup)
            moved_previous = True
        try:
            stage.rename(DESTINATION)
        except OSError:
            if moved_previous:
                backup.rename(previous)
            raise
        os.utime(DESTINATION, None)
    finally:
        # This uniquely named staging directory was created above and has never been launched.
        if stage.is_dir() and not stage.is_symlink():
            shutil.rmtree(stage)
    print('Installed: ' + str(DESTINATION))
    if moved_previous:
        print('Previous app retained: ' + str(backup))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Installation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
