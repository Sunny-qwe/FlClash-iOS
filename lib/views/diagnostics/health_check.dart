import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/common/vpn_diagnostics.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/resources.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkHealthView extends ConsumerStatefulWidget {
  const NetworkHealthView({super.key});

  @override
  ConsumerState<NetworkHealthView> createState() => _NetworkHealthViewState();
}

class _NetworkHealthViewState extends ConsumerState<NetworkHealthView> {
  final _results = <({String title, String detail, bool passed})>[];
  bool _busy = false;
  bool _stale = false;
  String? _error;
  DateTime? _checkedAt;
  RouteState? _checkedRoute;
  late final RouteTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = ref.read(routeTrackerProvider.notifier)..attach();
  }

  @override
  void dispose() {
    _tracker.detach();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    final l = context.appLocalizations;
    final core = ref.read(coreHandlerProvider);
    final route = ref.read(routeTrackerProvider);
    setState(() { _busy = true; _stale = false; _results.clear(); _error = null; _checkedAt = DateTime.now(); _checkedRoute = route; });
    try {
      for (final outbound in [directOutbound, routedOutbound]) {
        if (!mounted) return;
        final title = outbound == directOutbound ? l.directExitCheck : l.routedExitCheck;
        try {
        final result = await lookupOutboundIp(core, outbound, timeout: const Duration(seconds: 10));
        final ip = parseOutboundIp(result);
        if (!mounted) return;
        final hide = ref.read(appSettingProvider).hideIp;
        setState(() => _results.add((
          title: title,
          detail: ip == null ? l.serviceFailed : '${hide ? '••••••••' : ip.ip}${result.chains.isEmpty ? '' : '\n${result.chains.join(' → ')}'}',
          passed: ip != null,
        )));
        } catch (error) {
          if (!mounted) return;
          setState(() => _results.add((title: title, detail: redactDiagnostic(compactError(error)), passed: false)));
        }
      }
      for (final target in [ServiceTarget.google, ServiceTarget.youtube]) {
        if (!mounted) return;
        try {
        final results = await checkServices(core, targets: [target], timeout: const Duration(seconds: 10));
        if (!mounted) return;
        final result = results[target];
        setState(() => _results.add((
          title: target.label,
          detail: result == null ? l.serviceFailed : '${result.status == ServiceProbeStatus.available ? l.serviceAvailable : result.status.id}${result.delay == null ? '' : ' · ${result.delay} ms'}${result.chains.isEmpty ? '' : '\n${result.chains.join(' → ')}'}',
          passed: result?.status == ServiceProbeStatus.available,
        )));
        } catch (error) {
          if (!mounted) return;
          setState(() => _results.add((title: target.label, detail: redactDiagnostic(compactError(error)), passed: false)));
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = redactDiagnostic(compactError(error)));
    } finally {
      if (mounted) setState(() { _busy = false; _stale = route != ref.read(routeTrackerProvider) || !ref.read(isStartProvider); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final running = ref.watch(isStartProvider);
    final stale = _stale || _checkedRoute != null && (_checkedRoute != ref.watch(routeTrackerProvider) || !running);
    return Scaffold(
      title: l.networkHealth,
      isLoading: _busy,
      iconActions: [IconButtonData(glyph: AppGlyphs.sync, tooltip: l.runHealthCheck, onPressed: _busy || !running ? null : _check)],
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.sectionsTopPadding, 16, 24 + context.bottomInset),
        children: [
          generateSection(footer: l.networkHealthLimits, items: [
            ListItem(title: Text(l.runHealthCheck), subtitle: Text(running ? l.networkHealthDesc : l.healthRequiresVpn), onTap: _busy || !running ? null : _check),
            if (_checkedAt != null) ListItem(title: Text(l.vpnLastSample), subtitle: Text(_checkedAt.toString())),
          ]),
          if (stale) ListItem(title: Text(l.healthRouteChanged), subtitle: Text(l.runHealthCheck)),
          generateSection(items: [
            for (final result in _results) ListItem(title: Text(result.title), subtitle: Text(stale ? l.healthRouteChanged : result.detail), trailing: Text(stale ? '—' : result.passed ? '✓' : '!')),
            if (_error != null) ListItem(title: Text(l.error), subtitle: Text(_error!)),
          ]),
        ],
      ),
    );
  }
}

class ConfigPreflightView extends ConsumerStatefulWidget {
  const ConfigPreflightView({super.key});

  @override
  ConsumerState<ConfigPreflightView> createState() => _ConfigPreflightViewState();
}

class _ConfigPreflightViewState extends ConsumerState<ConfigPreflightView> {
  bool _busy = false;
  String? _result;
  int? _profileId;

  Future<void> _check() async {
    if (_busy) return;
    final l = context.appLocalizations;
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    setState(() { _busy = true; _result = null; _profileId = profile.id; });
    try {
      final yaml = await ref.read(setupActionProvider.notifier).buildProfileWithId(profile.id);
      if (yaml.trim().isEmpty) throw const FormatException('Empty generated configuration');
      final issue = await ref.read(coreHandlerProvider).validateConfigWithData(utf8.encode(yaml));
      if (mounted) setState(() => _result = issue == null ? l.configPreflightPassed : redactDiagnostic(issue));
    } catch (error) {
      if (mounted) setState(() => _result = redactDiagnostic(compactError(error)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      title: l.configPreflight,
      isLoading: _busy,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.sectionsTopPadding, 16, 24 + context.bottomInset),
        children: [
          generateSection(footer: l.configPreflightLimits, items: [
            ListItem(title: Text(profile?.realLabel ?? l.nullProfileDesc), subtitle: Text(l.configPreflightDesc)),
            ListItem(title: Text(l.runHealthCheck), onTap: _busy || profile == null ? null : _check),
            if (_result != null) ListItem(title: Text(l.status), subtitle: Text(_profileId == profile?.id ? _result! : l.healthRouteChanged)),
          ]),
          generateSection(footer: l.configProtectionDesc, items: [
            ListItem(title: Text(l.configProtection)),
            ListItem.open(title: Text(l.resources), subtitle: Text(l.geoResourcesCheckDesc), widget: const ResourcesView()),
          ]),
        ],
      ),
    );
  }
}
