#!/usr/bin/env python3
"""Format only v3 sources using the same cached formatter version as Gradle Spotless."""
from pathlib import Path
import os
import subprocess
root = Path(__file__).resolve().parents[1]
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
artifacts = ['google-java-format', 'guava', 'failureaccess', 'checker-qual', 'error_prone_annotations', 'j2objc-annotations']
jars = [str(p) for p in cache.rglob('*.jar') if any('/' + name + '/' in str(p) for name in artifacts)]
if not any('google-java-format-1.28.0.jar' in p for p in jars):
    raise SystemExit('Run the Gradle Spotless dependency resolution first (formatter 1.28.0).')
jdk = Path(os.environ.get('JAVA_HOME', root / '.build/tools/jdk-25.0.4.1+1/Contents/Home'))
files = sorted((root / 'backend/core/src/main/java/dev/blot/core/v3').glob('*.java'))
files.append(root / 'backend/api/src/test/java/dev/blot/api/V3ContractTest.java')
exports = [f'--add-exports=jdk.compiler/com.sun.tools.javac.{name}=ALL-UNNAMED' for name in ['api', 'file', 'parser', 'tree', 'util', 'code']]
subprocess.run([str(jdk / 'bin/java'), *exports, '-cp', os.pathsep.join(jars), 'com.google.googlejavaformat.java.Main', '--replace', *map(str, files)], check=True)
print(f'Formatted {len(files)} v3 Java sources')
