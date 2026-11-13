import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'custom/custom.dart';
import 'custom/custom_proxies.dart';
import 'edit.dart';

class NodeSourcesView extends ConsumerStatefulWidget {
  const NodeSourcesView({super.key, this.profileId});

  final int? profileId;

  @override
  ConsumerState<NodeSourcesView> createState() => _NodeSourcesViewState();
}

class _NodeSourcesViewState extends ConsumerState<NodeSourcesView> {
  bool _busy = false;
  Set<int>? _groupIds;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await globalState.safeRun(action, silence: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Profile? profile) async {
    if (profile?.type != ProfileType.custom) {
      if (profile != null) {
        final confirmed = await dialogs.showMessage(
          context: context,
          message: TextSpan(text: context.appLocalizations.nodeSourcesCopyTip),
          confirmText: context.appLocalizations.copy,
        );
        if (confirmed != true || !mounted) return;
      }
      final id = await ref
          .read(nodeSourcesActionProvider.notifier)
          .createProfile(source: profile);
      if (!mounted) return;
      await BaseNavigator.push(context, NodeSourcesView(profileId: id));
    } else {
      await BaseNavigator.push(
        context,
        NodeSourcesView(profileId: profile!.id),
      );
    }
  }

  Set<int> _selectedGroups(List<ProxyGroup> groups) =>
      (_groupIds ??
              groups
                  .where(
                    (g) =>
                        g.includeAllProviders == true ||
                        g.includeAllProxies == true ||
                        (g.use?.isNotEmpty ?? false),
                  )
                  .map((g) => g.id)
                  .toSet())
          .intersection(groups.map((g) => g.id).toSet());

  Future<Set<int>?> _choose(
    String title,
    List<({int id, String label})> items, {
    Set<int> selected = const {},
  }) => BaseNavigator.push<Set<int>>(
    context,
    _SourcePicker(title: title, items: items, selected: selected),
  );

  Future<void> _attach({
    Set<int> sources = const {},
    Set<int> nodes = const {},
  }) async {
    final groups = await ref.read(
      proxyGroupsProvider(widget.profileId!).future,
    );
    await ref
        .read(nodeSourcesActionProvider.notifier)
        .attach(
          widget.profileId!,
          groupIds: _selectedGroups(groups),
          subscriptionIds: sources,
          nodeIds: nodes,
        );
  }

  Future<void> _subscriptions() async {
    final l = context.appLocalizations;
    final links = await showNamedUrlsForm(
      context,
      title: l.nodeSourcesAddSubscription,
      withAgeSecretKey: true,
    );
    if (links == null || links.isEmpty || !mounted) return;
    final actions = ref.read(nodeSourcesActionProvider.notifier);
    final profileId = widget.profileId!;
    final groupIds = _selectedGroups(
      ref.read(proxyGroupsProvider(profileId)).value!,
    );
    final failures = <UpdatingMessage>[];
    final saved = <int>{};
    for (final link in links) {
      try {
        final profile = await actions.addSubscription(
          url: link.url,
          label: link.label,
          ageSecretKey: link.ageSecretKey,
        );
        saved.add(profile.id);
      } catch (error) {
        failures.add(
          UpdatingMessage(
            label: link.label.isEmpty ? l.profiles : link.label,
            message: userFacingErrorMessage(error, l),
          ),
        );
      }
    }
    if (saved.isNotEmpty)
      await actions.attach(
        profileId,
        groupIds: groupIds,
        subscriptionIds: saved,
      );
    if (mounted) dialogs.showFailures(failures);
  }

  Future<void> _existingSubscriptions() async {
    final ids = await _choose(context.appLocalizations.nodeSourcesExisting, [
      for (final profile in ref.read(profilesProvider))
        if (profile.type != ProfileType.custom)
          (id: profile.id, label: profile.realLabel),
    ]);
    if (mounted && ids != null && ids.isNotEmpty) await _attach(sources: ids);
  }

  Future<void> _manual({bool existing = false}) async {
    final before = await ref.read(customProxiesProvider.future);
    if (!mounted) return;
    Set<int>? ids;
    if (existing) {
      ids = await _choose(context.appLocalizations.nodeSourcesExistingNodes, [
        for (final node in before) (id: node.id, label: node.name),
      ]);
    } else {
      final previous = before.map((node) => node.id).toSet();
      await BaseNavigator.push(context, const CustomProxiesView());
      if (!mounted) return;
      ids = ref
          .read(customProxiesProvider)
          .value!
          .where((node) => !previous.contains(node.id))
          .map((node) => node.id)
          .toSet();
    }
    if (ids != null && ids.isNotEmpty) await _attach(nodes: ids);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final profiles = ref.watch(profilesProvider);
    final id = widget.profileId;
    if (id == null) {
      return Scaffold(
        title: l.nodeSourcesTitle,
        isLoading: _busy,
        body: PrismListView(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            24 + context.bottomInset,
          ),
          itemCount: profiles.length + 1,
          itemBuilder: (_, index) => index == 0
              ? ListItem(
                  leading: const GlyphIcon(AppGlyphs.addCircle),
                  title: Text(l.addProfile),
                  subtitle: Text(l.nodeSourcesDesc),
                  onTap: _busy ? null : () => _run(() => _open(null)),
                )
              : ListItem(
                  title: Text(profiles[index - 1].realLabel),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: _busy
                      ? null
                      : () => _run(() => _open(profiles[index - 1])),
                ),
        ),
      );
    }
    final profile = profiles.getProfile(id);
    final groups = ref.watch(proxyGroupsProvider(id)).value;
    final nodes = ref.watch(customProxiesProvider).value;
    final selected = groups == null ? <int>{} : _selectedGroups(groups);
    final uses = {for (final group in groups ?? <ProxyGroup>[]) ...?group.use};
    final named = {
      for (final group in groups ?? <ProxyGroup>[]) ...?group.proxies,
    };
    final attached = profiles
        .where(
          (p) => p.type != ProfileType.custom && uses.contains(p.realLabel),
        )
        .toList();
    final manual =
        nodes?.where((node) => named.contains(node.name)).length ?? 0;
    final canAdd = !_busy && selected.isNotEmpty;
    return Scaffold(
      title: l.nodeSourcesTitle,
      isLoading: _busy,
      body: NullStatusSwitcher(
        isLoading: groups == null || nodes == null,
        isEmpty: profile == null,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                context.sectionsTopPadding,
                16,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    generateSection(
                      items: [
                        ListItem(
                          title: Text(profile?.realLabel ?? l.profiles),
                          subtitle: Text(l.nodeSourcesDesc),
                          trailing: const GlyphIcon(AppGlyphs.chevronForward),
                          onTap: _busy
                              ? null
                              : () => BaseNavigator.push(
                                  context,
                                  CustomProfileView(profileId: id),
                                ),
                        ),
                        ListItem(
                          title: Text(l.nodeSourcesGroups),
                          subtitle: Text(
                            selected.isEmpty
                                ? l.nodeSourcesChooseGroups
                                : '${selected.length} / ${groups?.length ?? 0}',
                          ),
                          trailing: const GlyphIcon(AppGlyphs.chevronForward),
                          onTap: _busy
                              ? null
                              : () async {
                                  final result =
                                      await _choose(l.nodeSourcesGroups, [
                                        for (final group
                                            in groups ?? <ProxyGroup>[])
                                          (id: group.id, label: group.name),
                                      ], selected: selected);
                                  if (result != null && mounted)
                                    setState(() => _groupIds = result);
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    generateSection(
                      items: [
                        ListItem(
                          leading: const GlyphIcon(AppGlyphs.addCircle),
                          title: Text(l.nodeSourcesAddSubscription),
                          subtitle: Text(l.batchUrlInputTip),
                          onTap: canAdd ? () => _run(_subscriptions) : null,
                        ),
                        ListItem(
                          title: Text(l.nodeSourcesExisting),
                          onTap: canAdd
                              ? () => _run(_existingSubscriptions)
                              : null,
                        ),
                        ListItem(
                          leading: const GlyphIcon(AppGlyphs.proxies),
                          title: Text(l.nodeSourcesManual),
                          onTap: canAdd ? () => _run(() => _manual()) : null,
                        ),
                        ListItem(
                          title: Text(l.nodeSourcesExistingNodes),
                          subtitle: Text('$manual'),
                          onTap: canAdd
                              ? () => _run(() => _manual(existing: true))
                              : null,
                        ),
                        ListItem(
                          title: Text(l.applyNow),
                          onTap: _busy
                              ? null
                              : () => _run(() async {
                                  ref
                                          .read(
                                            currentProfileIdProvider.notifier,
                                          )
                                          .value =
                                      id;
                                  await ref
                                      .read(setupActionProvider.notifier)
                                      .applyProfile(force: true);
                                }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + context.bottomInset),
              sliver: SliverPrismList(
                itemCount: attached.length,
                itemBuilder: (_, index) => ListItem(
                  title: Text(attached[index].realLabel),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: _busy
                      ? null
                      : () => BaseNavigator.push(
                          context,
                          EditProfileView(profile: attached[index]),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({
    required this.title,
    required this.items,
    required this.selected,
  });
  final String title;
  final List<({int id, String label})> items;
  final Set<int> selected;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  late final _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final items = widget.items
        .where((item) => item.label.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      title: widget.title,
      searchState: AppBarSearchState(
        onSearch: (value) => setState(() => _query = value.toLowerCase()),
      ),
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: l.save,
        onPressed: () => Navigator.of(context).pop(_selected),
      ),
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.selectAll,
          tooltip: l.selectAll,
          onPressed: () => setState(() {
            if (items.every((item) => _selected.contains(item.id))) {
              _selected.removeAll(items.map((item) => item.id));
            } else {
              _selected.addAll(items.map((item) => item.id));
            }
          }),
        ),
      ],
      body: Builder(
        builder: (context) => NullStatusSwitcher(
          isEmpty: items.isEmpty,
          child: PrismListView(
            padding: EdgeInsets.fromLTRB(
              16,
              context.contentTopPadding,
              16,
              24 + context.bottomInset,
            ),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              void toggle() => setState(() {
                if (!_selected.add(item.id)) _selected.remove(item.id);
              });
              return ListItem(
                title: Text(item.label),
                onTap: toggle,
                trailing: Checkbox(
                  value: _selected.contains(item.id),
                  onChanged: (_) => toggle(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
