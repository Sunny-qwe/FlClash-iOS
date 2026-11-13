import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/test_profiles.dart';

class TestNodeGroups extends ProxyGroups {
  TestNodeGroups(this.initial);
  final List<ProxyGroup> initial;
  @override
  Stream<List<ProxyGroup>> build(int profileId) => Stream.value(initial);
  @override
  bool put(ProxyGroup group) {
    state = AsyncData([
      for (final item in state.value!) item.id == group.id ? group : item,
    ]);
    return true;
  }

  @override
  void setAll(List<ProxyGroup> groups) => state = AsyncData(groups);
}

class TestNodeRules extends ProfileRules {
  @override
  Stream<List<Rule>> build(int profileId) => Stream.value([]);
  @override
  void setAll(List<Rule> rules) => state = AsyncData(rules);
}

class TestSourceNodes extends CustomProxies {
  TestSourceNodes(this.initial);
  final List<CustomProxy> initial;
  @override
  Stream<List<CustomProxy>> build() => Stream.value(initial);
}

class TestSourceProfilesAction extends ProfilesAction {
  int touches = 0;
  @override
  void putProfile(Profile profile) =>
      ref.read(profilesProvider.notifier).put(profile);
  @override
  void touchProfile(int id) {
    touches++;
  }
}

class TestSourceSetup extends SetupAction {
  int applies = 0;
  @override
  void autoApplyProfile() {
    applies++;
  }
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });
  final target = Profile.custom(label: 'Target');
  final source = Profile.normal(
    label: 'Subscription',
    url: 'https://example.com/sub',
  );
  final node = CustomProxy.fromDefinition({
    'name': 'Node',
    'type': 'ss',
    'server': 'example.com',
    'port': 443,
    'cipher': 'aes-128-gcm',
    'password': 'test',
  });
  final group = ProxyGroup(
    id: 101,
    name: 'Select',
    type: GroupType.Selector,
    proxies: ['DIRECT'],
    filter: 'HK',
    excludeFilter: 'test',
    includeAllProviders: true,
  );

  ProviderContainer container({bool current = false, List<Profile>? sources}) {
    final result = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () =>
              TestProfiles([target, ...?sources, if (sources == null) source]),
        ),
        currentProfileIdProvider.overrideWithBuild(
          (_, _) => current ? target.id : null,
        ),
        proxyGroupsProvider.overrideWith2((_) => TestNodeGroups([group])),
        profileRulesProvider.overrideWith2((_) => TestNodeRules()),
        customProxiesProvider.overrideWith(() => TestSourceNodes([node])),
        profilesActionProvider.overrideWith(TestSourceProfilesAction.new),
        setupActionProvider.overrideWith(TestSourceSetup.new),
      ],
    );
    result.listen(proxyGroupsProvider(target.id), (_, _) {});
    result.listen(customProxiesProvider, (_, _) {});
    addTearDown(result.dispose);
    return result;
  }

  test(
    'binds subscriptions and manual nodes, preserves filters and other members',
    () async {
      final c = container(current: true);
      final action = c.read(nodeSourcesActionProvider.notifier);
      await action.attach(
        target.id,
        groupIds: {group.id},
        subscriptionIds: {source.id},
        nodeIds: {node.id},
      );
      final saved = c.read(proxyGroupsProvider(target.id)).value!.single;
      expect(saved.use, [source.realLabel]);
      expect(saved.proxies, ['DIRECT', node.name]);
      expect(saved.filter, 'HK');
      expect(saved.excludeFilter, 'test');
      expect(saved.includeAllProviders, true);
      expect(
        (c.read(setupActionProvider.notifier) as TestSourceSetup).applies,
        1,
      );
      await action.attach(
        target.id,
        groupIds: {group.id},
        subscriptionIds: {source.id},
        nodeIds: {node.id},
      );
      expect(
        (c.read(setupActionProvider.notifier) as TestSourceSetup).applies,
        1,
      );
      expect(
        (c.read(profilesActionProvider.notifier) as TestSourceProfilesAction)
            .touches,
        1,
      );
    },
  );

  test('adding to another config does not apply it', () async {
    final c = container();
    await c
        .read(nodeSourcesActionProvider.notifier)
        .attach(target.id, groupIds: {group.id}, subscriptionIds: {source.id});
    expect(
      (c.read(setupActionProvider.notifier) as TestSourceSetup).applies,
      0,
    );
    expect(c.read(currentProfileIdProvider), isNull);
  });

  test('rejects missing groups and sources before any mutation', () async {
    final c = container();
    final action = c.read(nodeSourcesActionProvider.notifier);
    for (final ids in [
      <int>{},
      {999},
      {group.id, 999},
    ]) {
      await expectLater(
        action.attach(target.id, groupIds: ids, subscriptionIds: {source.id}),
        throwsA(isA<MessageException>()),
      );
    }
    await expectLater(
      action.attach(target.id, groupIds: {group.id}, nodeIds: {999}),
      throwsA(isA<MessageException>()),
    );
    expect(c.read(proxyGroupsProvider(target.id)).value, [group]);
    expect(
      (c.read(profilesActionProvider.notifier) as TestSourceProfilesAction)
          .touches,
      0,
    );
  });

  test('rejects binding to an unmanaged subscription config', () async {
    final c = container();
    await expectLater(
      c
          .read(nodeSourcesActionProvider.notifier)
          .attach(source.id, groupIds: {group.id}, nodeIds: {node.id}),
      throwsA(isA<MessageException>()),
    );
  });

  test('adds hundreds of subscriptions without a fixed count limit', () async {
    final sources = List.generate(
      250,
      (i) => Profile.normal(label: 'Source $i', url: 'https://example.com/$i'),
    );
    final c = container(sources: sources);
    await c
        .read(nodeSourcesActionProvider.notifier)
        .attach(
          target.id,
          groupIds: {group.id},
          subscriptionIds: sources.map((p) => p.id).toSet(),
        );
    expect(
      c.read(proxyGroupsProvider(target.id)).value!.single.use,
      sources.map((p) => p.realLabel).toList(),
    );
  });

  test(
    'creates a working manual and automatic group with a final routing rule',
    () async {
      final c = container();
      final id = await c
          .read(nodeSourcesActionProvider.notifier)
          .createProfile();
      c.listen(proxyGroupsProvider(id), (_, _) {});
      c.listen(profileRulesProvider(id), (_, _) {});
      final groups = c.read(proxyGroupsProvider(id)).value!;
      expect(groups.length, 2);
      expect(groups.last.type, GroupType.URLTest);
      expect(groups.last.url, defaultTestUrl);
      expect(groups.first.proxies, contains(groups.last.name));
      expect(
        groups.every(
          (g) => g.includeAllProviders == true && g.includeAllProxies == true,
        ),
        true,
      );
      expect(c.read(profileRulesProvider(id)).value, hasLength(1));
      expect(c.read(currentProfileIdProvider), isNull);
    },
  );
}
