import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_serial_queue.dart';

typedef BrowserCookieReader = Future<String> Function(Uri uri);
typedef BrowserDataCleaner =
    Future<void> Function(Uri site, List<String> origins);

/// A saved website registration, not proof that the website is still logged in.
/// Authentication stays in the platform browser's persistent data store.
class WebsiteLoginSession {
  const WebsiteLoginSession({
    required this.site,
    required this.userAgent,
    this.origins = const [],
  });

  final Uri site;
  final String userAgent;
  final List<String> origins;

  String get host => PluginCookieManager.siteHost(site);
}

/// Website logins are shared by host, independently of installed rule names.
/// Captcha snapshots remain temporary and scoped to the rule that captured them.
class PluginCookieManager extends ChangeNotifier {
  PluginCookieManager({this.browserCookieReader, this.browserDataCleaner});
  static final PluginCookieManager instance = PluginCookieManager();

  BrowserCookieReader? browserCookieReader;
  BrowserDataCleaner? browserDataCleaner;
  final Map<String, WebsiteLoginSession> _loginSites = {};
  final AsyncSerialQueue _writes = AsyncSerialQueue();
  File? _sessionsFile;

  final Map<String, CookieJar> _jars = {};
  final Map<String, String> _userAgents = {};
  final Map<String, Uri> _captchaSites = {};

  List<WebsiteLoginSession> get savedSites {
    final sites = _loginSites.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    return List.unmodifiable(sites);
  }

  /// Only site URLs and browser fingerprints are stored here. Credentials,
  /// cookies and localStorage remain in the platform browser's data store.
  Future<void> init(Directory directory) async {
    final file = File('${directory.path}/website_sessions.json');
    _sessionsFile = file;
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      final legacy = !data.containsKey('version');
      final Iterable<dynamic> entries;
      if (legacy) {
        entries = data.values;
      } else if (data['version'] == 2 && data['sites'] is List) {
        entries = data['sites'] as List;
      } else {
        throw const FormatException('Unsupported website session format');
      }
      for (final value in entries) {
        if (value is! Map || value['site'] is! String) continue;
        final uri = Uri.tryParse(value['site'] as String);
        if (uri == null || !isWebsiteUrl(uri)) continue;
        final session = WebsiteLoginSession(
          site: _homeUrl(uri),
          userAgent: value['userAgent'] is String
              ? (value['userAgent'] as String).trim()
              : '',
          origins: _siteOrigins(
            uri,
            value['origins'] is List ? value['origins'] as List : const [],
          ),
        );
        final previous = _loginSites[session.host];
        _loginSites[session.host] =
            session.userAgent.isEmpty && previous != null ? previous : session;
      }
      if (legacy) await _writes.run(_persist);
      notifyListeners();
    } catch (error) {
      KazumiLogger().w('Unable to restore website sessions', error: error);
    }
  }

  static bool isWebsiteUrl(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  /// Normalize www without guessing a registrable domain, which could merge
  /// unrelated websites on shared hosts such as example.co.uk or user.github.io.
  static String siteHost(Uri uri) {
    var host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  static Uri _homeUrl(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: '/',
  );

  static bool isSiteHost(Uri site, Uri target) {
    if (!isWebsiteUrl(site) || !isWebsiteUrl(target)) return false;
    final host = siteHost(site);
    final targetHost = siteHost(target);
    return targetHost == host ||
        (InternetAddress.tryParse(host) == null &&
            targetHost.endsWith('.$host'));
  }

  WebsiteLoginSession? sessionFor(Uri uri) {
    WebsiteLoginSession? match;
    for (final session in _loginSites.values) {
      if (isSiteHost(session.site, uri) &&
          (match == null || session.host.length > match.host.length)) {
        match = session;
      }
    }
    return match;
  }

  Future<void> _persist() async {
    final file = _sessionsFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 2,
        'sites': [
          for (final session in savedSites)
            {
              'site': session.site.toString(),
              'userAgent': session.userAgent,
              if (session.origins.isNotEmpty) 'origins': session.origins,
            },
        ],
      }),
      flush: true,
    );
  }

  static List<String> _siteOrigins(Uri site, Iterable<dynamic> origins) {
    final result = <String>{};
    for (final origin in origins) {
      if (origin is! String) continue;
      final uri = Uri.tryParse(origin);
      if (uri != null && isSiteHost(site, uri)) result.add(uri.origin);
    }
    return List.unmodifiable(result);
  }

  Future<void> saveLoginSession(
    String siteUrl,
    String userAgent, {
    Iterable<String> origins = const [],
  }) async {
    final site = Uri.parse(siteUrl);
    if (!isWebsiteUrl(site)) throw const FormatException('无效的网站地址');
    await _writes.run(() async {
      final host = siteHost(site);
      final previous = _loginSites[host];
      _loginSites[host] = WebsiteLoginSession(
        site: _homeUrl(site),
        userAgent: userAgent.trim().isEmpty
            ? previous?.userAgent ?? ''
            : userAgent.trim(),
        origins: _siteOrigins(site, [
          if (previous != null && previous.site.origin != site.origin)
            previous.site.origin,
          ...?previous?.origins,
          ...origins,
        ]),
      );
      try {
        await _persist();
      } catch (_) {
        if (previous == null) {
          _loginSites.remove(host);
        } else {
          _loginSites[host] = previous;
        }
        rethrow;
      }
      // Never let a snapshot captured before website logout resurrect cookies.
      _clearCaptchaFor(site);
      notifyListeners();
    });
  }

  /// Clear actual browser credentials before removing the shared registration.
  Future<void> deleteAccountData(String siteUrl) async {
    final site = Uri.parse(siteUrl);
    if (!isWebsiteUrl(site)) throw const FormatException('无效的网站地址');
    await _writes.run(() async {
      final host = siteHost(site);
      final previous = _loginSites[host];
      final target = previous?.site ?? site;
      final related = {
        for (final session in _loginSites.values)
          if (isSiteHost(target, session.site)) session.host: session,
      };
      final origins = <String>{
        for (final session in related.values) ...[
          session.site.origin,
          ...session.origins,
        ],
      };
      final cleaner = browserDataCleaner;
      if (cleaner == null) throw StateError('网站账号清理功能不可用');
      await cleaner(target, origins.toList());
      // Metadata write failures must not resurrect credentials already deleted.
      _clearCaptchaFor(target);
      for (final key in related.keys) {
        _loginSites.remove(key);
      }
      try {
        await _persist();
      } catch (_) {
        _loginSites.addAll(related);
        rethrow;
      }
      notifyListeners();
    });
  }

  void _clearCaptchaFor(Uri site) {
    for (final entry in _captchaSites.entries.toList()) {
      if (isSiteHost(site, entry.value)) {
        _jars.remove(entry.key);
        _userAgents.remove(entry.key);
        _captchaSites.remove(entry.key);
      }
    }
  }

  Future<Map<String, String>> headersFor(
    String pluginName,
    String url,
    Map<String, String> headers,
  ) async {
    final uri = Uri.tryParse(url);
    final cookies = uri == null
        ? <Cookie>[]
        : await loadForRequest(pluginName, uri);
    final userAgent = userAgentFor(pluginName, url: url);
    return {
      ...headers,
      'user-agent': ?userAgent,
      if (cookies.isNotEmpty)
        'cookie': cookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; '),
    };
  }

  Future<void> saveFromWebView(
    String pluginName,
    String pageUrl,
    String cookieString, {
    String? userAgent,
  }) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || !isWebsiteUrl(uri)) return;
    _captchaSites[pluginName] = uri;
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _userAgents[pluginName] = userAgent.trim();
    }
    if (cookieString.trim().isEmpty) return;

    final jar = _jars.putIfAbsent(pluginName, () => CookieJar());
    final cookies = _parseCookieString(cookieString, uri);
    if (cookies.isEmpty) return;

    await jar.saveFromResponse(uri, cookies);
    KazumiLogger().i(
      '[PluginCookieManager] Saved ${cookies.length} cookies for $pluginName',
    );
  }

  List<Cookie> _parseCookieString(String raw, Uri uri) {
    final cookies = <Cookie>[];
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) continue;
      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      try {
        final cookie = Cookie(name, value)
          ..domain = uri.host
          ..path = '/';
        cookies.add(cookie);
      } catch (_) {}
    }
    return cookies;
  }

  Future<List<Cookie>> loadForRequest(String pluginName, Uri uri) async {
    if (!isWebsiteUrl(uri)) return <Cookie>[];
    final session = sessionFor(uri);
    final reader = browserCookieReader;
    if (session != null) {
      // Let the browser enforce each target's domain/path/expiry/secure rules,
      // including HttpOnly cookies. No credentials are copied between hosts.
      if (reader == null) return <Cookie>[];
      return _parseCookieString(await reader(uri), uri);
    }
    final jar = _jars[pluginName];
    if (jar == null) return <Cookie>[];
    return jar.loadForRequest(uri);
  }

  String? userAgentFor(String pluginName, {required String url}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !isWebsiteUrl(uri)) return null;
    final session = sessionFor(uri);
    if (session != null) {
      return session.userAgent.isEmpty ? null : session.userAgent;
    }
    final captchaSite = _captchaSites[pluginName];
    if (captchaSite == null || !isSiteHost(captchaSite, uri)) return null;
    return _userAgents[pluginName];
  }
}
