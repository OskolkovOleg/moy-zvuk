"""Check resources used by name at runtime in the actual release APK."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


root = Path(__file__).resolve().parent.parent
apk = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/app/outputs/flutter-apk/app-release.apk'
sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
if not sdk:
    properties = root / 'android/local.properties'
    if properties.exists():
        match = re.search(r'^sdk\.dir=(.+)$', properties.read_text(), re.MULTILINE)
        if match:
            sdk = match.group(1).strip()
aapt = shutil.which('aapt2')
if not aapt and sdk:
    candidates = list((Path(sdk) / 'build-tools').glob('*/aapt2*'))
    candidates.sort(key=lambda p: tuple(map(int, re.findall(r'\d+', p.parent.name))))
    if candidates:
        aapt = str(candidates[-1])
if not aapt:
    sys.exit('Set ANDROID_SDK_ROOT or put aapt2 on PATH to verify the release APK.')
config = (root / 'lib/playback/service_config.dart').read_text()
icon = re.search(r"androidNotificationIcon:\s*'([^']+)'", config)
if not icon:
    sys.exit('Could not find the notification icon configuration.')
result = subprocess.run([aapt, 'dump', 'resources', str(apk)], capture_output=True, text=True, check=True)
if not re.search(r'\b' + re.escape(icon.group(1)) + r'\s', result.stdout):
    sys.exit(f'Release APK is missing {icon.group(1)}: playback would crash. Check res/raw/keep.xml.')
print(f'Release notification resource verified: {icon.group(1)}')
