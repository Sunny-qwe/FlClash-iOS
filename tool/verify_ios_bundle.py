import argparse
import json
import plistlib
import struct
import zipfile
from pathlib import Path


ICONS = {f'AppIcon-{name}' for name in (
    'Classic', 'Dark', 'Neon', 'Sunset', 'Emerald', 'Sakura', 'Titanium', 'Purple',
)}


def verify_assets(root):
    for name in sorted(ICONS):
        folder = root / f'{name}.appiconset'
        entries = json.loads((folder / 'Contents.json').read_text())['images']
        slots = set()
        for entry in entries:
            width, height = map(float, entry['size'].split('x'))
            scale = float(entry['scale'][:-1])
            image = (folder / entry['filename']).read_bytes()
            assert image[:8] == b'\x89PNG\r\n\x1a\n', entry
            actual = struct.unpack_from('>II', image, 16)
            assert actual == (int(width * scale), int(height * scale)), (name, actual, entry)
            slots.add((entry['idiom'], entry['size'], entry['scale']))
        assert {('iphone', '60x60', '2x'), ('iphone', '60x60', '3x'),
                ('ipad', '76x76', '2x'), ('ipad', '83.5x83.5', '2x'),
                ('ios-marketing', '1024x1024', '1x')} <= slots, name
    print('Verified all alternate icon source slots and PNG dimensions')


def entitlements(binary):
    assert binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected arm64 Mach-O'
    position = 32
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, length = struct.unpack_from('<II', binary, position)
        if command == 0x1D:
            offset, size = struct.unpack_from('<II', binary, position + 8)
            signature = binary[offset:offset + size]
            for index in range(struct.unpack_from('>I', signature, 8)[0]):
                kind, location = struct.unpack_from('>II', signature, 12 + index * 8)
                if kind == 5:
                    length = struct.unpack_from('>I', signature, location + 4)[0]
                    return plistlib.loads(signature[location + 8:location + length])
        position += length
    raise AssertionError('Missing executable entitlements')


def verify_ipa(path):
    with zipfile.ZipFile(path) as archive:
        root = 'Payload/Runner.app/'
        info = plistlib.loads(archive.read(root + 'Info.plist'))
        bundle_id = info['CFBundleIdentifier']
        for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
            alternates = info[key].get('CFBundleAlternateIcons', {})
            assert ICONS <= alternates.keys(), (key, 'Missing alternate icons', sorted(alternates))
            for name in ICONS:
                files = alternates[name].get('CFBundleIconFiles', [])
                assert files, (key, name, 'Missing icon files')
                for filename in files:
                    assert any(item.startswith(root + filename) and item.endswith('.png')
                               for item in archive.namelist()), (key, name, filename)
        groups = [f'group.{bundle_id}']
        for suffix, executable in (('', 'Runner'), ('NECore', 'NECore'), ('Widget', 'Widget')):
            folder = root + (f'PlugIns/{suffix}.appex/' if suffix else '')
            target = plistlib.loads(archive.read(folder + 'Info.plist'))
            expected = bundle_id + (f'.{suffix}' if suffix else '')
            assert target['CFBundleIdentifier'] == expected, (suffix, target)
            rights = entitlements(archive.read(folder + executable))
            assert rights['com.apple.security.application-groups'] == groups, (suffix, rights)
            assert rights['application-identifier'].endswith('.' + expected), (suffix, rights)
            if suffix != 'Widget':
                assert 'packet-tunnel-provider' in rights['com.apple.developer.networking.networkextension']
            if suffix == 'NECore':
                extension = target['NSExtension']
                assert extension['NSExtensionPointIdentifier'] == 'com.apple.networkextension.packet-tunnel'
                assert extension['NSExtensionPrincipalClass'].endswith('.PacketTunnelProvider')
        print(f'Verified {path.name}: 8 alternate icons, 3 bundle identifiers, shared group {groups[0]}, VPN extension')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--assets', type=Path)
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    if args.assets:
        verify_assets(args.assets)
    if args.ipa:
        verify_ipa(args.ipa)
    assert args.assets or args.ipa, 'Provide --assets or --ipa'
