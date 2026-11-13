import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:fl_clash/common/vpn_log_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic export includes profiles and excludes unrelated private files', () async {
    final directory = await Directory.systemTemp.createTemp('vpn-export-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/app.log');
    await log.writeAsString('diagnostics');
    await File('${directory.path}/core-heap-pressure.pprof').writeAsBytes([1, 2, 3]);
    await File('${directory.path}/core-heap-pressure.pprof.json').writeAsString('{"id":"run"}');
    await File('${directory.path}/certificate.key').writeAsString('private');
    final oversized = await File('${directory.path}/core-heap-baseline.pprof').open(mode: FileMode.write);
    await oversized.truncate((2 << 20) + 1);
    await oversized.close();
    final archivePath = '${directory.path}/diagnostics.zip';
    await writeVpnDiagnosticArchive(home: directory.path, logPath: log.path, archivePath: archivePath);
    final archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
    expect(archive.files.map((file) => file.name).toSet(), {
      'FlClash.log', 'core-heap-pressure.pprof', 'core-heap-pressure.pprof.json',
    });
  });
}
