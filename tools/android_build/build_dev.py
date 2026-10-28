"""Build a dev APK; optional Google Maven fallback affects only this build."""
import argparse
import contextlib
import datetime
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

from environment import ROOT, SCRATCH, CMAKE_VERSION, prerequisites
from maven_bridge import Bridge


@contextlib.contextmanager
def fallback(env):
    server = Bridge(SCRATCH / 'maven-cache')
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        original_home = Path(env.get('GRADLE_USER_HOME', Path.home() / '.gradle')).expanduser().resolve()
        original_home.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='gradle-', dir=SCRATCH) as tmp:
            home = Path(tmp)
            # Share downloaded artifacts/distributions, isolate init scripts and daemons.
            for name in ('caches', 'wrapper', 'jdks', 'native'):
                source = original_home / name
                source.mkdir(exist_ok=True)
                (home / name).symlink_to(source, target_is_directory=True)
            original_properties = original_home / 'gradle.properties'
            config = original_properties.read_text() if original_properties.is_file() else ''
            (home / 'gradle.properties').write_text(config + '\norg.gradle.daemon=false\n')
            init = home / 'init.d'
            init.mkdir()
            if (original_home / 'init.d').is_dir():
                for existing in (original_home / 'init.d').iterdir():
                    (init / existing.name).symlink_to(existing)
            bridge_init = init / 'pdd-google-maven.gradle'
            while bridge_init.exists() or bridge_init.is_symlink():
                bridge_init = bridge_init.with_name(bridge_init.stem + '-pdd.gradle')
            shutil.copyfile(Path(__file__).with_name('google_maven.init.gradle'), bridge_init)
            child = dict(env, GRADLE_USER_HOME=str(home),
                         PDD_GOOGLE_MAVEN_URL=f'http://127.0.0.1:{server.server_port}/')
            print('Google Maven через локальный мост: curl, HTTPS, части по 64 КиБ.', flush=True)
            yield child
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-fallback', action='store_true')
    parser.add_argument('--arm64', action='store_true', help='Меньше APK для современного ARM64-телефона')
    args = parser.parse_args()
    sdk = prerequisites()
    if not (sdk / 'cmake' / CMAKE_VERSION / 'bin/cmake').is_file():
        raise RuntimeError('Нет CMake 3.22.1. Сначала ./scripts/setup_android.sh; см. docs/build/android.md.')
    command = ['flutter', 'build', 'apk', '--flavor', 'ru', '--release', '-Pdev',
               '--dart-define=COUNTRY=ru', '--dart-define=GAME_DEBUG=true',
               '--build-number=' + str(int(datetime.datetime.now(datetime.timezone.utc).timestamp()))]
    if args.arm64:
        command += ['--target-platform', 'android-arm64']
    commit = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, text=True).strip()
    command += ['--dart-define=GIT_COMMIT=' + commit]
    if os.environ.get('DEVICE_REGION'):
        command += ['--dart-define=DEVICE_REGION=' + os.environ['DEVICE_REGION']]
    secret = ROOT / 'secrets/install_notify_secret.txt'
    if secret.is_file():
        command += ['--dart-define=INSTALL_NOTIFY_SECRET=' + secret.read_text().strip()]
    firebase = ROOT / 'secrets/firebase/ru.defines.json'
    if firebase.is_file():
        command += ['--dart-define-from-file=' + str(firebase)]
    env = dict(os.environ, ANDROID_HOME=str(sdk))
    if (ROOT / 'android/godot/assets/project.binary').is_file() or shutil.which('godot'):
        # The Git label describes these sources, never an older cached Godot export.
        print('Пересобираем Godot из текущих исходников перед сборкой APK.', flush=True)
        exported = subprocess.run(['bash', str(ROOT / 'scripts/godot_android_assets.sh')], cwd=ROOT, env=env)
        if exported.returncode:
            return exported.returncode
    else:
        print('Godot ещё не экспортирован: игра недоступна. Для игры: ./scripts/godot_android_assets.sh', flush=True)
    with fallback(env) if args.download_fallback else contextlib.nullcontext(env) as child:
        result = subprocess.run(command, cwd=ROOT, env=child)
    if result.returncode and not args.download_fallback:
        print('При тайм-аутах Google Maven повторите с --download-fallback; см. docs/build/android.md.', file=sys.stderr)
    return result.returncode


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'Ошибка: {exc}', file=sys.stderr)
        sys.exit(1)
