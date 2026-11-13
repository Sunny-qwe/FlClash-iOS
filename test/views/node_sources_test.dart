import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/node_sources.dart';
import 'package:fl_clash/views/profiles/custom/custom_proxies.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../providers/node_sources_action_test.dart'
    show TestNodeGroups, TestSourceNodes;

class _RecordingSources extends NodeSourcesAction {
  bool fail = false;
  Set<int>? attached;
  Set<int>? attachedNodes;
  String? pasted;
  @override
  Future<Set<int>> importShareLinks(String content) async {
    pasted = content;
    return {42};
  }
  @override
  Future<void> attach(
    int profileId, {
    required Set<int> groupIds,
    Set<int> subscriptionIds = const {},
    Set<int> nodeIds = const {},
  }) async {
    if (fail) throw const MessageException('Import failed');
    attached = subscriptionIds;
    attachedNodes = nodeIds;
  }
}

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  setUpAll(() => registerFallbackValue(<Map<String, dynamic>>[]));
  final profile = Profile.custom(label: 'My config');
  final source = Profile.normal(
    label: 'My subscription',
    url: 'https://example.com/sub',
  );
  final group = ProxyGroup(
    id: 1001,
    name: 'Manual',
    type: GroupType.Selector,
    includeAllProviders: true,
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    int? id,
    bool dark = false,
    _RecordingSources? action,
    List<Profile>? profiles,
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = _Core();
    when(() => core.validateProxies(any())).thenAnswer((_) async => {});
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        customGroupNamesProvider.overrideWith((_) => Stream.value(<String>{})),
        profilesProvider.overrideWith(
          () => TestProfiles(profiles ?? [profile, source]),
        ),
        proxyGroupsProvider.overrideWith2((_) => TestNodeGroups([group])),
        customProxiesProvider.overrideWith(() => TestSourceNodes([])),
        if (action != null)
          nodeSourcesActionProvider.overrideWith(() => action),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 1200));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          child: NodeSourcesView(profileId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'empty app offers a configuration without requiring a YAML file',
    (tester) async {
      await pump(tester, profiles: []);
      expect(find.text(currentAppLocalizations.addProfile), findsOneWidget);
      expect(
        find.text(currentAppLocalizations.nodeSourcesDesc),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large source lists only build visible rows', (tester) async {
    await pump(
      tester,
      profiles: List.generate(
        1000,
        (i) => Profile.normal(
          label: 'Subscription $i',
          url: 'https://example.com/$i',
        ),
      ),
    );
    expect(find.text('Subscription 0'), findsOneWidget);
    expect(find.text('Subscription 999'), findsNothing);
    expect(find.byType(ListItem).evaluate().length, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'adds an existing subscription from the group picker in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final action = _RecordingSources();
        await pump(tester, id: profile.id, dark: dark, action: action);
        final l = currentAppLocalizations;
        await tester.tap(find.text(l.nodeSourcesExisting));
        await tester.pumpAndSettle();
        await tester.tap(find.text(source.realLabel));
        await tester.tap(find.byTooltip(l.save));
        await tester.pumpAndSettle();
        expect(action.attached, {source.id});
        expect(find.byType(NodeSourcesView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancel leaves the configuration unchanged and a failed add releases busy state',
    (tester) async {
      final action = _RecordingSources()..fail = true;
      await pump(tester, id: profile.id, action: action);
      final l = currentAppLocalizations;
      await tester.tap(find.text(l.nodeSourcesExisting));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text(source.realLabel))).pop();
      await tester.pumpAndSettle();
      expect(action.attached, isNull);
      await tester.tap(find.text(l.nodeSourcesExisting));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source.realLabel));
      await tester.tap(find.byTooltip(l.save));
      await tester.pumpAndSettle();
      expect(find.text('Import failed'), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).isLoading,
        false,
      );
    },
  );

  testWidgets('manual add opens the protocol form directly', (tester) async {
    await pump(tester, id: profile.id);
    await tester.tap(find.text(currentAppLocalizations.nodeSourcesManual));
    await tester.pumpAndSettle();
    expect(find.byType(CustomProxiesView), findsNothing);
    expect(find.text(currentAppLocalizations.server), findsWidgets);
    expect(find.text(currentAppLocalizations.port), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard nodes are attached to the open configuration', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'ss://first\nvless://second'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final action = _RecordingSources();
    await pump(tester, id: profile.id, action: action);
    await tester.tap(find.text(currentAppLocalizations.clipboardImport));
    await tester.pumpAndSettle();
    expect(action.pasted, 'ss://first\nvless://second');
    expect(action.attachedNodes, {42});
    expect(tester.takeException(), isNull);
  });
}
