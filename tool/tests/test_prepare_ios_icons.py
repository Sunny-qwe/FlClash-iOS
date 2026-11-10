import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_ios_icons import prepare_icons
from verify_ios_bundle import ICONS


class PrepareIconsTests(unittest.TestCase):
    def test_standalone_icons_match_catalog_pixels_and_scale_names(self):
        assets = Path(__file__).resolve().parents[2] / 'ios/Runner/Assets.xcassets'
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            info_path = app / 'Info.plist'
            info_path.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test', 'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}}}))
            prepare_icons(app, assets)
            info = plistlib.loads(info_path.read_bytes())
            self.assertEqual(info['CFBundleIcons']['CFBundlePrimaryIcon'], {'CFBundleIconName': 'AppIcon'})
            for name in ICONS:
                self.assertEqual(info['CFBundleIcons']['CFBundleAlternateIcons'][name]['CFBundleIconFiles'], [name + '60x60'])
                self.assertEqual(info['CFBundleIcons~ipad']['CFBundleAlternateIcons'][name]['CFBundleIconFiles'], [name + '76x76', name + '83.5x83.5'])
                for filename, size in ((name + '60x60@2x.png', 120), (name + '60x60@3x.png', 180), (name + '76x76.png', 76), (name + '76x76@2x.png', 152), (name + '83.5x83.5@2x.png', 167)):
                    self.assertEqual((app / filename).read_bytes(), (assets / (name + '.appiconset') / f'{name}-{size}.png').read_bytes())


if __name__ == '__main__':
    unittest.main()
