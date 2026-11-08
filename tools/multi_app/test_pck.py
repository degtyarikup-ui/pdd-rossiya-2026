import io
import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from tools.multi_app.pck import entries, inspect
from tools.multi_app.check_artifact import inspect_artifact


def pack(version=3, name='situations/example/scene.json', country='ru'):
    payload = json.dumps({'country': country}).encode()
    path = name.encode()
    header_size = 100 if version == 2 else 104
    directory = struct.pack('<II', 1, len(path)) + path
    offset = header_size + len(directory) + 36
    directory += struct.pack('<QQ', offset, len(payload)) + bytes(16) + struct.pack('<I', 0)
    header = b'GDPC' + struct.pack('<5IQ', version, 4, 7, 2, 0, 0)
    if version >= 3:
        header += struct.pack('<Q', header_size)
    header += bytes(header_size - len(header))
    # v2 directory starts at 96; v3/v4 use explicit directory offset.
    if version == 2:
        header = header[:96]
        offset -= 4
        directory = struct.pack('<II', 1, len(path)) + path + struct.pack('<QQ', offset, len(payload)) + bytes(16) + struct.pack('<I', 0)
    return header + directory + payload


class PackAuditTest(unittest.TestCase):
    def test_supported_versions_and_foreign_scene(self):
        for version in (2, 3, 4):
            with self.subTest(version=version):
                self.assertEqual(inspect(io.BytesIO(pack(version)), 'ru')['errors'], [])
                self.assertTrue(inspect(io.BytesIO(pack(version, country='by')), 'ru')['errors'])

    def test_foreign_path_without_scene_metadata(self):
        self.assertTrue(inspect(io.BytesIO(pack(name='assets/countries/by/q.json')), 'ru')['errors'])

    def test_corrupt_and_unknown_formats_fail(self):
        for data in (b'', pack()[:40], pack(99), pack()[:20] + struct.pack('<I', 1) + pack()[24:]):
            with self.assertRaises(ValueError):
                entries(io.BytesIO(data))

    def test_nested_ipa_pack_is_inspected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.ipa'
            with zipfile.ZipFile(path, 'w') as out:
                out.writestr('Payload/Runner.app/flutter_assets/assets/countries/ru/questions/q.json', '[]')
                out.writestr('Payload/Runner.app/Runner.pck', pack(country='by'))
            report = inspect_artifact(path, 'ru')
            self.assertFalse(report['ok'])
            self.assertEqual(len(report['packs']), 1)

    def test_loose_android_scene_is_inspected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.apk'
            with zipfile.ZipFile(path, 'w') as out:
                out.writestr('assets/flutter_assets/assets/countries/ru/questions/q.json', '[]')
                out.writestr('assets/situations/demo/scene.json', '{"country":"by"}')
            self.assertFalse(inspect_artifact(path, 'ru')['ok'])


if __name__ == '__main__':
    unittest.main()
