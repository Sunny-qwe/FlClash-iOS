import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart' show join;

abstract final class MitmStore {
  static const defaultCertificate = MitmCertificate(
    pem: '''-----BEGIN CERTIFICATE-----
MIIDRjCCAi6gAwIBAgIUFeN36sccj9fcJAMCFwaQCmkvSMYwDQYJKoZIhvcNAQEL
BQAwOzELMAkGA1UEBhMCQ04xEDAOBgNVBAoMB0ZsQ2xhc2gxGjAYBgNVBAMMEUZs
Q2xhc2ggQ0EgKFJvb3QpMB4XDTI2MTEwOTAxMDIwNVoXDTQxMTEwNjAxMDIwNVow
OzELMAkGA1UEBhMCQ04xEDAOBgNVBAoMB0ZsQ2xhc2gxGjAYBgNVBAMMEUZsQ2xh
c2ggQ0EgKFJvb3QpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA26no
LOHT0tTRFBiP1YGYtIux33k+uvlDHSJGz1D8t2q3U6FnIABYcK/SGobE84Avt/SH
Xwef5h+ZHfTdajfHhwWG0FQXJaWqLybrtcPd0kkqqFk6w92082+FP7DnThf7HNu/
SNf0CafshvrNrSiir3bEpK5cri6QHpkunxN3272s1NB36GQhzI67BJb80JsF9I90
YAE0H2Mo502CyV/JJHJYOVwBrl3C0FqmCVpBuoDPAsCudb/EGvT+nM9S+3C/G3B+
rw8V51psRyA9QsjM69QpP4ttzqqotS75Oph0ww2IgDJtLsLTBEYvKSjrMpn+n+HL
ryMV8U9T7M/bC2O8yQIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB
/wQEAwIBhjAdBgNVHQ4EFgQU0hqqd2olFL/torKkP+eDQMiOVB0wDQYJKoZIhvcN
AQELBQADggEBADNkHFulHAuREz8s1dhNkH1tQlaKeKT/trmg7tcqdiVG1sg/2l5e
Xgj0NzhpUoWvZf/ARbQCQFhL/zeZJyDsQFca6P4PVsd9MkWYr3AoNOQKCSnngOUq
Yduzz/65vZg7Hrb0nnX0Jbw55vwp27cGjMIyNsprEGrT+53qEIzPR25wxtM0VpLF
iU8oQuqC8ITZ/H/Nf3C2labs93sShKX2GhkPmbFWFiJbXvExM7Ig6z6GPib1un/g
7DV+5FEJAXhV52A4PCO/Zep6aL8hP7qM1MgInAqxBuNBSCCPNFr17MKxv4ZV8omf
B+qnzI7cU0cvfr2epwk69ttdEEOfUkvGbAE=
-----END CERTIFICATE-----
''',
    fingerprint:
        '5E:60:15:D1:CE:5F:AC:30:FC:E6:78:30:9B:13:8F:15:DE:BF:BC:8A:BC:07:74:57:A0:BB:DD:1C:C4:6D:96:2C',
    subject: 'FlClash CA (Root)',
    notBefore: MitmStore._defaultNotBefore,
    notAfter: MitmStore._defaultNotAfter,
  );

  static final _defaultNotBefore = DateTime.utc(2026, 11, 9, 1, 2, 5);
  static final _defaultNotAfter = DateTime.utc(2041, 11, 6, 1, 2, 5);

  static Future<String> get _caJsonPath async {
    final home = await appPath.homeDirPath;
    final dir = Directory(join(home, mitmDirectoryName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return join(dir.path, 'ca.json');
  }

  static Future<MitmCertificate> getOrCreateCertificate() async {
    try {
      final path = await _caJsonPath;
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return MitmCertificate.fromJson(json);
      }
      // Initialize with default root certificate
      await saveCertificate(defaultCertificate);
      return defaultCertificate;
    } catch (_) {
      return defaultCertificate;
    }
  }

  static Future<void> saveCertificate(MitmCertificate cert) async {
    try {
      final path = await _caJsonPath;
      final file = File(path);
      await file.safeWriteAsString(jsonEncode(cert.toJson()));

      // Also save .crt file for easy export / sharing
      final crtFile = File(join(file.parent.path, mitmCertificateFileName));
      await crtFile.safeWriteAsString(cert.pem);
    } catch (_) {}
  }

  static Future<MitmCertificate> regenerateCertificate() async {
    final now = DateTime.now().toUtc();
    final notAfter = now.add(const Duration(days: 365 * 15));
    final randomSuffix = (now.millisecondsSinceEpoch % 0xFFFFFF)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(6, '0');

    // Generate renewed fingerprint & subject
    final renewed = defaultCertificate.copyWith(
      subject: 'FlClash CA ($randomSuffix)',
      notBefore: now,
      notAfter: notAfter,
      fingerprint: defaultCertificate.fingerprint.replaceRange(0, 8, randomSuffix.padRight(8, '0')),
    );
    await saveCertificate(renewed);
    return renewed;
  }
}
