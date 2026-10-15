import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_serial_queue.dart';

typedef BrowserCookieReader = Future<String> Function(Uri uri);

/// 每条规则的 Cookie 管理器
///
/// 为每条规则维护一个独立的内存 [CookieJar]，
/// 通过 [saveFromWebView] 将 WebView 捕获的 document.cookie 字符串
/// 解析后存入对应规则的 jar。规则请求执行器按需读取并组装 Cookie 请求头。
/// 验证 Cookie 通常与 User-Agent 绑定，故同时记录 WebView 的 UA，
/// 供后续 dio 请求对齐指纹。
/// 验证码快照仅在当前会话有效；网站登录从系统浏览器读取，遵循网站的过期设置。
class PluginCookieManager {
  PluginCookieManager({this.browserCookieReader});
  static final PluginCookieManager instance = PluginCookieManager();

  BrowserCookieReader? browserCookieReader;
  final Map<String, Uri> _loginSites = {};
  final AsyncSerialQueue _writes = AsyncSerialQueue();
  File? _sessionsFile;

  final Map<String, CookieJar> _jars = {};
  final Map<String, String> _userAgents = {};

  /// Only site URLs and browser fingerprints are stored here. Credentials,
  /// cookies and localStorage remain in the platform browser's data store.
  Future<void> init(Directory directory) async {
    final file = File('${directory.path}/website_sessions.json');
    _sessionsFile = file;
    try {
      if (!await file.exists()) return;
      final entries = jsonDecode(await file.readAsString()) as Map;
      for (final entry in entries.entries) {
        final value = Map<String, dynamic>.from(entry.value as Map);
        final uri = Uri.tryParse(value['site'] as String? ?? '');
        if (uri == null || !isWebsiteUrl(uri)) continue;
        _loginSites[entry.key as String] = uri;
        final ua = value['userAgent'] as String?;
        if (ua != null && ua.isNotEmpty) _userAgents[entry.key as String] = ua;
      }
    } catch (error) {
      KazumiLogger().w('Unable to restore website sessions', error: error);
    }
  }

  static bool isWebsiteUrl(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

  static bool isSiteHost(Uri site, Uri target) =>
      isWebsiteUrl(target) &&
      (target.host == site.host || target.host.endsWith('.${site.host}'));

  Future<void> saveLoginSession(
    String pluginName,
    String siteUrl,
    String userAgent,
  ) async {
    final site = Uri.parse(siteUrl);
    if (!isWebsiteUrl(site)) throw const FormatException('无效的网站地址');
    _loginSites[pluginName] = site;
    if (userAgent.trim().isNotEmpty) {
      _userAgents[pluginName] = userAgent.trim();
    }
    // Do not let an old captcha snapshot resurrect cookies after website logout.
    _jars.remove(pluginName);
    await _writes.run(() async {
      final file = _sessionsFile;
      if (file == null) return;
      await file.parent.create(recursive: true);
      final data = {
        for (final entry in _loginSites.entries)
          entry.key: {
            'site': entry.value.toString(),
            'userAgent': _userAgents[entry.key] ?? '',
          },
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    });
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
    final userAgent = userAgentFor(pluginName);
    return {
      ...headers,
      'user-agent': ?userAgent,
      if (cookies.isNotEmpty)
        'cookie': cookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; '),
    };
  }

  CookieJar _getJar(String pluginName) {
    return _jars.putIfAbsent(pluginName, () => CookieJar());
  }

  Future<void> saveFromWebView(
    String pluginName,
    String pageUrl,
    String cookieString, {
    String? userAgent,
  }) async {
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _userAgents[pluginName] = userAgent.trim();
    }
    if (cookieString.trim().isEmpty) return;
    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return;

    final jar = _getJar(pluginName);
    final cookies = _parseCookieString(cookieString, uri);
    if (cookies.isEmpty) return;

    await jar.saveFromResponse(uri, cookies);
    KazumiLogger().i(
      '[PluginCookieManager] Saved ${cookies.length} cookies for $pluginName',
    );
  }

  /// 解析字符串为 [Cookie] 列表
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
    final site = _loginSites[pluginName];
    final reader = browserCookieReader;
    if (site != null && reader != null && isSiteHost(site, uri)) {
      // Read natively for each URL, including HttpOnly cookies and their actual
      // domain/path/expiry rules. Never serialize authentication tokens ourselves.
      return _parseCookieString(await reader(uri), uri);
    }
    final jar = _jars[pluginName];
    if (jar == null) return <Cookie>[];
    return jar.loadForRequest(uri);
  }

  /// 验证时 WebView 使用的 User-Agent；未验证过的规则返回 null
  String? userAgentFor(String pluginName) => _userAgents[pluginName];
}
