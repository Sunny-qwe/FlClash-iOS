import 'dart:io';

import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('iOS signing targets use the actual built application identifier', () {
      final targets = setup.createIOSNoSignSigningTargets(
        rootDir: Directory.current.path,
        appBundlePath: 'build/ios/iphoneos/Runner.app',
        appBundleId: 'com.follow.clash',
      );
      expect(targets.map((target) => target.bundleIdentifier), [
        'com.follow.clash.NECore',
        'com.follow.clash.Widget',
        'com.follow.clash',
      ]);
      for (final target in targets) {
        final output = setup.createIOSNoSignEntitlements(
          source: File(target.entitlements).readAsStringSync(),
          appBundleId: 'com.follow.clash',
          bundleIdentifier: target.bundleIdentifier,
          teamIdentifier: 'TESTTEAM00',
        );
        final elements = XmlDocument.parse(output)
            .findAllElements('dict')
            .single
            .childElements
            .toList();
        final values = {
          for (var index = 0; index < elements.length; index += 2)
            elements[index].innerText: elements[index + 1].innerText.trim(),
        };
        expect(values['application-identifier'], 'TESTTEAM00.${target.bundleIdentifier}');
        expect(values['com.apple.developer.team-identifier'], 'TESTTEAM00');
        expect(values['com.apple.security.application-groups'], 'group.com.follow.clash');
        if (!target.bundleIdentifier.endsWith('.Widget')) {
          expect(values['com.apple.developer.networking.networkextension'], 'packet-tunnel-provider');
        }
      }
    });

    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('refuses to package while a native build hook is skipped', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: true
''';

      expect(setup.packagesNotBuildingAssets(pubspec), ['setup']);
      expect(setup.packagesNotBuildingAssets('name: x\n'), isEmpty);
    });

    test('packages every Linux format on every architecture', () {
      expect(setup.createPackageTargets('linux', null), 'deb,appimage,rpm');
      expect(setup.createPackageTargets('linux', 'deb'), 'deb');
      expect(setup.createPackageTargets('macos', null), 'dmg');
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
    });
  });
}
