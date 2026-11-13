part of '../action.dart';

@Riverpod(keepAlive: true)
class NodeSourcesAction extends _$NodeSourcesAction {
  @override
  void build() {}

  Future<int> createProfile({Profile? source}) async {
    final actions = ref.read(profilesActionProvider.notifier);
    final l = currentAppLocalizations;
    final profile = Profile.custom(
      label: source == null
          ? l.visualConfig
          : '${source.realLabel} (${l.copy})',
    );
    final config = source == null
        ? null
        : await actions.readCustomImport(
            profile.id,
            utf8.encode(
              await ref
                  .read(setupActionProvider.notifier)
                  .buildProfileWithId(source.id),
            ),
          );
    if (config != null && config.droppedSubRules > 0) {
      throw MessageException(
        l.customImportDroppedSubRules(
          config.droppedSubRules,
          config.droppedSubRules.compact,
        ),
      );
    }
    ref.read(profilesProvider.notifier).put(profile);
    await ref.read(profilesProvider.notifier).flushWrites();
    final groupsLease = ref.listen(proxyGroupsProvider(profile.id), (_, _) {});
    final rulesLease = ref.listen(profileRulesProvider(profile.id), (_, _) {});
    final nodesLease = config == null ? null : ref.listen(customProxiesProvider, (_, _) {});
    final dialersLease = config == null ? null : ref.listen(proxyDialersProvider(profile.id), (_, _) {});
    try {
      await ref.read(proxyGroupsProvider(profile.id).future);
      await ref.read(profileRulesProvider(profile.id).future);
      if (config != null) {
        await ref.read(customProxiesProvider.future);
        await ref.read(proxyDialersProvider(profile.id).future);
        await actions.importCustomProfile(profile.id, config);
        await ref.read(customProxiesProvider.notifier).flushWrites();
        await ref.read(proxyDialersProvider(profile.id).notifier).flushWrites();
      } else {
        ref.read(proxyGroupsProvider(profile.id).notifier).setAll([
          ProxyGroup(
            id: snowflake.id,
            name: l.nodeSourcesManualGroup,
            type: GroupType.Selector,
            proxies: [l.nodeSourcesAutoGroup, 'DIRECT'],
            includeAllProviders: true,
            includeAllProxies: true,
          ),
          ProxyGroup(
            id: snowflake.id,
            name: l.nodeSourcesAutoGroup,
            type: GroupType.URLTest,
            includeAllProviders: true,
            includeAllProxies: true,
            emptyFallback: 'REJECT',
            url: defaultTestUrl,
            interval: 600,
            tolerance: 50,
            lazy: true,
          ),
        ]);
        ref.read(profileRulesProvider(profile.id).notifier).setAll([
          Rule.parse('MATCH,${l.nodeSourcesManualGroup}', id: snowflake.id),
        ]);
      }
      await ref.read(proxyGroupsProvider(profile.id).notifier).flushWrites();
      await ref.read(profileRulesProvider(profile.id).notifier).flushWrites();
      await ref.read(profilesProvider.notifier).flushWrites();
      actions.putProfile(ref.read(profilesProvider).getProfile(profile.id)!);
      return profile.id;
    } finally {
      groupsLease.close();
      rulesLease.close();
      nodesLease?.close();
      dialersLease?.close();
    }
  }

  Future<Profile> addSubscription({
    required String url,
    String label = '',
    String ageSecretKey = '',
  }) async {
    final link = unwrapInstallConfigUrl(url.trim());
    if (!link.isUrl)
      throw MessageException(currentAppLocalizations.invalidLinkTip);
    final existing = ref
        .read(profilesProvider)
        .where(
          (profile) =>
              profile.type == ProfileType.url &&
              profile.url == link &&
              profile.ageSecretKey == ageSecretKey,
        )
        .firstOrNull;
    if (existing != null && await (await existing.file).length() > 0) {
      await ref.read(coreHandlerProvider).prepareProxyProvider(existing.id);
      return existing;
    }
    final saved =
        await (existing ??
                Profile.normal(
                  label: label,
                  url: link,
                ).copyWith(ageSecretKey: ageSecretKey))
            .update(
              validate: (path, key) =>
                  ref.read(coreHandlerProvider).validateProfile(path, key),
            );
    await ref.read(coreHandlerProvider).prepareProxyProvider(saved.id);
    ref.read(profilesActionProvider.notifier).putProfile(saved);
    await ref.read(profilesProvider.notifier).flushWrites();
    return ref.read(profilesProvider).getProfile(saved.id)!;
  }

  Future<void> attach(
    int profileId, {
    required Set<int> groupIds,
    Set<int> subscriptionIds = const {},
    Set<int> nodeIds = const {},
  }) async {
    final profile = ref.read(profilesProvider).getProfile(profileId);
    if (profile?.type != ProfileType.custom) {
      throw MessageException(currentAppLocalizations.importConfigInvalid);
    }
    final groupsLease = ref.listen(proxyGroupsProvider(profileId), (_, _) {});
    final nodesLease = ref.listen(customProxiesProvider, (_, _) {});
    try {
      await ref.read(proxyGroupsProvider(profileId).future);
      await ref.read(customProxiesProvider.future);
      final groups = ref.read(proxyGroupsProvider(profileId)).value!;
      if (groupIds.isEmpty ||
          !groups.map((group) => group.id).toSet().containsAll(groupIds)) {
        throw MessageException(currentAppLocalizations.nodeSourcesChooseGroups);
      }
      final subscriptions = ref
          .read(profilesProvider)
          .where(
            (item) =>
                subscriptionIds.contains(item.id) &&
                item.type != ProfileType.custom,
          )
          .toList();
      final nodes = ref
          .read(customProxiesProvider)
          .value!
          .where((item) => nodeIds.contains(item.id))
          .toList();
      if (subscriptions.length != subscriptionIds.length ||
          nodes.length != nodeIds.length) {
        throw MessageException(currentAppLocalizations.importConfigInvalid);
      }
      final notifier = ref.read(proxyGroupsProvider(profileId).notifier);
      var changed = false;
      for (final group in groups) {
        if (!groupIds.contains(group.id)) continue;
        final next = group.copyWith(
          use: subscriptions.isEmpty
              ? group.use
              : {
                  ...?group.use,
                  for (final source in subscriptions) source.realLabel,
                }.toList(),
          proxies: nodes.isEmpty
              ? group.proxies
              : {
                  ...?group.proxies,
                  for (final node in nodes) node.name,
                }.toList(),
        );
        if (next == group) continue;
        notifier.put(next);
        changed = true;
      }
      if (!changed) return;
      await notifier.flushWrites();
      ref.read(profilesActionProvider.notifier).touchProfile(profileId);
      await ref.read(profilesProvider.notifier).flushWrites();
      if (ref.read(currentProfileIdProvider) == profileId) {
        ref.read(setupActionProvider.notifier).autoApplyProfile();
      }
    } finally {
      groupsLease.close();
      nodesLease.close();
    }
  }

  Future<Set<int>> importShareLinks(String content) async {
    final links = content.split(RegExp(r'\s+')).where((line) => line.isShareLink).toList();
    final core = ref.read(coreHandlerProvider);
    if (links.isEmpty) throw MessageException(currentAppLocalizations.shareLinksInvalid);
    final decoded = await core.decodeShareLinks(links);
    if (decoded.any((nodes) => nodes.isEmpty)) {
      throw MessageException(currentAppLocalizations.shareLinksInvalid);
    }
    final lease = ref.listen(customProxiesProvider, (_, _) {});
    try {
      final previous = await ref.read(customProxiesProvider.future);
      final taken = {...reservedProxyNames, ...previous.map((node) => node.name), ...await ref.read(customGroupNamesProvider.future)};
      final nodes = <CustomProxy>[];
      for (final definitions in decoded) {
        for (final definition in definitions) {
          final name = uniqueLabelFor(definition['name']?.toString() ?? '', fallback: 'Proxy', taken: taken.contains);
          taken.add(name);
          nodes.add(CustomProxy.fromDefinition({...definition, 'name': name}));
        }
      }
      final issues = await core.validateProxies(nodes.map((node) => node.definition).toList());
      if (issues.isNotEmpty) throw MessageException(issues.values.first);
      final notifier = ref.read(customProxiesProvider.notifier);
      notifier.putAll(nodes);
      await notifier.flushWrites();
      return nodes.map((node) => node.id).toSet();
    } finally {
      lease.close();
    }
  }
}
