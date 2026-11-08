"""Check SDK/CMake or install CMake using sdkmanager/the ranged downloader."""
import argparse
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from download import fetch, download
from environment import CMAKE_VERSION, SCRATCH, prerequisites, sdkmanager

REPOSITORY = 'https://dl.google.com/android/repository/'


def install_cmake(sdk):
    manifest = SCRATCH / 'sdk-repository.xml'
    fetch(REPOSITORY + 'repository2-3.xml', manifest)
    host = {'Darwin': 'macosx', 'Linux': 'linux'}.get(platform.system())
    if not host:
        raise RuntimeError('Этот скрипт предназначен для macOS/Linux; Windows — через Android Studio.')
    package = next((p for p in ET.parse(manifest).getroot()
                    if p.tag.split('}')[-1] == 'remotePackage'
                    and p.get('path') == f'cmake;{CMAKE_VERSION}'), None)
    if package is None:
        raise RuntimeError('CMake не найден в официальном каталоге SDK')
    archive = next((a for a in package.findall('./archives/archive')
                    if a.findtext('host-os') == host), None)
    if archive is None:
        raise RuntimeError(f'Нет архива CMake для {host}')
    complete = archive.find('complete')
    checksum = complete.find('checksum')
    if checksum.get('type') != 'sha1':
        raise RuntimeError('Неподдерживаемый тип контрольной суммы SDK')
    filename = complete.findtext('url')
    if '/' in filename or '\\' in filename or not filename.endswith('.zip'):
        raise RuntimeError('Некорректное имя архива SDK')
    archive_path = SCRATCH / filename
    print(f'Загрузка {filename} частями, проверка SHA-1 из каталога SDK…', flush=True)
    download(REPOSITORY + filename, archive_path, complete.findtext('size'), sha1=checksum.text)
    target = sdk / 'cmake' / CMAKE_VERSION
    if target.exists():
        raise RuntimeError(f'Неполная установка {target}: переименуйте/удалите её и повторите.')
    with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
        with zipfile.ZipFile(archive_path) as z:
            for entry in z.infolist():
                relative = Path(entry.filename)
                if relative.is_absolute() or '..' in relative.parts:
                    raise RuntimeError('Некорректный путь внутри архива SDK')
                z.extract(entry, tmp)
                mode = entry.external_attr >> 16
                if mode:
                    (Path(tmp) / relative).chmod(mode & 0o777)
        # Copy only after the archive is fully verified and extracted.
        import shutil
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(tmp, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Только проверка, без установки')
    parser.add_argument('--download-fallback', action='store_true', help='CMake через curl + Range + SHA-1')
    args = parser.parse_args()
    sdk = prerequisites()
    cmake = sdk / 'cmake' / CMAKE_VERSION / 'bin/cmake'
    print(f'Android SDK: {sdk}', flush=True)
    if not cmake.is_file():
        if args.check:
            raise RuntimeError(f'Нет CMake {CMAKE_VERSION}. Выполните ./scripts/setup_android.sh '
                               '(при тайм-аутах добавьте --download-fallback).')
        if args.download_fallback:
            install_cmake(sdk)
        else:
            try:
                subprocess.run([sdkmanager(sdk), f'--sdk_root={sdk}', f'cmake;{CMAKE_VERSION}'],
                               check=True, timeout=180)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as exc:
                raise RuntimeError('sdkmanager не завершил установку. '
                                   'Повторите с --download-fallback; см. docs/build/android.md.') from exc
    subprocess.run([str(cmake), '--version'], check=True)
    print('Окружение Android готово. Сборка: ./scripts/build_dev.sh')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError) as exc:
        print(f'Ошибка: {exc}', file=sys.stderr)
        sys.exit(1)
