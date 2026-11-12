import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/diagnostics/diagnostics.dart';
import 'package:fl_clash/views/diagnostics/health_check.dart';
import 'package:fl_clash/views/diagnostics/module_audit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prism_ui/prism_ui.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database_providers.dart';
import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Setup extends SetupAction {
  @override
  void build() {}

  @override
  Future<String> buildProfileWithId(int profileId) async => 'proxies: []\nrules: []\n';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Core core;
  setUpAll(() {
    registerFallbackValue(const OutboundIpParams(timeout: 1));
    registerFallbackValue(const ServiceCheckParams(timeout: 1));
  });
  setUpAll(() async {
    for (final path in ['/System/Library/Fonts/SFNS.ttf', 'C:/Windows/Fonts/arial.ttf']) {
      final file = File(path);
      if (!await file.exists()) continue;
      await (FontLoader('DiagnosticFont')..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      break;
    }
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diagnostics-view-');
    await useAppPaths(directory);
    core = _Core();
    when(() => core.outboundIp(any())).thenAnswer((_) async => const OutboundIpResult(
      url: 'https://www.cloudflare.com/cdn-cgi/trace', body: 'ip=203.0.113.24\nloc=JP\n', chains: ['test-node'],
    ));
    when(() => core.serviceCheck(any())).thenAnswer((invocation) async {
      final params = invocation.positionalArguments.single as ServiceCheckParams;
      return [ServiceCheckItem(name: params.names.single, status: 'available', delay: 50, chains: ['test-node'])];
    });
  });
  tearDown(() async { await directory.delete(recursive: true); });

  Future<ProviderContainer> mount(WidgetTester tester, Widget page, {bool running = true, bool dark = false, GlobalKey? capture}) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = Profile.custom(label: 'test-profile').copyWith(id: 1);
    final container = ProviderContainer(overrides: [
      coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      profilesProvider.overrideWith(() => TestProfiles([profile])),
      currentProfileIdProvider.overrideWithBuild((_, _) => 1),
      runTimeProvider.overrideWithBuild((_, _) => running ? 1000 : null),
      mitmModulesProvider.overrideWith(TestMitmModules.new),
      setupActionProvider.overrideWith(_Setup.new),
      routeTrackerProvider.overrideWithBuild((_, _) => const RouteState(coreEpoch: 1, routeVersion: 1, proxied: true, synced: true, live: true)),
    ]);
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(320, 740);
    final scheme = seededColorScheme(seedColor: const Color(0xFF635BDF), brightness: dark ? Brightness.dark : Brightness.light, style: ColorStyle.vivid);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: TestApp(
      locale: const Locale('en'), theme: ThemeData(colorScheme: scheme, fontFamily: 'DiagnosticFont'),
      child: MediaQuery(data: const MediaQueryData(size: Size(320, 740), textScaler: TextScaler.linear(1.5)), child: RepaintBoundary(key: capture, child: page)),
    )));
    await tester.pump();
    return container;
  }

  testWidgets('network check does not probe a stopped VPN', (tester) async {
    await mount(tester, const NetworkHealthView(), running: false);
    await tester.tap(find.text('Run check').first);
    await tester.pump();
    verifyNever(() => core.outboundIp(any()));
    expect(find.text('Start the VPN before testing.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('network check probes both exits and services through the Core', (tester) async {
    final container = await mount(tester, const NetworkHealthView(), dark: true);
    await tester.tap(find.text('Run check').first);
    await tester.pumpAndSettle();
    verify(() => core.outboundIp(any())).called(2);
    verify(() => core.serviceCheck(any())).called(2);
    expect(find.textContaining('203.0.113.24'), findsWidgets);
    container.read(routeTrackerProvider.notifier).applySnapshot(const RouteSnapshot(coreEpoch: 1, routeVersion: 2));
    await tester.pump();
    expect(find.textContaining('Connection or routing changed'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('network error clears busy state and permits retry', (tester) async {
    when(() => core.outboundIp(any())).thenThrow(StateError('offline'));
    await mount(tester, const NetworkHealthView());
    await tester.tap(find.text('Run check').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsWidgets);
    await tester.tap(find.text('Run check').first);
    await tester.pumpAndSettle();
    verify(() => core.outboundIp(any())).called(4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('configuration preflight validates without applying or changing profiles', (tester) async {
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    final container = await mount(tester, const ConfigPreflightView());
    await tester.tap(find.text('Run check').first);
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(find.text('Configuration parsed successfully.'), findsOneWidget);
    verify(() => core.validateConfig(any())).called(1);
    expect(container.read(currentProfileIdProvider), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    for (final page in [const DiagnosticsView(), const ConfigPreflightView(), const ModuleAuditView()]) {
      testWidgets('${page.runtimeType} fits enlarged text in ${dark ? 'dark' : 'light'} mode', (tester) async {
        final capture = GlobalKey();
        await mount(tester, page, dark: dark, capture: capture);
        await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 50)); });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File('build/verification/diagnostics/${page.runtimeType}-${dark ? 'dark' : 'light'}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
