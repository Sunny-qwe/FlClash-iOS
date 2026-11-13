import 'dart:io';

import 'package:archive/archive_io.dart';

Future<void> writeVpnDiagnosticArchive({
  required String home,
  required String logPath,
  required String archivePath,
}) async {
  final encoder = ZipFileEncoder()..create(archivePath);
  try {
    await encoder.addFile(File(logPath), 'FlClash.log');
    for (final name in ['vpn-memory.json', 'vpn-memory.json.previous', 'vpn-startup.json', 'core-crash.log', 'core-crash.log.previous']) {
      final file = File('$home/$name');
      try {
        if (await file.exists() && await file.length() <= (256 << 10)) {
          await encoder.addFile(file, name);
        }
      } on FileSystemException {
        continue;
      }
    }
    for (final kind in ['baseline', 'pressure']) {
      for (final suffix in ['', '.previous', '.json', '.json.previous']) {
        final name = 'core-heap-$kind.pprof$suffix';
        final file = File('$home/$name');
        try {
          if (await file.exists() && await file.length() <= (2 << 20)) {
            await encoder.addFile(file, name);
          }
        } on FileSystemException {
          continue;
        }
      }
    }
  } finally {
    await encoder.close();
  }
}
