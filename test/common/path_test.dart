import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('path_test');
    await useAppPaths(root);
  });

  tearDownAll(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('iOS remapped group preserves old data without replacing newer data', () async {
    final legacy = Directory(join(root.path, 'legacy'));
    final shared = Directory(join(root.path, 'shared'));
    await Directory(join(legacy.path, 'profiles')).create(recursive: true);
    await shared.create();
    await File(join(legacy.path, 'profiles', '1.yaml')).writeAsString('profile');
    await File(join(legacy.path, 'shared_preferences.json')).writeAsString('old');
    await File(join(shared.path, 'shared_preferences.json')).writeAsString('new');
    await File(join(legacy.path, 'run_time')).writeAsString('stale');

    final directory = await AppPath.resolveIOSDataDirectory(shared.path, legacy);
    expect(directory.path, shared.path);
    expect(await File(join(shared.path, 'profiles', '1.yaml')).readAsString(), 'profile');
    expect(await File(join(shared.path, 'shared_preferences.json')).readAsString(), 'new');
    expect(await File(join(shared.path, 'run_time')).exists(), isFalse);
    expect(await File(join(legacy.path, 'profiles', '1.yaml')).exists(), isTrue);

    await File(join(shared.path, 'profiles', '1.yaml')).delete();
    await AppPath.resolveIOSDataDirectory(shared.path, legacy);
    expect(await File(join(shared.path, 'profiles', '1.yaml')).exists(), isFalse);
    expect((await AppPath.resolveIOSDataDirectory(null, legacy)).path, legacy.path);
  });

  test('provider directories match the paths handed to the core', () async {
    const proxiesUrl = 'https://example.com/a.yaml';
    const rulesUrl = 'https://example.com/b.yaml';
    final proxiesDir = await appPath.getProviderDirPath(
      7,
      proxiesProviderDirectoryName,
    );
    final rulesDir = await appPath.getProviderDirPath(
      7,
      rulesProviderDirectoryName,
    );

    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': {
            'a': {'type': 'http', 'url': proxiesUrl},
          },
          'rule-providers': {
            'b': {'type': 'http', 'url': rulesUrl},
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(
      config['proxy-providers']['a']['path'],
      join(proxiesDir, 'a@$proxiesUrl'.toMd5()),
    );
    expect(
      config['rule-providers']['b']['path'],
      join(rulesDir, 'b@$rulesUrl'.toMd5()),
    );
  });

  test('confines a provider path the profile tried to choose', () async {
    final proxiesDir = await appPath.getProviderDirPath(
      7,
      proxiesProviderDirectoryName,
    );
    final rulesDir = await appPath.getProviderDirPath(
      7,
      rulesProviderDirectoryName,
    );

    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': {
            'escape': {'type': 'file', 'path': '../../../../config.yaml'},
            'urlless': {'type': 'http', 'path': 'cache.db'},
            'literal': {
              'type': 'inline',
              'payload': ['DIRECT'],
            },
          },
          'rule-providers': {
            'sneak': {'type': 'file', 'path': '/etc/hosts'},
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(
      config['proxy-providers']['escape']['path'],
      join(proxiesDir, 'proxy-providers/escape'.toMd5()),
    );
    expect(
      config['proxy-providers']['urlless']['path'],
      join(proxiesDir, 'proxy-providers/urlless'.toMd5()),
    );
    expect(config['proxy-providers']['literal']['path'], isNull);
    expect(
      config['rule-providers']['sneak']['path'],
      join(rulesDir, 'rule-providers/sneak'.toMd5()),
    );
  });

  test('survives a provider section that is not a map', () async {
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': ['not-a-map'],
          'rule-providers': {
            'broken': ['also-not-a-map'],
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );

    expect(result.yaml, isNotEmpty);
  });

  test('ensureProviderDirs creates both provider directories', () async {
    await appPath.ensureProviderDirs(9);

    for (final type in const [
      proxiesProviderDirectoryName,
      rulesProviderDirectoryName,
    ]) {
      expect(
        Directory(await appPath.getProviderDirPath(9, type)).existsSync(),
        isTrue,
      );
    }

    await expectLater(appPath.ensureProviderDirs(9), completes);
  });
}
