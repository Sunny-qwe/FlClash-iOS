import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'print.dart';
import 'protocol.dart';
import 'string.dart';

String? profileUrlFromQrCodes(Iterable<String?> values) {
  for (final value in values) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      continue;
    }
    if (text.isUrl || text.isShareLink) {
      return text;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !protocolSchemes.contains(uri.scheme)) {
      continue;
    }
    final url = _installConfigUrl(uri);
    if (url != null && url.isUrl) {
      return url;
    }
  }
  return null;
}

String unwrapInstallConfigUrl(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri != null) {
    if (uri.queryParameters.containsKey('url')) {
      final inner = uri.queryParameters['url']?.trim();
      if (inner != null && inner.isNotEmpty) {
        return inner;
      }
    }
  }
  return text;
}

Map<String, dynamic>? parseCustomShareLink(String link) {
  final trimmed = link.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();

  if (scheme == 'wireguard' || scheme == 'wg') {
    final server = uri.host;
    final port = uri.hasPort ? uri.port : 51820;
    final privateKey = uri.userInfo;
    final query = uri.queryParameters;
    final publicKey = query['public_key'] ?? query['publickey'] ?? query['pk'] ?? '';
    final ip = query['ip'] ?? query['address'] ?? '10.0.0.2/32';
    final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '$server:$port';
    final proxy = <String, dynamic>{
      'name': name,
      'type': 'wireguard',
      'server': server,
      'port': port,
      'private-key': privateKey,
      'public-key': publicKey,
      'ip': ip,
      'udp': true,
    };
    if (query['preshared_key'] ?? query['psk'] case final psk? when psk.isNotEmpty) {
      proxy['pre-shared-key'] = psk;
    }
    if (query['reserved'] case final reserved? when reserved.isNotEmpty) {
      final parts = reserved.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
      proxy['reserved'] = parts;
    }
    if (int.tryParse(query['mtu'] ?? '') case final mtu?) {
      proxy['mtu'] = mtu;
    }
    return proxy;
  }

  if (scheme == 'snell') {
    final server = uri.host;
    final port = uri.hasPort ? uri.port : 443;
    final psk = uri.userInfo;
    final query = uri.queryParameters;
    final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '$server:$port';
    final proxy = <String, dynamic>{
      'name': name,
      'type': 'snell',
      'server': server,
      'port': port,
      'psk': psk,
      'udp': true,
    };
    if (int.tryParse(query['version'] ?? '') case final ver?) {
      proxy['version'] = ver;
    }
    if (query['obfs'] case final obfs? when obfs.isNotEmpty) {
      proxy['obfs-opts'] = {
        'mode': obfs,
        if (query['obfs-host'] ?? query['host'] case final host? when host.isNotEmpty)
          'host': host,
      };
    }
    return proxy;
  }

  if (scheme == 'ssh') {
    final server = uri.host;
    final port = uri.hasPort ? uri.port : 22;
    final user = uri.userInfo.split(':').first;
    final pass = uri.userInfo.contains(':') ? uri.userInfo.split(':')[1] : '';
    final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '$server:$port';
    return {
      'name': name,
      'type': 'ssh',
      'server': server,
      'port': port,
      'user': user,
      if (pass.isNotEmpty) 'password': pass,
    };
  }

  return null;
}

String? _installConfigUrl(Uri uri) {
  if (uri.host != 'install-config') {
    return null;
  }
  final url = uri.queryParameters['url']?.trim();
  return url == null || url.isEmpty ? null : url;
}

class LinkManager {
  static LinkManager? _instance;
  StreamSubscription? subscription;
  Uri? _pendingUri;

  LinkManager._internal();

  @visibleForTesting
  Stream<Uri> Function() uriLinkStream = () => AppLinks().uriLinkStream;

  /// Linux argv: the gtk plugin hooks GApplication too late to see it.
  void seedInitialLink(List<String> args) {
    for (final arg in args) {
      final uri = Uri.tryParse(arg);
      if (uri != null && protocolSchemes.contains(uri.scheme)) {
        _pendingUri = uri;
        return;
      }
    }
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack,
  ) async {
    destroy();
    subscription = uriLinkStream().listen((uri) {
      _handle(uri, installConfigCallBack);
    });
    final pending = _pendingUri;
    _pendingUri = null;
    if (pending != null) {
      _handle(pending, installConfigCallBack);
    }
  }

  void _handle(Uri uri, Function(String url) installConfigCallBack) {
    commonPrint.log('onAppLink: $uri');
    final url = _installConfigUrl(uri);
    if (url != null) {
      installConfigCallBack(url);
    }
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
