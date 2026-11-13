import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Core core;
  late CoreController controller;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('provider-preparation-');
    await useAppPaths(root);
    await AppLocalizations.load(const Locale('en'));
    core = _Core();
    controller = CoreController.scoped(core);
  });
  tearDown(() => root.delete(recursive: true));

  test('provider file uses normalized nodes and refreshes after subscription updates', () async {
    final source = File(await appPath.getProfilePath('42'));
    await source.create(recursive: true);
    await source.writeAsString('original subscription');
    final normalized = {
      'proxies': [{'name': 'REALITY', 'type': 'vless', 'tls': true, 'client-fingerprint': 'chrome', 'reality-opts': {'short-id': '001234'}}],
      'rule': ['MATCH,DIRECT'],
    };
    when(() => core.readConfig(source.path)).thenAnswer((_) async => normalized);
    final path = await controller.prepareProxyProvider(42);
    expect(path, isNot(source.path));
    final config = loadYaml(await File(path).readAsString()) as YamlMap;
    expect(config.keys, ['proxies']);
    final node = config['proxies'][0];
    expect(node['tls'], true);
    expect(node['client-fingerprint'], 'chrome');
    expect(node['reality-opts']['short-id'], '001234');
    await controller.prepareProxyProvider(42);
    verify(() => core.readConfig(source.path)).called(1);
    await File(path).setLastModified(DateTime.fromMillisecondsSinceEpoch(0));
    await controller.prepareProxyProvider(42);
    verify(() => core.readConfig(source.path)).called(1);
    expect(await source.readAsString(), 'original subscription');
  });

  test('a configuration containing only providers cannot silently become an empty node source', () async {
    final source = File(await appPath.getProfilePath('43'));
    await source.create(recursive: true);
    await source.writeAsString('proxy-providers: {}');
    when(() => core.readConfig(source.path)).thenAnswer((_) async => {'proxies': []});
    await expectLater(controller.prepareProxyProvider(43), throwsA(isA<MessageException>()));
    expect(await File('${source.path}.provider-v1.yaml').exists(), false);
  });
}
