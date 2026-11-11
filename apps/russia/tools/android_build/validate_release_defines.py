"""Reject development switches before a store build exports or uploads anything."""
import json
from pathlib import Path
import re
import sys


FORBIDDEN_DEFINES = frozenset({
    'GAME_DEBUG', 'GAME_DEBUG_DEVICE', 'DEV_SEASON', 'DEVICE_REGION',
    'NOTIF_TEST', 'SCREEN', 'GIT_COMMIT',
    # The selected target owns these; an extra define must not change it.
    'COUNTRY', 'STORE',
})


def check_key(key):
    if key in FORBIDDEN_DEFINES:
        raise ValueError(f'{key} is not permitted in release extra defines')
    if key.startswith('dart.vm.'):
        raise ValueError('Dart VM mode overrides are not permitted in a release')


def check_file(filename):
    try:
        raw = Path(filename).read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        raise ValueError('Cannot read a release defines file') from None
    if raw.lstrip().startswith('{'):
        try:
            data = json.loads(raw)
        except ValueError:
            raise ValueError('Invalid JSON in a release defines file') from None
        for key in data:
            check_key(key)
    else:
        # Flutter also accepts dotenv files. Only inspect keys: values can be
        # secrets and must never appear in validation messages or build logs.
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            match = re.match(r'^([A-Za-z_][A-Za-z0-9_.-]*)\s*=', line)
            if match is None:
                raise ValueError('Invalid property in a release defines file')
            check_key(match.group(1))


def validate(arguments):
    args = iter(arguments)
    for arg in args:
        option, separator, value = arg.partition('=')
        if option not in ('--dart-define', '--dart-define-from-file'):
            raise ValueError('EXTRA_DEFINES accepts only Dart defines in release builds')
        if not separator:
            value = next(args, '')
        if not value:
            raise ValueError('Missing value in release extra defines')
        if option == '--dart-define-from-file':
            check_file(value)
        else:
            key, separator, _ = value.partition('=')
            if not key or not separator:
                raise ValueError('Invalid release Dart define')
            check_key(key)


if __name__ == '__main__':
    try:
        validate(sys.argv[1:])
    except ValueError as exc:
        print(f'Release configuration rejected: {exc}', file=sys.stderr)
        sys.exit(1)
