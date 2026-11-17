"""Cross-platform contracts for the streak celebration color and native icons."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def colors():
    return {e.attrib['name']: e.text.lstrip('#') for e in ET.parse(
        ROOT / 'android/app/src/main/res/values/streak_widget_colors.xml').getroot()}


def luminance(rgb):
    channels = [int(rgb[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(a * b for a, b in zip(linear, (.2126, .7152, .0722)))


class WidgetThemeTest(unittest.TestCase):
    def test_gallery_preview_always_shows_today_status(self):
        android_ns = '{http://schemas.android.com/apk/res/android}'
        for path in (ROOT / 'android/app/src/main/res/layout').glob('streak_widget*.xml'):
            status = next(e for e in ET.parse(path).getroot().iter()
                          if e.attrib.get(android_ns + 'id') == '@+id/streak_status')
            self.assertEqual(status.attrib.get(android_ns + 'visibility', 'visible'), 'visible', str(path))

    def test_gold_matches_the_app_celebration_on_both_platforms(self):
        source = (ROOT.parents[1] / 'packages/pdd_ui/lib/src/app_colors.dart').read_text()
        app_gold = re.search(r'static const Color gold = Color\(0xFF([0-9A-Fa-f]{6})\)', source).group(1).upper()
        self.assertEqual(colors()['streak_widget_active_background'].upper(), app_gold)
        swift = (ROOT / 'ios/StreakWidget/StreakWidget.swift').read_text()
        ios_gold = re.search(r'static let activeBackground = Color\(widgetRGB: 0x([0-9A-Fa-f]{6})\)', swift).group(1)
        self.assertEqual(ios_gold.upper(), app_gold)

    def test_small_text_has_readable_contrast_on_bright_background(self):
        palette = colors()
        for key in ('streak_widget_active_text', 'streak_widget_active_secondary'):
            light, dark = sorted([luminance(palette[key]), luminance(palette['streak_widget_active_background'])], reverse=True)
            self.assertGreaterEqual((light + .05) / (dark + .05), 4.5, key)

    def test_native_widget_content_uses_icons_instead_of_emoji(self):
        paths = list((ROOT / 'android/app/src/main/res/layout').glob('streak_widget*.xml')) + [
            ROOT / 'android/app/src/main/kotlin/ru/pdd/pdd_app/StreakWidgetRenderer.kt',
            ROOT / 'ios/StreakWidget/StreakWidget.swift',
        ]
        for path in paths:
            self.assertNotRegex(path.read_text(), '[\U0001F000-\U0001FFFF]', str(path))
        android_ns = '{http://schemas.android.com/apk/res/android}'
        for path in paths:
            if path.suffix != '.xml':
                continue
            by_id = {e.attrib.get(android_ns + 'id'): e.tag for e in ET.parse(path).getroot().iter()}
            for name in ('streak_flame', 'streak_trophy'):
                self.assertEqual(by_id['@+id/' + name], 'ImageView', str(path))


if __name__ == '__main__':
    unittest.main()
