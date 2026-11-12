import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/mitm_module_audit.dart';
import 'package:fl_clash/common/vpn_diagnostics.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/config/mitm_modules.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ModuleAuditView extends ConsumerStatefulWidget {
  const ModuleAuditView({super.key});

  @override
  ConsumerState<ModuleAuditView> createState() => _ModuleAuditViewState();
}

class _ModuleAuditViewState extends ConsumerState<ModuleAuditView> {
  final _reports = <int, MitmModuleAudit>{};
  final _errors = <int, String>{};
  bool _busy = false;
  int _revision = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    ref.listenManual(mitmModulesProvider, (_, _) => unawaited(_refresh()));
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _loadError = null;
      _reports.clear();
      _errors.clear();
    });
    try {
      final modules = await ref.read(mitmModulesProvider.future);
      final directory = await appPath.mitmModulesDirPath;
      final resources = await appPath.mitmResourcesDirPath;
      for (final module in modules) {
        if (!mounted || revision != _revision) return;
        try {
          final report = await auditMitmModule(module, directory, resources);
          if (!mounted || revision != _revision) return;
          setState(() => _reports[module.id] = report);
        } catch (error) {
          if (!mounted || revision != _revision) return;
          setState(
            () => _errors[module.id] = redactDiagnostic(compactError(error)),
          );
        }
      }
    } catch (error) {
      if (mounted && revision == _revision)
        setState(() => _loadError = redactDiagnostic(compactError(error)));
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final state = ref.watch(mitmModulesProvider);
    final modules = state.value ?? const <MitmModule>[];
    return Scaffold(
      title: l.moduleAudit,
      isLoading: _busy,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.sync,
          tooltip: l.sync,
          onPressed: _busy ? null : _refresh,
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
            footer: l.moduleAuditLimits,
            items: [
              ListItem.open(
                title: Text(l.mitmModules),
                subtitle: Text(l.moduleAuditDesc),
                widget: const MitmModulesView(),
              ),
            ],
          ),
          if (state.hasError)
            ListItem(
              title: Text(l.error),
              subtitle: Text(redactDiagnostic(compactError(state.error!))),
            ),
          if (_loadError != null)
            ListItem(title: Text(l.error), subtitle: Text(_loadError!)),
          if (modules.isEmpty && !state.isLoading)
            ListItem(title: Text(l.noDiagnosticRecord)),
          for (final module in modules)
            generateSection(
              title: module.name,
              items: [
                ListItem(
                  title: Text(l.status),
                  subtitle: Text(module.enabled ? l.enabled : l.disabled),
                ),
                if (_errors[module.id] case final error?)
                  ListItem(title: Text(l.error), subtitle: Text(error)),
                if (_reports[module.id] case final report?) ...[
                  ListItem(
                    title: Text(l.moduleParseResult),
                    subtitle: Text(
                      report.needsAttention
                          ? l.moduleNeedsAttention
                          : l.moduleParsePassed,
                    ),
                  ),
                  ListItem(
                    title: Text(l.moduleRuleCount),
                    trailing: Text('${report.rules}'),
                  ),
                  ListItem(
                    title: Text(l.moduleScriptCount),
                    trailing: Text('${report.scripts}'),
                  ),
                  ListItem(
                    title: Text(l.moduleSkippedCount),
                    trailing: Text('${report.skipped}'),
                  ),
                  ListItem(
                    title: Text(l.moduleMissingCount),
                    trailing: Text('${report.missingResources}'),
                  ),
                  ListItem(
                    title: Text(l.moduleHostCount),
                    trailing: Text('${report.hostnames}'),
                  ),
                ],
                ListItem.open(
                  title: Text(l.moduleInspectDetails),
                  widget: MitmModuleView(id: module.id),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
