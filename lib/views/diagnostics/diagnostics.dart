import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/vpn_diagnostics.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/logs.dart';
import 'package:fl_clash/views/resources.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_check.dart';
import 'module_audit.dart';

class DiagnosticsView extends ConsumerStatefulWidget {
  const DiagnosticsView({super.key});

  @override
  ConsumerState<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends ConsumerState<DiagnosticsView> {
  VpnDiagnosticSnapshot? _snapshot;
  Map<String, int> _resources = const {};
  String? _error;
  bool _loading = false;
  bool _repairing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final home = await appPath.homeDirPath;
      final snapshot = await readVpnDiagnostics(home);
      final resources = await inspectGeoResources(home);
      if (mounted)
        setState(() {
          _snapshot = snapshot;
          _resources = resources;
        });
    } catch (error) {
      if (mounted)
        setState(() => _error = redactDiagnostic(compactError(error)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    await globalState.safeRun(
      () => ref.read(logsProvider.notifier).exportLogs(),
      title: context.appLocalizations.exportLogs,
      silence: false,
    );
  }

  Future<void> _repairResources() async {
    if (_repairing) return;
    setState(() => _repairing = true);
    try {
      await globalState.safeRun(
        CoreController.initGeo,
        title: context.appLocalizations.repairGeoResources,
        silence: false,
      );
      if (mounted) await _refresh();
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final snapshot = _snapshot;
    final running = ref.watch(isStartProvider);
    final profile = ref.watch(currentProfileProvider);
    final modules = ref.watch(mitmModulesProvider).value;
    final logs = ref.read(logsProvider).list;
    final errors = logs
        .where(
          (log) =>
              log.logLevel == LogLevel.error ||
              log.logLevel == LogLevel.warning,
        )
        .toList()
        .reversed
        .take(8);
    return Scaffold(
      title: l.reliabilityCenter,
      isLoading: _loading || _repairing,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.sync,
          tooltip: l.sync,
          onPressed: _loading ? null : _refresh,
        ),
        IconButtonData(
          glyph: AppGlyphs.export,
          tooltip: l.exportLogs,
          onPressed: _export,
        ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.sectionsTopPadding,
          16,
          24 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ListItem(
                title: Text(l.status),
                subtitle: Text(running ? l.running : l.notRunning),
              ),
              ListItem(
                title: Text(l.profiles),
                subtitle: Text(profile?.realLabel ?? l.nullProfileDesc),
              ),
              ListItem(
                title: Text(l.mitmModules),
                subtitle: Text(
                  modules == null
                      ? l.loading
                      : '${modules.where((module) => module.enabled).length} / ${modules.length}',
                ),
              ),
            ],
          ),
          generateSection(
            items: [
              ListItem.open(
                leading: const GlyphIcon(AppGlyphs.proxies),
                title: Text(l.networkHealth),
                subtitle: Text(l.networkHealthDesc),
                widget: const NetworkHealthView(),
              ),
              ListItem.open(
                leading: const GlyphIcon(AppGlyphs.resources),
                title: Text(l.moduleAudit),
                subtitle: Text(l.moduleAuditDesc),
                widget: const ModuleAuditView(),
              ),
              ListItem.open(
                leading: const GlyphIcon(AppGlyphs.profiles),
                title: Text(l.configPreflight),
                subtitle: Text(l.configPreflightDesc),
                widget: const ConfigPreflightView(),
              ),
            ],
          ),
          if (system.isIOS)
            generateSection(
              title: l.vpnEvidence,
              footer: l.vpnEvidenceDesc,
              items: [
                ListItem(
                  title: Text(l.vpnPeakMemory),
                  subtitle: Text(switch (snapshot?.peakBytes) {
                    final bytes? =>
                      '${(bytes / 1048576).toStringAsFixed(1)} MiB',
                    _ => l.noDiagnosticRecord,
                  }),
                ),
                ListItem(
                  title: Text(l.vpnLastSample),
                  subtitle: Text(
                    snapshot?.sampledAt?.toString() ?? l.noDiagnosticRecord,
                  ),
                ),
                ListItem(
                  title: Text(l.vpnLastStage),
                  subtitle: Text(snapshot?.stage ?? l.noDiagnosticRecord),
                ),
                if (snapshot?.startupStage case final stage?)
                  ListItem(
                    title: Text(l.vpnStartupRecord),
                    subtitle: Text(
                      '$stage\n${snapshot?.startupAt ?? '—'}${snapshot?.startupDetail == null ? '' : '\n${snapshot!.startupDetail}'}',
                    ),
                  ),
              ],
            ),
          generateSection(
            title: l.geoResourcesCheck,
            footer: l.geoResourcesCheckDesc,
            items: [
              for (final entry in _resources.entries)
                ListItem(
                  title: Text(entry.key),
                  subtitle: Text(
                    entry.value > 0 ? '${entry.value} B' : l.resourceMissing,
                  ),
                ),
              ListItem(
                title: Text(l.repairGeoResources),
                subtitle: Text(l.repairGeoResourcesDesc),
                onTap: _loading || _repairing ? null : _repairResources,
              ),
              ListItem.open(
                title: Text(l.resources),
                widget: const ResourcesView(),
              ),
            ],
          ),
          if (_error != null)
            ListItem(title: Text(l.error), subtitle: Text(_error!)),
          generateSection(
            title: l.recentIssues,
            items: [
              if (errors.isEmpty) ListItem(title: Text(l.noDiagnosticRecord)),
              for (final log in errors)
                ListItem(
                  title: Text(log.dateTime),
                  subtitle: Text(
                    redactDiagnostic(log.payload),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ListItem.open(title: Text(l.logs), widget: const LogsView()),
            ],
          ),
        ],
      ),
    );
  }
}
