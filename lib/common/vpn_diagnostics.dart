import 'dart:convert';
import 'dart:io';

String redactDiagnostic(String text) => text
    .replaceAll(
      RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false),
      '[URL]',
    )
    .replaceAll(
      RegExp(r'/private/var/[^\s"\x27]+|[A-Za-z]:\\[^\r\n]+'),
      '[PATH]',
    )
    .replaceAllMapped(
      RegExp(
        r'(token|password|passwd|secret|authorization|cookie|uuid|OwO)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}=[REDACTED]',
    );

class VpnDiagnosticSnapshot {
  const VpnDiagnosticSnapshot({
    this.peakBytes,
    this.sampledAt,
    this.stage,
    this.startupStage,
    this.startupDetail,
    this.startupAt,
  });

  final int? peakBytes;
  final DateTime? sampledAt;
  final String? stage;
  final String? startupStage;
  final String? startupDetail;
  final DateTime? startupAt;

  factory VpnDiagnosticSnapshot.parse(
    Map<String, dynamic> memory,
    Map<String, dynamic> startup,
  ) {
    final samples = memory['samples'];
    final sample = samples is List && samples.isNotEmpty && samples.last is Map
        ? samples.last as Map
        : const {};
    DateTime? date(Object? value, {int epoch = 0}) =>
        value is num && value.isFinite && value.abs() < 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(
            ((value + epoch) * 1000).round(),
            isUtc: true,
          ).toLocal()
        : null;
    return VpnDiagnosticSnapshot(
      peakBytes: switch (memory['peak-footprint-bytes']) {
        final num bytes when bytes.isFinite && bytes >= 0 => bytes.toInt(),
        _ => null,
      },
      sampledAt: date(sample['timestamp']),
      stage: sample['stage'] is String
          ? redactDiagnostic(sample['stage'] as String)
          : null,
      startupStage: startup['stage'] is String
          ? redactDiagnostic(startup['stage'] as String)
          : null,
      startupDetail: startup['detail'] is String
          ? redactDiagnostic(startup['detail'] as String)
          : null,
      startupAt: date(startup['date'], epoch: 978307200),
    );
  }
}

Future<Map<String, dynamic>> _readDiagnosticJson(File file) async {
  try {
    if (!await file.exists() || await file.length() > 256 * 1024)
      return const {};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FileSystemException {
    return const {};
  } on FormatException {
    return const {};
  }
}

Future<VpnDiagnosticSnapshot> readVpnDiagnostics(String home) async {
  final memory = await _readDiagnosticJson(File('$home/vpn-memory.json'));
  final startup = await _readDiagnosticJson(File('$home/vpn-startup.json'));
  return VpnDiagnosticSnapshot.parse(memory, startup);
}

Future<Map<String, int>> inspectGeoResources(String home) async {
  final files = <String, int>{};
  const names = ['GEOSITE.dat', 'GEOIP.dat', 'ASN.mmdb', 'GEOIP.metadb'];
  final directory = Directory(home);
  if (!await directory.exists()) return {for (final name in names) name: 0};
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    for (final wanted in names) {
      if (name.toLowerCase() == wanted.toLowerCase())
        files[wanted] = await entry.length();
    }
  }
  return {for (final name in names) name: files[name] ?? 0};
}
