import 'dart:io';

import 'package:fl_clash/common/mitm_module_audit.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MitmModule module;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('module-audit-');
    module = MitmModule(id: 1, name: 'test', lastUpdateTime: DateTime.now());
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'rule-only modules have useful rules without claiming script execution',
    () async {
      await File('${directory.path}/1.txt').writeAsString('''
[Rule]
DOMAIN,ads.example.com,REJECT
[MITM]
hostname=api.example.com
''');
      final report = await auditMitmModule(
        module,
        directory.path,
        directory.path,
      );
      expect(report.rules, 1);
      expect(report.scripts, 0);
      expect(report.hostnames, 1);
      expect(report.needsAttention, isFalse);
    },
  );

  test(
    'missing downloaded resources are detected even when the database names them',
    () async {
      await File('${directory.path}/1.txt').writeAsString('''
[Script]
test=type=http-response,pattern=^https://example.com,script-path=https://example.com/test.js
''');
      module = module.copyWith(
        resources: {'https://example.com/test.js': 'cached.js'},
      );
      final missing = await auditMitmModule(
        module,
        directory.path,
        directory.path,
      );
      expect(missing.missingResources, 1);
      await File('${directory.path}/cached.js').writeAsString(r'$done({});');
      final ready = await auditMitmModule(
        module,
        directory.path,
        directory.path,
      );
      expect(ready.missingResources, 0);
      expect(ready.scripts, 1);
    },
  );

  test(
    'a missing source file is an error instead of a successful empty module',
    () async {
      await expectLater(
        auditMitmModule(module, directory.path, directory.path),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
