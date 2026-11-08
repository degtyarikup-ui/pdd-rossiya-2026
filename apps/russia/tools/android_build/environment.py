import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / 'scratch/android-build'
CMAKE_VERSION = '3.22.1'


def properties(path):
    if not path.exists():
        return {}
    return {k.strip(): v.strip().replace('\\:', ':').replace('\\\\', '\\')
            for line in path.read_text().splitlines()
            if '=' in line and not line.lstrip().startswith('#')
            for k, v in [line.split('=', 1)]}


def android_sdk():
    # Match Gradle's actual SDK first; never silently install into a different SDK.
    local = properties(ROOT / 'android/local.properties').get('sdk.dir')
    if local:
        return Path(local).expanduser().resolve()
    for key in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        if os.environ.get(key):
            return Path(os.environ[key]).expanduser().resolve()
    config = subprocess.check_output(['flutter', 'config', '--machine'], text=True)
    sdk = json.loads(config).get('android-sdk')
    if sdk:
        return Path(sdk).expanduser().resolve()
    for candidate in (Path.home() / 'Library/Android/sdk', Path.home() / 'Android/Sdk',
                      Path.home() / '.local/android-env/sdk',
                      Path('/opt/homebrew/share/android-commandlinetools')):
        if (candidate / 'platform-tools').is_dir():
            return candidate
    raise RuntimeError('Android SDK не найден. Установите SDK через Android Studio; задайте ANDROID_HOME.')


def prerequisites():
    for tool in ('flutter', 'java', 'curl'):
        if not shutil.which(tool):
            raise RuntimeError(f'Нет {tool} в PATH; см. docs/build/android.md')
    version = subprocess.check_output(['java', '-version'], stderr=subprocess.STDOUT, text=True)
    match = re.search(r'version "(\d+)', version)
    if not match or int(match[1]) < 17:
        raise RuntimeError('Нужен JDK 17 или новее; рекомендуемый JAVA_HOME — JDK 17.')
    sdk = android_sdk()
    if not sdk.is_dir():
        raise RuntimeError(f'Android SDK не существует: {sdk}. Исправьте sdk.dir в android/local.properties.')
    config = json.loads(subprocess.check_output(['flutter', 'config', '--machine'], text=True))
    configured_sdk = config.get('android-sdk')
    if configured_sdk and Path(configured_sdk).expanduser().resolve() != sdk.resolve():
        raise RuntimeError(f'Flutter настроен на другой SDK: {configured_sdk}; проверяется {sdk}. '
                           f'Выберите один SDK: flutter config --android-sdk="{sdk}"; '
                           'затем повторите setup_android.sh.')
    SCRATCH.mkdir(parents=True, exist_ok=True)
    return sdk


def sdkmanager(sdk):
    candidates = [sdk / 'cmdline-tools/latest/bin/sdkmanager']
    candidates += sorted(sdk.glob('cmdline-tools/*/bin/sdkmanager'), reverse=True)
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    raise RuntimeError('Нет sdkmanager: установите Android SDK Command-line Tools в Android Studio.')


if __name__ == '__main__':
    import sys
    try:
        print(android_sdk())
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f'Ошибка: {exc}', file=sys.stderr)
        sys.exit(1)
