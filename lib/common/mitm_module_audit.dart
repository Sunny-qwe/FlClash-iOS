import 'dart:io';

import 'package:fl_clash/common/mitm_module.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

class MitmModuleAudit {
  const MitmModuleAudit({required this.rules, required this.scripts, required this.skipped, required this.hostnames, required this.missingResources});

  final int rules;
  final int scripts;
  final int skipped;
  final int hostnames;
  final int missingResources;

  bool get needsAttention => skipped > 0 || missingResources > 0 || rules == 0 && scripts == 0;
}

MitmModuleAudit _parseAudit((String, Map<String, String>, Map<String, String>) source) {
  final declared = parseMitmModule(source.$1, values: source.$2);
  final parsed = parseMitmModule(source.$1, values: source.$2, resources: source.$3);
  return MitmModuleAudit(
    rules: parsed.rules.length + parsed.urlRewrite.length + parsed.headerRewrite.length + parsed.bodyRewrite.length + parsed.mapLocal.length,
    scripts: parsed.script.length,
    skipped: parsed.skipped.length,
    hostnames: parsed.hostname.length + parsed.insertedHostname.length,
    missingResources: declared.resourceUrls.where((url) => !source.$3.containsKey(url)).length,
  );
}

Future<MitmModuleAudit> auditMitmModule(MitmModule module, String directory, String resourcesDirectory) async {
  final file = File(p.join(directory, module.fileName));
  if (await file.length() > 4 * 1024 * 1024) throw const FormatException('Module source exceeds 4 MiB');
  final resources = <String, String>{};
  for (final entry in module.resources.entries) {
    final resource = p.normalize(p.join(resourcesDirectory, entry.value));
    if (p.isWithin(resourcesDirectory, resource) && await File(resource).exists()) resources[entry.key] = entry.value;
  }
  return compute(_parseAudit, (await file.readAsString(), module.arguments, resources));
}
