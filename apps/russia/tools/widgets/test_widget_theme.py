"""Public gallery and visual contracts for the home-screen streak widget."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / 'android/app/src/main'
RES = ANDROID / 'res'
NS = '{http://schemas.android.com/apk/res/android}'
SWIFT = (ROOT / 'ios/StreakWidget/StreakWidget.swift').read_text()


class WidgetThemeTest(unittest.TestCase):
    def test_gallery_has_one_resizable_streak_widget(self):
        manifest = ET.parse(ANDROID / 'AndroidManifest.xml')
        receivers = [
            receiver.attrib[NS + 'name'] for receiver in manifest.findall('.//receiver')
            if any(meta.get(NS + 'name') == 'android.appwidget.provider'
                   for meta in receiver.findall('meta-data'))
            and 'Streak' in receiver.get(NS + 'name', '')
        ]
        self.assertEqual([name.split('.')[-1] for name in receivers], ['StreakWidgetProvider'])
        info = ET.parse(RES / 'xml/streak_widget_info.xml').getroot()
        self.assertEqual(set(info.get(NS + 'resizeMode').split('|')), {'horizontal', 'vertical'})
        self.assertIn('kind: "PddStudyStreak"', SWIFT)
        self.assertNotIn('PddStudyStreakMinimal', SWIFT)
        self.assertNotIn('PddStudyStreakRecord', SWIFT)

    def test_all_sizes_share_the_celebration_art(self):
        source = (ROOT.parents[1] / 'packages/pdd_ui/lib/src/app_colors.dart').read_text()
        gold = re.search(r'static const Color gold = Color\(0xFF([0-9A-Fa-f]{6})\)', source).group(1)
        palette = ET.parse(RES / 'values/streak_widget_colors.xml')
        self.assertEqual(palette.find("color[@name='streak_widget_active_background']").text, '#' + gold)
        for filename in ('streak_widget.xml', 'streak_widget_wide.xml', 'streak_widget_row.xml'):
            path = RES / 'layout' / filename
            layout = ET.parse(path)
            elements = {node.get(NS + 'id'): node for node in layout.iter()}
            rays = elements['@+id/streak_rays']
            self.assertEqual(rays.get(NS + 'src'), '@drawable/streak_widget_rays', filename)
            self.assertEqual(rays.get(NS + 'scaleType'), 'centerCrop', filename)
            self.assertEqual(elements['@+id/streak_flame'].tag, 'ImageView')
            self.assertEqual(elements['@+id/streak_trophy'].tag, 'ImageView')
            self.assertEqual('@+id/streak_week' in elements, filename != 'streak_widget.xml')
            for metric in ('current', 'best'):
                self.assertEqual(elements['@+id/streak_' + metric].get(NS + 'textColor'), '#FFFFFF')
        self.assertTrue((RES / 'drawable-nodpi/streak_widget_rays.png').is_file())
        self.assertIn('CelebrationBackground', SWIFT)

    def test_inactive_day_is_a_solid_white_dot(self):
        marker = ET.parse(RES / 'drawable/streak_widget_day_empty.xml').getroot()
        path = marker.find('path')
        self.assertEqual(path.get(NS + 'fillColor'), '#FFFFFF')
        self.assertIsNone(path.get(NS + 'strokeColor'))


if __name__ == '__main__':
    unittest.main()
