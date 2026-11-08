#!/usr/bin/env python3
"""Explicit inclusion and the persistent review group, without starting a server."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync
import migrate
import server

GROUP = 'unmarked-2026-10-15'
ORIGINAL_GROUP = {
    'ticket_10_14', 'ticket_11_13', 'ticket_11_15', 'ticket_11_2',
    'ticket_12_15', 'ticket_12_5', 'ticket_13_15', 'ticket_14_14',
    'ticket_14_15', 'ticket_14_8', 'ticket_15_14', 'ticket_15_15',
    'ticket_16_13', 'ticket_16_14', 'ticket_16_15', 'ticket_16_2',
    'ticket_17_13', 'ticket_17_14', 'ticket_17_15', 'ticket_17_6',
    'ticket_17_8', 'ticket_18_14', 'ticket_18_15',
}


class SceneReviewTest(unittest.TestCase):
    def test_original_review_group_and_current_index(self):
        scenes = {p.stem: json.loads(p.read_text()) for p in check.NET.glob('*.json')}
        grouped = {sid for sid, scene in scenes.items() if scene.get('reviewGroup') == GROUP}
        self.assertEqual(grouped, ORIGINAL_GROUP)
        # The owner can enable any of these later without losing the original list.
        self.assertTrue(all(type(scenes[sid].get('reviewed')) is bool for sid in grouped))
        indexed = json.loads((engine_sync.SIT / 'index.json').read_text())
        expected = sorted(sid for sid, scene in scenes.items()
                          if sid != 'mini_regulator' and scene.get('reviewed') is True)
        self.assertEqual(indexed, expected)

    def test_explicit_flags_and_manual_include_preserve_group(self):
        with tempfile.TemporaryDirectory(prefix='scene-review-', dir=check.ROOT / 'scratch') as tmp:
            root = Path(tmp)
            net, sit = root / 'network', root / 'situations'
            net.mkdir()
            sit.mkdir()
            cases = {'missing': {}, 'enabled': {'reviewed': True},
                     'disabled': {'reviewed': False}, 'null': {'reviewed': None},
                     'number': {'reviewed': 1}, 'string': {'reviewed': 'true'},
                     'mini_regulator': {'reviewed': True}}
            for sid, flags in cases.items():
                scene = {'id': sid, 'reviewGroup': GROUP, 'routes': [], **flags}
                (net / f'{sid}.json').write_text(json.dumps(scene))
            responses = []
            handler = object.__new__(server.Handler)
            handler.send = lambda code, body: responses.append((code, body))
            with patch.object(check, 'NET', net), patch.object(engine_sync, 'NET', net), \
                    patch.object(engine_sync, 'SIT', sit), patch.object(server, 'NET', net), \
                    patch.object(server, 'HISTORY', net / 'history'), \
                    patch.object(check, 'check_scene', return_value=[]):
                listed = {entry['id']: entry for entry in handler.scene_list()}
                for sid in cases:
                    expected = sid == 'enabled'
                    self.assertEqual(engine_sync.playable(sid), expected, sid)
                    self.assertEqual(listed[sid]['playable'], expected, sid)
                    self.assertEqual(listed[sid]['reviewGroup'], GROUP, sid)
                self.assertEqual(engine_sync.write_index(), ['enabled'])
                # Turning off an old missing flag writes an explicit false too.
                handler.include('missing', False)
                self.assertEqual(responses[-1][0], 200)
                self.assertIs(check.load('missing')['reviewed'], False)
                original = copy.deepcopy(check.load('disabled'))
                handler.include('disabled', True)
                self.assertTrue(responses[-1][1]['playable'])
                enabled = check.load('disabled')
                self.assertEqual(enabled, {**original, 'reviewed': True})
                self.assertEqual(engine_sync.write_index(), ['disabled', 'enabled'])
                # Reopening the list reads the group from source, even after inclusion.
                reopened = {entry['id']: entry for entry in handler.scene_list()}['disabled']
                self.assertEqual(reopened['reviewGroup'], GROUP)
                self.assertTrue(reopened['playable'])
                handler.include('disabled', False)
                self.assertEqual(check.load('disabled'), original)
                self.assertEqual(engine_sync.write_index(), ['enabled'])
                self.assertTrue(list((net / 'history' / 'disabled').glob('*.json')))

    def test_newly_migrated_scenes_require_explicit_review(self):
        with tempfile.TemporaryDirectory(prefix='scene-review-migrate-', dir=check.ROOT / 'scratch') as tmp:
            root = Path(tmp)
            source = root / 'fixture'
            source.mkdir()
            with patch.object(migrate, 'SRC', root), \
                    patch.object(migrate, 'trace_mask', return_value=migrate.Polygon()):
                for flags in ({}, {'reviewed': False}, {'reviewed': None},
                              {'reviewed': 1}, {'reviewed': 'true'}, {'reviewed': True}):
                    scene = {'roadMask': {}, 'stopZ': -12, **flags}
                    (source / 'scene.json').write_text(json.dumps(scene))
                    converted = migrate.migrate('fixture')
                    self.assertEqual(converted['reviewed'], flags.get('reviewed') is True)
                    self.assertEqual(json.loads((source / 'scene.json').read_text()), scene)


if __name__ == '__main__':
    unittest.main()
