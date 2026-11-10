import argparse
import json
import plistlib
import shutil
from pathlib import Path

from verify_ios_bundle import ICONS, verify_assets


def prepare_icons(app, assets):
    verify_assets(assets)
    info_path = app / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    for name in sorted(ICONS):
        folder = assets / f'{name}.appiconset'
        entries = json.loads((folder / 'Contents.json').read_text())['images']
        files = {'iphone': set(), 'ipad': set()}
        for entry in entries:
            idiom = entry['idiom']
            if idiom not in files:
                continue
            base = name + entry['size']
            scale = entry['scale']
            filename = base + (f'@{scale}' if scale != '1x' else '') + '.png'
            shutil.copyfile(folder / entry['filename'], app / filename)
            files[idiom].add(base)
        for key, idiom in (('CFBundleIcons', 'iphone'), ('CFBundleIcons~ipad', 'ipad')):
            icon = info.setdefault(key, {}).setdefault('CFBundleAlternateIcons', {}).setdefault(name, {})
            icon['CFBundleIconName'] = name
            icon['CFBundleIconFiles'] = sorted(files[idiom])
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    print('Prepared standalone alternate icon PNGs and phone/iPad file declarations before signing')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    args = parser.parse_args()
    prepare_icons(args.app, args.assets)
