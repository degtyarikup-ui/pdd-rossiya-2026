"""Read unencrypted standalone Godot PCK v2/v3/v4 directories, without extraction.

Layout reference: godotengine/godot core/io/file_access_pack.cpp.
Reject unknown/encrypted/sparse formats rather than silently skip inspection.
"""
import struct


def read_exact(stream, size):
    data = stream.read(size)
    if len(data) != size:
        raise ValueError('Truncated PCK')
    return data


def entries(stream):
    stream.seek(0, 2)
    length = stream.tell()
    stream.seek(0)
    if read_exact(stream, 4) != b'GDPC':
        raise ValueError('Not a standalone PCK')
    version, major, minor, patch, flags = struct.unpack('<5I', read_exact(stream, 20))
    if version not in (2, 3, 4) or flags & ~2:
        raise ValueError(f'Unsupported PCK version/flags: {version}/{flags}')
    base, = struct.unpack('<Q', read_exact(stream, 8))
    if version >= 3:
        directory, = struct.unpack('<Q', read_exact(stream, 8))
        if directory >= length:
            raise ValueError('Invalid PCK directory offset')
        stream.seek(directory)
    else:
        read_exact(stream, 64)
    count, = struct.unpack('<I', read_exact(stream, 4))
    if count > 1000000:
        raise ValueError('Invalid PCK entry count')
    result = []
    names = set()
    for _ in range(count):
        size, = struct.unpack('<I', read_exact(stream, 4))
        if size > 65536:
            raise ValueError('Invalid PCK path length')
        name = read_exact(stream, size).rstrip(b'\0').decode('utf-8')
        offset, size = struct.unpack('<QQ', read_exact(stream, 16))
        read_exact(stream, 16)  # digest
        file_flags, = struct.unpack('<I', read_exact(stream, 4))
        if file_flags or base + offset + size > length:
            raise ValueError(f'Unsupported or invalid PCK entry: {name}')
        name = name.removeprefix('res://')
        if name in names or '..' in name.split('/') or name.startswith('/'):
            raise ValueError(f'Invalid/duplicate PCK path: {name}')
        names.add(name)
        result.append((name, size, base + offset))
    return result


def inspect(stream, country):
    import json
    import re
    errors = []
    listing = entries(stream)
    for name, size, offset in listing:
        for match in re.finditer(r'(?:^|/)countries/([^/]+)/', name):
            if match[1] != country:
                errors.append(f'Foreign PCK resource: {name}')
        if name.endswith('scene.json'):
            stream.seek(offset)
            scene = json.loads(read_exact(stream, size))
            if scene.get('country', country) != country:
                errors.append(f'Foreign scene country: {name}: {scene.get("country")}')
    return {'files': len(listing), 'content_bytes': sum(row[1] for row in listing), 'errors': errors}
