import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/geo_asset.dart';
import 'package:fl_clash/common/vpn_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async { directory = await Directory.systemTemp.createTemp('vpn-diagnostics-'); });
  tearDown(() async { await directory.delete(recursive: true); });

  test('native timestamps use their distinct epochs and preserve recorded evidence', () {
    final snapshot = VpnDiagnosticSnapshot.parse({
      'peak-footprint-bytes': 49 * 1048576,
      'samples': [{'timestamp': 1794480000, 'stage': 'running'}],
    }, {'date': 816172800, 'stage': 'failed', 'detail': 'error https://example.com/?token=private'});
    expect(snapshot.peakBytes, 49 * 1048576);
    expect(snapshot.sampledAt!.toUtc().year, 2026);
    expect(snapshot.startupAt!.toUtc().year, 2026);
    expect(snapshot.stage, 'running');
    expect(snapshot.startupDetail, 'error [URL]');
  });

  test('missing and partially written diagnostic files leave the page usable', () async {
    await File('${directory.path}/vpn-memory.json').writeAsString('{partial');
    final snapshot = await readVpnDiagnostics(directory.path);
    expect(snapshot.peakBytes, isNull);
    expect(snapshot.startupDetail, isNull);
  });

  test('resource checks detect missing, empty and legacy mixed-case files', () async {
    await File('${directory.path}/GeoSite.dat').writeAsBytes([1, 2]);
    await File('${directory.path}/GEOIP.dat').writeAsBytes([]);
    final resources = await inspectGeoResources(directory.path);
    expect(resources['GEOSITE.dat'], 2);
    expect(resources['GEOIP.dat'], 0);
    expect(resources['ASN.mmdb'], 0);
  });

  test('geographic asset installation recovers empty files but preserves existing data', () async {
    final target = File('${directory.path}/GEOSITE.dat');
    await target.writeAsBytes([]);
    await ensureGeoAsset(target, (file) => file.writeAsBytes([1, 2, 3]));
    expect(await target.readAsBytes(), [1, 2, 3]);
    await ensureGeoAsset(target, (_) async => fail('Do not overwrite custom data'));
  });

  test('interrupted extraction cannot leave a partial geographic asset', () async {
    final target = File('${directory.path}/GEOSITE.dat');
    await expectLater(ensureGeoAsset(target, (file) async {
      await file.writeAsBytes([1]);
      throw const FileSystemException('interrupted');
    }), throwsA(isA<FileSystemException>()));
    expect(await target.exists(), isFalse);
    expect(await directory.list().toList(), isEmpty);
  });

  test('redaction removes URLs, private paths and common credentials', () {
    final report = redactDiagnostic('url=https://example.com/sub?token=abc password=secret uuid=123 /private/var/mobile/test');
    expect(report, isNot(contains('abc')));
    expect(report, isNot(contains('password=secret')));
    expect(report, isNot(contains('uuid=123')));
    expect(report, isNot(contains('/private/var')));
  });

  test('oversized native report is not loaded', () async {
    await File('${directory.path}/vpn-memory.json').writeAsString(jsonEncode({'padding': 'x' * 300000}));
    expect((await readVpnDiagnostics(directory.path)).peakBytes, isNull);
  });
}
